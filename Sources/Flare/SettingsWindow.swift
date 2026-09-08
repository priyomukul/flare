import AppKit
import SwiftUI

/// The Settings window: a standard macOS preferences window, which is the
/// native form of the design's centred icon-over-label tab strip with the pane
/// name in the title bar. `NSToolbar` in `.preference` style draws exactly
/// that, including the selection highlight, for free.
final class SettingsWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    static let shared = SettingsWindowController()

    enum Pane: String, CaseIterable {
        case general, signals, nagging, flash, menuBar, about

        var title: String {
            switch self {
            case .general: "General"
            case .signals: "Signals"
            case .nagging: "Nagging"
            case .flash: "Flash"
            case .menuBar: "Menu Bar"
            case .about: "About"
            }
        }

        /// Chosen to read as the design's line icons: sliders, a signal trace,
        /// a bell, a bolt, a menu bar with its indicator, and an info circle.
        var symbol: String {
            switch self {
            case .general: "slider.horizontal.3"
            case .signals: "waveform.path.ecg"
            case .nagging: "bell"
            case .flash: "bolt.fill"
            case .menuBar: "menubar.rectangle"
            case .about: "info.circle"
            }
        }

        var identifier: NSToolbarItem.Identifier { .init("flare.pane." + rawValue) }

        @ViewBuilder var view: some View {
            switch self {
            case .general: GeneralPane()
            case .signals: SignalsPane()
            case .nagging: NaggingPane()
            case .flash: FlashPane()
            case .menuBar: MenuBarPane()
            case .about: AboutPane()
            }
        }
    }

    /// The design's window is 720 wide and never shorter than 396. There is no
    /// upper bound of our own: the window is sized to the pane, and a pane that
    /// did not fit would need a scroll bar, which a preferences window should
    /// not have. Only the screen limits it.
    private static let width: CGFloat = SettingsMetrics.paneWidth
    private static let minHeight: CGFloat = 396

    private var window: NSWindow?
    private var pane: Pane = .general
    /// The window's content view controller never changes. Swapping it makes
    /// AppKit resize the window to fit the incoming controller before we get a
    /// say, which reads as the window snapping and then sliding back.
    private let container = NSViewController()
    private var current: NSViewController?

    func show(_ pane: Pane = .general) {
        self.pane = pane
        let window = window ?? makeWindow()
        self.window = window
        install(pane, in: window)
        window.toolbar?.selectedItemIdentifier = pane.identifier
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.minHeight),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.toolbarStyle = .preference
        let toolbar = NSToolbar(identifier: "flare.settings")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconAndLabel
        w.toolbar = toolbar
        container.view = NSView(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.minHeight))
        w.contentViewController = container
        w.center()
        return w
    }

    /// A fresh hosting controller per switch. Reusing one does not re-run
    /// `onAppear`, so the listener status, the launch-at-login state and
    /// "Checked N ago" would all be whatever they were when it was first built.
    ///
    /// It is measured at the window's fixed width and the window is resized
    /// before the view goes in, so there is exactly one size change per switch
    /// and nothing to see between them.
    private func install(_ pane: Pane, in window: NSWindow) {
        let hosting = NSHostingController(rootView: pane.view)
        let natural = measure(hosting)

        // A pane taller than the screen has nowhere to go; clamp so the title
        // bar stays reachable rather than sliding off the top.
        let room = ((window.screen ?? NSScreen.main)?.visibleFrame.height ?? 900) - 40
        let height = min(max(natural, Self.minHeight), room)

        window.title = pane.title
        resize(window, toContentHeight: height)

        current?.view.removeFromSuperview()
        current?.removeFromParent()
        container.addChild(hosting)

        // Pinned to the top, at its natural height. Filling the window instead
        // would let the hosting view centre a short pane in the slack left by
        // the minimum height, which is where every pane but General ended up.
        let bounds = container.view.bounds
        let viewHeight = min(natural, height)
        hosting.view.frame = NSRect(x: 0, y: bounds.height - viewHeight,
                                    width: bounds.width, height: viewHeight)
        hosting.view.autoresizingMask = [.width, .minYMargin]
        container.view.addSubview(hosting.view)
        current = hosting
    }

    /// The pane's natural height. SwiftUI only reports a useful one once it
    /// knows the width it has to lay out in, so the view is pinned to the
    /// window's fixed width, laid out, and measured before anything is shown.
    private func measure(_ hosting: NSViewController) -> CGFloat {
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        let width = hosting.view.widthAnchor.constraint(equalToConstant: Self.width)
        width.isActive = true
        hosting.view.layoutSubtreeIfNeeded()
        let fitted = hosting.view.fittingSize.height
        width.isActive = false
        hosting.view.translatesAutoresizingMaskIntoConstraints = true
        return fitted
    }

    /// Cocoa positions a window by its bottom-left corner, so a plain resize
    /// grows it upwards — switch between panes of different heights and the
    /// title bar walks up the screen. Preferences windows stay put and change
    /// height downwards, so pin the top edge and move the origin ourselves.
    ///
    /// Never animated: a settings pane changes instantly, and animating the
    /// frame looks like someone dragging the window's corner.
    private func resize(_ window: NSWindow, toContentHeight height: CGFloat) {
        let target = window.frameRect(forContentRect:
            NSRect(origin: .zero, size: NSSize(width: Self.width, height: height)))
        var frame = window.frame
        guard abs(frame.height - target.height) > 0.5
                || abs(frame.width - target.width) > 0.5 else { return }
        frame.origin.y = frame.maxY - target.height
        frame.size = target.size
        window.setFrame(frame, display: true)
    }

    @objc private func selectPane(_ sender: NSToolbarItem) {
        guard let pane = Pane.allCases.first(where: { $0.identifier == sender.itemIdentifier }),
              let window else { return }
        self.pane = pane
        install(pane, in: window)
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Pane.allCases.map(\.identifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = Pane.allCases.first(where: { $0.identifier == identifier }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = pane.title
        item.paletteLabel = pane.title
        item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
        item.target = self
        item.action = #selector(selectPane(_:))
        return item
    }
}
