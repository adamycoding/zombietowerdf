//
//  SoundManager.swift
//  Core
//
//  Sound effects and background music, with on/off switches in Settings.
//  There are no audio files: every sound is made from a few sine/square/noise
//  waves when the app starts (a small retro synth), packed into WAV data and
//  played with AVFoundation. To use real recordings later, replace
//  `makeData(for:)` / `makeMusic()` with `AVAudioPlayer(contentsOf:)`.
//

import AVFoundation
import QuartzCore

final class SoundManager {

    static let shared = SoundManager()

    enum Effect: CaseIterable {
        case shot, heavyShot, flame, tesla, frost
        case kill, place, upgrade, sell, wave, baseHit, gameOver, win, tap
    }

    // MARK: Settings (saved between launches)

    var soundOn: Bool {
        didSet { UserDefaults.standard.set(soundOn, forKey: "soundOn") }
    }
    /// Separate switch for the zombie death sound (it plays a lot).
    var deathSoundOn: Bool {
        didSet { UserDefaults.standard.set(deathSoundOn, forKey: "deathSoundOn") }
    }
    var musicOn: Bool {
        didSet {
            UserDefaults.standard.set(musicOn, forKey: "musicOn")
            if musicOn { startMusic() } else { music?.pause() }
        }
    }

    // MARK: Players

    private var voices: [Effect: [AVAudioPlayer]] = [:]
    private var nextVoice: [Effect: Int] = [:]
    private var lastPlayed: [Effect: TimeInterval] = [:]
    private var music: AVAudioPlayer?
    private var musicIsBuilding = false

