import SwiftUI
import VeylumeCore

struct SettingsContent: View {
    @ObservedObject var session: SessionCoordinator
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var models: ModelCoordinator
    @ObservedObject var capabilities: CapabilityCoordinator
    @ObservedObject var updates: UpdateCoordinator
    @ViewState private var selection: SettingsSection
    var repeatOnboarding: () -> Void
    init(session: SessionCoordinator, preferences: PreferencesStore, models: ModelCoordinator, capabilities: CapabilityCoordinator, updates: UpdateCoordinator, initialSection: SettingsSection, repeatOnboarding: @escaping () -> Void) {
        self.session = session; self.preferences = preferences; self.models = models; self.capabilities = capabilities; self.updates = updates; self.repeatOnboarding = repeatOnboarding
        _selection = State(initialValue: initialSection)
    }
    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection, updateAvailable: updates.availableVersion != nil) { updates.install() }
            SidebarDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch selection {
                    case .general: GeneralSettings(session: session, preferences: preferences, capabilities: capabilities, models: models, updates: updates, repeatOnboarding: repeatOnboarding)
                    case .models: ModelsSettings(session: session, models: models, preferences: preferences)
                    case .shortcuts: ShortcutSettings(session: session, preferences: preferences, capabilities: capabilities)
                    case .appearance: AppearanceSettings(session: session, preferences: preferences)
                    case .dictionary: DictionarySettings(session: session)
                    case .history: HistorySettings(session: session, preferences: preferences)
                    case .statistics: StatisticsSettings(session: session)
                    }
                    if preferences.saveError { Text(Problem.storage.message).foregroundStyle(.red).font(.caption) }
                }.padding(22).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.background { MaterialBackground(style: .glass).ignoresSafeArea() }
            .environment(\.locale, I18n.locale)
            .frame(minWidth: 600, minHeight: 430)
            .onDisappear { if session.recordingShortcut { session.recordingShortcut = false; session.refreshHotkeys() } }
    }
}

