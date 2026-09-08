import AppKit
import ServiceManagement
import SwiftUI

/// The shape every pane is built from: a small heading, a white rounded card of
/// rows, and any explanation as prose underneath the card rather than inside
/// it. Colours are semantic rather than the design's literal greys, so the same
/// layout is right in dark mode, and controls take the system accent rather
/// than a tint of Flare's own.
enum SettingsMetrics {
    static let paneWidth: CGFloat = 715
    static let rowHeight: CGFloat = 42
    static let cardPadding: CGFloat = 14
    static let cardRadius: CGFloat = 8
    /// The design indents the heading and the notes to sit just inside the
    /// card's own text, not flush with its edge.
    static let gutter: CGFloat = 10
    /// #1e9d4b — a working listener is good news, not brand news.
    static let good = Color(red: 0.118, green: 0.616, blue: 0.294)
    /// #171615 — the strip that stands in for your screen and your menu bar.
    static let screen = Color(red: 0.09, green: 0.086, blue: 0.082)
}

/// A heading, a card, and the prose that belongs to it.
struct SettingsGroup<Content: View>: View {
    let title: String
    var notes: [String] = []
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, SettingsMetrics.gutter)
                .padding(.bottom, 6)

            VStack(spacing: 0) { content }
                .padding(.horizontal, SettingsMetrics.cardPadding)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.05), radius: 1, y: 1)

            ForEach(Array(notes.enumerated()), id: \.offset) { index, note in
                Text(note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SettingsMetrics.gutter)
                    .padding(.top, index == 0 ? 6 : 5)
            }
        }
    }
}

/// One label-and-control line. The hairline goes below every row but the last,
/// so a card never ends on a rule.
struct SettingsRow<Trailing: View>: View {
    let label: String
    var divided = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text(label)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                trailing
            }
            .padding(.vertical, 7)
            .frame(minHeight: SettingsMetrics.rowHeight)
            if divided { Divider().opacity(0.6) }
        }
    }
}

/// A row that lays itself out — buttons and previews, which the label-and-
/// control shape would push to the wrong edge.
struct SettingsFreeRow<Content: View>: View {
    var divided = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) { content }
                .padding(.vertical, 7)
                .frame(minHeight: SettingsMetrics.rowHeight)
            if divided { Divider().opacity(0.6) }
        }
    }
}

struct Mono: View {
    let text: String
    var size: CGFloat = 11.5
    var body: some View { Text(text).font(.system(size: size, design: .monospaced)) }
}

/// The design's 44×22 colour well: the colour itself, inset inside a white
/// border. `ColorPicker` with its label hidden is the AppKit equivalent and
/// opens the same system picker.
struct ColorWell: View {
    let title: String
    @Binding var color: NSColor

    var body: some View {
        ColorPicker(title, selection: Binding(
            get: { Color(nsColor: color) },
            set: { new in
                if let ns = NSColor(new).usingColorSpace(.sRGB) { color = ns }
            }), supportsOpacity: false)
            .labelsHidden()
            .help(title)
    }
}

// MARK: - General

struct GeneralPane: View {
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var autoCheckUpdates = Prefs.autoCheckUpdates
    @State private var listenerStatus = HTTPListener.shared.status
    @State private var listenerHealthy = HTTPListener.shared.isHealthy
    @State private var update = UpdateSummary.current()

