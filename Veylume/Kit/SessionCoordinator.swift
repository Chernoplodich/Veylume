import SwiftUI
import AVFoundation
import VeylumeCore
import CryptoKit

struct ResultEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let text: String
    let outcome: InsertionOutcome
    let incomplete: Bool
    var manualReason: String? = nil
    var needsRecovery: Bool { incomplete || outcome == .manualRequired }
    func persistRecovery(in store: EncryptedStore, enabled: Bool) async throws {
        guard enabled, needsRecovery else { return }
        try await store.save(id: id, kind: .recovery, data: JSONEncoder().encode(self), date: date, expires: Date().addingTimeInterval(86400))
    }
}
private struct SessionSnapshot {
    let id: UUID, startedAt: Date
    let preferences: Preferences
    let model: ModelManifest?
    let dictionary: DictionaryDocument
    let testOnly: Bool
}
private struct StorageConfiguration: Equatable {
    let enabled: Bool, recovery: Bool, history: Bool
    init(_ preferences: Preferences) {
        enabled = preferences.usesProtectedStorage; recovery = preferences.recoveryEnabled; history = preferences.historyEnabled
    }
}
struct PipelineMeasurement: Codable {
    let capturePreparationMilliseconds: Double
    let captureStopMilliseconds: Double
    let stopToResultMilliseconds: Double
    let insertionMilliseconds: Double
    let insertionOutcome: String
    let destinationDiagnostic: String
    let insertionDiagnostic: String
}

/// Meter changes invalidate only the waveform/meter, not Settings, model rows,
/// result lists, and every other observer of the session coordinator.
@MainActor final class AudioMeter: ObservableObject {
    struct Frame: Equatable {
        var level = 0.0
    }
    @Published private(set) var frame = Frame()
    var level: Double { frame.level }
    func update(_ value: Double) {
        let level = value.isFinite ? min(1, max(0, value)) : 0
        let next = Frame(level: level)
        if next != frame { frame = next }
    }
    func reset() { if frame != Frame() { frame = Frame() } }
}

@MainActor final class SessionCoordinator: ObservableObject {
    let preferences: PreferencesStore
    let capabilities: CapabilityCoordinator
    let models: ModelCoordinator
    let engines: EngineHost
    let store: EncryptedStore
    let recovery: RecoveryManager
    private let keys: KeychainKeys
    let hotkeys = HotkeyService()
    private let physicalKeys = PhysicalKeyState()
    private var holdWatchdog = HoldReleaseWatchdog()
    let tracker = DestinationTracker()
    private let capture = AudioCaptureService()
    private lazy var insertion = InsertionService(tracker: tracker)
    private let sounds = SoundService()
    private let outputSilencer = OutputSilencer(journal: AppPaths.root.appendingPathComponent("output-mute.json"))
    private var machine = SessionMachine()
    private var work: Task<Void, Never>?
    private var stopSignal: CheckedContinuation<Void, Never>?
    private var insertionGate: InsertionGate?
    private var interruption: Problem?
    private var stopTimestamp: UInt64?
    private var capturePreparationMilliseconds = 0.0
    private var captureStopMilliseconds = 0.0
    private var maintenance: Timer?, health: Timer?
    private var captureProbe: Task<Void, Never>?
    private var warmup: Task<Void, Never>?
    private var memoryPressure: DispatchSourceMemoryPressure?
    private var observers: [NSObjectProtocol] = []
    @Published private(set) var phase: SessionPhase = .idle
    let meter = AudioMeter()
    @Published private(set) var isTestSession = false
    @Published private(set) var progress = 0.0
    @Published private(set) var startedAt: Date?
    @Published private(set) var lastResult: ResultEntry?
    @Published var notice: String?
    @Published private(set) var pending: [ResultEntry] = []
    @Published private(set) var audioRecovery: [AudioRecoveryEntry] = []
    @Published private(set) var history: [StoredText] = []
    @Published private(set) var statistics = StatisticsSummary()
    @Published private(set) var dictionary = DictionaryDocument()
    @Published private(set) var measurement: ASRMeasurement?
    private var recentPipelines: [PipelineMeasurement] = []
    @Published private(set) var pipelineMeasurement: PipelineMeasurement?
    @Published private(set) var stopLatencies: [Double] = []
    @Published var recordingShortcut = false
    @Published var shortcutTest = false
    @Published var shortcutsAvailable = false
    @Published private(set) var probeProgress: Int?
    @Published private(set) var preparingEngine = false
    @Published private(set) var storageNeedsAuthorization = false
    @Published private(set) var storageAccessChecked = false
    private var checkingStorage = false
    @Published private(set) var authorizingStorage = false
    var onPresentResult: ((ResultEntry) -> Void)?
    var onRecoveryLimit: (() -> Void)?
    var onReadinessRequired: (() -> Void)?
    var onStorageAuthorizationBegan: (() -> Void)?
    var onStorageAuthorizationFinished: (() -> Void)?
    var onPhaseChange: (() -> Void)?
    var onIdle: (() -> Void)?
    var busy: Bool { machine.isBusy || work != nil }
    var unresolvedCount: Int { Set(pending.map(\.id) + audioRecovery.map(\.id)).count }

