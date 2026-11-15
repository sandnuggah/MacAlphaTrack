# MacAlphaTrack

A user-space macOS driver for the Frontier Design Group **AlphaTrack** control surface.

Frontier's original driver was a 32-bit kernel extension and stopped working after
macOS Catalina. MacAlphaTrack talks to the unit directly over USB (IOUSBHost, no kext,
no special entitlements) and exposes it as a virtual CoreMIDI device speaking the
documented **Native mode** MIDI protocol, so DAW plugins and mappings written for the
original driver keep working.

## Status

Talks to the hardware. The raw USB protocol is reverse-engineered and verified on a real
unit (buttons, encoders, fader, touch strip, LEDs, LCD); see `docs/PROTOCOL.md` and `TODO.md`.
`macalphatrack run` is a working driver: it publishes a virtual CoreMIDI source and
destination named **AlphaTrack** that speak the documented Native-mode protocol, so
anything written for Frontier's original driver should work unchanged. Buttons, encoders,
fader position and touch strip go out; LEDs, LCD text and fader motor position come in.
Not yet: footswitch (unverified bit).

Roadmap (see `docs/PROTOCOL.md` and `TODO.md`):

1. ~~Raw report dumper, protocol verification~~ done
2. ~~Buttons, encoders, fader position, touch strip → Native-mode MIDI out~~ done
3. ~~LEDs and LCD ← Native-mode MIDI in~~ done
4. Fader motor (command still unknown, needs reverse engineering).
5. Footswitch, LED id verification, touch calibration/debounce tuning.
6. Run at login (LaunchAgent) or as a menu bar app.

## Usage

```sh
swift build -c release
.build/release/macalphatrack run            # add --verbose to log every MIDI message
```

Leave it running; it waits for the unit, survives unplugging, and blanks the display on
Ctrl-C. In your DAW, pick the **AlphaTrack** MIDI input and output and configure the
AlphaTrack control surface in Native mode as you would with the original driver.

Other commands: `dump` (raw reports), `lights [on|off]`, `lcd "TOP" "BOTTOM"`, `send <hex bytes>`,
`descriptors`, `info`.

## Layout

- `Sources/AlphaTrackKit` – protocol constants, raw USB command encoders, Native-mode MIDI map. Pure Swift, unit-tested.
- `Sources/macalphatrack` – the CLI/daemon: IOUSBHost transport, CoreMIDI virtual ports, subcommands.
- `docs/` – extracted Native Mode manual and consolidated protocol notes.

## Building

```sh
swift build
swift test
swift run macalphatrack
```

Requires macOS 13+ and Xcode command line tools.
