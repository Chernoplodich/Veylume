import AppKit
import SwiftUI

@MainActor enum AppWindowStyle {
    static func install<Content: View>(_ content: Content, in window: NSWindow, size: NSSize) {
        let hosting = NSHostingView(rootView: content)
        // Window geometry belongs to AppKit. Propagating SwiftUI's flexible
        // intrinsic/minimum sizes creates a feedback loop at each state change.
        hosting.sizingOptions = []
        window.contentViewController = nil
        window.contentView = hosting
        window.setContentSize(size)
    }
    static func compactContentSize(preferred: NSSize, visibleFrame: NSRect) -> NSSize {
        NSSize(width: min(preferred.width, max(1, visibleFrame.width - 32)),
               height: min(preferred.height, max(1, visibleFrame.height - 64)))
    }
    static func apply(to window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isOpaque = false; window.backgroundColor = .clear
        // The hosting root's material ignores the titlebar safe area, while
        // its controls keep that inset. The system owns corners/traffic lights.
    }
}
