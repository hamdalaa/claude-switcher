import ClaudeSwitcherCore
import Foundation

/// Scriptable setup without the UI:
///   ClaudeSwitcher --install-hook | --remove-hook | --install-cli | --remove-cli
enum CommandLineSetup {
    static func runIfRequested() {
        let actions: [String: () throws -> String] = [
            "--install-hook": { try Setup.setHook(true); return "claude hook on in \(Setup.hookFile?.path ?? "?")" },
            "--remove-hook": { try Setup.setHook(false); return "claude hook off" },
            "--install-cli": { try Setup.installCLI(); return "ccx installed at \(Setup.installer.cliURL.path)" },
            "--remove-cli": { try Setup.removeCLI(); return "ccx removed" },
        ]
        guard let flag = CommandLine.arguments.first(where: { actions[$0] != nil }), let action = actions[flag] else { return }
        // Probe the login shell first so ZDOTDIR / XDG_CONFIG_HOME are respected.
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            Setup.shellInfo = await System.shellInfo()
            done.signal()
        }
        done.wait()
        do {
            print(try action())
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
