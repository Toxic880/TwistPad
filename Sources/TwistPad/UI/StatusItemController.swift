import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let dial: VolumeDial
    private let settings = Settings.shared
    private let onOpenSettings: () -> Void

    init(dial: VolumeDial, onOpenSettings: @escaping () -> Void) {
        self.dial = dial
        self.onOpenSettings = onOpenSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.toolTip = "TwistPad — twist two fingers to set the volume"
        refresh()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func refresh() {
        statusItem.button?.image = MenuBarIcon.image(
            level: Double(dial.volumeLevel),
            muted: dial.isMuted || dial.volumeLevel <= 0.001)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status: String
        if !dial.isSupported {
            status = "No trackpad detected"
        } else if !dial.canControlVolume {
            status = "\(dial.outputDeviceName) has no volume control"
        } else {
            status = "\(Int((dial.volumeLevel * 100).rounded()))%  ·  \(dial.outputDeviceName)"
        }
        let header = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "Twist for Volume",
                                action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = settings.isEnabled ? .on : .off
        menu.addItem(toggle)

        let haptics = NSMenuItem(title: "Haptic Detents",
                                 action: #selector(toggleHaptics), keyEquivalent: "")
        haptics.target = self
        haptics.state = settings.hapticsEnabled ? .on : .off
        menu.addItem(haptics)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        if LoginItem.isAvailable {
            let login = NSMenuItem(title: "Open at Login",
                                   action: #selector(toggleLoginItem), keyEquivalent: "")
            login.target = self
            login.state = LoginItem.isEnabled ? .on : .off
            menu.addItem(login)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit TwistPad",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
    }

    @objc private func toggleHaptics() {
        settings.hapticsEnabled.toggle()
    }

    @objc private func toggleLoginItem() {
        LoginItem.set(!LoginItem.isEnabled)
    }

    @objc private func openSettings() {
        onOpenSettings()
    }
}
