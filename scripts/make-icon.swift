#!/usr/bin/env swift
// Renders Resources/AppIcon.icns: three sound bars over a smile arc on a dark squircle.
// Run: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

/// Superellipse ("squircle") matching the macOS icon outline.
func squircle(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n: CGFloat = 4
    for step in 0...360 {
        let t = CGFloat(step) / 360 * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + rect.width / 2 * copysign(pow(abs(c), 2 / n), c)
        let y = rect.midY + rect.height / 2 * copysign(pow(abs(s), 2 / n), s)
        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha).cgColor
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)

    // macOS icon grid: 824pt body inset 100pt, with a soft drop shadow.
    let shape = squircle(in: CGRect(x: 100, y: 100, width: 824, height: 824))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: color(0x000000, 0.4))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x1B1C1F))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.drawLinearGradient(gradient([color(0x3A3D43), color(0x232428), color(0x16171A)]),
                           start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])

    let white = gradient([color(0xF7F7F9), color(0xDDDEE3)])
    func pill(_ rect: CGRect) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: rect.width / 2, cornerHeight: rect.width / 2, transform: nil)
    }
    func fill(_ path: CGPath, glow: CGColor? = nil) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: color(0x000000, 0.45))
        if let glow { ctx.setShadow(offset: .zero, blur: 36, color: glow) }
        ctx.addPath(path)
        ctx.setFillColor(color(0xEDEDF0))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let box = path.boundingBox
        ctx.drawLinearGradient(white, start: CGPoint(x: 0, y: box.maxY), end: CGPoint(x: 0, y: box.minY), options: [])
        ctx.restoreGState()
    }

    // Smile arc: lower half of a circle with round caps.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: color(0x000000, 0.45))
    ctx.setLineWidth(19)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(color(0xE6E7EA))
    ctx.addArc(center: CGPoint(x: 512, y: 516), radius: 193, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // Two side bars and the tall centre bar with a warm glow and an orange core.
    let side = CGSize(width: 57, height: 184)
    fill(pill(CGRect(x: 512 - 92 - side.width / 2, y: 531 - side.height / 2, width: side.width, height: side.height)))
    fill(pill(CGRect(x: 512 + 92 - side.width / 2, y: 531 - side.height / 2, width: side.width, height: side.height)))
    let centre = CGRect(x: 512 - 29, y: 542 - 174, width: 58, height: 348)
    fill(pill(centre), glow: color(0xFF6A45, 0.75))
    let core = CGRect(x: 512 - 6, y: centre.minY + 21, width: 12, height: centre.height - 42)
    ctx.saveGState()
    ctx.addPath(pill(core))
    ctx.clip()
    ctx.drawLinearGradient(gradient([color(0xF48A6C), color(0xE8604A)]),
                           start: CGPoint(x: 0, y: core.maxY), end: CGPoint(x: 0, y: core.minY), options: [])
    ctx.restoreGState()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try! iconutil.run()
iconutil.waitUntilExit()
print("Wrote \(output.path)")
