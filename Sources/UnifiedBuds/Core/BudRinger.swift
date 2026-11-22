import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import os

/// Plays an audible high-pitched locating chime through the connected earbuds,
/// panned 100% to the left or right earbud channel so the user can physically
/// locate a misplaced bud by sound.
@MainActor
final class BudRinger {
    static let shared = BudRinger()

    private var engine: AVAudioEngine?
    private var leftPlayer: AVAudioPlayerNode?
    private var rightPlayer: AVAudioPlayerNode?
    private var chirpPCMBuffer: AVAudioPCMBuffer?
    private var stopTimer: Timer?
    private var savedVolume: Float32?

    private(set) var isRingingLeft = false
    private(set) var isRingingRight = false

    private init() {
        prepareBuffer()
    }

    /// Synthesizes an intense, piercing multi-harmonic alarm waveform (2800 Hz ⇄ 3600 Hz)
    /// saturated with odd harmonics (3rd & 5th) and rapid piezo-style bursts.
    /// This produces maximum psychoacoustic loudness (~5x–10x louder to human ears than a gentle sine chirp).
    private func prepareBuffer() {
        let sampleRate: Double = 44100
        let duration: Double = 0.78 // Rapid 780ms repeating emergency beacon loop
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        let beeps: [(start: Double, end: Double, freq: Double)] = [
            (0.00, 0.14, 2800.0),
            (0.16, 0.30, 3600.0),
            (0.32, 0.46, 2800.0),
            (0.48, 0.62, 3600.0),
        ]

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            var sample: Float = 0.0
            for b in beeps {
                if t >= b.start && t < b.end {
                    let relT = t - b.start
                    let bDur = b.end - b.start
                    let fade = 0.004 // 4ms smooth anti-pop edge
                    var env = 1.0
                    if relT < fade {
                        env = relT / fade
                    } else if relT > bDur - fade {
                        env = (bDur - relT) / fade
                    }
                    let phase = 2.0 * .pi * b.freq * relT
                    // Fundamental + strong 3rd & 5th harmonics
                    let raw = sin(phase) + 0.45 * sin(3.0 * phase) + 0.25 * sin(5.0 * phase)
                    // Hyperbolic tangent saturation gives a dense, razor-sharp piezo buzzer timbre
                    sample = Float(tanh(raw * 2.8) * 0.99 * env)
                    break
                }
            }
            left[i] = sample
            right[i] = sample
        }
        self.chirpPCMBuffer = buffer
    }

    private func maximizeVolume() {
        var defaultOutputDeviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultOutputDeviceID) == noErr else { return }

        var volAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var currentVol: Float32 = 0.0
        var volSize = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(defaultOutputDeviceID, &volAddress, 0, nil, &volSize, &currentVol) == noErr {
            if savedVolume == nil {
                savedVolume = currentVol
            }
        }

        var maxVol: Float32 = 1.0
        AudioObjectSetPropertyData(defaultOutputDeviceID, &volAddress, 0, nil, volSize, &maxVol)
    }

    private func restoreVolume() {
        guard let saved = savedVolume else { return }
        savedVolume = nil

        var defaultOutputDeviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultOutputDeviceID) == noErr else { return }

        var volAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vol = saved
        let volSize = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(defaultOutputDeviceID, &volAddress, 0, nil, volSize, &vol)
    }

    private func setupEngine() {
        if engine != nil { return }
        let eng = AVAudioEngine()
        let lp = AVAudioPlayerNode()
        let rp = AVAudioPlayerNode()
        eng.attach(lp)
        eng.attach(rp)

        eng.connect(lp, to: eng.mainMixerNode, format: nil)
        eng.connect(rp, to: eng.mainMixerNode, format: nil)

        lp.pan = -1.0 // 100% Left bud only
        rp.pan = 1.0  // 100% Right bud only
        lp.volume = 1.0
        rp.volume = 1.0
        eng.mainMixerNode.outputVolume = 1.0

        self.engine = eng
        self.leftPlayer = lp
        self.rightPlayer = rp
    }

    func ring(left: Bool, start: Bool, deviceName: String?) {
        if start {
            maximizeVolume()
            setupEngine()
            guard let eng = engine, let lp = leftPlayer, let rp = rightPlayer, let buf = chirpPCMBuffer else { return }

            if !eng.isRunning {
                do {
                    try eng.start()
                    connectionLog.info("BudRinger engine started on default audio output")
                } catch {
                    connectionLog.error("BudRinger engine start failed: \(error.localizedDescription)")
                    return
                }
            }

            if left {
                isRingingLeft = true
                lp.stop()
                lp.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
                lp.play()
                connectionLog.info("BudRinger started ringing Left bud at maximum volume")
            } else {
                isRingingRight = true
                rp.stop()
                rp.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
                rp.play()
                connectionLog.info("BudRinger started ringing Right bud at maximum volume")
            }

            // Auto-stop after 30 seconds
            stopTimer?.invalidate()
            stopTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.stopAll()
                }
            }
        } else {
            if left {
                isRingingLeft = false
                leftPlayer?.stop()
                connectionLog.info("BudRinger stopped ringing Left bud")
            } else {
                isRingingRight = false
                rightPlayer?.stop()
                connectionLog.info("BudRinger stopped ringing Right bud")
            }

            if !isRingingLeft && !isRingingRight {
                stopAll()
            }
        }
    }

    func stopAll() {
        stopTimer?.invalidate()
        stopTimer = nil
        isRingingLeft = false
        isRingingRight = false
        leftPlayer?.stop()
        rightPlayer?.stop()
        engine?.stop()
        engine = nil
        leftPlayer = nil
        rightPlayer = nil
        restoreVolume()
    }
}
