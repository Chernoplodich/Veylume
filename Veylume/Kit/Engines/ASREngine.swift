import Foundation
import CoreML
import FluidAudio
import WhisperKit
import VeylumeCore

struct ASRText: Sendable { let text: String; let complete: Bool }
protocol ASREngine: AnyObject, Sendable {
    func load(from directory: URL) async throws
    func transcribe(samples: [Float], language: String) async throws -> ASRText
    func unload() async
}

actor FluidAudioEngine: ASREngine {
    private var manager: AsrManager?
    private let chunkConcurrency: Int
    init(chunkConcurrency: Int = 1) { self.chunkConcurrency = chunkConcurrency }
    func load(from directory: URL) async throws {
        let models = try AsrModels.loadLocal(from: directory, version: .v3)
        let manager = AsrManager(config: ASRConfig(parallelChunkConcurrency: chunkConcurrency)); try await manager.loadModels(models); self.manager = manager
    }
    func transcribe(samples: [Float], language: String) async throws -> ASRText {
        guard let manager else { throw Problem.modelNotReady }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let hint: Language? = language == "auto" ? nil : Language(rawValue: language)
        let result = try await manager.transcribe(samples, decoderState: &state, language: hint)
        try Task.checkCancellation(); return ASRText(text: result.text, complete: true)
    }
    func unload() { manager = nil }
}

actor CohereEngine: ASREngine {
    private var models: CoherePipeline.LoadedModels?
    private let pipeline = CoherePipeline()
    private let tokenLimit: Int?
    init(tokenLimit: Int? = nil) { self.tokenLimit = tokenLimit }
    func load(from directory: URL) async throws {
        models = try await CoherePipeline.loadModels(encoderDir: directory, decoderDir: directory, vocabDir: directory, decoderVariant: .v3)
    }
    func transcribe(samples: [Float], language: String) async throws -> ASRText {
        guard let language = CohereAsrConfig.Language(rawValue: language) else { throw Problem.language }
        guard let models else { throw Problem.modelNotReady }
        let result = try await pipeline.transcribeLong(audio: samples, models: models, language: language, maxNewTokens: tokenLimit)
        try Task.checkCancellation(); return ASRText(text: result.text, complete: result.cappedWindows == 0)
    }
    func unload() { models = nil }
}

/// Uses the public local tokenizer factory and never enters WhisperKit's
/// loadTokenizer fallback, which can make network requests even with download:false.
private struct LocalWhisperTokenizer: WhisperTokenizer {
    let base: TokenizerWrapper
    let specialTokens: SpecialTokens
    let allLanguageTokens: Set<Int>
    init(folder: URL) async throws {
        let parsed = try await AutoTokenizerWrapper.from(modelFolder: folder)
        base = parsed
        func token(_ name: String) throws -> Int {
            guard let id = parsed.convertTokenToId(name) else { throw Problem.modelIntegrity }; return id
        }
        specialTokens = try SpecialTokens(endToken: token("<|endoftext|>"), englishToken: token("<|en|>"), noSpeechToken: token("<|nospeech|>"), noTimestampsToken: token("<|notimestamps|>"), specialTokenBegin: token("<|endoftext|>"), startOfPreviousToken: token("<|startofprev|>"), startOfTranscriptToken: token("<|startoftranscript|>"), timeTokenBegin: token("<|0.00|>"), transcribeToken: token("<|transcribe|>"), translateToken: token("<|translate|>"), whitespaceToken: 220)
        allLanguageTokens = Set(Locale.LanguageCode.isoLanguageCodes.compactMap { parsed.convertTokenToId("<|\($0.identifier)|>") })
    }
    func encode(text: String) -> [Int] { base.encode(text: text) }
    func decode(tokens: [Int]) -> String { base.decode(tokens: tokens) }
    func convertTokenToId(_ token: String) -> Int? { base.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { base.convertIdToToken(id) }
    func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) {
        var words: [String] = [], tokens: [[Int]] = [], pending: [Int] = []
        for id in tokenIds {
            pending.append(id); let text = decode(tokens: pending)
            guard !text.contains("\u{fffd}") else { continue }
            if text.first?.isWhitespace == true || id >= specialTokens.specialTokenBegin || words.isEmpty {
                words.append(text); tokens.append(pending)
            } else { words[words.count - 1] += text; tokens[tokens.count - 1] += pending }
            pending.removeAll(keepingCapacity: true)
        }
        if !pending.isEmpty { words.append(decode(tokens: pending)); tokens.append(pending) }
        return (words, tokens)
    }
}

