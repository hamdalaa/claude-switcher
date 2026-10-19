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

/// Filled letter = pinned account, outlined = Auto's pick; then that account's 5-hour usage.
struct MenuBarLabel: View {
    let snapshot: Snapshot

    var body: some View {
        let next = snapshot.next
        let pinned = snapshot.mode != .auto
        let percent = snapshot.state(next).usage?.fiveHour?.percent
        HStack(spacing: 3) {
            Image(systemName: pinned ? "\(next.rawValue).circle.fill" : "\(next.rawValue).circle")
            if let percent { Text("\(percent)%").monospacedDigit() }
        }
        .accessibilityLabel("Claude account \(next.label)\(percent.map { ", \($0) percent used" } ?? "")")
    }
}
