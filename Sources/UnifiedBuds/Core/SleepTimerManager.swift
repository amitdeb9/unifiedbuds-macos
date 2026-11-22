import AppKit
import Foundation
import os

/// Manages a sleep timer that automatically pauses all media playback on macOS
/// (Music, Spotify, Chrome, YouTube, QuickTime, system audio) when the countdown finishes.
///
/// Designed to withstand macOS App Nap, fullscreen video playback in Chrome, and
/// popover window lifecycle changes.
@MainActor
final class SleepTimerManager: ObservableObject {
    static let shared = SleepTimerManager()

    @Published private(set) var isActive = false
    @Published private(set) var timeRemaining: TimeInterval = 0
    @Published private(set) var totalDuration: TimeInterval = 0
    @Published private(set) var targetEndDate: Date?

    private var dispatchTimer: DispatchSourceTimer?
    private var activityAssertion: (any NSObjectProtocol)?

    private init() {}

    /// Formatted remaining time string like "24:15" or "00:05"
    var formattedRemaining: String {
        guard isActive else { return "" }
        let totalSeconds = max(0, Int(timeRemaining.rounded(.up)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Starts a sleep timer for the specified minutes.
    func start(minutes: Int) {
        guard minutes > 0 else { return }
        cancel()

        let duration = TimeInterval(minutes * 60)
        let endDate = Date().addingTimeInterval(duration)
        self.targetEndDate = endDate
        self.totalDuration = duration
        self.timeRemaining = duration
        self.isActive = true

        connectionLog.info("Sleep timer started: \(minutes) minutes (until \(endDate))")

        // 1. Prevent macOS App Nap from throttling or freezing the timer when Chrome or other apps are fullscreen
        activityAssertion = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Active UnifiedBuds timer"
        )

        // 2. DispatchSourceTimer fires on the main queue with high accuracy, independent of run loop modes
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, let target = self.targetEndDate else { return }
                let remaining = target.timeIntervalSinceNow
                if remaining <= 0 {
                    self.timeRemaining = 0
                    self.timerFinished()
                } else {
                    self.timeRemaining = remaining
                }
            }
        }
        timer.resume()
        self.dispatchTimer = timer
    }

    /// Cancels any currently running sleep timer and releases system activity assertions.
    func cancel() {
        if let timer = dispatchTimer {
            timer.cancel()
            dispatchTimer = nil
        }

        if let assertion = activityAssertion {
            ProcessInfo.processInfo.endActivity(assertion)
            activityAssertion = nil
        }

        isActive = false
        targetEndDate = nil
        timeRemaining = 0
        totalDuration = 0
    }

    private func timerFinished() {
        connectionLog.info("Sleep timer expired — pausing all macOS audio/media playback")
        cancel()

        // Reliable universal media pause
        pauseAllMedia()

        // Post a native system notification
        NotificationManager.shared.postSleepTimerFinished()
    }

    /// Pauses all media playback across major macOS players and system media keys.
    func pauseAllMedia() {
        // 1. Direct AppleScript targeting popular native/third-party macOS audio/video players
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
        // This reliably pauses YouTube, Netflix, Twitch, etc. in Chrome, Safari, and other browsers
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
