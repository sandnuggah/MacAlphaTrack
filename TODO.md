# TODO

## Hardware / protocol
- [x] **Touch calibration** tried 2026-11-15: no effect. The sensors are proximity-sensitive;
      with a hand over the unit, neighbouring touch bits oscillate (~150 ms on / ~80 ms off)
      while real touches hold >500 ms. Driver now uses assert/release hysteresis
      (~210 ms / ~260 ms) and asserts fader touch immediately on fader movement.
- [ ] Check whether the oscillation is a grounding issue (laptop on battery vs mains / powered hub).
      If mains power fixes it, the hysteresis can be shortened.
- [x] Verify which physical LED each light id 0...22 drives (all 21 match; 7 and 8 drive nothing).
- [ ] Footswitch bit (presumably bit 7) – needs a footswitch plugged in.
- [x] Fader motor output command: `00 02 pp qq`. Byte 3 (2 LSBs) assumed, not visually verifiable.
- [ ] Fader feedback: the device does not report motor-driven positions. Decide whether the
      daemon should echo the commanded position back as MIDI (most DAWs don't need it).
- [ ] LCD custom characters 0x00...0x07 (bargraph glyphs) – check what each renders.
- [x] Device occasionally re-enumerates itself (seen 3x on 2026-11-15, cause unknown).
      Both `dump` and the driver reopen it and restore state.

## Driver
- [x] CoreMIDI bridge: virtual source/destination "AlphaTrack" speaking Native-mode MIDI.
- [x] Touch filtering (assert/release hysteresis). Maybe rate-limit fader/strip (~15 ms) like the original driver.
- [x] Clear LCD and LEDs on exit; restore them when the device reconnects.
- [x] Fader setpoint semantics understood: the unit servos the fader to the last commanded
      position (motor off while touched). Hosts MUST echo hand moves straight back, as REAPER
      and the Live script do, or the fader springs back on release. No suppression needed.
- [x] Run at login: the app registers itself as a login item (SMAppService).
- [x] Moved to the protocol-based CoreMIDI API (MIDIEventList, MIDI 1.0 UMP); UMP codec in AlphaTrackKit.
- [ ] Developer ID signing + notarization for distribution.
- [ ] Investigate publishing the source through Homebrew (a tap with a formula that builds from
      source, or a cask once there is a notarized release) so installs avoid Gatekeeper.
- [x] Menu bar header: connection status dot in the first menu item.
- [ ] Remove the macalphatrack:// URL scheme and the snapshot debug hook (CFBundleURLTypes in
      make-app.sh, AppDelegate.application(_:open:), WindowSnapshot) once no longer needed for testing.
- [ ] Run without a menu bar icon. Investigated 2026-11-18, feasible and small:
      1. "Show menu bar icon" switch in Settings (default on) bound to NSStatusItem.isVisible; also set
         behavior = .removalAllowed so Cmd-dragging the icon off the bar works, and observe isVisible
         to keep the preference in sync.
      2. applicationShouldHandleReopen: launching the app again while it runs opens Settings, which is
         the way back when the icon is hidden (works for LSUIElement apps). Caption under the switch says so.
      3. Login launch stays silent (no icon, no window); the driver runs as today.
      A separate LaunchAgent running the CLI (SMAppService.agent) would remove the app process entirely
      but needs IPC for status; not worth it. Once (2) exists the URL scheme is no longer needed.
- [x] Flaky debug builds were the default swiftbuild build system (objects dropped from the link,
      new files tripping the dependency scanner). Everything uses `--build-system native` now.
- [x] Live script installer reads the User Library location from the newest Live's Library.cfg; a chosen folder still wins.

## Ableton Live script (`LiveRemoteScript/`)
- [x] Tested inside Live 12.4 Suite: all mapped controls work; two bugs found and fixed (master track
      listeners, fader setpoint echo).
- [x] FLIP (swap fader with the left encoder's parameter) and 2-finger strip shuttle. Confirmed in Live 12.4.
- [x] AUTO WRITE LED = automation arm, READ LED = no overridden automation; SHIFT+AUTO re-enables. Confirmed in Live 12.4.
- [ ] Device mode: follow Live's blue-hand "selected device" more closely; parameter banks of 3 feel small.
