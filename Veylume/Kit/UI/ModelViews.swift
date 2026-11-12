import SwiftUI
import VeylumeCore

struct ModelsSettings: View {
    @ObservedObject var session: SessionCoordinator
    @ObservedObject var models: ModelCoordinator
    @ObservedObject var preferences: PreferencesStore
    @ViewState private var details: ModelManifest?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeading(title: SettingsSection.models.title, subtitle: I18n.tr("Выберите, что важнее: скорость или точность.", "Choose the balance of speed and accuracy that suits you."))
            ForEach(models.catalogue) { manifest in
                GlassGroup {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 7) {
                            ProviderBadge(publisher: manifest.publisher)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(manifest.name).font(.system(size: 12, weight: .medium))
                                Text(manifest.publisher + " · " + manifest.engine).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { details = manifest } label: { Image(systemName: "info.circle") }.buttonStyle(.plain).accessibilityLabel(I18n.tr("Подробнее о модели", "Model details"))
                        }
                        HStack(spacing: 12) {
                            RatingView(title: I18n.tr("Скорость", "Speed"), value: manifest.speed)
                            RatingView(title: I18n.tr("Точность", "Accuracy"), value: manifest.accuracy)
                            Spacer(minLength: 0)
                        }
                        Text(manifest.id == "cohere-transcribe" ? I18n.tr("14 языков · без русского · язык задаётся явно", "14 languages · no Russian · explicit language") : I18n.tr("Русский и английский", "Russian and English")).font(.system(size: 10)).foregroundStyle(.secondary)
                        HStack {
                            Text(I18n.bytes(manifest.downloadBytes)).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            modelActions(manifest)
                        }
                        if case .downloading = models.states[manifest.id] { ModelProgress(manifest: manifest, models: models) }
                        if case .verifying = models.states[manifest.id] { ModelProgress(manifest: manifest, models: models) }
                        if case .failed(let problem) = models.states[manifest.id] { Text(problem.message).font(.caption).foregroundStyle(.secondary) }
                    }.padding(12)
                }
            }
            Text(I18n.tr("Шкалы 1–5 — редакционные уровни, не проценты точности. Размеры относятся к этому полному комплекту Core ML, включая токенизатор.", "The 1–5 scales are editorial levels, not accuracy percentages. Sizes refer to these complete Core ML bundles, including tokenizers.")).font(.caption).foregroundStyle(.secondary)
            GlassGroup {
                AppRow(title: I18n.tr("Быстрый запуск", "Quick start"), detail: I18n.tr("Держать модель в памяти. В сбалансированном режиме — выгрузка через 15 минут бездействия.", "Keep the model in memory. Balanced mode unloads after 15 idle minutes.")) {
                    Toggle("", isOn: $preferences.value.keepModelWarm).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            if models.active?.id == "cohere-transcribe" {
                AppRow(title: I18n.tr("Язык Cohere", "Cohere language")) { SpeechLanguagePicker(preferences: preferences, manifest: models.active) }
            }
        }.sheet(item: $details) { ModelDetails(manifest: $0, session: session) }
    }
    @ViewBuilder private func modelActions(_ manifest: ModelManifest) -> some View {
        switch models.states[manifest.id] ?? .available {
        case .ready:
            if models.active?.id == manifest.id { Text(I18n.tr("Активна", "Active")).font(.caption).foregroundStyle(.green) }
            else { Button(I18n.tr("Выбрать", "Use")) { models.select(manifest) }.disabled(session.busy).controlSize(.small) }
            Button { FileActions.confirm(I18n.tr("Удалить модель?", "Remove model?"), explanation: I18n.tr("Комплект можно скачать снова. Другие модели и ваши данные сохранятся.", "You can download it again. Other models and your data will remain.")) { Task { do { try await models.remove(manifest) } catch { session.notice = Problem.storage.message } } } } label: { Image(systemName: "trash") }.disabled(session.busy).controlSize(.small).accessibilityLabel(I18n.tr("Удалить модель", "Remove model"))
        case .downloading, .verifying:
            Button(I18n.tr("Пауза", "Pause")) { models.pause(manifest.id) }.controlSize(.small)
        default:
            Button(I18n.tr("Скачать", "Download")) {
                models.download(manifest.id, bootstrap: manifest.id == "parakeet-v3" && preferences.value.bootstrap != .completed)
            }.disabled(session.busy || ProcessInfo.processInfo.operatingSystemVersion.majorVersion < manifest.minimumOS).controlSize(.small)
        }
    }
}

struct ModelProgress: View {
    let manifest: ModelManifest
    @ObservedObject var models: ModelCoordinator
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch models.states[manifest.id] ?? .available {
            case let .downloading(received, total):
                ProgressView(value: Double(received), total: Double(max(1, total)))
                Text(I18n.bytes(received) + " / " + I18n.bytes(total)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            case .verifying: HStack { ProgressView().controlSize(.small); Text(I18n.tr("Проверка и подготовка…", "Verifying and preparing…")).font(.caption) }
            case .ready: Label(I18n.tr("Модель готова", "Model is ready"), systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
            case .paused: Text(I18n.tr("Загрузка приостановлена", "Download paused")).font(.caption)
            case .failed(let problem): Text(problem.message).font(.caption)
            case .available: Text(I18n.tr("Нужна первоначальная загрузка", "Initial download needed")).font(.caption)
            }
        }
    }
}

struct ModelDetails: View {
    let manifest: ModelManifest
    @ObservedObject var session: SessionCoordinator
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(manifest.name).font(.title3)
            Text(manifest.publisher + " · " + manifest.engine + " · macOS \(manifest.minimumOS)+")
            Text(I18n.format("Рекомендуемая память: %d ГБ", "Recommended memory: %d GB", manifest.recommendedMemoryGB)).font(.caption)
            Text(I18n.tr("Ревизия: ", "Revision: ") + manifest.revision).font(.caption).textSelection(.enabled)
            Text(manifest.license).font(.caption)
            HStack { Link(I18n.tr("Карточка модели", "Model card"), destination: manifest.modelCardURL); Link(I18n.tr("Лицензия", "License"), destination: manifest.licenseURL) }
            Text(I18n.tr("Замер на этом Mac", "Measurement on this Mac")).font(.headline)
            if let m = session.measurement, m.modelID == manifest.id {
                Text(I18n.format("Загрузка %.2f с · ASR %.2f с · RTF %.3f", "Load %.2f s · ASR %.2f s · RTF %.3f", m.loadSeconds, m.recognitionSeconds, m.rtf)).font(.caption)
                Text(m.cold ? I18n.tr("Холодная загрузка", "Cold load") : I18n.tr("Тёплая модель", "Warm model")).font(.caption)
            } else { Text(I18n.tr("Не измерено", "Not measured")).font(.caption).foregroundStyle(.secondary) }
            Text(I18n.tr("Языки: ", "Languages: ") + manifest.languages.map { I18n.locale.localizedString(forLanguageCode: $0) ?? $0 }.joined(separator: ", ")).font(.caption).fixedSize(horizontal: false, vertical: true)
            Button(I18n.tr("Закрыть", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
        }.padding(24).frame(width: 450)
    }
}
