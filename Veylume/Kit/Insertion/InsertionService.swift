import AppKit
import ApplicationServices
import Carbon
import os
import VeylumeCore

final class InsertionGate: @unchecked Sendable {
    private struct State { var cancelled = false, committed = false }
    private let state = OSAllocatedUnfairLock(initialState: State())
    var committed: Bool { state.withLock { $0.committed } }
    var cancelled: Bool { state.withLock { $0.cancelled } }
    func cancel() { state.withLock { if !$0.committed { $0.cancelled = true } } }
    func commit(_ effect: () -> Void) -> Bool {
        state.withLock { s in
            guard !s.cancelled, !s.committed else { return false }
            s.committed = true; effect(); return true
        }
    }
}

struct ClipboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]
    let changeCount: Int
    static func capture(_ pasteboard: NSPasteboard, limit: Int = 8 * 1024 * 1024, failure: (String) -> Void = { _ in }) -> ClipboardSnapshot? {
        func reject(_ code: String) -> ClipboardSnapshot? { failure(code); return nil }
        let changeCount = pasteboard.changeCount
        var items: [[NSPasteboard.PasteboardType: Data]] = []; var total = 0
        guard limit >= 0, (pasteboard.pasteboardItems?.count ?? 0) <= 64 else { return reject("clipboard_too_large") }
        for item in pasteboard.pasteboardItems ?? [] {
            guard item.types.count <= 64 else { return reject("clipboard_too_large") }
            var stored: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                // Apps add their own opaque representations to otherwise normal
                // copies (including Finder). Preserve every materialized byte,
                // rather than treating an unfamiliar type as a reason to refuse
                // dictation. File promises need their original provider and
                // cannot be reconstructed by storing a descriptor alone.
                guard !isFilePromise(type) else { return reject("clipboard_file_promise") }
                let data: Data
                if let materialized = item.data(forType: type) { data = materialized }
                else if ["public.utf16-external-plain-text", "public.utf16-plain-text"].contains(type.rawValue),
                        let utf8 = item.data(forType: .string), let string = String(data: utf8, encoding: .utf8),
                        let encoded = string.data(using: .utf16) {
                    // macOS advertises this derived text representation even when
                    // its converter returns nil. It is reproducible from the
                    // already-materialized UTF-8 item; arbitrary providers aren't.
                    data = encoded
                } else { return reject("clipboard_provider_unavailable") }
                guard data.count <= limit - total else { return reject("clipboard_too_large") }
                total += data.count; stored[type] = data
            }
            items.append(stored)
        }
        guard pasteboard.changeCount == changeCount else { return reject("clipboard_changed") }
        return ClipboardSnapshot(items: items, changeCount: changeCount)
    }
    private static func isFilePromise(_ type: NSPasteboard.PasteboardType) -> Bool {
        let name = type.rawValue.lowercased()
        return name.hasPrefix("com.apple.pasteboard.promised-file")
            || name == "nsfilespromisepboardtype" || name == "com.apple.nsfilepromiseitemmetadata"
    }
    func restore(_ pasteboard: NSPasteboard, ownership: Int) {
        guard pasteboard.changeCount == ownership else { return }
        let restored = items.map { types -> NSPasteboardItem in let item = NSPasteboardItem(); for (type, data) in types { item.setData(data, forType: type) }; return item }
        pasteboard.clearContents(); if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}

