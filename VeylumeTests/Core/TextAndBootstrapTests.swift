import Testing
import Foundation
@testable import VeylumeCore

struct TextAndBootstrapTests {
    @Test func replacementsAreSinglePassAndPreferLongestPhrase() {
        let rules = [ReplacementRule(source: "a", replacement: "b"), ReplacementRule(source: "b", replacement: "a"), ReplacementRule(source: "a b", replacement: "phrase")]
        #expect(TextFinalizer.apply("a b a bbb", rules: rules) == "phrase b bbb")
        #expect(TextFinalizer.apply("апи API апитест", rules: [ReplacementRule(source: "апи", replacement: "API")]) == "API API апитест")
    }
    @Test func consolePayloadRemovesControlSequencesAndFlattensSeparators() {
        let input = "echo\nhello\r\nworld\t\u{2028}ok\u{1B}[31m RED\u{1B}[0m\u{1B}]0;hidden title\u{7}\u{1B}Pignored\u{1B}\\\u{0}\u{7F}\u{9B}2J"
        let payload = TextFinalizer.consolePayload(input)
        #expect(payload == "echo hello world ok RED")
        #expect(!payload.unicodeScalars.contains { $0.value < 32 || (127...159).contains($0.value) })
        #expect(TextFinalizer.apply("a\nb", rules: []) == "a\nb")
    }
    @Test func emptyAndOversizedDictionaryAreRejected() {
        var d = DictionaryDocument(); d.replacements = [ReplacementRule(source: "", replacement: "x")]
        #expect(throws: ValidationError.self) { try d.validate() }
        d = DictionaryDocument(); d.terms = Array(repeating: "word", count: 501)
        #expect(throws: ValidationError.self) { try d.validate() }
    }
    @Test func bootstrapNeverOverwritesNewManualSelection() {
        var p = Preferences(); let generation = p.modelSelectionGeneration
        p.selectModel("whisper-small"); p.completeBootstrap(selectionGeneration: generation)
        #expect(p.selectedModel == "whisper-small")
        var first = Preferences(); first.completeBootstrap(selectionGeneration: 0)
        #expect(first.selectedModel == "parakeet-v3")
    }
    @Test func traversalAndUntrustedSourceFailBeforeDownload() {
        for path in ["../outside", "/absolute", "a/../../escape", "a\\b", "a//b", "a/./b"] {
            let file = ModelArtifact(path: path, url: URL(string: "https://huggingface.co/model")!, bytes: 4, sha256: String(repeating: "0", count: 64))
            #expect(throws: ValidationError.self) { try file.validate(hosts: ["huggingface.co"]) }
        }
        let file = ModelArtifact(path: "model.bin", url: URL(string: "http://huggingface.co/model")!, bytes: 4, sha256: String(repeating: "0", count: 64))
        #expect(throws: ValidationError.self) { try file.validate(hosts: ["huggingface.co"]) }
    }
    @Test func russianAndEnglishWordsAreTokenized() {
        #expect(TextFinalizer.wordCount("Привет, Veylume! Три слова.") == 4)
        #expect(TextFinalizer.wordCount(" \n — … ") == 0)
    }
    @Test func quickReleaseDoesNotWaitForCoordinatorActivation() {
        var reducer = ShortcutReducer(); reducer.shortcut = Shortcut(keyCode: 50, modifiers: 0)
        #expect(reducer.consume(.down(50, 0, repeatKey: false)).action == .start)
        #expect(reducer.consume(.up(50)).action == .stop)
    }
    @Test func oneHundredQuickHoldSessionsNeverRemainRecording() {
        var m = SessionMachine()
        for _ in 0..<100 {
            let id = UUID(); _ = m.send(.begin(id, .hold)); _ = m.send(.release); _ = m.send(.audioReady(id)); _ = m.send(.audioStopped(id, usable: false))
            #expect(m.phase == .idle)
        }
    }
}
