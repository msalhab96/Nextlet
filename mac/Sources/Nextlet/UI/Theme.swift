import AppKit
import NextletCore
import SwiftUI

/// In this SDK `@State` is a macro, and the Command Line Tools don't ship its plugin.
/// `@ViewState` is the very same property wrapper, reached through a type alias.
typealias ViewState = SwiftUI.State

/// The Nextlet palette from the design, with a dark counterpart for every colour.
/// Each colour follows the appearance of the window it is drawn in, so the whole app
/// switches between light and dark on its own.
enum Palette {
    // Text
    static let ink = adaptive(0x15171C, 0xECEDF0)
    static let ink2 = adaptive(0x2A2C33, 0xD6D8DE)
    static let graphite = adaptive(0x4A4D57, 0xA9ACB6)
    /// Secondary text that still reads on the sidebar's darker ground.
    static let muted = adaptive(0x5A5D66, 0x8E919B)
    static let faint = adaptive(0xA9ABB3, 0x60636D)

    // Grounds, from the sidebar (furthest back) to cards (nearest)
    static let sidebar = adaptive(0xECECE6, 0x121316)
    static let paper = adaptive(0xF5F5F0, 0x111215)
    static let paper2 = adaptive(0xFAFAF7, 0x17181C)
    static let surface = adaptive(0xFFFFFF, 0x1C1D22)
    /// The project pill and other small filled chips.
    static let chip = adaptive(0xEFEFE9, 0x27292F)
    /// The strip at the bottom of quick capture.
    static let well = adaptive(0xF0F0EA, 0x222429)
    static let sidebarHover = adaptive(0xFFFFFF, 0xFFFFFF, lightAlpha: 0.55, darkAlpha: 0.06)

    // Lines
    static let line = adaptive(0xE4E4DD, 0x2D2F35)
    static let line2 = adaptive(0xE1E1DA, 0x34363D)
    static let hairline = adaptive(0xEDEDE8, 0x26282D)
    static let dashed = adaptive(0xDCDCD4, 0x3B3D45)
    static let cardBorder = adaptive(0xE8E8E2, 0x2D2F35)
    static let panelBorder = adaptive(0x000000, 0xFFFFFF, lightAlpha: 0.12, darkAlpha: 0.12)

    // Accents
    static let indigo = adaptive(0x3B3BD6, 0x6B6BF3)
    static let indigoInk = adaptive(0x2A2AA8, 0xA8A8FF)
    static let indigoSoft = adaptive(0xE8E8FB, 0x262852)
    static let marker = Color(hex: 0xFFD84D)
    /// Text and icons on the yellow marker, dark in both modes.
    static let onMarker = Color(hex: 0x15171C)
    static let carryBackground = adaptive(0xFDEBDD, 0x3A2617)
    static let carryText = adaptive(0x9A3412, 0xFDBA8C)
    static let danger = adaptive(0xB42318, 0xFF7B6B)

    /// The dark cards (Next up, focus, toasts). They stay dark, lifted a little off a dark ground.
    static let night = adaptive(0x15171C, 0x26282F)
    /// A faint edge that keeps the dark cards apart from a dark ground.
    static let nightEdge = adaptive(0xFFFFFF, 0xFFFFFF, lightAlpha: 0, darkAlpha: 0.08)
    static let onDark = Color.white
    static let onDark2 = Color(hex: 0xC9CAD1)

    /// Primary buttons: black on light, white on dark.
    static let primary = adaptive(0x15171C, 0xECEDF0)
    static let primaryHover = adaptive(0x262931, 0xFFFFFF)
    static let primaryPressed = adaptive(0x30333B, 0xD2D4DA)
    static let onPrimary = adaptive(0xFFFFFF, 0x15171C)
    static let onPrimary2 = adaptive(0xC9CAD1, 0x5A5D66)
    /// The play icon on a primary button.
    static let primaryAccent = adaptive(0xFFD84D, 0xB7791F)

    static let desktop = Color(hex: 0x3A3F4A)
    static let noProject = adaptive(0xA9ABB3, 0x6C6F79)
    static let priority = [adaptive(0x8A8D96, 0x8E919B), adaptive(0xC2410C, 0xFB8C50), adaptive(0x3B3BD6, 0x8C8CFF), adaptive(0x8A8D96, 0x8E919B)]
    static let projectColors = ["#3B3BD6", "#0F766E", "#C2410C", "#A16207", "#7C3AED", "#BE185D", "#0369A1", "#4D7C0F"]

    /// A colour with a light and a dark value, resolved for whichever appearance it's drawn in.
    static func adaptive(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark, alpha: darkAlpha)
                : NSColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// A project colour like "#3B3BD6".
    init(projectHex: String?) {
        guard let projectHex, projectHex.hasPrefix("#"), let value = UInt32(projectHex.dropFirst(), radix: 16) else {
            self = Palette.noProject
            return
        }
        self.init(hex: value)
    }

    /// Mixed with white, for project dots on the dark Next up card.
    func lightened(_ amount: Double) -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let mix = { (channel: CGFloat) in Double(channel) + (1 - Double(channel)) * amount }
        return Color(.sRGB, red: mix(base.redComponent), green: mix(base.greenComponent), blue: mix(base.blueComponent))
    }
}

/// Bricolage Grotesque for titles, Geist for text, Geist Mono for labels.
@MainActor
enum Typo {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { FontBook.display(size, weight) }
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { FontBook.sans(size, weight) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { FontBook.mono(size, weight) }
}

/// A colour swatch image that keeps its colour inside menus.
func swatchImage(_ hex: String?, size: CGFloat = 10) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        NSColor(Color(projectHex: hex)).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: size * 0.3, yRadius: size * 0.3).fill()
        return true
    }
    image.isTemplate = false
    return image
}

/// The Nextlet mark (a chevron and a dot) as a menu bar template image.
func menuBarMark() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: 5.5, y: 4.5))
        chevron.line(to: NSPoint(x: 10, y: 9))
        chevron.line(to: NSPoint(x: 5.5, y: 13.5))
        chevron.lineWidth = 2.2
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        NSColor.black.setStroke()
        chevron.stroke()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 11.8, y: 7.2, width: 3.6, height: 3.6)).fill()
        return true
    }
    image.isTemplate = true
    return image
}
