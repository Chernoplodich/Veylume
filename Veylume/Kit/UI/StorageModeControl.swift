import SwiftUI
import VeylumeCore

struct StorageModeControl: View {
    @ObservedObject var session: SessionCoordinator
    @ObservedObject var preferences: PreferencesStore
    var body: some View {
        StorageModeSurface(selection: Binding(get: { preferences.value.usesProtectedStorage ? StorageMode.protected : .sessionOnly }, set: {
            if $0 == .sessionOnly { session.useSessionOnlyStorage() }
            else { preferences.value.storageMode = .protected }
        }), busy: session.busy, authorizing: session.authorizingStorage,
            needsAuthorization: session.storageNeedsAuthorization, checked: session.storageAccessChecked,
            afterUpdate: session.storageReconnectionAfterUpdate, connect: { session.authorizeStorage() })
    }
}

struct StorageModeSurface: View {
    @Binding var selection: StorageMode
    var busy = false, authorizing = false, needsAuthorization = false, checked = true, afterUpdate = false
    var connect: () -> Void
    @Environment(\.locale) private var locale
    var body: some View {
        let _ = locale.identifier
        GlassGroup {
            AppRow(title: I18n.tr("Хранилище", "Storage")) {
                NativePopup(selection: $selection, choices: [(I18n.tr("Без сохранения", "No saved dictations"), .sessionOnly),
                              (I18n.tr("Защищённое хранилище", "Encrypted storage"), .protected)],
                            label: I18n.tr("Хранилище", "Storage")).frame(width: 200)
                    .disabled(busy || authorizing)
            }
        }
        if selection == .sessionOnly {
            Text(I18n.tr("Диктовка и вставка работают без хранилища. История, словарь и восстановление выключены. Последний текст остаётся в памяти до следующего результата или выхода. Старые сохранения не удаляются.", "Dictation and insertion work without storage. History, vocabulary and crash recovery are off. The last result stays in memory until the next result or quit. Existing saved data is kept."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(I18n.tr("Подключить хранилище", "Connect secure storage"), action: connect)
                .controlSize(.small).disabled(busy || authorizing)
        } else if needsAuthorization || authorizing {
            StorageAccessSurface(busy: busy, authorizing: authorizing, afterUpdate: afterUpdate, connect: connect)
        } else if checked {
            Label(I18n.tr("Хранилище подключено", "Storage connected"), systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
