import AppKit

/// Finds other installed copies of TwistPad.
///
/// macOS grants Accessibility per code signature, not per app name, so two
/// copies are two separate entries that both read "TwistPad" in Privacy &
/// Security. Granting the wrong one looks exactly like granting the right one
/// and does nothing, which is impossible to work out without being told.
enum AppCopies {

    static func all() -> [URL] {
        guard let bundleID = Bundle.main.bundleIdentifier else { return [] }
        return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
    }

    static var runningPath: String { Bundle.main.bundlePath }

    static var others: [URL] {
        all().filter { $0.standardizedFileURL.path != runningPath }
    }

    static var hasDuplicates: Bool { !others.isEmpty }
}
