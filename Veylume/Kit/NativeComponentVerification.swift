import AppKit
import SwiftUI
import VeylumeCore

/// Renders production presentation components with explicit fixture data.
/// Does not construct a SessionCoordinator or read any user data/permissions.
@MainActor enum NativeComponentVerification {
    static func run(output: URL) -> Int32 {
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        let runner = ComponentRunner(output: output); app.delegate = runner
        app.run(); withExtendedLifetime(runner) {}
        return runner.status
    }
}

@MainActor private final class ComponentRunner: NSObject, NSApplicationDelegate {
    private let output: URL
    private var window: NSWindow?
    private var index = 0
    private var images: [[String: Any]] = []
    private(set) var status: Int32 = 1
    init(output: URL) { self.output = output }
    func applicationDidFinishLaunching(_ notification: Notification) {
        do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        catch { stop(); return }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 500), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        if let window { AppWindowStyle.apply(to: window) }
        window?.isReleasedWhenClosed = false; window?.title = "Veylume · Components QA"
        next()
    }
    private func next() {
        guard index < 72 else { finish(); return }
        let group = index / 8, dark = index % 2 == 1, language = ["ru", "en", "es", "fr"][(index % 8) / 2], menu = group == 0
        I18n.language = language
        if menu || group == 2 { window?.styleMask = [.borderless] }
        else if let window { window.styleMask = [.titled, .closable]; AppWindowStyle.apply(to: window) }
        window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let root: AnyView
        if group == 8 { root = AnyView(settingsFixture) }
        else if group >= 3 {
            let step: SetupStep = [.checking, .microphone, .accessibility, .storage, .ready][group - 3]
            root = AnyView(ReadinessSurface(step: step, microphoneReady: step != .checking && step != .microphone,
                externalReady: step == .storage || step == .ready, storageReady: step == .ready, close: {}, advance: {}))
        } else if group == 2 {
            let text = I18n.tr("Готовый результат остаётся на вашем Mac.", "Your result stays on your Mac.")
            let entry = ResultEntry(id: UUID(), date: Date(), text: text, outcome: .manualRequired, incomplete: false, manualReason: "no_external_application")
            root = AnyView(ResultCardView(entry: entry, copy: {}, done: {}, close: {}))
        } else { root = menu ? AnyView(menuFixture) : AnyView(settingsFixture) }
        if (3...7).contains(group), let window {
            AppWindowStyle.install(root, in: window, size: NSSize(width: 600, height: 430))
        } else {
            let controller = NSHostingController(rootView: root)
            controller.sizingOptions = [.preferredContentSize]
            window?.contentViewController = controller
            window?.setContentSize(menu ? NSSize(width: 280, height: 360) : NSSize(width: 660, height: 500))
        }
        window?.center(); window?.orderFrontRegardless()
        if group == 8 { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in MainActor.assumeIsolated {
            self?.capture(group: group, menu: menu, dark: dark, language: language)
        } }
    }
    private func capture(group: Int, menu: Bool, dark: Bool, language: String) {
        guard let view = window?.contentView else { stop(); return }
        if menu || group == 2, let size = window?.contentViewController?.preferredContentSize, size.height > 0 { window?.setContentSize(size) }
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        let component = group == 8 ? "settings-active" : group >= 3 ? "readiness-\(group - 3)" : group == 2 ? "result-text" : menu ? "menu" : "settings"
        let name = "component-\(component)-\(language)-\(dark ? "dark" : "light").png"
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { stop(); return }
        view.cacheDisplay(in: view.bounds, to: rep)
        do {
            guard let png = rep.representation(using: .png, properties: [:]) else { stop(); return }
            try png.write(to: output.appendingPathComponent(name), options: .atomic)
            images.append(["image": name, "widthPoints": view.bounds.width, "heightPoints": view.bounds.height,
                "widthPixels": rep.pixelsWide, "heightPixels": rep.pixelsHigh,
                "requestedActive": group == 8, "applicationActive": NSApp.isActive, "windowKey": window?.isKeyWindow ?? false])
            index += 1; next()
        } catch { stop() }
    }
    private var menuFixture: some View {
        MenuSurface(status: I18n.tr("Готово к записи", "Ready to record"), model: "Parakeet TDT V3", material: .glass) {
            MenuActionRow(title: I18n.tr("Начать запись", "Start recording"), symbol: "mic", trailing: "⌃`", action: {})
            Divider().padding(.vertical, 4)
            MenuActionRow(title: I18n.tr("Последний результат", "Last result"), symbol: "text.alignleft", action: {})
            MenuActionRow(title: I18n.tr("Восстановление", "Recovery"), symbol: "arrow.counterclockwise", trailing: "2", action: {})
            MenuActionRow(title: I18n.tr("Настройки…", "Settings…"), symbol: "slider.horizontal.3", trailing: "⌘,", action: {})
            MenuActionRow(title: I18n.tr("Приостановить клавиши", "Pause shortcuts"), symbol: "pause", action: {})
            Divider().padding(.vertical, 4)
            MenuActionRow(title: I18n.tr("Выйти из Veylume", "Quit Veylume"), symbol: "power", trailing: "⌘Q", action: {})
        }
    }
    private var settingsFixture: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: .constant(.general))
            SidebarDivider()
            VStack(alignment: .leading, spacing: 14) {
                PageHeading(title: SettingsSection.general.title, subtitle: I18n.tr("Выберите микрофон — и можно начинать.", "Choose a microphone and start dictating."))
                GlassGroup {
                    AppRow(title: I18n.tr("Микрофон", "Microphone")) {
                        NativePopup(selection: .constant(0), choices: [(I18n.tr("Системное устройство", "System device"), 0)], label: "Microphone").frame(width: 200)
                    }; Divider()
                    AppRow(title: I18n.tr("Язык речи", "Speech language")) {
                        NativePopup(selection: .constant(0), choices: [(I18n.tr("Автоматически", "Automatic"), 0)], label: "Language").frame(width: 200)
                    }; Divider()
                    AppRow(title: I18n.tr("Язык интерфейса", "Interface language")) {
                        NativePopup(selection: .constant(I18n.languageCode), choices: [("English", "en"), ("Русский", "ru"), ("Español", "es"), ("Français", "fr")], label: I18n.tr("Язык интерфейса", "Interface language")).frame(width: 200)
                    }; Divider()
                    AppRow(title: I18n.tr("Запускать при входе", "Launch at login")) { Toggle("", isOn: .constant(false)).labelsHidden().toggleStyle(.switch).controlSize(.small) }
                }
                GlassGroup {
                    AppRow(title: I18n.tr("Автоматическая вставка", "Automatic insertion")) { Toggle("", isOn: .constant(true)).labelsHidden().toggleStyle(.switch).controlSize(.small) }
                }
                HStack { Button(I18n.tr("Диагностика…", "Diagnostics…"), action: {}); Button(I18n.tr("Повторить обучение", "Repeat setup"), action: {}) }.controlSize(.small)
                Spacer(minLength: 0)
            }.font(.system(size: 13)).padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.background { MaterialBackground(style: .glass).ignoresSafeArea() }.frame(width: 660, height: 500)
    }
    private func finish() {
        do {
            let data = try JSONSerialization.data(withJSONObject: ["kind": "production-components-with-fixture-data", "images": images,
                "scope": "Offscreen native view cache; not physical screen, permissions, capture or insertion verification"], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("report.json"), options: .atomic); status = 0
        } catch { print("component_report_failed") }
        stop()
    }
    private func stop() {
        window?.close(); NSApp.stop(nil)
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
    }
}
