import AppKit
import ClaudeSwitcherCore
import UniformTypeIdentifiers

/// Custom profile pictures, stored as 192px PNGs in ~/.claude-accounts/avatars/<key>.png.
/// Keys: "a", "b", "codex".
struct AvatarStore {
    static let pixelSize: CGFloat = 192
    let directory: URL

    init(paths: Paths = Paths()) {
        directory = paths.stateRoot.appending(path: "avatars")
    }

    func url(_ key: String) -> URL { directory.appending(path: "\(key).png") }

    func load(_ key: String) -> NSImage? {
        NSImage(contentsOf: url(key))
    }

    /// Center-crops to a square, scales down and saves as PNG.
    func save(_ key: String, from source: URL) throws {
        guard let image = NSImage(contentsOf: source),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { throw AvatarError.unreadable }
        let side = min(cg.width, cg.height)
        let crop = CGRect(x: (cg.width - side) / 2, y: (cg.height - side) / 2, width: side, height: side)
        guard let square = cg.cropping(to: crop) else { throw AvatarError.unreadable }

        let size = Int(Self.pixelSize)
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw AvatarError.unreadable }
        context.interpolationQuality = .high
        context.draw(square, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let scaled = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
        else { throw AvatarError.unreadable }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: url(key), options: .atomic)
    }

    func remove(_ key: String) throws {
        if FileManager.default.fileExists(atPath: url(key).path) {
            try FileManager.default.removeItem(at: url(key))
        }
    }

    /// Asks for an image file. Returns nil if cancelled.
    @MainActor static func pickImage() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a profile picture"
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }
}

enum AvatarError: LocalizedError {
    case unreadable
    var errorDescription: String? { "That file isn't an image I can read" }
}
