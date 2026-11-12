import Testing
import Foundation
import CoreGraphics
@testable import VeylumeKit
import VeylumeCore

struct PhysicalHoldTests {
    @Test func suppressedSessionKeyDoesNotLookLikePhysicalRelease() {
        // A session tap filters the down event. The session table is false,
        // while the hardware key remains held for all health-timer ticks.
        let keys = PhysicalKeyState(read: { table, _ in table == .hidSystemState })
        var machine = SessionMachine(); let id = UUID()
        _ = machine.send(.begin(id, .hold)); _ = machine.send(.audioReady(id))
        for _ in 0..<100 { if !keys.isDown(50) { _ = machine.send(.stop) } }
        #expect(machine.phase == .recording)
        let released = PhysicalKeyState(read: { _, _ in false })
        if !released.isDown(50) { _ = machine.send(.stop) }
        #expect(machine.phase == .stopping)
    }
    @Test func lostTapWhileIdleDoesNotSwallowTheNextFreshPhysicalPress() {
        var reducer = ShortcutReducer(); reducer.shortcut = Shortcut(keyCode: 50, modifiers: 0)
        _ = reducer.consume(.reset)
        let first = reducer.consume(.down(50, 0, repeatKey: false)); #expect(first.action == .start)
        let lost = reducer.consume(.reset); #expect(lost.action == .cancel)
        reducer.active = false
        let repeated = reducer.consume(.down(50, 0, repeatKey: true)); #expect(repeated.action == nil)
        _ = reducer.consume(.up(50))
        let fresh = reducer.consume(.down(50, 0, repeatKey: false)); #expect(fresh.action == .start)
    }
}
