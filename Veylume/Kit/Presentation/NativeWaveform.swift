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
    private var lastLevel = 0.0
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
        if bounds.size != renderedSize { render(lastLevel) }
    }
    private func subscribeIfVisible() {
        subscription = nil
        guard window != nil, let meter else { return }
        subscription = meter.$frame.sink { [weak self] frame in self?.render(frame.level) }
    }
    func render(_ level: Double) {
        lastLevel = level.isFinite ? min(1, max(0, level)) : 0
        let scale = window?.backingScaleFactor ?? 2
        // All bars respond to the current measured level. A scrolling history
        // made each syllable travel backwards after the user stopped speaking.
        // Interpolate the same symmetric profile on compact and wide surfaces.
        let profile = [0.30, 0.55, 0.80, 0.60, 1.0, 0.60, 0.80, 0.55, 0.30]
        let count = max(2, min(40, Int((bounds.width + 2) / 4)))
        let heights = (0..<count).map { index -> CGFloat in
            let position = Double(index) / Double(count - 1) * Double(profile.count - 1)
            let lower = Int(position), upper = min(lower + 1, profile.count - 1)
            let weight = profile[lower] + (profile[upper] - profile[lower]) * (position - Double(lower))
            let height = min(max(0, bounds.height), CGFloat(3 + lastLevel * 13 * weight))
            return (height * scale).rounded() / scale
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
