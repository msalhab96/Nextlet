import Carbon.HIToolbox
import Foundation

/// A system-wide shortcut (⌥Space by default) that opens quick capture from any app.
/// Uses Carbon's RegisterEventHotKey, which needs no Accessibility permission.
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    var onPress: (() -> Void)?
    private(set) var registeredPreset: HotKeyPreset?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// Returns false when the shortcut is taken by another app.
    @discardableResult
    func register(_ preset: HotKeyPreset) -> Bool {
        unregister()
        guard let (keyCode, modifiers) = preset.carbon else {
            registeredPreset = nil
            return true
        }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x4E58_4C54), id: 1) // 'NXLT'
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        registeredPreset = status == noErr ? preset : nil
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        registeredPreset = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.onPress?() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }
}
