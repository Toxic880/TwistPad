import AppKit
import Foundation

/// Watches raw trackpad contacts and emits `TwistSample`s for two-finger gestures.
final class MultitouchDialSource {

    typealias Handler = (TwistSample) -> Void

    static let shared = MultitouchDialSource()

    private var handler: Handler?
    private var devices: [MTDeviceRef] = []
    private var deviceHandles: [AnyObject] = []
    private(set) var isRunning = false
    private var hasWakeObserver = false

    private var trackedPair: Set<Int32> = []
    private var previousAngle: Double?
    private var centroidAtTouchdown: (x: Double, y: Double)?
    private var maxCentroidDrift: Double = 0
    private var initialSeparation: Double = 0

    /// Which trackpad the in-flight gesture belongs to. With a built-in trackpad
    /// and a Magic Trackpad both attached, frames arrive from both devices and
    /// interleaving them would thrash the gesture state, so a gesture claims one
    /// device and frames from the other are ignored until it ends.
    private var gestureDevice: MTDeviceRef?

    private(set) var surfaceWidth: Double = 160
    private(set) var surfaceHeight: Double = 100
    /// Sensor size per device: a Magic Trackpad is not shaped like a built-in one,
    /// and the angle correction depends on it.
    private var surfaceSizes: [Int: (width: Double, height: Double)] = [:]

    private init() {}

    var isSupported: Bool { MultitouchSupport.isAvailable }
    var deviceCount: Int { devices.count }

    // MARK: - Lifecycle

    @discardableResult
    func start(handler: @escaping Handler) -> Bool {
        guard MultitouchSupport.isAvailable else { return false }
        guard !isRunning else {
            self.handler = handler
            return true
        }

        self.handler = handler
        let found = MultitouchSupport.allDevices()
        deviceHandles = found.handles
        devices = found.refs
        guard !devices.isEmpty else { return false }

        for device in devices {
            surfaceSizes[deviceKey(device)] = MultitouchSupport.surfaceSize(of: device)
            MultitouchSupport.registerContactFrameCallback?(device, multitouchContactCallback)
            MultitouchSupport.startDevice?(device, 0)
        }
        if let first = devices.first, let size = surfaceSizes[deviceKey(first)] {
            surfaceWidth = size.width
            surfaceHeight = size.height
        }

        activeDialSource = self
        isRunning = true
        observeWake()
        return true
    }

    func stop() {
        guard isRunning else { return }
        for device in devices {
            MultitouchSupport.stopDevice?(device)
            MultitouchSupport.unregisterContactFrameCallback?(device, multitouchContactCallback)
        }
        devices = []
        deviceHandles = []
        surfaceSizes = [:]
        isRunning = false
        if activeDialSource === self { activeDialSource = nil }
        resetGesture(emitEnd: true)
    }

    /// Devices stop delivering frames across sleep, so registration is rebuilt on
    /// wake. Added once: `start` runs again on every wake and would compound.
    private func observeWake() {
        guard !hasWakeObserver else { return }
        hasWakeObserver = true
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, let handler = self.handler else { return }
            self.stop()
            self.start(handler: handler)
        }
    }

    private func deviceKey(_ device: MTDeviceRef) -> Int {
        Int(bitPattern: device)
    }

    // MARK: - Frame processing

    fileprivate func process(touches: [MTTouch], device: MTDeviceRef?) {
        // A gesture owns its trackpad until it finishes.
        if let gestureDevice, let device, gestureDevice != device { return }

        let active = touches.filter { $0.state == kMTTouchStateTouching }

        guard active.count == 2 else {
            if gestureDevice == nil || gestureDevice == device {
                resetGesture(emitEnd: true)
            }
            return
        }

        let sorted = active.sorted { $0.pathIndex < $1.pathIndex }
        let ids = Set(sorted.map(\.pathIndex))
        let a = sorted[0]
        let b = sorted[1]

        if let device, let size = surfaceSizes[deviceKey(device)] {
            surfaceWidth = size.width
            surfaceHeight = size.height
        }

        // Everything below is in millimetres, never normalized units. The sensor
        // is far wider than it is deep, so a normalized distance means something
        // different depending on which way the fingers are lying: the same gap
        // reads about 1.6x larger stacked vertically than side by side. Gates
        // built on normalized values therefore leak vertical two-finger scrolls.
        let dx = Double(b.normalized.position.x - a.normalized.position.x) * surfaceWidth
        let dy = Double(b.normalized.position.y - a.normalized.position.y) * surfaceHeight
        let separation = (dx * dx + dy * dy).squareRoot()
        let angle = atan2(dy, dx) * 180 / .pi
        let centroid = (x: Double(a.normalized.position.x + b.normalized.position.x) / 2,
                        y: Double(a.normalized.position.y + b.normalized.position.y) / 2)

        if ids != trackedPair {
            resetGesture(emitEnd: true)
            gestureDevice = device
            trackedPair = ids
            previousAngle = angle
            centroidAtTouchdown = centroid
            maxCentroidDrift = 0
            initialSeparation = separation
            handler?(TwistSample(deltaDegrees: 0,
                                 centroidDrift: 0,
                                 initialSeparation: separation,
                                 phase: .began))
            return
        }

        guard let previous = previousAngle else {
            previousAngle = angle
            return
        }

        // Two fingers define an *undirected* line, so its orientation is only
        // meaningful mod 180. Tracking a full 360 vector produces a phantom 180
        // jump the moment the pair rotates past the axis, which reads as the
        // volume slamming end to end.
        var delta = angle - previous
        while delta > 90 { delta -= 180 }
        while delta < -90 { delta += 180 }
        previousAngle = angle

        if let origin = centroidAtTouchdown {
            let driftX = (centroid.x - origin.x) * surfaceWidth
            let driftY = (centroid.y - origin.y) * surfaceHeight
            maxCentroidDrift = max(maxCentroidDrift,
                                   (driftX * driftX + driftY * driftY).squareRoot())
        }

        handler?(TwistSample(deltaDegrees: delta,
                             centroidDrift: maxCentroidDrift,
                             initialSeparation: initialSeparation,
                             phase: .changed))
    }

    private func resetGesture(emitEnd: Bool) {
        let hadGesture = !trackedPair.isEmpty
        trackedPair = []
        previousAngle = nil
        centroidAtTouchdown = nil
        gestureDevice = nil

        if emitEnd && hadGesture {
            handler?(TwistSample(deltaDegrees: 0,
                                 centroidDrift: maxCentroidDrift,
                                 initialSeparation: initialSeparation,
                                 phase: .ended))
        }
        maxCentroidDrift = 0
        initialSeparation = 0
    }
}

// The framework callback is a bare C function pointer with no context argument.
private weak var activeDialSource: MultitouchDialSource?

private let multitouchContactCallback: MTContactCallback = { device, touchesPtr, count, _, _ in
    guard count >= 0 else { return 0 }

    var touches: [MTTouch] = []
    if let raw = touchesPtr, count > 0 {
        let bound = raw.bindMemory(to: MTTouch.self, capacity: Int(count))
        touches = (0..<Int(count)).map { bound[$0] }
    }

    DispatchQueue.main.async {
        activeDialSource?.process(touches: touches, device: device)
    }
    return 0
}