actor WhisperKitEngine: ASREngine {
    private var kit: WhisperKit?
    func load(from directory: URL) async throws {
        let tokenizerDirectory = directory.appendingPathComponent("tokenizer")
        let localTokenizer = try await LocalWhisperTokenizer(folder: tokenizerDirectory)
        let config = WhisperKitConfig(modelFolder: directory.path, tokenizerFolder: tokenizerDirectory, verbose: false, logLevel: .none, prewarm: false, load: false, download: false)
        let kit = try await WhisperKit(config)
        kit.tokenizer = localTokenizer; kit.textDecoder.isModelMultilingual = true
        try await kit.loadModels(); self.kit = kit
    }
    func transcribe(samples: [Float], language: String) async throws -> ASRText {
        guard let kit else { throw Problem.modelNotReady }
        let options = Self.decodingOptions(language: language)
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        try Task.checkCancellation(); return ASRText(text: results.map(\.text).joined(separator: " "), complete: true)
    }
    static func decodingOptions(language: String) -> DecodingOptions {
        var options = DecodingOptions(); options.task = .transcribe; options.language = language == "auto" ? nil : language
        // With usePrefillPrompt=true, WhisperKit defaults detectLanguage=false.
        // A nil language alone would silently prefill English for Russian audio.
        options.detectLanguage = language == "auto"
        options.skipSpecialTokens = true; options.withoutTimestamps = true; options.wordTimestamps = false; options.concurrentWorkerCount = 1
        return options
    }
    func unload() { kit = nil }
}

struct ASRMeasurement: Codable, Sendable {
    let modelID: String, revision: String
    let cold: Bool
    let loadSeconds: Double, recognitionSeconds: Double, capturedSeconds: Double
    var rtf: Double { recognitionSeconds / max(0.001, capturedSeconds) }
}
struct Recognition: Sendable { let result: ASRText; let measurement: ASRMeasurement }

