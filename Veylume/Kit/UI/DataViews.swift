import SwiftUI
import UniformTypeIdentifiers
import VeylumeCore

struct DictionarySettings: View {
    @ObservedObject var session: SessionCoordinator
    @ViewState private var draft = DictionaryDocument()
    @ViewState private var term = ""
    @ViewState private var source = ""
    @ViewState private var replacement = ""
    @ViewState private var preview = ""
    @ViewState private var wholeWord = true
    @ViewState private var caseSensitive = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeading(title: SettingsSection.dictionary.title, subtitle: I18n.tr("Термины и буквальные замены без переписывания стиля.", "Terms and literal replacements without rewriting your style."))
            if !session.storageAvailable { StorageModeControl(session: session, preferences: session.preferences) }
            Text(I18n.tr("Подсказки терминов в выбранных комплектах пока не включены. Замены применяются после распознавания, за один проход.", "Vocabulary hints are not enabled in these bundles yet. Replacements run after transcription in a single pass.")).font(.caption).foregroundStyle(.secondary)
            GlassGroup {
                ForEach(Array(draft.terms.enumerated()), id: \.offset) { index, value in
                    AppRow(title: value) { Button { draft.terms.remove(at: index) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).accessibilityLabel(I18n.tr("Удалить термин", "Remove term")) }
                }
                HStack { TextField(I18n.tr("Имя или термин", "Name or term"), text: $term); Button(I18n.tr("Добавить", "Add")) { if !term.isEmpty { draft.terms.append(term); term = "" } }.disabled(term.isEmpty) }.padding(12)
            }
            Text(I18n.tr("Замены", "Replacements")).font(.headline)
            GlassGroup {
                ForEach(draft.replacements) { rule in
                    AppRow(title: rule.source + " → " + rule.replacement, detail: (rule.wholeWord ? I18n.tr("Целое слово/фраза", "Whole word/phrase") : I18n.tr("Буквальное совпадение", "Literal match")) + (rule.caseSensitive ? I18n.tr(" · с учётом регистра", " · case sensitive") : "")) {
                        Button { draft.replacements.removeAll { $0.id == rule.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).accessibilityLabel(I18n.tr("Удалить замену", "Remove replacement"))
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { TextField(I18n.tr("Заменить", "Replace"), text: $source); TextField(I18n.tr("На", "With"), text: $replacement) }
                    Toggle(I18n.tr("Целое слово или фраза", "Whole word or phrase"), isOn: $wholeWord).font(.caption)
                    Toggle(I18n.tr("С учётом регистра", "Case sensitive"), isOn: $caseSensitive).font(.caption)
                    Button(I18n.tr("Добавить замену", "Add replacement")) { draft.replacements.append(ReplacementRule(source: source, replacement: replacement, wholeWord: wholeWord, caseSensitive: caseSensitive)); source = ""; replacement = "" }.disabled(source.isEmpty)
                }.padding(12)
            }
            TextField(I18n.tr("Текст для проверки замен", "Text to preview replacements"), text: $preview)
            if !preview.isEmpty { Text(TextFinalizer.apply(preview, rules: draft.replacements)).textSelection(.enabled).font(.callout).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8)) }
            HStack {
                Button(I18n.tr("Сохранить", "Save")) { Task { do { try await session.saveDictionary(draft) } catch { session.notice = I18n.tr("Проверьте размер словаря и доступ к защищённому хранилищу.", "Check the dictionary size and secure storage access.") } } }.disabled(!session.storageAvailable || session.busy)
                Button(I18n.tr("Импорт…", "Import…")) { importDictionary() }
                Button(I18n.tr("Экспорт…", "Export…")) { if let data = try? JSONEncoder().encode(draft) { FileActions.save(data, name: "Veylume-dictionary.json", type: .json) } }
            }.controlSize(.small)
            if let notice = session.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
        }.onAppear { draft = session.dictionary }
            .task(id: session.storageAvailable) {
                if session.storageAvailable {
                    await session.refreshData()
                    if draft.terms.isEmpty && draft.replacements.isEmpty { draft = session.dictionary }
                }
            }
    }
    private func importDictionary() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey]); guard (values.fileSize ?? Int.max) <= 2 * 1024 * 1024 else { throw ValidationError.dictionary }
            let document = try JSONDecoder().decode(DictionaryDocument.self, from: Data(contentsOf: url)); try document.validate(); draft = document
        } catch { FileActions.showFailure() }
    }
}

