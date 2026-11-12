import SwiftUI

struct SecureStorageAction: View {
    @ObservedObject var session: SessionCoordinator
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(I18n.tr("Подключить хранилище", "Connect secure storage")) { session.authorizeStorage() }
                    .disabled(session.busy || session.authorizingStorage)
                if session.authorizingStorage { ProgressView().controlSize(.small) }
            }
            Text(I18n.tr("В системном окне выберите «Разрешать всегда» для Veylume. Пароль вводится только в окне macOS.", "Choose Always Allow for Veylume in the system dialog. Enter your password only in macOS’s dialog."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.controlSize(.small)
    }
}
