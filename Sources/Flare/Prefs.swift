import AppKit

/// Every user-visible setting. Backed by UserDefaults; no other persistence exists.
enum Prefs {
    static let didChange = Notification.Name("FlarePrefsDidChange")

    enum Key {
        static let port = "port"
        static let reminderInterval = "reminderInterval"
        static let flashColor = "flashColor"
        static let peakOpacity = "peakOpacity"
        static let menuBarBadge = "menuBarBadge"
        static let quietWhenFrontmost = "quietWhenFrontmost"
        static let autoCheckUpdates = "autoCheckUpdates"
        static let lastUpdateCheck = "lastUpdateCheck"
    }

    static let defaultPort = 4242
    static let defaultReminderInterval = 120.0
    static let minReminderInterval = 30.0
    static let maxReminderInterval = 3600.0
    static let defaultColorHex = "#FF4500"
    static let defaultPeakOpacity = 0.20

    /// What the menu bar icon shows while agents are waiting.
    enum MenuBarBadge: String, CaseIterable, Identifiable {
        case count, dot

        var id: String { rawValue }
        var label: String {
            switch self {
            case .count: "Number"
            case .dot: "Dot"
            }
        }
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.port: defaultPort,
            Key.reminderInterval: defaultReminderInterval,
            Key.flashColor: defaultColorHex,
            Key.peakOpacity: defaultPeakOpacity,
            Key.menuBarBadge: MenuBarBadge.count.rawValue,
            Key.quietWhenFrontmost: true,
            Key.autoCheckUpdates: true,
        ])
    }

    static var port: Int {
        get { clampPort(UserDefaults.standard.integer(forKey: Key.port)) }
        set { set(Key.port, clampPort(newValue)) }
    }

    /// Seconds between nag flashes. Floored at 30s so Flare can never strobe.
    static var reminderInterval: TimeInterval {
        get {
            let v = UserDefaults.standard.double(forKey: Key.reminderInterval)
            return min(max(v, minReminderInterval), maxReminderInterval)
        }
        set { set(Key.reminderInterval, min(max(newValue, minReminderInterval), maxReminderInterval)) }
    }

    static var peakOpacity: Double {
        get { min(max(UserDefaults.standard.double(forKey: Key.peakOpacity), 0.05), 1.0) }
        set { set(Key.peakOpacity, min(max(newValue, 0.05), 1.0)) }
    }

    /// Unknown values fall back to the count rather than showing nothing — a
    /// badge that silently disappears is worse than one in the wrong style.
    static var menuBarBadge: MenuBarBadge {
        get {
            let raw = UserDefaults.standard.string(forKey: Key.menuBarBadge) ?? ""
            return MenuBarBadge(rawValue: raw) ?? .count
        }
        set { set(Key.menuBarBadge, newValue.rawValue) }
    }

    static var flashColorHex: String {
        get { UserDefaults.standard.string(forKey: Key.flashColor) ?? defaultColorHex }
        set { set(Key.flashColor, newValue) }
    }

    static var flashColor: NSColor {
        get { NSColor(hex: flashColorHex) ?? NSColor(hex: defaultColorHex)! }
        set { flashColorHex = newValue.hexString }
    }

    /// Skip the flash while the only agents waiting are in the app already in
    /// front of you. Off by default would mean flashing at someone who is
    /// demonstrably reading the question.
    static var quietWhenFrontmost: Bool {
        get { UserDefaults.standard.bool(forKey: Key.quietWhenFrontmost) }
        set { set(Key.quietWhenFrontmost, newValue) }
    }

    /// The one setting that lets Flare talk to anything beyond 127.0.0.1.
    static var autoCheckUpdates: Bool {
        get { UserDefaults.standard.bool(forKey: Key.autoCheckUpdates) }
        set { set(Key.autoCheckUpdates, newValue) }
    }

    /// Written on every check, so it deliberately does not post didChange —
    /// nothing needs to restart the listener because a version was fetched.
    static var lastUpdateCheck: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: Key.lastUpdateCheck)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0,
                                      forKey: Key.lastUpdateCheck)
        }
    }

    private static func clampPort(_ p: Int) -> Int {
        (1024...65535).contains(p) ? p : defaultPort
    }

    private static func set(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

extension NSColor {
    /// Parses "#RRGGBB" / "RRGGBB". Returns nil on anything else.
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255,
                  alpha: 1)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
