import AppKit
import CoreGraphics
import CoreText
// Draws the Daily Budget app icons in the "Ledger" style (1024×1024, opaque):
//   swift tools/make_icon.swift DailyBudget/Assets.xcassets/AppIcon.appiconset
// writes AppIcon.png (paper), AppIcon-Dark.png (night) and AppIcon-Tinted.png (grey, for tinted home screens).

let size = 1024
let folder = CommandLine.arguments[1]
let S = CGFloat(size)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func draw(paper: UInt32, ink: UInt32, accent: UInt32, rule: UInt32, to name: String) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(rgb(paper)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))

    // Faint ledger lines across the page (CG origin is bottom-left).
    ctx.setStrokeColor(rgb(rule)); ctx.setLineWidth(S * 0.006)
    for i in 1...6 {
        let y = S * (0.14 + CGFloat(i) * 0.12)
        ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: S, y: y))
    }
    ctx.strokePath()
    // A red margin line, like a ledger page.
    ctx.setStrokeColor(rgb(accent, 0.55)); ctx.setLineWidth(S * 0.008)
    ctx.move(to: CGPoint(x: S * 0.2, y: 0)); ctx.addLine(to: CGPoint(x: S * 0.2, y: S)); ctx.strokePath()

    // A big serif "$" in ink.
    let base = NSFont.systemFont(ofSize: S * 0.56, weight: .semibold)
    let font = base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: S * 0.56) } ?? base
    let attr = NSAttributedString(string: "$", attributes: [.font: font, .foregroundColor: NSColor(cgColor: rgb(ink))!])
    let line = CTLineCreateWithAttributedString(attr)
    let b = CTLineGetImageBounds(line, ctx)
    ctx.textPosition = CGPoint(x: S * 0.56 - b.midX, y: S * 0.55 - b.midY)
    CTLineDraw(line, ctx)

    // A double rule under it, like a total.
    ctx.setStrokeColor(rgb(ink)); ctx.setLineWidth(S * 0.016)
    for y in [S * 0.20, S * 0.165] {
        ctx.move(to: CGPoint(x: S * 0.3, y: y)); ctx.addLine(to: CGPoint(x: S * 0.82, y: y))
    }
    ctx.strokePath()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(folder)/\(name)"))
    print("wrote \(name)")
}

draw(paper: 0xF7F3EA, ink: 0x1E2A3A, accent: 0x8A2E2E, rule: 0xE2D9C6, to: "AppIcon.png")
draw(paper: 0x121A24, ink: 0xEFE7D6, accent: 0xE59A86, rule: 0x223040, to: "AppIcon-Dark.png")
draw(paper: 0x000000, ink: 0xF2F2F2, accent: 0x8C8C8C, rule: 0x262626, to: "AppIcon-Tinted.png")
