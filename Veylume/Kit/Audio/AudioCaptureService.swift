import AVFoundation
import CoreAudio
import os
import VeylumeCore

struct MicrophoneDevice: Identifiable { let id: String; let name: String; let audioID: AudioDeviceID }
struct CapturedAudio { let archive: AudioArchive; let energeticSeconds: Double; let stopMilliseconds: Double }

/// Audio tap only copies into a preallocated bounded pool. Conversion, encryption
/// and disk writes run on the consumer queue. Stop never waits for the writer.
final class AudioCaptureService: @unchecked Sendable {
    private let control = DispatchQueue(label: "Veylume.audio.control", qos: .userInteractive)
    private let writer = DispatchQueue(label: "Veylume.audio.writer", qos: .userInitiated)
    private struct Pool {
        var free: [AVAudioPCMBuffer] = [], pending: [AVAudioPCMBuffer] = []
        var accepting = false, draining = false, overflowed = false
    }
    private let pool = OSAllocatedUnfairLock(initialState: Pool())
    private let stopIntent = OSAllocatedUnfairLock(initialState: false)
    private struct Timing { var requested: UInt64?; var stopped: UInt64? }
    private let timing = OSAllocatedUnfairLock(initialState: Timing())
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var conversionBuffer: AVAudioPCMBuffer?
    private var archive: AudioArchive?
    private var failure: Error?
    private var energeticSamples = 0
    private var meterTick = Date.distantPast
    private var smoothedLevel = 0.0
    var onLevel: (@Sendable (Double) -> Void)?
    var onFailure: (@Sendable (Problem) -> Void)?
    var onChunk: (@Sendable (AudioArchive) throws -> Void)?
    func beginSession() { stopIntent.withLock { $0 = false }; timing.withLock { $0 = Timing() } }
    func requestImmediateStop() {
        let now = DispatchTime.now().uptimeNanoseconds
        timing.withLock { if $0.requested == nil { $0.requested = now } }
        stopIntent.withLock { $0 = true }; pool.withLock { $0.accepting = false }
        control.async { self.stopEngine() }
    }
    private func stopEngine() {
        let wasRunning = engine?.isRunning == true
        engine?.stop()
        if wasRunning { let now = DispatchTime.now().uptimeNanoseconds; timing.withLock { if $0.stopped == nil { $0.stopped = now } } }
    }