actor EngineHost {
    typealias Loader = @Sendable (ModelManifest, URL) async throws -> any ASREngine
    private let loader: Loader
    private struct Preparation {
        let token: UUID
        let modelID: String
        let directory: URL
        let task: Task<any ASREngine, Error>
    }
    private var engine: (any ASREngine)?
    private var loadedID: String?, loadedDirectory: URL?
    private var preparation: Preparation?
    private var working = false
    private var releaseWhenIdle = false
    private var lastUse = Date.distantPast
    init(loader: Loader? = nil) {
        self.loader = loader ?? { manifest, directory in try await Self.makeEngine(manifest, directory: directory) }
        // Disable third-party text/path debug output before creating a manager.
        AppLogger.minimumLevel = .fault; AppLogger.mirrorsToConsole = false
        Logging.shared.logLevel = .none
    }
    private static func makeEngine(_ manifest: ModelManifest, directory: URL) async throws -> any ASREngine {
        try ModelIntegrity.verify(manifest, at: directory)
        let newEngine: any ASREngine
        switch manifest.id {
        case "parakeet-v3": newEngine = FluidAudioEngine()
        case "cohere-transcribe": newEngine = CohereEngine()
        default: newEngine = WhisperKitEngine()
        }
        try await newEngine.load(from: directory)
        return newEngine
    }
    private func load(_ manifest: ModelManifest, directory: URL, preparingOnly: Bool = false) async throws -> (Bool, Double) {
        if loadedID == manifest.id && loadedDirectory == directory && engine != nil { return (false, 0) }
        let started = Date()
        if let pending = preparation {
            try await complete(pending)
            try Task.checkCancellation()
            if loadedID == manifest.id && loadedDirectory == directory { return (true, Date().timeIntervalSince(started)) }
            if preparingOnly && working { return (false, 0) }
            return try await load(manifest, directory: directory, preparingOnly: preparingOnly)
        }
        if preparingOnly && working { return (false, 0) }
        let previous = engine; engine = nil; loadedID = nil; loadedDirectory = nil
        // One shared preparation task. Recording and inference join it instead
        // of opening duplicate Core ML plans or starting a second load on stop.
        let loader = self.loader
        let task = Task.detached(priority: .utility) { () throws -> any ASREngine in
            await previous?.unload()
            return try await loader(manifest, directory)
        }
        let pending = Preparation(token: UUID(), modelID: manifest.id, directory: directory, task: task)
        preparation = pending
        try await complete(pending); try Task.checkCancellation()
        return (true, Date().timeIntervalSince(started))
    }
    private func complete(_ pending: Preparation) async throws {
        do {
            let prepared = try await pending.task.value
            if preparation?.token == pending.token {
                engine = prepared; loadedID = pending.modelID; loadedDirectory = pending.directory; preparation = nil
                lastUse = Date()
            }
        } catch {
            if preparation?.token == pending.token { preparation = nil }
            throw error
        }
    }
    func prepare(_ manifest: ModelManifest, directory: URL) async throws {
        guard !working else { return }
        _ = try await load(manifest, directory: directory, preparingOnly: true)
    }
    func adoptInstalledDirectory(modelID: String, previous: URL, installed: URL) {
        // The installer atomically moved the very bundle already verified and
        // exercised by selfCheck. Keep its open Core ML mappings instead of
        // paying for the identical plan a second time under its final path.
        guard !working, preparation == nil, loadedID == modelID, loadedDirectory == previous else { return }
        loadedDirectory = installed
    }
    func selfCheck(_ manifest: ModelManifest, directory: URL) async throws {
        guard !working else { throw Problem.recognition }; working = true; defer {
            working = false
            if releaseWhenIdle { Task { await self.unload() } }
        }
        _ = try await load(manifest, directory: directory)
        let language = manifest.supportsAutoLanguage ? "auto" : "en"
        // This synthetic silence is an installation health check, not a speech
        // benchmark or a user-visible dictation result.
        _ = try await engine?.transcribe(samples: [Float](repeating: 0, count: 16000), language: language)
        lastUse = Date()
    }
    func recognize(_ archive: AudioArchive, manifest: ModelManifest, directory: URL, language: String, progress: @escaping @Sendable (Double) -> Void) async throws -> Recognition {
        guard !working else { throw Problem.recognition }; working = true; defer {
            working = false; lastUse = Date()
            if releaseWhenIdle { Task { await self.unload() } }
        }
        try manifest.validate(language: language)
        let (cold, loadSeconds) = try await load(manifest, directory: directory)
        guard let engine else { throw Problem.modelNotReady }
        let start = Date(); var text = "", complete = true, offset = 0
        let window = 16000 * 120, overlap = 16000 * 5
        while offset < archive.sampleCount {
            try Task.checkCancellation()
            let samples = try archive.samples(from: offset, count: min(window, archive.sampleCount - offset))
            let result = try await engine.transcribe(samples: samples, language: language)
            try Task.checkCancellation(); complete = complete && result.complete
            text = offset == 0 ? result.text : Self.merge(text, result.text)
            let end = offset + samples.count; progress(Double(end) / Double(max(1, archive.sampleCount)))
            if end >= archive.sampleCount { break }; offset = end - overlap
        }
        return Recognition(result: ASRText(text: text.trimmingCharacters(in: .whitespacesAndNewlines), complete: complete), measurement: ASRMeasurement(modelID: manifest.id, revision: manifest.revision, cold: cold, loadSeconds: loadSeconds, recognitionSeconds: Date().timeIntervalSince(start), capturedSeconds: archive.duration))
    }
    static func merge(_ previous: String, _ next: String) -> String {
        let left = previous.split(whereSeparator: \.isWhitespace).map(String.init), right = next.split(whereSeparator: \.isWhitespace).map(String.init)
        func normalized(_ s: String) -> String { s.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        let maximum = min(80, min(left.count, right.count))
        if maximum > 0 {
            for count in stride(from: maximum, through: 1, by: -1) {
                if left.suffix(count).map(normalized) == right.prefix(count).map(normalized) { return (left + right.dropFirst(count)).joined(separator: " ") }
            }
        }
        return previous + " " + next
    }
    func unload() async {
        guard !working else { releaseWhenIdle = true; return }
        if let pending = preparation { try? await complete(pending) }
        guard !working else { releaseWhenIdle = true; return }
        let previous = engine; engine = nil; loadedID = nil; loadedDirectory = nil; releaseWhenIdle = false
        await previous?.unload()
    }
    func maintain(keepWarm: Bool) async {
        // Two minutes forced a 16-second Core ML cold load during ordinary use.
        // Retain one mapped model for 15 minutes; pressure/sleep release earlier.
        if !keepWarm && Date().timeIntervalSince(lastUse) > 900 { await unload() }
    }
}
