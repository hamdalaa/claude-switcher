import ClaudeSwitcherCore
import SwiftUI

/// Codex CLI usage as a single menu row; clicking starts a Codex session.
struct CodexRow: View {
    let usage: CodexUsage?
    let error: String?
    let avatar: NSImage?
    let onOpen: () -> Void
    let onOpenWeb: () -> Void
    let onChoosePicture: () -> Void
    let onDropPicture: (URL) -> Void
    let onRemovePicture: () -> Void

    var body: some View {
        MenuRow(action: onOpen) {
            HStack(spacing: Theme.rowSpacing) {
                Color.clear.frame(width: Theme.checkColumn, height: 1)
                Avatar(image: avatar, tint: Theme.codexAvatar, letter: nil,
                       symbol: "chevron.left.forwardslash.chevron.right")
                VStack(alignment: .leading, spacing: Theme.textGap) {
                    Text("Codex").font(Theme.body)
                    Text(subtitle)
                        .font(Theme.detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: Theme.rowSpacing)
                if let left {
                    Text(left.text)
                        .font(Theme.bodyDigits)
                        .foregroundStyle(left.color ?? .secondary)
                }
            }
        }
        .modifier(ImageDrop(onDrop: onDropPicture))
        .contextMenu {
            Button("New Codex Session", action: onOpen)
            Button("Open Codex on chatgpt.com", action: onOpenWeb)
            Divider()
            Button("Change Picture…", action: onChoosePicture)
            if avatar != nil { Button("Remove Picture", action: onRemovePicture) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Starts a Codex session")
        .help("Start a Codex session")
    }

    private var subtitle: String {
        guard let usage else { return error ?? "Loading usage…" }
        if let error, Date.now.timeIntervalSince(usage.updatedAt) > 300 { return error }
        return [usage.email, usage.plan].compactMap { $0 }.joined(separator: " · ")
    }

    /// "79% left", in warning colors as it runs low.
    private var left: (text: String, color: Color?)? {
        guard let usage else { return nil }
        if usage.limitReached { return ("Limit reached", .red) }
        guard let percent = usage.percentLeft else { return nil }
        return ("\(percent)% left", Theme.warning(for: 100 - percent))
    }
}