    func start(archive: AudioArchive, deviceUID: String?) async throws {
        try await withCheckedThrowingContinuation { continuation in
            control.async {
                do {
                    guard !self.stopIntent.withLock({ $0 }) else { throw Problem.noSpeech }
                    guard self.engine == nil else { throw Problem.capture }
                    let engine = AVAudioEngine(); self.engine = engine
                    let input = engine.inputNode
                    if let uid = deviceUID {
                        guard let device = Self.devices().first(where: { $0.id == uid }), let unit = input.audioUnit else { throw Problem.capture }
                        var id = device.audioID
                        guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout.size(ofValue: id))) == noErr else { throw Problem.capture }
                    }
                    let format = input.outputFormat(forBus: 0)
                    guard format.sampleRate > 0, format.channelCount > 0, format.commonFormat == .pcmFormatFloat32,
                          let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
                          let converter = AVAudioConverter(from: format, to: output) else { throw Problem.capture }
                    self.converter = converter; self.outputFormat = output; self.archive = archive
                    self.conversionBuffer = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: 16384)
                    guard self.conversionBuffer != nil else { throw Problem.capture }
                    self.failure = nil; self.energeticSamples = 0; self.smoothedLevel = 0; self.meterTick = .distantPast
                    var free: [AVAudioPCMBuffer] = []; free.reserveCapacity(32)
                    for _ in 0..<32 { guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { throw Problem.capture }; free.append(buffer) }
                    let buffers = free
                    self.pool.withLock { p in p = Pool(); p.free = buffers; p.pending.reserveCapacity(32); p.accepting = true }
                    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in self.enqueue(buffer) }
                    guard !self.stopIntent.withLock({ $0 }) else { throw Problem.noSpeech }
                    engine.prepare(); try engine.start()
                    guard !self.stopIntent.withLock({ $0 }) else { throw Problem.noSpeech }
                    continuation.resume()
                } catch {
                    self.pool.withLock { $0.accepting = false }
                    self.stopEngine(); self.engine?.inputNode.removeTap(onBus: 0); self.engine = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    private func enqueue(_ input: AVAudioPCMBuffer) {
        let (schedule, overflow) = pool.withLock { p -> (Bool, Bool) in
            guard p.accepting else { return (false, false) }
            guard input.frameLength <= 8192, let buffer = p.free.popLast(), let source = input.floatChannelData, let target = buffer.floatChannelData else {
                if !p.overflowed { p.overflowed = true; p.accepting = false; return (false, true) }; return (false, false)
            }
            buffer.frameLength = input.frameLength
            let channels = input.format.isInterleaved ? 1 : Int(input.format.channelCount)
            let frames = Int(input.frameLength) * (input.format.isInterleaved ? Int(input.format.channelCount) : 1)
            for channel in 0..<channels { target[channel].update(from: source[channel], count: frames) }
            p.pending.append(buffer)
            if !p.draining { p.draining = true; return (true, false) }
            return (false, false)
        }
        if schedule { writer.async { self.drain() } }
        if overflow { onFailure?(.overflow) }
    }
    private func drain() {
        while true {
            let input: AVAudioPCMBuffer? = pool.withLock { p in
                if p.pending.isEmpty { p.draining = false; return nil }
                return p.pending.removeFirst()
            }
            guard let input else { return }
            defer { pool.withLock { $0.free.append(input) } }
            do { if failure == nil { try convert(input, end: false) } }
            catch { failure = error; pool.withLock { $0.accepting = false }; onFailure?(.storage) }
        }
    }
    private func convert(_ input: AVAudioPCMBuffer?, end: Bool) throws {
        guard let converter else { return }
        var supplied = false
        while true {
            guard let output = conversionBuffer else { throw Problem.capture }
            output.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in
                if let input, !supplied { supplied = true; state.pointee = .haveData; return input }
                state.pointee = end ? .endOfStream : .noDataNow; return nil
            }
            if let error { throw error }
            if output.frameLength > 0, let pointer = output.floatChannelData?[0] {
                let samples = Array(UnsafeBufferPointer(start: pointer, count: Int(output.frameLength)))
                let energy = samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count)
                if energy > 0.00000225 { energeticSamples += samples.count }
                let decibels = 20 * log10(max(sqrt(energy), 0.00001))
                let targetLevel = max(0, min(1, (decibels + 65) / 50))
                let tau = targetLevel > smoothedLevel ? 0.045 : 0.22
                let alpha = 1 - exp(-Double(samples.count) / (16000 * tau))
                smoothedLevel += alpha * (targetLevel - smoothedLevel)
                if Date().timeIntervalSince(meterTick) >= 1.0 / 30 { meterTick = Date(); onLevel?(smoothedLevel) }
                let previousChunks = archive?.chunkCount
                try archive?.append(samples)
                if let archive, previousChunks != archive.chunkCount { try onChunk?(archive) }
            }
            if status == .error { throw Problem.capture }
            if status == .inputRanDry || status == .endOfStream || (output.frameLength == 0 && status != .haveData) { break }
        }
    }
    /// Disallow further samples immediately, then stop hardware on its own queue.
    func stop() async throws -> CapturedAudio? {
        let observed = DispatchTime.now().uptimeNanoseconds
        timing.withLock { if $0.requested == nil { $0.requested = observed } }
        pool.withLock { $0.accepting = false }
        let milliseconds: Double = await withCheckedContinuation { continuation in
            control.async {
                self.stopEngine(); self.engine?.inputNode.removeTap(onBus: 0); self.engine = nil
                let now = DispatchTime.now().uptimeNanoseconds
                let elapsed = self.timing.withLock { Double(($0.stopped ?? now) - ($0.requested ?? observed)) / 1_000_000 }
                continuation.resume(returning: elapsed)
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            writer.async {
                do {
                    self.drain(); try self.convert(nil, end: true); try self.archive?.finish()
                    if let archive = self.archive { try self.onChunk?(archive) }
                    if let failure = self.failure { throw failure }
                    let result = self.archive.map { CapturedAudio(archive: $0, energeticSeconds: Double(self.energeticSamples) / 16000, stopMilliseconds: milliseconds) }
                    self.converter = nil; self.conversionBuffer = nil; self.archive = nil; self.onChunk = nil; self.onLevel?(0)
                    continuation.resume(returning: result)
                } catch { self.converter = nil; self.conversionBuffer = nil; self.archive = nil; self.onChunk = nil; continuation.resume(throwing: error) }
            }
        }
    }
    static func devices() -> [MicrophoneDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &bytes) == noErr, bytes > 0 else { return nil }
            func string(_ selector: AudioObjectPropertySelector) -> String? {
                var a = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                var value: Unmanaged<CFString>?; var length = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                guard AudioObjectGetPropertyData(id, &a, 0, nil, &length, &value) == noErr else { return nil }; return value?.takeRetainedValue() as String?
            }
            guard let uid = string(kAudioDevicePropertyDeviceUID), let name = string(kAudioObjectPropertyName) else { return nil }
            return MicrophoneDevice(id: uid, name: name, audioID: id)
        }
    }
}
