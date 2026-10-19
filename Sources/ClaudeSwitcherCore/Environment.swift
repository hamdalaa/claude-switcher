import Foundation

/// The user's login shell and what kind it is (decides rc files and syntax).
public enum ShellKind: String, Sendable {
    case zsh, bash, fish, other

    public init(path: String) {
        switch (path as NSString).lastPathComponent {
        case "zsh": self = .zsh
        case "bash": self = .bash
        case "fish": self = .fish
        default: self = .other
        }
    }

    /// Prints PATH on its own marked line, joined with ':' (fish keeps PATH as a list).
    public var printPathCommand: String {
        self == .fish
            ? #"printf '\n__CS_PATH__%s\n' (string join : $PATH)"#
            : #"printf '\n__CS_PATH__%s\n' "$PATH""#
    }

    /// Extracts PATH from the output of `printPathCommand` (rc files may print noise around it).
    public static func parsePath(_ output: String) -> String? {
        output.split(separator: "\n").last { $0.hasPrefix("__CS_PATH__") }
            .map { String($0.dropFirst("__CS_PATH__".count)) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// POSIX single-quoting for /bin/sh, zsh and bash. NOT safe for fish (fish treats `\\` inside
/// single quotes as an escape) — never build fish code from untrusted text; pass it as argv.
public func shellQuote(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
}

/// The `claude` shell hook: makes plain `claude` start on the account Claude Switcher picked.
/// Falls back to the real binary if ccx is missing, so uninstalling never breaks `claude`.
public enum ShellHook {
    public static let begin = "# >>> claude-switcher >>>"
    public static let end = "# <<< claude-switcher <<<"

    /// The file the hook goes in.
    /// - zsh: `$ZDOTDIR/.zshrc` (ZDOTDIR defaults to home).
    /// - bash: the login file bash actually reads — the first existing of `.bash_profile`,
    ///   `.bash_login`, `.profile` — so creating one never shadows the others; else `.bash_profile`.
    /// - fish: its own file in `$XDG_CONFIG_HOME/fish/conf.d` (defaults to `~/.config`).
    public static func rcFile(_ kind: ShellKind, home: URL, zdotdir: String? = nil, xdgConfigHome: String? = nil,
                              exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL? {
        switch kind {
        case .zsh:
            let dir = zdotdir.flatMap { $0.hasPrefix("/") ? URL(filePath: $0, directoryHint: .isDirectory) : nil } ?? home
            return dir.appending(path: ".zshrc")
        case .bash:
            let candidates = [".bash_profile", ".bash_login", ".profile"].map { home.appending(path: $0) }
            return candidates.first(where: exists) ?? candidates[0]
        case .fish:
            let config = xdgConfigHome.flatMap { $0.hasPrefix("/") ? URL(filePath: $0, directoryHint: .isDirectory) : nil }
                ?? home.appending(path: ".config")
            return config.appending(path: "fish/conf.d/claude-switcher.fish")
        case .other:
            return nil
        }
    }

    public static func block(_ kind: ShellKind, ccxPath: String) -> String {
        block(kind, ccxExpression: shellQuote(ccxPath))
    }

    /// The default install location written as `"$HOME/.local/bin/ccx"`, so the same rc file
    /// works on every Mac a dotfiles repo is synced to.
    public static let homeCCXExpression = #""$HOME/.local/bin/ccx""#

    /// `ccxExpression` is inserted verbatim: an already-quoted path or `homeCCXExpression`.
    public static func block(_ kind: ShellKind, ccxExpression ccx: String) -> String {
        let body: String
        switch kind {
        case .fish:
            body = """
            function claude --description 'Claude Code on the account picked by Claude Switcher'
                if test -x \(ccx)
                    \(ccx) run $argv
                else
                    command claude $argv
                end
            end
            """
        default:
            body = """
            claude() { if [ -x \(ccx) ]; then \(ccx) run "$@"; else command claude "$@"; fi; }
            """
        }
        return """
        \(begin)
        # Plain `claude` follows Claude Switcher. Turn off in the app, or delete this block.
        \(body)
        \(end)
        """
    }

    public static func isInstalled(in text: String) -> Bool {
        text.contains(begin) && text.contains(end)
    }

    /// Text with our block (re)placed at the end; idempotent.
    public static func adding(_ block: String, to text: String) -> String {
        var base = removing(from: text)
        if !base.isEmpty && !base.hasSuffix("\n") { base += "\n" }
        if !base.isEmpty && !base.hasSuffix("\n\n") { base += "\n" }
        return base + block + "\n"
    }

    /// Text without our block; everything else byte-for-byte unchanged.
    public static func removing(from text: String) -> String {
        guard let stop = text.range(of: end),
              let start = text.range(of: begin, options: .backwards, range: text.startIndex..<stop.lowerBound)
        else { return text }
        var lower = start.lowerBound
        var upper = stop.upperBound
        if upper < text.endIndex, text[upper] == "\n" { upper = text.index(after: upper) }
        // Also drop the blank separator line we added before the block.
        if lower > text.startIndex, text[text.index(before: lower)] == "\n",
           text.index(before: lower) > text.startIndex,
           text[text.index(lower, offsetBy: -2)] == "\n" {
            lower = text.index(before: lower)
        }
        return String(text[..<lower] + text[upper...])
    }
}

/// Terminal apps Claude Switcher can open sessions in.
public enum TerminalApp: String, CaseIterable, Sendable, Identifiable {
    case terminal, iterm, ghostty, kitty, wezterm
    public var id: String { rawValue }

    public var bundleIdentifier: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iterm: "com.googlecode.iterm2"
        case .ghostty: "com.mitchellh.ghostty"
        case .kitty: "net.kovidgoyal.kitty"
        case .wezterm: "com.github.wez.wezterm"
        }
    }

    public var displayName: String {
        switch self {
        case .terminal: "Terminal"
        case .iterm: "iTerm2"
        case .ghostty: "Ghostty"
        case .kitty: "kitty"
        case .wezterm: "WezTerm"
        }
    }

    /// Auto choice: a third-party terminal the user installed beats the built-in one.
    public static func preferred(installed: Set<TerminalApp>) -> TerminalApp {
        [.ghostty, .iterm, .kitty, .wezterm].first(where: installed.contains) ?? .terminal
    }
}

/// How to open a terminal that runs `command` (an argv list) in `directory`, then leaves the
/// user in an interactive shell. The directory and command are passed to the shell as
/// arguments — never spliced into shell code — so odd folder names can't inject commands.
public enum TerminalLaunch: Equatable, Sendable {
    /// Run /usr/bin/open with these arguments.
    case open([String])
    /// Write `script` to an executable file and hand it to the terminal app.
    case scriptFile(script: String, app: TerminalApp)

    /// Fixed shell code run with `shell -lic <code> <arg0> <directory> <command…>`.
    /// -l -i so PATH from the user's rc files (claude, codex, node) is present.
    static func code(for kind: ShellKind) -> String {
        switch kind {
        case .fish:
            // fish: $argv = directory, command…  (no $0 slot)
            "cd -- $argv[1]; or exit 1; $argv[2..-1]; exec (status fish-path) -l"
        default:
            // sh/zsh/bash: $0 = shell path, $1 = directory, $2… = command
            #"cd -- "$1" || exit 1; shift; "$@"; exec "$0" -l"#
        }
    }

    /// The shell that runs the launch code: the user's zsh/bash/fish; anything else (tcsh, nu…)
    /// falls back to zsh so `-lic` and the code above are understood.
    public static func launchShell(for shell: String) -> String {
        ShellKind(path: shell) == .other ? "/bin/zsh" : shell
    }

    /// argv after the shell path: -lic, code, then the positional arguments.
    static func shellArguments(shell: String, command: [String], directory: String) -> [String] {
        let kind = ShellKind(path: shell)
        let positional = kind == .fish ? [directory] + command : [shell, directory] + command
        return ["-lic", code(for: kind)] + positional
    }

    public static func plan(app: TerminalApp, appPath: String, shell userShell: String,
                            command: [String], directory: String) -> TerminalLaunch {
        let shell = launchShell(for: userShell)
        let argv = [shell] + shellArguments(shell: shell, command: command, directory: directory)
        switch app {
        case .terminal, .iterm:
            // /bin/sh parses this file, so POSIX quoting of every argument is exact.
            let script = "#!/bin/sh\nexec " + argv.map(shellQuote).joined(separator: " ") + "\n"
            return .scriptFile(script: script, app: app)
        case .kitty:
            return .open(["-na", appPath, "--args"] + argv)
        case .ghostty:
            return .open(["-na", appPath, "--args", "-e"] + argv)
        case .wezterm:
            return .open(["-na", appPath, "--args", "start", "--"] + argv)
        }
    }
}
