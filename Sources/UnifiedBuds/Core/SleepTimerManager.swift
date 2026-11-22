import AppKit
import Foundation
import os

/// Manages a sleep timer that automatically pauses all media playback on macOS
/// (Music, Spotify, Safari, YouTube, QuickTime, system audio) when the countdown finishes.
@MainActor
final class SleepTimerManager: ObservableObject {
    static let shared = SleepTimerManager()

    @Published private(set) var isActive = false
    @Published private(set) var timeRemaining: TimeInterval = 0
    @Published private(set) var totalDuration: TimeInterval = 0

    private var timer: Timer?

    private init() {}

    /// Formatted remaining time string like "24:15" or "10m"
    var formattedRemaining: String {
        guard isActive else { return "" }
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Starts a sleep timer for the specified minutes.
    func start(minutes: Int) {
        guard minutes > 0 else { return }
        cancel()
        totalDuration = TimeInterval(minutes * 60)
        timeRemaining = totalDuration
        isActive = true

        connectionLog.info("Sleep timer started: \(minutes) minutes")

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.timeRemaining > 1 {
                    self.timeRemaining -= 1
                } else {
                    self.timerFinished()
                }
            }
        }
    }

    /// Cancels any currently running sleep timer.
    func cancel() {
        timer?.invalidate()
        timer = nil
        isActive = false
        timeRemaining = 0
        totalDuration = 0
    }

    private func timerFinished() {
        cancel()
        connectionLog.info("Sleep timer expired — pausing all macOS audio/media playback")
        pauseAllMedia()

        // Post a system notification
        NotificationManager.shared.postSleepTimerFinished()
    }

    /// Pauses all media playback across major macOS players and system media keys.
    func pauseAllMedia() {
        // 1. Direct AppleScript targeting popular macOS audio/video players
        let script = """
        if application "Music" is running then
            tell application "Music" to pause
        end if
        if application "Spotify" is running then
            tell application "Spotify" to pause
        end if
        if application "QuickTime Player" is running then
            tell application "QuickTime Player" to pause
        end if
        if application "TV" is running then
            tell application "TV" to pause
        end if
        if application "Podcasts" is running then
            tell application "Podcasts" to pause
        end if
        """
        if let appleScript = NSAppleScript(source: script) {
            var errorInfo: NSDictionary?
            appleScript.executeAndReturnError(&errorInfo)
        }

        // 2. Synthesize system-wide Media Play/Pause key event (NX_KEYTYPE_PLAY = 16)
        func postMediaKey(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = Int((16 << 16) | ((down ? 0xa : 0xb) << 8))
            let ev = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            if let cgEv = ev?.cgEvent {
                cgEv.post(tap: .cghidEventTap)
            }
        }

        postMediaKey(down: true)
        postMediaKey(down: false)
    }
}
