import Foundation

// Runtime bindings for the private MultitouchSupport framework. The public
// NSEvent.rotate gesture is not usable here: macOS arbitrates scroll-vs-rotate
// before emitting, and never emits rotation for a thumb-and-index twist.

typealias MTDeviceRef = UnsafeMutableRawPointer

struct MTPoint {
    var x: Float = 0
    var y: Float = 0
}

struct MTVector {
    var position = MTPoint()
    var velocity = MTPoint()
}

/// Must stay 96 bytes on arm64; checked by `MultitouchSupport.isLayoutSane`.
struct MTTouch {
    var frame: Int32 = 0
    var timestamp: Double = 0
    /// Stable for the life of one contact. Pair fingers by this, never by order.
    var pathIndex: Int32 = 0
    var state: Int32 = 0
    var fingerID: Int32 = 0
    var handID: Int32 = 0
    var normalized = MTVector()
    var zTotal: Float = 0
    var unknown1: Int32 = 0
    var angle: Float = 0
    var majorAxis: Float = 0
    var minorAxis: Float = 0
    var absoluteVector = MTVector()
    var unknown2: Int32 = 0
    var unknown3: Int32 = 0
    var zDensity: Float = 0
}

let kMTTouchStateTouching: Int32 = 4

/// Swift structs are not C-representable in `@convention(c)`, so touches arrive
/// as a raw pointer and are bound at the call site.
typealias MTContactCallback = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
) -> Int32

enum MultitouchSupport {

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
        RTLD_LAZY)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    static let createDefaultDevice =
        symbol("MTDeviceCreateDefault", as: (@convention(c) () -> MTDeviceRef?).self)

    static let createDeviceList =
        symbol("MTDeviceCreateList", as: (@convention(c) () -> CFArray?).self)

    static let registerContactFrameCallback =
        symbol("MTRegisterContactFrameCallback",
               as: (@convention(c) (MTDeviceRef, MTContactCallback) -> Void).self)

    static let unregisterContactFrameCallback =
        symbol("MTUnregisterContactFrameCallback",
               as: (@convention(c) (MTDeviceRef, MTContactCallback) -> Void).self)

    static let startDevice =
        symbol("MTDeviceStart", as: (@convention(c) (MTDeviceRef, Int32) -> Void).self)

    static let stopDevice =
        symbol("MTDeviceStop", as: (@convention(c) (MTDeviceRef) -> Void).self)

    static let getSensorSurfaceDimensions =
        symbol("MTDeviceGetSensorSurfaceDimensions",
               as: (@convention(c) (MTDeviceRef, UnsafeMutablePointer<Int32>,
                                    UnsafeMutablePointer<Int32>) -> Void).self)

    static let getDeviceID = symbol("MTDeviceGetDeviceID",
        as: (@convention(c) (MTDeviceRef, UnsafeMutablePointer<UInt64>) -> Int32).self)

    /// Returns the actuator directly. It is not an out-parameter call, and
    /// treating it as one reads the low half of the pointer as an error code.
    static let actuatorCreateFromDeviceID = symbol("MTActuatorCreateFromDeviceID",
        as: (@convention(c) (UInt64) -> UnsafeMutableRawPointer?).self)

    static let actuatorOpen = symbol("MTActuatorOpen",
        as: (@convention(c) (UnsafeMutableRawPointer) -> Int32).self)

    static let actuatorClose = symbol("MTActuatorClose",
        as: (@convention(c) (UnsafeMutableRawPointer) -> Int32).self)

    /// Whether this trackpad has a Taptic Engine at all. Opening an actuator
    /// succeeds only on hardware that can actually produce feedback, so it is a
    /// far better test than assuming every Mac can.
    static func hasHapticHardware() -> Bool {
        guard let device = allDevices().refs.first,
              let readID = getDeviceID,
              let create = actuatorCreateFromDeviceID,
              let open = actuatorOpen else { return false }

        var deviceID: UInt64 = 0
        guard readID(device, &deviceID) == 0 else { return false }
        guard let actuator = create(deviceID) else { return false }

        let opened = open(actuator) == 0
        if opened { _ = actuatorClose?(actuator) }
        return opened
    }

    static var isLayoutSane: Bool { MemoryLayout<MTTouch>.size == 96 }

    static var isAvailable: Bool {
        handle != nil
            && registerContactFrameCallback != nil
            && startDevice != nil
            && isLayoutSane
            && (createDefaultDevice != nil || createDeviceList != nil)
    }

    /// `handles` must be retained by the caller — the devices are owned by that
    /// array, so keeping only raw pointers would leave them dangling.
    static func allDevices() -> (handles: [AnyObject], refs: [MTDeviceRef]) {
        if let list = createDeviceList?() as? [AnyObject], !list.isEmpty {
            return (list, list.map { Unmanaged.passUnretained($0).toOpaque() })
        }
        if let device = createDefaultDevice?() {
            return ([], [device])
        }
        return ([], [])
    }

    /// Sensor surface in millimetres, falling back to typical trackpad proportions.
    static func surfaceSize(of device: MTDeviceRef) -> (width: Double, height: Double) {
        guard let query = getSensorSurfaceDimensions else { return (160, 100) }
        var width: Int32 = 0
        var height: Int32 = 0
        query(device, &width, &height)
        guard width > 0, height > 0 else { return (160, 100) }
        return (Double(width) / 100, Double(height) / 100)
    }
}
