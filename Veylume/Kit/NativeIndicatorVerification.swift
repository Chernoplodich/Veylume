import AppKit
import SwiftUI
import VeylumeCore

/// Production indicator views on a simulated camera cutout. This fixture reads
/// no permissions, user preferences, microphone, clipboard or Keychain.
@MainActor enum NativeIndicatorVerification {
    static func run(output: URL) -> Int32 {
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        let runner = IndicatorFixtureRunner(output: output); app.delegate = runner
        app.run(); withExtendedLifetime(runner) {}
        return runner.status
    }
}

@MainActor private final class IndicatorFixtureRunner: NSObject, NSApplicationDelegate {
    private let output: URL
    private let meter = AudioMeter()
    private var window: NSWindow?
    private(set) var status: Int32 = 1
    init(output: URL) { self.output = output }
    func applicationDidFinishLaunching(_ notification: Notification) {
        do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        catch { stop(); return }
        let root = VStack(spacing: 28) {
            example("Recording · side extensions", phase: .recording, layout: .wings(cutoutWidth: 192, height: 32))
            example("Processing · microphone has stopped", phase: .transcribing, layout: .wings(cutoutWidth: 192, height: 32))
            example("Menu occupied · continuous contour below cutout", phase: .recording, layout: .attached(width: 192, cutoutHeight: 32))
            example("Display without a cutout · Mini", phase: .recording, layout: .mini)
        }.padding(24).frame(width: 720).background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: root)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 720, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window?.appearance = NSAppearance(named: .aqua); window?.isReleasedWhenClosed = false
        window?.contentView = host
        window?.setContentSize(host.fittingSize)
        // Attach the real waveform to a window, but keep the fixture offscreen.
        for level in [0.2, 0.4, 0.9, 0.6, 0.3, 0.7, 0.95, 0.55, 0.25] { meter.update(level) }
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.capture() } }
    }
    private func example(_ title: String, phase: SessionPhase, layout: IndicatorSurfaceLayout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.66, green: 0.78, blue: 0.86), Color(red: 0.86, green: 0.91, blue: 0.94)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if layout != .mini {
                    UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 0)
                        .fill(.black).frame(width: 192, height: 32)
                }
                IndicatorSurface(phase: phase, meter: meter, layout: layout, openControls: {})
                    .padding(.top, layout == .mini ? 20 : 0)
            }.frame(width: 672, height: 88).clipped()
        }
    }
    private func capture() {
        defer { stop() }
        guard let view = window?.contentView else { return }
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        do {
            guard let png = rep.representation(using: .png, properties: [:]) else { return }
            try png.write(to: output.appendingPathComponent("indicator-layouts.png"), options: .atomic)
            let data = try JSONSerialization.data(withJSONObject: ["kind": "production-indicator-with-simulated-cutout", "widthPoints": view.bounds.width,
                "heightPoints": view.bounds.height, "scope": "Offscreen native components; not a physical MacBook or capture/insertion test"], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("report.json"), options: .atomic)
            status = 0
        } catch { print("indicator_fixture_failed") }
    }
    private func stop() {
        window?.close(); NSApp.stop(nil)
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
    }
}
