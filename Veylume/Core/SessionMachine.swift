import Foundation

public enum RecordingMode: String, Codable, Sendable, CaseIterable { case hold, toggle }
public enum SessionPhase: String, Sendable { case idle, preparing, recording, stopping, transcribing, finalizing, inserting, cancelling }
public enum SessionEffect: Equatable, Sendable {
    case prepare(UUID), stop(UUID), recognize(UUID), finalize(UUID), insert(UUID), discard(UUID)
}
public enum SessionEvent: Sendable {
    case begin(UUID, RecordingMode), release, stop, cancel
    case audioReady(UUID), audioStopped(UUID, usable: Bool), recognized(UUID), finalized(UUID)
    case finished(UUID), failed(UUID), cleanupFinished(UUID)
}

/// All external effects are authorized here. A cancelled inference retains its
/// slot until cleanup, even if the underlying Core ML call ignores cancellation.
public struct SessionMachine: Sendable {
    public private(set) var phase: SessionPhase = .idle
    public private(set) var id: UUID?
    public private(set) var generation: UInt64 = 0
    public private(set) var mode: RecordingMode = .hold
    public private(set) var stopRequested = false
    public private(set) var insertionCommitted = false

    public init() {}
    public func accepts(_ candidate: UUID) -> Bool { id == candidate && phase != .idle && phase != .cancelling }
    public var isBusy: Bool { phase != .idle }

    public mutating func send(_ event: SessionEvent) -> [SessionEffect] {
        switch event {
        case let .begin(newID, newMode):
            guard phase == .idle else { return [] }
            generation &+= 1; id = newID; mode = newMode
            stopRequested = false; insertionCommitted = false; phase = .preparing
            return [.prepare(newID)]
        case .release:
            guard mode == .hold else { return [] }
            return requestStop()
        case .stop: return requestStop()
        case .cancel:
            guard let id, phase != .idle, phase != .cancelling, !insertionCommitted else { return [] }
            generation &+= 1; phase = .cancelling
            return [.discard(id)]
        case let .audioReady(candidate):
            guard accepts(candidate), phase == .preparing else { return [] }
            if stopRequested { phase = .stopping; return [.stop(candidate)] }
            phase = .recording
        case let .audioStopped(candidate, usable):
            guard accepts(candidate), phase == .stopping else { return [] }
            if usable { phase = .transcribing; return [.recognize(candidate)] }
            reset()
        case let .recognized(candidate):
            guard accepts(candidate), phase == .transcribing else { return [] }
            phase = .finalizing; return [.finalize(candidate)]
        case let .finalized(candidate):
            guard accepts(candidate), phase == .finalizing, !insertionCommitted else { return [] }
            // Dispatch and cancellation are serialized by the owner. No retry.
            insertionCommitted = true; phase = .inserting; return [.insert(candidate)]
        case let .finished(candidate), let .failed(candidate):
            guard id == candidate, phase != .cancelling else { return [] }; reset()
        case let .cleanupFinished(candidate):
            guard id == candidate, phase == .cancelling else { return [] }; reset()
        }
        return []
    }

    private mutating func requestStop() -> [SessionEffect] {
        guard let id else { return [] }
        if phase == .preparing { stopRequested = true; return [] }
        guard phase == .recording else { return [] }
        phase = .stopping; return [.stop(id)]
    }
    private mutating func reset() { phase = .idle; id = nil; stopRequested = false }
}
