import AppKit
import SwiftUI
import VeylumeCore

@MainActor enum NativeIndicatorSettingsVerification {
    static func run(output: URL) -> Int32 {
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        let runner = IndicatorSettingsRunner(output: output); app.delegate = runner
        app.run(); withExtendedLifetime(runner) {}
        return runner.status
    }
}

/// Offscreen production controls with fixture preferences; no session, stored
/// user settings, microphone, clipboard, Keychain, model or permission prompts.
@MainActor private final class IndicatorSettingsRunner: NSObject, NSApplicationDelegate {
    private let output: URL
    private var window: NSWindow?
    private var index = 0
    private var images: [String] = []
    private(set) var status: Int32 = 1
    init(output: URL) { self.output = output }
    func applicationDidFinishLaunching(_ notification: Notification) {
        do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        catch { stop(); return }
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 424, height: 390), styleMask: .borderless, backing: .buffered, defer: false)
        window?.isReleasedWhenClosed = false
        next()
    }
    private func next() {
        guard index < 24 else { finish(); return }
        let language = ["en", "ru", "es", "fr"][index / 6]
        let dark = index % 2 == 1
        let integrated = index % 6 >= 4
        let position: IndicatorPosition = index % 6 < 2 || integrated ? .top : .bottom
        I18n.language = language
        var preferences = Preferences(); preferences.indicator = integrated ? .notch : .mini; preferences.indicatorPosition = position
        let root = VStack(alignment: .leading, spacing: 14) {
            Text(SettingsSection.appearance.title).font(.title3.weight(.semibold))
            IndicatorSettings(value: .constant(preferences))
            Spacer(minLength: 0)
        }.padding(22).frame(width: 424, height: 390).background { MaterialBackground(style: .glass) }
            .environment(\.locale, I18n.locale)
        let host = NSHostingView(rootView: root); host.sizingOptions = []
        window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window?.contentView = host; window?.setContentSize(CGSize(width: 424, height: 390))
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in MainActor.assumeIsolated {
            self?.capture(name: "indicator-settings-\(language)-\(integrated ? "cutout" : position.rawValue)-\(dark ? "dark" : "light").png")
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
            let data = try JSONSerialization.data(withJSONObject: ["images": images, "widthPoints": 424, "heightPoints": 390,
                "scope": "Offscreen native settings with fixture preferences; not physical camera or dictation verification"], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("report.json"), options: .atomic); status = 0
        } catch { print("indicator_settings_fixture_failed") }
        stop()
    }
    private func stop() {
        window?.close(); NSApp.stop(nil)
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
    }
}
