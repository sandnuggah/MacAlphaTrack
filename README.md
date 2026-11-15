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

Tested end to end with REAPER's built-in "Frontier AlphaTrack" control surface: track
name and timecode on the LCD, fader following, LED feedback, transport and encoders.

Roadmap (see `docs/PROTOCOL.md` and `TODO.md`):

1. ~~Raw report dumper, protocol verification~~ done
2. ~~Buttons, encoders, fader position, touch strip → Native-mode MIDI out~~ done
3. ~~LEDs and LCD ← Native-mode MIDI in~~ done
4. Fader motor (command still unknown, needs reverse engineering).
5. Footswitch, LED id verification, touch calibration/debounce tuning.
6. ~~Menu bar app with Live script installer and launch at login~~ done
7. App icon, notarized release build.

## Command line

```sh
swift build -c release
.build/release/macalphatrack run            # headless driver; --verbose logs every MIDI message
```

It waits for the unit, survives unplugging, and blanks the display on Ctrl-C. In your DAW,
pick the **AlphaTrack** MIDI input and output and configure the AlphaTrack control surface
in Native mode as you would with the original driver.

Other commands: `install-live`, `dump` (raw reports), `lights [on|off]`, `lcd "TOP" "BOTTOM"`,
`send <hex bytes>`, `fader-probe`, `descriptors`, `info`.

## The app

`MacAlphaTrack.app` is a menu bar app that runs the driver in the background. Its panel
shows whether the unit is connected and the MIDI traffic, lets you switch the driver off
and on, installs or updates the Ableton Live control surface script into Live's User
Library, and can register itself as a login item.

```sh
Scripts/make-app.sh            # -> build/MacAlphaTrack.app (release, ad-hoc signed)
open build/MacAlphaTrack.app
```

Copy it to /Applications to keep it. The app and the `macalphatrack` CLI share the
`AlphaTrackDriver` library; run only one of them at a time, since the unit can be opened
by a single process.

## Ableton Live

`LiveRemoteScript/` holds a Live Control Surface script for the AlphaTrack (Live has
none built in; it ships one for the sibling TranzPort). It drives the unit through the
virtual ports in Native mode. See `LiveRemoteScript/README.md` for the mapping and
`LiveRemoteScript/install.sh` to install it. Tested in Live 12.4 Suite; also unit-tested
against a mock of Live's API.

## Layout

- `Sources/AlphaTrackKit` – protocol constants, report decoder, Native-mode MIDI translation. Pure Swift, unit-tested.
- `Sources/AlphaTrackDriver` – IOUSBHost transport, CoreMIDI virtual ports, the driver service, the Live script installer.
- `Sources/MacAlphaTrackApp` – the SwiftUI menu bar app. `Scripts/make-app.sh` wraps it into `MacAlphaTrack.app`.
- `Sources/macalphatrack` – command-line tool for running headless and poking the hardware.
- `docs/` – extracted Native Mode manual and consolidated protocol notes.
- `LiveRemoteScript/` – Ableton Live Control Surface script, mock Live API and tests.

## Building

```sh
swift build
swift test
swift run macalphatrack
```

Requires macOS 13+ and Xcode command line tools.
