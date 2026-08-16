import AppKit
import SwiftUI

/// Floating readout shown while a twist is in progress. Never takes focus and
/// never swallows a click.
final class VolumeHUDController {

    let model = HUDModel()

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    /// Bumped on every `show`. A fade-out that started before the latest show
    /// carries a stale token and must not order the panel out — otherwise
    /// twisting again during the fade hides the panel that was just re-opened.
    private var showToken = 0

    /// The track skip panel is much smaller, so the window resizes with the mode.
    private var size: CGSize {
        model.trackSkipForward == nil ? HUDSize.volume : HUDSize.trackSkip
    }
    private let bottomMargin: CGFloat = 140

    func show() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        showToken &+= 1

        let panel = ensurePanel()
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
        reposition(panel)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().alphaValue = 1
        }
    }

    func scheduleHide(after delay: TimeInterval = 0.95) {
        hideWorkItem?.cancel()
        let token = showToken

        let work = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.panel, token == self.showToken else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                guard let self, token == self.showToken else { return }
                panel.orderOut(nil)
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func update(level: Float, detents: Int, isMuted: Bool) {
        model.level = Double(level)
        model.detents = detents
        model.isMuted = isMuted
    }

    /// Switches back to the dial. Kept separate from `update`, which runs on
    /// every volume change including external ones, and must not yank a skip
    /// indicator out from under itself.
    func showVolume() {
        model.trackSkipForward = nil
        show()
    }

    /// Track skips are momentary, so this shows and hides itself.
    func showTrackSkip(forward: Bool) {
        model.trackSkipForward = forward
        show()
        scheduleHide(after: 0.55)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 0
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary, .ignoresCycle]

        let hosting = NSHostingView(rootView: VolumeHUDView(model: model))
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting

        self.panel = panel
        return panel
    }

    /// Follow the pointer's screen rather than always using the main one.
    private func reposition(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.frame else { return }

        panel.setFrame(
            NSRect(origin: CGPoint(x: frame.midX - size.width / 2,
                                   y: frame.minY + bottomMargin),
                   size: size),
            display: false)
    }
}
