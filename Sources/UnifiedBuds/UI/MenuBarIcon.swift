import AppKit

/// Which glyph the menu bar shows, chosen in the settings.
enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    /// Three bars over a smile arc, matching the app icon.
    case appLogo = "App logo"
    /// The system earbuds symbol.
    case earbuds = "Earbuds"
    /// Neckband earphones symbol (e.g. realme Buds Wireless).
    case neckband = "Neckband"
    /// Over-ear headphones symbol.
    case headphones = "Headphones"
    /// Waveform audio symbol.
    case waveform = "Waveform"

    var id: String { rawValue }
}

/// Draws the menu bar glyph as a template image so it follows the menu bar's
/// light/dark appearance. The glyph changes with the earbuds' state.
enum MenuBarIcon {
    enum Status {
        case disconnected
        case connected
        case ancOn
        case transparency
        case adaptive
        case off
        case charging
    }

    private static let height: CGFloat = 18
    private static let glyphWidth: CGFloat = 18
    /// Transparency adds sound waves on both sides.
    private static let wavesWidth: CGFloat = 28

    static func image(for status: Status, style: MenuBarIconStyle = .appLogo) -> NSImage {
        let width = status == .transparency ? wavesWidth : glyphWidth
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setAlpha(status == .disconnected ? 0.45 : 1)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineCap(.round)
            let centerX = width / 2
            switch style {
            case .appLogo: drawLogo(ctx, centerX: centerX)
            case .earbuds: drawEarbudsSymbol(centerX: centerX)
            case .neckband: drawNeckbandSymbol(centerX: centerX)
            case .headphones: drawHeadphonesSymbol(centerX: centerX)
            case .waveform: drawWaveformSymbol(centerX: centerX)
            }
            switch status {
            case .transparency:
                drawWaves(ctx, centerX: centerX)
            case .ancOn:
                drawBadge(ctx, centerX: centerX) { drawShield(ctx, center: $0) }
            case .adaptive:
                drawBadge(ctx, centerX: centerX) { drawLetterA(ctx, center: $0) }
            case .off:
                drawBadge(ctx, centerX: centerX) { drawSlashCircle(ctx, center: $0) }
            case .charging:
                if style == .appLogo {
                    drawBolt(ctx, centerX: centerX)
                } else {
                    drawBadge(ctx, centerX: centerX) { drawSmallBolt(ctx, center: $0) }
                }
            case .connected, .disconnected:
                break
            }
            ctx.endTransparencyLayer()
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: Base glyphs

    private static func pill(_ ctx: CGContext, centerX: CGFloat, top: CGFloat, bottom: CGFloat, width: CGFloat) {
        let rect = CGRect(x: centerX - width / 2, y: bottom, width: width, height: top - bottom)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: width / 2, cornerHeight: width / 2, transform: nil))
        ctx.fillPath()
    }

    /// Tall centre bar, two shorter side bars, and the lower half-circle beneath them.
    private static func drawLogo(_ ctx: CGContext, centerX: CGFloat) {
        pill(ctx, centerX: centerX, top: 17, bottom: 3.3, width: 2.4)
        pill(ctx, centerX: centerX - 3.6, top: 13.4, bottom: 6.1, width: 2.4)
        pill(ctx, centerX: centerX + 3.6, top: 13.4, bottom: 6.1, width: 2.4)
        ctx.setLineWidth(1.5)
        ctx.addArc(center: CGPoint(x: centerX, y: 9.2), radius: 7.4, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
        ctx.strokePath()
    }

    private static func drawEarbudsSymbol(centerX: CGFloat) {
        // Palette with one colour flattens the symbol's two-tone layers into a solid glyph.
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.black]))
        guard let symbol = NSImage(systemSymbolName: "earbuds", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let size = symbol.size
        symbol.draw(in: NSRect(x: centerX - size.width / 2, y: (height - size.height) / 2,
                               width: size.width, height: size.height))
    }

    private static func drawNeckbandSymbol(centerX: CGFloat) {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.black]))
        let name = "beats.earphones"
        if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let size = symbol.size
            symbol.draw(in: NSRect(x: centerX - size.width / 2, y: (height - size.height) / 2,
                                   width: size.width, height: size.height))
        } else {
            drawEarbudsSymbol(centerX: centerX)
        }
    }

    private static func drawHeadphonesSymbol(centerX: CGFloat) {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.black]))
        if let symbol = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let size = symbol.size
            symbol.draw(in: NSRect(x: centerX - size.width / 2, y: (height - size.height) / 2,
                                   width: size.width, height: size.height))
        } else {
            drawEarbudsSymbol(centerX: centerX)
        }
    }

    private static func drawWaveformSymbol(centerX: CGFloat) {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.black]))
        if let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let size = symbol.size
            symbol.draw(in: NSRect(x: centerX - size.width / 2, y: (height - size.height) / 2,
                                   width: size.width, height: size.height))
        } else {
            drawEarbudsSymbol(centerX: centerX)
        }
    }

    /// Selects the appropriate device-specific icon based on form factor and product name.
    static func symbolForDevice(name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("neckband") || lower.contains("wireless") || lower.contains("flex") {
            return "beats.earphones"
        }
        if lower.contains("wh-") || lower.contains("space q") || lower.contains("headphones") || lower.contains("life q") || lower.contains("max") {
            return "headphones"
        }
        return "earbuds"
    }

    // MARK: Status overlays

    /// Two sound-wave arcs on each side, centred on the glyph.
    private static func drawWaves(_ ctx: CGContext, centerX: CGFloat) {
        let center = CGPoint(x: centerX, y: 9.2)
        ctx.setLineWidth(1.5)
        for (radius, spread) in [(CGFloat(10.2), CGFloat(0.48)), (12.6, 0.55)] {
            ctx.addArc(center: center, radius: radius, startAngle: -spread, endAngle: spread, clockwise: false)
            ctx.strokePath()
            ctx.addArc(center: center, radius: radius, startAngle: .pi - spread, endAngle: .pi + spread, clockwise: false)
            ctx.strokePath()
        }
    }

    /// A lightning bolt over the bars, with a gap cut around it so it stays legible.
    private static func drawBolt(_ ctx: CGContext, centerX: CGFloat) {
        let points: [(CGFloat, CGFloat)] = [(1.3, 14.9), (-2.8, 8.4), (-0.35, 8.4), (-1.5, 3.7), (2.7, 10), (0.2, 10)]
        let bolt = CGMutablePath()
        bolt.addLines(between: points.map { CGPoint(x: centerX + $0.0, y: $0.1) })
        bolt.closeSubpath()

        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.setLineWidth(2.2)
        ctx.setLineJoin(.round)
        ctx.addPath(bolt)
        ctx.drawPath(using: .fillStroke)
        ctx.restoreGState()

        ctx.addPath(bolt)
        ctx.fillPath()
    }

    /// A filled circle at the bottom right, cut out of the glyph, with a mark knocked out of it.
    private static func drawBadge(_ ctx: CGContext, centerX: CGFloat, mark: (CGPoint) -> Void) {
        let center = CGPoint(x: centerX + 5.2, y: 4.3)
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.addEllipse(in: CGRect(x: center.x - 4.5, y: center.y - 4.5, width: 9, height: 9))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addEllipse(in: CGRect(x: center.x - 3.7, y: center.y - 3.7, width: 7.4, height: 7.4))
        ctx.fillPath()
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        mark(center)
        ctx.restoreGState()
    }

    private static func drawLetterA(_ ctx: CGContext, center: CGPoint) {
        ctx.setLineWidth(1.2)
        ctx.setLineJoin(.round)
        ctx.move(to: CGPoint(x: center.x - 1.8, y: center.y - 2))
        ctx.addLine(to: CGPoint(x: center.x, y: center.y + 2.2))
        ctx.addLine(to: CGPoint(x: center.x + 1.8, y: center.y - 2))
        ctx.move(to: CGPoint(x: center.x - 1, y: center.y - 0.5))
        ctx.addLine(to: CGPoint(x: center.x + 1, y: center.y - 0.5))
        ctx.strokePath()
    }

    private static func drawShield(_ ctx: CGContext, center: CGPoint) {
        // Subtle solid circle in badge for active noise cancellation
        ctx.addEllipse(in: CGRect(x: center.x - 1.8, y: center.y - 1.8, width: 3.6, height: 3.6))
        ctx.fillPath()
    }

    private static func drawSlashCircle(_ ctx: CGContext, center: CGPoint) {
        ctx.setLineWidth(1.1)
        ctx.move(to: CGPoint(x: center.x - 1.5, y: center.y - 1.5))
        ctx.addLine(to: CGPoint(x: center.x + 1.5, y: center.y + 1.5))
        ctx.strokePath()
    }

    private static func drawSmallBolt(_ ctx: CGContext, center: CGPoint) {
        let points: [(CGFloat, CGFloat)] = [(0.8, 2.7), (-1.6, -0.2), (-0.1, -0.2), (-0.8, -2.7), (1.6, 0.4), (0.1, 0.4)]
        ctx.addLines(between: points.map { CGPoint(x: center.x + $0.0, y: center.y + $0.1) })
        ctx.closePath()
        ctx.fillPath()
    }
}
