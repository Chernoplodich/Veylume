import SwiftUI
import AppKit
import VeylumeCore

public enum VeylumeApplication {
    @MainActor public static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
        app.run(); withExtendedLifetime(delegate) {}
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var item: NSStatusItem?
    private let menu = NSPopover()
    private var settings: NSWindow?, onboarding: NSWindow?, readiness: NSWindow?
    private var session: SessionCoordinator?
    private var presentation: PresentationCoordinator?
    private var updates: UpdateCoordinator?
    private var quitAfterStop = false
    private var menuLanguage: String?
    private var escapeMonitor: Any?
    private let permissionFocus = PermissionFlowFocus()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        if let bundleID = Bundle.main.bundleIdentifier,
           let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { $0.processIdentifier != getpid() }) {
            other.activate(); NSApp.terminate(nil); return
        }
        do {
            let preferences = PreferencesStore(), capabilities = CapabilityCoordinator()
            let session = try SessionCoordinator(preferences: preferences, capabilities: capabilities); self.session = session
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak session] event in
                if event.keyCode == 53, session?.busy == true, session?.recordingShortcut == false { session?.cancel(); return nil }
                return event
            }
            let updates = UpdateCoordinator(session: session); self.updates = updates
            let presentation = PresentationCoordinator(session: session); self.presentation = presentation
            session.onPhaseChange = { [weak self] in self?.applyAppearance(); self?.presentation?.update() }
            session.onPresentResult = { [weak self] entry in self?.showResult(entry) }
            session.onRecoveryLimit = { [weak self] in self?.showSettings(section: .history) }
            session.onReadinessRequired = { [weak self] in self?.showReadiness() }
            capabilities.onPermissionRequest = { [weak self] request in self?.beginPermissionRequest(request) }
            capabilities.onPermissionResolved = { [weak self] request in self?.permissionFocus.resolved(request) }
            session.onStorageAuthorizationBegan = { [weak self] in self?.beginPermissionRequest(.storage) }
            session.onStorageAuthorizationFinished = { [weak self] in self?.permissionFocus.resolved(.storage) }
            session.onIdle = { [weak self] in
                self?.updates?.resumeIfSafe()
                if self?.quitAfterStop == true { self?.quitAfterStop = false; NSApp.reply(toApplicationShouldTerminate: true) }
            }
            let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            status.button?.image = BrandAssets.menuImage()
            status.button?.setAccessibilityLabel("Veylume")
            status.button?.toolTip = "Veylume"
            status.button?.target = self; status.button?.action = #selector(toggleMenu)
            item = status; menu.behavior = .transient
            let menuController = NSHostingController(rootView: MenuContent(session: session, models: session.models, preferences: preferences, updates: updates, capabilities: capabilities, startRecording: { [weak self] in self?.menu.close(); session.start() }, showSettings: { [weak self] in self?.showSettings() }, showResult: { [weak self] in if let entry = session.lastResult { self?.showResult(entry) } }, showRecovery: { [weak self] in self?.showSettings(section: .history) }))
            menuController.sizingOptions = [.preferredContentSize]
            menu.contentViewController = menuController
            applyAppearance()
            if AppPaths.needsInstallation { showInstallation() }
            else if !preferences.value.onboardingCompleted { showOnboarding() }
            let appURL = Bundle.main.bundleURL
            Task.detached(priority: .utility) { InstallerDisk.ejectMatchingImage(app: appURL) }
        } catch {
            let alert = NSAlert(); alert.messageText = "Veylume"; alert.informativeText = Problem.storage.message; alert.runModal(); NSApp.terminate(nil)
        }
    }
    @objc private func toggleMenu() {
        guard let button = item?.button else { return }
        if menu.isShown { menu.close() }
        else { session?.capabilities.refresh(); session?.refreshHotkeys(); menu.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
    private func window<V: View>(title: String, size: NSSize, content: V) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title; AppWindowStyle.apply(to: window); window.isReleasedWhenClosed = false
        window.hasShadow = true; window.delegate = self
        window.minSize = NSSize(width: 600, height: 430)
        AppWindowStyle.install(content, in: window, size: size)
        window.center(); return window
    }
    func showSettings(section: SettingsSection = .general) {
        guard let session, let updates else { return }; menu.close()
        if settings == nil || section == .history {
            let content = SettingsContent(session: session, preferences: session.preferences, models: session.models, capabilities: session.capabilities, updates: updates, initialSection: section, repeatOnboarding: { [weak self] in self?.showOnboarding() })
            if settings == nil { settings = window(title: "Veylume", size: NSSize(width: 660, height: 500), content: content) }
            else if let settings { AppWindowStyle.install(content, in: settings, size: settings.contentView?.bounds.size ?? NSSize(width: 660, height: 500)) }
        }
        applyAppearance(); settings?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func showOnboarding() {
        guard let session else { return }
        if onboarding == nil {
            onboarding = window(title: "Veylume", size: NSSize(width: 600, height: 460), content: OnboardingContent(session: session, preferences: session.preferences, models: session.models, capabilities: session.capabilities, close: { [weak self] in self?.onboarding?.close() }))
        }
        applyAppearance(); onboarding?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func showResult(_ entry: ResultEntry) {
        menu.close(); presentation?.showResult(entry)
    }
    private func showReadiness() {
        guard let session, !AppPaths.needsInstallation else { return }
        if !session.preferences.value.onboardingCompleted {
            session.preferences.value.onboardingStep = 1; showOnboarding(); return
        }
        menu.close()
        if readiness == nil {
            readiness = window(title: "Veylume", size: NSSize(width: 600, height: 430), content: ReadinessContent(session: session, capabilities: session.capabilities, close: { [weak self] in self?.readiness?.close() }))
            if let readiness, let screen = readiness.screen ?? NSScreen.main {
                readiness.minSize = .zero
                readiness.setContentSize(AppWindowStyle.compactContentSize(preferred: NSSize(width: 600, height: 430), visibleFrame: screen.visibleFrame))
                readiness.styleMask.remove(.resizable)
                readiness.center()
            }
        }
        applyAppearance(); readiness?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func beginPermissionRequest(_ request: PermissionRequest) {
        let windows = [readiness, onboarding, settings].compactMap { $0 }
        let key = NSApp.keyWindow?.sheetParent ?? NSApp.keyWindow
        let existing = windows.first { $0 === key && $0.isVisible } ?? windows.first(where: \.isVisible)
        menu.close()
        if existing == nil { showReadiness() }
        let owner = existing ?? [readiness, onboarding, settings].compactMap { $0 }.first(where: \.isVisible)
        permissionFocus.begin(request, owner: owner)
    }
    private func showInstallation() {
        guard let session else { return }
        onboarding = window(title: "Veylume", size: NSSize(width: 600, height: 430), content: InstallationContent(preferences: session.preferences))
        onboarding?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func applyAppearance() {
        if menuLanguage != I18n.locale.identifier { installMainMenu() }
        let theme = session?.preferences.value.theme ?? .system
        let appearance = theme == .system ? nil : NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
        for window in [settings, onboarding, readiness] { window?.appearance = appearance }
        menu.appearance = appearance
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if !flag { showSettings() }; return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session else { return .terminateNow }
        let recoveryEnabled = session.preferences.value.recordingConfiguration(storageAvailable: session.storageAvailable).recoveryEnabled
        if session.busy {
            let alert = NSAlert(); alert.messageText = I18n.tr("Завершить запись?", "Finish recording?")
            alert.informativeText = I18n.tr("Остановите и обработайте запись либо отмените её перед выходом.", "Stop and process the recording, or cancel it before quitting.")
            for text in [I18n.tr("Остановить и сохранить", "Stop and preserve"), I18n.tr("Отменить и выйти", "Cancel and quit"), I18n.tr("Остаться", "Stay")] { alert.addButton(withTitle: text) }
            let response = alert.runModal()
            if response == .alertFirstButtonReturn { quitAfterStop = recoveryEnabled; session.stop(); return quitAfterStop ? .terminateLater : .terminateCancel }
            if response == .alertSecondButtonReturn { quitAfterStop = true; session.cancel(); return .terminateLater }
            return .terminateCancel
        }
        if session.unresolvedCount > 0 {
            let alert = NSAlert(); alert.messageText = I18n.tr("Остались временные результаты", "Temporary results remain")
            alert.informativeText = recoveryEnabled ? I18n.tr("Защищённые восстановления доступны до 24 часов. Последний результат в памяти будет очищен.", "Recovery items remain available for up to 24 hours. The last result in memory will be cleared.") : I18n.tr("Восстановление выключено. Результаты в памяти будут потеряны.", "Recovery is off. Results in memory will be lost.")
            alert.addButton(withTitle: I18n.tr("Выйти", "Quit")); alert.addButton(withTitle: I18n.tr("Остаться", "Stay"))
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        session.shutdown(); return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { session?.shutdown() }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            let cancelled = permissionFocus.closed(window)
            session?.capabilities.cancelRequests(cancelled)
            // Remove the hosting view so its permission-check task cannot keep
            // running in a retained, closed window.
            if window === readiness { window.contentView = nil; readiness = nil }
            if window === onboarding { window.contentView = nil; onboarding = nil }
        }
        if session?.isTestSession == true { session?.cancel() }
        session?.recordingShortcut = false; session?.refreshHotkeys()
    }
    @objc private func openPreferences() { showSettings() }
    private func installMainMenu() {
        menuLanguage = I18n.locale.identifier
        let main = NSMenu(), appItem = NSMenuItem(), appMenu = NSMenu(title: "Veylume")
        let settingsItem = NSMenuItem(title: I18n.tr("Настройки…", "Settings…"), action: #selector(openPreferences), keyEquivalent: ","); settingsItem.target = self
        appMenu.addItem(settingsItem); appMenu.addItem(.separator())
        appMenu.addItem(withTitle: I18n.tr("Выйти из Veylume", "Quit Veylume"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(), edit = NSMenu(title: I18n.tr("Правка", "Edit"))
        edit.addItem(withTitle: I18n.tr("Отменить", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: I18n.tr("Повторить", "Redo"), action: Selector(("redo:")), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: I18n.tr("Вырезать", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: I18n.tr("Скопировать", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: I18n.tr("Вставить", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: I18n.tr("Выбрать всё", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
    }
}