actor InsertionService {
    private let tracker: DestinationTracker
    private(set) var diagnosticCode = "not_attempted"
    init(tracker: DestinationTracker) { self.tracker = tracker }
    func insert(_ text: String, destination: Destination?, gate: InsertionGate, automatic: Bool) async -> InsertionOutcome {
        diagnosticCode = "not_attempted"
        guard automatic else { diagnosticCode = "automatic_disabled"; return .manualRequired }
        guard let destination else { diagnosticCode = "no_destination"; return .manualRequired }
        guard AXIsProcessTrusted() else { diagnosticCode = "accessibility_unavailable"; return .manualRequired }
        guard !IsSecureEventInputEnabled() else { diagnosticCode = "secure_input"; return .manualRequired }
        for _ in 0..<30 {
            if gate.cancelled { return .cancelledBeforeCommit }
            if CGEventSource.flagsState(.combinedSessionState).rawValue & Shortcut.modifierMask == 0 { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard CGEventSource.flagsState(.combinedSessionState).rawValue & Shortcut.modifierMask == 0 else { diagnosticCode = "modifiers_held"; return .manualRequired }
        guard tracker.matches(destination) else { diagnosticCode = "destination_changed"; return .manualRequired }
        guard !gate.cancelled else { return .cancelledBeforeCommit }
        // Some hosts advertise a setter on an internal input proxy: AX reports
        // success while their visible editor never changes (observed in Monaco).
        // Use direct selection only for the verified native profile. Every other
        // app still has the general guarded paste path, without an app allowlist.
        // A committed attempt never falls through into another insertion method.
        if destination.directSelectionCandidate, destination.bundleID == "com.apple.TextEdit" {
            var result = AXError.failure
            guard gate.commit({ result = AXUIElementSetAttributeValue(destination.element, kAXSelectedTextAttribute as CFString, text as CFString) }) else { return .cancelledBeforeCommit }
            guard result == .success else { diagnosticCode = "ax_selection_failed"; return .manualRequired }
            diagnosticCode = "ax_selection_dispatched"
            return await awaitAcknowledgement(text, destination: destination) ? .verifiedInserted : .dispatchedUnverified
        }
        guard CGPreflightPostEventAccess() || AXIsProcessTrusted() else { diagnosticCode = "post_unavailable"; return .manualRequired }
        // Pasteboard/AX work stays on this serial actor rather than blocking the
        // UI thread. No observer reads the clipboard outside an insertion.
        let transaction: (InsertionOutcome, ClipboardSnapshot?, Int?) = {
            let pasteboard = NSPasteboard.general
            guard !gate.cancelled, tracker.matches(destination) else { diagnosticCode = "destination_changed"; return (.manualRequired, nil, nil) }
            var clipboardFailure = "clipboard_unsupported"
            guard let snapshot = ClipboardSnapshot.capture(pasteboard, failure: { clipboardFailure = $0 }) else { diagnosticCode = clipboardFailure; return (.manualRequired, nil, nil) }
            let previousCount = snapshot.changeCount
            let payload = NSPasteboardItem(); payload.setString(text, forType: .string)
            payload.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
            payload.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            guard pasteboard.changeCount == previousCount, !gate.cancelled,
                  CGEventSource.flagsState(.combinedSessionState).rawValue & Shortcut.modifierMask == 0,
                  tracker.matches(destination) else { diagnosticCode = "precommit_changed"; return (.manualRequired, nil, nil) }
            var dispatched = false, ownedCount: Int?
            let committed = gate.commit {
                pasteboard.clearContents(); pasteboard.writeObjects([payload]); let ownership = pasteboard.changeCount
                ownedCount = ownership
                guard tracker.matches(destination) else { diagnosticCode = "commit_destination_changed"; snapshot.restore(pasteboard, ownership: ownership); return }
                let source = CGEventSource(stateID: .privateState)
                guard let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true), let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { diagnosticCode = "event_unavailable"; snapshot.restore(pasteboard, ownership: ownership); return }
                for event in [down, up] { event.flags = .maskCommand; event.setIntegerValueField(.eventSourceUserData, value: HotkeyService.syntheticTag); event.post(tap: .cghidEventTap) }
                dispatched = true; diagnosticCode = "paste_dispatched"
            }
            if !committed { return (.cancelledBeforeCommit, nil, nil) }
            return (dispatched ? .dispatchedUnverified : .manualRequired, snapshot, ownedCount)
        }()
        guard transaction.0 == .dispatchedUnverified else { return transaction.0 }
        // A console's visible buffer/caret is not an acknowledgement that its
        // input consumer read the paste (raw/no-echo input is a common case).
        // Retain the owned payload and RAM result immediately, with no polling
        // delay and no second dispatch. The outcome remains explicitly unverified.
        if destination.isConsole || !destination.acknowledgementPossible { return .dispatchedUnverified }
        if await awaitAcknowledgement(text, destination: destination) {
            if let snapshot = transaction.1, let ownership = transaction.2 { snapshot.restore(.general, ownership: ownership) }
            return .verifiedInserted
        }
        // No generic public paste acknowledgement exists. A timeout isn't proof
        // of consumption: retain the paste payload and expose the RAM result.
        return .dispatchedUnverified
    }
    private func awaitAcknowledgement(_ text: String, destination: Destination) async -> Bool {
        guard destination.acknowledgementPossible, text.utf16.count <= 65536 else { return false }
        // Native and browser ACKs measured at 6–60 ms. A slow/opaque host keeps
        // the payload and RAM result rather than blocking the next dictation.
        // Expiry changes only the outcome; it never proves consumption/restores.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .milliseconds(350))
        repeat {
            if tracker.acknowledges(text, destination: destination) { return true }
            try? await Task.sleep(for: .milliseconds(50))
        } while clock.now < deadline
        return false
    }
}
