import Foundation
import Testing
@testable import ClaudeSwitcherCore

private struct Fixture {
    let root: URL
    let home: URL
    let bundled: URL

    init(bundledText: String = "#!/bin/sh\n# ccx-managed-by: claude-switcher\necho v1\n") throws {
        root = FileManager.default.temporaryDirectory.appending(path: "inst-\(UUID().uuidString)")
        home = root.appending(path: "home")
        bundled = root.appending(path: "ccx")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try bundledText.write(to: bundled, atomically: true, encoding: .utf8)
    }

    func installer(shell: String = "/bin/zsh") -> Installer {
        Installer(home: home, shell: shell, bundledCLI: bundled)
    }

    func read(_ path: String) throws -> String {
        try String(contentsOf: home.appending(path: path), encoding: .utf8)
    }
}

@Test func installsCLIExecutable() throws {
    let f = try Fixture()
    let installer = f.installer()
    #expect(installer.cliState() == .missing)
    try installer.installCLI()
    #expect(installer.cliState() == .managed(upToDate: true))
    #expect(FileManager.default.isExecutableFile(atPath: installer.cliURL.path))
}

@Test func updatesOnlyManagedCLI() throws {
    let f = try Fixture()
    let installer = f.installer()
    try installer.installCLI()
    try "#!/bin/sh\n# ccx-managed-by: claude-switcher\necho v2\n".write(to: f.bundled, atomically: true, encoding: .utf8)
    #expect(installer.cliState() == .managed(upToDate: false))
    #expect(installer.updateCLIIfManaged())
    #expect(try f.read(".local/bin/ccx").contains("v2"))
}

@Test func neverTouchesForeignCLI() throws {
    let f = try Fixture()
    let installer = f.installer()
    try FileManager.default.createDirectory(at: installer.cliURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\necho someone else's ccx\n".write(to: installer.cliURL, atomically: true, encoding: .utf8)
    #expect(installer.cliState() == .foreign)
    #expect(throws: Installer.Failure.foreignCLI) { try installer.installCLI() }
    #expect(throws: Installer.Failure.foreignCLI) { try installer.setHook(true) }
    #expect(!installer.updateCLIIfManaged())
    try installer.removeCLI()
    #expect(try f.read(".local/bin/ccx").contains("someone else"))
}

@Test func symlinkedCLIIsForeign() throws {
    let f = try Fixture()
    let installer = f.installer()
    try FileManager.default.createDirectory(at: installer.cliURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: installer.cliURL, withDestinationURL: f.bundled)
    #expect(installer.cliState() == .foreign)
}

@Test func zshHookRoundTripWithBackup() throws {
    let f = try Fixture()
    let original = "export EDITOR=vim\n"
    try original.write(to: f.home.appending(path: ".zshrc"), atomically: true, encoding: .utf8)
    let installer = f.installer()

    try installer.setHook(true)
    #expect(installer.hookInstalled())
    #expect(installer.cliState() == .managed(upToDate: true))
    #expect(try f.read(".zshrc").contains("ccx-managed") == false)
    #expect(try f.read(".zshrc").contains(ShellHook.begin))
    #expect(try f.read(".zshrc.before-claude-switcher") == original)

    try installer.setHook(true)   // idempotent
    #expect(try f.read(".zshrc").components(separatedBy: ShellHook.begin).count == 2)

    try installer.setHook(false)
    #expect(!installer.hookInstalled())
    #expect(try f.read(".zshrc") == original)
}

@Test func hookWritesThroughSymlinkedRc() throws {
    let f = try Fixture()
    let real = f.root.appending(path: "dotfiles-zshrc")
    try "alias g=git\n".write(to: real, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: f.home.appending(path: ".zshrc"), withDestinationURL: real)
    try f.installer().setHook(true)
    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: f.home.appending(path: ".zshrc").path)) != nil)
    #expect(try String(contentsOf: real, encoding: .utf8).contains(ShellHook.begin))
}

