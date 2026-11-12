import SwiftUI
import VeylumeCore

/// A shared surface keeps native fixtures and the running menu on the same
/// layout. Content determines the popover height, including conditional rows.
struct MenuSurface<Content: View>: View {
    let status: String, model: String, material: MaterialStyle
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 10) {
                BrandAvatar(size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Veylume").font(.system(size: 13, weight: .semibold))
                    Text(status).font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(model).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 10)
            content
        }.padding(8).frame(width: 280).fixedSize(horizontal: false, vertical: true)
            .background(MaterialBackground(style: material))
    }
}

struct MenuActionRow: View {
    let title: String, symbol: String
    var trailing: String? = nil
    var action: () -> Void
    @ViewState private var hovering = false
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 18).accessibilityHidden(true)
                Text(title)
                Spacer(minLength: 4)
                if let trailing { Text(trailing).font(.system(size: 11)).foregroundStyle(.secondary).accessibilityHidden(true) }
            }.font(.system(size: 13)).padding(.horizontal, 8).frame(height: 30)
                .frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .foregroundStyle(Color.primary.opacity(enabled ? 1 : 0.4))
            .background(hovering && enabled ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .onHover { hovering = $0 }
    }
}

struct MenuContent: View {
    @ObservedObject var session: SessionCoordinator
    @ObservedObject var models: ModelCoordinator
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var updates: UpdateCoordinator
    @ObservedObject var capabilities: CapabilityCoordinator
    var startRecording: () -> Void, showSettings: () -> Void, showResult: () -> Void, showRecovery: () -> Void
    var body: some View {
        MenuSurface(status: session.status, model: models.active?.name ?? I18n.tr("Подготовка Parakeet V3", "Preparing Parakeet V3"), material: preferences.value.material) {
            if session.busy {
                MenuActionRow(title: I18n.tr("Остановить запись", "Stop recording"), symbol: "stop.circle", action: { session.stop() })
                    .disabled(session.phase != .recording && session.phase != .preparing)
                MenuActionRow(title: I18n.tr("Отменить", "Cancel"), symbol: "xmark.circle", trailing: "esc", action: { session.cancel() }).keyboardShortcut(.cancelAction)
            } else if capabilities.microphone != .authorized {
                MenuActionRow(title: I18n.tr("Разрешить микрофон…", "Allow microphone…"), symbol: "mic", action: { Task { await capabilities.requestMicrophone() } })
            } else if session.unresolvedCount >= 10 {
                MenuActionRow(title: I18n.tr("Открыть восстановление", "Open recovery"), symbol: "arrow.counterclockwise", trailing: "\(session.unresolvedCount)", action: showRecovery)
            } else {
                MenuActionRow(title: I18n.tr("Начать запись", "Start recording"), symbol: "mic", trailing: preferences.value.preferredShortcut == nil ? nil : HotkeyService.display(preferences.value.preferredShortcut), action: startRecording)
                    .disabled(!models.activeReady || session.capabilities.microphone != .authorized)
            }
            Divider().padding(.vertical, 4)
            if preferences.value.usesProtectedStorage && session.storageNeedsAuthorization {
                MenuActionRow(title: I18n.tr("Подключить хранилище…", "Connect storage…"), symbol: "lock", action: { session.authorizeStorage() }).disabled(session.busy || session.authorizingStorage)
            }
            MenuActionRow(title: I18n.tr("Последний результат", "Last result"), symbol: "text.alignleft", action: showResult).disabled(session.lastResult == nil || session.busy)
            if session.unresolvedCount > 0 {
                MenuActionRow(title: I18n.tr("Восстановление", "Recovery"), symbol: "arrow.counterclockwise", trailing: "\(session.unresolvedCount)", action: showRecovery)
            }
            MenuActionRow(title: I18n.tr("Настройки…", "Settings…"), symbol: "slider.horizontal.3", trailing: "⌘,", action: showSettings).keyboardShortcut(",")
            MenuActionRow(title: I18n.tr("Приостановить клавиши", "Pause shortcuts"), symbol: preferences.value.shortcutsPaused ? "checkmark" : "pause", action: { preferences.value.shortcutsPaused.toggle() })
                .accessibilityValue(preferences.value.shortcutsPaused ? I18n.tr("Включено", "On") : I18n.tr("Выключено", "Off"))
            if updates.availableVersion != nil {
                MenuActionRow(title: I18n.tr("Обновить", "Update"), symbol: "arrow.down.circle", action: { updates.install() }).disabled(session.busy || session.unresolvedCount > 0)
            }
            Divider().padding(.vertical, 4)
            MenuActionRow(title: I18n.tr("Выйти из Veylume", "Quit Veylume"), symbol: "power", trailing: "⌘Q", action: { NSApp.terminate(nil) }).keyboardShortcut("q")
        }
    }
}

