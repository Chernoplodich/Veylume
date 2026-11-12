import Foundation

public struct Shortcut: Codable, Equatable, Sendable {
    public let keyCode: UInt16
    /// CGEventFlags device-independent mask: shift/control/option/command/fn.
    public let modifiers: UInt64
    public init(keyCode: UInt16, modifiers: UInt64) { self.keyCode = keyCode; self.modifiers = modifiers & Self.modifierMask }
    public static let modifierMask: UInt64 = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20) | (1 << 23)
}
public enum KeySignal: Sendable { case down(UInt16, UInt64, repeatKey: Bool), up(UInt16), flags(UInt64), escape, reset }
public enum KeyAction: Equatable, Sendable { case start, stop, cancel }
public struct KeyDecision: Sendable { public let suppress: Bool; public let action: KeyAction? }

/// Reducer has no I/O and stores only the configured key's physical state.
public struct ShortcutReducer: Sendable {
    public var shortcut: Shortcut?
    public var mode: RecordingMode = .hold
    public var enabled = true
    public var active = false
    private var baseDown = false
    private var blockedUntilRelease = false
    private var consumedDown = false
    public init() {}

    public mutating func consume(_ signal: KeySignal) -> KeyDecision {
        var action: KeyAction?
        var suppress = false
        switch signal {
        case .reset:
            blockedUntilRelease = baseDown
            if active { action = .cancel }
        case .escape:
            if active { suppress = true; blockedUntilRelease = baseDown; action = .cancel }
        case let .down(code, flags, repeatKey):
            guard enabled, let shortcut, code == shortcut.keyCode else { break }
            if consumedDown { suppress = true }
            guard !repeatKey, !baseDown else { break }
            baseDown = true
            guard !blockedUntilRelease, flags & Shortcut.modifierMask == shortcut.modifiers else { break }
            consumedDown = true; suppress = true
            if active { action = mode == .toggle ? .stop : nil }
            else { active = true; action = .start }
        case let .up(code):
            guard let shortcut, code == shortcut.keyCode else { break }
            suppress = consumedDown
            if consumedDown, active, mode == .hold { action = .stop }
            baseDown = false; blockedUntilRelease = false; consumedDown = false
        case let .flags(flags):
            if let shortcut, active, mode == .hold, consumedDown, flags & shortcut.modifiers != shortcut.modifiers { action = .stop }
        }
        return KeyDecision(suppress: suppress, action: action)
    }
}
