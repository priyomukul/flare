import Foundation

/// Whether Flare is allowed to flash. Signals are still recorded while paused.
/// Main-queue only.
final class PauseController {
    static let shared = PauseController()
    static let didChange = Notification.Name("FlarePauseDidChange")

    private(set) var until: Date?
    private(set) var isIndefinite = false

    private init() {}

    var isPaused: Bool {
        if isIndefinite { return true }
        if let until, until > Date() { return true }
        return false
    }

    var summary: String? {
        if isIndefinite { return "Paused until resumed" }
        guard let until, until > Date() else { return nil }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return "Paused until \(f.string(from: until))"
    }

    func pause(for interval: TimeInterval) {
        isIndefinite = false
        until = Date().addingTimeInterval(interval)
        announce()
    }

    func pauseUntilResumed() {
        isIndefinite = true
        until = nil
        announce()
    }

    func resume() {
        isIndefinite = false
        until = nil
        announce()
    }

    /// Clears a timed pause that has run out. Returns true if state changed.
    @discardableResult
    func expireIfNeeded() -> Bool {
        guard !isIndefinite, let until, until <= Date() else { return false }
        self.until = nil
        announce()
        return true
    }

    private func announce() {
        NotificationCenter.default.post(name: PauseController.didChange, object: nil)
    }
}
