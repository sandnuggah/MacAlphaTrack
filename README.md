# MacAlphaTrack

A macOS driver and menu bar app for the Frontier Design Group **AlphaTrack** control
surface, with a Control Surface script for Ableton Live.

Frontier's original driver was a 32-bit kernel extension that died with macOS Catalina,
and the company no longer maintains it. MacAlphaTrack talks to the unit directly over USB
from user space (IOUSBHost, no kernel extension, no special entitlements) and publishes
it as a virtual CoreMIDI device speaking the unit's documented **Native mode** MIDI
protocol. Anything written for the original driver, such as REAPER's built-in
"Frontier AlphaTrack" surface, works unchanged. Runs natively on Apple Silicon.

## What works

| Direction | Covered |
|---|---|
| Unit → DAW | all 22 buttons, 3 encoders (touch, push, relative turn), motorised fader position and touch, touch strip (1 and 2 fingers, position), device inquiry reply |
| DAW → unit | all 21 LEDs, 16×2 LCD, fader motor |
| Resilience | waits for the unit, survives unplugging and the unit's occasional self-reset, restores LEDs, LCD and fader on reconnect, blanks the unit on quit |

Not covered: the footswitch (its bit is unverified, no footswitch was available).

Tested with REAPER's built-in AlphaTrack surface and with the bundled Ableton Live 12
script, on macOS 27 with an M4 MacBook Air.

## Install and run

1. Build the app:

   ```sh
   Scripts/make-app.sh
   ```

   This produces `build/MacAlphaTrack.app` (release, ad-hoc signed). Copy it to
   `/Applications` to keep it.

2. Launch it. It lives in the menu bar as a fader icon; the menu shows the connection
   status and opens the settings window (⌘,), which has the driver status, MIDI activity
   counters, a launch-at-login switch, the Ableton Live installer and the log.

3. In your DAW, pick the **AlphaTrack** MIDI input and output and set up the AlphaTrack
   control surface in Native mode, as you would with the original driver. Start
   MacAlphaTrack before the DAW so the ports exist.

The driver runs for as long as the app does. Only one process can hold the unit, so quit
the app before using the command-line tools below.

### Distribution note

The build is ad-hoc signed, not notarized. On another Mac, macOS blocks the first launch
of a downloaded copy until it is allowed in System Settings › Privacy & Security
("Open Anyway"). Building from source avoids that. Developer ID signing and
notarization are on the TODO list.

## Ableton Live

Live has no AlphaTrack surface of its own (it ships one for the sibling TranzPort), so
`LiveRemoteScript/` provides one. Install it from the app's settings window, or with
`macalphatrack install-live`, or `LiveRemoteScript/install.sh` for a developer symlink.
Then restart Live and choose Control Surface **AlphaTrack** with Input and Output
**AlphaTrack** in Preferences › Link, Tempo & MIDI.

Transport, track navigation, arm/mute/solo with LEDs, a motorised fader for the selected
track, pan/send/device encoder modes, F-keys for undo, view toggle, clip fire and
metronome, strip scrubbing, and an LCD with track name and context. The full mapping is
in [LiveRemoteScript/README.md](LiveRemoteScript/README.md).

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

## How it works

- **USB.** The AlphaTrack is a vendor-specific USB device, not USB-MIDI. It sends a
  12-byte interrupt report every 8 ms and accepts 8-byte commands. The protocol was
  reconstructed from the old Linux staging driver and then verified and completed on
  hardware (fader motor command, LED ids, touch strip). Everything known is written up in
  [docs/PROTOCOL.md](docs/PROTOCOL.md); the original Native Mode manual is in `docs/` too.
- **Translation.** `AlphaTrackKit` is pure Swift: it decodes reports, turns them into the
  Native-mode MIDI messages from Frontier's manual, and turns incoming MIDI into USB
  commands, keeping a shadow of LEDs, LCD and fader so state can be restored after a
  reconnect. Capacitive touch is filtered with hysteresis because the sensors react to a
  hovering hand. All of this is unit-tested with bytes captured from the real unit.
- **CoreMIDI.** `AlphaTrackDriver` opens the device with IOUSBHost, creates the virtual
  source and destination with stable unique ids, and runs the bridging loop. The app and
  the CLI both use it.
- **App.** `MacAlphaTrackApp` is an AppKit status item with a SwiftUI settings window
  themed in the unit's blue and charcoal. The bundling script compiles the Icon Composer
  package in `Design/icons/AppIcon.icon` with `actool`, so the icon is real Liquid Glass,
  and stamps the SDK version into the binary with `vtool` so macOS gives the app the
  current window design (SwiftPM records the deployment target instead, which puts an app
  into pre-macOS-26 compatibility mode).

## Layout

- `Sources/AlphaTrackKit` – protocol constants, report decoder, Native-mode MIDI translation.
- `Sources/AlphaTrackDriver` – IOUSBHost transport, CoreMIDI ports, driver service, Live script installer.
- `Sources/MacAlphaTrackApp` – menu bar app.
- `Sources/macalphatrack` – command-line tool.
- `LiveRemoteScript/` – Ableton Live Control Surface script, a mock of Live's API, and its tests.
- `Design/icons/` – app icon package, menu bar glyph, concept sketches.
- `Scripts/make-app.sh` – builds and signs `MacAlphaTrack.app`.
- `docs/` – protocol notes and the extracted Frontier manual.
- `TODO.md` – open items.

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

## Acknowledgements

- Frontier Design Group's *AlphaTrack Native Mode MIDI Interface Description*, rev 1.0.
- David Täht's Linux staging driver and Ardour code for the TranzPort and AlphaTrack,
  the only public record of the raw USB protocol.
- Ableton's bundled TranzPort script, the model for the Live Control Surface script.
