import ClaudeSwitcherCore
import SwiftUI

/// The menu bar panel, laid out like a native macOS menu (see DESIGN.md).
struct PanelView: View {
    let model: SwitcherModel

    private var active: AccountState { model.snapshot.state(model.snapshot.next) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(model.snapshot.states) { state in
                AccountRow(
                    state: state,
                    name: model.names[state.account],
                    isActive: model.snapshot.next == state.account,
                    isAutoPick: model.snapshot.mode == .auto,
                    plan: model.plans[state.account],
                    staleError: staleError(state),
                    avatar: model.avatars[state.account.rawValue],
                    onSelect: { model.setMode(.pinned(state.account)) },
                    onSignIn: { model.signIn(state.account) },
                    onOpenSession: { model.open(state.account) },
                    onOpenWeb: { model.openWeb(state.account) },
                    onChoosePicture: { model.chooseAvatar(state.account.rawValue) },
                    onDropPicture: { model.setAvatar(state.account.rawValue, from: $0) },
                    onRemovePicture: { model.removeAvatar(state.account.rawValue) },
                    onRename: { model.rename(state.account) },
                    onRemove: state.account == .a ? nil : { model.removeAccount(state.account) }
                )
            }
            if model.canAddAccount {
                MenuItem(title: "Add Account…") { model.addAccount() }
                    .help("Sign in another Claude account (up to four)")
            }

            if model.showsHookBanner {
                MenuSeparator()
                hookPrompt
            }

            MenuSeparator()
            actions

            if model.codexAvailable {
                MenuSeparator()
                CodexRow(
                    usage: model.codex,
                    error: model.codexError,
                    avatar: model.avatars["codex"],
                    onOpen: { model.openCodex() },
                    onOpenWeb: { model.openCodexWeb() },
                    onChoosePicture: { model.chooseAvatar("codex") },
                    onDropPicture: { model.setAvatar("codex", from: $0) },
                    onRemovePicture: { model.removeAvatar("codex") }
                )
            }

            if let message = model.message {
                MenuSeparator()
                messageRow(message)
            }

            if let update = model.update {
                MenuSeparator()
                MenuItem(title: "Update to \(update.version)…", trailing: model.installedWithHomebrew ? "brew" : nil) {
                    model.installUpdate()
                }
                .foregroundStyle(Color.accentColor)
                .help(model.installedWithHomebrew ? "Runs brew upgrade --cask claude-switcher" : "Opens the release page")
            }

            MenuSeparator()
            SettingsMenu(model: model)
            MenuItem(title: "Quit Claude Switcher", trailing: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(Theme.panelInset)
        .frame(width: Theme.panelWidth)
        .onAppear { model.panelOpened() }
        // MenuBarExtra may keep this view alive between opens; refresh each time it's shown.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            model.panelOpened()
        }
    }

    private var header: some View {
        HStack(spacing: Theme.rowSpacing) {
            Text("Claude Code").font(Theme.title)
            Spacer()
            Text("Auto").font(Theme.detail).foregroundStyle(.secondary)
            Toggle("Auto", isOn: Binding(
                get: { model.snapshot.mode == .auto },
                set: { model.setMode($0 ? .auto : .pinned(model.snapshot.next)) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .help("Automatically start new sessions on the account with more room left")
        }
        .padding(.horizontal, Theme.rowPaddingH)
        .padding(.top, Theme.headerPaddingTop)
        .padding(.bottom, Theme.separatorGap)
    }

    /// Actions apply to the ✓ account; per-account versions are in each row's context menu.
    @ViewBuilder private var actions: some View {
        let label = model.snapshot.next.label
        if active.isSignedIn {
            MenuItem(title: "New Claude Code Session") { model.open(model.snapshot.next) }
                .help("Opens \(model.terminal.displayName) on account \(label)")
            if !model.recentSessions.isEmpty {
                Menu {
                    Section("Continue on account \(label)") {
                        ForEach(model.recentSessions) { session in
                            Button("\(session.title) — \(Self.displayPath(session.directory))") {
                                model.continueSession(session, on: model.snapshot.next)
                            }
                        }
                    }
                } label: {
                    menuLabel("Continue a Conversation")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .help("Pick up a recent conversation on account \(label) — handy when another account hits its limit")
            }
            if !model.recentProjects.isEmpty {
                Menu {
                    ForEach(model.recentProjects, id: \.self) { path in
                        Button(Self.displayPath(path)) { model.open(model.snapshot.next, in: path) }
                    }
                } label: {
                    menuLabel("Open in Recent Folder")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            }
            MenuItem(title: "Open claude.ai") { model.openWeb(model.snapshot.next) }
                .help("claude.ai signed in as account \(label), in its own browser window")
        } else {
            MenuItem(title: "Sign In to Account \(label)…") { model.signIn(model.snapshot.next) }
        }
    }

    private var hookPrompt: some View {
        VStack(alignment: .leading, spacing: Theme.stackGap) {
            Text("Make plain `claude` follow the switch?").font(Theme.body)
            Text("Adds a small hook to your shell config. You can undo it in Settings.")
                .font(Theme.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.rowSpacing) {
                Button("Turn On") { model.setHook(true) }
                    .buttonStyle(.borderedProminent)
                Button("Not Now") { model.dismissHookBanner() }
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, Theme.rowPaddingH)
        .padding(.vertical, Theme.rowPaddingV)
    }

    private func messageRow(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.rowSpacing) {
            Text(message)
                .font(Theme.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { model.dismissMessage() } label: {
                Image(systemName: "xmark").font(Theme.detail.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, Theme.rowPaddingH)
        .padding(.vertical, Theme.rowPaddingV)
    }

    private func staleError(_ state: AccountState) -> String? {
        guard state.isSignedIn, let error = model.liveErrors[state.account] else { return nil }
        // No usage yet: say why, instead of "loading usage…" forever.
        guard let usage = state.usage else { return error }
        guard let updated = usage.updatedAt, Date.now.timeIntervalSince(updated) > 300 else { return nil }
        return error
    }

    static func displayPath(_ path: String) -> String {
        let home = System.home.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// A row-shaped label for native Menus (submenu chevron on the right).
@MainActor func menuLabel(_ title: String) -> some View {
    HStack {
        Text(title).font(Theme.body)
        Spacer(minLength: Theme.rowSpacing)
        Image(systemName: "chevron.right").font(Theme.detail.weight(.semibold)).foregroundStyle(.tertiary)
    }
    .padding(.horizontal, Theme.rowPaddingH)
    .padding(.vertical, Theme.rowPaddingV)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
}