struct HistorySettings: View {
    @ObservedObject var session: SessionCoordinator
    @ObservedObject var preferences: PreferencesStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeading(title: SettingsSection.history.title, subtitle: session.unresolvedCount >= 10 ? Problem.pendingLimit.message : I18n.tr("Вы решаете, сохранять ли тексты диктовок.", "Choose whether to keep dictation text."))
            StorageModeControl(session: session, preferences: preferences)
            GlassGroup {
                AppRow(title: I18n.tr("Сохранять текст локально", "Save text locally")) { Toggle("", isOn: $preferences.value.historyEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(!session.storageAvailable || session.busy) }
                if preferences.value.historyEnabled {
                    Divider(); AppRow(title: I18n.tr("Хранить", "Keep for")) {
                        Picker("", selection: $preferences.value.historyDays) { ForEach([7, 30, 90], id: \.self) { Text("\($0) " + I18n.tr("дней", "days")).tag($0) }; Text(I18n.tr("До удаления", "Until deleted")).tag(0) }.labelsHidden().frame(width: 150)
                    }
                }
                Text(session.storageAvailable && preferences.value.historyEnabled ? I18n.tr("Сохраняется только текст новых диктовок. Аудио в историю не попадает.", "Only new dictation text is saved. Audio is never added to history.") : I18n.tr("Новые тексты сейчас не сохраняются. Существующие зашифрованные данные остаются до удаления или истечения срока.", "New text is not being saved. Existing encrypted data remains until deletion or expiry.")).font(.caption).foregroundStyle(.secondary).padding(12)
            }
            if !session.history.isEmpty {
                ForEach(session.history) { entry in
                    GlassGroup {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(entry.date, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                            Text(entry.text).font(.callout).textSelection(.enabled)
                            Button(I18n.tr("Скопировать", "Copy")) { session.copyText(entry.text) }.controlSize(.small)
                        }.padding(12)
                    }
                }
                HStack {
                    Button(I18n.tr("Экспорт истории…", "Export history…")) {
                        let text = session.history.map { $0.date.ISO8601Format() + "\n" + $0.text }.joined(separator: "\n\n")
                        FileActions.save(Data(text.utf8), name: "Veylume-history.txt", type: .plainText)
                    }
                    Button(I18n.tr("Удалить историю…", "Delete history…")) { FileActions.confirm(I18n.tr("Удалить историю?", "Delete history?"), explanation: I18n.tr("Только сохранённые тексты. Статистика, модели и словарь останутся.", "Only saved text is deleted. Statistics, models, and your dictionary remain.")) { Task { await session.clearHistory() } } }
                }.controlSize(.small)
            }
            Text(I18n.tr("Временное восстановление", "Temporary recovery")).font(.headline)
            GlassGroup { AppRow(title: I18n.tr("Восстановление после сбоя", "Recovery after failure")) { Toggle("", isOn: $preferences.value.recoveryEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(!session.storageAvailable || session.busy) } }
            if session.storageAvailable {
                Text(I18n.tr("Защищённые аудио и текст доступны до 24 часов; максимум 10. После успеха или отмены временное аудио удаляется. При выключенной программе очистка произойдёт при следующем запуске. Выключение настройки не удаляет старые восстановления.", "Protected audio and text are available for up to 24 hours; at most 10. Temporary audio is removed after success or cancellation. When the app is closed, cleanup happens next launch. Turning this off does not delete existing recovery.")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(session.pending) { entry in
                GlassGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.incomplete ? I18n.tr("Неполный результат", "Incomplete result") : entry.outcome == .dispatchedUnverified ? I18n.tr("Вставка не подтверждена", "Insertion unverified") : I18n.tr("Текст готов", "Text is ready")).font(.caption).foregroundStyle(.secondary)
                        Text(entry.text).font(.callout).textSelection(.enabled)
                        HStack { Button(I18n.tr("Скопировать", "Copy")) { session.copy(entry) }; Button(I18n.tr("Удалить", "Delete")) { Task { await session.removePending(entry) } } }.controlSize(.small)
                    }.padding(12)
                }
            }
            ForEach(session.audioRecovery) { entry in
                GlassGroup {
                    AppRow(title: I18n.tr("Незавершённая запись", "Unfinished recording"), detail: I18n.date(entry.metadata.startedAt) + " · " + I18n.duration(Double(entry.metadata.samples) / 16000)) {
                        Button(I18n.tr("Повторить", "Retry")) { session.retry(entry) }.disabled(session.busy)
                        Button { Task { await session.deleteAudio(entry) } } label: { Image(systemName: "trash") }.disabled(session.busy).accessibilityLabel(I18n.tr("Удалить запись", "Delete recording"))
                    }.controlSize(.small)
                }
            }
            if session.unresolvedCount == 0 { Text(I18n.tr("Временных результатов нет.", "No temporary results.")).font(.caption).foregroundStyle(.secondary) }
            Button(I18n.tr("Очистить все данные…", "Erase all data…"), role: .destructive) {
                FileActions.confirm(I18n.tr("Очистить данные Veylume?", "Erase Veylume data?"), explanation: I18n.tr("Будут удалены модели, история, восстановления, статистика, словарь и настройки. Автозапуск будет выключен. Системные разрешения macOS не сбрасываются.", "Models, history, recovery, statistics, dictionary, and settings will be deleted. Login launch will be disabled. macOS permissions are not reset.")) { Task { await session.eraseAllData() } }
            }.disabled(session.busy)
        }.task { await session.refreshData() }
    }
}

