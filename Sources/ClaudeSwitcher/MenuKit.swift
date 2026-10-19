import ClaudeSwitcherCore
import SwiftUI
import UniformTypeIdentifiers

/// A macOS-menu-style row: full width, rounded hover highlight, plain text.
struct MenuRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.rowPaddingH)
                .padding(.vertical, Theme.rowPaddingV)
                .background(RoundedRectangle(cornerRadius: Theme.highlightRadius, style: .continuous)
                    .fill(isHovered ? Theme.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Plain text menu item with an optional trailing hint (shortcut, chevron).
struct MenuItem: View {
    let title: String
    var trailing: String?
    var trailingSymbol: String?
    let action: () -> Void

    var body: some View {
        MenuRow(action: action) {
            HStack {
                Text(title).font(Theme.body)
                Spacer(minLength: Theme.rowSpacing)
                if let trailing { Text(trailing).font(Theme.body).foregroundStyle(.tertiary) }
                if let trailingSymbol {
                    Image(systemName: trailingSymbol).font(Theme.detail.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct MenuSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
            .padding(.horizontal, Theme.separatorInsetH)
            .padding(.vertical, Theme.separatorGap)
    }
}

/// Circle avatar: the user's picture, else a letter or symbol on a tinted disc.
struct Avatar: View {
    let image: NSImage?
    let tint: Color
    let letter: String?
    var symbol: String?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
            } else {
                Circle().fill(tint)
                if let letter {
                    Text(letter).font(Theme.avatarLetter).foregroundStyle(.white)
                } else if let symbol {
                    Image(systemName: symbol).font(Theme.detail.weight(.bold)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: Theme.avatarSize, height: Theme.avatarSize)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// One usage window: label, thin meter, percent, time to reset. Neutral until it's a warning.
struct UsageLine: View {
    let title: String
    let window: UsageWindow?

    var body: some View {
        HStack(spacing: Theme.rowSpacing) {
            Text(title)
                .font(Theme.detail)
                .foregroundStyle(.secondary)
                .frame(width: Theme.meterLabelWidth, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.meterTrack)
                    if let window, window.percent > 0 {
                        Capsule()
                            .fill(Theme.warning(for: window.percent) ?? Theme.meterFill)
                            .frame(width: max(proxy.size.width * CGFloat(min(window.percent, 100)) / 100, Theme.meterHeight))
                    }
                }
            }
            .frame(height: Theme.meterHeight)
            Text(window.map { "\($0.percent)%" } ?? "–")
                .font(Theme.detailDigits.weight(.medium))
                .foregroundStyle(window.flatMap { Theme.warning(for: $0.percent) } ?? .primary)
                .frame(width: Theme.meterValueWidth, alignment: .trailing)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(window?.resetsAt.flatMap { countdown(to: $0, now: context.date) } ?? "")
                    .font(Theme.detailDigits)
                    .foregroundStyle(.tertiary)
                    .frame(width: Theme.meterResetWidth, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let window else { return "\(title) usage unknown" }
        let reset = window.resetsAt.flatMap { countdown(to: $0) }.map { ", resets in \($0)" } ?? ""
        return "\(title) \(window.percent) percent used\(reset)"
    }
}

/// Accepts an image file dropped on a view (used to set profile pictures).
struct ImageDrop: ViewModifier {
    let onDrop: (URL) -> Void

    func body(content: Content) -> some View {
        content.onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { onDrop(url) } }
            }
            return true
        }
    }
}
