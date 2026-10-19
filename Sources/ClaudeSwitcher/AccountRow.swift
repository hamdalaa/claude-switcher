import ClaudeSwitcherCore
import SwiftUI

/// One Claude account as a menu row. ✓ marks where new sessions start; clicking switches to it.
/// The active row expands to show its meters; the other keeps a one-line summary.
struct AccountRow: View {
    let state: AccountState
    let isActive: Bool
    /// The ✓ was chosen by Auto rather than by the user.
    let isAutoPick: Bool
    let plan: String?
    let staleError: String?
    let avatar: NSImage?
    let onSelect: () -> Void
    let onSignIn: () -> Void
    let onOpenSession: () -> Void
    let onOpenWeb: () -> Void
    let onChoosePicture: () -> Void
    let onDropPicture: (URL) -> Void
    let onRemovePicture: () -> Void

    var body: some View {
        MenuRow(action: state.isSignedIn ? onSelect : onSignIn) {
            HStack(alignment: .top, spacing: Theme.rowSpacing) {
                Image(systemName: "checkmark")
                    .font(Theme.detail.weight(.bold))
                    .opacity(isActive && state.isSignedIn ? 1 : 0)
                    .frame(width: Theme.checkColumn, height: Theme.avatarSize)
                Avatar(image: avatar,
                       tint: state.isSignedIn ? Theme.tint(state.account) : Theme.neutralAvatar,
                       letter: state.account.label)
                VStack(alignment: .leading, spacing: Theme.textGap) {
                    Text(state.email ?? "Account \(state.account.label)")
                        .font(Theme.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    summary
                    if isActive, state.isSignedIn, let usage = state.usage {
                        VStack(spacing: Theme.meterGap) {
                            UsageLine(title: "5-hour", window: usage.fiveHour)
                            UsageLine(title: "Weekly", window: usage.sevenDay)
                        }
                        .padding(.top, Theme.meterGap)
                    }
                    if let staleError {
                        Text(staleError)
                            .font(Theme.detail)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .modifier(ImageDrop(onDrop: onDropPicture))
        .contextMenu {
            if state.isSignedIn {
                Button("New Claude Code Session on This Account", action: onOpenSession)
                Button("Open claude.ai for This Account", action: onOpenWeb)
            } else {
                Button("Sign In…", action: onSignIn)
            }
            Divider()
            Button("Change Picture…", action: onChoosePicture)
            if avatar != nil { Button("Remove Picture", action: onRemovePicture) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint(state.isSignedIn ? "New sessions start on this account" : "Signs in this account")
        .help(state.isSignedIn ? "Start new sessions on this account" : "Sign in this account")
    }

    /// "Max 20x · 5h 51% · week 86%": numbers turn orange/red only when they matter.
    @ViewBuilder private var summary: some View {
        if !state.isSignedIn {
            Text("Not signed in — click to sign in").font(Theme.detail).foregroundStyle(.secondary)
        } else {
            let parts = summaryParts
            parts.dropFirst().reduce(parts.first ?? Text("")) { $0 + Text(" · ").foregroundColor(.secondary) + $1 }
                .font(Theme.detailDigits)
                .lineLimit(1)
        }
    }

    private var summaryParts: [Text] {
        var parts: [Text] = []
        if let plan { parts.append(Text(plan).foregroundColor(.secondary)) }
        // The active row shows its meters below, so its summary doesn't repeat the numbers.
        if isActive {
            if isAutoPick { parts.append(Text("picked by Auto").foregroundColor(.secondary)) }
            return parts.isEmpty ? [Text("Signed in").foregroundColor(.secondary)] : parts
        }
        if let usage = state.usage {
            if let five = usage.fiveHour { parts.append(percentText("5h", five.percent)) }
            if let week = usage.sevenDay { parts.append(percentText("week", week.percent)) }
        } else {
            parts.append(Text("loading usage…").foregroundColor(.secondary))
        }
        return parts
    }

    private func percentText(_ label: String, _ percent: Int) -> Text {
        Text("\(label) \(percent)%").foregroundColor(Theme.warning(for: percent) ?? .secondary)
    }
}