@Test func bashUsesBashProfileAndCreatesIt() throws {
    let f = try Fixture()
    let installer = f.installer(shell: "/bin/bash")
    try installer.setHook(true)
    #expect(try f.read(".bash_profile").contains("claude()"))
    try installer.setHook(false)
    #expect(try f.read(".bash_profile") == "")
}

@Test func fishUsesItsOwnFile() throws {
    let f = try Fixture()
    let installer = f.installer(shell: "/opt/homebrew/bin/fish")
    try installer.setHook(true)
    #expect(try f.read(".config/fish/conf.d/claude-switcher.fish").contains("function claude"))
    try installer.setHook(false)
    #expect(!FileManager.default.fileExists(atPath: f.home.appending(path: ".config/fish/conf.d/claude-switcher.fish").path))
}

@Test func unsupportedShell() throws {
    let f = try Fixture()
    #expect(throws: Installer.Failure.unsupportedShell("/bin/tcsh")) { try f.installer(shell: "/bin/tcsh").setHook(true) }
}

@Test func missingBundledCLI() throws {
    let f = try Fixture()
    let installer = Installer(home: f.home, shell: "/bin/zsh", bundledCLI: nil)
    #expect(throws: Installer.Failure.noBundledCLI) { try installer.installCLI() }
}

/// Real end-to-end: the installed hook in a real zsh runs the installed real ccx.
@Test func installedHookRunsRealCcx() throws {
    let repoCCX = URL(filePath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appending(path: "cli/ccx")
    let f = try Fixture()
    let installer = Installer(home: f.home, shell: "/bin/zsh", bundledCLI: repoCCX)
    try installer.setHook(true)
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(filePath: "/bin/zsh")
    process.arguments = ["-c", "source ~/.zshrc; claude --version-of-ccx-test 2>&1; ccx_status=$?; \(shellQuote(installer.cliURL.path)) version"]
    process.environment = ["HOME": f.home.path, "PATH": "/usr/bin:/bin"]
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(out.contains("Claude Code isn't installed"))   // hook → ccx run → explains missing claude
    #expect(out.contains("ccx 1.1.1"))
}

@Test func refusesToRewriteNonUTF8Rc() throws {
    let f = try Fixture()
    let rc = f.home.appending(path: ".zshrc")
    let bytes = Data("export NAME=caf".utf8) + Data([0xE9]) + Data("\n".utf8)   // Latin-1 é
    try bytes.write(to: rc)
    #expect(throws: Installer.Failure.unreadableRcFile(rc.path)) { try f.installer().setHook(true) }
    #expect(try Data(contentsOf: rc) == bytes)
}

@Test func bashPrefersExistingProfile() throws {
    let f = try Fixture()
    try "export PATH=/opt/x:$PATH\n".write(to: f.home.appending(path: ".profile"), atomically: true, encoding: .utf8)
    try f.installer(shell: "/bin/bash").setHook(true)
    #expect(!FileManager.default.fileExists(atPath: f.home.appending(path: ".bash_profile").path))
    #expect(try f.read(".profile").contains("claude()"))
}

@Test func keepsRcPermissions() throws {
    let f = try Fixture()
    let rc = f.home.appending(path: ".zshrc")
    try "x\n".write(to: rc, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: rc.path)
    try f.installer().setHook(true)
    let mode = try FileManager.default.attributesOfItem(atPath: rc.path)[.posixPermissions] as? Int
    #expect(mode == 0o600)
}

@Test func zdotdirIsHonoured() throws {
    let f = try Fixture()
    let zdot = f.home.appending(path: ".config/zsh")
    let installer = Installer(home: f.home, shell: "/bin/zsh", bundledCLI: f.bundled, zdotdir: zdot.path)
    try installer.setHook(true)
    #expect(try String(contentsOf: zdot.appending(path: ".zshrc"), encoding: .utf8).contains(ShellHook.begin))
    #expect(!FileManager.default.fileExists(atPath: f.home.appending(path: ".zshrc").path))
}
