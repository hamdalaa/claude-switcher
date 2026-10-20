import AppKit
import ClaudeSwitcherCore
import os

/// Opens terminal sessions (Claude Code via the bundled ccx, or Codex) and per-account claude.ai windows.
enum Launcher {
    private static let log = Logger(subsystem: System.subsystem, category: "launch")
    private static let chromiumBrowsers = ["com.google.Chrome", "com.brave.browser", "com.microsoft.edgemac",
                                           "org.chromium.Chromium", "com.vivaldi.Vivaldi"]
    static let webURL = "https://claude.ai/new"

    /// `arguments` go to claude, e.g. ["--resume", sessionID] to continue a conversation.
    static func session(_ account: Account, in directory: String, terminal: TerminalApp, arguments: [String] = []) throws {
        try openTerminal(running: [try ccx(), account.rawValue] + arguments, in: directory, terminal: terminal)
    }

    /// Checks shared state and active processes before loading the saved conversation.
    static func resume(_ session: RecentSession, on account: Account, terminal: TerminalApp) throws {
        try openTerminal(running: [try ccx(), "resume", account.rawValue, session.id],
                         in: session.directory, terminal: terminal)
    }

    /// `brew upgrade --cask claude-switcher` in a terminal.
    static func brewUpgrade(terminal: TerminalApp) throws {
        try openTerminal(running: ["brew", "upgrade", "--cask", "claude-switcher"], in: System.home.path, terminal: terminal)
    }

    /// Signs out and removes account B–D via the bundled `ccx remove`.
    static func removeAccount(_ account: Account) async throws {
        guard let ccx = System.bundledCCX else { throw Installer.Failure.noBundledCLI }
        let result = await System.run("/bin/bash", [ccx.path, "remove", account.rawValue],
                                      environment: await System.toolEnvironment())
        guard result.status == 0 else { throw LaunchError.failed(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    static func signIn(_ account: Account, terminal: TerminalApp) throws {
        try openTerminal(running: [try ccx(), "login", account.rawValue], in: System.home.path, terminal: terminal)
    }

    static func codex(in directory: String, terminal: TerminalApp) throws {
        try openTerminal(running: ["codex"], in: directory, terminal: terminal)
    }

    /// `ccx sync` in the background.
    static func sync() async throws {
        guard let ccx = System.bundledCCX else { throw Installer.Failure.noBundledCLI }
        let result = await System.run("/bin/bash", [ccx.path, "sync"], environment: await System.toolEnvironment())
        guard result.status == 0 else { throw LaunchError.failed(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// claude.ai in a browser window that belongs to this account alone: a Chromium instance with
    /// its own profile folder (~/.claude-accounts/web/<a|b>). Sign in once per account; it stays
    /// signed in, both can be open at once, and the everyday browser profile is never touched.
    static func web(_ account: Account, paths: Paths = Paths()) throws {
        guard let browser = chromiumBrowsers.lazy
            .compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first
        else { throw LaunchError.failed("claude.ai per account needs Chrome, Brave, Edge, Chromium or Vivaldi") }
        let profile = paths.stateRoot.appending(path: "web/\(account.rawValue)")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        log.info("web \(account.rawValue, privacy: .public) via \(browser.lastPathComponent, privacy: .public)")
        try open(["-na", browser.path, "--args", "--user-data-dir=\(profile.path)",
                  "--no-first-run", "--no-default-browser-check", "--app=\(webURL)"])
    }

    private static func ccx() throws -> String {
        guard let url = System.bundledCCX else { throw Installer.Failure.noBundledCLI }
        return url.path
    }

    private static let scriptPrefix = "claude-switcher-"

    /// Launch scripts are deleted shortly after use; this sweeps any left by a crash or quit.
    static func removeStaleScripts() {
        let dir = FileManager.default.temporaryDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(scriptPrefix) && file.pathExtension == "command" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func openTerminal(running command: [String], in directory: String, terminal: TerminalApp) throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleIdentifier) else {
            throw LaunchError.failed("\(terminal.displayName) isn't installed — pick another terminal in Settings")
        }
        log.info("\(terminal.rawValue, privacy: .public): \(command.joined(separator: " "), privacy: .public)")
        switch TerminalLaunch.plan(app: terminal, appPath: appURL.path, shell: System.loginShell,
                                   command: command, directory: directory) {
        case .open(let args):
            try open(args)
        case .scriptFile(let script, let app):
            let file = FileManager.default.temporaryDirectory
                .appending(path: "\(scriptPrefix)\(UUID().uuidString).command")
            try Data(script.utf8).write(to: file, options: [.atomic, .withoutOverwriting])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            // The terminal reads the script when it starts; remove it shortly after.
            DispatchQueue.global().asyncAfter(deadline: .now() + 60) { try? FileManager.default.removeItem(at: file) }
            if app == .iterm {
                // iTerm2 runs commands through AppleScript (asks for Automation permission once).
                let source = """
                tell application "iTerm"
                    activate
                    create window with default profile command "/bin/sh " & quoted form of "\(appleScriptEscaped(file.path))"
                end tell
                """
                var error: NSDictionary?
                NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error { throw LaunchError.failed("iTerm2: \(error[NSAppleScript.errorMessage] ?? "couldn't open a window")") }
            } else {
                try open(["-a", appURL.path, file.path])
            }
        }
    }

    /// Escapes text for an AppleScript string literal.
    static func appleScriptEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func open(_ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/open")
        process.environment = System.cleanEnvironment()
        process.arguments = args
        try process.run()
    }
}

enum LaunchError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}
