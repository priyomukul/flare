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

    func applicationDidFinishLaunching(_ note: Notification) {
        Prefs.registerDefaults()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
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

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(prefsChanged), name: Prefs.didChange, object: nil)
        nc.addObserver(self, selector: #selector(refreshStatusItem), name: AgentStore.didChange, object: nil)
        nc.addObserver(self, selector: #selector(refreshStatusItem), name: PauseController.didChange, object: nil)
        nc.addObserver(self, selector: #selector(refreshStatusItem), name: HTTPListener.stateChanged, object: nil)
    }

    func applicationWillTerminate(_ note: Notification) {
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
        if FlashOverlay.shared.flash(label: AgentStore.shared.summaryLabel()) {
            Reminder.shared.noteFlashed()
        }
    }

    @objc private func prefsChanged() {
        HTTPListener.shared.restartIfNeeded(port: Prefs.port)
    }

    // MARK: - Status item

    @objc private func refreshStatusItem() {
        let count = AgentStore.shared.count
        let active = count > 0 && !PauseController.shared.isPaused
        statusItem.button?.image = Self.icon(active: active)
        statusItem.button?.title = count > 0 ? " \(count)" : ""
        statusItem.button?.toolTip = count > 0
            ? AgentStore.shared.summaryLabel()
            : "Flare · nothing waiting"
    }

    static func icon(active: Bool) -> NSImage? {
        let name = active ? "light.beacon.max.fill" : "light.beacon.max"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Flare")
            ?? NSImage(systemSymbolName: active ? "bell.fill" : "bell", accessibilityDescription: "Flare")
        img?.isTemplate = true
        return img
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
        add(to: menu, title: "Settings…", action: #selector(openSettings)).keyEquivalent = ","

        menu.addItem(.separator())
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
        if FlashOverlay.shared.flash(label: "Flare · test flash") {
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

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
