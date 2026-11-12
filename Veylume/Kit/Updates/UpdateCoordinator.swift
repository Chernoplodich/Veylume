import Foundation
import Sparkle

@MainActor final class UpdateCoordinator: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var availableVersion: String?
    @Published private(set) var configured = false
    @Published private(set) var checking = false
    @Published var message: String?
    private weak var session: SessionCoordinator?
    private var controller: SPUStandardUpdaterController?
    private var timer: Timer?
    private var postponed: (() -> Void)?
    init(session: SessionCoordinator) {
        self.session = session; super.init()
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else { return }
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        do {
            try controller?.updater.start()
            controller?.updater.automaticallyChecksForUpdates = false
            controller?.updater.automaticallyDownloadsUpdates = false
            controller?.updater.sendsSystemProfile = false
            configured = true
            timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in Task { @MainActor in self?.check(automatic: true) } }
            Task { try? await Task.sleep(for: .seconds(3)); check(automatic: true) }
        } catch { message = I18n.tr("Не удалось запустить проверку обновлений.", "Couldn’t start update checking.") }
    }
    func check(automatic: Bool = false) {
        guard configured, !checking, let session else { return }
        if automatic && !session.preferences.value.automaticallyCheckUpdates { return }
        checking = true; message = nil; controller?.updater.checkForUpdateInformation()
    }
    func install() {
        guard let session, !session.busy, session.unresolvedCount == 0, availableVersion != nil else {
            message = I18n.tr("Завершите запись и обработайте временные результаты перед обновлением.", "Finish recording and resolve temporary results before updating."); return
        }
        controller?.checkForUpdates(nil)
    }
    func resumeIfSafe() {
        guard let session, !session.busy, session.unresolvedCount == 0, let postponed else { return }
        self.postponed = nil; postponed()
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { checking = false; availableVersion = item.displayVersionString }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) { checking = false; availableVersion = nil; message = I18n.tr("Установлена актуальная версия.", "You’re up to date.") }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { checking = false; message = I18n.tr("Проверка обновлений не завершена. Повторите позже.", "Update checking didn’t finish. Try again later.") }
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        if updateCheck == .updateInformation { return }
        guard let session, !session.busy, session.unresolvedCount == 0 else {
            throw NSError(domain: "Veylume.Update", code: 1, userInfo: [NSLocalizedDescriptionKey: I18n.tr("Завершите запись и обработайте результаты.", "Finish recording and resolve temporary results.")])
        }
    }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard let session else { return true }
        if session.busy || session.unresolvedCount > 0 { postponed = installHandler; return true }; return false
    }
    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool { session.map { !$0.busy && $0.unresolvedCount == 0 } ?? false }
    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool { false }
}
