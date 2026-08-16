# TwistPad

Twist two fingers on your trackpad — thumb and index, like turning a dial — to set
your Mac's volume. Detented, with a haptic click at every step.

```bash
git clone https://github.com/Toxic880/TwistPad.git
cd TwistPad
./build.sh
open TwistPad.app
```

Menu bar only — no Dock icon. Requires macOS 14+ and a multitouch trackpad.
**No permissions needed:** not Accessibility, not Input Monitoring.

---

## Why it isn't built on the public API

macOS has a public two-finger rotation gesture (`NSEvent.EventType.rotate`), and
it's the obvious foundation. It cannot be used here.

Measured while building this: across **8,782 multitouch frames containing 48
deliberate thumb-and-index twists, a global `.rotate` monitor fired zero times**,
while 131 `.scrollWheel` events came through. macOS arbitrates scroll-vs-rotate
*before* emitting an event, and for this hand shape it commits to scroll every
time. There's no threshold to tune, because no event ever arrives.

So TwistPad reads raw trackpad contacts from the private `MultitouchSupport`
framework, resolved at runtime with `dlopen`/`dlsym` — the same approach
BetterTouchTool and Jitouch take. `MTTouch` is 96 bytes on arm64 and the layout is
verified at launch; if a future macOS changes it, TwistPad reports that it can't
read the trackpad instead of misbehaving.

## Telling a twist from a scroll

Two fingers resting on a trackpad are ambiguous. Measured over 48 twists and 21
scrolls:

| signal                  | twists      | scrolls     |
| ----------------------- | ----------- | ----------- |
| peak rotation           | 20.9°…183°  | 0.1°…18.9°  |
| centroid drift          | ≤ 0.11      | up to 0.24  |
| separation at touchdown | 0.20…0.59   | 0.14…0.18   |

Rotation alone separates the two populations by about **2°** — nowhere near enough
to rely on. All three signals have to agree:

- **Rotation** clears the dead zone (default 8°).
- **Centroid drift** stays low *while arming*. Twisting barely moves the midpoint
  between your fingers; scrolling drags it. This stops applying once engaged,
  because a long twist naturally wanders.
- **Stance width** looks like thumb-and-index. Too narrow is an index-and-middle
  scroll; too wide is a palm, or two hands.

A contact that fails a check is rejected for the rest of the touch, so a scroll
can't sneak in by rotating slightly at the end.

## The 180° trap

Worth calling out, because the naive implementation looks correct and fails badly.

Two fingers define an **undirected line**. Its orientation is only meaningful
modulo 180°. Pair the contacts by position (say, sorted by x) and track a full
360° vector, and the moment a twist carries the pair through the sort axis the
ordering swaps and the measured angle jumps 180° in one frame — which reads as the
volume slamming from one end to the other.

The fix is two-part: pair contacts by `pathIndex`, which is stable for the life of
a contact, and unwrap every delta into ±90°.

## Feel

**Range of motion is the binding constraint.** A natural thumb-and-index twist has
a median of 60°, so the full sweep defaults to **70°** with an **8°** dead zone —
one comfortable turn covers the whole range without re-gripping.

- **16 detents** by default, matching the volume keys, with a `levelChange` haptic
  per step and a firmer `alignment` tap at 0% and 100% so you feel the ends.
- **Clockwise raises the volume**, like every physical knob. Reversible.
- **Anchors to live system volume** on each engage, so it respects the media keys.
- **The dead zone is spent, not applied** — the first 8° arms the gesture without
  moving anything, which reads as the free play at the start of a real knob.

The on-screen dial is segmented, one segment per detent, so what lights up is
exactly what you felt click under your fingers. Everything is tunable in Settings,
including a live readout of how far you're actually twisting.

## Layout

```
Sources/TwistPad/
├── main.swift                     entry point, .accessory activation policy
├── AppDelegate.swift              wiring, settings window
├── VolumeDial.swift               rotation → volume, detents, haptics
├── Gesture/
│   ├── MultitouchSupport.swift    private framework ABI, resolved at runtime
│   ├── MultitouchDialSource.swift contacts → TwistSample, angle unwrapping
│   └── DialRecognizer.swift       twist-vs-scroll state machine
├── Audio/VolumeController.swift   CoreAudio, coalesced writes
├── UI/                            HUD, menu bar icon, settings
└── Support/                       settings, haptics, login item
```

The recognizer consumes `TwistSample` values rather than multitouch structs, so the
input path can be swapped without touching the gesture logic.

**Writes are coalesced.** A twist produces up to 120 updates/second, and
`AudioObjectSetPropertyData` round-trips over the link for Bluetooth and AirPlay
where it can block for milliseconds. Writes go latest-wins onto a serial queue, so
a slow device drops intermediate values instead of stuttering the HUD.

**Not every device has a master volume control.** Built-in speakers do; many USB
and aggregate devices only expose per-channel controls, and some digital outputs
expose none. The strategy is probed per device.

## Limitations

- **Private API.** A macOS update could change the `MTTouch` layout or remove the
  symbols. TwistPad degrades to "can't read the trackpad" rather than crashing.
- **Apps that use rotation themselves.** Because contacts are read at the driver
  level, TwistPad can't consume the event — Preview would rotate an image *and*
  change the volume. Those apps are excluded by bundle ID instead (editable in
  Settings → Apps). Consuming the event would need a CGEventTap and the
  Accessibility permission that currently isn't required at all.
- **Ad-hoc signed**, not notarized. First launch may need right-click → Open.
- **Open at Login** registers the app at its current path, so re-toggle it if you
  move `TwistPad.app`.

## License

MIT
