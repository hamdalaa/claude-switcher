import ClaudeSwitcherCore
import SwiftUI

struct PanelView: View {
    let model: SwitcherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ModeControl(selection: ModeChoice(model.snapshot.mode)) { model.setMode($0.mode) }
                .help("Which account new sessions start on (same as `ccx use`)")
            if model.showsHookBanner { hookBanner }
            VStack(spacing: 8) {
                ForEach(model.snapshot.states) { state in
                    AccountCard(
                        state: state,
                        isNext: model.snapshot.next == state.account,
                        isPinned: model.snapshot.mode != .auto,
                        plan: model.plans[state.account],
                        liveError: model.liveErrors[state.account],
                        recentProjects: model.recentProjects,
                        onSelect: { model.setMode(.pinned(state.account)) },
                        onOpen: { model.open(state.account, in: $0) },
                        onWeb: { model.openWeb(state.account) },
                        onSignIn: { model.signIn(state.account) },
                        avatar: model.avatars[state.account.rawValue],
                        onChooseAvatar: { model.chooseAvatar(state.account.rawValue) },
                        onDropAvatar: { model.setAvatar(state.account.rawValue, from: $0) },
                        onRemoveAvatar: { model.removeAvatar(state.account.rawValue) }
                    )
                }
            }
            if model.codexAvailable {
            CodexCard(
                usage: model.codex,
                error: model.codexError,
                recentProjects: model.recentProjects,
                onOpen: { model.openCodex(in: $0) },
                onWeb: { model.openCodexWeb() },
                avatar: model.avatars["codex"],
                onChooseAvatar: { model.chooseAvatar("codex") },
                onDropAvatar: { model.setAvatar("codex", from: $0) },
                onRemoveAvatar: { model.removeAvatar("codex") }
            )
            }
            if let message = model.message {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                    Text(message).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { model.dismissMessage() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .help("Dismiss")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: Theme.panelWidth)
        .onAppear { model.panelOpened() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Claude")
                .font(.title3.weight(.semibold))
            Button {
                Task { await model.refreshLive() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(model.isRefreshing ? 360 : 0))
                    .animation(model.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                               value: model.isRefreshing)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(model.isRefreshing)
            .help("Refresh usage now")
            Spacer()
            Text("Next session → \(model.snapshot.next.label)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.tint(model.snapshot.next))
                .contentTransition(.numericText())
                .animation(.snappy, value: model.snapshot.next)
        }
    }

    /// One-time nudge: without the hook, plain `claude` ignores the switch.
    private var hookBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "terminal.fill")
                .foregroundStyle(Theme.tint(model.snapshot.next))
            VStack(alignment: .leading, spacing: 6) {
                Text("Make plain `claude` follow the switch?")
                    .font(.caption.weight(.semibold))
                Text("Adds a small hook to your shell config. Undo anytime in Settings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Turn On") { model.setHook(true) }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.tint(model.snapshot.next))
                    Button("Not Now") { model.dismissHookBanner() }
                        .controlSize(.small)
                        .buttonStyle(.borderless)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private var footer: some View {
        HStack(spacing: 14) {
            SettingsMenu(model: model)
            Spacer()
            Button {
                model.sync()
            } label: {
                if model.isSyncing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
            .help("Re-link shared settings, skills and memory into account B")
            .disabled(model.isSyncing)
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .help("Quit Claude Switcher")
        }
        .font(.caption)
        .buttonStyle(.borderless)
    }
}

enum ModeChoice: String, CaseIterable, Identifiable {
    case auto, a, b
    var id: String { rawValue }

    init(_ mode: Mode) {
        switch mode {
        case .auto: self = .auto
        case .pinned(.a): self = .a
        case .pinned(.b): self = .b
        }
    }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .a: "A"
        case .b: "B"
        }
    }

    var tint: Color {
        switch self {
        case .auto: .primary
        case .a: Theme.tint(.a)
        case .b: Theme.tint(.b)
        }
    }

    var mode: Mode {
        switch self {
        case .auto: .auto
        case .a: .pinned(.a)
        case .b: .pinned(.b)
        }
    }
}

/// Full-width segmented control; the selected segment takes its account colour.
private struct ModeControl: View {
    let selection: ModeChoice
    let onSelect: (ModeChoice) -> Void
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ModeChoice.allCases) { choice in
                let isSelected = choice == selection
                Button { onSelect(choice) } label: {
                    Text(choice.title)
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? choice.tint : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .contentShape(Rectangle())
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(.background)
                                    .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.07)))
        .animation(.snappy(duration: 0.22), value: selection)
    }
}
