import Testing
import Foundation
import AppKit
import CryptoKit
@testable import VeylumeKit
import VeylumeCore

struct BoundaryTests {
    @Test @MainActor func clipboardRoundTripPreservesMultipleItemsAndNewOwnerWins() throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let first = NSPasteboardItem(); first.setString("original", forType: .string); first.setData(Data([1,2,3]), forType: .rtf)
        let second = NSPasteboardItem(); second.setData(Data([4,5,6]), forType: .png)
        board.writeObjects([first, second])
        let snapshot = try #require(ClipboardSnapshot.capture(board))
        board.clearContents(); board.setString("temporary", forType: .string)
        snapshot.restore(board, ownership: board.changeCount)
        #expect(board.pasteboardItems?.count == 2)
        #expect(board.pasteboardItems?[0].data(forType: .rtf) == Data([1,2,3]))
        board.clearContents(); board.setString("paste", forType: .string); let ownership = board.changeCount
        board.clearContents(); board.setString("new user copy", forType: .string)
        snapshot.restore(board, ownership: ownership)
        #expect(board.string(forType: .string) == "new user copy")
    }
    @Test @MainActor func filePromisesAreNeverClearedEvenIfTheirDescriptorIsMaterialized() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let item = NSPasteboardItem(); let type = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")
        item.setData(Data([1,2]), forType: type); board.writeObjects([item]); let change = board.changeCount
        #expect(ClipboardSnapshot.capture(board) == nil)
        #expect(board.changeCount == change)
        #expect(board.data(forType: type) == Data([1,2]))
    }
    @Test @MainActor func opaqueApplicationFormatsRoundTripWithoutDisablingTheNextPaste() throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        let applicationType = NSPasteboard.PasteboardType("com.example.editor.selection-metadata")
        let opaque = Data([0, 255, 17, 0, 200])
        item.setString("fixture", forType: .string); item.setData(opaque, forType: applicationType)
        #expect(board.writeObjects([item]))
        let snapshot = try #require(ClipboardSnapshot.capture(board))
        board.clearContents(); board.setString("dictation", forType: .string)
        snapshot.restore(board, ownership: board.changeCount)
        #expect(board.string(forType: .string) == "fixture")
        #expect(board.data(forType: applicationType) == opaque)
        #expect(ClipboardSnapshot.capture(board) != nil)
    }
    @Test @MainActor func oversizedOpaqueClipboardStaysUntouched() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let item = NSPasteboardItem(); let type = NSPasteboard.PasteboardType("com.example.opaque")
        item.setData(Data(repeating: 7, count: 32), forType: type); board.writeObjects([item])
        let change = board.changeCount
        var failure = ""
        #expect(ClipboardSnapshot.capture(board, limit: 16, failure: { failure = $0 }) == nil)
        #expect(failure == "clipboard_too_large")
        #expect(board.changeCount == change); #expect(board.data(forType: type)?.count == 32)
    }
    @Test @MainActor func retainedVeylumePasteCanBeSnapshottedForTheNextDictation() throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let previous = NSPasteboardItem()
        previous.setString("previous dictation", forType: .string)
        let markers = ["org.nspasteboard.TransientType", "org.nspasteboard.ConcealedType"].map { NSPasteboard.PasteboardType($0) }
        for marker in markers { previous.setString("", forType: marker) }
        board.writeObjects([previous])
        // An unacknowledged paste deliberately stays on the board. Its known,
        // materialized markers must not disable the next automatic transaction.
        let snapshot = try #require(ClipboardSnapshot.capture(board))
        board.clearContents(); board.setString("next dictation", forType: .string)
        snapshot.restore(board, ownership: board.changeCount)
        #expect(board.string(forType: .string) == "previous dictation")
        for marker in markers { #expect(board.data(forType: marker) == Data()) }
    }
    @Test func cancellationBeforeCommitPreventsSideEffect() {
        let gate = InsertionGate(); gate.cancel(); var effects = 0
        #expect(!gate.commit { effects += 1 }); #expect(effects == 0)
        let committed = InsertionGate()
        #expect(committed.commit { effects += 1 }); committed.cancel()
        #expect(!committed.commit { effects += 1 }); #expect(effects == 1)
    }
    @Test func installedModelByteTamperingFailsVerification() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VeylumeIntegrity-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let data = Data([0,1,2,3]), file = root.appendingPathComponent("weights.bin"); try data.write(to: file)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let artifact = ModelArtifact(path: "weights.bin", url: URL(string: "https://huggingface.co/pinned/file")!, bytes: 4, sha256: hash)
        try ModelIntegrity.verify(artifact, at: root)
        try Data([0,1,2,4]).write(to: file)
        #expect(throws: (any Error).self) { try ModelIntegrity.verify(artifact, at: root) }
    }
    @Test func publicCatalogueHasRealArtifactsAndCohereRejectsAutoAndRussian() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Veylume/Kit/Resources/Models")
        for (id, speed, accuracy) in [("parakeet-v3",5,4),("cohere-transcribe",5,5),("whisper-turbo",4,4),("whisper-small",4,3),("whisper-large",3,5)] {
            let manifest = try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: root.appendingPathComponent(id+".json")))
            try manifest.validate(); #expect(manifest.downloadBytes > 100_000_000); #expect(manifest.speed == speed); #expect(manifest.accuracy == accuracy)
            if id == "cohere-transcribe" {
                #expect(throws: ValidationError.self) { try manifest.validate(language: "auto") }
                #expect(throws: ValidationError.self) { try manifest.validate(language: "ru") }
                try manifest.validate(language: "en")
            }
        }
    }
    @Test @MainActor func recorderExposesStandardAccessibilityAction() {
        let button = RecorderButton(frame: .zero)
        #expect(button.target === button)
        #expect(button.action != nil)
        button.performClick(nil); #expect(button.listening)
        button.finish(); #expect(!button.listening)
    }
}
