import AppKit
import ApplicationServices
import os
import VeylumeCore

struct Destination: @unchecked Sendable {
    let pid: pid_t
    let bundleID: String
    let application: AXUIElement
    let window: AXUIElement
    let element: AXUIElement
    let selection: CFRange?
    let generation: UInt64
    let isConsole: Bool
    let directSelectionCandidate: Bool
    let acknowledgementPossible: Bool
}

struct DestinationRequest: Sendable {
    let pid: pid_t?
    let generation: UInt64
}

final class DestinationTracker: @unchecked Sendable {
    private let generation = OSAllocatedUnfairLock(initialState: UInt64(0))
    private let captureCode = OSAllocatedUnfairLock(initialState: "not_attempted")
    var diagnosticCode: String { captureCode.withLock { $0 } }
    private var observer: AXObserver?
    private var observed: [(AXUIElement, String)] = []
    private let queue = DispatchQueue(label: "Veylume.destination", qos: .userInitiated)
    private var workspaceToken: NSObjectProtocol?
    init() {
        workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil) { [weak self] note in
            guard let self else { return }; self.invalidate()
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                let pid = app.processIdentifier
                self.queue.async { self.primeApplication(pid) }
            }
        }
    }
    deinit { if let workspaceToken { NSWorkspace.shared.notificationCenter.removeObserver(workspaceToken) }; detach() }
    func invalidate() { generation.withLock { $0 &+= 1 } }
    private func primeApplication(_ pid: pid_t) {
        guard pid != getpid(), AXIsProcessTrusted() else { return }
        let application = AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(application, 0.05)
        // Chromium explicitly activates native accessibility when an assistive
        // client reads the application's public AXRole. No private mode flags,
        // tree crawl, field contents, or continuous polling are needed.
        _ = Self.attribute(application, kAXRoleAttribute)
    }
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }; return value
    }
    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }; return (value as! AXUIElement)
    }
    static func range(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange(); guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return checkedRange(location: range.location, length: range.length)
    }
    static func checkedRange(location: Int, length: Int) -> CFRange? {
        // Accessibility metadata belongs to another process. Reject malformed
        // ranges before arithmetic, including Int.max/negative sentinels.
        guard location >= 0, length >= 0, location <= Int.max - length else { return nil }
        return CFRange(location: location, length: length)
    }
    static func settable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var result: DarwinBoolean = false; return AXUIElementIsAttributeSettable(element, attribute as CFString, &result) == .success && result.boolValue
    }
    func request() -> DestinationRequest {
        // Freeze the source before showing our own recording UI. Never infer a
        // different target later from whichever app has become frontmost.
        DestinationRequest(pid: NSWorkspace.shared.frontmostApplication?.processIdentifier, generation: generation.withLock { $0 })
    }
    static func acceptsSource(request: DestinationRequest, currentPID: pid_t?, ownPID: pid_t, generation: UInt64) -> Bool {
        request.pid != nil && request.pid != ownPID && currentPID == request.pid && request.generation == generation
    }
    func capture(_ request: DestinationRequest) async -> Destination? {
        await withCheckedContinuation { continuation in queue.async { continuation.resume(returning: self.captureSync(request)) } }
    }
    private func captureSync(_ request: DestinationRequest) -> Destination? {
        detach()
        func reject(_ code: String) -> Destination? { captureCode.withLock { $0 = code }; detach(); return nil }
        guard AXIsProcessTrusted() else { return reject("accessibility_unavailable") }
        guard let requestedPID = request.pid, requestedPID != getpid() else { return reject("no_external_application") }
        guard let app = NSWorkspace.shared.frontmostApplication,
              Self.acceptsSource(request: request, currentPID: app.processIdentifier, ownPID: getpid(), generation: generation.withLock({ $0 })) else { return reject("source_changed_before_capture") }
        let clock = ContinuousClock(), started = ContinuousClock.now, ticket = request.generation
        let application = AXUIElementCreateApplication(app.processIdentifier); AXUIElementSetMessagingTimeout(application, 0.05)
        _ = Self.attribute(application, kAXRoleAttribute)
        var focused = Self.element(application, kAXFocusedUIElementAttribute)
        while focused == nil && started.duration(to: clock.now) < .milliseconds(140) {
            guard Self.acceptsSource(request: request, currentPID: NSWorkspace.shared.frontmostApplication?.processIdentifier, ownPID: getpid(), generation: generation.withLock({ $0 })) else { return reject("source_changed_before_capture") }
            Thread.sleep(forTimeInterval: 0.02)
            focused = Self.element(application, kAXFocusedUIElementAttribute)
        }
        guard let element = focused else { return reject("no_focused_element") }
        guard let window = Self.element(application, kAXFocusedWindowAttribute) else { return reject("no_focused_window") }
        AXUIElementSetMessagingTimeout(element, 0.05)
        AXUIElementSetMessagingTimeout(window, 0.05)
        let role = Self.attribute(element, kAXRoleAttribute) as? String ?? ""
        let subrole = Self.attribute(element, kAXSubroleAttribute) as? String ?? ""
        guard subrole != kAXSecureTextFieldSubrole else { return reject("secure_field") }
        guard Self.attribute(element, kAXEnabledAttribute) as? Bool ?? true else { return reject("disabled_field") }
        let direct = Self.settable(element, kAXSelectedTextAttribute)
        var labels: [String] = []; var ancestor: AXUIElement? = element
        for _ in 0..<6 {
            guard started.duration(to: clock.now) < .milliseconds(180) else { return reject("metadata_deadline") }
            guard let current = ancestor else { break }
            labels += [Self.attribute(current, kAXIdentifierAttribute) as? String ?? "", Self.attribute(current, kAXDescriptionAttribute) as? String ?? ""]
            ancestor = Self.element(current, kAXParentAttribute)
        }
        let label = labels.joined(separator: " ").lowercased()
        let bundle = app.bundleIdentifier ?? ""
        let console = ["terminal", "console", "shell prompt", "repl", "терминал", "консоль"].contains(where: label.contains)
            || ["com.apple.Terminal", "com.googlecode.iterm2", "com.github.wez.wezterm", "org.alacritty", "net.kovidgoyal.kitty"].contains(bundle)
        guard [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) || direct || console else { return reject("unsupported_focused_role") }
        var axObserver: AXObserver?
        guard AXObserverCreate(app.processIdentifier, { _, _, _, pointer in
            guard let pointer else { return }; Unmanaged<DestinationTracker>.fromOpaque(pointer).takeUnretainedValue().invalidate()
        }, &axObserver) == .success, let axObserver else { return reject("observer_unavailable") }
        observer = axObserver
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        for (target, name) in [(application, kAXFocusedUIElementChangedNotification), (application, kAXFocusedWindowChangedNotification), (element, kAXSelectedTextChangedNotification), (element, kAXValueChangedNotification)] {
            if AXObserverAddNotification(axObserver, target, name as CFString, pointer) == .success { observed.append((target, name)) }
        }
        // We require observable text/selection changes or a readable caret token.
        let range = Self.range(element)
        guard range != nil || observed.contains(where: { CFEqual($0.0, element) }) else { return reject("unobservable_caret") }
        var parameterizedNames: CFArray?
        let acknowledgementPossible = range != nil
            && AXUIElementCopyParameterizedAttributeNames(element, &parameterizedNames) == .success
            && (parameterizedNames as? [String] ?? []).contains(kAXStringForRangeParameterizedAttribute)
        guard Self.acceptsSource(request: request, currentPID: NSWorkspace.shared.frontmostApplication?.processIdentifier, ownPID: getpid(), generation: generation.withLock({ $0 })), generation.withLock({ $0 }) == ticket else { return reject("destination_changed") }
        guard started.duration(to: clock.now) < .milliseconds(250) else { return reject("capture_deadline") }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes)
        captureCode.withLock { $0 = "ready" }
        return Destination(pid: app.processIdentifier, bundleID: bundle, application: application, window: window, element: element,
                           selection: range, generation: ticket, isConsole: console,
                           directSelectionCandidate: direct, acknowledgementPossible: acknowledgementPossible)
    }
    func matches(_ d: Destination) -> Bool {
        guard generation.withLock({ $0 }) == d.generation,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == d.pid,
              let element = Self.element(d.application, kAXFocusedUIElementAttribute), CFEqual(element, d.element),
              let window = Self.element(d.application, kAXFocusedWindowAttribute), CFEqual(window, d.window),
              Self.attribute(element, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole else { return false }
        if let previous = d.selection {
            guard let current = Self.range(element), previous.location == current.location, previous.length == current.length else { return false }
        }
        return true
    }
    func acknowledges(_ text: String, destination d: Destination) -> Bool {
        let length = text.utf16.count
        guard let before = d.selection, length <= 65536,
              let inserted = Self.checkedRange(location: before.location, length: length),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == d.pid,
              let focused = Self.element(d.application, kAXFocusedUIElementAttribute), CFEqual(focused, d.element),
              let window = Self.element(d.application, kAXFocusedWindowAttribute), CFEqual(window, d.window),
              let current = Self.range(d.element), current.length == 0, current.location == inserted.location + inserted.length else { return false }
        // Read only the inserted range; never read AXValue/the whole document.
        var range = inserted
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(d.element, kAXStringForRangeParameterizedAttribute as CFString, value, &result) == .success else { return false }
        return result as? String == text
    }
    private func detach() {
        if let observer {
            for (element, name) in observed { AXObserverRemoveNotification(observer, element, name as CFString) }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil; observed.removeAll()
    }
}
