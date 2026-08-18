import CoreAudio
import Foundation

/// Reads and writes the system output volume.
///
/// Writes are coalesced latest-wins onto a serial queue: a twist produces up to
/// 120 updates a second, and `AudioObjectSetPropertyData` round-trips over the
/// link for Bluetooth and AirPlay devices where it can block for milliseconds.
final class VolumeController {

    enum Strategy {
        case master
        /// No master control; drive these channel elements individually.
        case channels([UInt32])
        /// No settable volume at all (HDMI, optical, some interfaces).
        case unsupported
    }

    private(set) var deviceID: AudioDeviceID = kAudioObjectUnknown
    private(set) var strategy: Strategy = .unsupported

    var onDeviceChanged: (() -> Void)?
    var onVolumeChangedExternally: (() -> Void)?

    private let writeQueue = DispatchQueue(label: "com.lukek.TwistPad.volume-write",
                                           qos: .userInteractive)
    private let lock = NSLock()
    private var pendingWrite: Float?
    /// The value `performWrite` is busy sending, if any.
    private var inFlightWrite: Float?
    /// The last value that finished writing, and when.
    private var lastCommandedValue: Float?
    private var lastWriteFinished: TimeInterval = 0
    private var isDraining = false

    // CoreAudio's change notification arrives after the write lands, so an
    // in-flight flag would already be clear by the time the echo shows up.
    private var lastSelfWrite: TimeInterval = 0
    private let selfWriteGrace: TimeInterval = 0.2

    /// How long the last value written stays authoritative over a fresh read.
    /// Long enough to cover a device that has not caught up yet, short enough
    /// that a media key pressed straight afterwards still wins.
    private let settleGrace: TimeInterval = 0.3

    private var deviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var volumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var muteListenerBlock: AudioObjectPropertyListenerBlock?
    /// Exactly what was registered, so the same addresses come back off again.
    private var observedVolumeElements: [UInt32] = []
    private var observesMute = false

    var isAvailable: Bool {
        if case .unsupported = strategy { return false }
        return deviceID != kAudioObjectUnknown
    }

    init() {
        refreshDevice()
        installDefaultDeviceListener()
    }

    deinit {
        removeVolumeListener()
        removeDefaultDeviceListener()
    }

