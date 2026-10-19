import Foundation
import Testing
@testable import ClaudeSwitcherCore

@Test func shellKindFromPath() {
    #expect(ShellKind(path: "/bin/zsh") == .zsh)
    #expect(ShellKind(path: "/opt/homebrew/bin/bash") == .bash)
    #expect(ShellKind(path: "/opt/homebrew/bin/fish") == .fish)
    #expect(ShellKind(path: "/bin/tcsh") == .other)
}

@Test func parsesPathThroughRcNoise() {
    let output = "Welcome!\n\u{1B}[0m\n__CS_PATH__/opt/homebrew/bin:/usr/bin\n"
    #expect(ShellKind.parsePath(output) == "/opt/homebrew/bin:/usr/bin")
    #expect(ShellKind.parsePath("nothing here") == nil)
    #expect(ShellKind.parsePath("__CS_PATH__\n") == nil)
}

@Test func quotesForShell() {
    #expect(shellQuote("plain") == "'plain'")
    #expect(shellQuote("/Applications/Claude Switcher.app") == "'/Applications/Claude Switcher.app'")
    #expect(shellQuote("it's") == #"'it'\''s'"#)
}

@Test func quotingSurvivesARealShell() throws {
    let tricky = #"/tmp/a b/it's "q" $HOME `x`"#
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(filePath: "/bin/sh")
    process.arguments = ["-c", "printf %s \(shellQuote(tricky))"]
    process.standardOutput = pipe
    try process.run()
    process.waitUntilExit()
    #expect(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) == tricky)
}

@Test func hookRcFiles() {
    let home = URL(filePath: "/Users/x")
    let none: (URL) -> Bool = { _ in false }
    #expect(ShellHook.rcFile(.zsh, home: home, exists: none)?.path == "/Users/x/.zshrc")
    #expect(ShellHook.rcFile(.zsh, home: home, zdotdir: "/Users/x/.config/zsh", exists: none)?.path == "/Users/x/.config/zsh/.zshrc")
    #expect(ShellHook.rcFile(.bash, home: home, exists: none)?.path == "/Users/x/.bash_profile")
    #expect(ShellHook.rcFile(.bash, home: home, exists: { $0.lastPathComponent == ".profile" })?.path == "/Users/x/.profile")
    #expect(ShellHook.rcFile(.bash, home: home, exists: { $0.lastPathComponent != ".bash_profile" })?.path == "/Users/x/.bash_login")
    #expect(ShellHook.rcFile(.fish, home: home, exists: none)?.path == "/Users/x/.config/fish/conf.d/claude-switcher.fish")
    #expect(ShellHook.rcFile(.fish, home: home, xdgConfigHome: "/cfg", exists: none)?.path == "/cfg/fish/conf.d/claude-switcher.fish")
    #expect(ShellHook.rcFile(.other, home: home) == nil)
}

@Test func orphanBeginNeverSwallowsUserLines() {
    let block = ShellHook.block(.zsh, ccxPath: "/c")
    let broken = "keep1\n\(ShellHook.begin)\nkeep2\n"          // a stray begin marker, no end
    let added = ShellHook.adding(block, to: broken)
    let removed = ShellHook.removing(from: added)
    #expect(removed.contains("keep1"))
    #expect(removed.contains("keep2"))
    #expect(!ShellHook.isInstalled(in: removed) || !removed.contains(ShellHook.end))
}

@Test func hookAddIsIdempotentAndRemoveRestoresOriginal() {
    let original = "export PATH=$HOME/bin:$PATH\nalias ll='ls -l'\n"
    let block = ShellHook.block(.zsh, ccxPath: "/Users/x/.local/bin/ccx")
    let once = ShellHook.adding(block, to: original)
    let twice = ShellHook.adding(block, to: once)
    #expect(once == twice)
    #expect(ShellHook.isInstalled(in: once))
    #expect(once.hasPrefix(original))
    #expect(ShellHook.removing(from: once) == original)
    #expect(!ShellHook.isInstalled(in: original))
    #expect(ShellHook.removing(from: original) == original)
}

@Test func hookOnEmptyAndUnterminatedFiles() {
    let block = ShellHook.block(.bash, ccxPath: "/c")
    #expect(ShellHook.adding(block, to: "") == block + "\n")
    #expect(ShellHook.removing(from: ShellHook.adding(block, to: "")) == "")
    let noNewline = "echo hi"
    #expect(ShellHook.removing(from: ShellHook.adding(block, to: noNewline)) == "echo hi\n")
}

