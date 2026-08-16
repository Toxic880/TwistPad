import Foundation
import ServiceManagement

/// Requires a signed app bundle; the bare binary reports `.notFound`.
enum LoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("TwistPad: could not \(enabled ? "enable" : "disable") login item: \(error)")
            return false
        }
    }
}
