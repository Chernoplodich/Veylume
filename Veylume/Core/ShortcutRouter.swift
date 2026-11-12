import Foundation

public enum RecordingShortcutAction: Equatable, Sendable {
    case start(RecordingMode), stop, cancel
}
public struct RecordingShortcutDecision: Sendable {
    public let suppress: Bool
    public let action: RecordingShortcutAction?
}

/// Two independent bindings share one recording. The binding that starts it
/// owns its stop gesture; the other binding cannot switch its mode mid-session.
public struct ShortcutRouter: Sendable {
    private var hold = ShortcutReducer(), toggle = ShortcutReducer()
    private var owner: RecordingMode?
    private var active = false
    public init() {}
    public mutating func configure(hold holdKey: Shortcut?, toggle toggleKey: Shortcut?, paused: Bool, active: Bool) {
        hold.shortcut = holdKey; hold.mode = .hold; hold.enabled = !paused
        toggle.shortcut = toggleKey == holdKey ? nil : toggleKey; toggle.mode = .toggle; toggle.enabled = !paused
        self.active = active
        if !active { owner = nil }
    }
    public mutating func consume(_ signal: KeySignal) -> RecordingShortcutDecision {
        hold.active = active; toggle.active = active
        let h = hold.consume(signal), t = toggle.consume(signal)
        var action: RecordingShortcutAction?
        if h.action == .cancel || t.action == .cancel { action = .cancel }
        else if !active {
            if h.action == .start { owner = .hold; active = true; action = .start(.hold) }
            else if t.action == .start { owner = .toggle; active = true; action = .start(.toggle) }
        } else if owner == .hold {
            if h.action == .stop { action = .stop }
        } else if t.action == .stop { action = .stop }
        return RecordingShortcutDecision(suppress: h.suppress || t.suppress, action: action)
    }
}
