import AppKit
import SwiftUI

/// TextKit lays out visible content lazily, so a long dictation does not require
/// a huge SwiftUI Text layout whenever Copy changes the card's button label.
struct ResultTextView: NSViewRepresentable {
    let text: String
    static func makeScrollView() -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let view = NSTextView(frame: .zero)
        view.isEditable = false; view.isSelectable = true; view.isRichText = false
        view.drawsBackground = false; view.font = .systemFont(ofSize: 13)
        view.textColor = .labelColor; view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 328, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.layoutManager?.allowsNonContiguousLayout = true
        view.setAccessibilityLabel(I18n.tr("Распознанный текст", "Recognized text"))
        scroll.documentView = view
        return scroll
    }
    func makeNSView(context: Context) -> NSScrollView { Self.makeScrollView() }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if let view = scroll.documentView as? NSTextView, view.string != text { view.string = text }
    }
}
