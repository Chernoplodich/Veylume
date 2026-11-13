import Foundation
import CoreAudio

struct OutputAudioControl: Codable, Hashable {
    let uid: String
    let selector: UInt32
    let element: UInt32
    var quietValue: UInt32 { selector == kAudioDevicePropertyMute ? 1 : 0 }
    var valid: Bool {
        !uid.isEmpty && uid.utf8.count <= 1024 && element <= 32 &&
        [kAudioDevicePropertyMute, kAudioDevicePropertyVolumeScalar].contains(selector)
    }
}
struct OutputAudioChange: Codable {
    let control: OutputAudioControl
    let original: UInt32
    var valid: Bool {
        guard control.valid, original != control.quietValue else { return false }
        if control.selector == kAudioDevicePropertyMute { return original <= 1 }
        return Float32(bitPattern: original).isFinite && (0...1).contains(Float32(bitPattern: original))
    }
}
protocol OutputAudioHardware {
    func outputs() -> [String]
    func controls(for uid: String) -> [OutputAudioControl]?
    func read(_ control: OutputAudioControl) -> UInt32?
    func write(_ value: UInt32, to control: OutputAudioControl) -> Bool
}
struct OutputSilencingReport { let outputs: Int; let unavailable: Int }

/// Serial-queue policy. Changes only output mute/volume; never the microphone,
/// routing, an app's playback state, or the user's later volume adjustment.
final class OutputMuteTransaction {
    private let hardware: OutputAudioHardware
    private let save: ([OutputAudioChange]) throws -> Void
    private(set) var changes: [OutputAudioChange]
    private var visited: Set<String> = []
    init(hardware: OutputAudioHardware, pending: [OutputAudioChange] = [], save: @escaping ([OutputAudioChange]) throws -> Void) {
        self.hardware = hardware; self.save = save
        changes = Array(pending.filter { $0.valid }.prefix(128))
    }
    func begin() -> OutputSilencingReport { restore(); visited = []; return updateOutputs() }
    func updateOutputs() -> OutputSilencingReport {
        let outputs = Array(Set(hardware.outputs()).prefix(16)); let current = Set(outputs)
        restore(where: { !current.contains($0.control.uid) })
        visited.formIntersection(current)
        var unavailable = 0
        for uid in outputs where !visited.contains(uid) {
            visited.insert(uid)
            guard let controls = hardware.controls(for: uid), !controls.isEmpty,
                  controls.allSatisfy({ $0.valid }),
                  controls.allSatisfy({ hardware.read($0) != nil }) else { unavailable += 1; continue }
            for control in controls {
                guard !changes.contains(where: { $0.control == control }), let old = hardware.read(control) else { continue }
                if old == control.quietValue { continue } // Already silent: no ownership to undo.
                let change = OutputAudioChange(control: control, original: old)
                changes.append(change)
                do { try save(changes) } catch { changes.removeLast(); unavailable += 1; break }
                if !hardware.write(control.quietValue, to: control) { unavailable += 1; break }
            }
        }
        return OutputSilencingReport(outputs: outputs.count, unavailable: unavailable)
    }
    func restore() { restore(where: { _ in true }); visited = [] }
    private func restore(where included: (OutputAudioChange) -> Bool) {
        changes = changes.filter { change in
            guard included(change) else { return true }
            guard let now = hardware.read(change.control) else { return true } // Unplugged: retain for reconnect/relaunch.
            guard now == change.control.quietValue else { return false } // A later user adjustment wins.
            return !hardware.write(change.original, to: change.control)
        }
        try? save(changes)
    }
}

final class OutputSilencer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Veylume.audio.output", qos: .userInitiated)
    private let transaction: OutputMuteTransaction
    private var session: UUID?
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    init(journal: URL) {
        let pending: [OutputAudioChange]
        if let data = try? Data(contentsOf: journal), data.count <= 65536,
           let decoded = try? JSONDecoder().decode([OutputAudioChange].self, from: data) { pending = decoded }
        else { pending = [] }
        transaction = OutputMuteTransaction(hardware: CoreAudioOutputHardware(), pending: pending) { changes in
            if changes.isEmpty { if FileManager.default.fileExists(atPath: journal.path) { try FileManager.default.removeItem(at: journal) }; return }
            try JSONEncoder().encode(changes).write(to: journal, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journal.path)
        }
        // One recovery pass after an unclean exit, not an idle polling loop.
        queue.async { self.transaction.restore() }
    }
    func begin(session id: UUID) async -> OutputSilencingReport {
        await withCheckedContinuation { continuation in queue.async { [self] in
            self.removeListeners(); self.session = id
            let report = self.transaction.begin()
            for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                    guard let self, self.session != nil else { return }; _ = self.transaction.updateOutputs()
                }
                if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, self.queue, listener) == noErr { self.listeners.append((address, listener)) }
            }
            continuation.resume(returning: report)
        } }
    }
    func end(session id: UUID) {
        queue.async { guard self.session == id else { return }; self.session = nil; self.removeListeners(); self.transaction.restore() }
    }
    func shutdown() { queue.sync { session = nil; removeListeners(); transaction.restore() } }
    private func removeListeners() {
        for (var address, block) in listeners { AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block) }
        listeners = []
    }
}