    // MARK: - Device tracking

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private func installDefaultDeviceListener() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshDevice()
                self.onDeviceChanged?()
            }
        }
        deviceListenerBlock = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                           &Self.defaultOutputAddress,
                                           DispatchQueue.main, block)
    }

    private func removeDefaultDeviceListener() {
        guard let block = deviceListenerBlock else { return }
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                              &Self.defaultOutputAddress,
                                              DispatchQueue.main, block)
        deviceListenerBlock = nil
    }

    private func refreshDevice() {
        removeVolumeListener()

        // Nothing cached survives a device change: a queued write belongs to the
        // old device's scale, and the level it was heading for says nothing about
        // the new one.
        lock.lock()
        pendingWrite = nil
        lastCommandedValue = nil
        lock.unlock()

        var dev = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                             &Self.defaultOutputAddress,
                                             0, nil, &size, &dev)
        guard err == noErr else {
            deviceID = kAudioObjectUnknown
            strategy = .unsupported
            return
        }

        deviceID = dev
        strategy = Self.probeStrategy(for: dev)
        installVolumeListener()
    }

    private static func probeStrategy(for device: AudioDeviceID) -> Strategy {
        if isSettable(device, element: kAudioObjectPropertyElementMain) {
            return .master
        }

        // Not always {1, 2}: aggregate devices can map elsewhere.
        var stereo: [UInt32] = [1, 2]
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &addr) {
            var pair: (UInt32, UInt32) = (1, 2)
            var size = UInt32(MemoryLayout<(UInt32, UInt32)>.size)
            if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &pair) == noErr {
                stereo = [pair.0, pair.1]
            }
        }

        let usable = stereo.filter { isSettable(device, element: $0) }
        return usable.isEmpty ? .unsupported : .channels(usable)
    }

    private static func isSettable(_ device: AudioDeviceID, element: UInt32) -> Bool {
        var addr = volumeAddress(element: element)
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &addr, &settable) == noErr else { return false }
        return settable.boolValue
    }

    // MARK: - Addresses

    private static func volumeAddress(element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element)
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    /// The elements this device's volume actually lives on.
    private var volumeElements: [UInt32] {
        switch strategy {
        case .master: return [kAudioObjectPropertyElementMain]
        case .channels(let ch): return ch
        case .unsupported: return []
        }
    }

    // MARK: - External change notifications

    private func installVolumeListener() {
        guard deviceID != kAudioObjectUnknown else { return }

        // Every element the volume lives on, not just the main one. A device with
        // no master control reports its changes per channel, so listening only on
        // main means media keys and other apps move the volume without TwistPad
        // ever hearing about it.
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, !self.isEchoOfOwnWrite() else { return }
            self.onVolumeChangedExternally?()
        }
        volumeListenerBlock = block

        for element in volumeElements {
            var addr = Self.volumeAddress(element: element)
            guard AudioObjectHasProperty(deviceID, &addr) else { continue }
            AudioObjectAddPropertyListenerBlock(deviceID, &addr, DispatchQueue.main, block)
            observedVolumeElements.append(element)
        }

        // Mute is a separate property and used to go unwatched entirely, so
        // muting with F10 left the menu bar icon and the HUD showing sound.
        var mute = Self.muteAddress
        if AudioObjectHasProperty(deviceID, &mute) {
            let muteBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self, !self.isEchoOfOwnWrite() else { return }
                self.onVolumeChangedExternally?()
            }
            muteListenerBlock = muteBlock
            AudioObjectAddPropertyListenerBlock(deviceID, &mute, DispatchQueue.main, muteBlock)
            observesMute = true
        }
    }

    private func removeVolumeListener() {
        guard deviceID != kAudioObjectUnknown else {
            observedVolumeElements = []
            observesMute = false
            volumeListenerBlock = nil
            muteListenerBlock = nil
            return
        }

        if let block = volumeListenerBlock {
            for element in observedVolumeElements {
                var addr = Self.volumeAddress(element: element)
                AudioObjectRemovePropertyListenerBlock(deviceID, &addr,
                                                       DispatchQueue.main, block)
            }
        }
        if let block = muteListenerBlock, observesMute {
            var mute = Self.muteAddress
            AudioObjectRemovePropertyListenerBlock(deviceID, &mute, DispatchQueue.main, block)
        }
        observedVolumeElements = []
        observesMute = false
        volumeListenerBlock = nil
        muteListenerBlock = nil
    }

    /// Whether a notification is just our own write coming back. Also drops the
    /// cached value when it is not, so a media key immediately takes over from
    /// what TwistPad last wrote.
    private func isEchoOfOwnWrite() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let elapsed = ProcessInfo.processInfo.systemUptime - lastSelfWrite
        if elapsed > selfWriteGrace {
            lastCommandedValue = nil
            return false
        }
        return true
    }

    // MARK: - Reading

    func readVolume() -> Float? {
        guard deviceID != kAudioObjectUnknown else { return nil }

        let elements = volumeElements
        guard !elements.isEmpty else { return nil }

        var total: Float = 0
        var count = 0
        for element in elements {
            var addr = Self.volumeAddress(element: element)
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &value) == noErr {
                total += value
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return min(max(total / Float(count), 0), 1)
    }

    /// Where the volume is heading, which is not always where it is.
    ///
    /// Writes are queued and the device applies them in its own time, so asking
    /// the hardware mid-flight hands back whatever it still holds — for Bluetooth
    /// and AirPlay, milliseconds behind. Starting a second twist off that stale
    /// reading drags the volume back to where the previous one began, which is
    /// the "it won't go up until I twist down and up again" stall. Falls through
    /// to a real read once the writes have settled, so a media key pressed in
    /// between is still respected.
    func currentVolume() -> Float? {
        lock.lock()
        if let queued = pendingWrite ?? inFlightWrite {
            lock.unlock()
            return queued
        }
        let recent = lastCommandedValue
        let sinceWrite = ProcessInfo.processInfo.systemUptime - lastWriteFinished
        lock.unlock()

        if let recent, sinceWrite < settleGrace { return recent }
        return readVolume()
    }

    func readMute() -> Bool {
        guard deviceID != kAudioObjectUnknown else { return false }
        var addr = Self.muteAddress
        guard AudioObjectHasProperty(deviceID, &addr) else { return false }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &muted) == noErr else {
            return false
        }
        return muted != 0
    }

    // MARK: - Writing

    func setVolume(_ value: Float) {
        let clamped = min(max(value, 0), 1)

        lock.lock()
        pendingWrite = clamped
        let alreadyDraining = isDraining
        isDraining = true
        lock.unlock()

        guard !alreadyDraining else { return }
        writeQueue.async { [weak self] in self?.drain() }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let value = pendingWrite else {
                inFlightWrite = nil
                isDraining = false
                lock.unlock()
                return
            }
            pendingWrite = nil
            inFlightWrite = value
            lastSelfWrite = ProcessInfo.processInfo.systemUptime
            lock.unlock()

            performWrite(value)

            // Stamped again on the way out. The write itself can block for
            // milliseconds on a Bluetooth device and CoreAudio's echo follows
            // that, not the moment the call went in — stamping only on entry
            // lets a slow write's own echo look like somebody else's change.
            lock.lock()
            let now = ProcessInfo.processInfo.systemUptime
            lastSelfWrite = now
            lastWriteFinished = now
            lastCommandedValue = value
            lock.unlock()
        }
    }

    private func performWrite(_ value: Float) {
        guard deviceID != kAudioObjectUnknown else { return }

        var scalar = Float32(value)
        for element in volumeElements {
            var addr = Self.volumeAddress(element: element)
            AudioObjectSetPropertyData(deviceID, &addr, 0, nil,
                                       UInt32(MemoryLayout<Float32>.size), &scalar)
        }
    }

    func setMute(_ muted: Bool) {
        guard deviceID != kAudioObjectUnknown else { return }
        var addr = Self.muteAddress
        guard AudioObjectHasProperty(deviceID, &addr) else { return }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &addr, &settable) == noErr,
              settable.boolValue else { return }

        // Stamped so the mute listener recognises the echo as ours.
        lock.lock()
        lastSelfWrite = ProcessInfo.processInfo.systemUptime
        lock.unlock()

        var flag: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(deviceID, &addr, 0, nil,
                                   UInt32(MemoryLayout<UInt32>.size), &flag)
    }

    var strategyDescription: String {
        switch strategy {
        case .master: return "master channel"
        case .channels(let elements): return "per-channel \(elements)"
        case .unsupported: return "none available"
        }
    }

    var deviceName: String {
        guard deviceID != kAudioObjectUnknown else { return "No output device" }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let err = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, $0)
        }
        return err == noErr ? (name as String) : "Output device"
    }
}
