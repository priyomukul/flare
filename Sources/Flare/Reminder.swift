import AppKit
import CoreGraphics

/// Two nags, both on the main queue:
///   1. a free-running timer that re-flashes while anything is still waiting
///   2. a 5s tick that notices when I come back to the desk after being away
final class Reminder {
    static let shared = Reminder()

    /// Idle time that counts as "away from the desk".
    static let awayThreshold: TimeInterval = 5 * 60
    static let tickInterval: TimeInterval = 5

    /// 0xFFFFFFFF is kCGEventTapDisabledByUserInput, which CGEventSource treats
    /// as "any input event" — the documented way to ask for overall idle time.
    private static let anyInput = CGEventType(rawValue: ~0) ?? .null

    /// Called when Flare should flash. The caller decides what the label says.
    var onFlash: (() -> Void)?

    private var reminderTimer: Timer?
    private var tickTimer: Timer?
    private var wasAway = false
    private var lastIdle: TimeInterval = 0

    private init() {}

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        lastIdle = currentIdle()
        wasAway = lastIdle >= Self.awayThreshold
        scheduleReminder()
        scheduleTick()
        NotificationCenter.default.addObserver(
            self, selector: #selector(prefsChanged), name: Prefs.didChange, object: nil)
    }

    func stop() {
        reminderTimer?.invalidate()
        reminderTimer = nil
        tickTimer?.invalidate()
        tickTimer = nil
    }

    @objc private func prefsChanged() {
        guard let timer = reminderTimer, timer.timeInterval != Prefs.reminderInterval else { return }
        scheduleReminder()
    }

    // MARK: - Timers

    private func scheduleReminder() {
        reminderTimer?.invalidate()
        let interval = Prefs.reminderInterval
        let timer = Timer(timeInterval: interval, target: self,
                          selector: #selector(reminderFired), userInfo: nil, repeats: true)
        timer.tolerance = min(5, interval / 10)
        // .common so it keeps firing while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        reminderTimer = timer
    }

    private func scheduleTick() {
        tickTimer?.invalidate()
        let timer = Timer(timeInterval: Self.tickInterval, target: self,
                          selector: #selector(tick), userInfo: nil, repeats: true)
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    @objc private func reminderFired() {
        guard !PauseController.shared.isPaused, !AgentStore.shared.isEmpty else { return }
        onFlash?()
    }

    @objc private func tick() {
        // A timed pause that has run out behaves like Resume.
        if PauseController.shared.expireIfNeeded(), !AgentStore.shared.isEmpty {
            onFlash?()
            lastIdle = currentIdle()
            return
        }

        let idle = currentIdle()
        defer { lastIdle = idle }

        if idle >= Self.awayThreshold {
            wasAway = true
            return
        }
        guard wasAway, idle < lastIdle else { return }
        wasAway = false
        guard !PauseController.shared.isPaused, !AgentStore.shared.isEmpty else { return }
        onFlash?()
    }

    private func currentIdle() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInput)
    }
}
