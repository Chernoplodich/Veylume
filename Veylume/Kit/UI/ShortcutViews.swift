import SwiftUI
import AppKit
import VeylumeCore

struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var session: SessionCoordinator
    @ObservedObject var preferences: PreferencesStore
    var bindingMode: RecordingMode = .hold
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton(); button.bezelStyle = .rounded; button.setButtonType(.momentaryPushIn)
        button.onListening = { listening in session.recordingShortcut = listening; session.refreshHotkeys() }
        button.onRecord = { shortcut in
            let other = bindingMode == .hold ? preferences.value.toggleShortcut : preferences.value.holdShortcut
            guard shortcut != other else { session.notice = I18n.tr("Эта клавиша уже назначена второму способу записи.", "This shortcut is already assigned to the other recording gesture."); return }
            if bindingMode == .hold { preferences.value.holdShortcut = shortcut } else { preferences.value.toggleShortcut = shortcut }
        }
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        if !button.listening { button.title = HotkeyService.display(bindingMode == .hold ? preferences.value.holdShortcut : preferences.value.toggleShortcut) }
        button.isEnabled = !session.busy; button.setAccessibilityLabel(I18n.tr("Назначить клавишу записи", "Assign recording shortcut"))
    }
    static func dismantleNSView(_ button: RecorderButton, coordinator: ()) { button.finish() }
}
final class RecorderButton: NSButton {
    var listening = false
    var onListening: ((Bool) -> Void)?, onRecord: ((Shortcut) -> Void)?
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); target = self; action = #selector(beginListening) }
    required init?(coder: NSCoder) { super.init(coder: coder); target = self; action = #selector(beginListening) }
    override var acceptsFirstResponder: Bool { true }
    @objc private func beginListening() {
        guard isEnabled else { return }; listening = true; onListening?(true)
        title = I18n.tr("Нажмите клавишу…", "Press a key…"); window?.makeFirstResponder(self)
    }
    override func keyDown(with event: NSEvent) {
        guard listening else { super.keyDown(with: event); return }
        guard !event.isARepeat else { return }
        if event.keyCode == 53 { finish(); return }
        let modifiers = UInt64(event.modifierFlags.rawValue) & Shortcut.modifierMask
        let reserved = [UInt16(36), 48, 51, 117].contains(event.keyCode)
            || (modifiers & (1 << 20) != 0 && [UInt16(12), 13, 4, 46, 48, 49, 9, 8].contains(event.keyCode))
        guard !reserved else { title = I18n.tr("Выберите другую", "Choose another key"); return }
        let shortcut = Shortcut(keyCode: event.keyCode, modifiers: modifiers); onRecord?(shortcut); title = HotkeyService.display(shortcut); finish()
    }
    override func resignFirstResponder() -> Bool { finish(); return super.resignFirstResponder() }
    func finish() { if listening { listening = false; onListening?(false) } }
}

struct ShortcutSettings: View {
    @ObservedObject var session: SessionCoordinator
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var capabilities: CapabilityCoordinator
    var body: some View {
        PageHeading(title: SettingsSection.shortcuts.title, subtitle: I18n.tr("Два способа записи — каждый на своей клавише.", "Two recording gestures, each with its own shortcut."))
        GlassGroup {
            shortcutRow(.hold, title: I18n.tr("Удерживать", "Hold to record"), detail: I18n.tr("Отпускание завершает запись", "Release to finish"))
            Divider()
            shortcutRow(.toggle, title: I18n.tr("Нажать", "Press to record"), detail: I18n.tr("Нажать ещё раз для остановки", "Press again to finish"))
            Divider()
            AppRow(title: I18n.tr("Отмена", "Cancel")) { Text("Escape").font(.system(.body, design: .monospaced)) }
        }
        Text(I18n.tr("Можно назначить одну клавишу или сочетание. Чтобы печатать назначенный символ, приостановите клавиши в меню.", "Assign a single key or a combination. Pause shortcuts in the menu to type the assigned character.")).font(.caption).foregroundStyle(.secondary)
        PermissionSettings(capabilities: capabilities, hasShortcut: preferences.value.hasShortcuts, recheck: { session.refreshHotkeys() })
        Button(I18n.tr("Проверить клавишу", "Test shortcut")) {
            session.notice = I18n.tr("Удерживайте назначенную клавишу, затем отпустите. Проверьте системный индикатор микрофона. Тест не распознаёт и не вставляет текст.", "Hold your shortcut, then release it. Check the system microphone indicator. This test does not transcribe or insert text.")
            session.shortcutTest = true
        }.disabled(!preferences.value.hasShortcuts || !session.shortcutsAvailable || session.busy)
            .onDisappear { if session.shortcutTest { session.cancel(); session.shortcutTest = false } }
        if session.shortcutTest {
            Text(session.status).font(.caption)
            Button(I18n.tr("Завершить проверку", "Finish test")) { if session.busy { session.cancel() }; session.shortcutTest = false }
        }
        if let notice = session.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
    }
    private func shortcutRow(_ mode: RecordingMode, title: String, detail: String) -> some View {
        AppRow(title: title, detail: detail) {
            HStack(spacing: 6) {
                ShortcutRecorder(session: session, preferences: preferences, bindingMode: mode).frame(width: 170, height: 28)
                Button {
                    if mode == .hold { preferences.value.holdShortcut = nil } else { preferences.value.toggleShortcut = nil }
                } label: { Image(systemName: "xmark").font(.system(size: 10)).frame(width: 24, height: 28).contentShape(Rectangle()) }
                    .buttonStyle(.borderless).help(I18n.tr("Убрать клавишу", "Clear shortcut"))
                    .disabled(mode == .hold ? preferences.value.holdShortcut == nil : preferences.value.toggleShortcut == nil)
            }.disabled(session.busy)
        }
    }

}

struct AppearanceSettings: View {
    @ObservedObject var session: SessionCoordinator
    @ObservedObject var preferences: PreferencesStore
    var body: some View {
        PageHeading(title: SettingsSection.appearance.title, subtitle: I18n.tr("Немного стекла, тихие сигналы и ничего лишнего.", "A little glass, gentle cues, and just what you need."))
        GlassGroup {
            AppRow(title: I18n.tr("Тема", "Theme")) { NativePopup(selection: $preferences.value.theme, choices: [(I18n.tr("Как в системе", "System"), Theme.system), (I18n.tr("Светлая", "Light"), .light), (I18n.tr("Тёмная", "Dark"), .dark)], label: I18n.tr("Тема", "Theme")).frame(width: 200) }
        }
        IndicatorSettings(value: $preferences.value)
        GlassGroup {
            AppRow(title: I18n.tr("Звуки", "Sounds")) { Toggle("", isOn: $preferences.value.soundsEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small) }
            Divider(); AppRow(title: I18n.tr("Громкость", "Volume")) { Slider(value: $preferences.value.soundVolume, in: 0...1).frame(width: 160).accessibilityLabel(I18n.tr("Громкость сигналов", "Cue volume")) }
            Divider(); AppRow(title: I18n.tr("Лимит записи", "Recording limit")) { RecordingLimitControl(minutes: $preferences.value.recordingLimitMinutes).frame(width: 200) }
        }
    }
}
