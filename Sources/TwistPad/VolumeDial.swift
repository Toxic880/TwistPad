import AppKit
import Combine

/// Ties the twist gesture to the system volume.
final class VolumeDial: ObservableObject, DialRecognizerDelegate {

    @Published private(set) var volumeLevel: Float = 0
    @Published private(set) var isMuted: Bool = false
    @Published private(set) var isEngaged: Bool = false
    /// Live rotation of the in-flight gesture, for the calibration readout.
    @Published private(set) var liveTwistDegrees: Double = 0

    let volumeController = VolumeController()

    private let recognizer = DialRecognizer()
    private let source = MultitouchDialSource.shared
    private let settings = Settings.shared

    private var isSuppressed = false
    private var baseVolume: Float = 0
    private var accumulatedDegrees: Double = 0
    private var currentStepIndex: Int?
    private var cancellables = Set<AnyCancellable>()

    var isSupported: Bool { source.isSupported }
    var canControlVolume: Bool { volumeController.isAvailable }
    var outputDeviceName: String { volumeController.deviceName }

    var onEngagementChanged: ((Bool) -> Void)?

    init() {
        recognizer.delegate = self
        syncFromSystem()

        volumeController.onVolumeChangedExternally = { [weak self] in
            self?.syncFromSystem()
        }
        volumeController.onDeviceChanged = { [weak self] in
            self?.syncFromSystem()
        }

        applyTuning()

        // `receive(on:)` defers past the willSet, so the new value is committed.
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyTuning() }
            .store(in: &cancellables)
    }

    private func applyTuning() {
        recognizer.activationThreshold = settings.activationThreshold
        if !settings.isEnabled && recognizer.isEngaged {
            recognizer.abort()
        }
    }

    @discardableResult
    func start() -> Bool {
        source.start { [weak self] sample in
            self?.recognizer.handle(sample)
        }
    }

    func stop() {
        source.stop()
    }

    func syncFromSystem() {
        volumeLevel = volumeController.readVolume() ?? 0
        isMuted = volumeController.readMute()
    }

    // MARK: - DialRecognizerDelegate

    func dialDidEngage(_ recognizer: DialRecognizer) {
        guard settings.isEnabled, canControlVolume, !isExcludedAppFrontmost() else {
            isSuppressed = true
            return
        }

        isSuppressed = false
        // Read live, so the dial respects media keys pressed since last time.
        baseVolume = volumeController.readVolume() ?? 0
        if volumeController.readMute() { baseVolume = 0 }
        accumulatedDegrees = 0
        liveTwistDegrees = 0
        currentStepIndex = settings.detentCount > 0
            ? Int((Double(baseVolume) * Double(settings.detentCount)).rounded())
            : nil

        isEngaged = true
        onEngagementChanged?(true)
    }

    func dial(_ recognizer: DialRecognizer, didRotateBy degrees: Double) {
        guard !isSuppressed else { return }

        accumulatedDegrees += degrees
        liveTwistDegrees = accumulatedDegrees

        // Rotation is positive counter-clockwise; a knob gets louder clockwise.
        let direction: Double = settings.invertDirection ? 1 : -1
        let sweep = max(settings.degreesForFullSweep, 10)
        let target = min(max(baseVolume + Float(direction * accumulatedDegrees / sweep), 0), 1)

        if settings.detentCount > 0 {
            applyDetented(target)
        } else {
            applyContinuous(target)
        }
    }

    func dialDidDisengage(_ recognizer: DialRecognizer) {
        isSuppressed = false
        accumulatedDegrees = 0
        liveTwistDegrees = 0
        currentStepIndex = nil

        guard isEngaged else { return }
        isEngaged = false
        onEngagementChanged?(false)
    }

    // MARK: - Applying the value

    private func applyDetented(_ target: Float) {
        let steps = settings.detentCount
        let raw = Double(target) * Double(steps)
        // Hysteresis, so resting on a boundary doesn't chatter between steps.
        let hysteresis = 0.15

        var index = currentStepIndex ?? Int(raw.rounded())
        while raw > Double(index) + 0.5 + hysteresis { index += 1 }
        while raw < Double(index) - 0.5 - hysteresis { index -= 1 }
        index = min(max(index, 0), steps)

        guard index != currentStepIndex else { return }
        let wasAtLimit = currentStepIndex == 0 || currentStepIndex == steps
        currentStepIndex = index

        commit(Float(index) / Float(steps))

        if settings.hapticsEnabled {
            if (index == 0 || index == steps) && !wasAtLimit {
                Haptics.limitTap()
            } else {
                Haptics.detentClick()
            }
        }
    }

    private func applyContinuous(_ target: Float) {
        guard abs(target - volumeLevel) > 0.002 else { return }
        commit(target)
    }

    private func commit(_ value: Float) {
        volumeController.setVolume(value)
        volumeLevel = value

        // Turning the dial up off zero unmutes, or someone who hit F10 twists up
        // and still hears nothing. Only on the transition: doing it inside every
        // write meant a second CoreAudio call per frame, 120 times a second.
        if isMuted && value > 0 {
            isMuted = false
            volumeController.setMute(false)
        }
    }

    private func isExcludedAppFrontmost() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return settings.excludedBundleIDs.contains(bundleID)
    }
}
