import AppKit
import Foundation

/// Watches raw trackpad contacts and emits `TwistSample`s for two- and
/// three-finger twists.
///
/// Two fingers drive the volume by twisting. Three fingers change tracks by
/// pinching: two fingers together plus the thumb, squeezed for the previous
/// track and spread for the next.
///
/// Three contacts is what makes the pinch safe to claim. macOS owns the
/// two-finger pinch for zoom, and its three-finger gestures are swipes, which
/// translate rather than change spread.
final class MultitouchDialSource {

    typealias Handler = (TwistSample) -> Void

    static let shared = MultitouchDialSource()

    private var handler: Handler?
    private var devices: [MTDeviceRef] = []
    private var deviceHandles: [AnyObject] = []
    private(set) var isRunning = false
    private var hasWakeObserver = false

    private var trackedIDs: Set<Int32> = []
    private var gestureContactCount = 0
    /// Two-finger state: orientation of the line between the contacts.
    private var previousLineAngle: Double?
    /// Three-finger state: each contact's bearing from the cluster centroid.
    private var previousBearings: [Int32: Double] = [:]
    private var previousSpread: Double?
    private var centroidAtTouchdown: (x: Double, y: Double)?
    private var maxCentroidDrift: Double = 0
    private var initialSeparation: Double = 0

    /// Which trackpad the in-flight gesture belongs to. With a built-in trackpad
    /// and a Magic Trackpad both attached, frames arrive from both devices and
    /// interleaving them would thrash the gesture state, so a gesture claims one
    /// device and frames from the other are ignored until it ends.
    private var gestureDevice: MTDeviceRef?

    private(set) var surfaceWidth: Double = 156
    private(set) var surfaceHeight: Double = 96
    /// Sensor size per device: a Magic Trackpad is not shaped like a built-in one,
    /// and the angle correction depends on it.
    private var surfaceSizes: [Int: (width: Double, height: Double)] = [:]

