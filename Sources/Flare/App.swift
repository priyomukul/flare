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

    /// Everything the icon depends on. Rebuilding it on every refresh — and
    /// there is one per signal, pause, listener change and menu open — hands
    /// NSStatusItem a new image each time, which makes it re-snapshot the
    /// button for its Control Center replica. That is expensive enough to
    /// matter on its own, and it used to be ruinous: see `appearanceObserver`
    /// in the git history for the spin it caused.
    private struct IconKey: Equatable {
        let active: Bool
        let dot: Bool
        let accent: String
        let appearance: String
    }
    private var cachedIcon: (key: IconKey, image: NSImage)?

    func applicationDidFinishLaunching(_ note: Notification) {
        Prefs.registerDefaults()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        // A dot in the flash colour cannot be a template image, so the beacon
        // is tinted by hand and has to be redrawn when the menu bar flips
        // between light and dark. This notification fires once per switch;
        // observing the button's own effectiveAppearance instead feeds back
        // into the redraw it triggers and spins the main thread.
        DistributedNotificationCenter.default.addObserver(
            self, selector: #selector(refreshStatusItem),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
        let menu = NSMenu()
        menu.delegate = self
        // No item is ever checked, so drop the leading state column and let the
        // titles start at the left edge.
        menu.showsStateColumn = false
        statusItem.menu = menu
        refreshStatusItem()

        // An accessory app never shows a menu bar, but NSApplication still
        // dispatches key equivalents through the main menu — so without one
        // there is no Cmd-W to close Settings, and no Cmd-C or Cmd-V in the
        // port field either. None of this is ever drawn.
        NSApp.mainMenu = Self.makeMainMenu()

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
        guard shouldFlash() else { return }
        if FlashOverlay.shared.flash() {
            Reminder.shared.noteFlashed()
        }
    }

    /// There is nothing to tell you if everything waiting is in the app you are
    /// already looking at. Deliberately not a clear: the agents stay in the
    /// list and on the badge, because "waiting" is still true — you just do not
    /// need the screen to shout it.
    ///
    /// Frontmost app is the finest granularity macOS offers here. It cannot say
    /// which tab, which is exactly why this suppresses rather than clears: a
    /// clear would have to guess, and guessing wrong loses state.
    private func shouldFlash() -> Bool {
        guard Prefs.quietWhenFrontmost else { return true }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return AgentStore.shared.hasWaitingOutside(front)
    }

    @objc private func prefsChanged() {
        HTTPListener.shared.restartIfNeeded(port: Prefs.port)
        // Nothing else posts when the badge style changes.
        refreshStatusItem()
    }

    // MARK: - Status item

    /// Every assignment here is guarded. NSStatusItem treats any write as a
    /// change and re-snapshots the button, so writing the same values back on
    /// every signal is pure waste — and writing a freshly built, equal image is
    /// worse than waste.
    @objc private func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        let count = AgentStore.shared.count
        let active = count > 0 && !PauseController.shared.isPaused
        let dot = count > 0 && Prefs.menuBarBadge == .dot

        let accent = Prefs.menuBarBadgeColor
        let key = IconKey(active: active, dot: dot,
                          accent: dot ? (accent?.hexString ?? Prefs.menuBarBadgeAuto) : "",
                          appearance: button.effectiveAppearance.name.rawValue)
        if cachedIcon?.key != key,
           let image = Self.icon(active: active, dot: dot, accent: accent,
                                 appearance: button.effectiveAppearance) {
            cachedIcon = (key, image)
        }
        if button.image !== cachedIcon?.image { button.image = cachedIcon?.image }

        let title = count > 0 && Prefs.menuBarBadge == .count ? " \(count)" : ""
        if button.title != title { button.title = title }
        // A count in a colour of its own has to be an attributed title; left
        // plain, the menu bar draws it in the label colour like the icon.
        if let accent, !title.isEmpty {
            let styled = NSAttributedString(string: title, attributes: [.foregroundColor: accent])
            if button.attributedTitle != styled { button.attributedTitle = styled }
        }

        let tip = count > 0 ? AgentStore.shared.summaryLabel() : "Flare · nothing waiting"
        if button.toolTip != tip { button.toolTip = tip }
    }

    static func icon(active: Bool, dot: Bool = false, accent: NSColor? = nil,
                     appearance: NSAppearance? = nil) -> NSImage? {
        let name = active ? "light.beacon.max.fill" : "light.beacon.max"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Flare")
            ?? NSImage(systemSymbolName: active ? "bell.fill" : "bell", accessibilityDescription: "Flare")
        img?.isTemplate = true
        guard let img, dot else { return img }
        return badged(img, accent: accent, appearance: appearance ?? NSApp.effectiveAppearance)
    }

    /// A dot in the top-right corner, with the artwork behind it cleared so it
    /// reads as a badge rather than as part of the beacon.
    ///
    /// With no accent — the default — the result stays a template image, which
    /// is both the cheapest thing to draw and correct in light and dark without
    /// anyone having to say so. An accent rules that out, so the beacon is
    /// tinted by hand against the menu bar's own appearance instead, which is
    /// what the template would have done for us.
    private static func badged(_ base: NSImage, accent: NSColor?,
                               appearance: NSAppearance) -> NSImage {
        var glyph = NSColor.black
        if accent != nil {
            appearance.performAsCurrentDrawingAppearance {
                glyph = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
            }
        }

        let badge = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            if accent != nil {
                glyph.setFill()
                rect.fill(using: .sourceAtop)
            }

            let d = min(max(rect.height * 0.3, 4), 6)
            let dot = NSRect(x: rect.maxX - d, y: rect.maxY - d, width: d, height: d)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            (accent ?? .black).setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        badge.isTemplate = accent == nil
        badge.accessibilityDescription = base.accessibilityDescription
        return badge
    }

    /// The invisible main menu. Only the key equivalents matter, but the items
    /// are given real titles so they read correctly in the Help menu's search
    /// and to accessibility clients.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Flare", action: #selector(openAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Flare",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // Standard editing selectors, so the port field behaves like a text
        // field rather than a place where Cmd-V does nothing.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All",
                         action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close",
                           action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        return main
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
                               action: #selector(goToAgent(_:)))
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

    /// Raise the terminal the agent is waiting in, then drop it from the list —
    /// clicking the row means "I am dealing with this one now".
    ///
    /// Clearing from the menu is itself proof I am at the keyboard; without
    /// noteUserIsPresent the return-to-desk trigger stays armed and flashes for
    /// whatever is left a moment later.
    @objc private func goToAgent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Reminder.shared.noteUserIsPresent()
        if let agent = AgentStore.shared.agent(id: id) { Focus.go(to: agent.origin) }
        AgentStore.shared.remove(id: id)
    }

    @objc private func clearAll() {
        Reminder.shared.noteUserIsPresent()
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

    /// About is a pane of Settings rather than the standard AppKit panel — one
    /// About, and the only one that can carry the version, the author and the
    /// links together.
    @objc private func openAbout() {
        SettingsWindowController.shared.show(.about)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show(.general)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
