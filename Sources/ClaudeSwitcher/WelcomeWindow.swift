import AppKit
import ClaudeSwitcherCore
import SwiftUI

/// First-launch setup: confirms account A, adds a second account, and offers the `claude` hook.
/// Shown once automatically; reopen from Settings → Show Welcome.
@MainActor
enum WelcomeWindow {
    private static var window: NSWindow?

    static func show(model: SwitcherModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let host = NSHostingController(rootView: WelcomeView(model: model) { close() })
        let window = NSWindow(contentViewController: host)
        window.title = "Welcome to Claude Switcher"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    static func close() {
        window?.close()
        window = nil
    }
}

struct WelcomeView: View {
    let model: SwitcherModel
    let onDone: () -> Void

    private var accountA: AccountState { model.snapshot.state(.a) }
    private var others: [AccountState] { model.snapshot.states.filter { $0.account != .a } }
    private var secondAccount: AccountState? { others.first { $0.isSignedIn } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.welcomeSectionGap) {
            VStack(alignment: .leading, spacing: Theme.textGap) {
                Text("Your Claude accounts, one menu bar.")
                    .font(Theme.welcomeTitle)
                Text("Switch which account new Claude Code sessions use, and see how much each has left.")
                    .font(Theme.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Theme.welcomeStepGap) {
                step(number: 1, done: accountA.isSignedIn,
                     title: accountA.isSignedIn ? "Account A: \(accountA.email ?? "signed in")" : "Sign in to Claude Code",
                     detail: accountA.isSignedIn
                        ? "Your existing Claude Code setup. Its settings, skills and memory are shared with the others."
                        : "Claude Switcher uses your Claude Code login as account A.") {
                    if !accountA.isSignedIn {
                        Button("Sign In…") { model.signIn(.a) }
                    }
                }

                step(number: 2, done: secondAccount != nil,
                     title: secondAccount.map { "Account \($0.account.label): \($0.email ?? "signed in")" } ?? "Add another account",
                     detail: secondAccount != nil
                        ? "Click either account in the menu bar to switch."
                        : "Opens a terminal and your browser. Sign in with your other Claude account.") {
                    if secondAccount == nil {
                        Button("Sign In to Account B…") { model.signIn(.b) }
                            .buttonStyle(.borderedProminent)
                    }
                }

                step(number: 3, done: model.hookInstalled,
                     title: "Make plain claude follow the switch",
                     detail: "Optional. Adds a small, marked hook to your shell config. Without it, plain claude always uses account A.") {
                    Toggle("Plain claude follows the switch", isOn: Binding(
                        get: { model.hookInstalled },
                        set: { model.setHook($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!model.shellSupportsHook)
                }

                step(number: 4, done: model.launchesAtLogin,
                     title: "Open at login",
                     detail: "Keeps usage and alerts up to date.") {
                    Toggle("Open at login", isOn: Binding(
                        get: { model.launchesAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            if let message = model.message {
                Text(message).font(Theme.detail).foregroundStyle(.secondary)
            }

            HStack {
                Text("Claude Switcher lives in your menu bar.")
                    .font(Theme.detail)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.welcomePadding)
        .frame(width: Theme.welcomeWidth)
        .onAppear { model.panelOpened() }
    }

    private func step<Accessory: View>(number: Int, done: Bool, title: String, detail: String,
                                       @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(alignment: .top, spacing: Theme.rowSpacing + Theme.textGap * 2) {
            ZStack {
                Circle().fill(done ? Color.accentColor : Theme.meterTrack)
                if done {
                    Image(systemName: "checkmark").font(Theme.detail.weight(.bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(Theme.detailDigits.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: Theme.welcomeBadge, height: Theme.welcomeBadge)
            .accessibilityLabel(done ? "Done" : "Step \(number)")
            VStack(alignment: .leading, spacing: Theme.textGap) {
                Text(title).font(Theme.bodyStrong).lineLimit(1).truncationMode(.middle)
                Text(detail).font(Theme.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.rowSpacing)
            accessory().controlSize(.small)
        }
    }
}
