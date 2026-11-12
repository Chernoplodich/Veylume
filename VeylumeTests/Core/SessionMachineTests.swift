import Testing
import Foundation
@testable import VeylumeCore

struct SessionMachineTests {
    @Test func quickHoldStopsWhenAudioBecomesReady() {
        var machine = SessionMachine(); let id = UUID()
        #expect(machine.send(.begin(id, .hold)) == [.prepare(id)])
        #expect(machine.send(.release).isEmpty)
        #expect(machine.send(.audioReady(id)) == [.stop(id)])
        #expect(machine.phase == .stopping)
        #expect(machine.send(.audioReady(id)).isEmpty)
    }
    @Test func cancelledInferenceBlocksNewWorkAndRejectsLateResults() {
        var machine = SessionMachine(); let id = UUID(), next = UUID()
        _ = machine.send(.begin(id, .hold)); _ = machine.send(.audioReady(id)); _ = machine.send(.stop)
        _ = machine.send(.audioStopped(id, usable: true)); _ = machine.send(.cancel)
        #expect(machine.phase == .cancelling)
        #expect(machine.send(.begin(next, .toggle)).isEmpty)
        #expect(machine.send(.recognized(id)).isEmpty)
        _ = machine.send(.cleanupFinished(id)); _ = machine.send(.begin(next, .toggle))
        #expect(machine.send(.recognized(id)).isEmpty)
        #expect(machine.id == next)
    }
    @Test func insertionCommitsOnlyOnce() {
        var m = SessionMachine(); let id = UUID()
        _ = m.send(.begin(id, .toggle)); _ = m.send(.audioReady(id)); _ = m.send(.stop)
        _ = m.send(.audioStopped(id, usable: true)); _ = m.send(.recognized(id))
        #expect(m.send(.finalized(id)) == [.insert(id)])
        #expect(m.send(.finalized(id)).isEmpty)
        #expect(m.send(.cancel).isEmpty)
    }
    @Test func toggleRequiresNewPhysicalTapAndEscapeRearm() {
        var k = ShortcutReducer(); k.shortcut = Shortcut(keyCode: 50, modifiers: 0); k.mode = .toggle
        #expect(k.consume(.down(50, 0, repeatKey: false)).action == .start)
        k.active = true
        for _ in 0..<100 { #expect(k.consume(.down(50, 0, repeatKey: true)).action == nil) }
        #expect(k.consume(.escape).action == .cancel); k.active = false
        #expect(k.consume(.down(50, 0, repeatKey: false)).action == nil)
        _ = k.consume(.up(50))
        #expect(k.consume(.down(50, 0, repeatKey: false)).action == .start)
    }
    @Test func requiredModifierReleaseStopsHold() {
        var k = ShortcutReducer(); k.shortcut = Shortcut(keyCode: 50, modifiers: 1 << 19)
        _ = k.consume(.down(50, 1 << 19, repeatKey: false)); k.active = true
        #expect(k.consume(.flags(0)).action == .stop)
    }
}
