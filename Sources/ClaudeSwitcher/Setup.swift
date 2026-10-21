import ClaudeSwitcherCore
import Foundation

/// The app's view of `Installer`: this user's home, login shell, bundled ccx, and — once the
/// login shell has been probed — ZDOTDIR / XDG_CONFIG_HOME so the hook lands where the shell reads.
enum Setup {
    nonisolated(unsafe) static var shellInfo: System.ShellInfo?

    static var installer: Installer {
        Installer(home: System.home, shell: System.loginShell, bundledCLI: System.bundledCCX,
                  zdotdir: shellInfo?.zdotdir, xdgConfigHome: shellInfo?.xdgConfigHome)
    }

    typealias CLIState = Installer.CLIState
    static var hookFile: URL? { installer.hookFile }
    static func cliState() -> CLIState { installer.cliState() }
    static func installCLI() throws { try installer.installCLI() }
    static func removeCLI() throws { try installer.removeCLI() }
    @discardableResult static func updateCLIIfManaged() -> Bool { installer.updateCLIIfManaged() }
    static func hookInstalled() -> Bool { installer.hookInstalled() }
    static func setHook(_ enabled: Bool) throws { try installer.setHook(enabled) }
}
