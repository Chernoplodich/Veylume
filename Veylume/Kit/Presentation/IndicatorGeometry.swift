import Foundation
import VeylumeCore

enum IndicatorSurfaceLayout: Equatable {
    case mini
    case attached(width: CGFloat, cutoutHeight: CGFloat)
    case wings(cutoutWidth: CGFloat, height: CGFloat)

    static let wingWidth: CGFloat = 52
    var size: CGSize {
        switch self {
        case .mini: return CGSize(width: 72, height: 24)
        case .attached(let width, let height): return CGSize(width: width, height: height + 24)
        case .wings(let width, let height): return CGSize(width: width + Self.wingWidth * 2, height: height)
        }
    }
    var cutoutHeight: CGFloat {
        if case .attached(_, let height) = self { return height }
        return 0
    }
    var attached: Bool { self != .mini }
}

/// Display geometry plus a conservative, one-shot menu clearance snapshot.
/// Missing clearance never authorizes drawing over the menu bar.
struct IndicatorPlacement: Equatable {
    let frame: CGRect
    let layout: IndicatorSurfaceLayout
}

enum IndicatorGeometry {
    static func placement(screen: CGRect, visible: CGRect, safeAreaTop: CGFloat,
                          leftArea: CGRect?, rightArea: CGRect?, style: IndicatorStyle,
                          resultSize: CGSize? = nil, protectedMenuRects: [CGRect]? = nil) -> IndicatorPlacement {
        var cutout: CGRect?
        if style == .auto || style == .notch,
           safeAreaTop.isFinite, safeAreaTop > 0, safeAreaTop < screen.height / 4,
           let leftArea, let rightArea,
           [screen, leftArea, rightArea].allSatisfy({ $0.isFiniteRect }),
           abs(leftArea.minX - screen.minX) <= 1, abs(rightArea.maxX - screen.maxX) <= 1,
           abs(leftArea.maxY - screen.maxY) <= 1, abs(rightArea.maxY - screen.maxY) <= 1,
           abs(leftArea.minY - (screen.maxY - safeAreaTop)) <= 1,
           abs(rightArea.minY - (screen.maxY - safeAreaTop)) <= 1,
           leftArea.maxX >= screen.minX, rightArea.minX <= screen.maxX,
           rightArea.minX - leftArea.maxX >= 72, rightArea.minX - leftArea.maxX < screen.width / 2 {
            cutout = CGRect(x: leftArea.maxX, y: screen.maxY - safeAreaTop,
                            width: rightArea.minX - leftArea.maxX, height: safeAreaTop)
        }
        if let cutout, resultSize == nil,
           protectedMenuRects?.contains(where: { !$0.isFiniteRect || $0.intersects(cutout) }) != true {
            let wingWidth = IndicatorSurfaceLayout.wingWidth
            let leftWing = CGRect(x: cutout.minX - wingWidth, y: cutout.minY, width: wingWidth, height: cutout.height)
            let rightWing = leftWing.offsetBy(dx: cutout.width + wingWidth, dy: 0)
            if (24...48).contains(cutout.height), let protectedMenuRects,
               leftArea?.contains(leftWing) == true, rightArea?.contains(rightWing) == true,
               !protectedMenuRects.contains(where: { !$0.isFiniteRect || $0.insetBy(dx: -6, dy: -2).intersects(leftWing) || $0.insetBy(dx: -6, dy: -2).intersects(rightWing) }) {
                return IndicatorPlacement(frame: leftWing.union(rightWing), layout: .wings(cutoutWidth: cutout.width, height: cutout.height))
            }
            // Fill the cutout's lower curved corners too. Two shapes merely
            // touching at minY leave wallpaper-visible wedges at that seam.
            return IndicatorPlacement(frame: CGRect(x: cutout.minX, y: cutout.minY - 24,
                                                     width: cutout.width, height: cutout.height + 24),
                                      layout: .attached(width: cutout.width, cutoutHeight: cutout.height))
        }
        let size = resultSize ?? CGSize(width: 72, height: 24)
        let top = cutout.map { $0.minY - 6 } ?? visible.maxY - 36
        let x = min(visible.maxX - size.width - 8, max(visible.minX + 8, (cutout?.midX ?? screen.midX) - size.width / 2))
        return IndicatorPlacement(frame: CGRect(x: x, y: max(visible.minY + 8, top - size.height),
                                                 width: size.width, height: size.height), layout: .mini)
    }
}

extension CGRect {
    fileprivate var isFiniteRect: Bool {
        [origin.x, origin.y, size.width, size.height].allSatisfy(\.isFinite) && width > 0 && height > 0
    }
}
