import Foundation

/// Opt-in logging of why gestures were accepted or rejected.
///
/// Writes to a file rather than the unified log: NSLog from this app does not
/// reliably surface in `log show`, and os_log redacts dynamic strings, so the
/// numbers we actually care about come back as <private>.
///
///   defaults write com.lukek.TwistPad verboseGestureLog -bool true
///   tail -f ~/Library/Logs/TwistPad-gestures.log
enum GestureLog {

    static var isEnabled: Bool = UserDefaults.standard.bool(forKey: "verboseGestureLog")

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

    static func record(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let line = "\(stamp.string(from: Date()))  \(message())\n"
        queue.async { append(line) }
    }

    private static func append(_ line: String) {
        let manager = FileManager.default
        try? manager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                     withIntermediateDirectories: true)

        // Fresh file per launch, so a session is readable without hunting for
        // where it started.
        if !startedThisRun {
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
