import Testing
import Foundation
import VeylumeCore
@testable import VeylumeKit

struct IndicatorGeometryTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let visible = CGRect(x: 0, y: 40, width: 1512, height: 910)
    private let left = CGRect(x: 0, y: 950, width: 660, height: 32)
    private let right = CGRect(x: 852, y: 950, width: 660, height: 32)
    @Test func attachedIndicatorCoversTheCameraCornersWithoutCoveringMenuAreas() {
        for style in [IndicatorStyle.auto, .notch] {
            let p = IndicatorGeometry.placement(screen: screen, visible: visible, safeAreaTop: 32, leftArea: left, rightArea: right, style: style)
            #expect(p.layout == .attached(width: 192, cutoutHeight: 32)); #expect(p.frame == CGRect(x: 660, y: 926, width: 192, height: 56))
            #expect(p.frame.maxY == screen.maxY)
            #expect(p.layout.cutoutHeight == 32)
            #expect(!p.frame.intersects(left)); #expect(!p.frame.intersects(right))
        }
    }
    @Test func wingsUseActualCutoutWithNoPanelBelowItWhenMenusAreClear() {
        let p = IndicatorGeometry.placement(screen: screen, visible: visible, safeAreaTop: 32,
            leftArea: left, rightArea: right, style: .auto, protectedMenuRects: [CGRect(x: 0, y: 950, width: 500, height: 32), CGRect(x: 1100, y: 950, width: 412, height: 32)])
        #expect(p.layout == .wings(cutoutWidth: 192, height: 32))
        #expect(p.frame == CGRect(x: 608, y: 950, width: 296, height: 32))
        #expect(p.frame.minY == left.minY)
        #expect(p.frame.maxY == screen.maxY)
    }
    @Test func menuAndPrivacyItemsForceTheFullWidthAttachedFallback() {
        for rect in [CGRect(x: 630, y: 954, width: 24, height: 24), CGRect(x: 905, y: 954, width: 24, height: 24)] {
            let p = IndicatorGeometry.placement(screen: screen, visible: visible, safeAreaTop: 32,
                leftArea: left, rightArea: right, style: .notch, protectedMenuRects: [rect])
            #expect(p.layout == .attached(width: 192, cutoutHeight: 32))
            #expect(!p.frame.intersects(rect))
        }
    }
    @Test func windowsSpanningTheCameraDoNotDisableTheReservedCameraAttachment() {
        let overlay = CGRect(x: 850, y: 954, width: 24, height: 24)
        let p = IndicatorGeometry.placement(screen: screen, visible: visible, safeAreaTop: 32,
            leftArea: left, rightArea: right, style: .auto, protectedMenuRects: [overlay])
        #expect(p.layout == .attached(width: 192, cutoutHeight: 32))
        #expect(!p.frame.intersects(overlay.intersection(right)))
        let backdrop = IndicatorGeometry.placement(screen: screen, visible: visible, safeAreaTop: 32,
            leftArea: left, rightArea: right, style: .notch, protectedMenuRects: [CGRect(x: 0, y: 950, width: 1512, height: 32)])
        #expect(backdrop.layout == .attached(width: 192, cutoutHeight: 32))
        #expect(!backdrop.frame.intersects(left)); #expect(!backdrop.frame.intersects(right))
    }
    @Test func auxiliaryAreaHeightCanDifferFromTheCameraInset() {
        let tallerLeft = CGRect(x: 0, y: 945, width: 660, height: 37)
        let tallerRight = CGRect(x: 852, y: 945, width: 660, height: 37)
        let p = IndicatorGeometry.placement(screen: screen, visible: visible, safeAreaTop: 32,
            leftArea: tallerLeft, rightArea: tallerRight, style: .notch)
        #expect(p.layout == .attached(width: 192, cutoutHeight: 32))
    }
    @Test func compactBottomUsesTheVisibleFrameAboveTheDockAndMovesResultsWithIt() {
        let p = IndicatorGeometry.placement(screen: screen, visible: visible, safeAreaTop: 32,
            leftArea: left, rightArea: right, style: .mini, position: .bottom)
        #expect(p.layout == .mini); #expect(p.frame.minY == visible.minY + 18)
        #expect(visible.contains(p.frame))
        let result = IndicatorGeometry.placement(screen: screen, visible: visible, safeAreaTop: 32,
            leftArea: left, rightArea: right, style: .mini, position: .bottom, resultSize: CGSize(width: 360, height: 180))
        #expect(result.frame.minY == p.frame.minY); #expect(visible.contains(result.frame))
        let attached = IndicatorGeometry.placement(screen: screen, visible: visible, safeAreaTop: 32,
            leftArea: left, rightArea: right, style: .notch, position: .bottom)
        #expect(attached.frame.maxY == screen.maxY)
    }
    @Test func menuWindowCoordinatesUseThePrimaryScreenTopIncludingNegativeOffsets() {
        let cgFrame = CGRect(x: -900, y: -500, width: 40, height: 24)
        #expect(NotchMenuClearance.appKitFrame(cgFrame, primaryTop: 982) == CGRect(x: -900, y: 1458, width: 40, height: 24))
    }
    @Test func noCutoutAndExplicitMiniStayCompact() {
        let plain = IndicatorGeometry.placement(screen: screen, visible: visible, safeAreaTop: 0, leftArea: nil, rightArea: nil, style: .notch)
        let mini = IndicatorGeometry.placement(screen: screen, visible: visible, safeAreaTop: 32, leftArea: left, rightArea: right, style: .mini)
        #expect(plain.layout == .mini); #expect(mini.layout == .mini)
        #expect(plain.frame.size == CGSize(width: 72, height: 24)); #expect(mini.frame == plain.frame)
    }
    @Test func attachedPlacementUsesRealScreenCoordinatesForSecondaryDisplays() {
        let offset = CGPoint(x: -1512, y: 400)
        func shifted(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: offset.x, dy: offset.y) }
        let p = IndicatorGeometry.placement(screen: shifted(screen), visible: shifted(visible), safeAreaTop: 32,
            leftArea: shifted(left), rightArea: shifted(right), style: .auto)
        #expect(p.frame == CGRect(x: -852, y: 1326, width: 192, height: 56))
        let wings = IndicatorGeometry.placement(screen: shifted(screen), visible: shifted(visible), safeAreaTop: 32,
            leftArea: shifted(left), rightArea: shifted(right), style: .auto, protectedMenuRects: [])
        #expect(wings.frame == CGRect(x: -904, y: 1350, width: 296, height: 32))
    }
    @Test func resultsRemainReadableBelowTheCutout() {
        let p = IndicatorGeometry.placement(screen: screen, visible: visible, safeAreaTop: 32, leftArea: left, rightArea: right,
            style: .auto, resultSize: CGSize(width: 360, height: 180))
        #expect(p.layout == .mini); #expect(p.frame.maxY == 944)
        #expect(visible.contains(p.frame))
    }
    @Test func invalidOrMissingAuxiliaryGeometryFallsBackWithoutInventingANotch() {
        for inset in [CGFloat.nan, -CGFloat.infinity, CGFloat(0), CGFloat(400)] {
            let p = IndicatorGeometry.placement(screen: screen, visible: visible, safeAreaTop: inset, leftArea: left, rightArea: right, style: .auto)
            #expect(p.layout == .mini)
        }
        let overlap = IndicatorGeometry.placement(screen: screen, visible: visible, safeAreaTop: 32, leftArea: right, rightArea: left, style: .notch)
        #expect(overlap.layout == .mini)
    }
}
