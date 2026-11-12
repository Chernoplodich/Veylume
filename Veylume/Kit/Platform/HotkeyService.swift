import AppKit
import Carbon
import os
import VeylumeCore

struct PhysicalKeyState: Sendable {
    var read: @Sendable (CGEventSourceStateID, CGKeyCode) -> Bool = { CGEventSource.keyState($0, key: $1) }
    func isDown(_ key: CGKeyCode) -> Bool {
        // The session table is downstream of our suppressing session tap. A
        // consumed keyDown need not appear there. HID state precedes the tap.
        read(.hidSystemState, key)
    }
}

final class HotkeyService: @unchecked Sendable {
    static let syntheticTag: Int64 = 0x5645594C554D45
    private let state = OSAllocatedUnfairLock(initialState: ShortcutRouter())
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var onAction: (@Sendable (RecordingShortcutAction) -> Void)?
    var onLost: (@Sendable () -> Void)?
    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    func configure(hold: Shortcut?, toggle: Shortcut?, paused: Bool, active: Bool) {
        state.withLock { $0.configure(hold: hold, toggle: toggle, paused: paused, active: active) }
    }
    func start() -> Bool {
        if isRunning { return true }
        stop()
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<HotkeyService>.fromOpaque(pointer).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                _ = service.state.withLock { $0.consume(.reset) }; service.onLost?()
                return Unmanaged.passUnretained(event)
            }
            guard event.getIntegerValueField(.eventSourceUserData) != HotkeyService.syntheticTag else { return Unmanaged.passUnretained(event) }
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let signal: KeySignal
            if type == .keyDown && code == 53 { signal = .escape }
            else if type == .keyDown { signal = .down(code, event.flags.rawValue, repeatKey: event.getIntegerValueField(.keyboardEventAutorepeat) != 0) }
            else if type == .keyUp { signal = .up(code) }
            else { signal = .flags(event.flags.rawValue) }
            let decision = service.state.withLock { $0.consume(signal) }
            if let action = decision.action { service.onAction?(action) }
            return decision.suppress ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap; source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes); CGEvent.tapEnable(tap: tap, enable: true); return true
    }
    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }
    func reenable() { if let tap { CGEvent.tapEnable(tap: tap, enable: true) } }
    static func display(_ shortcut: Shortcut?) -> String {
        guard let shortcut else { return I18n.tr("Назначить…", "Assign…") }
        let symbols: [(mask: UInt64, text: String)] = [
            (1 << 18, "⌃"), (1 << 19, "⌥"), (1 << 17, "⇧"), (1 << 20, "⌘"), (1 << 23, "fn ")
        ]
        var modifiers = ""
        for symbol in symbols where shortcut.modifiers & symbol.mask != 0 { modifiers += symbol.text }
        var name = "Key \(shortcut.keyCode)"
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(), let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
            let layout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
            var dead: UInt32 = 0, length = 0; var chars = [UniChar](repeating: 0, count: 8)
            let status = UCKeyTranslate(layout, shortcut.keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
            if status == noErr, length > 0 { name = String(utf16CodeUnits: chars, count: length).uppercased() }
        }
        if shortcut.keyCode == 49 { name = "Space" }
        return modifiers + name
    }
}
