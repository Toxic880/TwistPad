import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let dial = VolumeDial()
    private let hud = VolumeHUDController()
    private let settings = Settings.shared

    private var statusItem: StatusItemController?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var startAttempts = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(dial: dial) { [weak self] in
            self?.showSettings()
        }

        dial.onEngagementChanged = { [weak self] engaged in
            guard let self else { return }
            if engaged {
                guard self.settings.hudEnabled else { return }
                self.hud.update(level: self.dial.volumeLevel,
                                detents: self.settings.detentCount,
                                isMuted: self.dial.isMuted)
                self.hud.show()
            } else {
                // Unconditional: if the HUD was switched off mid-twist, guarding
                // this would leave the panel on screen forever.
                self.hud.scheduleHide()
            }
        }

        // No scheduler hop: the arc is meant to move with your fingers.
        dial.$volumeLevel
            .sink { [weak self] level in
                guard let self else { return }
                self.hud.update(level: level,
                                detents: self.settings.detentCount,
                                isMuted: self.dial.isMuted)
            }
            .store(in: &cancellables)

        dial.$volumeLevel
            .throttle(for: .milliseconds(150), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.statusItem?.refresh() }
            .store(in: &cancellables)

        startGesture()
    }

    /// At login the app can launch before the HID stack has enumerated the
    /// trackpad, so `MTDeviceCreateList` comes back empty and the gesture would
    /// be dead until the user relaunched. Retry for a while before giving up.
    /// This also picks up a Magic Trackpad that gets connected shortly after.
    private func startGesture() {
        if dial.start() { return }

        startAttempts += 1
        guard startAttempts < 15 else {
            presentUnsupportedAlert()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.startGesture()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        dial.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func showSettings() {
        if let settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(contentViewController:
            NSHostingController(rootView: SettingsView(dial: dial)))
        window.title = "TwistPad"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()

        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func presentUnsupportedAlert() {
        let alert = NSAlert()
        alert.messageText = "TwistPad can't read the trackpad"
        alert.informativeText = """
            The twist gesture needs raw multitouch data, which this Mac isn't \
            providing. That usually means there's no multitouch trackpad \
            attached, or this version of macOS changed the private \
            MultitouchSupport interface TwistPad relies on.

            The menu bar item stays available, but the gesture won't work.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