    init(preferences: PreferencesStore, capabilities: CapabilityCoordinator) throws {
        self.preferences = preferences; self.capabilities = capabilities
        engines = EngineHost()
        models = ModelCoordinator(preferences: preferences, engines: engines, root: try AppPaths.directory("Models"))
        let keys = KeychainKeys(); self.keys = keys
        store = try EncryptedStore(url: AppPaths.root.appendingPathComponent("data.sqlite"), keys: keys)
        recovery = RecoveryManager(root: try AppPaths.directory("Audio"), keys: keys)
        capture.onLevel = { [weak self] value in Task { @MainActor in
            self?.meter.update(value)
        } }
        capture.onFailure = { [weak self] problem in Task { @MainActor in self?.interrupt(problem) } }
        hotkeys.onAction = { [weak self] action in Task { @MainActor in
            guard let self else { return }
            switch action { case .start(let mode): self.start(testOnly: self.shortcutTest, fromShortcut: true, shortcutMode: mode); case .stop: self.stop(); case .cancel: self.cancel() }
            self.refreshHotkeys()
        } }
        hotkeys.onLost = { [weak self] in Task { @MainActor in self?.interrupt(.permissionChanged); self?.hotkeys.reenable() } }
        var storageConfiguration = StorageConfiguration(preferences.value)
        preferences.onChange = { [weak self] in
            guard let self else { return }
            self.refreshHotkeys(); self.onPhaseChange?(); self.prepareSelectedEngine()
            let next = StorageConfiguration(self.preferences.value)
            if next != storageConfiguration {
                storageConfiguration = next
                if !next.enabled { self.storageNeedsAuthorization = false; self.storageAccessChecked = true; keys.clearCache() }
                Task { await self.refreshData(); await self.checkStorageReadiness(presentIfNeeded: false) }
            }
        }
        models.sessionIsBusy = { [weak self] in self?.busy ?? false }
        models.onActiveReady = { [weak self] in self?.prepareSelectedEngine() }
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        pressure.setEventHandler { [weak engines] in Task { await engines?.unload() } }; pressure.resume(); memoryPressure = pressure
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in
            // Secure Input is system-wide and can outlive a password field's
            // foreground app. Refresh on app switches, without an idle poller.
            self?.capabilities.refreshCaptureAccess()
        } })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in
                self?.interrupt(.deviceChanged)
                if let keys = self?.keys { Task.detached { keys.clearCache() } }
                await self?.engines.unload()
            } })
        }
        for name in [NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in
                // Prepare after wake rather than charging a cold Core ML load
                // to the first short dictation. No microphone is opened.
                self?.capabilities.refreshCaptureAccess(); self?.refreshHotkeys()
                self?.prepareSelectedEngine()
                if self?.storageNeedsAuthorization == true { await self?.checkStorageReadiness(presentIfNeeded: false) }
            } })
        }
        observers.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in if self?.phase == .recording { self?.interrupt(.deviceChanged) } } })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in
            self?.capabilities.refresh(); self?.refreshHotkeys(); await self?.refreshData()
            if self?.storageNeedsAuthorization == true { await self?.checkStorageReadiness(presentIfNeeded: false) }
        } })
        maintenance = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in
            guard let self, !self.busy else { return }
            // Idle expiry needs metadata, not decryption/reloading of the entire
            // history and dictionary every minute while Settings is closed.
            try? await self.store.cleanup(); try? self.recovery.pruneExpired()
            let now = Date()
            self.pending.removeAll { now.timeIntervalSince($0.date) >= 86400 }
            self.audioRecovery.removeAll { now.timeIntervalSince($0.metadata.startedAt) >= 86400 }
            if self.preferences.value.historyDays > 0 { self.history.removeAll { now.timeIntervalSince($0.date) >= Double(self.preferences.value.historyDays) * 86400 } }
            await self.engines.maintain(keepWarm: self.preferences.value.keepModelWarm)
        } }
        maintenance?.tolerance = 15
        Task {
            await refreshData(); await checkStorageReadiness()
            if !AppPaths.needsInstallation { await models.bootstrap(); prepareSelectedEngine() }
            refreshHotkeys()
        }
    }
    private func requiredStoragePurposes() async -> [String] {
        guard preferences.value.usesProtectedStorage else { return [] }
        var purposes = Set((preferences.value.recoveryEnabled ? ["recovery"] : []) + (preferences.value.historyEnabled ? ["history"] : []))
        if let stored = try? await store.keyPurposesForStoredData() { purposes.formUnion(stored) }
        return purposes.sorted()
    }
    var storageAvailable: Bool { preferences.value.usesProtectedStorage && storageAccessChecked && !storageNeedsAuthorization && !authorizingStorage }
    var storageReconnectionAfterUpdate: Bool {
        guard storageNeedsAuthorization else { return false }
        if let previous = preferences.value.lastAuthorizedStorageBuild,
           let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String { return previous != current }
        return preferences.value.storageMode == nil && preferences.value.onboardingCompleted
    }
    func useSessionOnlyStorage() {
        guard !busy, !authorizingStorage else { return }
        preferences.value.storageMode = .sessionOnly
        storageNeedsAuthorization = false; storageAccessChecked = true
        if notice == Problem.keychain.message { notice = nil }
    }
    var setupStep: SetupStep {
        SetupReadiness.next(microphone: capabilities.microphone == .authorized, accessibility: capabilities.accessibility,
            requiresExternalAccess: preferences.value.hasShortcuts || preferences.value.automaticInsertion,
            storageChecked: storageAccessChecked, storageNeedsAuthorization: storageNeedsAuthorization, requiresProtectedStorage: false)
    }
    private func checkStorageReadiness(presentIfNeeded: Bool = true) async {
        guard preferences.value.usesProtectedStorage else {
            storageNeedsAuthorization = false; storageAccessChecked = true; return
        }
        guard !checkingStorage, !authorizingStorage, !busy else { return }
        checkingStorage = true; defer { checkingStorage = false }
        let purposes = await requiredStoragePurposes()
        let needsAccess = await StorageReadinessProbe.needsAuthorization(requiredKeyAccess: { [keys] in
            await Task.detached {
                do { try keys.verifyRequiredAccess(to: purposes); return true }
                catch { return false }
            }.value
        }, storedDataAccess: { await self.refreshData() })
        guard preferences.value.usesProtectedStorage else { return }
        storageNeedsAuthorization = needsAccess
        if !needsAccess && notice == Problem.keychain.message { notice = nil }
        storageAccessChecked = true
        if !needsAccess { recordStorageAccessBuild() }
        if presentIfNeeded && preferences.value.onboardingCompleted && setupStep != .ready { onReadinessRequired?() }
    }
    private func prepareSelectedEngine() {
        guard warmup == nil, !AppPaths.needsInstallation, models.activeReady, let model = models.active else { return }
        preparingEngine = true
        warmup = Task {
            defer {
                warmup = nil; preparingEngine = false
                if models.active?.id != model.id { prepareSelectedEngine() }
            }
            // No microphone is opened. Core ML preparation runs on a shared
            // detached worker and is joined if recording stops before it ends.
            try? await engines.prepare(model, directory: models.installer.directory(for: model.id))
        }
    }
    var status: String {
        switch phase {
        case .idle:
            if !storageAccessChecked { return I18n.tr("Проверяем подготовку…", "Checking setup…") }
            if capabilities.microphone != .authorized { return I18n.tr("Нужен доступ к микрофону", "Microphone access needed") }
            if unresolvedCount >= 10 { return I18n.tr("Откройте восстановление", "Open recovery") }
            if !models.activeReady { return I18n.tr("Подготовьте модель", "Prepare a model") }
            if let active = models.active, (try? active.validate(language: preferences.value.speechLanguage)) == nil { return Problem.language.message }
            if capabilities.secureInput, preferences.value.hasShortcuts, !preferences.value.shortcutsPaused { return I18n.tr("Защищённый ввод — клавиша недоступна", "Secure input — shortcut unavailable") }
            if preparingEngine { return I18n.tr("Подготавливаем распознавание…", "Preparing transcription…") }
            return I18n.tr("Готово к записи", "Ready to record")
        case .preparing: return I18n.tr("Подготовка микрофона…", "Preparing microphone…")
        case .recording: return I18n.tr("Идёт запись", "Recording")
        case .stopping: return I18n.tr("Запись остановлена", "Recording stopped")
        case .transcribing: return I18n.tr("Распознавание…", "Transcribing…")
        case .finalizing, .inserting: return I18n.tr("Текст готов…", "Text is ready…")
        case .cancelling: return I18n.tr("Отмена и очистка…", "Cancelling and cleaning up…")
        }
    }
    func refreshHotkeys() {
        let p = preferences.value
        let shouldRun = p.hasShortcuts && !p.shortcutsPaused && !recordingShortcut && capabilities.shortcutAccessPossible && !AppPaths.needsInstallation
        if hotkeys.isRunning && !shouldRun && (phase == .preparing || phase == .recording) { interrupt(.permissionChanged) }
        hotkeys.configure(hold: p.holdShortcut, toggle: p.toggleShortcut, paused: p.shortcutsPaused || recordingShortcut, active: busy)
        if shouldRun { shortcutsAvailable = hotkeys.start() }
        else { hotkeys.stop(); shortcutsAvailable = false }
    }
    private func send(_ event: SessionEvent) {
        _ = machine.send(event); phase = machine.phase; refreshHotkeys(); onPhaseChange?()
    }
    func start(testOnly: Bool = false, fromShortcut: Bool = false, shortcutMode: RecordingMode? = nil) {
        guard !busy, !recordingShortcut, probeProgress == nil || testOnly else { return }
        guard !authorizingStorage else { return }
        capabilities.refresh()
        if fromShortcut, capabilities.secureInput { notice = I18n.tr("Выйдите из поля пароля, затем запишите снова.", "Leave the password field, then try recording again."); return }
        guard capabilities.microphone == .authorized else { notice = Problem.microphone.message; onReadinessRequired?(); return }
        guard testOnly || models.activeReady else { notice = Problem.modelNotReady.message; return }
        guard testOnly || !models.isPreparing else { notice = I18n.tr("Модель подготавливается. Дождитесь завершения или приостановите её загрузку.", "A model is being prepared. Wait for it to finish or pause its installation."); return }
        guard unresolvedCount < 10 else { notice = Problem.pendingLimit.message; onRecoveryLimit?(); return }
        if !testOnly, let active = models.active, (try? active.validate(language: preferences.value.speechLanguage)) == nil { notice = Problem.language.message; return }
        var effectivePreferences = preferences.value.recordingConfiguration(storageAvailable: storageAvailable)
        effectivePreferences.mode = fromShortcut ? (shortcutMode ?? .hold) : .toggle
        effectivePreferences.shortcut = effectivePreferences.mode == .hold ? preferences.value.holdShortcut : preferences.value.toggleShortcut
        let destinationRequest = tracker.request()
        let snapshot = SessionSnapshot(id: UUID(), startedAt: Date(), preferences: effectivePreferences, model: models.active, dictionary: storageAvailable ? dictionary : DictionaryDocument(), testOnly: testOnly)
        if !testOnly { prepareSelectedEngine() }
        notice = nil; progress = 0; interruption = nil; isTestSession = testOnly; startedAt = snapshot.startedAt; insertionGate = InsertionGate()
        capture.beginSession()
        holdWatchdog = HoldReleaseWatchdog()
        stopTimestamp = nil
        send(.begin(snapshot.id, snapshot.preferences.mode))
        let initialAX = capabilities.accessibility, initialListen = capabilities.listen, initialPost = capabilities.post
        let limitDeadline = ContinuousClock.now.advanced(by: .seconds(snapshot.preferences.recordingLimitMinutes * 60))
        health = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in Task { @MainActor in
            guard let self, self.busy else { return }
            self.capabilities.refreshCaptureAccess()
            if self.capabilities.microphone != .authorized { self.interrupt(.permissionChanged) }
            if self.capabilities.secureInput && fromShortcut { self.interrupt(.permissionChanged) }
            if (initialAX && !self.capabilities.accessibility) || (initialListen && !self.capabilities.listen) || (initialPost && !self.capabilities.post) { self.interrupt(.permissionChanged) }
            if ContinuousClock.now >= limitDeadline { self.stop() }
            if !testOnly, snapshot.preferences.mode == .hold, self.phase == .recording, self.shortcutsAvailable,
               let key = snapshot.preferences.shortcut,
               self.holdWatchdog.shouldStop(hardwareDown: self.physicalKeys.isDown(key.keyCode)) { self.stop() }
        } }
        work = Task { await self.run(snapshot, destinationRequest: destinationRequest) }
    }
    func stop() {
        if phase == .preparing || phase == .recording {
            if stopTimestamp == nil { stopTimestamp = DispatchTime.now().uptimeNanoseconds }
            capture.requestImmediateStop()
        }
        send(.stop); stopSignal?.resume(); stopSignal = nil
    }
    func cancel() {
        guard busy, insertionGate?.committed != true, !machine.insertionCommitted else { return }
        captureProbe?.cancel(); capture.requestImmediateStop()
        insertionGate?.cancel(); send(.cancel); work?.cancel(); stopSignal?.resume(); stopSignal = nil
    }
    func interrupt(_ problem: Problem) {
        guard busy, phase != .idle, phase != .cancelling, insertionGate?.committed != true, !machine.insertionCommitted else { return }
        interruption = problem
        if phase == .preparing || phase == .recording { stop() }
        else {
            insertionGate?.cancel(); send(.cancel); work?.cancel()
            stopSignal?.resume(); stopSignal = nil
        }
    }
    private func run(_ requestedSnapshot: SessionSnapshot, destinationRequest: DestinationRequest) async {
        var snapshot = requestedSnapshot
        var archive: AudioArchive?
        defer { outputSilencer.end(session: snapshot.id) }
        do {
            let preparationStarted = DispatchTime.now().uptimeNanoseconds
            let destination = snapshot.testOnly ? nil : await tracker.capture(destinationRequest)
            try Task.checkCancellation()
            if machine.stopRequested { throw Problem.noSpeech }
            let newArchive = try AudioArchive(id: snapshot.id, root: recovery.root); archive = newArchive
            if snapshot.preferences.recoveryEnabled && !snapshot.testOnly {
                let metadata = AudioRecoveryMetadata(id: snapshot.id, modelID: snapshot.model!.id, language: snapshot.preferences.speechLanguage, rules: snapshot.dictionary.replacements, startedAt: snapshot.startedAt, audioKey: newArchive.keyData, chunks: 0, samples: 0)
                // A key can become unavailable after the startup probe. Basic
                // dictation still uses an encrypted spool with a RAM-only key;
                // pause persistent saving for this snapshot and show reconnect.
                do {
                    let journal = try await Task.detached { [recovery] in try recovery.journaler(metadata) }.value
                    try journal(newArchive); capture.onChunk = journal
                } catch ValidationError.keychain {
                    storageNeedsAuthorization = true; storageAccessChecked = true; capture.onChunk = nil
                    snapshot = SessionSnapshot(id: snapshot.id, startedAt: snapshot.startedAt,
                        preferences: snapshot.preferences.recordingConfiguration(storageAvailable: false), model: snapshot.model,
                        dictionary: DictionaryDocument(), testOnly: snapshot.testOnly)
                }
            } else { capture.onChunk = nil }
            if snapshot.preferences.mutesOutputDuringRecording {
                let report = await outputSilencer.begin(session: snapshot.id)
                if report.unavailable > 0 || report.outputs == 0 {
                    notice = I18n.tr("Не удалось отключить звук на одном из аудиовыходов. Запись доступна; уменьшите громкость вручную.", "An audio output could not be muted. You can still record; turn its volume down manually.")
                }
            }
            try Task.checkCancellation()
            if machine.stopRequested { throw Problem.noSpeech }
            try await capture.start(archive: newArchive, deviceUID: snapshot.preferences.microphoneUID)
            capturePreparationMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - preparationStarted) / 1_000_000
            try Task.checkCancellation()
            send(.audioReady(snapshot.id))
            if phase == .recording {
                sounds.play(.start, preferences: snapshot.preferences)
                await withCheckedContinuation { stopSignal = $0 }
            }
            let captured = try await capture.stop()
            outputSilencer.end(session: snapshot.id)
            if let captured { captureStopMilliseconds = captured.stopMilliseconds; stopLatencies.append(captured.stopMilliseconds); if stopLatencies.count > 200 { stopLatencies.removeFirst() } }
            try Task.checkCancellation()
            sounds.play(.stop, preferences: snapshot.preferences)
            if let interruption { throw interruption }
            if snapshot.testOnly { try newArchive.remove(); send(.failed(snapshot.id)); finish(); return }
            guard let captured, captured.archive.duration >= 0.3, captured.energeticSeconds >= 0.15 else { throw Problem.noSpeech }
            send(.audioStopped(snapshot.id, usable: true))
            try await recognize(snapshot, archive: captured.archive, destination: destination)
        } catch is CancellationError {
            _ = try? await capture.stop()
            outputSilencer.end(session: snapshot.id)
            if interruption == nil || !snapshot.preferences.recoveryEnabled || snapshot.testOnly { try? archive?.remove() }
            if let interruption { notice = interruption.message }
            sounds.play(.cancel, preferences: snapshot.preferences)
            send(.cleanupFinished(snapshot.id))
            if interruption != nil { await refreshData() }
            finish()
        } catch {
            _ = try? await capture.stop()
            outputSilencer.end(session: snapshot.id)
            let problem = interruption ?? (error as? Problem) ?? ((error as? ValidationError) == .keychain ? .keychain : .recognition)
            if problem == .keychain { storageNeedsAuthorization = true }
            if problem == .noSpeech || !snapshot.preferences.recoveryEnabled || snapshot.testOnly { try? archive?.remove() }
            notice = problem.message
            send(.failed(snapshot.id)); await refreshData(); finish()
        }
    }
    private func recognize(_ snapshot: SessionSnapshot, archive: AudioArchive, destination: Destination?) async throws {
        guard let manifest = snapshot.model else { throw Problem.modelNotReady }
        let recognized = try await engines.recognize(archive, manifest: manifest, directory: models.installer.directory(for: manifest.id), language: snapshot.preferences.speechLanguage) { [weak self] value in
            Task { @MainActor in if self?.machine.id == snapshot.id { self?.progress = value } }
        }
        try Task.checkCancellation(); guard machine.accepts(snapshot.id) else { throw CancellationError() }
        var text = TextFinalizer.apply(recognized.result.text, rules: snapshot.dictionary.replacements)
        if destination?.isConsole == true { text = TextFinalizer.consolePayload(text) }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Problem.noSpeech }
        send(.recognized(snapshot.id))
        guard let gate = insertionGate else { throw CancellationError() }
        let insertionStarted = DispatchTime.now().uptimeNanoseconds
        let outcome: InsertionOutcome
        if recognized.result.complete {
            // The insertion service checks cancellation again at the actual
            // external side effect. This state transition isn't permission to paste.
            outcome = await insertion.insert(text, destination: destination, gate: gate, automatic: snapshot.preferences.automaticInsertion)
        } else { outcome = .manualRequired }
        let insertionDiagnostic = recognized.result.complete ? await insertion.diagnosticCode : "incomplete_recognition"
        guard !gate.cancelled, machine.accepts(snapshot.id), outcome != .cancelledBeforeCommit else { throw CancellationError() }
        var entry = ResultEntry(id: snapshot.id, date: snapshot.startedAt, text: text, outcome: outcome, incomplete: !recognized.result.complete)
        if outcome == .manualRequired { entry.manualReason = insertionDiagnostic == "no_destination" ? tracker.diagnosticCode : insertionDiagnostic }
        let now = DispatchTime.now().uptimeNanoseconds
        pipelineMeasurement = PipelineMeasurement(capturePreparationMilliseconds: capturePreparationMilliseconds, captureStopMilliseconds: captureStopMilliseconds,
            stopToResultMilliseconds: stopTimestamp.map { Double(now - $0) / 1_000_000 } ?? 0,
            insertionMilliseconds: Double(now - insertionStarted) / 1_000_000, insertionOutcome: outcome.rawValue,
            destinationDiagnostic: tracker.diagnosticCode, insertionDiagnostic: insertionDiagnostic)
        // MainActor serializes the result commit against Escape. From here on,
        // cancellation cannot promise to undo another app's completed action.
        _ = machine.send(.finalized(snapshot.id)); phase = machine.phase
        if recognized.result.complete { lastResult = entry; measurement = recognized.measurement }
        if entry.needsRecovery {
            pending.removeAll { $0.id == entry.id }; pending.insert(entry, at: 0)
            if entry.incomplete { notice = Problem.incomplete.message }
            else { notice = I18n.tr("Текст готов. Скопируйте его, когда будет удобно.", "Your text is ready. Copy it whenever you are ready.") }
            // Only a manual or incomplete result needs an immediate surface.
            onPresentResult?(entry)
        }
        do {
            // Statistics and technical timing do not depend on Keychain access,
            // recovery, or opt-in history. Their idempotency key is the session.
            if recognized.result.complete {
                try await store.record(StatisticsEvent(id: snapshot.id, startedAt: snapshot.startedAt, words: TextFinalizer.wordCount(text), duration: archive.duration, modelID: manifest.id, revision: manifest.revision))
                try JSONEncoder().encode(recognized.measurement).write(to: AppPaths.root.appendingPathComponent("last-benchmark.json"), options: .atomic)
                if let pipelineMeasurement {
                    try JSONEncoder().encode(pipelineMeasurement).write(to: AppPaths.root.appendingPathComponent("last-pipeline.json"), options: .atomic)
                    recentPipelines.append(pipelineMeasurement)
                    if recentPipelines.count > 10 { recentPipelines.removeFirst(recentPipelines.count - 10) }
                    try JSONEncoder().encode(recentPipelines).write(to: AppPaths.root.appendingPathComponent("recent-pipelines.json"), options: .atomic)
                }
            }
            try await entry.persistRecovery(in: store, enabled: snapshot.preferences.recoveryEnabled)
            if recognized.result.complete {
                if snapshot.preferences.historyEnabled {
                    let expires = snapshot.preferences.historyDays == 0 ? nil : Date().addingTimeInterval(Double(snapshot.preferences.historyDays) * 86400)
                    try await store.save(id: entry.id, kind: .history, data: Data(text.utf8), date: entry.date, expires: expires)
                }
            }
            if !entry.incomplete { try archive.remove() }
        } catch {
            if (error as? ValidationError) == .keychain { storageNeedsAuthorization = true; notice = Problem.keychain.message }
            else { notice = Problem.storage.message }
        }
        send(.finished(snapshot.id)); await refreshData(); finish()
    }
    private func finish() {
        health?.invalidate(); health = nil; meter.reset(); isTestSession = false; startedAt = nil; work = nil; insertionGate = nil; stopSignal = nil
        refreshHotkeys(); onPhaseChange?(); onIdle?()
    }
    func retry(_ entry: AudioRecoveryEntry) {
        guard storageAvailable else { notice = Problem.keychain.message; return }
        guard !busy, let manifest = models.catalogue.first(where: { $0.id == entry.metadata.modelID }), models.states[manifest.id] == .ready else { notice = Problem.modelNotReady.message; return }
        var p = preferences.value; p.speechLanguage = entry.metadata.language
        var dict = DictionaryDocument(); dict.replacements = entry.metadata.rules
        let snapshot = SessionSnapshot(id: entry.id, startedAt: entry.metadata.startedAt, preferences: p, model: manifest, dictionary: dict, testOnly: false)
        insertionGate = InsertionGate(); interruption = nil
        send(.begin(entry.id, .toggle)); send(.audioReady(entry.id)); send(.stop); send(.audioStopped(entry.id, usable: true))
        work = Task {
            do { try await recognize(snapshot, archive: recovery.restore(entry), destination: nil) }
            catch is CancellationError { try? recovery.remove(entry); send(.cleanupFinished(entry.id)); finish(); await refreshData() }
            catch { notice = Problem.recognition.message; send(.failed(entry.id)); finish() }
        }
    }
    @discardableResult func refreshData() async -> Bool {
        guard !authorizingStorage else { return false }
        defer {
            if !preferences.value.usesProtectedStorage {
                history = []; audioRecovery = []; dictionary = DictionaryDocument()
                storageNeedsAuthorization = false; storageAccessChecked = true
                if notice == Problem.keychain.message { notice = nil }
            }
        }
        do {
            try await store.cleanup()
            statistics = try await store.summary()
            if !preferences.value.usesProtectedStorage {
                history = []; audioRecovery = []; dictionary = DictionaryDocument()
                let excluded = busy ? machine.id : nil
                try await Task.detached { [recovery] in try recovery.pruneExpired(excluding: excluded) }.value
                storageNeedsAuthorization = false; storageAccessChecked = true
                return true
            }
            let restored = try await store.load(kind: .recovery).compactMap { try? JSONDecoder().decode(ResultEntry.self, from: $0.2) }
            pending.removeAll { Date().timeIntervalSince($0.date) >= 86400 }
            for entry in restored where !pending.contains(where: { $0.id == entry.id }) { pending.append(entry) }
            let excluded = busy ? machine.id : nil
            audioRecovery = try await Task.detached { [recovery] in try recovery.entries(excluding: excluded) }.value
            history = try await store.load(kind: .history).compactMap { id, date, data in String(data: data, encoding: .utf8).map { StoredText(id: id, date: date, text: $0) } }
            if let data = try await store.load(kind: .dictionary).first?.2 { dictionary = try JSONDecoder().decode(DictionaryDocument.self, from: data) }
            return true
        } catch {
            if (error as? ValidationError) == .keychain { storageNeedsAuthorization = true; storageAccessChecked = true; return false }
            notice = Problem.storage.message
            // A disk/integrity error must not be presented as a missing grant.
            return true
        }
    }
    func authorizeStorage() {
        guard !busy, !authorizingStorage else { return }
        preferences.value.storageMode = .protected
        onStorageAuthorizationBegan?()
        authorizingStorage = true
        Task {
            defer { onStorageAuthorizationFinished?() }
            do {
                let purposes = await requiredStoragePurposes()
                try await Task.detached { [keys] in try keys.authorizeNeeded(required: purposes) }.value
                storageNeedsAuthorization = false
                storageAccessChecked = true
                if preferences.value.recoveryEnabled {
                    for entry in pending {
                        try await store.save(id: entry.id, kind: .recovery, data: JSONEncoder().encode(entry), date: entry.date, expires: entry.date.addingTimeInterval(86400))
                    }
                }
                authorizingStorage = false; notice = nil
                if await refreshData(), !storageNeedsAuthorization { recordStorageAccessBuild() }
            } catch { authorizingStorage = false; storageNeedsAuthorization = true; notice = Problem.keychain.message }
        }
    }
    func saveDictionary(_ document: DictionaryDocument) async throws {
        guard storageAvailable else { throw Problem.keychain }
        do {
            try document.validate(); try await store.save(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, kind: .dictionary, data: JSONEncoder().encode(document)); dictionary = document
        } catch { if (error as? ValidationError) == .keychain { storageNeedsAuthorization = true }; throw error }
    }
    private func recordStorageAccessBuild() {
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           preferences.value.lastAuthorizedStorageBuild != build { preferences.value.lastAuthorizedStorageBuild = build }
    }
    func removePending(_ entry: ResultEntry) async {
        do { try await store.delete(id: entry.id, kind: .recovery); pending.removeAll { $0.id == entry.id }; onIdle?() }
        catch { notice = Problem.storage.message }
    }
    func deleteAudio(_ entry: AudioRecoveryEntry) async { do { try recovery.remove(entry); await refreshData() } catch { notice = Problem.storage.message } }
    func copy(_ entry: ResultEntry) { copyText(entry.text) }
    func copyText(_ text: String) { let board = NSPasteboard.general; board.clearContents(); board.setString(text, forType: .string) }
    func clearHistory() async { do { try await store.deleteAll(kind: .history); await refreshData() } catch { notice = Problem.storage.message } }
    func clearStatistics() async { do { try await store.resetStatistics(); await refreshData() } catch { notice = Problem.storage.message } }
    func eraseAllData() async {
        guard !busy else { return }
        do {
            try capabilities.setLogin(false)
            await models.cancelAll(); await engines.unload()
            try await models.installer.eraseAll()
            for kind in [BlobKind.history, .recovery, .dictionary] { try await store.deleteAll(kind: kind) }
            try await store.resetStatistics()
            for entry in try recovery.entries() { try recovery.remove(entry) }
            dictionary = DictionaryDocument(); pending = []; lastResult = nil; audioRecovery = []; measurement = nil
            pipelineMeasurement = nil; recentPipelines = []; stopLatencies = []
            try? FileManager.default.removeItem(at: AppPaths.root.appendingPathComponent("last-benchmark.json"))
            try? FileManager.default.removeItem(at: AppPaths.root.appendingPathComponent("last-pipeline.json"))
            try? FileManager.default.removeItem(at: AppPaths.root.appendingPathComponent("recent-pipelines.json"))
            var reset = Preferences(); reset.bootstrap = .removed; preferences.value = reset
            await models.refresh(); await refreshData()
        } catch { notice = Problem.storage.message }
    }
    func shutdown() { hotkeys.stop(); maintenance?.invalidate(); health?.invalidate(); memoryPressure?.cancel(); outputSilencer.shutdown() }
    #if DEBUG
    func probeCaptureStops() {
        guard !busy, probeProgress == nil else { return }
        captureProbe = Task {
            for index in 0..<100 {
                if Task.isCancelled { break }
                probeProgress = index + 1
                start(testOnly: true)
                // Include very short preparing releases and normal ready stops.
                if index % 2 == 0 { try? await Task.sleep(for: .milliseconds(15)) }
                else {
                    while phase == .preparing && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
                    try? await Task.sleep(for: .milliseconds(40))
                }
                stop()
                while busy && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
                if Task.isCancelled { break }
            }
            probeProgress = nil; captureProbe = nil
            if !busy { notice = I18n.tr("Проверка завершена. Измерения доступны в диагностике.", "Test finished. Measurements are available in Diagnostics.") }
        }
    }
    #endif
}