struct CoreAudioOutputHardware: OutputAudioHardware {
    func outputs() -> [String] {
        [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice].compactMap { selector in
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var device: UInt32 = 0; var size: UInt32 = 4
            guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr, device != 0 else { return nil }
            return uid(device)
        }
    }
    func controls(for uid: String) -> [OutputAudioControl]? {
        guard let device = device(uid) else { return nil }
        func available(_ selector: UInt32, _ element: UInt32) -> Bool {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var settable = DarwinBoolean(false)
            return AudioObjectHasProperty(device, &address) && AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
        }
        for selector in [kAudioDevicePropertyMute, kAudioDevicePropertyVolumeScalar] {
            if available(selector, kAudioObjectPropertyElementMain) { return [OutputAudioControl(uid: uid, selector: selector, element: kAudioObjectPropertyElementMain)] }
        }
        guard let count = channelCount(device), count > 0, count <= 32 else { return nil }
        for selector in [kAudioDevicePropertyMute, kAudioDevicePropertyVolumeScalar] {
            if (1...count).allSatisfy({ available(selector, $0) }) { return (1...count).map { OutputAudioControl(uid: uid, selector: selector, element: $0) } }
        }
        return nil
    }
    func read(_ control: OutputAudioControl) -> UInt32? {
        guard control.valid, let device = device(control.uid) else { return nil }
        var address = address(control); var value: UInt32 = 0, size: UInt32 = 4
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, size == 4 else { return nil }
        if control.selector == kAudioDevicePropertyVolumeScalar {
            let volume = Float32(bitPattern: value); guard volume.isFinite, (0...1).contains(volume) else { return nil }
        } else if value > 1 { return nil }
        return value
    }
    func write(_ value: UInt32, to control: OutputAudioControl) -> Bool {
        guard control.valid, let device = device(control.uid) else { return false }
        if control.selector == kAudioDevicePropertyVolumeScalar { guard Float32(bitPattern: value).isFinite, (0...1).contains(Float32(bitPattern: value)) else { return false } }
        else if value > 1 { return false }
        var address = address(control), data = value
        guard AudioObjectSetPropertyData(device, &address, 0, nil, 4, &data) == noErr else { return false }
        // HAL properties can settle asynchronously. This short bounded wait is
        // on our control queue, never on the UI/audio callback or an idle timer.
        let deadline = DispatchTime.now().uptimeNanoseconds + 150_000_000
        repeat {
            if read(control) == value { return true }
            Thread.sleep(forTimeInterval: 0.005)
        } while DispatchTime.now().uptimeNanoseconds < deadline
        return false
    }
    private func address(_ control: OutputAudioControl) -> AudioObjectPropertyAddress { AudioObjectPropertyAddress(mSelector: control.selector, mScope: kAudioDevicePropertyScopeOutput, mElement: control.element) }
    private func uid(_ device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?; var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
    private func device(_ uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let string = uid as CFString
        var qualifier = Unmanaged.passUnretained(string), result: UInt32 = 0, size: UInt32 = 4
        let status = withExtendedLifetime(string) { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<CFString>.size), &qualifier, &size, &result) }
        guard status == noErr, result != 0 else { return nil }
        return result
    }
    private func channelCount(_ device: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size >= MemoryLayout<AudioBufferList>.size, size <= 65536 else { return nil }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment); defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr else { return nil }
        let list = buffer.assumingMemoryBound(to: AudioBufferList.self)
        guard Int(list.pointee.mNumberBuffers) <= (Int(size) - 8) / MemoryLayout<AudioBuffer>.stride else { return nil }
        let channels = UnsafeMutableAudioBufferListPointer(list).map(\.mNumberChannels)
        guard channels.allSatisfy({ $0 <= 32 }) else { return nil }
        return channels.reduce(0, +)
    }
}
