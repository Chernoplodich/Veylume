import AppKit
import SwiftUI
import VeylumeCore

@MainActor enum NativeFollowupVerification {
    static func run(output: URL) -> Int32 {
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        let runner = FollowupRunner(output: output); app.delegate = runner
        app.run(); withExtendedLifetime(runner) {}
        return runner.status
    }
}

/// Production surfaces with fixture values; no session, Keychain, microphone,
/// clipboard, model or stored user preferences are accessed.
@MainActor private final class FollowupRunner: NSObject, NSApplicationDelegate {
    private let output: URL
    private var window: NSWindow?
    private var index = 0
    private var images: [String] = []
    private(set) var status: Int32 = 1
    init(output: URL) { self.output = output }
    func applicationDidFinishLaunching(_ notification: Notification) {
        do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        catch { stop(); return }
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 424, height: 340), styleMask: .borderless, backing: .buffered, defer: false)
        window?.isReleasedWhenClosed = false; next()
    }
    private func next() {
        guard index < 48 else { finish(); return }
        let group = index / 8, language = ["en", "ru", "es", "fr"][(index % 8) / 2], dark = index % 2 == 1
        I18n.language = language
        let size = group == 4 ? CGSize(width: 600, height: 430) : CGSize(width: 424, height: 340)
        let root: AnyView
        if group == 4 {
            root = AnyView(ReadinessSurface(step: .ready, microphoneReady: true, externalReady: true,
                storageReady: false, storageOptional: true, storageConfigured: true, close: {}, advance: {}))
        } else if group == 5 {
            root = AnyView(VStack(alignment: .leading, spacing: 14) {
                PageHeading(title: SettingsSection.general.title, subtitle: I18n.tr("Выберите микрофон — и можно начинать.", "Choose a microphone and start dictating."))
                GlassGroup { OutputMuteSetting(enabled: .constant(true)) }
                Spacer(minLength: 0)
            }.padding(22).frame(width: size.width, height: size.height).background { MaterialBackground(style: .glass) })
        } else {
            root = AnyView(VStack(alignment: .leading, spacing: 14) {
                PageHeading(title: SettingsSection.general.title, subtitle: I18n.tr("Выберите микрофон — и можно начинать.", "Choose a microphone and start dictating."))
                StorageModeSurface(selection: .constant(group == 0 ? .sessionOnly : .protected), authorizing: group == 3,
                    needsAuthorization: group == 1 || group == 3, afterUpdate: group == 1, connect: {})
                Spacer(minLength: 0)
            }.padding(22).frame(width: size.width, height: size.height).background { MaterialBackground(style: .glass) })
        }
        let host = NSHostingView(rootView: root.environment(\.locale, I18n.locale)); host.sizingOptions = []
        window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window?.contentView = host; window?.setContentSize(size)
        let state = ["session-only", "reconnect-after-update", "connected", "authorizing", "optional-ready", "mute-output"][group]
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in MainActor.assumeIsolated {
            self?.capture(name: "followup-\(state)-\(language)-\(dark ? "dark" : "light").png")
        } }
    }
    private func capture(name: String) {
        guard let view = window?.contentView else { stop(); return }
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { stop(); return }
        view.cacheDisplay(in: view.bounds, to: rep)
        do {
            guard let data = rep.representation(using: .png, properties: [:]) else { stop(); return }
            try data.write(to: output.appendingPathComponent(name), options: .atomic)
            images.append(name); index += 1; next()
        } catch { stop() }
    }
    private func finish() {
        do {
            let report: [String: Any] = ["images": images, "scope": "Offscreen native fixture values; not a physical permission grant or dictation test"]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("report.json"), options: .atomic)
            status = 0
        } catch { print("followup_fixture_failed") }
        stop()
    }
    private func stop() {
        window?.close(); NSApp.stop(nil)
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
    }
}
