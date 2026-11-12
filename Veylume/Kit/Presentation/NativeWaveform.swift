import AppKit
import SwiftUI
import Combine

/// The audio service already smooths RMS. One path, one layer, no timer and no
/// implicit animation. Detached views stop their meter subscription.
final class NativeWaveformView: NSView {
    private let bars = CAShapeLayer()
    private var subscription: AnyCancellable?
    private weak var meter: AudioMeter?
    private var renderedHeights: [CGFloat] = []
    private var renderedSize = CGSize.zero
    private var lastHistory: [Double] = []
    private(set) var renderCount = 0
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; bars.fillColor = NSColor.white.cgColor
        layer?.addSublayer(bars)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func bind(_ meter: AudioMeter) {
        guard self.meter !== meter else { return }
        self.meter = meter; subscribeIfVisible()
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); subscribeIfVisible() }
    override func layout() {
        super.layout()
        if bounds.size != renderedSize { render(lastHistory) }
    }
    private func subscribeIfVisible() {
        subscription = nil
        guard window != nil, let meter else { return }
        subscription = meter.$frame.sink { [weak self] frame in self?.render(frame.history) }
    }
    func render(_ history: [Double]) {
        lastHistory = history
        let scale = window?.backingScaleFactor ?? 2
        let samples = history.suffix(9).map { $0.isFinite ? min(1, max(0, $0)) : 0 }
        // Fill the wider attached surface with interpolated history, rather
        // than stretching nine tiny bars apart. Still one path and one layer.
        let count = max(2, min(40, Int((bounds.width + 2) / 4)))
        let heights = (0..<count).map { index -> CGFloat in
            let position = Double(index) / Double(count - 1) * Double(max(0, samples.count - 1))
            let lower = Int(position), upper = min(lower + 1, samples.count - 1)
            let level = samples.isEmpty ? 0 : samples[lower] + (samples[upper] - samples[lower]) * (position - Double(lower))
            return (CGFloat(3 + level * 13) * scale).rounded() / scale
        }
        guard heights != renderedHeights || renderedSize != bounds.size else { return }
        renderedHeights = heights; renderedSize = bounds.size; renderCount += 1
        let path = CGMutablePath()
        let width = min(3, max(2, bounds.width / 28))
        let step = heights.count > 1 ? max(0, bounds.width - width) / CGFloat(heights.count - 1) : 0
        for (index, height) in heights.enumerated() {
            let x = (CGFloat(index) * step * scale).rounded() / scale
            let rect = CGRect(x: x, y: (bounds.height - height) / 2, width: width, height: height)
            path.addRoundedRect(in: rect, cornerWidth: width / 2, cornerHeight: width / 2)
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        bars.path = path; CATransaction.commit()
    }
}

struct MeterWaveform: NSViewRepresentable {
    let meter: AudioMeter
    func makeNSView(context: Context) -> NativeWaveformView {
        let view = NativeWaveformView(frame: NSRect(x: 0, y: 0, width: 34, height: 16))
        view.bind(meter); return view
    }
    func updateNSView(_ view: NativeWaveformView, context: Context) { view.bind(meter) }
    static func dismantleNSView(_ view: NativeWaveformView, coordinator: ()) { /* subscription dies with view */ }
}