@Test func hookKeepsTextAfterBlock() {
    let block = ShellHook.block(.zsh, ccxPath: "/c")
    let text = "before\n\n" + block + "\nafter\n"
    #expect(ShellHook.removing(from: text) == "before\nafter\n")
}

/// Runs the generated hook in real zsh and bash with a stub ccx.
@Test(arguments: [ShellKind.zsh, .bash])
func hookWorksInRealShell(kind: ShellKind) throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "hook-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let ccx = dir.appending(path: "c c x")
    try "#!/bin/sh\necho \"ccx $*\"\n".write(to: ccx, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ccx.path)
    let hook = ShellHook.block(kind, ccxPath: ccx.path)

    func run(_ script: String) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: kind == .zsh ? "/bin/zsh" : "/bin/bash")
        process.arguments = ["-c", hook + "\n" + script]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
    #expect(try run(#"claude -c "two words""#) == "ccx run -c two words\n")
    try FileManager.default.removeItem(at: ccx)
    // ccx gone → falls back to the real `claude` (here: "command not found", not ccx).
    #expect(try !run("claude --version").contains("ccx"))
}

@Test func preferredTerminal() {
    #expect(TerminalApp.preferred(installed: []) == .terminal)
    #expect(TerminalApp.preferred(installed: [.terminal, .kitty]) == .kitty)
    #expect(TerminalApp.preferred(installed: [.kitty, .ghostty, .iterm]) == .ghostty)
}

@Test func terminalLaunchPlans() {
    let kitty = TerminalLaunch.plan(app: .kitty, appPath: "/Applications/kitty.app", shell: "/bin/zsh",
                                    command: ["/x/ccx", "a"], directory: "/Users/me/my proj")
    #expect(kitty == .open(["-na", "/Applications/kitty.app", "--args", "/bin/zsh", "-lic",
                            #"cd -- "$1" || exit 1; shift; "$@"; exec "$0" -l"#,
                            "/bin/zsh", "/Users/me/my proj", "/x/ccx", "a"]))

    let ghostty = TerminalLaunch.plan(app: .ghostty, appPath: "/G.app", shell: "/opt/homebrew/bin/fish", command: ["codex"], directory: "/d")
    #expect(ghostty == .open(["-na", "/G.app", "--args", "-e", "/opt/homebrew/bin/fish", "-lic",
                              "cd -- $argv[1]; or exit 1; $argv[2..-1]; exec (status fish-path) -l", "/d", "codex"]))

    let wez = TerminalLaunch.plan(app: .wezterm, appPath: "/W.app", shell: "/bin/tcsh", command: ["codex"], directory: "/d")
    #expect(wez == .open(["-na", "/W.app", "--args", "start", "--", "/bin/zsh", "-lic",
                          #"cd -- "$1" || exit 1; shift; "$@"; exec "$0" -l"#, "/bin/zsh", "/d", "codex"]))

    guard case .scriptFile(let script, let app) = TerminalLaunch.plan(
        app: .terminal, appPath: "/T.app", shell: "/bin/zsh", command: ["/x/ccx", "b"], directory: "/d")
    else { Issue.record("expected script file"); return }
    #expect(app == .terminal)
    #expect(script.hasPrefix("#!/bin/sh\nexec '/bin/zsh' '-lic' "))
}

/// Runs the real launch script with hostile folder names: it must cd there and run the
/// command as argv, never execute anything from the name.
@Test(arguments: [#"it's"#, #"\'; touch PWNED; #"#, "-rf", #"$(touch PWNED)"#, "`touch PWNED`", "a\"b"])
func terminalScriptIsInjectionProof(name: String) throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "inj-\(UUID().uuidString)")
    let dir = root.appending(path: name)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // Stand-in for the user's shell: /bin/sh doesn't take -l/-i the same way, so use bash.
    guard case .scriptFile(let script, _) = TerminalLaunch.plan(
        app: .terminal, appPath: "", shell: "/bin/bash", command: ["/bin/pwd"], directory: dir.path)
    else { Issue.record("expected script file"); return }
    // Replace the trailing interactive shell with a plain exit so the test terminates.
    let runnable = script.replacingOccurrences(of: #"exec "$0" -l"#, with: "exit 0")
    let file = root.appending(path: "run.command")
    try runnable.write(to: file, atomically: true, encoding: .utf8)
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(filePath: "/bin/sh")
    process.arguments = [file.path]
    process.currentDirectoryURL = root
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    process.environment = ["HOME": root.path, "PATH": "/usr/bin:/bin"]
    try process.run()
    process.waitUntilExit()
    let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(out.trimmingCharacters(in: .newlines).hasSuffix(name))
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "PWNED").path))
    #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "PWNED").path))
}
