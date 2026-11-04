import AppKit
// Regenerate: swift tools/make_icon.swift DailyBudget/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import CoreText

// Draws the Daily Budget app icon (1024x1024, opaque) in the app's theme.
let size = 1024
let out = CommandLine.arguments[1]

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let S = CGFloat(size)

// Background: Theme.base
ctx.setFillColor(rgb(0x040509)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))

// Soft glows (violet top-left, pink right, teal bottom-left). CG origin is bottom-left.
func glow(_ hex: UInt32, _ alpha: CGFloat, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
    let g = CGGradient(colorsSpace: cs, colors: [rgb(hex, alpha), rgb(hex, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                           endCenter: CGPoint(x: cx, y: cy), endRadius: r, options: [])
}
glow(0x7B5CFF, 0.55, S * 0.18, S * 0.86, S * 0.62)
glow(0xFF5E8A, 0.30, S * 0.92, S * 0.55, S * 0.50)
glow(0x12B5A2, 0.45, S * 0.20, S * 0.08, S * 0.62)

let center = CGPoint(x: S / 2, y: S / 2)
let radius = S * 0.30
let line = S * 0.085

// Ring track
ctx.setLineWidth(line); ctx.setLineCap(.round)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.16))
ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.strokePath()

// Progress arc (about 3/4 left), mint -> sky gradient, starting at 12 o'clock going clockwise.
let start = CGFloat.pi / 2
let end = start - CGFloat.pi * 2 * 0.75
let arc = CGMutablePath()
arc.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
let stroked = arc.copy(strokingWithWidth: line, lineCap: .round, lineJoin: .round, miterLimit: 10)
ctx.saveGState()
ctx.addPath(stroked); ctx.clip()
let ringGrad = CGGradient(colorsSpace: cs, colors: [rgb(0x7CF2A0), rgb(0x5FD0FF)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(ringGrad, start: CGPoint(x: S * 0.2, y: S * 0.8), end: CGPoint(x: S * 0.8, y: S * 0.2), options: [])
ctx.restoreGState()

// "$" in SF Rounded heavy, centered
let base = NSFont.systemFont(ofSize: S * 0.34, weight: .heavy)
let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: S * 0.34) } ?? base
let attr = NSAttributedString(string: "$", attributes: [.font: font, .foregroundColor: NSColor.white])
let ctLine = CTLineCreateWithAttributedString(attr)
let bounds = CTLineGetImageBounds(ctLine, ctx)
ctx.textPosition = CGPoint(x: center.x - bounds.midX, y: center.y - bounds.midY)
CTLineDraw(ctLine, ctx)

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
