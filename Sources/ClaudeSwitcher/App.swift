import ClaudeSwitcherCore
import SwiftUI

@main
struct ClaudeSwitcherApp: App {
    @State private var model: SwitcherModel

    init() {
        // Writing to a child's closed stdin (e.g. codex exiting early) must be an error, not a crash.
        signal(SIGPIPE, SIG_IGN)
        CommandLineSetup.runIfRequested()
        let model = SwitcherModel(demo: CommandLine.arguments.contains("--demo"))
        PanelSnapshot.renderIfRequested(model: model)
        _model = State(initialValue: model)
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            MenuBarLabel(snapshot: model.snapshot)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Filled letter = pinned account, outlined = Auto's pick; then that account's usage as
/// "D:56% W:87%" (D = the 5-hour window, W = weekly).
struct MenuBarLabel: View {
    let snapshot: Snapshot

    var body: some View {
        let next = snapshot.next
        let pinned = snapshot.mode != .auto
        let usage = snapshot.state(next).usage
        let daily = usage?.fiveHour?.percent
        let weekly = usage?.sevenDay?.percent
        HStack(spacing: 3) {
            Image(systemName: pinned ? "\(next.rawValue).circle.fill" : "\(next.rawValue).circle")
            if let text = Self.usageText(daily: daily, weekly: weekly) {
                Text(text).monospacedDigit()
            }
        }
        .accessibilityLabel(Self.accessibilityText(account: next, daily: daily, weekly: weekly))
    }

    static func usageText(daily: Int?, weekly: Int?) -> String? {
        let parts = [daily.map { "D:\($0)%" }, weekly.map { "W:\($0)%" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    static func accessibilityText(account: Account, daily: Int?, weekly: Int?) -> String {
        var text = "Claude account \(account.label)"
        if let daily { text += ", 5-hour \(daily) percent used" }
        if let weekly { text += ", weekly \(weekly) percent used" }
        return text
    }
}
