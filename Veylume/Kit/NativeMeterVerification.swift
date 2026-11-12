import AppKit
import SwiftUI
import Darwin

/// Developer-only, isolated UI benchmark. No session, microphone, model, user
/// preferences, clipboard, Keychain or recovery store is opened by this runner.
@MainActor enum NativeMeterVerification {
    static func run(mode: String, seconds: Double, report: URL) -> Int32 {
        guard (3...60).contains(seconds) else { return 2 }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let runner = MeterRunner(mode: mode, seconds: seconds, report: report)
        app.delegate = runner
        app.run()
        withExtendedLifetime(runner) {}
        return runner.status
    }
}

@MainActor private final class LegacyMeter: ObservableObject {
    @Published var level = 0.0
    @Published var history = Array(repeating: 0.0, count: 9)
    func update(_ value: Double) { level = value; history.removeFirst(); history.append(value) }
}
private struct LegacyWaveform: View {
    @ObservedObject var meter: LegacyMeter
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<9) { i in Capsule().fill(.white).frame(width: 2, height: CGFloat(3 + meter.history[i] * 13)) }
        }.frame(width: 34, height: 16).animation(.linear(duration: 0.06), value: meter.history)
    }
}

@MainActor private final class MeterRunner: NSObject, NSApplicationDelegate {
    private let mode: String, seconds: Double, report: URL
    private let meter = AudioMeter(), legacy = LegacyMeter()
    private var panel: NSPanel?
    private var timer: Timer?
    private var started = ContinuousClock.now
    private var cpuStarted = 0.0, tick = 0
    private(set) var status: Int32 = 1
    init(mode: String, seconds: Double, report: URL) { self.mode = mode; self.seconds = seconds; self.report = report }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let content: AnyView
        if mode == "meter-legacy" { content = AnyView(LegacyWaveform(meter: legacy)) }
        else { content = AnyView(MeterWaveform(meter: meter).frame(width: mode == "meter-wide" ? 154 : 34, height: 16)) }
        let root = HStack(spacing: 6) {
            Circle().fill(.red).frame(width: 4, height: 4)
            content
        }.frame(width: mode == "meter-wide" ? 192 : 72, height: 24).background(.black, in: Capsule())
        panel = PresentationCoordinator.makeIndicatorPanel(content: NSHostingView(rootView: root))
        panel?.setContentSize(NSSize(width: mode == "meter-wide" ? 192 : 72, height: 24))
        panel?.center(); panel?.orderFrontRegardless()
        // Let fonts/layers/layout settle before measuring steady-state work.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.begin() } }
    }
    private func begin() {
        started = .now; cpuStarted = Self.cpu()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.step() } }
    }
    private func step() {
        let elapsed = Self.duration(started.duration(to: .now))
        if elapsed >= seconds { finish(elapsed); return }
        tick += 1
        let value = 0.5 + 0.45 * sin(Double(tick) / 9)
        if mode == "meter-legacy" { legacy.update(value) }
        else if mode != "meter-idle" { meter.update(value) }
    }
    private func finish(_ elapsed: Double) {
        timer?.invalidate(); timer = nil
        let cpu = Self.cpu() - cpuStarted
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let result: [String: Any] = ["mode": mode, "seconds": elapsed, "ticks": tick, "processCPUSeconds": cpu,
            "oneCorePercent": 100 * cpu / elapsed, "peakResidentBytes": usage.ru_maxrss,
            "panelVisible": panel?.isVisible == true, "sizePoints": [mode == "meter-wide" ? 192 : 72, 24], "inputHz": 30,
            "scope": "Isolated process UI plus identical 30 Hz fixture timer; no microphone, ASR, WindowServer or GPU cost included"]
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: report, options: .atomic)
            print(String(decoding: data, as: UTF8.self)); status = 0
        } catch { print("meter_report_failed") }
        panel?.close(); NSApp.stop(nil)
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
    }
    private static func cpu() -> Double {
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
    private static func duration(_ value: Duration) -> Double { Double(value.components.seconds) + Double(value.components.attoseconds) / 1e18 }
}