    /// Contact area above which a touch is a palm rather than a finger. Measured
    /// across 194 real contacts: fingers and thumbs peak around 0.9, palms come
    /// in at 1.27 and up. A resting palm counted as a contact turns a two-finger
    /// scroll into a three-contact pinch, which fires a track skip.
    private let maximumFingerSize: Float = 1.1

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
            Haptics.invalidateHardwareCache()
        }
    }

    private func deviceKey(_ device: MTDeviceRef) -> Int {
        Int(bitPattern: device)
    }

    // MARK: - Frame processing

    fileprivate func process(touches: [MTTouch], device: MTDeviceRef?) {
        // A gesture owns its trackpad until it finishes.
        if let gestureDevice, let device, gestureDevice != device { return }

        let touching = touches.filter { $0.state == kMTTouchStateTouching }
        let active = touching.filter { $0.zTotal <= maximumFingerSize }
        let palms = touching.count - active.count
        let count = active.count

        guard count == 2 || count == 3 else {
            if gestureDevice == nil || gestureDevice == device {
                if !trackedIDs.isEmpty {
                    GestureLog.record("abandoned: contacts went \(gestureContactCount) -> \(count)")
                }
                resetGesture(emitEnd: true)
            }
            return
        }

        if let device, let size = surfaceSizes[deviceKey(device)] {
            surfaceWidth = size.width
            surfaceHeight = size.height
        }

        // Everything below is in millimetres, never normalized units. The sensor
        // is far wider than it is deep, so a normalized distance means something
        // different depending on which way the fingers are lying: the same gap
        // reads about 1.6x larger stacked vertically than side by side. Gates
        // built on normalized values therefore leak vertical two-finger scrolls.
        let points = active.map { touch in
            (id: touch.pathIndex,
             x: Double(touch.normalized.position.x) * surfaceWidth,
             y: Double(touch.normalized.position.y) * surfaceHeight)
        }
        let centroid = (x: points.map(\.x).reduce(0, +) / Double(count),
                        y: points.map(\.y).reduce(0, +) / Double(count))

        // Mean radius doubled, so a three-finger spread is measured on the same
        // scale as the gap between two fingers.
        let spread = points
            .map { ((($0.x - centroid.x) * ($0.x - centroid.x))
                    + (($0.y - centroid.y) * ($0.y - centroid.y))).squareRoot() }
            .reduce(0, +) / Double(count)
        let separation = spread * 2

        let ids = Set(points.map(\.id))
        let bearings = Dictionary(uniqueKeysWithValues: points.map {
            ($0.id, atan2($0.y - centroid.y, $0.x - centroid.x) * 180 / .pi)
        })
        let lineAngle: Double? = count == 2 ? {
            let sorted = points.sorted { $0.id < $1.id }
            return atan2(sorted[1].y - sorted[0].y, sorted[1].x - sorted[0].x) * 180 / .pi
        }() : nil

        if ids != trackedIDs {
            resetGesture(emitEnd: true)
            gestureDevice = device
            trackedIDs = ids
            gestureContactCount = count
            previousLineAngle = lineAngle
            previousBearings = bearings
            previousSpread = separation
            centroidAtTouchdown = centroid
            maxCentroidDrift = 0
            initialSeparation = separation
            GestureLog.record(String(
                format: "start: contacts=%d sep=%.1fmm palmsIgnored=%d sizes=[%@]",
                count, separation, palms,
                active.map { String(format: "%.2f", $0.zTotal) }.joined(separator: ", ")))
            emit(delta: 0, spreadDelta: 0, phase: .began)
            return
        }

        let delta: Double
        if count == 2 {
            guard let previous = previousLineAngle, let current = lineAngle else {
                previousLineAngle = lineAngle
                return
            }
            // Two fingers define an *undirected* line, so its orientation is only
            // meaningful mod 180. Tracking a full 360 vector produces a phantom
            // 180 jump the moment the pair rotates past the axis, which reads as
            // the volume slamming end to end.
            var d = current - previous
            while d > 90 { d -= 180 }
            while d < -90 { d += 180 }
            delta = d
            previousLineAngle = current
        } else {
            // Three or more contacts each have a real bearing from the centroid,
            // so there is no 180 ambiguity. Averaging their rotation is steadier
            // than tracking any single pair.
            var total = 0.0
            var counted = 0
            for (id, bearing) in bearings {
                guard let previous = previousBearings[id] else { continue }
                var d = bearing - previous
                while d > 180 { d -= 360 }
                while d < -180 { d += 360 }
                total += d
                counted += 1
            }
            previousBearings = bearings
            guard counted > 0 else { return }
            delta = total / Double(counted)
        }

        if let origin = centroidAtTouchdown {
            let driftX = centroid.x - origin.x
            let driftY = centroid.y - origin.y
            maxCentroidDrift = max(maxCentroidDrift,
                                   (driftX * driftX + driftY * driftY).squareRoot())
        }

        let spreadDelta = separation - (previousSpread ?? separation)
        previousSpread = separation

        emit(delta: delta, spreadDelta: spreadDelta, phase: .changed)
    }

    private func emit(delta: Double, spreadDelta: Double, phase: GesturePhase) {
        handler?(TwistSample(deltaDegrees: delta,
                             centroidDrift: maxCentroidDrift,
                             initialSeparation: initialSeparation,
                             spreadDeltaMM: spreadDelta,
                             contactCount: gestureContactCount,
                             phase: phase))
    }

    private func resetGesture(emitEnd: Bool) {
        let hadGesture = !trackedIDs.isEmpty
        trackedIDs = []
        previousLineAngle = nil
        previousBearings = [:]
        previousSpread = nil
        centroidAtTouchdown = nil
        gestureDevice = nil

        // Ends with the count the gesture actually had, so going from two
        // fingers to three closes the volume gesture rather than the track one.
        if emitEnd && hadGesture {
            emit(delta: 0, spreadDelta: 0, phase: .ended)
        }
        gestureContactCount = 0
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
