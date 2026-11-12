import Testing
@testable import VeylumeCore

struct HoldWatchdogTests {
    @Test func unavailableHardwareStateDoesNotStopAFilteredHoldButConfirmedReleaseDoes() {
        var watchdog = HoldReleaseWatchdog()
        // Suppression/remote input/permission can make a key table report false
        // from the start. A healthy tap still owns keyUp and modifier release.
        for _ in 0..<100 { let stop = watchdog.shouldStop(hardwareDown: false); #expect(!stop) }
        let held = watchdog.shouldStop(hardwareDown: true); #expect(!held)
        let stillHeld = watchdog.shouldStop(hardwareDown: true); #expect(!stillHeld)
        let released = watchdog.shouldStop(hardwareDown: false); #expect(released)
        watchdog = HoldReleaseWatchdog()
        let newSession = watchdog.shouldStop(hardwareDown: false); #expect(!newSession)
    }
}
