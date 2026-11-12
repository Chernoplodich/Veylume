import SwiftUI
import VeylumeCore

/// Shown once when launch/upgrade loses a required capability. No automatic
/// permission prompts; the user initiates each system request from this view.
struct ReadinessContent: View {
    @ObservedObject var session: SessionCoordinator
    @ObservedObject var capabilities: CapabilityCoordinator
    var close: () -> Void
    private var step: SetupStep { session.setupStep }
    var body: some View {
        ReadinessSurface(step: step, microphoneReady: capabilities.microphone == .authorized,
            externalReady: capabilities.accessibility || !(session.preferences.value.hasShortcuts || session.preferences.value.automaticInsertion),
            storageReady: session.storageAccessChecked && !session.storageNeedsAuthorization,
            authorizingStorage: session.authorizingStorage, close: close, advance: advance)
            .task {
                while !Task.isCancelled {
                    capabilities.refresh(); session.refreshHotkeys()
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
    }
    private func advance() {
        switch step {
        case .checking: break
        case .microphone: Task { await capabilities.requestMicrophone() }
        case .accessibility: capabilities.requestAccessibility(); capabilities.openAccessibilitySettings()
        case .storage: session.authorizeStorage()
        case .ready: close()
        }
    }
}

/// Production layout with explicit state, also rendered through every step by
/// native regression fixtures without accessing real permissions or Keychain.
struct ReadinessSurface: View {
    let step: SetupStep
    let microphoneReady: Bool, externalReady: Bool, storageReady: Bool
    var authorizingStorage = false
    var close: () -> Void, advance: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        BrandAvatar(size: 32)
                        Text(I18n.tr("Подготовим Veylume", "Get Veylume ready")).font(.system(size: 20, weight: .semibold))
                    }
                    Text(I18n.tr("Проверим доступы перед первой записью.", "Check access before your first recording.")).font(.system(size: 13)).foregroundStyle(.secondary)
                    GlassGroup {
                        status(I18n.tr("Микрофон", "Microphone"), ready: microphoneReady)
                        Divider()
                        status(I18n.tr("Вставка и клавиши", "Insertion and shortcuts"), ready: externalReady)
                        Divider()
                        status(I18n.tr("Защищённое хранилище", "Secure storage"), ready: storageReady)
                    }
                    Text(explanation).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    if step == .storage {
                        Text(I18n.tr("Если macOS спросит, выберите «Разрешать всегда». Пароль вводится только в системном окне.", "If macOS asks, choose Always Allow. Enter your password only in the system dialog.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.hidden)
            Divider()
            HStack {
                Button(I18n.tr("Позже", "Later"), action: close).buttonStyle(.borderless).foregroundStyle(.secondary)
                Spacer()
                if authorizingStorage || step == .checking { ProgressView().controlSize(.small) }
                Button(actionTitle, action: advance).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(step == .checking || authorizingStorage)
            }.controlSize(.large).padding(.horizontal, 24).padding(.vertical, 16)
        }.background { MaterialBackground(style: .glass).ignoresSafeArea() }
    }
    private func status(_ title: String, ready: Bool) -> some View {
        HStack { Text(title); Spacer(); Image(systemName: ready ? "checkmark.circle.fill" : "circle").foregroundStyle(ready ? Color.green : Color.secondary).accessibilityLabel(ready ? I18n.tr("Готово", "Ready") : I18n.tr("Нужен доступ", "Access needed")) }.padding(12).font(.system(size: 13))
    }
    private var explanation: String {
        switch step {
        case .checking: return I18n.tr("Проверяем доступ к локальным ключам без системных запросов.", "Checking local key access without system prompts.")
        case .microphone: return I18n.tr("Разрешите микрофон. Он включается только для записи.", "Allow the microphone. It turns on only for recording.")
        case .accessibility: return I18n.tr("В настройках macOS включите Veylume в Accessibility, затем вернитесь сюда.", "Enable Veylume under Accessibility in macOS settings, then return here.")
        case .storage: return I18n.tr("Подключите ключ шифрования для защиты временных записей и сохранённых данных.", "Connect the encryption key to protect temporary recordings and saved data.")
        case .ready: return I18n.tr("Доступы готовы. Можно вернуться в своё приложение и начать диктовку.", "Access is ready. Return to your app and start dictating.")
        }
    }
    private var actionTitle: String {
        switch step {
        case .checking: return I18n.tr("Проверяем…", "Checking…")
        case .microphone: return I18n.tr("Разрешить микрофон", "Allow microphone")
        case .accessibility: return I18n.tr("Открыть Accessibility", "Open Accessibility")
        case .storage: return I18n.tr("Подключить хранилище", "Connect secure storage")
        case .ready: return I18n.tr("Готово", "Done")
        }
    }
}
