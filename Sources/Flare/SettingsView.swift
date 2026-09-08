import AppKit
import ServiceManagement
import SwiftUI

/// The only SwiftUI in Flare. Everything it writes goes straight to UserDefaults
/// via Prefs, which posts Prefs.didChange so the listener and timers pick it up.
struct SettingsView: View {
    @State private var port: Int = Prefs.port
    @State private var portText: String = String(Prefs.port)
    @State private var reminderInterval: Double = Prefs.reminderInterval
    @State private var color: Color = Color(nsColor: Prefs.flashColor)
    @State private var peakOpacity: Double = Prefs.peakOpacity
    @State private var menuBarBadge: Prefs.MenuBarBadge = Prefs.menuBarBadge
    @State private var launchAtLogin: Bool = LoginItem.isEnabled
    @State private var autoCheckUpdates: Bool = Prefs.autoCheckUpdates
    @State private var updateStatus: String = ""
    @State private var updateIsError = false
    @State private var updateAvailable = false
    @State private var loginError: String?
    @State private var listenerStatus: String = HTTPListener.shared.status

    var body: some View {
        Form {
            Section {
                LabeledContent("Port") {
                    HStack(spacing: 8) {
                        TextField("", text: $portText)
                            .frame(width: 80)
                            .onSubmit(commitPort)
                        Button("Apply", action: commitPort)
                    }
                }
                LabeledContent("Listener") {
                    Text(listenerStatus)
                        .font(.callout)
                        .foregroundStyle(HTTPListener.shared.isHealthy ? .secondary : Color.red)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Signals")
            } footer: {
                Text("Flare listens on 127.0.0.1 only. Changing the port rewrites the hooks snippet in the menu — repaste it into ~/.claude/settings.json.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Nagging") {
                LabeledContent("Remind every") {
                    HStack(spacing: 10) {
                        Slider(value: $reminderInterval,
                               in: Prefs.minReminderInterval...600, step: 10)
                            .frame(width: 180)
                        Text(Self.intervalLabel(reminderInterval))
                            .monospacedDigit()
                            .frame(width: 64, alignment: .leading)
                    }
                }
                .onChange(of: reminderInterval) { _, new in Prefs.reminderInterval = new }
            }

            Section("Flash") {
                ColorPicker("Colour", selection: $color, supportsOpacity: false)
                    .onChange(of: color) { _, new in
                        if let ns = NSColor(new).usingColorSpace(.sRGB) { Prefs.flashColor = ns }
                    }
                LabeledContent("Peak opacity") {
                    HStack(spacing: 10) {
                        Slider(value: $peakOpacity, in: 0.05...1.0, step: 0.05)
                            .frame(width: 180)
                        Text("\(Int((peakOpacity * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 64, alignment: .leading)
                    }
                }
                .onChange(of: peakOpacity) { _, new in Prefs.peakOpacity = new }
            }

            Section {
                Picker("While agents are waiting", selection: $menuBarBadge) {
                    ForEach(Prefs.MenuBarBadge.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: menuBarBadge) { _, new in Prefs.menuBarBadge = new }
            } header: {
                Text("Menu bar")
            } footer: {
                Text("The number tells you how many agents are waiting; the dot, in the flash colour, only tells you that some are. Either way the menu and the tooltip list them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version") {
                    Text(UpdateChecker.shared.currentVersion)
                        .foregroundStyle(.secondary)
                }
                Toggle("Check for updates automatically", isOn: $autoCheckUpdates)
                    .onChange(of: autoCheckUpdates) { _, on in Prefs.autoCheckUpdates = on }
                LabeledContent("Status") {
                    HStack(spacing: 10) {
                        Text(updateStatus)
                            .font(.callout)
                            .foregroundStyle(updateIsError ? Color.red : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if updateAvailable {
                            Button("Get it") { UpdateChecker.shared.act() }
                        } else {
                            Button("Check Now") { UpdateChecker.shared.check() }
                        }
                    }
                }
                if UpdateChecker.shared.isHomebrewManaged {
                    Text("Installed with Homebrew — update with `\(UpdateChecker.shared.homebrewCommand)`.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("The only thing Flare sends beyond 127.0.0.1: a version check against GitHub, once a day. It never downloads or installs anything on its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, want in
                        loginError = LoginItem.set(enabled: want)
                        launchAtLogin = LoginItem.isEnabled
                    }
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 620)
        .onReceive(NotificationCenter.default.publisher(for: HTTPListener.stateChanged)) { _ in
            listenerStatus = HTTPListener.shared.status
        }
        .onReceive(NotificationCenter.default.publisher(for: UpdateChecker.didChange)) { _ in
            refreshUpdateStatus()
        }
        .onAppear {
            listenerStatus = HTTPListener.shared.status
            launchAtLogin = LoginItem.isEnabled
            autoCheckUpdates = Prefs.autoCheckUpdates
            refreshUpdateStatus()
        }
    }

    private func refreshUpdateStatus() {
        switch UpdateChecker.shared.state {
        case .idle:
            updateStatus = Self.lastCheckedLabel()
            updateIsError = false
            updateAvailable = false
        case .checking:
            updateStatus = "Checking…"
            updateIsError = false
            updateAvailable = false
        case .upToDate:
            updateStatus = "Up to date. \(Self.lastCheckedLabel())"
            updateIsError = false
            updateAvailable = false
        case .available(let version, _):
            updateStatus = "Version \(version) is available."
            updateIsError = false
            updateAvailable = true
        case .failed(let reason):
            updateStatus = reason
            updateIsError = true
            updateAvailable = false
        }
    }

    static func lastCheckedLabel() -> String {
        guard let last = Prefs.lastUpdateCheck else { return "Not checked yet." }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return "Checked \(f.localizedString(for: last, relativeTo: Date()))."
    }

    private func commitPort() {
        guard let value = Int(portText.trimmingCharacters(in: .whitespaces)),
              (1024...65535).contains(value) else {
            portText = String(Prefs.port)
            return
        }
        port = value
        Prefs.port = value
        portText = String(Prefs.port)
    }

    static func intervalLabel(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        let m = s / 60, r = s % 60
        return r == 0 ? "\(m)m" : "\(m)m \(r)s"
    }
}

/// SMAppService wrapper. Registration needs a real, signed bundle — ad-hoc is
/// fine, but the app must be somewhere stable (see `make install`).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns a message to show the user, or nil on success.
    static func set(enabled: Bool) -> String? {
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundlePath.hasSuffix(".app") else {
            return "Launch at login needs the bundled app — build with `make app` and launch Flare.app."
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
                if Bundle.main.bundlePath.contains("/dist/") {
                    return "Registered — but this copy lives in the build tree, and `make clean` "
                        + "would leave a login item pointing at nothing. Run `make install` and "
                        + "enable it from /Applications instead."
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "Could not \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)"
        }
    }
}

/// Plain NSWindow hosting the SwiftUI form. The app is an accessory, so it has
/// to activate itself to bring the window forward.
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        // A fresh view every time. Reopening a cached NSHostingController does
        // not fire onAppear again, so the launch-at-login state, the listener
        // status and "Checked N ago" would all be whatever they were when the
        // window was first built.
        let hosting = NSHostingController(rootView: SettingsView())
        if let window {
            window.contentViewController = hosting
            window.setContentSize(NSSize(width: 460, height: 700))
        } else {
            let w = NSWindow(contentViewController: hosting)
            w.title = "Flare Settings"
            w.styleMask = [.titled, .closable]
            w.setContentSize(NSSize(width: 460, height: 700))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
