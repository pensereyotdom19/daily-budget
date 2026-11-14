import AppKit
import CoreGraphics
import CoreText
// Draws the Daily Budget app icons in the "Calm" style (1024×1024, opaque):
//   swift tools/make_icon.swift DailyBudget/Assets.xcassets/AppIcon.appiconset
// writes AppIcon.png (light), AppIcon-Dark.png (dark) and AppIcon-Tinted.png (grey, for tinted home screens).
//
// The picture: a "$" inside a ring that is three-quarters full, like today's money left.
// Plain solid background, one font (SF Pro), no lines or textures.

let size = 1024
let folder = CommandLine.arguments[1]
let S = CGFloat(size)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func draw(background: UInt32, ring: UInt32, track: CGFloat, symbol: UInt32, to name: String) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(rgb(background)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))

    let center = CGPoint(x: S / 2, y: S / 2)
    let radius = S * 0.30
    ctx.setLineWidth(S * 0.07)
    ctx.setLineCap(.round)

    // The faint full ring underneath.
    ctx.setStrokeColor(rgb(ring, track))
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Three quarters of it, clockwise from the top (CG angles go counter-clockwise from the right).
    ctx.setStrokeColor(rgb(ring))
    ctx.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: .pi / 2 - .pi * 1.5, clockwise: true)
    ctx.strokePath()

    // "$" in the middle.
    let font = NSFont.systemFont(ofSize: S * 0.34, weight: .semibold)
    let attr = NSAttributedString(string: "$", attributes: [.font: font, .foregroundColor: NSColor(cgColor: rgb(symbol))!])
    let line = CTLineCreateWithAttributedString(attr)
    let b = CTLineGetImageBounds(line, ctx)
    ctx.textPosition = CGPoint(x: center.x - b.midX, y: center.y - b.midY)
    CTLineDraw(line, ctx)

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(folder)/\(name)"))
    print("wrote \(name)")
}

// Light: forest green with white. Dark: navy with powder blue ring and a sunflower "$".
draw(background: 0x2E5E3E, ring: 0xFFFFFF, track: 0.22, symbol: 0xFFFFFF, to: "AppIcon.png")
draw(background: 0x0F1A2E, ring: 0xA9CBE8, track: 0.18, symbol: 0xF5C542, to: "AppIcon-Dark.png")
draw(background: 0x000000, ring: 0xF2F2F2, track: 0.2, symbol: 0xF2F2F2, to: "AppIcon-Tinted.png")
