import SwiftUI
import UniformTypeIdentifiers

/// Circular avatar: custom picture if set, else the fallback (letter or symbol) on a tinted disc.
/// Click or drop an image to change it; right-click to remove. A custom picture keeps a small
/// corner badge so accounts stay distinguishable at a glance.
struct AvatarView<Fallback: View>: View {
    let image: NSImage?
    let tint: Color
    let badge: String?
    let onChoose: () -> Void
    let onDrop: (URL) -> Void
    let onRemove: () -> Void
    @ViewBuilder let fallback: () -> Fallback

    @State private var isHovered = false
    @State private var isTargeted = false

    var body: some View {
        Button(action: onChoose) {
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    Circle().fill(tint)
                    fallback()
                }
                if isHovered || isTargeted {
                    Circle().fill(.black.opacity(0.42))
                    Image(systemName: isTargeted ? "arrow.down.circle.fill" : "camera.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: Theme.avatarSize, height: Theme.avatarSize)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(image == nil ? 0 : 0.12), lineWidth: 0.5))
            .overlay(alignment: .bottomTrailing) {
                if image != nil, let badge {
                    Text(badge)
                        .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(tint))
                        .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                        .offset(x: 3, y: 3)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered || isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { onDrop(url) } }
            }
            return true
        }
        .contextMenu {
            Button("Choose Picture…", action: onChoose)
            if image != nil { Button("Remove Picture", role: .destructive, action: onRemove) }
        }
        .help("Click or drop an image to change the picture")
    }
}
