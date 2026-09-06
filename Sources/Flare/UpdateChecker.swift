import AppKit

/// Asks GitHub whether a newer release exists. It never downloads or installs
/// anything — the most it does is open the release page, or hand you the
/// Homebrew command when this copy is managed by a cask.
///
/// This is the only part of Flare that talks to anything beyond 127.0.0.1, and
/// it can be turned off in Settings.
final class UpdateChecker {
    static let shared = UpdateChecker()
    static let didChange = Notification.Name("FlareUpdateCheckerDidChange")

    /// How stale a check has to be before the hourly tick runs another one.
    static let checkInterval: TimeInterval = 24 * 60 * 60
    private static let endpoint = URL(string: "https://api.github.com/repos/priyomukul/flare/releases/latest")!
    private static let releasesPage = URL(string: "https://github.com/priyomukul/flare/releases/latest")!

    enum State {
        case idle
        case checking
        case upToDate
        case available(version: String, page: URL)
        case failed(String)
    }

    /// Main-queue only.
    private(set) var state: State = .idle
    private var timer: Timer?
    private var inFlight: URLSessionDataTask?

    private init() {}

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// A cask-managed copy should be updated through Homebrew, not by hand.
    lazy var isHomebrewManaged: Bool = {
        ["/opt/homebrew/Caskroom/flare", "/usr/local/Caskroom/flare"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }()

    var homebrewCommand: String { "brew upgrade --cask flare" }

    // MARK: - Scheduling

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        // Hourly rather than daily: a Mac that sleeps through a 24h timer would
        // never fire it, and comparing elapsed time survives sleep.
        let timer = Timer(timeInterval: 3600, target: self, selector: #selector(tick),
                          userInfo: nil, repeats: true)
        timer.tolerance = 300
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // Give launch a moment to settle before touching the network.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.tick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        inFlight?.cancel()
        inFlight = nil
    }

    @objc private func tick() {
        guard Prefs.autoCheckUpdates else { return }
        let last = Prefs.lastUpdateCheck ?? .distantPast
        guard Date().timeIntervalSince(last) >= Self.checkInterval else { return }
        check()
    }

    // MARK: - Checking

    func check() {
        dispatchPrecondition(condition: .onQueue(.main))
        if case .checking = state { return }
        state = .checking
        announce()

        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Flare/\(currentVersion) (macOS; +https://github.com/priyomukul/flare)",
                         forHTTPHeaderField: "User-Agent")

        inFlight?.cancel()
        inFlight = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { self?.finish(data: data, response: response, error: error) }
        }
        inFlight?.resume()
    }

    private func finish(data: Data?, response: URLResponse?, error: Error?) {
        inFlight = nil
        Prefs.lastUpdateCheck = Date()

        if let error {
            // A cancelled request is us replacing it, not a failure worth showing.
            if (error as NSError).code == NSURLErrorCancelled { return }
            state = .failed(error.localizedDescription)
            announce()
            return
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            state = .failed(http.statusCode == 403
                            ? "GitHub rate limit reached — try again later"
                            : "GitHub returned \(http.statusCode)")
            announce()
            return
        }
        guard let data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = json["tag_name"] as? String
        else {
            state = .failed("Could not read GitHub's answer")
            announce()
            return
        }

        let latest = Self.normalise(tag)
        if Self.isNewer(latest, than: currentVersion) {
            let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? Self.releasesPage
            state = .available(version: latest, page: page)
        } else {
            state = .upToDate
        }
        announce()
    }

    /// Open the release page, or put the Homebrew command on the pasteboard when
    /// that is the right way to update this copy.
    func act() {
        guard case .available(_, let page) = state else { return }
        if isHomebrewManaged {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(homebrewCommand, forType: .string)
        }
        NSWorkspace.shared.open(page)
    }

    // MARK: - Versions

    static func normalise(_ tag: String) -> String {
        var t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.first == "v" || t.first == "V" { t.removeFirst() }
        return t
    }

    /// Numeric component comparison. Anything non-numeric in a component is
    /// ignored, so "1.2.0-beta" reads as 1.2.0 — GitHub's `releases/latest`
    /// already excludes prereleases.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        guard !a.isEmpty else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        normalise(version).split(separator: ".").map { part in
            Int(part.prefix { $0.isNumber }) ?? 0
        }
    }

    private func announce() {
        NotificationCenter.default.post(name: UpdateChecker.didChange, object: nil)
    }
}
