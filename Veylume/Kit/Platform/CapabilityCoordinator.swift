import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import Carbon

@MainActor final class CapabilityCoordinator: ObservableObject {
    @Published private(set) var microphone: AVAuthorizationStatus = .notDetermined
    @Published private(set) var accessibility = false
    @Published private(set) var listen = false
    @Published private(set) var post = false
    @Published private(set) var clipboardAccessDenied = false
    @Published private(set) var secureInput = false
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginApprovalRequired = false
    @Published private(set) var guidance: String?
    @Published private(set) var accessibilityRequested = false
    var onPermissionRequest: ((PermissionRequest) -> Void)?
    var onPermissionResolved: ((PermissionRequest) -> Void)?
    private var pendingRequests: Set<PermissionRequest> = []
    private var permissionWatch: Timer?
    private var permissionDeadline: ContinuousClock.Instant?
    var shortcutAccessPossible: Bool { accessibility || listen }
    var pasteAccessPossible: Bool { accessibility || post }
    init() { refresh() }
    func refresh() {
        refreshCaptureAccess()
        let currentListen = CGPreflightListenEventAccess(), currentPost = CGPreflightPostEventAccess()
        if listen != currentListen { listen = currentListen }; if post != currentPost { post = currentPost }
        refreshClipboardAccess()
        let loginStatus = SMAppService.mainApp.status
        let login = loginStatus == .enabled
        if loginEnabled != login { loginEnabled = login }
        let approval = loginStatus == .requiresApproval
        if loginApprovalRequired != approval { loginApprovalRequired = approval }
        resolveGrantedRequests()
    }
    func refreshCaptureAccess() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio), ax = AXIsProcessTrusted(), secure = IsSecureEventInputEnabled()
        if microphone != mic { microphone = mic }; if accessibility != ax { accessibility = ax }
        if secureInput != secure { secureInput = secure }
        // Accessibility is sufficient for our default event tap. The recording
        // health tick must not query Login Items or redundant TCC services.
        if !ax {
            let currentListen = CGPreflightListenEventAccess()
            if listen != currentListen { listen = currentListen }
        }
    }
    func requestMicrophone() async {
        begin(.microphone)
        if microphone == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            refresh()
            if microphone != .authorized {
                resolved(.microphone)
                guidance = I18n.tr("В настройках macOS включите микрофон для Veylume.", "Enable Veylume’s microphone in macOS settings.")
            }
            return
        }
        refresh()
        if microphone != .authorized { explainAndOpen(section: "Privacy_Microphone", name: I18n.tr("Микрофон", "Microphone")) }
    }
    func requestAccessibility() {
        begin(.accessibility)
        accessibilityRequested = true
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary); refresh()
        // AX prompting is asynchronous. A false immediate return isn't a denial.
        // The guided UI offers Settings as the next explicit action.
        if !accessibility { guidance = I18n.tr("Включите Veylume в Accessibility.", "Enable Veylume in Accessibility.") }
    }
    func requestListen() {
        begin(.listen)
        _ = CGRequestListenEventAccess(); refresh()
        if !listen { explainAndOpen(section: "Privacy_ListenEvent", name: I18n.tr("Мониторинг ввода", "Input Monitoring")) }
    }
    func requestPost() {
        begin(.post)
        _ = CGRequestPostEventAccess(); refresh()
        if !post { explainAndOpen(section: "Privacy_Accessibility", name: "Accessibility") }
    }
    private func explainAndOpen(section: String, name: String) {
        guidance = I18n.tr("Откройте Системные настройки → Конфиденциальность и безопасность → ", "Open System Settings → Privacy & Security → ") + name + I18n.tr(" и включите Veylume. Если приложения нет в списке, добавьте его кнопкой «+». После изменения вернитесь в Veylume: статус будет проверен заново.", " and enable Veylume. If it is missing, add it with the “+” button. Return to Veylume afterwards to recheck access.")
        // Deep links are best-effort navigation only. The written path and the
        // plain System Settings fallback remain available on every supported OS.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + section), NSWorkspace.shared.open(url) { return }
        openSystemSettings()
    }
    func revealApplication() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
    func openAccessibilitySettings() { begin(.accessibility); explainAndOpen(section: "Privacy_Accessibility", name: "Accessibility") }
    private func begin(_ request: PermissionRequest) {
        pendingRequests.insert(request); onPermissionRequest?(request)
        permissionDeadline = .now.advanced(by: .seconds(180))
        guard permissionWatch == nil else { return }
        // General Settings has no permanent permission poll. Watch only an
        // explicit grant journey; completion, closing its window or timeout
        // removes this timer. Never continuously keep a window above Settings.
        permissionWatch = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated {
            guard let self else { return }
            if let deadline = self.permissionDeadline, ContinuousClock.now >= deadline {
                self.cancelRequests(self.pendingRequests); return
            }
            self.refreshCaptureAccess()
            if self.pendingRequests.contains(.listen) { self.listen = CGPreflightListenEventAccess() }
            if self.pendingRequests.contains(.post) { self.post = CGPreflightPostEventAccess() }
            if self.pendingRequests.contains(.clipboard) { self.refreshClipboardAccess() }
            self.resolveGrantedRequests()
        } }
        permissionWatch?.tolerance = 0.1
    }
    private func resolved(_ request: PermissionRequest) {
        guard pendingRequests.remove(request) != nil else { return }
        stopWatchingIfFinished(); onPermissionResolved?(request)
    }
    private func resolveGrantedRequests() {
        let granted: [(PermissionRequest, Bool)] = [(.microphone, microphone == .authorized), (.accessibility, accessibility), (.listen, listen), (.post, post), (.clipboard, !clipboardAccessDenied)]
        for (request, allowed) in granted where allowed && pendingRequests.contains(request) { resolved(request) }
    }
    func cancelRequests(_ requests: Set<PermissionRequest>) {
        pendingRequests.subtract(requests); stopWatchingIfFinished()
    }
    private func stopWatchingIfFinished() {
        if pendingRequests.isEmpty { permissionWatch?.invalidate(); permissionWatch = nil; permissionDeadline = nil }
    }
    private func refreshClipboardAccess() {
        let denied = ClipboardSnapshot.accessBehaviorCode() == "always_deny"
        if clipboardAccessDenied != denied { clipboardAccessDenied = denied }
    }
    func openClipboardSettings() {
        begin(.clipboard)
        explainAndOpen(section: "Privacy_Pasteboard", name: I18n.tr("Буфер обмена", "Clipboard"))
    }
    deinit { permissionWatch?.invalidate() }
    func setLogin(_ enabled: Bool) throws {
        guard !AppPaths.needsInstallation else { throw Problem.permissionChanged }
        if enabled { if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() } }
        else if SMAppService.mainApp.status != .notRegistered && SMAppService.mainApp.status != .notFound { try SMAppService.mainApp.unregister() }
        refresh()
    }
    func openSystemSettings() { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) }
    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
}
