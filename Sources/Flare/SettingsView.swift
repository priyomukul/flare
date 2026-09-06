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
    @State private var launchAtLogin: Bool = LoginItem.isEnabled
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
        .frame(width: 460, height: 540)
        .onReceive(NotificationCenter.default.publisher(for: HTTPListener.stateChanged)) { _ in
            listenerStatus = HTTPListener.shared.status
        }
        .onAppear {
            listenerStatus = HTTPListener.shared.status
            launchAtLogin = LoginItem.isEnabled
        }
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
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: hosting)
            w.title = "Flare Settings"
            w.styleMask = [.titled, .closable]
            w.setContentSize(NSSize(width: 460, height: 540))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
