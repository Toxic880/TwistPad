import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let dial = VolumeDial()
    private let hud = VolumeHUDController()
    private let settings = Settings.shared
    private let updateChecker = UpdateChecker()

    private var statusItem: StatusItemController?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var startAttempts = 0
    private var updateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        replaceOlderInstances()

        statusItem = StatusItemController(dial: dial, updateChecker: updateChecker) { [weak self] in
            self?.showSettings()
        }

        dial.onEngagementChanged = { [weak self] engaged in
            guard let self else { return }
            if engaged {
                guard self.settings.hudEnabled else { return }
                self.hud.update(level: self.dial.volumeLevel,
                                detents: self.settings.detentCount,
                                isMuted: self.dial.isMuted)
                self.hud.showVolume()
            } else {
                // Unconditional: if the HUD was switched off mid-twist, guarding
                // this would leave the panel on screen forever.
                self.hud.scheduleHide()
            }
        }

        dial.onTrackSkip = { [weak self] forward in
            guard let self, self.settings.hudEnabled else { return }
            self.hud.showTrackSkip(forward: forward)
        }

        // No scheduler hop: the dial is meant to move with your fingers.
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

        // Only the system setting is authoritative enough to switch someone's
        // preference off. The hardware probe can report a false negative when
        // another app holds the actuator, and silently disabling working
        // haptics is worse than leaving a switch on that does nothing.
        if settings.hapticsEnabled, Haptics.availability == .disabledInSystemSettings {
            settings.hapticsEnabled = false
        }

        // No-op without Accessibility, which is the point: the volume dial keeps
        // working with no permissions at all, just alongside the system's own
        // interpretation of the same fingers.
        InputSuppressor.shared.start()
        configureLoginItemOnFirstLaunch()

        startGesture()
        scheduleUpdateChecks()
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateTimer?.invalidate()
        InputSuppressor.shared.stop()
        dial.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Startup

    /// Installing over a running copy used to leave two menu bar icons fighting
    /// over the same trackpad. The newest launch wins, since that is the one the
    /// user just started.
    private func replaceOlderInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != mine }
        guard !others.isEmpty else { return }

        others.forEach { $0.terminate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
        }
    }

    /// Menu bar utilities are expected to come back after a restart, so this is
    /// set up once on first launch and is a toggle from then on.
    private func configureLoginItemOnFirstLaunch() {
        guard LoginItem.isAvailable, !settings.hasConfiguredLoginItem else { return }
        settings.hasConfiguredLoginItem = true
        LoginItem.set(true)
    }

    /// At login the app can launch before the HID stack has enumerated the
    /// trackpad, so `MTDeviceCreateList` comes back empty and the gesture would
    /// be dead until the user relaunched. Retry for a while before giving up.
    /// This also picks up a Magic Trackpad connected shortly after.
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

    /// `checkIfDue` enforces the once-a-day cap, so waking every six hours just
    /// means a long-running app still notices a release the day it lands.
    private func scheduleUpdateChecks() {
        updateChecker.checkIfDue()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.updateChecker.checkIfDue()
        }
    }

    // MARK: - Settings window

    private func showSettings() {
        if let settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(contentViewController: NSHostingController(
            rootView: SettingsView(dial: dial, updateChecker: updateChecker)))
        window.title = "TwistPad"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()

        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Failure

    /// TwistPad rides a private framework, so "it stopped working" is usually
    /// "macOS moved and there's a fixed build". Check before apologising, and
    /// turn the dead end into a download.
    private func presentUnsupportedAlert() {
        updateChecker.check { [weak self] outcome in
            guard let self else { return }
            if case .updateAvailable(let version) = outcome {
                self.showAlert(
                    title: "TwistPad needs an update",
                    body: """
                        This build can't read the trackpad on your version of macOS, \
                        but version \(version) is available and may fix it.
                        """,
                    primary: "Get Update")
            } else {
                self.showAlert(
                    title: "TwistPad can't read the trackpad",
                    body: """
                        The twist gesture needs raw multitouch data, which this Mac \
                        isn't providing. That usually means there's no multitouch \
                        trackpad attached, or this version of macOS changed the \
                        private interface TwistPad relies on.

                        The menu bar item stays available, but the gesture won't work.
                        """,
                    primary: nil)
            }
        }
    }

    private func showAlert(title: String, body: String, primary: String?) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .warning
        if let primary {
            alert.addButton(withTitle: primary)
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(UpdateChecker.releasesPage)
            }
        } else {
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