struct StatisticsSettings: View {
    @ObservedObject var session: SessionCoordinator
    var body: some View {
        PageHeading(title: SettingsSection.statistics.title, subtitle: I18n.tr("Локальные агрегаты без содержания диктовок.", "Local aggregates without dictation content."))
        GlassGroup {
            AppRow(title: I18n.tr("Слова", "Words")) { Text(session.statistics.words, format: .number).monospacedDigit() }
            Divider(); AppRow(title: I18n.tr("Завершённые записи", "Completed recordings")) { Text(session.statistics.recordings, format: .number).monospacedDigit() }
            Divider(); AppRow(title: I18n.tr("Время записи", "Recording time")) { Text(I18n.duration(session.statistics.duration)).monospacedDigit() }
            Divider(); AppRow(title: I18n.tr("Самая длинная", "Longest recording")) { Text(I18n.duration(session.statistics.longest)).monospacedDigit() }
        }
        Text(I18n.tr("Последние 7 дней", "Last 7 days")).font(.headline)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<7, id: \.self) { offset in
                let date = Calendar.current.date(byAdding: .day, value: offset - 6, to: Date()) ?? Date()
                let formatter = ISO8601DateFormatter()
                let key = Self.dayKey(date)
                let count = session.statistics.days.first { $0.0 == key }?.1 ?? 0
                VStack(spacing: 5) {
                    Text(count, format: .number).font(.caption2).foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.65)).frame(height: count == 0 ? 2 : CGFloat(max(3, min(70, count * 5))))
                    Text(date, format: .dateTime.weekday(.narrow)).font(.caption2).foregroundStyle(.secondary)
                }.accessibilityElement(children: .ignore).accessibilityLabel(date.formatted(.dateTime.weekday().locale(I18n.locale)) + ": \(count)")
                let _ = formatter
            }
        }.frame(height: 110)
        Text(I18n.tr("Время записи включает паузы. Удаление истории не меняет статистику. Повторная обработка и копирование не увеличивают счётчики.", "Recording time includes pauses. Deleting history does not change statistics. Retry and Copy never increment counters.")).font(.caption).foregroundStyle(.secondary)
        Button(I18n.tr("Сбросить статистику…", "Reset statistics…")) { FileActions.confirm(I18n.tr("Сбросить статистику?", "Reset statistics?"), explanation: I18n.tr("История, модели и словарь останутся.", "History, models, and your dictionary remain.")) { Task { await session.clearStatistics() } } }
    }
    private static func dayKey(_ date: Date) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
}
