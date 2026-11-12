import AppKit
import ApplicationServices

/// Reads rectangles only: no menu titles, window names, documents or pixels.
/// Runs off the main actor at preparation, capture-start and display/app changes. Unknown
/// or timed-out geometry leaves the indicator below the system menu bar.
actor NotchMenuProbe {
    static let shared = NotchMenuProbe()
    func read(frontPID: pid_t, primaryTop: CGFloat, ownPID: pid_t, screen: CGRect) -> [CGRect]? {
        guard !Task.isCancelled else { return nil }
        return NotchMenuClearance.read(frontPID: frontPID, primaryTop: primaryTop, ownPID: ownPID, screen: screen)
    }
}

enum NotchMenuClearance {
    static func read(frontPID: pid_t, primaryTop: CGFloat, ownPID: pid_t, screen: CGRect) -> [CGRect]? {
        guard AXIsProcessTrusted() else { return nil }
        let application = AXUIElementCreateApplication(frontPID)
        guard AXUIElementSetMessagingTimeout(application, 0.025) == .success else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXMenuBarAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let menu = unsafeBitCast(value, to: AXUIElement.self)
        // AX timeouts belong to each individual object, not its descendants.
        guard AXUIElementSetMessagingTimeout(menu, 0.025) == .success else { return nil }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement], !items.isEmpty else { return nil }
        // One unresponsive app cannot schedule an unbounded series of AX calls.
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(120))
        var rectangles: [CGRect] = []
        for item in items.prefix(32) {
            guard !Task.isCancelled, ContinuousClock.now < deadline, let rect = frame(item, primaryTop: primaryTop) else { return nil }
            rectangles.append(rect)
        }
        guard items.count <= 32, rectangles.contains(where: { screen.contains($0) }),
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        // Menu extras and privacy/system overlays are separate WindowServer
        // windows. Do not read kCGWindowName or persist this ephemeral snapshot.
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? Int32) != ownPID,
                  let level = window[kCGWindowLayer as String] as? Int,
                  level >= Int(CGWindowLevelForKey(.mainMenuWindow)),
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            // The system's full-width menu backdrop is not an occupied item.
            // Its individual app menus are protected by the AX frames above.
            if level == Int(CGWindowLevelForKey(.mainMenuWindow)), rect.width > 500, rect.height <= 48 { continue }
            rectangles.append(appKitFrame(rect, primaryTop: primaryTop))
        }
        return rectangles
    }
    static func appKitFrame(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }
    private static func frame(_ element: AXUIElement, primaryTop: CGFloat) -> CGRect? {
        guard AXUIElementSetMessagingTimeout(element, 0.025) == .success else { return nil }
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions),
              [origin.x, origin.y, dimensions.width, dimensions.height].allSatisfy(\.isFinite), dimensions.width > 0, dimensions.height > 0 else { return nil }
        return appKitFrame(CGRect(origin: origin, size: dimensions), primaryTop: primaryTop)
    }
}
