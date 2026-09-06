import Foundation

struct WaitingAgent {
    let id: String
    /// Name as supplied (simple payload) or derived from `cwd` (hook payload).
    var baseName: String
    /// `baseName`, plus a session-id suffix when two agents share a base name.
    var displayName: String
    var note: String?
    var since: Date

    var waitingSeconds: Int { max(0, Int(Date().timeIntervalSince(since).rounded())) }
}

/// The set of agents currently waiting on me. Lock-protected so the HTTP
/// listener can read and write from its own queue and answer immediately;
/// UI observers are notified on the main queue.
final class AgentStore {
    static let shared = AgentStore()
    static let didChange = Notification.Name("FlareAgentStoreDidChange")

    private let lock = NSLock()
    private var storage: [String: WaitingAgent] = [:]

    private init() {}

    var all: [WaitingAgent] {
        lock.withLock { storage.values.sorted { ($0.since, $0.displayName) < ($1.since, $1.displayName) } }
    }

    var count: Int { lock.withLock { storage.count } }
    var isEmpty: Bool { count == 0 }

    /// Create or refresh an agent. `since` is preserved across refreshes so the
    /// menu shows how long I have actually been keeping it waiting.
    func upsert(id: String, name: String, note: String?) {
        lock.withLock {
            if var existing = storage[id] {
                existing.baseName = name
                existing.note = note
                storage[id] = existing
            } else {
                storage[id] = WaitingAgent(id: id, baseName: name, displayName: name,
                                           note: note, since: Date())
            }
            disambiguateLocked()
        }
        notify()
    }

    func remove(id: String) {
        let removed: Bool = lock.withLock {
            guard storage.removeValue(forKey: id) != nil else { return false }
            disambiguateLocked()
            return true
        }
        if removed { notify() }
    }

    func removeAll() {
        let had: Bool = lock.withLock {
            guard !storage.isEmpty else { return false }
            storage.removeAll()
            return true
        }
        if had { notify() }
    }

    /// `Flare · 2 waiting · api-server, web`
    func summaryLabel() -> String {
        let agents = all
        guard !agents.isEmpty else { return "Flare · nothing waiting" }
        let names = agents.map(\.displayName)
        let shown = names.prefix(3).joined(separator: ", ")
        let extra = names.count > 3 ? " +\(names.count - 3) more" : ""
        return "Flare · \(agents.count) waiting · \(shown)\(extra)"
    }

    /// Two sessions in identically-named directories get the first 4 characters
    /// of their session id appended.
    private func disambiguateLocked() {
        var byName: [String: [String]] = [:]
        for (id, a) in storage { byName[a.baseName, default: []].append(id) }
        for (name, ids) in byName {
            let ambiguous = ids.count > 1
            for id in ids {
                guard var a = storage[id] else { continue }
                // A simple payload's id *is* its name, so "web (web)" would add
                // nothing — only hook payloads get a session-id suffix.
                a.displayName = ambiguous && a.id != name ? "\(name) (\(a.id.prefix(4)))" : name
                storage[id] = a
            }
        }
    }

    private func notify() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: AgentStore.didChange, object: nil)
        }
    }
}
