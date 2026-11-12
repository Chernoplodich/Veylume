import AppKit

enum PermissionRequest: Hashable { case microphone, accessibility, listen, post, clipboard, storage }

/// Focus belongs to an explicit permission action, not to background status
/// polling. A closed window or a completed request can never pull the app back.
@MainActor final class PermissionFlowFocus {
    private final class Owner {
        weak var window: NSWindow?
        init(_ window: NSWindow) { self.window = window }
    }
    private var owners: [PermissionRequest: Owner] = [:]
    private let isOpen: (NSWindow) -> Bool
    private let show: (NSWindow) -> Void
    init(isOpen: @escaping (NSWindow) -> Bool = { $0.isVisible },
         show: @escaping (NSWindow) -> Void = { window in
             NSApp.activate(ignoringOtherApps: true)
             window.makeKeyAndOrderFront(nil)
         }) {
        self.isOpen = isOpen; self.show = show
    }
    func begin(_ request: PermissionRequest, owner: NSWindow?) {
        guard let owner, isOpen(owner) else { return }
        owners[request] = Owner(owner); show(owner)
    }
    func resolved(_ request: PermissionRequest) {
        guard let owner = owners.removeValue(forKey: request)?.window, isOpen(owner) else { return }
        show(owner)
    }
    @discardableResult func closed(_ window: NSWindow) -> Set<PermissionRequest> {
        let requests = Set(owners.filter { $0.value.window === window }.keys)
        owners = owners.filter { $0.value.window != nil && $0.value.window !== window }
        return requests
    }
}
