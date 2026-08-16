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
    private var isDraining = false

    // CoreAudio's change notification arrives after the write lands, so an
    // in-flight flag would already be clear by the time the echo shows up.
    private var lastSelfWrite: TimeInterval = 0
    private let selfWriteGrace: TimeInterval = 0.2

    private var deviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var volumeListenerBlock: AudioObjectPropertyListenerBlock?

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
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element)
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &addr, &settable) == noErr else { return false }
        return settable.boolValue
    }

    // MARK: - External change notifications

    private var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    private func installVolumeListener() {
        guard deviceID != kAudioObjectUnknown else { return }
        var addr = volumeAddress
        guard AudioObjectHasProperty(deviceID, &addr) else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.lock.lock()
            let elapsed = ProcessInfo.processInfo.systemUptime - self.lastSelfWrite
            self.lock.unlock()
            guard elapsed > self.selfWriteGrace else { return }
            self.onVolumeChangedExternally?()
        }
        volumeListenerBlock = block
        AudioObjectAddPropertyListenerBlock(deviceID, &addr, DispatchQueue.main, block)
    }

    private func removeVolumeListener() {
        guard let block = volumeListenerBlock, deviceID != kAudioObjectUnknown else { return }
        var addr = volumeAddress
        AudioObjectRemovePropertyListenerBlock(deviceID, &addr, DispatchQueue.main, block)
        volumeListenerBlock = nil
    }

    // MARK: - Reading

    func readVolume() -> Float? {
        guard deviceID != kAudioObjectUnknown else { return nil }

        let elements: [UInt32]
        switch strategy {
        case .master: elements = [kAudioObjectPropertyElementMain]
        case .channels(let ch): elements = ch
        case .unsupported: return nil
        }

        var total: Float = 0
        var count = 0
        for element in elements {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element)
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

    func readMute() -> Bool {
        guard deviceID != kAudioObjectUnknown else { return false }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
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
                isDraining = false
                lock.unlock()
                return
            }
            pendingWrite = nil
            lastSelfWrite = ProcessInfo.processInfo.systemUptime
            lock.unlock()

            performWrite(value)
        }
    }

    private func performWrite(_ value: Float) {
        guard deviceID != kAudioObjectUnknown else { return }

        let elements: [UInt32]
        switch strategy {
        case .master: elements = [kAudioObjectPropertyElementMain]
        case .channels(let ch): elements = ch
        case .unsupported: return
        }

        var scalar = Float32(value)
        for element in elements {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element)
            AudioObjectSetPropertyData(deviceID, &addr, 0, nil,
                                       UInt32(MemoryLayout<Float32>.size), &scalar)
        }
    }

    func setMute(_ muted: Bool) {
        guard deviceID != kAudioObjectUnknown else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(deviceID, &addr) else { return }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &addr, &settable) == noErr,
              settable.boolValue else { return }
        var flag: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(deviceID, &addr, 0, nil,
                                   UInt32(MemoryLayout<UInt32>.size), &flag)
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
