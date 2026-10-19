import ClaudeSwitcherCore
import SwiftUI

struct AccountCard: View {
    let state: AccountState
    let isNext: Bool
    let isPinned: Bool
    let plan: String?
    let liveError: String?
    let recentProjects: [String]
    let onSelect: () -> Void
    let onOpen: (String?) -> Void
    let onWeb: () -> Void
    let onSignIn: () -> Void
    let avatar: NSImage?
    let onChooseAvatar: () -> Void
    let onDropAvatar: (URL) -> Void
    let onRemoveAvatar: () -> Void

    @State private var isHovered = false
    private var tint: Color { Theme.tint(state.account) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            identity
            if state.isSignedIn, let usage = state.usage {
                VStack(spacing: 7) {
                    UsageRow(title: "5-hour", window: usage.fiveHour)
                    UsageRow(title: "Weekly", window: usage.sevenDay)
                }
            }
            actions
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(isNext ? tint.opacity(0.11) : Color.primary.opacity(isHovered ? 0.07 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(isNext ? tint.opacity(0.5) : .clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .onTapGesture { if state.isSignedIn { onSelect() } }
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.2), value: isNext)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityAddTraits(isNext ? .isSelected : [])
        .accessibilityAction(named: "Make default") { if state.isSignedIn { onSelect() } }
    }

    private var identity: some View {
        HStack(spacing: 10) {
            AvatarView(
                image: avatar,
                tint: state.isSignedIn ? tint : Color.secondary.opacity(0.5),
                badge: state.account.label,
                onChoose: onChooseAvatar,
                onDrop: onDropAvatar,
                onRemove: onRemoveAvatar,
                accessibilityName: "account \(state.account.label)"
            ) {
                Text(state.account.label)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(state.email ?? "Not signed in")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(state.isSignedIn ? .primary : .secondary)
                    if let plan, state.isSignedIn {
                        PlanTag(plan: plan, tint: tint)
                    }
                }
                HStack(spacing: 6) {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(subtitle)
                    Spacer(minLength: 4)
                    badge
                }
                .frame(height: 18)
                if let staleError {
                    Text(staleError)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private var badge: some View {
        if isNext && state.isSignedIn {
            Label(isPinned ? "Default" : "Auto", systemImage: isPinned ? "pin.fill" : "sparkles")
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(tint.opacity(0.15)))
                .help(isPinned ? "New sessions start here" : "Auto picked this account (most headroom)")
        } else if isHovered && state.isSignedIn {
            Text("Make default")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .transition(.opacity)
        }
    }

    @ViewBuilder private var actions: some View {
        if state.isSignedIn {
            HStack(spacing: 8) {
                Menu {
                    Button("Home folder") { onOpen(nil) }
                    if !recentProjects.isEmpty {
                        Section("Recent") {
                            ForEach(recentProjects, id: \.self) { path in
                                Button(Self.displayPath(path)) { onOpen(path) }
                            }
                        }
                    }
                } label: {
                    Label("Claude Code", systemImage: "terminal")
                } primaryAction: {
                    onOpen(nil)
                }
                .menuStyle(.button)
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .help("New Claude Code session on \(state.account.label). Arrow: open in a recent folder")

                Button(action: onWeb) {
                    Label("claude.ai", systemImage: "globe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help("claude.ai signed in as \(state.account.label), in its own browser window")
            }
            .controlSize(.regular)
        } else {
            Button(action: onSignIn) {
                Label("Sign in to Claude Code", systemImage: "person.crop.circle.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .help("Opens a terminal running `ccx login \(state.account.rawValue)`")
        }
    }

    private var subtitle: String {
        guard state.isSignedIn else { return "Account \(state.account.label)" }
        guard let updated = state.usage?.updatedAt else { return liveError ?? "Loading usage…" }
        return updated.timeIntervalSinceNow > -60
            ? "Live"
            : "Updated \(updated.formatted(.relative(presentation: .named)))"
    }

    /// A failed refresh, shown on its own line once the numbers on screen are getting old.
    private var staleError: String? {
        guard state.isSignedIn, let liveError, let updated = state.usage?.updatedAt,
              Date.now.timeIntervalSince(updated) > 300 else { return nil }
        return liveError
    }

    static func displayPath(_ path: String) -> String {
        let home = System.home.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// Quiet outline tag so it reads as metadata next to the louder Default/Auto badge.
struct PlanTag: View {
    let plan: String
    let tint: Color

    var body: some View {
        Text(plan)
            .font(.system(size: 9.5, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .overlay(Capsule().strokeBorder(tint.opacity(0.55), lineWidth: 0.8))
            .fixedSize()
            .accessibilityLabel("\(plan) plan")
    }
}

struct UsageRow: View {
    let title: String
    let window: UsageWindow?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    if let window, window.percent > 0 {
                        Capsule()
                            .fill(Theme.usageColor(window.percent))
                            .frame(width: max(proxy.size.width * CGFloat(min(window.percent, 100)) / 100, Theme.barHeight))
                    }
                }
            }
            .frame(height: Theme.barHeight)

            Text(window.map { "\($0.percent)%" } ?? "–")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(percentStyle)
                .frame(width: 36, alignment: .trailing)

            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(resetText(now: context.date))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 56, alignment: .trailing)
            }
        }
        .help(window?.resetsAt.map { "Resets \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")
        .accessibilityElement(children: .combine)
    }

    /// Plain text normally; the warning colour once usage is high enough to matter.
    private var percentStyle: AnyShapeStyle {
        guard let window, window.percent >= Theme.warnPercent else { return AnyShapeStyle(.primary) }
        return AnyShapeStyle(Theme.usageColor(window.percent))
    }

    private func resetText(now: Date) -> String {
        guard let resets = window?.resetsAt, let left = countdown(to: resets, now: now) else { return "" }
        return "↻ " + left
    }
}
