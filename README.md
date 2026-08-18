# TwistPad

Twist two fingers on your trackpad like you're turning a dial, and the volume follows. Thumb and index works best.

It clicks as it turns. 16 haptic detents across the range, so it feels like a knob instead of a gesture.

![TwistPad demo](docs/demo.gif)

## Install

```bash
brew install --cask Toxic880/tap/twistpad
```

Or grab the zip from [Releases](https://github.com/Toxic880/TwistPad/releases/latest), unzip it, and drag TwistPad to Applications.

Signed and notarized by Apple, so it just opens. No warnings, nothing to allow, no permissions to grant. It lives in the menu bar and needs macOS 14 or newer and a trackpad.

Building it yourself works too:

```bash
git clone https://github.com/Toxic880/TwistPad.git
cd TwistPad
./build.sh
open TwistPad.app
```

The gesture recognisers take plain structs in and call a delegate out, so they can be driven frame by frame without a trackpad:

```bash
swift test
```

## How it feels

Your wrist is the limit here, not the software. A natural twist runs about 60°, so a full sweep from silent to max is set to 70° by default. One comfortable turn covers the whole range and you never have to re-grip.

* Clockwise turns it up, like every volume knob ever made. Flip it in settings if you're wired backwards.
* 16 detents, the same steps as the volume keys. Haptic tick on each one, and a firmer tap at 0 and 100 so you feel the ends without looking.
* The first 8° of twist does nothing on purpose, so a stray scroll never nudges your volume.
* The on-screen dial is segmented, one chunk per detent. What lights up is exactly what you just felt click.

Sensitivity, detent count, direction and the app blacklist are all in settings, along with a live readout of how far you're twisting so you can find your own feel.

## How it knows you meant it

Two fingers on a trackpad are ambiguous. A scroll rotates a little too, because no two fingers ever travel exactly together, so counting degrees is not enough on its own. What actually separates them is the shape of the movement: a twist turns the fingers against each other and stays where it is, while a scroll carries the pair across the pad and picks up a few degrees of slip on the way.

So a touch has to clear four checks before it takes over:

* **Enough rotation.** 8° by default, adjustable.
* **All in one direction.** Rotation that wandered its way to the threshold is fingers settling under pressure, not a turn.
* **Turning, not travelling.** The movement is split into how far the midpoint went and how far the fingers moved against it, both in millimetres. A twist is mostly the second; a scroll is almost entirely the first.
* **A thumb-and-index stance**, rather than two fingers pressed together — and a hard limit on how far the whole hand may drift before the touch is disqualified outright.

Fail any one and that touch is ignored until you lift off.

Apps that use rotation themselves, like Preview, Photos and Figma, are excluded by default so it stays out of their way. That list is editable in settings.

If a gesture is firing when it shouldn't, turn on **Log gesture decisions** in the About tab. Every touch then records what it measured and which check turned it away, which is the thing worth attaching to a bug report.

## Problems?

Email **Support@traluco.com** with **TwistPad** in the subject line.

## License

MIT. Do whatever you want with it.