    private init() {
        UserDefaults.standard.register(defaults: ["soundOn": true, "musicOn": true, "deathSoundOn": true])
        soundOn = UserDefaults.standard.bool(forKey: "soundOn")
        musicOn = UserDefaults.standard.bool(forKey: "musicOn")
        deathSoundOn = UserDefaults.standard.bool(forKey: "deathSoundOn")
        // Ambient: mixes with other audio and follows the silent switch.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        for effect in Effect.allCases {
            let data = SoundManager.makeData(for: effect)
            voices[effect] = (0..<3).compactMap { _ in
                let player = try? AVAudioPlayer(data: data)
                player?.prepareToPlay()
                return player
            }
        }
    }

    /// Call once at launch so the first shot doesn't have to wait.
    func prepare() {}

    // MARK: Playing

    func play(_ effect: Effect) {
        guard soundOn, effect != .kill || deathSoundOn, let players = voices[effect], !players.isEmpty else { return }
        let now = CACurrentMediaTime()
        let minGap: TimeInterval = (effect == .shot || effect == .flame || effect == .kill) ? 0.05 : 0.02
        if let last = lastPlayed[effect], now - last < minGap { return }
        lastPlayed[effect] = now
        let index = (nextVoice[effect] ?? 0) % players.count
        nextVoice[effect] = index + 1
        let player = players[index]
        player.currentTime = 0
        player.play()
    }

    func startMusic() {
        guard musicOn else { return }
        if let music {
            if !music.isPlaying { music.play() }
            return
        }
        guard !musicIsBuilding else { return }
        musicIsBuilding = true
        DispatchQueue.global(qos: .utility).async {
            let data = SoundManager.makeMusic()
            DispatchQueue.main.async {
                self.musicIsBuilding = false
                guard let player = try? AVAudioPlayer(data: data) else { return }
                player.numberOfLoops = -1
                player.volume = 0.45
                self.music = player
                if self.musicOn { player.play() }
            }
        }
    }

    // MARK: Tiny synth

    private static let rate = 22050.0

    private enum Wave { case sine, square, noise }
    private enum Shape { case decay, hold }

    private struct Voice {
        var start: Double = 0
        var duration: Double
        var from: Double
        var to: Double? = nil
        var wave: Wave = .sine
        var volume: Double = 0.3
        var shape: Shape = .decay
    }

    /// Mixes the voices into one mono track and wraps it as WAV data.
    private static func render(_ voices: [Voice], length: Double) -> Data {
        let count = Int(length * rate)
        var mix = [Float](repeating: 0, count: count)
        for voice in voices {
            let first = Int(voice.start * rate)
            let last = min(count, Int((voice.start + voice.duration) * rate))
            guard first < last else { continue }
            var phase = 0.0
            let target = voice.to ?? voice.from
            for i in first..<last {
                let t = Double(i - first) / rate
                let p = t / voice.duration
                let freq = voice.from + (target - voice.from) * p
                phase += 2 * Double.pi * freq / rate
                var s: Double
                switch voice.wave {
                case .sine: s = sin(phase)
                case .square: s = sin(phase) >= 0 ? 0.6 : -0.6
                case .noise: s = Double.random(in: -1...1)
                }
                let attack = min(1, t / 0.004)
                let env: Double
                switch voice.shape {
                case .decay: env = (1 - p) * (1 - p) * attack
                case .hold: env = attack * min(1, (voice.duration - t) / 0.03)
                }
                mix[i] += Float(s * env * voice.volume)
            }
        }
        var bytes = [UInt8]()
        bytes.reserveCapacity(44 + count * 2)
        func put32(_ v: UInt32) { for k in 0..<4 { bytes.append(UInt8((v >> (8 * UInt32(k))) & 0xFF)) } }
        func put16(_ v: UInt16) { for k in 0..<2 { bytes.append(UInt8((v >> (8 * UInt16(k))) & 0xFF)) } }
        bytes.append(contentsOf: Array("RIFF".utf8)); put32(UInt32(36 + count * 2))
        bytes.append(contentsOf: Array("WAVEfmt ".utf8)); put32(16)
        put16(1); put16(1); put32(UInt32(rate)); put32(UInt32(rate) * 2); put16(2); put16(16)
        bytes.append(contentsOf: Array("data".utf8)); put32(UInt32(count * 2))
        for sample in mix {
            let v = Int16(max(-1, min(1, sample)) * 32000)
            put16(UInt16(bitPattern: v))
        }
        return Data(bytes)
    }

    private static func makeData(for effect: Effect) -> Data {
        func note(_ start: Double, _ f: Double, _ dur: Double, _ wave: Wave = .sine, _ vol: Double = 0.3) -> Voice {
            Voice(start: start, duration: dur, from: f, wave: wave, volume: vol)
        }
        switch effect {
        case .shot:
            return render([Voice(duration: 0.09, from: 0, wave: .noise, volume: 0.35),
                           Voice(duration: 0.09, from: 520, to: 140, volume: 0.3)], length: 0.1)
        case .heavyShot:
            return render([Voice(duration: 0.2, from: 0, wave: .noise, volume: 0.45),
                           Voice(duration: 0.22, from: 200, to: 50, volume: 0.5)], length: 0.22)
        case .flame:
            return render([Voice(duration: 0.14, from: 0, wave: .noise, volume: 0.22)], length: 0.14)
        case .tesla:
            return render([Voice(duration: 0.16, from: 900, to: 150, wave: .square, volume: 0.22),
                           Voice(duration: 0.16, from: 0, wave: .noise, volume: 0.15)], length: 0.16)
        case .frost:
            return render([note(0, 1300, 0.12, .sine, 0.22), note(0.07, 1750, 0.2, .sine, 0.2)], length: 0.27)
        case .kill:
            return render([Voice(duration: 0.16, from: 320, to: 70, wave: .square, volume: 0.22),
                           Voice(duration: 0.1, from: 0, wave: .noise, volume: 0.2)], length: 0.16)
        case .place:
            return render([Voice(duration: 0.12, from: 260, to: 620, volume: 0.35)], length: 0.12)
        case .upgrade:
            return render([note(0, 523, 0.09, .square, 0.2), note(0.08, 659, 0.09, .square, 0.2),
                           note(0.16, 784, 0.09, .square, 0.2), note(0.24, 1046, 0.22, .square, 0.22)], length: 0.46)
        case .sell:
            return render([note(0, 880, 0.08, .sine, 0.3), note(0.07, 1320, 0.2, .sine, 0.3)], length: 0.27)
        case .wave:
            return render([note(0, 523, 0.5, .sine, 0.22), note(0, 659, 0.5, .sine, 0.18),
                           note(0, 784, 0.5, .sine, 0.18)], length: 0.5)
        case .baseHit:
            return render([Voice(duration: 0.28, from: 120, to: 60, wave: .square, volume: 0.4),
                           Voice(duration: 0.2, from: 0, wave: .noise, volume: 0.25)], length: 0.28)
        case .gameOver:
            return render([note(0, 392, 0.3, .square, 0.25), note(0.3, 330, 0.3, .square, 0.25),
                           note(0.6, 262, 0.3, .square, 0.25), note(0.9, 196, 0.7, .square, 0.28)], length: 1.6)
        case .win:
            return render([note(0, 523, 0.18, .square, 0.22), note(0.18, 659, 0.18, .square, 0.22),
                           note(0.36, 784, 0.18, .square, 0.22), note(0.54, 1046, 0.8, .square, 0.25),
                           note(0.54, 784, 0.8, .sine, 0.18)], length: 1.4)
        case .tap:
            return render([Voice(duration: 0.05, from: 700, to: 500, volume: 0.25)], length: 0.05)
        }
    }

    /// A slow, spooky loop in A minor: pad, bass, an arpeggio and soft drums.
    private static func makeMusic() -> Data {
        let beat = 60.0 / 100.0
        let bar = beat * 4
        let eighth = beat / 2
        let bars = 8
        // Each chord lasts two bars: Am, F, Dm, E.
        let chords: [(root: Double, tones: [Double])] = [
            (110.00, [220.00, 261.63, 329.63]),
            (87.31, [174.61, 220.00, 261.63]),
            (73.42, [146.83, 174.61, 220.00]),
            (82.41, [164.81, 207.65, 246.94])
        ]
        var voices: [Voice] = []
        for b in 0..<bars {
            let chord = chords[b / 2]
            let t0 = Double(b) * bar
            // Soft pad.
            for tone in chord.tones {
                voices.append(Voice(start: t0, duration: bar, from: tone, volume: 0.035, shape: .hold))
            }
            // Bass: root, root, fifth, root...
            let pattern: [Double] = [1, 1, 1.5, 1, 1, 1.5, 1, 1.5]
            for i in 0..<8 {
                voices.append(Voice(start: t0 + Double(i) * eighth, duration: eighth * 0.9,
                                    from: chord.root * pattern[i], wave: .square, volume: 0.07, shape: .hold))
            }
            // Arpeggio an octave up.
            let arp = [0, 1, 2, 1, 0, 2, 1, 2]
            for i in 0..<8 {
                voices.append(Voice(start: t0 + Double(i) * eighth, duration: eighth * 1.4,
                                    from: chord.tones[arp[i]] * 2, wave: .sine, volume: 0.07))
            }
            // Drums: kick on 1 and 3, snare on 2 and 4, hat on the off-beats.
            for beatIndex in 0..<4 {
                let t = t0 + Double(beatIndex) * beat
                if beatIndex % 2 == 0 {
                    voices.append(Voice(start: t, duration: 0.14, from: 130, to: 40, volume: 0.28))
                } else {
                    voices.append(Voice(start: t, duration: 0.1, from: 0, wave: .noise, volume: 0.07))
                }
                voices.append(Voice(start: t + eighth, duration: 0.03, from: 0, wave: .noise, volume: 0.035))
            }
        }
        return render(voices, length: Double(bars) * bar)
    }
}