struct InstallationContent: View {
    @ObservedObject var preferences: PreferencesStore
    var body: some View {
        VStack(spacing: 20) {
            BrandAvatar(size: 72)
            Text("Veylume").font(.title2)
            Text(I18n.tr("Перенесите Veylume в Applications", "Move Veylume to Applications")).font(.headline)
            Text(I18n.tr("Перетащите приложение в Applications или ~/Applications, затем откройте установленную копию. Разрешения и автозапуск настраиваются после переноса. Приложение не запрашивает пароль администратора.", "Drag the app to Applications or ~/Applications, then open that copy. Set up permissions and login launch after moving it. The app does not ask for an administrator password.")).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(I18n.tr("Открыть Applications", "Open Applications")) { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications")) }
        }.padding(36).frame(maxWidth: .infinity, maxHeight: .infinity).background { MaterialBackground(style: .glass).ignoresSafeArea() }
    }
}

struct CompactResultContent: View {
    let entry: ResultEntry
    @ObservedObject var session: SessionCoordinator
    @ObservedObject var preferences: PreferencesStore
    var close: () -> Void
    static func size(for entry: ResultEntry) -> NSSize { ResultCardView.size(for: entry) }
    static func textHeight(for entry: ResultEntry) -> CGFloat { ResultCardView.textHeight(for: entry) }
    var body: some View {
        ResultCardView(entry: entry,
            authorizingStorage: session.authorizingStorage || session.busy,
            copy: { session.copy(entry) }, done: { Task { await session.removePending(entry); close() } },
            authorize: { session.authorizeStorage() }, close: close)
    }
}

struct ResultCardView: View {
    let entry: ResultEntry
    var needsStorage = false, authorizingStorage = false
    var copy: () -> Void, done: () -> Void, authorize: () -> Void = {}, close: () -> Void
    @ViewState private var copied = false
    private var warning: String? { Self.warning(for: entry) }
    static func warning(for entry: ResultEntry) -> String? {
        if entry.incomplete { return I18n.tr("Результат может быть неполным", "The result may be incomplete") }
        if entry.outcome == .dispatchedUnverified { return I18n.tr("Проверьте вставку перед копированием", "Check the field before copying again") }
        if entry.outcome == .manualRequired {
            switch entry.manualReason {
            case "clipboard_unsupported": return I18n.tr("Автовставка пропущена, чтобы сохранить буфер.", "Auto-paste was skipped to preserve your clipboard.")
            case "clipboard_too_large": return I18n.tr("В буфере слишком много данных для безопасного восстановления. Этот текст можно скопировать.", "The clipboard is too large to restore safely. You can copy this result.")
            case "clipboard_file_promise", "clipboard_provider_unavailable": return I18n.tr("Приложение ещё не подготовило данные в буфере. Этот текст можно скопировать.", "An app has not finished providing the clipboard data. You can copy this result.")
            case "clipboard_changed": return I18n.tr("Буфер изменился во время подготовки вставки. Этот текст можно скопировать.", "The clipboard changed while preparing the paste. You can copy this result.")
            case "no_external_application", "source_changed_before_capture": return I18n.tr("Выберите поле перед следующей записью. Этот текст можно скопировать.", "Choose a field before your next recording. You can copy this text.")
            case "no_destination", "destination_changed", "precommit_changed", "commit_destination_changed": return I18n.tr("Поле изменилось. Скопируйте текст в нужное место.", "The field changed. Copy the text where you need it.")
            case "modifiers_held": return I18n.tr("Отпустите клавиши и скопируйте текст.", "Release the keys, then copy your text.")
            case "secure_input": return I18n.tr("В защищённых полях доступно ручное копирование.", "Use manual copy for protected fields.")
            case "ax_selection_failed": return I18n.tr("Поле не приняло вставку. Нажмите «Скопировать».", "The field did not accept insertion. Use Copy.")
            case "accessibility_unavailable", "post_unavailable": return I18n.tr("Для автовставки нужен доступ Accessibility.", "Auto-paste needs Accessibility access.")
            default: break
            }
        }
        return nil
    }
    static func textHeight(for entry: ResultEntry) -> CGFloat {
        let rect = (String(entry.text.prefix(2048)) as NSString).boundingRect(with: NSSize(width: 308, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 13)])
        return min(160, max(20, ceil(rect.height) + 2))
    }
    static func size(for entry: ResultEntry) -> NSSize {
        let warningHeight = warning(for: entry).map { message -> CGFloat in
            let rect = (message as NSString).boundingRect(with: NSSize(width: 328, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 11)])
            return max(14, ceil(rect.height))
        } ?? 0
        return NSSize(width: 360, height: 120 + textHeight(for: entry) + (warningHeight > 0 ? warningHeight + 12 : 0))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: entry.incomplete ? "exclamationmark.circle" : "doc.text").foregroundStyle(entry.incomplete ? Color.orange : Color.accentColor)
                Text(entry.incomplete ? I18n.tr("Неполный результат", "Incomplete result") : I18n.tr("Текст готов", "Your text is ready")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).frame(width: 24, height: 24).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel(I18n.tr("Закрыть", "Close"))
            }.frame(height: 20)
            ResultTextView(text: entry.text).frame(height: Self.textHeight(for: entry)).padding(8)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            if let warning { Text(warning).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 8) {
                if needsStorage { Button(I18n.tr("Хранилище…", "Storage…"), action: authorize).disabled(authorizingStorage) }
                Button { copy(); copied = true } label: {
                    Label(copied ? I18n.tr("Скопировано", "Copied") : I18n.tr("Скопировать", "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent)
                Button(I18n.tr("Готово", "Done"), action: done).buttonStyle(.bordered)
            }.controlSize(.regular).frame(height: 28)
        }.padding(16).frame(width: 360, alignment: .leading)
            .background { MaterialBackground(style: .glass).ignoresSafeArea() }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.1), lineWidth: 0.5))
    }
}
