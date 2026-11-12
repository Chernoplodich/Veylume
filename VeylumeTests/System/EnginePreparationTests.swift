import Testing
import Foundation
@testable import VeylumeKit
import VeylumeCore

struct WhisperLanguageTests {
    @Test func automaticLanguageReallyDetectsInsteadOfPrefillingEnglish() {
        let automatic = WhisperKitEngine.decodingOptions(language: "auto")
        #expect(automatic.detectLanguage); #expect(automatic.language == nil)
        #expect(automatic.usePrefillPrompt); #expect(automatic.task == .transcribe)
        let russian = WhisperKitEngine.decodingOptions(language: "ru")
        #expect(!russian.detectLanguage); #expect(russian.language == "ru")
        #expect(russian.task == .transcribe)
    }
}

private actor StubEngine: ASREngine {
    func load(from directory: URL) {}
    func transcribe(samples: [Float], language: String) -> ASRText { ASRText(text: "fixture", complete: true) }
    func unload() {}
}
private actor PreparationProbe {
    private(set) var count = 0
    private var started: CheckedContinuation<Void, Never>?
    private var blocked: CheckedContinuation<Void, Never>?
    func waitForStart() async {
        if count > 0 { return }
        await withCheckedContinuation { started = $0 }
    }
    func load() async -> any ASREngine {
        count += 1; started?.resume(); started = nil
        if count == 1 { await withCheckedContinuation { blocked = $0 } }
        return StubEngine()
    }
    func release() { blocked?.resume(); blocked = nil }
}
struct EnginePreparationTests {
    @Test func preparationIsSharedWithRecognitionAndWaiterCancellationDoesNotEvictIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VeylumePreparation-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifestURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Veylume/Kit/Resources/Models/parakeet-v3.json")
        let manifest = try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: manifestURL))
        let probe = PreparationProbe(), host = EngineHost(loader: { _, _ in await probe.load() })
        let warmup = Task { try await host.prepare(manifest, directory: root) }
        await probe.waitForStart()
        let archive = try AudioArchive(id: UUID(), root: root)
        try archive.append([Float](repeating: 0, count: 16000)); try archive.finish()
        let recognition = Task { try await host.recognize(archive, manifest: manifest, directory: root, language: "auto", progress: { _ in }) }
        warmup.cancel(); await probe.release()
        await #expect(throws: CancellationError.self) { try await warmup.value }
        #expect(try await recognition.value.result.text == "fixture")
        #expect(await probe.count == 1)
        let warm = try await host.recognize(archive, manifest: manifest, directory: root, language: "auto", progress: { _ in })
        #expect(!warm.measurement.cold); #expect(warm.measurement.loadSeconds == 0)
        await host.unload(); try await host.prepare(manifest, directory: root)
        #expect(await probe.count == 2)
    }
    @Test @MainActor func compactResultUsesContentHeightAndCapsLongText() {
        func entry(_ text: String) -> ResultEntry { ResultEntry(id: UUID(), date: Date(), text: text, outcome: .manualRequired, incomplete: false) }
        let short = CompactResultContent.size(for: entry("One short phrase."))
        let long = CompactResultContent.size(for: entry(String(repeating: "A longer fixture sentence. ", count: 500)))
        #expect(short.width == 360); #expect(short.height <= 140)
        #expect(long.height > short.height); #expect(long.height <= 284)
    }
}
