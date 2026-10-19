import Foundation

/// Installs the `ccx` command and the `claude` shell hook into a home folder.
/// Never overwrites a ccx it didn't install; backs up an rc file once before first editing it.
public struct Installer: Sendable {
    public static let marker = "ccx-managed-by: claude-switcher"

    public enum CLIState: Equatable, Sendable {
        case missing
        case managed(upToDate: Bool)
        /// Something else lives at ~/.local/bin/ccx; we never overwrite it.
        case foreign
    }

    public enum Failure: LocalizedError, Equatable {
        case noBundledCLI
        case foreignCLI
        case unsupportedShell(String)
        case unreadableRcFile(String)

        public var errorDescription: String? {
            switch self {
            case .noBundledCLI: "The ccx script is missing from the app"
            case .foreignCLI: "~/.local/bin/ccx already exists and wasn't installed by Claude Switcher — move it away first"
            case .unsupportedShell(let shell): "The claude hook supports zsh, bash and fish (your shell: \(shell))"
            case .unreadableRcFile(let path): "Couldn't safely read \(path) (permissions or not UTF-8) — left it untouched"
            }
        }
    }

    public let home: URL
    public let shell: String
    public let bundledCLI: URL?
    /// From the user's login shell, when it sets them (zsh ZDOTDIR, XDG_CONFIG_HOME for fish).
    public let zdotdir: String?
    public let xdgConfigHome: String?

    public init(home: URL, shell: String, bundledCLI: URL?, zdotdir: String? = nil, xdgConfigHome: String? = nil) {
        self.home = home
        self.shell = shell
        self.bundledCLI = bundledCLI
        self.zdotdir = zdotdir
        self.xdgConfigHome = xdgConfigHome
    }

    public var cliURL: URL { home.appending(path: ".local/bin/ccx") }
    public var kind: ShellKind { ShellKind(path: shell) }
    public var hookFile: URL? { ShellHook.rcFile(kind, home: home, zdotdir: zdotdir, xdgConfigHome: xdgConfigHome) }
    public static let backupExtension = "before-claude-switcher"

    // MARK: ccx command

    public func cliState() -> CLIState {
        let fm = FileManager.default
        let isLink = (try? fm.destinationOfSymbolicLink(atPath: cliURL.path)) != nil
        guard isLink || fm.fileExists(atPath: cliURL.path) else { return .missing }
        guard let installed = try? String(contentsOf: cliURL.resolvingSymlinksInPath(), encoding: .utf8),
              installed.contains(Self.marker), !isLink
        else { return .foreign }
        let bundled = bundledCLI.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        return .managed(upToDate: bundled == nil || bundled == installed)
    }

    public func installCLI() throws {
        guard let bundledCLI else { throw Failure.noBundledCLI }
        if cliState() == .foreign { throw Failure.foreignCLI }
        let fm = FileManager.default
        try fm.createDirectory(at: cliURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: bundledCLI).write(to: cliURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cliURL.path)
    }

    /// After an app update: refresh our own copy; never touch a foreign one.
    @discardableResult
    public func updateCLIIfManaged() -> Bool {
        guard case .managed(upToDate: false) = cliState() else { return false }
        return (try? installCLI()) != nil
    }

    public func removeCLI() throws {
        guard case .managed = cliState() else { return }
        try FileManager.default.removeItem(at: cliURL)
    }

    // MARK: claude hook

    public func hookInstalled() -> Bool {
        guard let file = hookFile, let text = try? readRc(file) else { return false }
        return ShellHook.isInstalled(in: text)
    }

    /// "" only when the file doesn't exist. Any other failure throws — we must never mistake an
    /// unreadable or non-UTF-8 rc file for an empty one and overwrite it.
    func readRc(_ file: URL) throws -> String {
        let fm = FileManager.default
        let target = file.resolvingSymlinksInPath()
        guard fm.fileExists(atPath: target.path) else { return "" }
        guard let data = fm.contents(atPath: target.path), let text = String(data: data, encoding: .utf8) else {
            throw Failure.unreadableRcFile(file.path)
        }
        return text
    }

    /// Adds or removes the hook. Enabling also installs the ccx command it calls.
    public func setHook(_ enabled: Bool) throws {
        guard let file = hookFile else { throw Failure.unsupportedShell(shell) }
        let fm = FileManager.default
        let current = try readRc(file)
        let updated: String
        if enabled {
            if cliState() == .foreign { throw Failure.foreignCLI }
            try installCLI()
            updated = ShellHook.adding(ShellHook.block(kind, ccxExpression: ShellHook.homeCCXExpression), to: current)
        } else {
            updated = ShellHook.removing(from: current)
        }
        guard updated != current else { return }

        if kind == .fish {   // conf.d file is ours alone
            if enabled {
                try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try updated.write(to: file, atomically: true, encoding: .utf8)
            } else {
                try? fm.removeItem(at: file)
            }
            return
        }
        // Write through symlinks (dotfile managers link ~/.zshrc into a repo).
        let target = file.resolvingSymlinksInPath()
        var permissions: Any?
        if fm.fileExists(atPath: target.path) {
            permissions = try? fm.attributesOfItem(atPath: target.path)[.posixPermissions]
            let backup = file.appendingPathExtension(Self.backupExtension)
            if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: target, to: backup) }
        } else {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try updated.write(to: target, atomically: true, encoding: .utf8)
        if let permissions {   // an atomic write would otherwise reset e.g. 0600 to the default
            try? fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
        }
    }
}
