import AppKit
import Carbon.HIToolbox
import Foundation
import Observation

/// How Nextlet looks: like the rest of the Mac, or always light or dark.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// The AppKit appearance; nil follows the system.
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// The global shortcut for quick capture.
enum HotKeyPreset: String, CaseIterable, Identifiable {
    case optionSpace
    case controlOptionSpace
    case shiftCommandSpace
    case optionCommandN
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .optionSpace: return "⌥ Space"
        case .controlOptionSpace: return "⌃⌥ Space"
        case .shiftCommandSpace: return "⇧⌘ Space"
        case .optionCommandN: return "⌥⌘ N"
        case .off: return "Off"
        }
    }

    /// Carbon virtual key code and modifier mask, or nil when turned off.
    var carbon: (keyCode: UInt32, modifiers: UInt32)? {
        switch self {
        case .optionSpace: return (UInt32(kVK_Space), UInt32(optionKey))
        case .controlOptionSpace: return (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        case .shiftCommandSpace: return (UInt32(kVK_Space), UInt32(shiftKey | cmdKey))
        case .optionCommandN: return (UInt32(kVK_ANSI_N), UInt32(optionKey | cmdKey))
        case .off: return nil
        }
    }
}

/// Preferences, kept in UserDefaults.
@MainActor @Observable
final class AppSettings {
    static let defaultServer = "http://localhost:8080"

    private enum Key {
        static let server = "serverAddress"
        static let token = "sessionToken"
        static let hotKey = "quickCaptureHotKey"
        static let focusMinutes = "focusMinutes"
        static let floatingTimer = "showFloatingTimer"
        static let sound = "playSoundWhenDone"
        static let appearance = "appearance"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var serverAddress: String { didSet { defaults.set(serverAddress, forKey: Key.server) } }
    /// Session token from signing in, sent as a Bearer header. Not the password.
    var sessionToken: String? { didSet { defaults.set(sessionToken, forKey: Key.token) } }
    var hotKey: HotKeyPreset { didSet { defaults.set(hotKey.rawValue, forKey: Key.hotKey) } }
    /// Session length when a task has no estimate.
    var focusMinutes: Int { didSet { defaults.set(focusMinutes, forKey: Key.focusMinutes) } }
    var showFloatingTimer: Bool { didSet { defaults.set(showFloatingTimer, forKey: Key.floatingTimer) } }
    var playSound: Bool { didSet { defaults.set(playSound, forKey: Key.sound) } }
    var appearance: AppearanceMode {
        didSet {
            defaults.set(appearance.rawValue, forKey: Key.appearance)
            applyAppearance()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        serverAddress = defaults.string(forKey: Key.server) ?? AppSettings.defaultServer
        sessionToken = defaults.string(forKey: Key.token)
        hotKey = HotKeyPreset(rawValue: defaults.string(forKey: Key.hotKey) ?? "") ?? .optionSpace
        let minutes = defaults.integer(forKey: Key.focusMinutes)
        focusMinutes = minutes > 0 ? minutes : 25
        showFloatingTimer = defaults.object(forKey: Key.floatingTimer) as? Bool ?? true
        playSound = defaults.object(forKey: Key.sound) as? Bool ?? true
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
    }

    /// Every window, menu and panel follows the app's appearance.
    func applyAppearance() {
        NSApp.appearance = appearance.appearance
    }

    /// The server address as a URL, accepting "localhost:8080" without a scheme.
    var serverURL: URL? {
        AppSettings.url(from: serverAddress)
    }

    static func url(from address: String) -> URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://\(text)" }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else {
            return nil
        }
        return url
    }
}
