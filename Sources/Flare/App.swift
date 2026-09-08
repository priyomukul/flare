import AppKit

@main
enum FlareMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // LSUIElement in Info.plist covers the bundled app; this covers `swift run`.
        app.setActivationPolicy(.accessory)
        app.run()
        _ = delegate
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    /// A coloured dot means the icon is no longer a template image, so nothing
    /// recolours the beacon for us when the menu bar flips between light and
    /// dark. Redraw it ourselves.
    private var appearanceObserver: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ note: Notification) {
        Prefs.registerDefaults()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        appearanceObserver = statusItem.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshStatusItem() }
        }
        let menu = NSMenu()
        menu.delegate = self
        // No item is ever checked, so drop the leading state column and let the
        // titles start at the left edge.
        menu.showsStateColumn = false
        statusItem.menu = menu
        refreshStatusItem()

        HTTPListener.shared.onWaiting = { [weak self] in self?.signalReceived() }
        HTTPListener.shared.start(port: Prefs.port)

        Reminder.shared.onFlash = { [weak self] in self?.flashNow() }
        Reminder.shared.start()

        UpdateChecker.shared.start()

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(prefsChanged), name: Prefs.didChange, object: nil)
        nc.addObserver(self, selector: #selector(refreshStatusItem), name: AgentStore.didChange, object: nil)
        nc.addObserver(self, selector: #selector(refreshStatusItem), name: PauseController.didChange, object: nil)
        nc.addObserver(self, selector: #selector(refreshStatusItem), name: HTTPListener.stateChanged, object: nil)
    }

    func applicationWillTerminate(_ note: Notification) {
        UpdateChecker.shared.stop()
        Reminder.shared.stop()
        HTTPListener.shared.stop()
    }

    // MARK: - Flashing

    /// A POST /waiting landed. Record it (already done) and flash unless paused.
    private func signalReceived() {
        guard !PauseController.shared.isPaused else { return }
        flashNow()
    }

    func flashNow() {
        if FlashOverlay.shared.flash() {
            Reminder.shared.noteFlashed()
        }
    }

    @objc private func prefsChanged() {
        HTTPListener.shared.restartIfNeeded(port: Prefs.port)
        // Nothing else posts when the badge style changes.
        refreshStatusItem()
    }

    // MARK: - Status item

    @objc private func refreshStatusItem() {
        let count = AgentStore.shared.count
        let active = count > 0 && !PauseController.shared.isPaused
        let dot = count > 0 && Prefs.menuBarBadge == .dot
        statusItem.button?.image = Self.icon(active: active, dot: dot,
                                             appearance: statusItem.button?.effectiveAppearance)
        statusItem.button?.title = count > 0 && Prefs.menuBarBadge == .count ? " \(count)" : ""
        statusItem.button?.toolTip = count > 0
            ? AgentStore.shared.summaryLabel()
            : "Flare · nothing waiting"
    }

    static func icon(active: Bool, dot: Bool = false, appearance: NSAppearance? = nil) -> NSImage? {
        let name = active ? "light.beacon.max.fill" : "light.beacon.max"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Flare")
            ?? NSImage(systemSymbolName: active ? "bell.fill" : "bell", accessibilityDescription: "Flare")
        img?.isTemplate = true
        guard let img, dot else { return img }
        return badged(img, appearance: appearance ?? NSApp.effectiveAppearance)
    }

    /// A dot in the flash colour in the top-right corner, with the artwork
    /// behind it cleared so it reads as a badge rather than as part of the
    /// beacon. A coloured badge rules out a template image, so the beacon is
    /// tinted here instead — resolved against the menu bar's own appearance,
    /// which is what a template image would have done for us.
    private static func badged(_ base: NSImage, appearance: NSAppearance) -> NSImage {
        var glyph = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance {
            glyph = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
        }
        let accent = Prefs.flashColor

        let badge = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            glyph.setFill()
            rect.fill(using: .sourceAtop)

            let d = min(max(rect.height * 0.3, 4), 6)
            let dot = NSRect(x: rect.maxX - d, y: rect.maxY - d, width: d, height: d)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            accent.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        badge.accessibilityDescription = base.accessibilityDescription
        return badge
    }

    // MARK: - Menu

    /// Rebuilt on every open so the waiting times are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let pause = PauseController.shared

        if !HTTPListener.shared.isHealthy {
            add(to: menu, title: "⚠︎ \(HTTPListener.shared.status)", action: nil)
        }
        if let summary = pause.summary {
            add(to: menu, title: summary, action: nil)
        }

        let agents = AgentStore.shared.all
        if agents.isEmpty {
            add(to: menu, title: "No agents waiting", action: nil)
        } else {
            for agent in agents {
                let item = add(to: menu, title: Self.menuTitle(for: agent),
                               action: #selector(clearAgent(_:)))
                item.representedObject = agent.id
                item.toolTip = agent.note
            }
        }

        menu.addItem(.separator())
        add(to: menu, title: "Clear all",
            action: agents.isEmpty ? nil : #selector(clearAll))
        add(to: menu, title: "Test flash", action: #selector(testFlash))

        if pause.isPaused {
            add(to: menu, title: "Resume", action: #selector(resume))
        } else {
            let item = add(to: menu, title: "Pause", action: nil, enabled: true)
            let sub = NSMenu()
            sub.showsStateColumn = false
            addPause(to: sub, title: "15 minutes", seconds: 15 * 60)
            addPause(to: sub, title: "1 hour", seconds: 60 * 60)
            add(to: sub, title: "Until resumed", action: #selector(pauseUntilResumed))
            item.submenu = sub
        }

        add(to: menu, title: "Copy Claude Code hooks snippet", action: #selector(copyHooks))

        // macOS gives the standard Settings item a gear automatically, and the
        // image column is laid out per section — so anything sharing a section
        // with it picks up a blank 40pt gutter. Settings sits on its own.
        menu.addItem(.separator())
        add(to: menu, title: "Settings…", action: #selector(openSettings)).keyEquivalent = ","

        menu.addItem(.separator())
        add(to: menu, title: "About Flare", action: #selector(openAbout))
        add(to: menu, title: "Quit Flare", action: #selector(quit)).keyEquivalent = "q"
    }

    /// `enabled` defaults to "has an action". Pass it explicitly for a submenu
    /// parent, which has no action of its own but must still open.
    @discardableResult
    private func add(to menu: NSMenu, title: String, action: Selector?,
                     enabled: Bool? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = action == nil ? nil : self
        item.isEnabled = enabled ?? (action != nil)
        menu.addItem(item)
        return item
    }

    // MARK: - About

    static let developer = "Priyo Mukul"
    static let repoURL = URL(string: "https://github.com/priyomukul/flare")!

    /// The standard panel already draws the icon, the name and "Version x (y)";
    /// credits carries the rest. `applicationVersion` is passed explicitly so
    /// `swift run`, which has no bundle to read it from, still shows something.
    private static var aboutOptions: [NSApplication.AboutPanelOptionKey: Any] {
        [.applicationName: "Flare",
         .applicationVersion: UpdateChecker.shared.currentVersion,
         .credits: aboutCredits]
    }

    private static var aboutCredits: NSAttributedString {
        let font = NSFont.systemFont(ofSize: 11)
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center

        let text = NSMutableAttributedString(
            string: """
            Flashes the screen when an AI agent is waiting on you.
            Menu bar only, no dependencies, nothing leaves 127.0.0.1
            but the daily version check.

            By \(developer)

            """,
            attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        // NSAttributedString.Key.link makes this clickable in the panel's text view.
        text.append(NSAttributedString(string: repoURL.absoluteString,
                                       attributes: [.font: font, .link: repoURL]))
        text.addAttribute(.paragraphStyle, value: centred,
                          range: NSRange(location: 0, length: text.length))
        return text
    }

    private func addPause(to menu: NSMenu, title: String, seconds: TimeInterval) {
        let item = add(to: menu, title: title, action: #selector(pauseFor(_:)))
        item.representedObject = seconds
    }

    /// `api-server · 4m · Claude needs your permission to use Bash`
    static func menuTitle(for agent: WaitingAgent) -> String {
        var parts = [agent.displayName, shortDuration(agent.waitingSeconds)]
        if let note = agent.note, !note.isEmpty {
            parts.append(note.count > 48 ? String(note.prefix(47)) + "…" : note)
        }
        return parts.joined(separator: " · ")
    }

    static func shortDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    // MARK: - Actions

    @objc private func clearAgent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        AgentStore.shared.remove(id: id)
    }

    @objc private func clearAll() {
        AgentStore.shared.removeAll()
    }

    /// Deliberately ignores pause — it is an explicit request to see a flash.
    @objc private func testFlash() {
        Reminder.shared.noteUserIsPresent()
        if FlashOverlay.shared.flash() {
            Reminder.shared.noteFlashed()
        }
    }

    @objc private func pauseFor(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        PauseController.shared.pause(for: seconds)
    }

    @objc private func pauseUntilResumed() {
        PauseController.shared.pauseUntilResumed()
    }

    @objc private func resume() {
        PauseController.shared.resume()
        // Resuming from the menu is itself proof I am back at the desk; without
        // this the 5s tick would flash again a moment later.
        Reminder.shared.noteUserIsPresent()
        if !AgentStore.shared.isEmpty { flashNow() }
    }

    @objc private func copyHooks() {
        let text = HooksSnippet.json(port: Prefs.port)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// The panel is a normal window, and Flare is an accessory app — without the
    /// activate it opens behind whatever you were using.
    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: Self.aboutOptions)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
