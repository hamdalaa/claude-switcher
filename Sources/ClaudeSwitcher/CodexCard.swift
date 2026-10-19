import ClaudeSwitcherCore
import SwiftUI

/// OpenAI Codex CLI usage, shown alongside the Claude accounts.
struct CodexCard: View {
    let usage: CodexUsage?
    let error: String?
    let recentProjects: [String]
    let onOpen: (String?) -> Void
    let onWeb: () -> Void
    let avatar: NSImage?
    let onChooseAvatar: () -> Void
    let onDropAvatar: (URL) -> Void
    let onRemoveAvatar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            identity
            if let usage {
                VStack(spacing: 7) {
                    ForEach(Array(usage.windows.enumerated()), id: \.offset) { _, item in
                        UsageRow(title: item.title, window: item.window)
                    }
                }
            }
            actions
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var identity: some View {
        HStack(spacing: 10) {
            AvatarView(
                image: avatar,
                tint: Color.primary.opacity(0.85),
                badge: nil,
                onChoose: onChooseAvatar,
                onDrop: onDropAvatar,
                onRemove: onRemoveAvatar,
                accessibilityName: "Codex"
            ) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(usage?.email ?? "Codex")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let plan = usage?.plan { PlanTag(plan: plan, tint: .secondary) }
                }
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(usage?.limitReached == true ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .frame(height: 18, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
    }

    private var subtitle: String {
        guard let usage else { return error ?? "Loading Codex usage…" }
        if usage.limitReached { return "Limit reached" }
        let left = usage.percentLeft.map { "\($0)% left" } ?? "No limits reported"
        let age = usage.updatedAt.timeIntervalSinceNow > -60
            ? "Live" : "Updated \(usage.updatedAt.formatted(.relative(presentation: .named)))"
        if let error, Date.now.timeIntervalSince(usage.updatedAt) > 300 { return "\(left) · \(error)" }
        return "\(left) · \(age)"
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Home folder") { onOpen(nil) }
                if !recentProjects.isEmpty {
                    Section("Recent") {
                        ForEach(recentProjects, id: \.self) { path in
                            Button(AccountCard.displayPath(path)) { onOpen(path) }
                        }
                    }
                }
            } label: {
                Label("Codex", systemImage: "terminal")
            } primaryAction: {
                onOpen(nil)
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .help("New Codex session. Arrow: open in a recent folder")

            Button(action: onWeb) {
                Label("chatgpt.com", systemImage: "globe")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .help("Open Codex on chatgpt.com")
        }
    }
}