struct GeneralSettings: View {
    @ObservedObject var session: SessionCoordinator
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var capabilities: CapabilityCoordinator
    @ObservedObject var models: ModelCoordinator
    @ObservedObject var updates: UpdateCoordinator
    var repeatOnboarding: () -> Void
    @ViewState private var devices: [MicrophoneDevice] = []
    @ViewState private var diagnostics = false
    var body: some View {
        PageHeading(title: SettingsSection.general.title, subtitle: I18n.tr("Выберите микрофон — и можно начинать.", "Choose a microphone and start dictating."))
        Label(session.status, systemImage: session.busy ? "waveform" : "circle.fill").font(.caption).foregroundStyle(session.models.activeReady && capabilities.microphone == .authorized ? Color.green : Color.secondary)
        if let notice = session.notice { Text(notice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        GlassGroup {
            AppRow(title: I18n.tr("Микрофон", "Microphone")) {
                NativePopup(selection: Binding(get: { preferences.value.microphoneUID ?? "system" }, set: { preferences.value.microphoneUID = $0 == "system" ? nil : $0 }), choices: [(I18n.tr("Системное устройство", "System device"), "system")] + devices.map { ($0.name, $0.id) }, label: I18n.tr("Микрофон", "Microphone")).frame(width: 200).disabled(session.busy)
            }; Divider()
            OutputMuteSetting(enabled: Binding(get: { preferences.value.mutesOutputDuringRecording }, set: { preferences.value.muteOutputDuringRecording = $0 })).disabled(session.busy)
            Divider()
            AppRow(title: I18n.tr("Язык речи", "Speech language")) { SpeechLanguagePicker(preferences: preferences, manifest: models.active).disabled(session.busy) }; Divider()
            AppRow(title: I18n.tr("Язык интерфейса", "Interface language")) {
                NativePopup(selection: $preferences.value.uiLanguage, choices: [(I18n.tr("Как в системе", "System"), "system"), ("English", "en"), ("Русский", "ru"), ("Español", "es"), ("Français", "fr")], label: I18n.tr("Язык интерфейса", "Interface language")).frame(width: 200)
            }; Divider()
            AppRow(title: I18n.tr("Запускать при входе", "Launch at login")) {
                Toggle("", isOn: Binding(get: { capabilities.loginEnabled }, set: { enabled in
                    do { try capabilities.setLogin(enabled) }
                    catch { session.notice = I18n.tr("Не удалось изменить автозапуск. Проверьте Veylume в настройках macOS → Основные → Объекты входа.", "Could not change launch at login. Check Veylume in macOS Settings → General → Login Items.") }
                })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .help(I18n.tr("Открывать Veylume в строке меню при входе в macOS.", "Open Veylume in the menu bar when you sign in to macOS."))
            }
            if capabilities.loginApprovalRequired {
                HStack {
                    Text(I18n.tr("Подтвердите автозапуск в macOS", "Approve launch at login in macOS")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(I18n.tr("Открыть настройки…", "Open Settings…")) { capabilities.openLoginSettings() }.controlSize(.small)
                }.padding(12)
            }
        }
        PermissionSettings(capabilities: capabilities, hasShortcut: preferences.value.hasShortcuts, recheck: { session.refreshHotkeys() })
        GlassGroup {
            AppRow(title: I18n.tr("Автоматическая вставка", "Automatic insertion")) { Toggle("", isOn: $preferences.value.automaticInsertion).labelsHidden().toggleStyle(.switch).controlSize(.small) }
            if preferences.value.automaticInsertion && capabilities.clipboardAccessDenied {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text(I18n.tr("macOS запретила доступ к буферу. Разрешите его для сохранения прежнего содержимого при вставке.", "macOS has denied clipboard access. Allow it to preserve the previous contents during paste."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(I18n.tr("Настроить доступ к буферу", "Set up clipboard access")) { capabilities.openClipboardSettings() }.controlSize(.small)
                }.padding(12)
            }
        }
        StorageModeControl(session: session, preferences: preferences)
        GlassGroup {
            AppRow(title: I18n.tr("Проверять обновления", "Check for updates")) { Toggle("", isOn: $preferences.value.automaticallyCheckUpdates).labelsHidden().toggleStyle(.switch).controlSize(.small) }
            if !updates.configured { Text(I18n.tr("Лента подписанных обновлений ещё не настроена для этой локальной сборки.", "A signed update feed is not configured for this local build.")).font(.caption).foregroundStyle(.secondary).padding(12) }
        }
        HStack {
            Button(I18n.tr("Диагностика…", "Diagnostics…")) { diagnostics = true }
            Button(I18n.tr("Повторить обучение", "Repeat setup"), action: repeatOnboarding)
        }.controlSize(.small)
        Button(I18n.tr("Проверить обновления", "Check for updates")) { updates.check() }.disabled(!updates.configured || updates.checking)
            .sheet(isPresented: $diagnostics) { DiagnosticsContent(session: session, capabilities: capabilities) }
            .onAppear { devices = AudioCaptureService.devices(); capabilities.refresh() }
        if let message = updates.message { Text(message).font(.caption).foregroundStyle(.secondary) }
    }
}

struct OutputMuteSetting: View {
    @Binding var enabled: Bool
    var body: some View {
        AppRow(title: I18n.tr("Отключать звук при записи", "Mute Mac audio while recording")) {
            Toggle("", isOn: $enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .accessibilityLabel(I18n.tr("Отключать звук при записи", "Mute Mac audio while recording"))
        }.help(I18n.tr("Музыка и системные звуки отключаются на время записи, затем возвращаются. Поддержка зависит от аудиовыхода. Ваши изменения громкости сохраняются.", "Music and system sounds are muted during recording, then restored. Support depends on the audio output. Your own volume changes are preserved."))
    }
}

struct SpeechLanguagePicker: View {
    @ObservedObject var preferences: PreferencesStore
    let manifest: ModelManifest?
    var body: some View {
        let automatic: [(String, String)] = manifest?.supportsAutoLanguage != false ? [(I18n.tr("Автоматически", "Automatic"), "auto")] : [(I18n.tr("Выберите язык…", "Choose a language…"), "choose")]
        let languages = manifest?.supportsLanguageHint == true ? manifest!.languages.map { (I18n.locale.localizedString(forLanguageCode: $0) ?? $0, $0) } : []
        NativePopup(selection: $preferences.value.speechLanguage, choices: automatic + languages, label: I18n.tr("Язык речи", "Speech language")).frame(width: 200)
    }
}

struct PermissionSettings: View {
    @ObservedObject var capabilities: CapabilityCoordinator
    let hasShortcut: Bool
    var recheck: () -> Void = {}
    @ViewState private var checked = false
    var body: some View {
        FullRowDisclosure(title: I18n.tr("Доступ для записи и вставки", "Recording and insertion access")) {
            permissionRow(I18n.tr("Микрофон", "Microphone"), allowed: capabilities.microphone == .authorized) { Task { await capabilities.requestMicrophone() } }
            permissionRow(I18n.tr("Вставка и клавиши", "Insertion and shortcuts"), allowed: capabilities.accessibility) { if capabilities.accessibilityRequested { capabilities.openAccessibilitySettings() } else { capabilities.requestAccessibility() } }
            if capabilities.clipboardAccessDenied {
                permissionRow(I18n.tr("Буфер обмена", "Clipboard"), allowed: false) { capabilities.openClipboardSettings() }
            }
            HStack {
                Button(I18n.tr("Настройки macOS…", "macOS Settings…")) { capabilities.openSystemSettings() }
                Spacer()
                Button(checked ? I18n.tr("Проверить ещё раз", "Check again") : I18n.tr("Проверить доступ", "Recheck access")) { capabilities.refresh(); recheck(); checked = true }
            }.controlSize(.small)
            if checked {
                let available = capabilities.microphone == .authorized && capabilities.accessibility && !capabilities.clipboardAccessDenied
                Label(available ? I18n.tr("Проверено: запись и вставка доступны", "Checked: recording and insertion are available") : I18n.tr("Проверено: разрешите доступы, отмеченные выше", "Checked: allow the access marked above"), systemImage: available ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.caption).foregroundStyle(available ? Color.green : .secondary)
            }
            if capabilities.secureInput { Text(I18n.tr("Защищённый ввод включён. Выйдите из поля пароля для работы клавиш.", "Secure Input is enabled. Leave the password field to use shortcuts.")).font(.caption).foregroundStyle(.secondary) }
            PermissionGuidance(capabilities: capabilities)
        }.disabled(AppPaths.needsInstallation)
    }
    private func permissionRow(_ name: String, allowed: Bool, request: @escaping () -> Void) -> some View {
        HStack {
            Label(name, systemImage: allowed ? "checkmark.circle.fill" : "circle").foregroundStyle(allowed ? Color.green : .primary)
            Spacer()
            if !allowed { Button(I18n.tr("Разрешить…", "Allow…"), action: request).controlSize(.small) }
        }.font(.system(size: 12))
    }
}

struct PermissionGuidance: View {
    @ObservedObject var capabilities: CapabilityCoordinator
    var body: some View {
        if capabilities.guidance != nil && !capabilities.accessibility {
            Text(I18n.tr("Нет Veylume в списке? Добавьте установленное приложение через «+».", "Veylume missing? Add the installed app using “+”.")).font(.caption).foregroundStyle(.secondary)
            Button(I18n.tr("Показать Veylume в Finder", "Show Veylume in Finder")) { capabilities.revealApplication() }.controlSize(.small)
        }
    }
}
