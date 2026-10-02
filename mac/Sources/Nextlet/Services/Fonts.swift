import AppKit
import CoreText
import SwiftUI

/// Registers the bundled brand fonts (Bricolage Grotesque, Geist, Geist Mono) for this
/// process and hands out SwiftUI fonts, falling back to the system fonts if missing.
@MainActor
enum FontBook {
    private static var hasGeist = false
    private static var hasGeistMono = false
    private static var bricolage: CTFontDescriptor?
    private static var cache: [String: Font] = [:]

    static func register(from directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("Fonts")) {
        guard let directory else { return }
        func load(_ file: String) -> [CTFontDescriptor] {
            let url = directory.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            return CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
        }
        hasGeist = !load("geist-latin-wght-normal.woff2").isEmpty
        hasGeistMono = !load("geist-mono-latin-wght-normal.woff2").isEmpty
        bricolage = load("bricolage-grotesque-latin-opsz-normal.woff2").first
        cache.removeAll()
    }

    private static func axisValue(_ weight: Font.Weight) -> CGFloat {
        switch weight {
        case .medium: return 500
        case .semibold: return 600
        case .bold: return 700
        case .heavy, .black: return 800
        default: return 400
        }
    }

    private static func instanceName(_ weight: Font.Weight) -> String {
        switch weight {
        case .medium: return "Medium"
        case .semibold: return "SemiBold"
        case .bold: return "Bold"
        case .heavy, .black: return "ExtraBold"
        case .light: return "Light"
        default: return "Regular"
        }
    }

    /// Bricolage Grotesque, for titles.
    static func display(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        let key = "d\(size)\(axisValue(weight))"
        if let cached = cache[key] { return cached }
        let font: Font
        if let bricolage {
            let wght = NSNumber(value: 0x7767_6874) // 'wght'
            let descriptor = CTFontDescriptorCreateCopyWithVariation(bricolage, wght, axisValue(weight))
            font = Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
        } else {
            font = .system(size: size, weight: weight)
        }
        cache[key] = font
        return font
    }

    /// Geist, for everything else.
    static func sans(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        hasGeist ? .custom("Geist-\(instanceName(weight))", size: size) : .system(size: size, weight: weight)
    }

    /// Geist as an AppKit font, for the AppKit text views.
    static func sansNSFont(_ size: CGFloat) -> NSFont {
        (hasGeist ? NSFont(name: "Geist-Regular", size: size) : nil) ?? .systemFont(ofSize: size)
    }

    /// Geist Mono, for small labels, counts and the timer.
    static func mono(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        hasGeistMono ? .custom("GeistMono-\(instanceName(weight))", size: size) : .system(size: size, weight: weight, design: .monospaced)
    }
}
