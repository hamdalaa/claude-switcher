// Renders the 1024px app icon: two overlapping account discs on a warm dark tile.
import AppKit

let size = 1024.0
let out = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(red: 0.16, green: 0.14, blue: 0.13, alpha: 1),
           ending: NSColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1))!.draw(in: tile, angle: -90)
let clay = NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)
let sage = NSColor(red: 0.24, green: 0.56, blue: 0.50, alpha: 1)
sage.setFill(); NSBezierPath(ovalIn: NSRect(x: 452, y: 300, width: 360, height: 360)).fill()
clay.withAlphaComponent(0.94).setFill(); NSBezierPath(ovalIn: NSRect(x: 212, y: 364, width: 360, height: 360)).fill()
let font = NSFont.systemFont(ofSize: 190, weight: .heavy)
for (text, x, y) in [("A", 392.0, 544.0), ("B", 632.0, 480.0)] {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let s = NSAttributedString(string: text, attributes: attrs)
    let b = s.size()
    s.draw(at: NSPoint(x: x - b.width / 2, y: y - b.height / 2))
}
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
