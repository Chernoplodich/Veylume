import Foundation
import AppKit
import VeylumeCore

enum AppPaths {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "local.Veylume.dev", isDirectory: true)
    }
    static func directory(_ component: String) throws -> URL {
        let url = root.appendingPathComponent(component, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]); return url
    }
    static var needsInstallation: Bool {
        let path = Bundle.main.bundleURL.path
        return path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
    }
}

@MainActor final class PreferencesStore: ObservableObject {
    @Published var value: Preferences { didSet { persist(); onChange?() } }
    @Published private(set) var saveError = false
    var onChange: (() -> Void)?
    private let url: URL
    init(root: URL = AppPaths.root) {
        url = root.appendingPathComponent("preferences.json")
        if let data = try? Data(contentsOf: url), var decoded = try? JSONDecoder().decode(Preferences.self, from: data), decoded.version == 1 { decoded.migrateSettings(); value = decoded }
        else { value = Preferences() }
        I18n.language = value.uiLanguage
    }
    private func persist() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            I18n.language = value.uiLanguage; saveError = false
        } catch { saveError = true }
    }
}

enum I18n {
    static var language = "system"
    static let supportedLanguages = ["en", "ru", "es", "fr"]
    static func resolveLanguage(_ preference: String, preferred: [String] = Locale.preferredLanguages) -> String {
        let candidates = preference == "system" ? preferred : [preference]
        return candidates.lazy.map { $0.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init) ?? "en" }
            .first(where: { supportedLanguages.contains($0) }) ?? "en"
    }
    static var languageCode: String { resolveLanguage(language) }
    private static let bundles: [String: Bundle] = Dictionary(uniqueKeysWithValues: supportedLanguages.compactMap { code in
        guard let url = Bundle.module.url(forResource: code, withExtension: "lproj"), let bundle = Bundle(url: url) else { return nil }
        return (code, bundle)
    })
    static func tr(_ ru: String, _ en: String) -> String {
        let code = languageCode
        return bundles[code]?.localizedString(forKey: en, value: code == "ru" ? ru : en, table: "Localizable") ?? (code == "ru" ? ru : en)
    }
    static var locale: Locale { Locale(identifier: languageCode) }
    static func format(_ ru: String, _ en: String, _ values: CVarArg...) -> String {
        String(format: tr(ru, en), locale: locale, arguments: values)
    }
    static func date(_ date: Date) -> String { date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute().locale(locale)) }
    static func bytes(_ count: Int64) -> String { count.formatted(.byteCount(style: .file).locale(locale)) }
    static func duration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter(); formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]; formatter.unitsStyle = .abbreviated
        var calendar = Calendar.current; calendar.locale = locale; formatter.calendar = calendar
        return formatter.string(from: max(0, seconds)) ?? "0"
    }
}

enum Problem: String, Error {
    case microphone, modelNotReady, language, noSpeech, capture, overflow, deviceChanged, storage, keychain, recognition, incomplete, pendingLimit, permissionChanged, cancelled, modelIntegrity, download, lowDisk
    var message: String {
        switch self {
        case .microphone: return I18n.tr("Разрешите микрофон в Системных настройках.", "Allow microphone access in System Settings.")
        case .modelNotReady: return I18n.tr("Модель ещё не готова. Откройте подготовку модели.", "The model isn’t ready. Open model preparation.")
        case .language: return I18n.tr("Выберите поддерживаемый язык речи в настройках модели.", "Choose a supported speech language in model settings.")
        case .noSpeech: return I18n.tr("Речь не обнаружена. Попробуйте более длинную фразу.", "No speech detected. Try a longer phrase.")
        case .overflow: return I18n.tr("Не удалось сохранить аудио вовремя. Запись остановлена.", "Audio could not be stored in time. Recording stopped.")
        case .deviceChanged: return I18n.tr("Аудиоустройство изменилось. Начните новую запись.", "The audio device changed. Start a new recording.")
        case .keychain: return I18n.tr("Нужен доступ к Связке ключей. Подключите защищённое хранилище.", "Keychain access is needed. Connect secure storage.")
        case .storage: return I18n.tr("Не удалось сохранить защищённые данные. Проверьте свободное место.", "Couldn’t save protected data. Check free disk space.")
        case .recognition: return I18n.tr("Не удалось распознать. Доступную запись можно повторить в разделе восстановления.", "Transcription failed. Retry available audio in Recovery.")
        case .incomplete: return I18n.tr("Модель достигла ограничения текста. Полный результат не подтверждён; автоматическая вставка отменена.", "The model reached its text limit. The result may be incomplete; automatic insertion was skipped.")
        case .pendingLimit: return I18n.tr("Сначала обработайте временные результаты: достигнут лимит 10.", "Resolve temporary results first: the limit of 10 has been reached.")
        case .permissionChanged: return I18n.tr("Доступ изменился. Запись остановлена; повторно проверьте разрешения.", "Access changed. Recording stopped; check permissions again.")
        case .modelIntegrity: return I18n.tr("Файлы модели не прошли проверку. Удалите комплект и скачайте снова.", "Model files failed verification. Remove the model and download it again.")
        case .download: return I18n.tr("Загрузка не завершена. Проверьте сеть и повторите.", "Download didn’t finish. Check your connection and retry.")
        case .lowDisk: return I18n.tr("Недостаточно места для модели и безопасной подготовки.", "Not enough disk space to download and prepare the model.")
        case .cancelled: return I18n.tr("Отменено", "Cancelled")
        case .capture: return I18n.tr("Не удалось начать запись. Выберите доступный микрофон.", "Couldn’t start recording. Choose an available microphone.")
        }
    }
}
