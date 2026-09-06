import AppKit
import QuartzCore

/// Full-screen overlay window. Must never become key or main — it sits above
/// everything, including full-screen apps, without stealing focus.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Content of one overlay window: a full-bleed colour layer plus a small badge in
/// the top-right. The two animate separately so the text stays readable even
/// though the colour only ever reaches `peakOpacity`.
final class FlashContentView: NSView {
    private let colorView = NSView()
    private let badgeView = NSView()
    private let label = NSTextField(labelWithString: "")
    private let topInset: CGFloat

    init(frame: NSRect, topInset: CGFloat) {
        self.topInset = topInset
        super.init(frame: frame)
        wantsLayer = true

        // Layer-hosting (layer assigned before wantsLayer): AppKit never resets
        // this layer's opacity behind our back.
        colorView.frame = bounds
        colorView.autoresizingMask = [.width, .height]
        colorView.layer = CALayer()
        colorView.wantsLayer = true
        colorView.layer?.opacity = 0
        addSubview(colorView)

        badgeView.wantsLayer = true
        badgeView.layer?.cornerRadius = 8
        badgeView.layer?.backgroundColor = NSColor(white: 0, alpha: 0.78).cgColor
        badgeView.autoresizingMask = [.minXMargin, .minYMargin]
        badgeView.alphaValue = 0
        addSubview(badgeView)

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.usesSingleLineMode = true
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        badgeView.addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func setLabel(_ text: String) {
        label.stringValue = text
        label.sizeToFit()
        let padX: CGFloat = 12, padY: CGFloat = 7
        let tw = min(ceil(label.frame.width), max(120, bounds.width - 100))
        let th = ceil(label.frame.height)
        let w = tw + padX * 2, h = th + padY * 2
        badgeView.frame = NSRect(x: bounds.maxX - 24 - w,
                                 y: bounds.maxY - topInset - h,
                                 width: w, height: h)
        label.frame = NSRect(x: padX, y: padY, width: tw, height: th)
    }

    func setColor(_ color: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        colorView.layer?.backgroundColor = (color.usingColorSpace(.sRGB) ?? color).cgColor
        CATransaction.commit()
    }

    /// Two pulses in and out. Base opacity stays 0, so once the animation is
    /// removed the overlay is invisible again with no flicker.
    func run(peak: Float, duration: CFTimeInterval) {
        guard let colorLayer = colorView.layer, let badgeLayer = badgeView.layer else { return }
        let ease = CAMediaTimingFunction(name: .easeInEaseOut)

        let pulse = CAKeyframeAnimation(keyPath: "opacity")
        pulse.values = [0.0, Double(peak), 0.0, Double(peak), 0.0]
        pulse.keyTimes = [0, 0.18, 0.46, 0.64, 1.0]
        pulse.timingFunctions = Array(repeating: ease, count: 4)
        pulse.duration = duration
        pulse.isRemovedOnCompletion = true
        colorLayer.removeAnimation(forKey: "flare.pulse")
        colorLayer.add(pulse, forKey: "flare.pulse")

        let badge = CAKeyframeAnimation(keyPath: "opacity")
        badge.values = [0.0, 1.0, 1.0, 0.0]
        badge.keyTimes = [0, 0.09, 0.82, 1.0]
        badge.timingFunctions = Array(repeating: ease, count: 3)
        badge.duration = duration
        badge.isRemovedOnCompletion = true
        badgeLayer.removeAnimation(forKey: "flare.badge")
        badgeLayer.add(badge, forKey: "flare.badge")
    }

    func stop() {
        colorView.layer?.removeAnimation(forKey: "flare.pulse")
        badgeView.layer?.removeAnimation(forKey: "flare.badge")
    }
}

/// Owns one overlay window per screen and drives the flash animation.
final class FlashOverlay {
    static let shared = FlashOverlay()

    static let flashDuration: TimeInterval = 1.2
    /// Photosensitivity guard. The spec's hard ceiling is 3 flashes/second; we
    /// keep a 0.5s floor between flash starts, so at most 2/second.
    static let minGap: TimeInterval = 0.5

    private var windows: [OverlayWindow] = []
    /// Monotonic — a backwards wall-clock step must not disable flashing.
    private var lastStart: CFTimeInterval = -.greatestFiniteMagnitude
    private var lastLabel = "Flare"
    private var teardown: DispatchWorkItem?
    private var pendingRestart: DispatchWorkItem?

    private init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(displaysChanged),
                       name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(displaysChanged),
                       name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    /// Flash every screen. Safe to call at any rate; excess calls only refresh
    /// the badge text of the in-flight flash. Returns true if a pulse actually
    /// started, false if the photosensitivity floor swallowed it.
    @discardableResult
    func flash(label: String) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        lastLabel = label
        pendingRestart?.cancel()
        pendingRestart = nil
        syncWindows()
        guard !windows.isEmpty else { return false }
        for w in windows { (w.contentView as? FlashContentView)?.setLabel(label) }

        let now = CACurrentMediaTime()
        guard now - lastStart >= Self.minGap else { return false }
        lastStart = now

        let color = Prefs.flashColor
        let peak = Float(Prefs.peakOpacity)
        for w in windows {
            guard let v = w.contentView as? FlashContentView else { continue }
            v.setColor(color)
            w.orderFrontRegardless()
            v.run(peak: peak, duration: Self.flashDuration)
        }

        teardown?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        teardown = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flashDuration + 0.08, execute: work)
        return true
    }

    /// Order the windows out so they cost nothing between flashes.
    func hide() {
        teardown?.cancel()
        teardown = nil
        for w in windows {
            (w.contentView as? FlashContentView)?.stop()
            w.orderOut(nil)
        }
    }

    // MARK: - Window lifecycle

    /// Screen geometry changed, or the Mac woke. Both can land in the middle of
    /// a flash — on wake they reliably do, which is exactly when I most need to
    /// see one. Rebuild and re-run rather than dropping it on the floor.
    @objc private func displaysChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let interrupted = self.teardown != nil || self.pendingRestart != nil
            self.pendingRestart?.cancel()
            self.pendingRestart = nil
            self.hide()
            self.destroyWindows()
            guard interrupted else { return }

            // The interrupted flash never rendered, so it must not spend the
            // rate-limit budget. The delay coalesces the burst of notifications
            // a single wake produces into one restart.
            self.lastStart = -.greatestFiniteMagnitude
            let label = self.lastLabel
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingRestart = nil
                self.flash(label: label)
            }
            self.pendingRestart = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    private func syncWindows() {
        let screens = NSScreen.screens
        if windows.count == screens.count,
           zip(windows, screens).allSatisfy({ $0.frame == $1.frame }) { return }
        destroyWindows()
        windows = screens.map(makeWindow(for:))
    }

    private func destroyWindows() {
        for w in windows {
            w.orderOut(nil)
            w.contentView = nil
            w.close()
        }
        windows.removeAll()
    }

    private func makeWindow(for screen: NSScreen) -> OverlayWindow {
        let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.isReleasedWhenClosed = false
        w.animationBehavior = .none
        w.setFrame(screen.frame, display: false)

        // Keep the badge clear of the menu bar / notch.
        let chrome = screen.frame.maxY - screen.visibleFrame.maxY
        let view = FlashContentView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                    topInset: chrome + 12)
        w.contentView = view
        return w
    }
}
