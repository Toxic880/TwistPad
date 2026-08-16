# TwistPad

Twist two fingers on your trackpad like you're turning a dial, and the volume follows. Thumb and index works best.

It clicks as it turns. 16 haptic detents across the range, so it actually feels like a knob instead of a gesture.

## Install

```bash
git clone https://github.com/Toxic880/TwistPad.git
cd TwistPad
./build.sh
open TwistPad.app
```

It lives in the menu bar. You need macOS 14 or newer and a trackpad.

## How it feels

Your wrist is the limit here, not the software. I measured how far a hand actually twists before it gets awkward and the median came out around 60°, so a full sweep from silent to max is set to 70° by default. One comfortable turn covers the whole range and you never have to re-grip.

* Clockwise turns it up, like every volume knob ever made. Flip it in settings if you're wired backwards.
* 16 detents by default, the same granularity as the volume keys. Every one gives you a haptic tick, and you get a firmer tap at 0 and 100 so you can feel the ends without looking.
* The first 8° of twist does nothing on purpose. It's the free play at the start of a real knob, and it stops a stray scroll from nudging your volume.
* It reads the actual system volume every time you start a twist, so it doesn't fight with the media keys.
* The on-screen dial is segmented, one chunk per detent. What lights up is exactly what you just felt click.

Everything is tunable in settings, including a live readout of how far you're twisting so you can find your own sensitivity.

## Why it doesn't use Apple's rotation gesture

macOS has a built-in two finger rotate gesture (`NSEvent.EventType.rotate`) and that's obviously where you'd start. It doesn't work.

I logged 8,782 multitouch frames while doing 48 deliberate thumb-and-index twists. The rotate event fired exactly zero times. 131 scroll events came through instead. macOS decides between scroll and rotate before it ever hands you an event, and for this hand shape it picks scroll every single time. There's no threshold to tune because the event simply never arrives.

So TwistPad reads raw contacts straight off the trackpad using the private MultitouchSupport framework, loaded at runtime with `dlopen`. Same approach BetterTouchTool and Jitouch take. The `MTTouch` struct is 96 bytes on Apple Silicon and the app verifies that at launch, so if Apple ever changes it you get a clear "can't read the trackpad" message instead of garbage angles.

Nice side effect: this needs no permissions at all. No Accessibility prompt, no Input Monitoring. I expected to have to ask for something and never did.

## Telling a twist from a scroll

Two fingers sitting on a trackpad are ambiguous. Here's what I measured across 48 twists and 21 scrolls:

| | twists | scrolls |
|---|---|---|
| peak rotation | 20.9° to 183° | 0.1° to 18.9° |
| centroid drift | under 0.11 | up to 0.24 |
| finger separation | 0.20 to 0.59 | 0.14 to 0.18 |

Look at the rotation row. The two overlap to within about 2°, so you cannot just threshold on "did it rotate enough". All three signals have to agree:

**Rotation** has to clear the 8° dead zone.

**Centroid drift** has to stay low while it's still deciding. Twisting barely moves the point between your fingers, scrolling drags it across the pad. Once the gesture locks in this stops mattering, because a long twist naturally wanders a bit.

**Finger separation** has to look like thumb and index. Too close and it's an index/middle scroll, too far apart and it's a palm or two hands.

Fail any of those and that touch is dead until you lift your fingers, so a scroll can't sneak through by twisting slightly at the end.

## The 180° thing that will bite you

This one looks correct and breaks spectacularly.

Two fingers give you a line, not an arrow. A line pointing up-left and a line pointing down-right are the same line, so the angle only means anything modulo 180.

If you pair the contacts by position (sorting them by x, say) and track a full 360° vector, then the moment a twist carries the pair past vertical the sort order flips and your measured angle jumps 180° in a single frame. The volume slams straight to 0 or 100. My first version did this and the logs were full of impossible 176° jumps between consecutive frames.

The fix has two parts. Pair the contacts by `pathIndex`, which stays constant for as long as a finger is down, and unwrap every angle change into ±90.

## Code layout

```
Sources/TwistPad/
├── main.swift                     entry point, .accessory activation policy
├── AppDelegate.swift              wiring, settings window
├── VolumeDial.swift               rotation to volume, detents, haptics
├── Gesture/
│   ├── MultitouchSupport.swift    private framework ABI, resolved at runtime
│   ├── MultitouchDialSource.swift contacts to TwistSample, angle unwrapping
│   └── DialRecognizer.swift       twist vs scroll state machine
├── Audio/VolumeController.swift   CoreAudio
├── UI/                            HUD, menu bar icon, settings
└── Support/                       settings, haptics, login item
```

The recognizer takes `TwistSample` values rather than raw multitouch structs, so you can swap the input out without touching the gesture logic.

One non-obvious bit: volume writes get coalesced latest-wins onto a serial queue. A twist fires up to 120 updates a second, and setting volume on a Bluetooth device round-trips over the link and can block for milliseconds.

## Known issues

* It's built on a private framework. Apple could change or remove it in any update. It'll tell you it can't read the trackpad rather than crashing, but it would need fixing.
* Apps that use rotation themselves (Preview, Photos, Figma) will rotate their content *and* change your volume, because reading contacts at the driver level means TwistPad can't swallow the event. Those apps are excluded by default and the list is editable in settings.
* Not notarized, so the first launch probably needs a right click then Open.
* "Open at Login" registers whatever path the app is currently at. Move it and you'll need to toggle it off and back on.

## License

MIT. Do whatever you want with it.
