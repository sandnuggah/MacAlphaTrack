# Developing MacAlphaTrack

Technical notes for people building, changing or scripting MacAlphaTrack. The end-user
guide is the [README](../README.md); the wire protocol is in [PROTOCOL.md](PROTOCOL.md).

## Building and testing

```sh
swift build --build-system native
swift test  --build-system native                 # Swift targets
python3 -m unittest discover -s LiveRemoteScript/tests   # Live script against the mock
```

Requires macOS 13 or later and Xcode (Icon Composer and `actool` come with it). The
`--build-system native` flag matters: the default SwiftPM build system in current
toolchains intermittently drops object files from the link and fails on newly added
files; the classic one is dependable.

## Building the app

```sh
Scripts/make-app.sh
```

This produces `build/MacAlphaTrack.app` (release, ad-hoc signed, not notarized). On another
Mac, macOS blocks the first launch of a downloaded copy until it is allowed in
System Settings › Privacy & Security ("Open Anyway"). Building from source avoids that.
Developer ID signing and notarization are on the TODO list.

## Command line

`macalphatrack` is the same driver without the app, plus tools used while reverse
engineering the unit:

```sh
swift build --build-system native -c release
.build/release/macalphatrack run          # headless driver; --verbose logs every MIDI message
.build/release/macalphatrack dump         # print raw USB reports as you touch the unit
.build/release/macalphatrack lights       # cycle every LED, naming each on the LCD
.build/release/macalphatrack lcd "TOP" "BOTTOM"
.build/release/macalphatrack send 00 02 80 00   # raw 8-byte command (this one centres the fader)
```

Also `install-live`, `fader-probe`, `descriptors`, `info`.

Only one process can hold the unit, so quit the app before using the command-line tools.

## How it works

- **USB.** The AlphaTrack is a vendor-specific USB device, not USB-MIDI. It sends a
  12-byte interrupt report every 8 ms and accepts 8-byte commands. The protocol was
  reconstructed from the old Linux staging driver and then verified and completed on
  hardware (fader motor command, LED ids, touch strip). Everything known is written up in
  [PROTOCOL.md](PROTOCOL.md); the MIDI layer comes from Frontier's Native Mode manual (see Acknowledgements).
- **Translation.** `AlphaTrackKit` is pure Swift: it decodes reports, turns them into the
  Native-mode MIDI messages from Frontier's manual, and turns incoming MIDI into USB
  commands, keeping a shadow of LEDs, LCD and fader so state can be restored after a
  reconnect. Capacitive touch is filtered with hysteresis because the sensors react to a
  hovering hand. All of this is unit-tested with bytes captured from the real unit.
- **Idle display.** `IdleScreen` in `AlphaTrackKit` renders what the unit shows while no
  host is using it: a block with a tail sweeping under the name, and a view of whichever control is being
  touched. The driver draws it when the host's own state is blank (LCD empty, LEDs off) and
  the host has sent nothing that changes the unit for three seconds. It never enters the
  saved state, and the first host message that changes the unit restores that state. While
  idle the driver echoes hand moves of the fader as the setpoint, since no host is there to.
- **CoreMIDI.** `AlphaTrackDriver` opens the device with IOUSBHost, creates the virtual
  source and destination with stable unique ids, and runs the bridging loop. The app and
  the CLI both use it.
- **App.** `MacAlphaTrackApp` is an AppKit status item with a SwiftUI settings window
  themed in the unit's blue and charcoal. The bundling script compiles the Icon Composer
  package in `Design/icons/AppIcon.icon` with `actool`, so the icon is real Liquid Glass,
  and stamps the SDK version into the binary with `vtool` so macOS gives the app the
  current window design (SwiftPM records the deployment target instead, which puts an app
  into pre-macOS-26 compatibility mode).

- **Live script.** `LiveRemoteScript/` is a plain-object Control Surface script modelled on
  Live's TranzPort script. `macalphatrack install-live` copies it into the User Library;
  `LiveRemoteScript/install.sh` makes a developer symlink instead. The installer reads the
  User Library location from the newest installed Live's own preferences (`Library.cfg`).

## Layout

- `Sources/AlphaTrackKit` – protocol constants, report decoder, Native-mode MIDI translation.
- `Sources/AlphaTrackDriver` – IOUSBHost transport, CoreMIDI ports, driver service, Live script installer.
- `Sources/MacAlphaTrackApp` – menu bar app.
- `Sources/macalphatrack` – command-line tool.
- `LiveRemoteScript/` – Ableton Live Control Surface script, a mock of Live's API, and its tests.
- `Design/icons/` – app icon package, menu bar glyph, concept sketches.
- `Scripts/make-app.sh` – builds and signs `MacAlphaTrack.app`.
- `docs/` – protocol reference, these notes, release steps ([RELEASING.md](RELEASING.md); the
  Homebrew formula is in the separate `homebrew-MacAlphaTrack` repository), README images.
- `TODO.md` – open items.

## Acknowledgements

- Frontier Design Group's *AlphaTrack Native Mode MIDI Interface Description*, rev 1.0
  (2006-12-21), the manual that shipped with the original driver. It is Frontier's document
  and is not included here; [PROTOCOL.md](PROTOCOL.md) restates the facts the driver relies on.
- David Täht's Linux staging driver and Ardour code for the TranzPort and AlphaTrack,
  the only public record of the raw USB protocol.
- Ableton's bundled TranzPort script, the model for the Live Control Surface script.
