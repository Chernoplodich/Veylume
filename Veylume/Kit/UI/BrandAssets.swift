import SwiftUI
import AppKit

@MainActor enum BrandAssets {
    static let avatar: NSImage = {
        guard let url = Bundle.module.url(forResource: "VeylumeAvatar", withExtension: "png"), let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "waveform", accessibilityDescription: nil) ?? NSImage()
        }
        return image
    }()
    static func menuImage() -> NSImage? {
        let url = Bundle.module.url(forResource: "VeylumeTemplate", withExtension: "pdf")
            ?? Bundle.module.url(forResource: "VeylumeTemplate", withExtension: "png")
        let image = url.flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
        image?.size = NSSize(width: 18, height: 18); image?.isTemplate = true
        return image
    }
}

struct BrandAvatar: View {
    var size: CGFloat = 28
    var body: some View {
        Image(nsImage: BrandAssets.avatar).resizable().interpolation(.high)
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}
