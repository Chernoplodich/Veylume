import Testing
import AppKit
@testable import VeylumeKit
import VeylumeCore

struct PresentationTests {
    @Test @MainActor func firstNativePanelUsesRealContentInsteadOfAppKitsDefaultView() {
        _ = NSApplication.shared
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 72, height: 24))
        let panel = PresentationCoordinator.makeIndicatorPanel(content: content)
        defer { panel.close() }
        #expect(panel.contentView === content)
        #expect(panel.frame.size == NSSize(width: 72, height: 24))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.canBecomeKey); #expect(!panel.canBecomeMain)
        let atTop = NSRect(x: 600, y: 950, width: 296, height: 32)
        #expect(panel.constrainFrameRect(atTop, to: NSScreen.main) == atTop)
    }
    @Test func lateCloseFromPreviousResultCannotClearAnActiveRecordingOrNewResult() {
        let old = ResultEntry(id: UUID(), date: Date(), text: "Old fixture", outcome: .manualRequired, incomplete: false)
        let next = ResultEntry(id: UUID(), date: Date(), text: "Next fixture", outcome: .manualRequired, incomplete: false)
        var overlay = ResultOverlayState(); overlay.show(old)
        overlay.recordingBegan()
        let staleAfterStart = overlay.dismiss(old.id)
        #expect(!staleAfterStart); #expect(overlay.entry == nil)
        overlay.show(next)
        let staleAfterNextResult = overlay.dismiss(old.id)
        #expect(!staleAfterNextResult); #expect(overlay.entry?.id == next.id)
        let currentClose = overlay.dismiss(next.id)
        #expect(currentClose); #expect(overlay.entry == nil)
    }
}

import Combine

struct MeterAndBrandTests {
    @Test func externalSelectionRangesRejectNegativeAndOverflowingValues() {
        #expect(DestinationTracker.checkedRange(location: -1, length: 0) == nil)
        #expect(DestinationTracker.checkedRange(location: 0, length: -1) == nil)
        #expect(DestinationTracker.checkedRange(location: Int.max, length: 1) == nil)
        #expect(DestinationTracker.checkedRange(location: Int.max - 4, length: 5) == nil)
        #expect(DestinationTracker.checkedRange(location: 20, length: 65536)?.length == 65536)
        #expect(DestinationTracker.checkedRange(location: Int.max - 4, length: 4)?.location == Int.max - 4)
    }
    @Test @MainActor func resultUsesSelectableReadOnlyTextWithLazyLayout() {
        _ = NSApplication.shared
        let scroll = ResultTextView.makeScrollView()
        let view = scroll.documentView as? NSTextView
        #expect(view?.isEditable == false); #expect(view?.isSelectable == true)
        #expect(view?.layoutManager?.allowsNonContiguousLayout == true)
        #expect(view?.font?.pointSize == 13)
        #expect(scroll.hasVerticalScroller)
    }
    @Test @MainActor func meterPublishesOneCoherentFrameAndIgnoresUnchangedSilence() {
        let meter = AudioMeter()
        var frames: [AudioMeter.Frame] = []
        let subscription = meter.$frame.dropFirst().sink { frames.append($0) }
        meter.update(0)
        #expect(frames.isEmpty)
        meter.update(0.5)
        #expect(frames.count == 1)
        #expect(frames.first?.level == 0.5)
        #expect(frames.first?.history.last == 0.5)
        meter.update(.nan); meter.update(.infinity); meter.update(-1); meter.update(2)
        #expect(meter.frame.history.count == 9)
        #expect(meter.frame.history.allSatisfy { $0.isFinite && (0...1).contains($0) })
        meter.reset(); let afterReset = frames.count
        meter.reset(); meter.update(0)
        #expect(frames.count == afterReset)
        withExtendedLifetime(subscription) {}
    }
    @Test @MainActor func nativeWaveformSkipsSubpixelNoiseAndImplicitAnimations() {
        _ = NSApplication.shared
        let view = NativeWaveformView(frame: NSRect(x: 0, y: 0, width: 34, height: 16))
        view.render(Array(repeating: 0.5, count: 9))
        let before = view.renderCount
        for _ in 0..<1000 { view.render(Array(repeating: 0.50001, count: 9)) }
        #expect(view.renderCount == before)
        #expect(view.layer?.sublayers?.count == 1)
        #expect(view.layer?.sublayers?.first?.animationKeys()?.isEmpty != false)
        view.render(Array(repeating: 1, count: 9))
        #expect(view.renderCount == before + 1)
    }
    @Test @MainActor func wideWaveformFillsItsSurfaceAndRelayoutsWithoutNewAudio() {
        _ = NSApplication.shared
        let view = NativeWaveformView(frame: NSRect(x: 0, y: 0, width: 154, height: 16))
        view.render([0, 0.2, 0.7, 0.5, 0.9, 0.3, 0.4, 0.8, 0.1])
        let layer = view.layer?.sublayers?.first as? CAShapeLayer
        #expect(layer?.path?.boundingBoxOfPath.minX == 0)
        #expect(abs((layer?.path?.boundingBoxOfPath.maxX ?? 0) - 154) <= 0.5)
        let count = view.renderCount
        view.setFrameSize(NSSize(width: 34, height: 16)); view.layout()
        #expect(view.renderCount == count + 1)
        #expect(layer?.path?.boundingBoxOfPath.maxX == 34)
        #expect(view.layer?.sublayers?.count == 1)
        #expect(layer?.animationKeys()?.isEmpty != false)
    }
    @Test @MainActor func processingSpinnerRespectsReducedMotionAndStopsWhenDetached() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 24, height: 24), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let spinner = IndicatorSpinnerView(frame: NSRect(x: 0, y: 0, width: 14, height: 14))
        window.contentView = spinner; spinner.layout()
        let layer = spinner.layer?.sublayers?.first as? CAShapeLayer
        #expect(layer?.strokeColor == NSColor.white.cgColor)
        #expect(layer?.animation(forKey: "processing") != nil)
        spinner.reduceMotion = true
        #expect(layer?.animationKeys()?.isEmpty != false)
        spinner.reduceMotion = false
        #expect(layer?.animation(forKey: "processing") != nil)
        window.contentView = nil
        #expect(layer?.animationKeys()?.isEmpty != false)
        window.close()
    }
    @Test @MainActor func menuBrandIsTemplateWithRealVectorAndRetinaResources() {
        let image = BrandAssets.menuImage()
        #expect(image?.isTemplate == true)
        #expect(image?.size == NSSize(width: 18, height: 18))
        #expect(image?.representations.contains(where: { $0 is NSPDFImageRep }) == true)
        #expect(BrandAssets.avatar.size.width >= 128)
    }
}
