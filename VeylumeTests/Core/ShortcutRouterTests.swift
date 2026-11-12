import Testing
import Foundation
@testable import VeylumeCore

struct ShortcutRouterTests {
    let hold = Shortcut(keyCode: 50, modifiers: 1 << 18)
    let toggle = Shortcut(keyCode: 18, modifiers: 1 << 18)
    @Test func independentBindingsRetainTheGestureThatStartedRecording() {
        var r = ShortcutRouter(); r.configure(hold: hold, toggle: toggle, paused: false, active: false)
        #expect(r.consume(.down(50, 1 << 18, repeatKey: false)).action == .start(.hold))
        r.configure(hold: hold, toggle: toggle, paused: false, active: true)
        #expect(r.consume(.down(18, 1 << 18, repeatKey: false)).action == nil)
        #expect(r.consume(.up(18)).action == nil)
        #expect(r.consume(.up(50)).action == .stop)
        r.configure(hold: hold, toggle: toggle, paused: false, active: false)
        #expect(r.consume(.down(18, 1 << 18, repeatKey: false)).action == .start(.toggle))
        #expect(r.consume(.up(18)).action == nil)
        #expect(r.consume(.down(50, 1 << 18, repeatKey: false)).action == nil)
        #expect(r.consume(.up(50)).action == nil)
        #expect(r.consume(.down(18, 1 << 18, repeatKey: false)).action == .stop)
    }
    @Test func repeatEscapeAndModifierReleaseRemainStrict() {
        var r = ShortcutRouter(); r.configure(hold: hold, toggle: toggle, paused: false, active: false)
        _ = r.consume(.down(50, 1 << 18, repeatKey: false))
        #expect(r.consume(.down(50, 1 << 18, repeatKey: true)).action == nil)
        #expect(r.consume(.flags(0)).action == .stop)
        #expect(r.consume(.escape).action == .cancel)
        r.configure(hold: hold, toggle: toggle, paused: false, active: false)
        #expect(r.consume(.down(50, 1 << 18, repeatKey: false)).action == nil)
        _ = r.consume(.up(50))
        #expect(r.consume(.down(50, 1 << 18, repeatKey: false)).action == .start(.hold))
    }
    @Test func sameBaseKeyWithDifferentModifiersDoesNotMixModes() {
        let other = Shortcut(keyCode: 50, modifiers: (1 << 18) | (1 << 17))
        var r = ShortcutRouter(); r.configure(hold: hold, toggle: other, paused: false, active: false)
        #expect(r.consume(.down(50, other.modifiers, repeatKey: false)).action == .start(.toggle))
        #expect(r.consume(.flags(0)).action == nil)
        #expect(r.consume(.up(50)).action == nil)
        #expect(r.consume(.down(50, other.modifiers, repeatKey: false)).action == .stop)
    }
    @Test func legacyToggleMigratesOnceAndClearedKeysDoNotReturn() throws {
        var p = Preferences(); p.shortcut = toggle; p.mode = .toggle; p.material = .frosted
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        json.removeValue(forKey: "shortcutSchema")
        var decoded = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: json))
        decoded.migrateSettings()
        #expect(decoded.toggleShortcut == toggle); #expect(decoded.holdShortcut == nil); #expect(decoded.material == .glass)
        decoded.toggleShortcut = nil
        var restarted = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(decoded)); restarted.migrateSettings()
        #expect(!restarted.hasShortcuts)
    }
    @Test func oldIndicatorSettingsKeepTheShortcutModelAndHistoryWhenPositionIsMissing() throws {
        var p = Preferences(); p.indicator = .auto; p.holdShortcut = hold
        p.selectedModel = "whisper-small"; p.historyEnabled = true; p.onboardingCompleted = true
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        json.removeValue(forKey: "indicatorPosition")
        json.removeValue(forKey: "storageMode"); json.removeValue(forKey: "lastAuthorizedStorageBuild")
        var restored = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: json))
        restored.migrateSettings()
        #expect(restored.indicator == .notch); #expect(restored.resolvedIndicatorPosition == .top)
        #expect(restored.holdShortcut == hold); #expect(restored.selectedModel == "whisper-small")
        #expect(restored.historyEnabled); #expect(restored.onboardingCompleted)
        #expect(restored.usesProtectedStorage)
        restored.indicator = .mini; restored.indicatorPosition = .bottom
        let restarted = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(restored))
        #expect(restarted.indicator == .mini); #expect(restarted.resolvedIndicatorPosition == .bottom)
        #expect(restarted.holdShortcut == hold)
    }
}
