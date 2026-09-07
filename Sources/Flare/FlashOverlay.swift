import AppKit
import QuartzCore

/// Full-screen overlay window. Must never become key or main — it sits above
/// everything, including full-screen apps, without stealing focus.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Content of one overlay window: a single full-bleed colour layer.
final class FlashContentView: NSView {
    private let colorView = NSView()

    override init(frame: NSRect) {
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func setColor(_ color: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        colorView.layer?.backgroundColor = (color.usingColorSpace(.sRGB) ?? color).cgColor
        CATransaction.commit()
    }

    /// Two pulses in and out. Base opacity stays 0, so once the animation is
    /// removed the overlay is invisible again with no flicker.
    func run(peak: Float, duration: CFTimeInterval) {
        guard let colorLayer = colorView.layer else { return }
        let ease = CAMediaTimingFunction(name: .easeInEaseOut)

        let pulse = CAKeyframeAnimation(keyPath: "opacity")
        pulse.values = [0.0, Double(peak), 0.0, Double(peak), 0.0]
        pulse.keyTimes = [0, 0.18, 0.46, 0.64, 1.0]
        pulse.timingFunctions = Array(repeating: ease, count: 4)
        pulse.duration = duration
        pulse.isRemovedOnCompletion = true
        colorLayer.removeAnimation(forKey: "flare.pulse")
        colorLayer.add(pulse, forKey: "flare.pulse")
    }

    func stop() {
        colorView.layer?.removeAnimation(forKey: "flare.pulse")
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

    /// Flash every screen. Safe to call at any rate. Returns true if a pulse
    /// actually started, false if the photosensitivity floor swallowed it.
    @discardableResult
    func flash() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        pendingRestart?.cancel()
        pendingRestart = nil
        syncWindows()
        guard !windows.isEmpty else { return false }

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
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingRestart = nil
                self.flash()
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

        w.contentView = FlashContentView(frame: NSRect(origin: .zero, size: screen.frame.size))
        return w
    }
}
