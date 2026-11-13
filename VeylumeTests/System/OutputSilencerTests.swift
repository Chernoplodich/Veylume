import Testing
import Foundation
import CoreAudio
@testable import VeylumeKit

private final class OutputFixture: OutputAudioHardware {
    var selected = ["speaker"]
    var available: [String: [OutputAudioControl]] = [:]
    var values: [OutputAudioControl: UInt32] = [:]
    var writes: [(OutputAudioControl, UInt32)] = []
    func outputs() -> [String] { selected }
    func controls(for uid: String) -> [OutputAudioControl]? { available[uid] }
    func read(_ control: OutputAudioControl) -> UInt32? { values[control] }
    func write(_ value: UInt32, to control: OutputAudioControl) -> Bool {
        guard values[control] != nil else { return false }
        values[control] = value; writes.append((control, value)); return true
    }
    func add(_ uid: String = "speaker", selector: UInt32 = kAudioDevicePropertyMute, original: UInt32 = 0, channel: UInt32 = 0) -> OutputAudioControl {
        let control = OutputAudioControl(uid: uid, selector: selector, element: channel)
        available[uid, default: []].append(control); values[control] = original; return control
    }
}

struct OutputSilencerTests {
    @Test func muteRestoresPreviousStateOnceAndNeverUnmutesAnAlreadyMutedDevice() {
        let hardware = OutputFixture(); let control = hardware.add()
        let transaction = OutputMuteTransaction(hardware: hardware, save: { _ in })
        #expect(transaction.begin().unavailable == 0); #expect(hardware.values[control] == 1)
        transaction.restore(); transaction.restore()
        #expect(hardware.values[control] == 0); #expect(hardware.writes.count == 2)
        hardware.values[control] = 1
        _ = transaction.begin(); transaction.restore()
        #expect(hardware.values[control] == 1); #expect(hardware.writes.count == 2)
    }
    @Test func volumeFallbackPreservesStereoBalanceAndLaterUserChanges() {
        let hardware = OutputFixture()
        let left = hardware.add(selector: kAudioDevicePropertyVolumeScalar, original: Float32(0.25).bitPattern, channel: 1)
        let right = hardware.add(selector: kAudioDevicePropertyVolumeScalar, original: Float32(0.7).bitPattern, channel: 2)
        let transaction = OutputMuteTransaction(hardware: hardware, save: { _ in })
        _ = transaction.begin(); #expect(hardware.values[left] == 0); #expect(hardware.values[right] == 0)
        hardware.values[right] = Float32(0.4).bitPattern
        transaction.restore()
        #expect(hardware.values[left] == Float32(0.25).bitPattern)
        #expect(hardware.values[right] == Float32(0.4).bitPattern)
    }
    @Test func routeChangeRestoresOldOutputAndMutesNewOutputIncludingSystemAlerts() {
        let hardware = OutputFixture(); let old = hardware.add(); let new = hardware.add("headphones"); let alerts = hardware.add("alerts")
        hardware.selected = ["speaker", "alerts", "speaker"]
        let transaction = OutputMuteTransaction(hardware: hardware, save: { _ in })
        #expect(transaction.begin().outputs == 2)
        hardware.selected = ["headphones", "alerts"]
        _ = transaction.updateOutputs()
        #expect(hardware.values[old] == 0); #expect(hardware.values[new] == 1); #expect(hardware.values[alerts] == 1)
        transaction.restore(); #expect(hardware.values[new] == 0); #expect(hardware.values[alerts] == 0)
    }
    @Test func durableIntentPrecedesSystemMutationAndMissingJournalPreventsIt() {
        let hardware = OutputFixture(); _ = hardware.add()
        let transaction = OutputMuteTransaction(hardware: hardware, save: { changes in
            if !changes.isEmpty { #expect(hardware.writes.isEmpty); throw CocoaError(.fileWriteNoPermission) }
        })
        #expect(transaction.begin().unavailable == 1)
        #expect(hardware.writes.isEmpty); #expect(transaction.changes.isEmpty)
    }
    @Test func uncleanExitRecoveryUsesStableDeviceIdentityAndKeepsUnpluggedIntent() {
        let hardware = OutputFixture(); let control = hardware.add(original: 1)
        let transaction = OutputMuteTransaction(hardware: hardware, pending: [OutputAudioChange(control: control, original: 0)], save: { _ in })
        hardware.values[control] = nil; transaction.restore(); #expect(transaction.changes.count == 1)
        hardware.values[control] = 1; transaction.restore()
        #expect(hardware.values[control] == 0); #expect(transaction.changes.isEmpty)
    }
    @Test func unsupportedOutputDoesNotPreventSupportedOutputOrClaimSuccess() {
        let hardware = OutputFixture(); let control = hardware.add(); hardware.selected.append("hdmi")
        let transaction = OutputMuteTransaction(hardware: hardware, save: { _ in })
        let report = transaction.begin(); #expect(report.outputs == 2); #expect(report.unavailable == 1)
        #expect(hardware.values[control] == 1); transaction.restore(); #expect(hardware.values[control] == 0)
    }
}
