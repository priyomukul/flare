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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ note: Notification) {
        Prefs.registerDefaults()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.icon(active: false)
        statusItem.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.addItem(withTitle: "Test flash", action: #selector(testFlash), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Flare", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu

        HTTPListener.shared.onWaiting = { [weak self] in self?.flashForWaiting() }
        HTTPListener.shared.start(port: Prefs.port)

        NotificationCenter.default.addObserver(
            self, selector: #selector(prefsChanged), name: Prefs.didChange, object: nil)
    }

    func applicationWillTerminate(_ note: Notification) {
        HTTPListener.shared.stop()
    }

    @objc private func prefsChanged() {
        HTTPListener.shared.restartIfNeeded(port: Prefs.port)
    }

    private func flashForWaiting() {
        FlashOverlay.shared.flash(label: AgentStore.shared.summaryLabel())
    }

    static func icon(active: Bool) -> NSImage? {
        let name = active ? "light.beacon.max.fill" : "light.beacon.max"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Flare")
            ?? NSImage(systemSymbolName: active ? "bell.fill" : "bell", accessibilityDescription: "Flare")
        img?.isTemplate = true
        return img
    }

    @objc private func testFlash() {
        FlashOverlay.shared.flash(label: "Flare · test flash")
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
