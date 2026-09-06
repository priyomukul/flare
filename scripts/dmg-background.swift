// Renders the drag-and-drop background for Flare.dmg at 1x and 2x.
// Zero dependencies — AppKit only. Run via scripts/make-dmg.sh.
import AppKit

let W: CGFloat = 600, H: CGFloat = 400
/// Icon slot centres, measured from the top-left of the window's content area,
/// and kept in step with the positions make-dmg.sh gives Finder.
let appSlot = CGPoint(x: 150, y: 180)
let dropSlot = CGPoint(x: 450, y: 180)

func flip(_ y: CGFloat) -> CGFloat { H - y }

func draw(into ctx: CGContext) {
    let space = CGColorSpaceCreateDeviceRGB()

    // Warm ground, picked out of the app icon.
    let bg = CGGradient(colorsSpace: space,
                        colors: [NSColor(srgbRed: 1.0, green: 0.973, blue: 0.953, alpha: 1).cgColor,
                                 NSColor(srgbRed: 1.0, green: 0.906, blue: 0.843, alpha: 1).cgColor] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])

    // Beacon rings, echoing the icon without competing with it.
    ctx.setLineWidth(1.5)
    ctx.setStrokeColor(NSColor(srgbRed: 0.91, green: 0.40, blue: 0.16, alpha: 0.10).cgColor)
    for r in stride(from: CGFloat(90), through: 330, by: 60) {
        ctx.strokeEllipse(in: CGRect(x: appSlot.x - r, y: flip(appSlot.y) - r, width: r * 2, height: r * 2))
    }

    // The arrow: drag from here to there.
    let accent = NSColor(srgbRed: 0.85, green: 0.35, blue: 0.12, alpha: 0.55).cgColor
    let y = flip(appSlot.y)
    ctx.setStrokeColor(accent)
    ctx.setLineWidth(7)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: 258, y: y))
    ctx.addLine(to: CGPoint(x: 330, y: y))
    ctx.strokePath()
    ctx.move(to: CGPoint(x: 316, y: y + 16))
    ctx.addLine(to: CGPoint(x: 342, y: y))
    ctx.addLine(to: CGPoint(x: 316, y: y - 16))
    ctx.strokePath()

    // Caption, clear of the icon labels Finder draws for itself.
    let caption = "Drag Flare into Applications"
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0.62, green: 0.29, blue: 0.13, alpha: 1),
    ]
    let text = NSAttributedString(string: caption, attributes: attrs)
    let size = text.size()
    text.draw(at: NSPoint(x: (W - size.width) / 2, y: flip(310)))
}

func render(scale: CGFloat, to path: String) {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else {
        FileHandle.standardError.write(Data("could not allocate bitmap\n".utf8))
        exit(1)
    }
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(into: NSGraphicsContext.current!.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try! png.write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments[1]
render(scale: 1, to: "\(out)/background.png")
render(scale: 2, to: "\(out)/background@2x.png")
print("rendered \(out)/background.png and @2x")
