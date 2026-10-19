import ClaudeSwitcherCore
import SwiftUI

/// Everything configurable, in one native menu so the panel stays about the accounts.
struct SettingsMenu: View {
    let model: SwitcherModel

    var body: some View {
        Menu {
            Picker("Terminal", selection: Binding(
                get: { model.terminalChoice.flatMap { model.installedTerminals.contains($0) ? $0.rawValue : nil } ?? "auto" },
                set: { model.setTerminal(TerminalApp(rawValue: $0)) }
            )) {
                Text("Automatic (\(TerminalApp.preferred(installed: model.installedTerminals).displayName))").tag("auto")
                Divider()
                ForEach(TerminalApp.allCases.filter { model.installedTerminals.contains($0) }) { app in
                    Text(app.displayName).tag(app.rawValue)
                }
            }

            Section("Terminal Integration") {
                Toggle("Plain `claude` Follows the Switch", isOn: Binding(
                    get: { model.hookInstalled },
                    set: { model.setHook($0) }
                ))
                .disabled(!model.shellSupportsHook)
                Toggle(cliTitle, isOn: Binding(
                    get: { if case .managed = model.cliState { true } else { false } },
                    set: { model.setCLIInstalled($0) }
                ))
                .disabled(model.cliState == .foreign || model.hookInstalled)
            }

            Section {
                Toggle("Open at Login", isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Toggle("Usage Alerts", isOn: Binding(
                    get: { model.notificationsEnabled },
                    set: { model.setNotifications($0) }
                ))
                Toggle("Check for Updates Daily", isOn: Binding(
                    get: { model.checksForUpdates },
                    set: { model.setChecksForUpdates($0) }
                ))
            }

            Section {
                Button("Refresh Usage") { Task { await model.refreshLive() } }
                Button("Re-sync Shared Settings") { model.sync() }
                Button("Check for Updates Now") { Task { await model.checkForUpdates(force: true, announce: true) } }
                Button("Show Welcome…") { model.showWelcome() }
            }

            Section {
                Link("Help & Source Code", destination: URL(string: "https://github.com/hamdalaa/claude-switcher")!)
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
            }
        } label: {
            menuLabel("Settings")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Terminal, shell integration, login item, alerts")
    }

    private var cliTitle: String {
        model.cliState == .foreign ? "`ccx` Command (another ccx is installed)" : "Install `ccx` Command"
    }
}
