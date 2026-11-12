import Testing
import AppKit
import SwiftUI
import VeylumeCore
@testable import VeylumeKit

struct NativeSettingsTests {
    @Test @MainActor func readinessWindowDoesNotGrowAcrossRepeatedPermissionStepsOnEitherDisplayShape() throws {
        _ = NSApplication.shared
        let steps: [SetupStep] = [.checking, .microphone, .accessibility, .storage, .ready]
        let previousLanguage = I18n.language; defer { I18n.language = previousLanguage }
        for visible in [NSRect(x: 0, y: 0, width: 1280, height: 680), NSRect(x: 0, y: 0, width: 900, height: 1400), NSRect(x: 0, y: 0, width: 800, height: 460)] {
            let size = AppWindowStyle.compactContentSize(preferred: NSSize(width: 600, height: 430), visibleFrame: visible)
            #expect(size.width <= visible.width - 32); #expect(size.height <= visible.height - 64)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; defer { window.close() }
            AppWindowStyle.apply(to: window)
            func surface(_ step: SetupStep) -> ReadinessSurface {
                ReadinessSurface(step: step, microphoneReady: step != .microphone, externalReady: step == .storage || step == .ready, storageReady: step == .ready, close: {}, advance: {})
            }
            AppWindowStyle.install(surface(.checking), in: window, size: size)
            let hosting = try #require(window.contentView as? NSHostingView<ReadinessSurface>)
            let initialFrame = window.frame.size
            for language in ["ru", "en"] {
                I18n.language = language
                for _ in 0..<2 { for step in steps {
                    hosting.rootView = surface(step)
                    hosting.layoutSubtreeIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.005))
                    #expect(window.frame.size == initialFrame)
                } }
            }
        }
    }
    @Test func sourceTicketRejectsOwnAppSwitchesAndOldGenerations() {
        let request = DestinationRequest(pid: 42, generation: 7)
        #expect(DestinationTracker.acceptsSource(request: request, currentPID: 42, ownPID: 9, generation: 7))
        #expect(!DestinationTracker.acceptsSource(request: request, currentPID: 9, ownPID: 9, generation: 7))
        #expect(!DestinationTracker.acceptsSource(request: request, currentPID: 43, ownPID: 9, generation: 7))
        #expect(!DestinationTracker.acceptsSource(request: request, currentPID: 42, ownPID: 9, generation: 8))
        #expect(!DestinationTracker.acceptsSource(request: .init(pid: 9, generation: 7), currentPID: 9, ownPID: 9, generation: 7))
    }
    @Test func recordingLimitAcceptsDirectInputAndRejectsInvalidValues() {
        #expect(RecordingLimitControl.parse("37") == 37)
        #expect(RecordingLimitControl.parse(" 60 мин ") == 60)
        #expect(RecordingLimitControl.parse("120 min") == 120)
        for value in ["4", "121", "30.5", "30 hours", "", "99999999999999999999999"] { #expect(RecordingLimitControl.parse(value) == nil) }
    }
    @Test @MainActor func glassTitlebarUsesTheSameContentAndMiniCannotTakeKeyboardFocus() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 500), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        AppWindowStyle.apply(to: window)
        #expect(window.titlebarAppearsTransparent)
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.backgroundColor.alphaComponent == 0)
        let mini = PresentationCoordinator.makeIndicatorPanel(content: NSView()); defer { mini.close() }
        #expect(!mini.canBecomeKey); #expect(!mini.canBecomeMain)
    }
}
