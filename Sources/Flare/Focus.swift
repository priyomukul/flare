import AppKit

/// Where a waiting signal came from, as far as the hook could tell us. Every
/// field is optional: a plain `curl` integration sends none of them, and even a
/// hook only sees what its terminal exported.
struct Origin: Equatable {
    /// `$TERM_PROGRAM` — `Apple_Terminal`, `iTerm.app`, `vscode`, `ghostty`…
    var termProgram: String?
    /// `$__CFBundleIdentifier`, set by LaunchServices for anything opened from
    /// Finder or the Dock. More reliable than guessing from `termProgram`.
    var bundleID: String?
    /// The UUID half of `$ITERM_SESSION_ID`, which is iTerm2's session id.
    var itermSession: String?
    /// `/dev/ttysNNN` of the shell that ran the hook. Terminal.app exposes the
    /// same string per tab, which is what makes an exact match possible.
    var tty: String?

    var isEmpty: Bool { self == Origin() }

    init(termProgram: String? = nil, bundleID: String? = nil,
         itermSession: String? = nil, tty: String? = nil) {
        self.termProgram = termProgram
        self.bundleID = bundleID
        self.itermSession = itermSession
        self.tty = tty
    }

    init(headers: [String: String]) {
        self.init(termProgram: Self.clean(headers["x-flare-term"]),
                  bundleID: Self.clean(headers["x-flare-app"]),
                  itermSession: Self.itermID(Self.clean(headers["x-flare-iterm"])),
                  tty: Self.device(Self.clean(headers["x-flare-tty"])))
    }

    private static func clean(_ value: String?) -> String? {
        let t = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    /// `w0t1p0:5B8F…` — only the part after the colon identifies the session.
    private static func itermID(_ value: String?) -> String? {
        guard let value else { return nil }
        guard let colon = value.lastIndex(of: ":") else { return value }
        let id = String(value[value.index(after: colon)...])
        return id.isEmpty ? nil : id
    }

    /// `ps -o tty=` prints `ttys004`; Terminal.app reports `/dev/ttys004`. A
    /// shell with no controlling terminal prints `??`, which identifies nothing.
    private static func device(_ value: String?) -> String? {
        guard let value, value != "??", !value.hasPrefix("?") else { return nil }
        return value.hasPrefix("/dev/") ? value : "/dev/" + value
    }

    /// Best guess at the app to raise when no exact tab can be found.
    var appBundleID: String? {
        if let bundleID { return bundleID }
        guard let termProgram else { return nil }
        return Self.knownTerminals[termProgram.lowercased()]
    }

    private static let knownTerminals = [
        "apple_terminal": "com.apple.Terminal",
        "iterm.app": "com.googlecode.iterm2",
        "vscode": "com.microsoft.VSCode",
        "ghostty": "com.mitchellh.ghostty",
        "warpterminal": "dev.warp.Warp-Stable",
        "wezterm": "com.github.wez.wezterm",
        "alacritty": "org.alacritty",
        "hyper": "co.zeit.hyper",
        "tabby": "org.tabby",
        "kitty": "net.kovidgoyal.kitty",
        "rio": "com.raphaelamorim.rio",
    ]
}

/// Raises the terminal an agent is waiting in.
///
/// Two apps can be told which tab: iTerm2, which gives every session a stable
/// id, and Terminal.app, which exposes each tab's tty. Everything else gets its
/// window raised and no more, because no other terminal we know of can be asked
/// where a given tty is. Both scripted paths fall back to plain activation, so
/// a refused Automation prompt still gets you to the right app.
enum Focus {
    /// AppleScript can block on an unresponsive app, so it never runs on the
    /// main thread — the menu must close immediately either way.
    private static let queue = DispatchQueue(label: "com.priyomukul.flare.focus")

    static func go(to origin: Origin) {
        guard !origin.isEmpty else { return }

        if let session = origin.itermSession {
            run(script: itermScript(session: session), fallback: origin)
            return
        }
        if let tty = origin.tty, origin.appBundleID == "com.apple.Terminal" {
            run(script: terminalScript(tty: tty), fallback: origin)
            return
        }
        activate(origin)
    }

    private static func activate(_ origin: Origin) {
        guard let id = origin.appBundleID else { return }
        DispatchQueue.main.async {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            if let app = running.first {
                app.activate(options: [.activateAllWindows])
                return
            }
            // Not running: nothing to raise, and launching a terminal would not
            // bring back the session anyway. Only VS Code-style editors survive
            // a relaunch, and even then not the agent.
        }
    }

    private static func run(script: String, fallback origin: Origin) {
        queue.async {
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            // No permission, app not running, or a tab that has since closed.
            if error != nil { activate(origin) }
        }
    }

    private static func itermScript(session: String) -> String {
        """
        tell application id "com.googlecode.iterm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if id of s is "\(escaped(session))" then
                            select w
                            select t
                            select s
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end repeat
            activate
        end tell
        """
    }

    private static func terminalScript(tty: String) -> String {
        """
        tell application id "com.apple.Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(escaped(tty))" then
                        set selected of t to true
                        set frontmost of w to true
                        activate
                        return
                    end if
                end repeat
            end repeat
            activate
        end tell
        """
    }

    /// The values come off the wire, so they are quoted into the script rather
    /// than trusted. Neither a session id nor a tty can legitimately contain a
    /// quote or a backslash.
    private static func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
