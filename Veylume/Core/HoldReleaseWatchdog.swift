/// Missing state is not evidence of release until this hardware source has
/// actually reported the key held. Event-tap keyUp/modifier events remain the
/// authoritative stop path; this only recovers a missed release.
public struct HoldReleaseWatchdog: Sendable {
    private var observedDown = false
    public init() {}
    public mutating func shouldStop(hardwareDown: Bool) -> Bool {
        if hardwareDown { observedDown = true; return false }
        return observedDown
    }
}
