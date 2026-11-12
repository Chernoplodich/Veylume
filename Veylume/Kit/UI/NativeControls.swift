import SwiftUI
import AppKit

/// A real AppKit popup fills its assigned column; SwiftUI's menu-style Picker
/// otherwise centers an intrinsic-width pill inside the requested frame.
struct NativePopup<Value: Hashable>: NSViewRepresentable {
    @Binding var selection: Value
    let choices: [(String, Value)]
    var label: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.font = .systemFont(ofSize: 13)
        button.target = context.coordinator; button.action = #selector(Coordinator.changed(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.select = { index in if choices.indices.contains(index) { selection = choices[index].1 } }
        let titles = choices.map(\.0)
        if button.itemTitles != titles { button.removeAllItems(); button.addItems(withTitles: titles) }
        if let index = choices.firstIndex(where: { $0.1 == selection }) { button.selectItem(at: index) }
        button.isEnabled = context.environment.isEnabled; button.setAccessibilityLabel(label)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        NSSize(width: proposal.width ?? 190, height: nsView.intrinsicContentSize.height)
    }
    final class Coordinator: NSObject {
        var select: ((Int) -> Void)?
        @objc func changed(_ button: NSPopUpButton) { select?(button.indexOfSelectedItem) }
    }
}

struct RecordingLimitControl: NSViewRepresentable {
    @Binding var minutes: Int
    static let presets = [5, 10, 15, 30, 45, 60, 90, 120]
    static func parse(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let scanner = Scanner(string: trimmed)
        guard let value = scanner.scanInt(), (5...120).contains(value) else { return nil }
        let tail = String(trimmed[scanner.currentIndex...]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["", "мин", "min", "min."].contains(tail) else { return nil }
        return value
    }
    static func title(_ value: Int) -> String { "\(value) " + I18n.tr("мин", "min") }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSComboBox {
        let view = NSComboBox(frame: .zero); view.isEditable = true; view.completes = false
        view.font = .systemFont(ofSize: 13); view.delegate = context.coordinator
        view.setAccessibilityLabel(I18n.tr("Лимит записи в минутах, от 5 до 120", "Recording limit in minutes, from 5 to 120"))
        return view
    }
    func updateNSView(_ view: NSComboBox, context: Context) {
        view.setAccessibilityLabel(I18n.tr("Лимит записи в минутах, от 5 до 120", "Recording limit in minutes, from 5 to 120"))
        context.coordinator.commit = { minutes = $0 }
        context.coordinator.current = minutes
        let titles = Self.presets.map(Self.title)
        if view.objectValues.compactMap({ $0 as? String }) != titles { view.removeAllItems(); view.addItems(withObjectValues: titles) }
        if view.currentEditor() == nil { view.stringValue = Self.title(minutes) }
        view.isEnabled = context.environment.isEnabled
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSComboBox, context: Context) -> CGSize? {
        NSSize(width: proposal.width ?? 200, height: nsView.intrinsicContentSize.height)
    }
    final class Coordinator: NSObject, NSComboBoxDelegate {
        var commit: ((Int) -> Void)?, current = 30
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let view = notification.object as? NSComboBox else { return }
            if let value = RecordingLimitControl.parse(view.stringValue) { current = value; commit?(value) }
            view.stringValue = RecordingLimitControl.title(current)
        }
        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSComboBox, RecordingLimitControl.presets.indices.contains(view.indexOfSelectedItem) else { return }
            current = RecordingLimitControl.presets[view.indexOfSelectedItem]; commit?(current)
        }
    }
}

struct FullRowDisclosure<Content: View>: View {
    let title: String
    @ViewState private var expanded = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(title).font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                }.padding(12).frame(maxWidth: .infinity, minHeight: 42, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityValue(expanded ? I18n.tr("Развёрнуто", "Expanded") : I18n.tr("Свёрнуто", "Collapsed"))
            if expanded { VStack(alignment: .leading, spacing: 10) { content }.padding(.horizontal, 12).padding(.bottom, 12).frame(maxWidth: .infinity, alignment: .leading) }
        }.background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PrivacyInfoButton: View {
    @Environment(\.locale) private var locale
    @ViewState private var showing = false
    var body: some View {
        Button { showing.toggle() } label: {
            Label(I18n.tr("На этом Mac", "On this Mac"), systemImage: "lock.shield")
                .font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
            // The copy resolver is static. Read the live environment so this
            // stateful footer updates with the rest of Settings immediately.
            .id(locale.identifier)
            .help(I18n.tr("Речь распознаётся локально. Подробнее о конфиденциальности.", "Speech is recognized locally. Learn about privacy."))
            .popover(isPresented: $showing, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(I18n.tr("Только на вашем Mac", "On your Mac"), systemImage: "lock.shield").font(.system(size: 14, weight: .semibold))
                    Text(I18n.tr("Veylume распознаёт речь на компьютере и не отправляет аудио или текст в облако.", "Veylume recognizes speech on your computer and never sends audio or text to the cloud."))
                    Text(I18n.tr("После установки модели диктовка работает без интернета. Сеть нужна для загрузки моделей и проверки обновлений.", "Once a model is installed, dictation works offline. Network access is used for model downloads and update checks."))
                    Text(I18n.tr("Приложение, в которое вы вставляете текст, обрабатывает его по собственным правилам.", "The app receiving your text handles it according to its own privacy policy.")).foregroundStyle(.secondary)
                }.font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).padding(18).frame(width: 300)
            }
    }
}
