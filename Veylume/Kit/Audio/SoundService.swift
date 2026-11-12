import AVFoundation
import VeylumeCore

@MainActor final class SoundService {
    enum Cue { case start, stop, cancel }
    private var player: AVAudioPlayer?
    func play(_ cue: Cue, preferences: Preferences) {
        guard preferences.soundsEnabled, preferences.soundVolume > 0 else { return }
        let frames = 4800, rate = 48000
        var pcm = Data(); pcm.reserveCapacity(frames * 2)
        for n in 0..<frames {
            let t = Double(n) / Double(rate), x = Double(n) / Double(frames)
            let frequency = cue == .start ? 620 + 240 * x : cue == .stop ? 620 - 200 * x : 270 - 80 * x
            var value = Int16(sin(2 * .pi * frequency * t) * sin(.pi * x) * 8000).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        var wav = Data("RIFF".utf8)
        func number<T: FixedWidthInteger>(_ value: T) { var value = value.littleEndian; withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) } }
        number(UInt32(36 + pcm.count)); wav.append(Data("WAVEfmt ".utf8)); number(UInt32(16)); number(UInt16(1)); number(UInt16(1)); number(UInt32(rate)); number(UInt32(rate * 2)); number(UInt16(2)); number(UInt16(16)); wav.append(Data("data".utf8)); number(UInt32(pcm.count)); wav.append(pcm)
        player = try? AVAudioPlayer(data: wav); player?.volume = preferences.soundVolume; player?.play()
    }
}
