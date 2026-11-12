import Testing
import AppKit
@testable import VeylumeKit

struct PermissionFocusTests {
    @Test @MainActor func onlyAnExplicitPendingRequestReturnsToItsStillOpenWindow() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        var open = true, presentations = 0
        let focus = PermissionFlowFocus(isOpen: { _ in open }, show: { shown in
            #expect(shown === window); presentations += 1
        })
        focus.resolved(.microphone); #expect(presentations == 0)
        focus.begin(.microphone, owner: window); #expect(presentations == 1)
        focus.resolved(.accessibility); #expect(presentations == 1)
        focus.resolved(.microphone); #expect(presentations == 2)
        focus.resolved(.microphone); #expect(presentations == 2)
        focus.begin(.storage, owner: window); #expect(presentations == 3)
        open = false; focus.resolved(.storage); #expect(presentations == 3)
        window.close()
    }
    @Test @MainActor func closingSetupCancelsAnyLateReturnAfterSystemSettings() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        var presentations = 0
        let focus = PermissionFlowFocus(isOpen: { _ in true }, show: { _ in presentations += 1 })
        focus.begin(.accessibility, owner: window); focus.begin(.storage, owner: window)
        #expect(presentations == 2)
        #expect(focus.closed(window) == Set([.accessibility, .storage]))
        focus.resolved(.accessibility); focus.resolved(.storage)
        #expect(presentations == 2)
        window.close()
    }
}
