# TODO

## Hardware / protocol
- [ ] **Touch calibration.** Capacitive touch bits (encoders, fader) flicker heavily when a hand
      is near the unit. Try the manual's calibration (hold SHIFT+STOP, press F4) and re-check with
      `macalphatrack dump`. If still noisy, the driver needs debouncing (N consecutive reports)
      before emitting touch notes.
- [x] Verify which physical LED each light id 0...22 drives (all 21 match; 7 and 8 drive nothing).
- [ ] Footswitch bit (presumably bit 7) – needs a footswitch plugged in.
- [x] Fader motor output command: `00 02 pp qq`. Byte 3 (2 LSBs) assumed, not visually verifiable.
- [ ] Fader feedback: the device does not report motor-driven positions. Decide whether the
      daemon should echo the commanded position back as MIDI (most DAWs don't need it).
- [ ] LCD custom characters 0x00...0x07 (bargraph glyphs) – check what each renders.
- [ ] Device occasionally re-enumerates itself (seen 3x on 2026-11-15, cause unknown).
      The daemon must survive this; `dump` already reopens, the MIDI bridge must too.

## Driver
- [x] CoreMIDI bridge: virtual source/destination "AlphaTrack" speaking Native-mode MIDI.
- [x] Debounce touch bits (3 reports). Still to tune after calibration; maybe rate-limit fader/strip (~15 ms) like the original driver.
- [x] Clear LCD and LEDs on exit; restore them when the device reconnects.
- [ ] Move from the deprecated MIDIPacketList API to MIDIEventList/UMP before Apple removes it.
- [ ] Run as a LaunchAgent / menu bar app.
