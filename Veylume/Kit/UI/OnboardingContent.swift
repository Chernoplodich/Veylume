import SwiftUI
import VeylumeCore

/// Five short steps; only the current decision is visible. Model preparation is
/// independent, quiet after success, and never asks a newcomer to compare models.
struct OnboardingContent: View {
    @ObservedObject var session: SessionCoordinator
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var models: ModelCoordinator
    @ObservedObject var capabilities: CapabilityCoordinator
    var close: () -> Void
    @ViewState private var practice = ""
    @ViewState private var testingMicrophone = false
    @ViewState private var details = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var step: Int { min(4, max(0, preferences.value.onboardingStep)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                BrandAvatar(size: 26)
                Text("Veylume").fontWeight(.medium)
                Spacer()
                ForEach(0..<5) { i in Capsule().fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.18)).frame(width: 18, height: 4).accessibilityHidden(true) }
            }.padding(.horizontal, 28).padding(.top, 22)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case 0: welcome
                    case 1: microphone
                    case 2: shortcut
                    case 3: insertionAccess
                    default: practiceView
                    }
                    if let notice = session.notice { Text(notice).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }.padding(.horizontal, 32).padding(.vertical, 26).frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.hidden)
            modelStatus.padding(.horizontal, 28).padding(.bottom, 16)
            Divider()
            HStack {
                Button(I18n.tr("Позже", "Later")) { stopTesting(); close() }.buttonStyle(.borderless).foregroundStyle(.secondary)
                Spacer()
                if step > 0 { Button(I18n.tr("Назад", "Back")) { stopTesting(); preferences.value.onboardingStep -= 1 } }
                Button(primaryTitle, action: primaryAction).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(session.authorizingStorage || ((step == 1 || step == 4) && !session.storageAccessChecked))
            }.controlSize(.large).padding(.horizontal, 28).padding(.vertical, 16)
        }
        .background { MaterialBackground(style: .glass).ignoresSafeArea() }
        .environment(\.locale, I18n.locale)
        .onChange(of: session.lastResult?.id) { _, _ in if step == 4 { practice = session.lastResult?.text ?? "" } }
        .onDisappear { stopTesting() }
        .task(id: step) {
            // Poll only while the permission step is visible; no idle watcher.
            while step == 1 || step == 3 {
                capabilities.refresh(); session.refreshHotkeys()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .sheet(isPresented: $details) { HelpContent() }
    }
    private func heading(_ title: String, _ subtitle: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 19, weight: .medium)).foregroundStyle(.tint)
                    .frame(width: 38, height: 38).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                Text(title).font(.system(size: 21, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            }
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading(I18n.tr("Говорите. Текст появится сам.", "Speak. Your words appear."), I18n.tr("В редакторе, чате или терминале. Распознавание — на вашем Mac.", "In an editor, chat, or terminal. Transcription runs on your Mac."), symbol: "waveform")
            VStack(alignment: .leading, spacing: 10) {
                Label(I18n.tr("Без аккаунта и оплаты", "No account or payment"), systemImage: "checkmark")
                Label(I18n.tr("История выключена", "History is off"), systemImage: "checkmark")
                Label(I18n.tr("Модель готовится автоматически", "Your model prepares automatically"), systemImage: "checkmark")
            }.font(.callout)
            Button(I18n.tr("Данные и обновления", "Data and updates")) { details = true }.buttonStyle(.link).font(.caption)
            Text(I18n.tr("Восстановление — до 24 часов. Автопроверка обновлений включена. Всё меняется в настройках.", "Recovery lasts up to 24 hours. Update checks are on. Both can be changed in Settings.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var microphone: some View {
        VStack(alignment: .leading, spacing: 18) {
            if capabilities.microphone == .authorized && session.storageNeedsAuthorization {
                heading(I18n.tr("Защитим ваши записи", "Protect your recordings"), I18n.tr("Ключ для шифрования хранится в Связке ключей macOS.", "Your encryption key stays in macOS Keychain."), symbol: "lock.shield")
                Text(I18n.tr("Подключите хранилище один раз до первой диктовки. Если появится системный запрос, выберите «Разрешать всегда». Пароль вводится только в окне macOS.", "Connect secure storage before your first dictation. If a system prompt appears, choose Always Allow. Enter your password only in the macOS dialog.")).font(.callout)
            } else {
                heading(I18n.tr("Разрешите микрофон", "Allow your microphone"), I18n.tr("Он включается только после запуска записи.", "It turns on only when you start recording."), symbol: "mic")
            }
            if capabilities.microphone == .authorized && !session.storageNeedsAuthorization {
                Label(I18n.tr("Микрофон разрешён", "Microphone allowed"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                HStack(spacing: 16) {
                    Button(testingMicrophone && session.busy ? I18n.tr("Остановить", "Stop") : I18n.tr("Проверить уровень", "Test level")) {
                        if testingMicrophone && session.busy { session.stop(); testingMicrophone = false }
                        else { testingMicrophone = true; session.start(testOnly: true) }
                    }
                    if testingMicrophone && session.busy { MicrophoneLevel(meter: session.meter) }
                }
            } else if capabilities.microphone != .authorized {
                Text(capabilities.microphone == .denied ? I18n.tr("В настройках macOS включите микрофон для Veylume.", "Enable Veylume’s microphone in macOS settings.") : I18n.tr("Нажмите кнопку ниже и выберите «Разрешить» в окне macOS.", "Click below, then choose Allow in the macOS dialog.")).font(.callout)
            }
        }
    }
    private var shortcut: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading(I18n.tr("Выберите клавишу", "Choose your shortcut"), I18n.tr("Удерживайте — говорите. Отпустите — получите текст.", "Hold and speak. Release to get your text."), symbol: "keyboard")
            ShortcutRecorder(session: session, preferences: preferences).frame(width: 250, height: 36)
            if preferences.value.holdShortcut?.modifiers == 0 {
                Text(I18n.tr("Для обычного ввода этого символа приостановите клавишу в меню.", "Pause shortcuts in the menu to type this character normally.")).font(.caption).foregroundStyle(.secondary)
            }
            Text(I18n.tr("Escape отменяет запись. Клавишу для записи по нажатию можно добавить в настройках.", "Escape cancels recording. Add a separate press-to-record key in Settings.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var insertionAccess: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading(I18n.tr("Разрешите клавишу и вставку", "Allow shortcuts and insertion"), I18n.tr("Один доступ Accessibility — для работы в других приложениях.", "One Accessibility permission lets Veylume work across apps."), symbol: "cursorarrow.and.square.on.square.dashed")
            if capabilities.accessibility {
                Label(I18n.tr("Accessibility разрешён", "Accessibility allowed"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                if preferences.value.hasShortcuts {
                    Label(session.shortcutsAvailable ? I18n.tr("Клавиша работает", "Shortcut is ready") : I18n.tr("Нужно перезапустить Veylume", "Restart Veylume to enable your shortcut"), systemImage: session.shortcutsAvailable ? "checkmark.circle" : "arrow.clockwise").font(.callout)
                }
            } else if capabilities.accessibilityRequested {
                VStack(alignment: .leading, spacing: 12) {
                    instruction("1", I18n.tr("Откройте Accessibility в настройках macOS.", "Open Accessibility in macOS settings."))
                    instruction("2", I18n.tr("Включите Veylume. Нет в списке? Добавьте через «+».", "Enable Veylume. Missing? Add it with “+”."))
                    instruction("3", I18n.tr("Вернитесь сюда — проверим доступ сами.", "Return here. We’ll recheck automatically."))
                }
                Button(I18n.tr("Показать приложение в Finder", "Show the app in Finder")) { capabilities.revealApplication() }.controlSize(.small)
            } else {
                Text(I18n.tr("macOS попросит вас включить Veylume. Это делаете только вы.", "macOS will ask you to enable Veylume. Only you can grant access.")).font(.callout)
            }
            Button(I18n.tr("Продолжить с ручным копированием", "Continue with manual Copy")) { preferences.value.onboardingStep = 4 }.buttonStyle(.link).font(.caption)
        }
    }
    private func instruction(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).font(.caption.weight(.semibold)).frame(width: 20, height: 20).background(.quaternary, in: Circle())
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var practiceView: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading(I18n.tr("Попробуем?", "Try it out"), I18n.tr("Произнесите короткую фразу — она появится здесь.", "Say a short phrase. It will appear here."), symbol: "text.bubble")
            TextEditor(text: $practice).font(.body).frame(height: 78).scrollContentBackground(.hidden).padding(8).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Button(session.phase == .recording ? I18n.tr("Остановить", "Stop") : I18n.tr("Записать фразу", "Record a phrase")) { if session.busy { session.stop() } else { session.start() } }.disabled(!models.activeReady || capabilities.microphone != .authorized || !session.storageAccessChecked || session.storageNeedsAuthorization || (session.busy && session.phase != .recording))
                if session.busy { Button(I18n.tr("Отмена", "Cancel")) { session.cancel() } }
                Text(session.status).font(.caption).foregroundStyle(.secondary)
            }
            Text(I18n.tr("Затем проверьте клавишу в своём редакторе. Enter приложение не нажимает.", "Next test the shortcut in your editor. Veylume never presses Enter.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var modelStatus: some View {
        if let manifest = models.catalogue.first(where: { $0.id == "parakeet-v3" }) {
            switch models.states[manifest.id] ?? .available {
            case .ready:
                HStack(spacing: 6) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text(I18n.tr("Модель готова · работает без сети", "Model ready · works offline")) }.font(.caption).foregroundStyle(.secondary)
            default:
                VStack(alignment: .leading, spacing: 7) {
                    HStack { Text(I18n.tr("Готовим Parakeet V3", "Preparing Parakeet V3")).font(.caption); Spacer(); modelAction(manifest) }
                    ModelProgress(manifest: manifest, models: models)
                }
            }
        }
    }
    @ViewBuilder private func modelAction(_ manifest: ModelManifest) -> some View {
        switch models.states[manifest.id] ?? .available {
        case .downloading, .verifying: Button(I18n.tr("Пауза", "Pause")) { models.pause(manifest.id) }.buttonStyle(.link).font(.caption)
        default: Button(I18n.tr("Повторить", "Retry")) { models.download(manifest.id, bootstrap: true) }.buttonStyle(.link).font(.caption)
        }
    }
    private var primaryTitle: String {
        if step == 1 && capabilities.microphone != .authorized { return capabilities.microphone == .notDetermined ? I18n.tr("Разрешить микрофон", "Allow microphone") : I18n.tr("Открыть настройки", "Open Settings") }
        if (step == 1 || step == 4) && session.storageNeedsAuthorization { return I18n.tr("Подключить хранилище", "Connect secure storage") }
        if step == 3 && !capabilities.accessibility { return capabilities.accessibilityRequested ? I18n.tr("Открыть Accessibility", "Open Accessibility") : I18n.tr("Разрешить доступ", "Allow access") }
        return step == 0 ? I18n.tr("Начать", "Get started") : step == 4 ? I18n.tr("Готово", "Done") : I18n.tr("Продолжить", "Continue")
    }
    private func primaryAction() {
        stopTesting()
        if step == 1 && capabilities.microphone != .authorized { Task { await capabilities.requestMicrophone() }; return }
        if (step == 1 || step == 4) && session.storageNeedsAuthorization { session.authorizeStorage(); return }
        if step == 3 && !capabilities.accessibility {
            if capabilities.accessibilityRequested { capabilities.openAccessibilitySettings() } else { capabilities.requestAccessibility() }; return
        }
        if step == 4 { preferences.value.onboardingCompleted = true; close() }
        else { preferences.value.onboardingStep += 1 }
    }
    private func stopTesting() { if testingMicrophone { session.cancel(); testingMicrophone = false } }
}
