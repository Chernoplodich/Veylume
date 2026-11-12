import AppKit
import SwiftUI

/// A single compositor-animated path, white in both application themes. No
/// timer or view updates per tick. Detaching it removes the animation.
final class IndicatorSpinnerView: NSView {
    private let arc = CAShapeLayer()
    var reduceMotion = false { didSet { if oldValue != reduceMotion { updateAnimation() } } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        arc.fillColor = nil; arc.strokeColor = NSColor.white.cgColor
        arc.lineWidth = 1.5; arc.lineCap = .round
        layer?.addSublayer(arc); setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        arc.frame = bounds
        arc.path = CGPath(ellipseIn: bounds.insetBy(dx: 1.5, dy: 1.5), transform: nil)
        arc.strokeStart = 0; arc.strokeEnd = 0.72
        CATransaction.commit()
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateAnimation() }
    private func updateAnimation() {
        guard window != nil, !reduceMotion else { arc.removeAllAnimations(); return }
        guard arc.animation(forKey: "processing") == nil else { return }
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0; rotation.toValue = -Double.pi * 2
        rotation.duration = 0.8; rotation.repeatCount = .infinity
        arc.add(rotation, forKey: "processing")
    }
    func stop() { arc.removeAllAnimations() }
}

struct IndicatorProcessingSpinner: NSViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeNSView(context: Context) -> IndicatorSpinnerView {
        let view = IndicatorSpinnerView(frame: CGRect(x: 0, y: 0, width: 14, height: 14))
        view.reduceMotion = reduceMotion; return view
    }
    func updateNSView(_ view: IndicatorSpinnerView, context: Context) { view.reduceMotion = reduceMotion }
    static func dismantleNSView(_ view: IndicatorSpinnerView, coordinator: ()) { view.stop() }
}
