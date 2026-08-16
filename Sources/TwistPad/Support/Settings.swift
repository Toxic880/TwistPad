import Combine
import Foundation

final class Settings: ObservableObject {

    static let shared = Settings()

    private enum Key {
        static let isEnabled = "isEnabled"
        static let degreesForFullSweep = "degreesForFullSweep"
        static let activationThreshold = "activationThresholdDegrees"
        static let invertDirection = "invertDirection"
        static let detentCount = "detentCount"
        static let hapticsEnabled = "hapticsEnabled"
        static let hudEnabled = "hudEnabled"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let automaticUpdateChecks = "automaticUpdateChecks"
        static let trackControlEnabled = "trackControlEnabled"
        static let blockScrollDuringGestures = "blockScrollDuringGestures"
        static let hasConfiguredLoginItem = "hasConfiguredLoginItem"
    }

    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }

    /// Wrist range of motion is the binding constraint: a natural thumb-and-index
    /// twist has a median of 60°, so 70° puts the whole range in one turn.
    @Published var degreesForFullSweep: Double {
        didSet { defaults.set(degreesForFullSweep, forKey: Key.degreesForFullSweep) }
    }

    @Published var activationThreshold: Double {
        didSet { defaults.set(activationThreshold, forKey: Key.activationThreshold) }
    }

    @Published var invertDirection: Bool {
        didSet { defaults.set(invertDirection, forKey: Key.invertDirection) }
    }

    /// Detents across the full range; 0 is smooth. 16 matches the volume keys.
    @Published var detentCount: Int {
        didSet { defaults.set(detentCount, forKey: Key.detentCount) }
    }

    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) }
    }

    @Published var hudEnabled: Bool {
        didSet { defaults.set(hudEnabled, forKey: Key.hudEnabled) }
    }

    /// Apps that use two-finger rotation themselves.
    @Published var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: Key.excludedBundleIDs) }
    }

    /// Set once, so turning the login item off stays off.
    @Published var hasConfiguredLoginItem: Bool {
        didSet { defaults.set(hasConfiguredLoginItem, forKey: Key.hasConfiguredLoginItem) }
    }

    /// Swallow scroll and gesture events while a gesture is engaged, so a twist
    /// does not also scroll the page. Needs Accessibility, and does nothing
    /// without it.
    @Published var blockScrollDuringGestures: Bool {
        didSet { defaults.set(blockScrollDuringGestures, forKey: Key.blockScrollDuringGestures) }
    }

    /// Three-finger twist to change tracks. Off by default: it needs
    /// Accessibility permission, and TwistPad needs nothing at all without it.
    @Published var trackControlEnabled: Bool {
        didSet { defaults.set(trackControlEnabled, forKey: Key.trackControlEnabled) }
    }

    /// A daily call to GitHub reveals that someone is running the app, so it's
    /// worth being able to switch off.
    @Published var automaticUpdateChecks: Bool {
        didSet { defaults.set(automaticUpdateChecks, forKey: Key.automaticUpdateChecks) }
    }

    static let defaultExclusions: [String] = [
        "com.apple.Preview",
        "com.apple.Photos",
        "com.apple.Maps",
        "com.apple.iWork.Keynote",
        "com.apple.iWork.Pages",
        "com.apple.FinalCut",
        "com.apple.Motion",
        "com.adobe.Photoshop",
        "com.adobe.illustrator",
        "com.adobe.AfterEffects",
        "com.figma.Desktop",
        "com.bohemiancoding.sketch3",
        "com.seriflabs.affinityphoto2",
        "com.seriflabs.affinitydesigner2",
        "org.blenderfoundation.blender",
        "com.pixelmatorteam.pixelmator.x",
    ]

    private init() {
        defaults.register(defaults: [
            Key.isEnabled: true,
            Key.degreesForFullSweep: 70.0,
            Key.activationThreshold: 8.0,
            Key.invertDirection: false,
            Key.detentCount: 16,
            Key.hapticsEnabled: true,
            Key.hudEnabled: true,
            Key.excludedBundleIDs: Settings.defaultExclusions,
            Key.automaticUpdateChecks: true,
            Key.trackControlEnabled: false,
            Key.blockScrollDuringGestures: true,
            Key.hasConfiguredLoginItem: false,
        ])

        isEnabled = defaults.bool(forKey: Key.isEnabled)
        degreesForFullSweep = defaults.double(forKey: Key.degreesForFullSweep)
        activationThreshold = defaults.double(forKey: Key.activationThreshold)
        invertDirection = defaults.bool(forKey: Key.invertDirection)
        detentCount = defaults.integer(forKey: Key.detentCount)
        hapticsEnabled = defaults.bool(forKey: Key.hapticsEnabled)
        hudEnabled = defaults.bool(forKey: Key.hudEnabled)
        excludedBundleIDs = defaults.stringArray(forKey: Key.excludedBundleIDs)
            ?? Settings.defaultExclusions
        automaticUpdateChecks = defaults.bool(forKey: Key.automaticUpdateChecks)
        trackControlEnabled = defaults.bool(forKey: Key.trackControlEnabled)
        blockScrollDuringGestures = defaults.bool(forKey: Key.blockScrollDuringGestures)
        hasConfiguredLoginItem = defaults.bool(forKey: Key.hasConfiguredLoginItem)
    }

    func resetExclusionsToDefault() {
        excludedBundleIDs = Settings.defaultExclusions
    }

    func resetAll() {
        isEnabled = true
        degreesForFullSweep = 70
        activationThreshold = 8
        invertDirection = false
        detentCount = 16
        hapticsEnabled = true
        hudEnabled = true
        excludedBundleIDs = Settings.defaultExclusions
        automaticUpdateChecks = true
        trackControlEnabled = false
        blockScrollDuringGestures = true
    }
}
