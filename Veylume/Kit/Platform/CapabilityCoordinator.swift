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
    @Published private(set) var secureInput = false
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginApprovalRequired = false
    @Published private(set) var guidance: String?
    @Published private(set) var accessibilityRequested = false
    var shortcutAccessPossible: Bool { accessibility || listen }
    var pasteAccessPossible: Bool { accessibility || post }
    init() { refresh() }
    func refresh() {
        refreshCaptureAccess()
        let currentListen = CGPreflightListenEventAccess(), currentPost = CGPreflightPostEventAccess()
        if listen != currentListen { listen = currentListen }; if post != currentPost { post = currentPost }
        let loginStatus = SMAppService.mainApp.status
        let login = loginStatus == .enabled
        if loginEnabled != login { loginEnabled = login }
        let approval = loginStatus == .requiresApproval
        if loginApprovalRequired != approval { loginApprovalRequired = approval }
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
        if microphone == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .audio) }
        refresh()
        if microphone != .authorized { explainAndOpen(section: "Privacy_Microphone", name: I18n.tr("Микрофон", "Microphone")) }
    }
    func requestAccessibility() {
        accessibilityRequested = true
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary); refresh()
        // AX prompting is asynchronous. A false immediate return isn't a denial.
        // The guided UI offers Settings as the next explicit action.
        if !accessibility { guidance = I18n.tr("Включите Veylume в Accessibility.", "Enable Veylume in Accessibility.") }
    }
    func requestListen() {
        _ = CGRequestListenEventAccess(); refresh()
        if !listen { explainAndOpen(section: "Privacy_ListenEvent", name: I18n.tr("Мониторинг ввода", "Input Monitoring")) }
    }
    func requestPost() {
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
    func openAccessibilitySettings() { explainAndOpen(section: "Privacy_Accessibility", name: "Accessibility") }
    func setLogin(_ enabled: Bool) throws {
        guard !AppPaths.needsInstallation else { throw Problem.permissionChanged }
        if enabled { if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() } }
        else if SMAppService.mainApp.status != .notRegistered && SMAppService.mainApp.status != .notFound { try SMAppService.mainApp.unregister() }
        refresh()
    }
    func openSystemSettings() { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) }
    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
}