    var body: some View {
        SettingsPane {
            SettingsGroup(title: "Status") {
                SettingsFreeRow(divided: false) {
                    Image(systemName: listenerHealthy ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(listenerHealthy ? SettingsMetrics.good : .red)
                    Text(listenerHealthy
                         ? "Connected — your agents can reach Flare"
                         : "Not listening — agents cannot reach Flare")
                        .font(.system(size: 13))
                    Spacer(minLength: 8)
                    Mono(text: listenerStatus)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            SettingsGroup(
                title: "Startup",
                notes: [loginError
                        ?? "Flare has no Dock icon — it lives in the menu bar and opens this window from there."]
            ) {
                SettingsRow(label: "Launch at Login", divided: false) {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: launchAtLogin) { _, want in
                            loginError = LoginItem.set(enabled: want)
                            launchAtLogin = LoginItem.isEnabled
                        }
                }
            }

            SettingsGroup(title: "Updates", notes: updateNotes) {
                SettingsRow(label: "Version") {
                    HStack(spacing: 8) {
                        Mono(text: "\(UpdateChecker.shared.currentVersion) (\(AboutPane.build))", size: 12)
                        Text(update.versionNote)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                SettingsRow(label: "Check for Updates Automatically") {
                    Toggle("", isOn: $autoCheckUpdates)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: autoCheckUpdates) { _, on in Prefs.autoCheckUpdates = on }
                }
                SettingsFreeRow(divided: false) {
                    if update.available {
                        Button("Get It") { UpdateChecker.shared.act() }
                    } else {
                        Button(update.checking ? "Checking…" : "Check for Updates") {
                            UpdateChecker.shared.check()
                        }
                        .disabled(update.checking)
                    }
                    Spacer(minLength: 8)
                    Text(update.status)
                        .font(.system(size: 11.5))
                        .foregroundStyle(update.isError ? Color.red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: HTTPListener.stateChanged)) { _ in
            listenerStatus = HTTPListener.shared.status
            listenerHealthy = HTTPListener.shared.isHealthy
        }
        .onReceive(NotificationCenter.default.publisher(for: UpdateChecker.didChange)) { _ in
            update = UpdateSummary.current()
        }
    }

    private var updateNotes: [String] {
        var notes: [String] = []
        if UpdateChecker.shared.isHomebrewManaged {
            notes.append("Installed with Homebrew — update with \(UpdateChecker.shared.homebrewCommand)")
        }
        notes.append("The only thing Flare sends beyond 127.0.0.1: a version check against GitHub, once a day. It never downloads or installs anything on its own.")
        return notes
    }
}

// MARK: - Signals

struct SignalsPane: View {
    @State private var portText = String(Prefs.port)
    @State private var applied = Prefs.port
    @State private var listenerStatus = HTTPListener.shared.status
    @State private var listenerHealthy = HTTPListener.shared.isHealthy
    @State private var copied = false
    @State private var revealError: String?

    private var applyDisabled: Bool {
        guard let value = Int(portText.trimmingCharacters(in: .whitespaces)) else { return true }
        return value == applied
    }

    var body: some View {
        SettingsPane {
            SettingsGroup(
                title: "Local Listener",
                notes: [revealError
                        ?? "Flare listens on 127.0.0.1 only. Changing the port rewrites the hooks snippet — repaste it into ~/.claude/settings.json"]
            ) {
                SettingsRow(label: "Port") {
                    HStack(spacing: 8) {
                        TextField("", text: $portText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 74)
                            .onSubmit(commitPort)
                            .onChange(of: portText) { _, new in
                                portText = String(new.filter(\.isNumber).prefix(5))
                            }
                        Button("Apply", action: commitPort)
                            .buttonStyle(.borderedProminent)
                            .disabled(applyDisabled)
                    }
                }
                SettingsRow(label: "Listener") {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(listenerHealthy ? SettingsMetrics.good : .red)
                            .frame(width: 7, height: 7)
                        Mono(text: listenerStatus)
                            .foregroundStyle(listenerHealthy ? .secondary : Color.red)
                            .textSelection(.enabled)
                    }
                }
                SettingsFreeRow(divided: false) {
                    Button(copied ? "Snippet Copied" : "Copy Hooks Snippet", action: copySnippet)
                    Button("Reveal settings.json…", action: revealSettings)
                    Spacer(minLength: 0)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: HTTPListener.stateChanged)) { _ in
            listenerStatus = HTTPListener.shared.status
            listenerHealthy = HTTPListener.shared.isHealthy
        }
    }

    private func commitPort() {
        guard let value = Int(portText.trimmingCharacters(in: .whitespaces)),
              (1024...65535).contains(value) else {
            portText = String(Prefs.port)
            return
        }
        Prefs.port = value
        applied = Prefs.port
        portText = String(Prefs.port)
    }

    private func copySnippet() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(HooksSnippet.json(port: Prefs.port), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
    }

    /// Claude Code's settings live at a fixed path. Reveal the file when it is
    /// there, the folder when only that exists, and say so when neither does —
    /// silently doing nothing would read as a broken button.
    private func revealSettings() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")
        let file = dir.appending(path: "settings.json")
        let fm = FileManager.default
        if fm.fileExists(atPath: file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
            revealError = nil
        } else if fm.fileExists(atPath: dir.path) {
            NSWorkspace.shared.activateFileViewerSelecting([dir])
            revealError = "No settings.json yet — showing ~/.claude. Paste the snippet into a new one."
        } else {
            revealError = "No ~/.claude folder yet. Claude Code creates it on first run."
        }
    }
}

// MARK: - Nagging

struct NaggingPane: View {
    /// Eight choices rather than a free slider: every value here is a decision
    /// about how often to be interrupted, and these cover it. Spelled out,
    /// because a pop-up menu has room to say what it means.
    static let steps: [(seconds: TimeInterval, label: String)] = [
        (30, "30 seconds"), (60, "1 minute"), (120, "2 minutes"), (180, "3 minutes"),
        (300, "5 minutes"), (600, "10 minutes"), (900, "15 minutes"), (1800, "30 minutes"),
    ]

    @State private var stepIndex = NaggingPane.nearestStep(to: Prefs.reminderInterval)
    @State private var quiet = Prefs.quietWhenFrontmost

    var body: some View {
        SettingsPane {
            SettingsGroup(
                title: "Reminders",
                notes: ["An agent you are already looking at does not need the screen to flash — it stays in the menu and on the badge either way. Agents in any other app still flash, and so does everything if Flare was never told which app an agent belongs to."]
            ) {
                SettingsRow(label: "Remind Every") {
                    Picker("", selection: $stepIndex) {
                        ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                            Text(step.label).tag(index)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 132)
                    .onChange(of: stepIndex) { _, new in
                        Prefs.reminderInterval = Self.steps[new].seconds
                    }
                }
                SettingsRow(label: "Stay Quiet While the Agent's App Is in Front", divided: false) {
                    Toggle("", isOn: $quiet)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: quiet) { _, on in Prefs.quietWhenFrontmost = on }
                }
            }
        }
    }

    static func nearestStep(to seconds: TimeInterval) -> Int {
        var best = 0
        for (i, step) in steps.enumerated()
        where abs(step.seconds - seconds) < abs(steps[best].seconds - seconds) { best = i }
        return best
    }
}

// MARK: - Flash

struct FlashPane: View {
    @State private var color = Prefs.flashColor
    @State private var peak = Prefs.peakOpacity
    @State private var previewOpacity: Double = 0

    var body: some View {
        SettingsPane {
            SettingsGroup(
                title: "Appearance",
                notes: ["Peak opacity is how much of the screen the flash covers at its brightest. Test Flash plays it once at the current settings."]
            ) {
                SettingsRow(label: "Color") {
                    HStack(spacing: 9) {
                        Mono(text: color.hexString)
                            .foregroundStyle(.secondary)
                        ColorWell(title: "Flash color", color: $color)
                            .onChange(of: color) { _, new in Prefs.flashColor = new }
                    }
                }
                SettingsRow(label: "Peak Opacity") {
                    HStack(spacing: 12) {
                        Slider(value: $peak, in: 0.05...0.60, step: 0.05)
                            .frame(width: 264)
                            .onChange(of: peak) { _, new in Prefs.peakOpacity = new }
                        Mono(text: "\(Int((peak * 100).rounded()))%", size: 12)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                SettingsFreeRow(divided: false) {
                    HStack(spacing: 14) {
                        Button("Test Flash", action: runTest)
                        ZStack(alignment: .leading) {
                            Rectangle().fill(SettingsMetrics.screen)
                            Text("your screen")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.45))
                                .padding(.horizontal, 11)
                            Rectangle()
                                .fill(Color(nsColor: color))
                                .opacity(previewOpacity * peak)
                        }
                        .frame(height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    /// Runs the real thing as well as the preview — this is the same "Test
    /// flash" the menu has, and it deliberately ignores pause.
    private func runTest() {
        Reminder.shared.noteUserIsPresent()
        FlashOverlay.shared.flash()

        // Two pulses, matching FlashOverlay's own shape.
        previewOpacity = 0
        withAnimation(.easeInOut(duration: 0.22)) { previewOpacity = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.easeInOut(duration: 0.34)) { previewOpacity = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.56) {
            withAnimation(.easeInOut(duration: 0.22)) { previewOpacity = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.78) {
            withAnimation(.easeInOut(duration: 0.42)) { previewOpacity = 0 }
        }
    }
}

// MARK: - Menu Bar

struct MenuBarPane: View {
    enum ColorMode: Hashable { case auto, custom }

    @State private var badge = Prefs.menuBarBadge
    @State private var mode: ColorMode = Prefs.menuBarBadgeColor == nil ? .auto : .custom
    /// Kept while "Match Menu Bar" is selected, so switching back to Custom
    /// returns the colour you last chose rather than starting over.
    @State private var custom = Prefs.menuBarBadgeColor ?? Prefs.flashColor

    var body: some View {
        SettingsPane {
            SettingsGroup(
                title: "Indicator",
                notes: ["The number tells you how many agents are waiting; the dot only tells you that some are. Either way the menu and the tooltip list them."]
            ) {
                SettingsRow(label: "While Agents Are Waiting") {
                    Picker("", selection: $badge) {
                        ForEach(Prefs.MenuBarBadge.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    .onChange(of: badge) { _, new in Prefs.menuBarBadge = new }
                }
                SettingsRow(label: "Indicator Color") {
                    HStack(spacing: 9) {
                        Picker("", selection: $mode) {
                            Text("Match Menu Bar").tag(ColorMode.auto)
                            Text("Custom Color").tag(ColorMode.custom)
                        }
                        .labelsHidden()
                        .frame(width: 150)
                        .onChange(of: mode) { _, new in apply(mode: new) }
                        if mode == .custom {
                            ColorWell(title: "Indicator color", color: $custom)
                                .onChange(of: custom) { _, _ in apply(mode: mode) }
                        }
                    }
                }
                SettingsRow(label: "Preview", divided: false) {
                    HStack(spacing: 10) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 14, height: 14)
                        Text(badge == .count ? "3" : "●")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(mode == .custom ? Color(nsColor: custom) : Color(white: 0.96))
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 24)
                    .background(SettingsMetrics.screen, in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
    }

    private func apply(mode: ColorMode) {
        Prefs.menuBarBadgeColor = mode == .auto ? nil : custom
    }
}

// MARK: - About

struct AboutPane: View {
    private static let repo = URL(string: "https://github.com/priyomukul/flare")!

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)
                .shadow(color: .black.opacity(0.18), radius: 5, y: 4)
                .padding(.top, 26)
            Text("Flare")
                .font(.system(size: 27, weight: .bold))
                .padding(.top, 16)
            Text("Version \(UpdateChecker.shared.currentVersion) (\(Self.build))")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .textSelection(.enabled)
            Text("Your agent stops to ask; you're in another window. Flare flashes the screen the moment it needs an answer, and keeps nudging until you turn back. Everything stays on your Mac.")
                .font(.system(size: 12.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
                .padding(.top, 16)
            Text("Made by \(AppDelegate.developer)")
                .font(.system(size: 12.5))
                .padding(.top, 14)
            HStack(spacing: 18) {
                Link("Report an Issue", destination: Self.repo.appending(path: "issues"))
                Link("Source Code", destination: Self.repo)
                Link("Author", destination: URL(string: "https://github.com/priyomukul")!)
            }
            .font(.system(size: 12.5))
            .padding(.top, 12)
            Text("MIT licensed")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 26)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}

// MARK: - Shell

/// Never scrolls. The window is sized to whichever pane is showing, which is
/// how a preferences window behaves — a scroll bar inside one would mean the
/// window was the wrong size.
struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) { content }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What the Updates rows need, gathered in one place so the pane does not have
/// to switch over the checker's state inline.
struct UpdateSummary {
    var status: String
    /// The clause after the version number: "— up to date", and so on.
    var versionNote: String
    var isError = false
    var available = false
    var checking = false

    static func current() -> UpdateSummary {
        switch UpdateChecker.shared.state {
        case .idle:
            return UpdateSummary(status: lastCheckedLabel(), versionNote: "")
        case .checking:
            return UpdateSummary(status: "Contacting GitHub…", versionNote: "— checking…",
                                 checking: true)
        case .upToDate:
            return UpdateSummary(status: lastCheckedLabel(), versionNote: "— up to date")
        case .available(let version, _):
            return UpdateSummary(status: "Version \(version) is available.",
                                 versionNote: "— \(version) available", available: true)
        case .failed(let reason):
            return UpdateSummary(status: reason, versionNote: "— check failed", isError: true)
        }
    }

    static func lastCheckedLabel() -> String {
        guard let last = Prefs.lastUpdateCheck else { return "Not checked yet." }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return "Checked \(f.localizedString(for: last, relativeTo: Date()))."
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
