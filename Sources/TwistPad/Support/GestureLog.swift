import AppKit
import Foundation

/// Opt-in logging of why gestures were accepted or rejected.
///
/// Writes to a file rather than the unified log: NSLog from this app does not
/// reliably surface in `log show`, and os_log redacts dynamic strings, so the
/// numbers we actually care about come back as <private>.
///
/// There is a switch for this in Settings, since "it thought my scroll was a
/// twist" is unanswerable without the numbers behind the decision. Also
/// reachable without opening the app:
///
///   defaults write com.lukek.TwistPad verboseGestureLog -bool true
///   tail -f ~/Library/Logs/TwistPad-gestures.log
enum GestureLog {

    private static let key = "verboseGestureLog"

    static var isEnabled: Bool = UserDefaults.standard.bool(forKey: key) {
        didSet { UserDefaults.standard.set(isEnabled, forKey: key) }
    }

    static let fileURL: URL = {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return library.appendingPathComponent("Logs/TwistPad-gestures.log")
    }()

    private static let queue = DispatchQueue(label: "com.lukek.TwistPad.gesture-log")
    private static var startedThisRun = false

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// Rewritten from scratch past this size. A gesture line per frame adds up
    /// quickly, and a log left switched on should not quietly fill a disk.
    private static let sizeLimit = 4 * 1024 * 1024

    static func record(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        // Captured here, formatted on the queue: `DateFormatter` is expensive
        // enough not to want on a path that runs at the contact frame rate.
        let now = Date()
        let text = message()
        queue.async { append("\(stamp.string(from: now))  \(text)\n") }
    }

    static func revealInFinder() {
        // Somewhere to point at even before the first line is written.
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? "--- TwistPad gesture log ---\n".write(to: fileURL, atomically: true,
                                                       encoding: .utf8)
        }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private static func append(_ line: String) {
        let manager = FileManager.default
        try? manager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                     withIntermediateDirectories: true)

        // Fresh file per launch, so a session is readable without hunting for
        // where it started, and again whenever it has grown past the cap.
        let size = (try? manager.attributesOfItem(atPath: fileURL.path))
            .flatMap { $0[.size] as? Int } ?? 0
        if !startedThisRun || size > sizeLimit {
            startedThisRun = true
            try? "--- TwistPad gesture log ---\n".write(to: fileURL, atomically: true,
                                                       encoding: .utf8)
        }
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? line.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
