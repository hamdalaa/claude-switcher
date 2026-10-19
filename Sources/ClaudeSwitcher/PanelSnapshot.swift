import AppKit
import SwiftUI

/// `ClaudeSwitcher --snapshot out.png` renders the panel offscreen (for visual checks) and exits.
enum PanelSnapshot {
    @MainActor static func renderIfRequested(model: SwitcherModel) {
        let args = CommandLine.arguments
        // `--set-avatar <a|b|codex> <image>` — same path as dropping an image on the avatar.
        if let i = args.firstIndex(of: "--set-avatar"), i + 2 < args.count {
            model.setAvatar(args[i + 1], from: URL(filePath: args[i + 2]))
        }
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return }
        Task { @MainActor in
            await model.refreshLive()
            render(model: model, to: args[index + 1], dark: args.contains("--dark"))
        }
    }

    @MainActor private static func render(model: SwitcherModel, to path: String, dark: Bool) {
        let content: AnyView = CommandLine.arguments.contains("--welcome")
            ? AnyView(WelcomeView(model: model) {})
            : AnyView(PanelView(model: model))
        let host = NSHostingView(rootView: content
            .background(.regularMaterial)
            .environment(\.colorScheme, dark ? .dark : .light))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
        exit(0)
    }
}
