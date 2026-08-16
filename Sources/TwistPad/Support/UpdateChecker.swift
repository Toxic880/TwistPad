import Combine
import Foundation

/// Checks GitHub for a newer release and reports it. Never downloads or installs
/// anything: TwistPad is ad-hoc signed, so an auto-installed update would land
/// back in Gatekeeper quarantine. This only ever opens the releases page.
final class UpdateChecker: ObservableObject {

    /// Hardcoded on purpose. The API response carries an `html_url`, and
    /// following it would let a tampered response send users to someone else's
    /// download. Only the version number is read from the network.
    static let releasesPage = URL(string: "https://github.com/Toxic880/TwistPad/releases/latest")!
    private static let api = URL(string: "https://api.github.com/repos/Toxic880/TwistPad/releases/latest")!

    enum Outcome {
        case upToDate
        case updateAvailable(String)
        case noReleasesYet
        case failed
    }

    @Published private(set) var availableVersion: String?
    @Published private(set) var isChecking = false
    @Published private(set) var lastOutcome: Outcome?

    /// Unauthenticated GitHub allows 60 requests an hour per IP, so automatic
    /// checks are capped at one a day.
    private let minimumInterval: TimeInterval = 60 * 60 * 24
    private let lastCheckKey = "lastUpdateCheck"
    private let defaults = UserDefaults.standard

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// Automatic check, skipped if switched off or already done today.
    func checkIfDue() {
        guard Settings.shared.automaticUpdateChecks else { return }
        let last = defaults.double(forKey: lastCheckKey)
        let now = Date().timeIntervalSince1970
        guard last == 0 || now - last >= minimumInterval else { return }
        check()
    }

    func check(completion: ((Outcome) -> Void)? = nil) {
        guard !isChecking else { completion?(lastOutcome ?? .failed); return }
        isChecking = true

        var request = URLRequest(url: Self.api, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }

            let outcome: Outcome
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 404 {
                // No published releases yet. Not a failure, and not worth nagging.
                outcome = .noReleasesYet
            } else if status == 200,
                      let data,
                      let payload = try? JSONDecoder().decode(ReleasePayload.self, from: data) {
                let latest = payload.tagName
                outcome = Self.isVersion(latest, newerThan: self.currentVersion)
                    ? .updateAvailable(Self.normalize(latest))
                    : .upToDate
            } else {
                outcome = .failed
            }

            DispatchQueue.main.async {
                self.isChecking = false
                self.lastOutcome = outcome
                if case .updateAvailable(let version) = outcome {
                    self.availableVersion = version
                } else {
                    self.availableVersion = nil
                }
                if status == 200 || status == 404 {
                    self.defaults.set(Date().timeIntervalSince1970, forKey: self.lastCheckKey)
                }
                completion?(outcome)
            }
        }.resume()
    }

    private struct ReleasePayload: Decodable {
        let tagName: String
        enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
    }

    // MARK: - Version comparison

    /// Compares numerically, component by component. String comparison would put
    /// 1.10 behind 1.9, which is the classic way these checks ship broken.
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = components(of: candidate)
        let b = components(of: current)
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    /// Tolerates a leading `v` and trailing suffixes like `-beta`.
    private static func components(of version: String) -> [Int] {
        normalize(version)
            .split(separator: ".")
            .map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    private static func normalize(_ version: String) -> String {
        var trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "v" || trimmed.first == "V" {
            trimmed.removeFirst()
        }
        return trimmed
    }
}
