import SwiftUI

struct SecureStorageAction: View {
    @ObservedObject var session: SessionCoordinator
    var body: some View {
        StorageAccessSurface(busy: session.busy, authorizing: session.authorizingStorage,
                             afterUpdate: session.storageReconnectionAfterUpdate, connect: { session.authorizeStorage() })
    }
}

struct StorageAccessSurface: View {
    var busy = false, authorizing = false, afterUpdate = false
    var connect: () -> Void
    @Environment(\.locale) private var locale
    var body: some View {
        let _ = locale.identifier
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(I18n.tr("Подключить хранилище", "Connect secure storage"), action: connect)
                    .disabled(busy || authorizing)
                    .help(I18n.tr("В системном окне выберите «Разрешать всегда» для Veylume. Пароль вводится только в окне macOS.", "Choose Always Allow for Veylume in the system dialog. Enter your password only in macOS’s dialog."))
                if authorizing { ProgressView().controlSize(.small) }
            }
            Text(afterUpdate
                ? I18n.tr("После обновления подтвердите доступ к сохранённым данным. Диктовка и вставка уже работают; до подключения история, словарь и восстановление приостановлены.", "After this update, reconnect access to your saved data. Dictation and insertion already work; history, vocabulary and crash recovery are paused until you reconnect.")
                : I18n.tr("Сохранение включено, но нужен доступ к Связке ключей. Диктовка и вставка работают; история, словарь и восстановление временно приостановлены.", "Saved data is enabled, but Keychain access is needed. Dictation and insertion work; history, vocabulary and crash recovery are temporarily paused."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.controlSize(.small)
    }
}
