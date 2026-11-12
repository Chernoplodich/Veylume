import Foundation
import AVFoundation
import VeylumeCore
import Darwin
import Security

/// Developer-only runner. It is a separate executable and is never copied into
/// Veylume.app. Reports contain metrics/assertions, never the transcript or paths.
public enum NativeVerification {
    public static func run(arguments: [String]) async -> Int32 {
        if arguments.count == 2, arguments[0] == "indicator-settings" {
            return await NativeIndicatorSettingsVerification.run(output: URL(fileURLWithPath: arguments[1], isDirectory: true))
        }
        if arguments.count == 2, arguments[0] == "indicators" {
            return await NativeIndicatorVerification.run(output: URL(fileURLWithPath: arguments[1], isDirectory: true))
        }
        if arguments.count == 2, arguments[0] == "components" {
            return await NativeComponentVerification.run(output: URL(fileURLWithPath: arguments[1], isDirectory: true))
        }
        if arguments.count == 3, ["meter-native", "meter-wide", "meter-legacy", "meter-idle"].contains(arguments[0]), let seconds = Double(arguments[1]) {
            return await NativeMeterVerification.run(mode: arguments[0], seconds: seconds, report: URL(fileURLWithPath: arguments[2]))
        }
        if arguments == ["keychain-status"] {
            var before = DarwinBoolean(false), after = DarwinBoolean(false)
            _ = SecKeychainGetUserInteractionAllowed(&before)
            let start = Date(); var status = "ready"
            do { try KeychainKeys(service: "local.Veylume.dev.keys").verifyExistingAccess(to: "recovery") }
            catch { status = "authorizationRequired" }
            _ = SecKeychainGetUserInteractionAllowed(&after)
            let report: [String: Any] = ["status": status, "seconds": Date().timeIntervalSince(start), "interactionPolicyRestored": before.boolValue == after.boolValue, "mode": "noninteractive-existing-only"]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) { print(String(decoding: data, as: UTF8.self)) }
            return before.boolValue == after.boolValue ? 0 : 1
        }
        guard arguments.count >= 4, ["asr", "asr-prepared", "asr-cap", "asr-serial", "asr-move"].contains(arguments[0]) else {
            print("Usage: VeylumeVerify asr|asr-prepared|asr-cap|asr-serial|asr-move MODEL_ID MODEL_DIRECTORY AUDIO_FILE [REFERENCE_TEXT_FILE] [LANGUAGE]")
            return 2
        }
        let modelID = arguments[1], audio = URL(fileURLWithPath: arguments[3])
        var directory = URL(fileURLWithPath: arguments[2])
        let language = arguments.count >= 6 ? arguments[5] : "auto"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VeylumeVerification-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var stage = "manifest"
        do {
            guard let url = Bundle.module.url(forResource: modelID, withExtension: "json") else { throw Problem.modelNotReady }
            let manifest = try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: url))
            let archive = try AudioArchive(id: UUID(), root: root)
            stage = "audioConversion"
            try convert(audio, into: archive)
            stage = "reference"
            let reference = arguments.count >= 5 ? try String(contentsOf: URL(fileURLWithPath: arguments[4]), encoding: .utf8) : nil
            let host: EngineHost
            if arguments[0] == "asr-cap" {
                guard modelID == "cohere-transcribe" else { throw Problem.modelNotReady }
                host = EngineHost(loader: { manifest, directory in
                    try ModelIntegrity.verify(manifest, at: directory)
                    let engine = CohereEngine(tokenLimit: 1); try await engine.load(from: directory); return engine
                })
            } else if arguments[0] == "asr-serial" {
                guard modelID == "parakeet-v3" else { throw Problem.modelNotReady }
                host = EngineHost(loader: { manifest, directory in
                    try ModelIntegrity.verify(manifest, at: directory)
                    let engine = FluidAudioEngine(chunkConcurrency: 1); try await engine.load(from: directory); return engine
                })
            } else { host = EngineHost() }
            let preparationStarted = Date()
            if arguments[0] == "asr-prepared" { try await host.prepare(manifest, directory: directory) }
            if arguments[0] == "asr-move" {
                let staging = root.appendingPathComponent("staging"), installed = root.appendingPathComponent("installed")
                try FileManager.default.copyItem(at: directory, to: staging)
                try await host.selfCheck(manifest, directory: staging)
                try FileManager.default.moveItem(at: staging, to: installed)
                await host.adoptInstalledDirectory(modelID: modelID, previous: staging, installed: installed); directory = installed
            }
            let preparationSeconds = ["asr-prepared", "asr-move"].contains(arguments[0]) ? Date().timeIntervalSince(preparationStarted) : 0
            stage = "recognition"
            var reports: [[String: Any]] = []
            for _ in 0..<(arguments[0] == "asr-prepared" ? 10 : 2) {
                var before = rusage(); getrusage(RUSAGE_SELF, &before)
                let recognized = try await host.recognize(archive, manifest: manifest, directory: directory, language: language, progress: { _ in })
                var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
                let m = recognized.measurement
                var report: [String: Any] = ["model": modelID, "revision": manifest.revision, "cold": m.cold, "loadSeconds": m.loadSeconds, "asrSeconds": m.recognitionSeconds, "audioSeconds": m.capturedSeconds, "rtf": m.rtf, "complete": recognized.result.complete, "recognizedWords": TextFinalizer.wordCount(recognized.result.text), "maxResidentBytes": usage.ru_maxrss]
                func cpu(_ value: rusage) -> Double { Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec) + Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1_000_000 }
                report["cpuSeconds"] = cpu(usage) - cpu(before)
                if let reference { report["wordErrorRate"] = wordErrorRate(reference: reference, actual: recognized.result.text) }
                reports.append(report)
            }
            let data = try JSONSerialization.data(withJSONObject: ["os": ProcessInfo.processInfo.operatingSystemVersionString, "ramBytes": ProcessInfo.processInfo.physicalMemory, "preparationSeconds": preparationSeconds, "measurements": reports], options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self)); return 0
        } catch {
            let code = (error as? Problem)?.rawValue ?? (error is CancellationError ? "cancelled" : "verificationFailed")
            let ns = error as NSError
            let domain = [NSCocoaErrorDomain, NSOSStatusErrorDomain, NSURLErrorDomain, "com.apple.CoreML", "com.apple.coreaudio.avfaudio"].contains(ns.domain) ? ns.domain : "other"
            let report: [String: Any] = ["error": code, "stage": stage, "errorDomain": domain, "errorCode": ns.code, "errorType": String(reflecting: type(of: error))]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) { print(String(decoding: data, as: UTF8.self)) }; return 1
        }
    }
    private static func convert(_ url: URL, into archive: AudioArchive) throws {
        let file = try AVAudioFile(forReading: url), input = file.processingFormat
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input, to: target),
              let source = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 8192) else { throw Problem.capture }
        var finished = false
        while true {
            let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 16000)!
            var conversionError: NSError?, readError: Error?
            let status = converter.convert(to: output, error: &conversionError) { requested, flag in
                if finished || file.framePosition >= file.length { finished = true; flag.pointee = .endOfStream; return nil }
                do {
                    try file.read(into: source, frameCount: min(requested, source.frameCapacity))
                    if source.frameLength == 0 { finished = true; flag.pointee = .endOfStream; return nil }
                    flag.pointee = .haveData; return source
                } catch { readError = error; flag.pointee = .endOfStream; return nil }
            }
            if let error = readError ?? conversionError { throw error }
            if output.frameLength > 0 { try archive.append(Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))) }
            if status == .endOfStream { break }; if status == .error { throw Problem.capture }
        }
        try archive.finish()
    }
    private static func wordErrorRate(reference: String, actual: String) -> Double {
        func words(_ s: String) -> [String] { s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init) }
        let a = words(reference), b = words(actual)
        var previous = Array(0...b.count)
        for (i, word) in a.enumerated() {
            var row = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, candidate) in b.enumerated() { row[j + 1] = min(previous[j + 1] + 1, row[j] + 1, previous[j] + (word == candidate ? 0 : 1)) }
            previous = row
        }
        return Double(previous[b.count]) / Double(max(1, a.count))
    }
}
