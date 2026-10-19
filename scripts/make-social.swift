// Renders docs/social-preview.png (1280×640) for GitHub's social preview from the dark demo screenshot.
// Usage: swift scripts/make-social.swift docs/screenshot-dark.png docs/social-preview.png
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let shot = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("usage: make-social.swift <screenshot> <out.png>\n".utf8)); exit(1)
}
let size = NSSize(width: 1280, height: 640)
let image = NSImage(size: size)
image.lockFocus()
NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

// Screenshot on the right, as a floating panel.
let panelHeight: CGFloat = 560
let panelWidth = panelHeight * shot.size.width / shot.size.height
let panel = NSRect(x: size.width - panelWidth - 80, y: (size.height - panelHeight) / 2, width: panelWidth, height: panelHeight)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
shadow.shadowBlurRadius = 40
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSBezierPath(roundedRect: panel, xRadius: 14, yRadius: 14).addClip()
shot.draw(in: panel)
NSGraphicsContext.restoreGraphicsState()
NSColor.white.withAlphaComponent(0.12).setStroke()
let border = NSBezierPath(roundedRect: panel, xRadius: 14, yRadius: 14)
border.lineWidth = 1
border.stroke()

func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, at point: NSPoint, width: CGFloat) {
    let style = NSMutableParagraphStyle()
    style.lineHeightMultiple = 1.08
    let attributed = NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style,
    ])
    // point = bottom-left of the text block (AppKit's y axis points up).
    let bounds = attributed.boundingRect(with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin])
    attributed.draw(with: NSRect(x: point.x, y: point.y, width: width, height: ceil(bounds.height)),
                    options: [.usesLineFragmentOrigin])
}
let left: CGFloat = 80
let textWidth = panel.minX - left - 60
draw("Claude Switcher", size: 64, weight: .bold, color: .white, at: NSPoint(x: left, y: 400), width: textWidth)
draw("Two Claude Code accounts.\nOne click to switch.\nLive usage in your menu bar.", size: 30, weight: .regular,
     color: NSColor.white.withAlphaComponent(0.62), at: NSPoint(x: left, y: 250), width: textWidth)
draw("Free & open source · macOS", size: 20, weight: .medium, color: NSColor.white.withAlphaComponent(0.4),
     at: NSPoint(x: left, y: 170), width: textWidth)
image.unlockFocus()
// Draw at 1× so the file is exactly 1280×640 (GitHub's recommended size).
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1280, pixelsHigh: 640, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(origin: .zero, size: size))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
