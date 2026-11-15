# MacAlphaTrack

A user-space macOS driver for the Frontier Design Group **AlphaTrack** control surface.

Frontier's original driver was a 32-bit kernel extension and stopped working after
macOS Catalina. MacAlphaTrack talks to the unit directly over USB (IOUSBHost, no kext,
no special entitlements) and exposes it as a virtual CoreMIDI device speaking the
documented **Native mode** MIDI protocol, so DAW plugins and mappings written for the
original driver keep working.

## Status

Early scaffold. Nothing talks to hardware yet.

Roadmap (see `docs/PROTOCOL.md` for the protocol details and open questions):

1. `macalphatrack dump` – open the device and print raw 12-byte reports, to pin down
   every button bit, encoder, fader and touch-strip encoding.
2. Buttons, encoders, fader position → Native-mode MIDI out.
3. LEDs and LCD ← Native-mode MIDI in.
4. Fader motor (command still unknown, needs reverse engineering).
5. Touch strip and footswitch.

## Layout

- `Sources/AlphaTrackKit` – protocol constants, raw USB command encoders, Native-mode MIDI map. Pure Swift, unit-tested.
- `Sources/macalphatrack` – the CLI/daemon: USB transport, CoreMIDI ports, subcommands.
- `docs/` – extracted Native Mode manual and consolidated protocol notes.

## Building

```sh
swift build
swift test
swift run macalphatrack
```

Requires macOS 13+ and Xcode command line tools.
