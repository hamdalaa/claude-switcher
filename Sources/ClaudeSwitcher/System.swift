import AppKit
import ClaudeSwitcherCore
import Darwin
import os

/// Facts about this Mac the app needs: login shell, the PATH the user's shell sets up
/// (claude/codex/node usually live there), and where the bundled `ccx` script is.
enum System {
    static let subsystem = Bundle.main.bundleIdentifier ?? "io.github.hamdalaa.ClaudeSwitcher"
    private static let log = Logger(subsystem: subsystem, category: "system")

    static let home = Paths.defaultHome

    /// The account's login shell from the user database (not $SHELL, which apps may not get).
    static let loginShell: String = {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }()

    static var shellKind: ShellKind { ShellKind(path: loginShell) }

    /// Our environment minus Claude Code session markers (CLAUDECODE, CLAUDE_CODE_CHILD_SESSION, …).
    /// If the app was started from inside a Claude session, passing these on would make new
    /// sessions think they're children and turn transcript saving off.
    static func cleanEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        env.filter { !$0.key.hasPrefix("CLAUDE") }
    }

    /// The bundled ccx: Contents/Resources/ccx in the app; cli/ccx in a source checkout.
    static let bundledCCX: URL? = {
        if let url = Bundle.main.url(forResource: "ccx", withExtension: nil) { return url }
        #if DEBUG
        var dir = Bundle.main.executableURL?.deletingLastPathComponent()
        for _ in 0..<6 {
            guard let current = dir else { break }
            let candidate = current.appending(path: "cli/ccx")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            dir = current.deletingLastPathComponent()
        }
        #endif
        return nil
    }()

    // MARK: Login-shell environment

    struct ShellInfo: Sendable {
        let path: String
        let zdotdir: String?
        let xdgConfigHome: String?
    }

    private static let infoCache = ShellInfoCache()
    static let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:\(home.path)/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// PATH, ZDOTDIR and XDG_CONFIG_HOME as the user's interactive login shell sets them up.
    /// Cached after the first success; a failed probe falls back without caching, so it's retried.
    static func shellInfo() async -> ShellInfo {
        if let cached = await infoCache.value { return cached }
        let kind = shellKind
        let shell = TerminalLaunch.launchShell(for: loginShell)
        let script = kind == .fish
            ? #"printf '\n__CS_PATH__%s\n__CS_ZDOTDIR__\n__CS_XDG__%s\n' (string join : $PATH) "$XDG_CONFIG_HOME""#
            : #"printf '\n__CS_PATH__%s\n__CS_ZDOTDIR__%s\n__CS_XDG__%s\n' "$PATH" "${ZDOTDIR:-}" "${XDG_CONFIG_HOME:-}""#
        let result = await run(shell, ["-lic", script], environment: cleanEnvironment(), timeout: 10)
        func value(_ marker: String) -> String? {
            result.output.split(separator: "\n").last { $0.hasPrefix(marker) }
                .map { String($0.dropFirst(marker.count)) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let path = value("__CS_PATH__") else {
            log.notice("couldn't read PATH from \(shell, privacy: .public) (status \(result.status)); using fallback")
            return ShellInfo(path: fallbackPath, zdotdir: nil, xdgConfigHome: nil)
        }
        let info = ShellInfo(path: path, zdotdir: value("__CS_ZDOTDIR__"), xdgConfigHome: value("__CS_XDG__"))
        await infoCache.store(info)
        return info
    }

    static func loginPath() async -> String { await shellInfo().path }

    /// Clean environment with the user's PATH, for running claude / codex / ccx.
    static func toolEnvironment(extra: [String: String] = [:]) async -> [String: String] {
        var env = cleanEnvironment()
        env["PATH"] = await loginPath()
        env.merge(extra) { _, new in new }
        return env
    }

    /// First executable named `tool` on the user's PATH.
    static func which(_ tool: String) async -> String? {
        await loginPath().split(separator: ":")
            .map { "\($0)/\(tool)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: Processes

    struct Result: Sendable {
        let status: Int32
        let output: String
    }

    /// Runs a process with stdin closed and a hard timeout. Returns when the process exits —
    /// not at pipe EOF, which a background grandchild (e.g. an agent started from .zshrc) can
    /// hold open forever. Interactive shells ignore SIGTERM, so a timeout escalates to SIGKILL.
    static func run(_ executable: String, _ args: [String], environment: [String: String],
                    directory: URL? = nil, timeout: TimeInterval = 30) async -> Result {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let output = OutputBuffer()
            process.executableURL = URL(filePath: executable)
            process.arguments = args
            process.environment = environment
            if let directory { process.currentDirectoryURL = directory }
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe
            process.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty { handle.readabilityHandler = nil } else { output.append(chunk) }
            }
            process.terminationHandler = { finished in
                // Let in-flight output land, then stop reading regardless of EOF.
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    try? pipe.fileHandleForReading.close()
                    if output.finish() {
                        continuation.resume(returning: Result(status: finished.terminationStatus, output: output.text))
                    }
                }
            }
            do { try process.run() } catch {
                if output.finish() { continuation.resume(returning: Result(status: -1, output: error.localizedDescription)) }
                return
            }
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    if process.isRunning { kill(pid, SIGKILL) }
                }
            }
        }
    }

    static func installedTerminals() -> Set<TerminalApp> {
        Set(TerminalApp.allCases.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier) != nil })
    }
}

private actor ShellInfoCache {
    private(set) var value: System.ShellInfo?
    func store(_ info: System.ShellInfo) { value = info }
}

/// Thread-safe output accumulator that also guarantees a single continuation resume.
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var finished = false

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        if !finished, data.count < 4_000_000 { data.append(chunk) }
    }

    /// True exactly once.
    func finish() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if finished { return false }
        finished = true
        return true
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
