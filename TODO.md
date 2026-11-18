# TODO

## Hardware / protocol
- [x] **Touch calibration** tried 2026-11-15: no effect. The sensors are proximity-sensitive;
      with a hand over the unit, neighbouring touch bits oscillate (~150 ms on / ~80 ms off)
      while real touches hold >500 ms. Driver now uses assert/release hysteresis
      (~210 ms / ~260 ms) and asserts fader touch immediately on fader movement.
- [x] Grounding test 2026-11-18 (`Scripts/touch-noise.sh`, hand hovering 20 s): on battery the three
      encoder touch bits flicker (39 false touches, typically ~190 ms, longest 1.2 s); on mains
      (15 W charger) none. Fader and strip sensors silent either way. So the oscillation is a
      floating-supply effect. Hysteresis kept as is: the driver cannot tell how the Mac is powered,
      and on battery the longest false touches still exceed the ~210 ms assert time.
- [x] Verify which physical LED each light id 0...22 drives (all 21 match; 7 and 8 drive nothing).
- [ ] Footswitch bit (presumably bit 7) – needs a footswitch plugged in.
- [x] Fader motor output command: `00 02 pp qq`. Byte 3 (2 LSBs) assumed, not visually verifiable.
- [x] Fader feedback: the device does not report motor-driven positions. Decided 2026-11-18 not to
      echo the commanded position back as MIDI: hosts track it themselves, and an echo could be
      taken for a hand move.
- [x] LCD custom characters 0x00...0x07: bars with a centre tick, 4..1 columns from the right (0-3)
      and 1..4 columns from the left (4-7). Photographed 2026-11-18; table in docs/PROTOCOL.md.
- [x] Device occasionally re-enumerates itself (seen 3x on 2026-11-15, cause unknown).
      Both `dump` and the driver reopen it and restore state.

## Driver
- [x] CoreMIDI bridge: virtual source/destination "AlphaTrack" speaking Native-mode MIDI.
- [x] Touch filtering (assert/release hysteresis). Rate limiting considered and dropped 2026-11-18:
      Frontier's ~15 ms limit applied to encoder turns only, and one message per 8 ms report is no load.
- [x] Clear LCD and LEDs on exit; restore them when the device reconnects.
- [x] Fader setpoint semantics understood: the unit servos the fader to the last commanded
      position (motor off while touched). Hosts MUST echo hand moves straight back, as REAPER
      and the Live script do, or the fader springs back on release. No suppression needed.
- [x] Run at login: the app registers itself as a login item (SMAppService).
- [x] Moved to the protocol-based CoreMIDI API (MIDIEventList, MIDI 1.0 UMP); UMP codec in AlphaTrackKit.
- [x] Menu bar app (AppKit status item + SwiftUI settings window), `Scripts/make-app.sh` builds the bundle.
- [x] Custom icons: fader app icon as an Icon Composer package compiled by actool; menu bar template glyph.
- [ ] Developer ID signing + notarization for distribution.
- [ ] Publish through Homebrew. Investigated 2026-11-18:
      - Route: own tap (repo `homebrew-<name>`) with a formula that builds from source. Locally built
        apps are not quarantined, so no Gatekeeper prompt. homebrew-core is out (notability rules, and
        it does not take GUI apps); a cask needs a signed + notarized build (unsigned casks are being
        disabled, and `--no-quarantine` is gone).
      - Prerequisites, none done yet: public Git remote, a version tag (LICENSE done: Unlicense) (formula points at
        the tag tarball + sha256). Frontier's manual text has been removed from the tree and
        purged from the git history.
      - Formula sketch: depends_on xcode (actool/Icon Composer need full Xcode) and macos >= 13;
        `swift build --disable-sandbox --build-system native -c release`; run Scripts/make-app.sh
        (make it take the version from an env var, no git in a tarball); install bin/macalphatrack and
        prefix/MacAlphaTrack.app; caveats telling the user to open or copy the app; optional
        `service do` block so `brew services start macalphatrack` runs the headless driver.
      - To check when doing it: build inside Homebrew's sandbox, CoreMIDI ports from a brew service,
        and that "Launch at login" survives upgrades (the Cellar path changes per version).
- [x] Menu bar header: connection status dot in the first menu item.
- [x] Removed the macalphatrack:// URL scheme and the window snapshot debug hook; opening the app again shows Settings.
- [x] Run without a menu bar icon: "Show menu bar icon" switch in Settings (also Cmd-drag the icon off
      the bar); opening the app again shows Settings; a manual launch with the icon hidden shows
      Settings, a login launch stays silent.
- [x] Flaky debug builds were the default swiftbuild build system (objects dropped from the link,
      new files tripping the dependency scanner). Everything uses `--build-system native` now.
- [x] Live script installer reads the User Library location from the newest Live's Library.cfg; a chosen folder still wins.
- [x] Idle display: while no host uses the unit (LCD blank, LEDs off, no host output for 3 s) a block
      with a tail sweeps under the name (built-in characters 0xff, 0xdb, 0xa5), and touching a control shows it (fader level, knob and strip position,
      button name with its LED). Any host output takes the display back. Switch in Settings.

## Ableton Live script (`LiveRemoteScript/`)
- [x] Tested inside Live 12.4 Suite: all mapped controls work; two bugs found and fixed (master track
      listeners, fader setpoint echo).
- [x] FLIP (swap fader with the left encoder's parameter) and 2-finger strip shuttle. Confirmed in Live 12.4.
- [x] AUTO WRITE LED = automation arm, READ LED = no overridden automation; SHIFT+AUTO re-enables. Confirmed in Live 12.4.
- [x] FLIP confirmed in Live 12.4 (all five checks: baseline, LED and motor, swapped controls, send/device modes, unflip).
- [x] Device mode: blue-hand appointment and Live's curated banks (Best of + named banks, pages of three,
      parameter names on the LCD, SHIFT+PLUG-IN pages back). Confirmed in Live 12.4. The hand only shows
      once the script declares `can_lock_to_devices()` and calls `update_locks()`.
