# AlphaTrack protocol notes

Two layers matter for a modern macOS driver:

1. **Raw USB** – what the hardware actually speaks. Frontier never documented it;
   everything below comes from the Linux staging driver (`drivers/staging/frontier/alphatrack.c`,
   David/Michael Täht, 2007) and Täht's Ardour surface code
   (github.com/harryhaaren/Alphatrack-Linux-Kernel-module).
2. **Native-mode MIDI** – what Frontier's old driver exposed to DAWs. Fully documented in
   `alphatrack-native-mode-manual.txt` (Rev 1.0, 2006-12-21). Our driver should present a
   virtual CoreMIDI source/destination that speaks exactly this, so the device looks the same
   as it did with the vendor driver.

## 1. Raw USB layer

| Item | Value | Confidence |
|---|---|---|
| Vendor ID | `0x165b` (Frontier Design Group) | confirmed |
| Product ID | `0xfad1` | confirmed |
| Class | vendor-specific 0xFF (not USB-MIDI, not HID), full speed, 1 configuration | confirmed |
| Endpoints | interrupt IN 0x81, interrupt OUT 0x02, wMaxPacketSize 64, bInterval 10 | confirmed on hardware |
| macOS notes | device is left unconfigured by the OS; the driver must call setConfiguration(1) before the interface appears. IOUSBHost rejects non-zero timeouts on interrupt pipes. | confirmed |
| Input report | 12 bytes | confirmed |
| Output command | 8 bytes | confirmed |
| Driver dedupes identical consecutive input reports | yes (device re-sends state) | confirmed |

### Input report (12 bytes, device -> host) — VERIFIED on hardware 2026-11-15

The device sends a report every ~8 ms regardless of activity (so consecutive duplicates
must be ignored). After `open` + `configure` the first report arrives after ~1.9 s and
carries status 0x01.

```
byte 0    : 0x00
byte 1    : status  0x00 = normal, 0x01 = came online (first report), 0xff = offline
bytes 2-5 : 32-bit switch mask, big-endian (byte 2 = bits 31..24)
byte 6    : fader position bits 9..2            } 10-bit position = (b6 << 2) | (b7 >> 6)
byte 7    : fader position bits 1..0 in bits 7-6 }  0 = bottom, 1023 = top
byte 8    : left encoder   delta since previous report, signed: +1 clockwise, -1 (0xff) counter-clockwise
byte 9    : middle encoder delta
byte 10   : right encoder  delta
byte 11   : touch strip position, 0x00..0xf8 in steps of 8 -> position = byte >> 3 (0..31, left to right);
            keeps its last value after the finger lifts
```

Switch bits (all confirmed; they match the Linux `alphatrack.h` table):

```
bit 31 TRACK L   bit 30 FLIP     bit 29 SHIFT    bit 28 STOP     bit 27 PLAY
bit 26 FFWD      bit 25 RECORD   bit 24 REW      bit 23 SOLO     bit 22 F2
bit 21 F3        bit 20 F1       bit 19 F4       bit 18 MUTE     bit 17 TRACK R
bit 16 LOOP      bit 15 enc M push   bit 14 EQ   bit 13 enc R push   bit 12 REC (arm)
bit 11 SEND      bit 10 PLUG-IN  bit  9 PAN      bit  8 AUTO
bit  6 FADER TOUCH   bit 5 enc R touch   bit 4 enc M touch   bit 3 enc L touch
bit  2 STRIP 2 fingers   bit 1 STRIP 1 finger   bit 0 enc L push
bit  7: never seen; presumably FOOTSWITCH (none connected during verification)
```

Encoder push always comes with the matching touch bit (hence the old PRESS masks 0x09,
0x8010, 0x2020).

Observed quirk: the capacitive touch bits (encoders 3/4/5, fader 6) flicker heavily while
the hand is anywhere near the unit, e.g. fader touch toggles while turning an encoder. The
manual's touch calibration (hold SHIFT+STOP, press F4) may fix it; the driver should also
debounce touch bits (require a few consecutive reports) before emitting touch notes.

Observed quirk: the device re-enumerated (new IORegistry id) right after a full fader
sweep; reads failed with kIOReturnNotResponding then IOUSBHost error 0x10000003 until it
came back. The daemon must handle device removal/arrival and reopen.

### Output commands (8 bytes, host -> device)

```
LED on/off :  00 00 nn ss 00 00 00 00      nn = light id 0..22, ss = 01 on / 00 off      VERIFIED (all LEDs light); id->LED map unverified
LCD write  :  00 01 cc a0 a1 a2 a3 00      cc = cell 0..7 (4 chars each; 0-3 = top row,   VERIFIED on hardware
                                           4-7 = bottom row), a = LCD char codes
Fader move :  UNKNOWN - needs reverse engineering (TranzPort had no fader, so no prior art)
```

Light ids (`enum LightID`, confirmed by Ardour lightmap):

```
 0 EQ        1 OUT(TrackR?)  2 F2     3 SEND    4 IN(TrackL?)  5 F1    6 PAN    7 ?    8 ?
 9 SHIFT    10 MUTE         11 SOLO  12 REC(arm) 13 READ      14 WRITE 15 ANYSOLO
16 AUTO     17 F4           18 RECORD 19 WINDOW? 20 PLUGIN     21 F3    22 LOOP
```

LCD special chars seen in Ardour code: `0x07` = full 4-quadrant block, `0x03` = left-half block
(meter/bargraph glyphs). Manual says 8 custom chars exist; the character map image did not
survive text extraction - check the PDF page 8 for the table.

### Open questions

- Footswitch bit (presumably 7).
- Which physical LED each light id 0..22 drives.
- Fader motor output command. Candidates to try: `00 02 hi lo ...`, `00 03 ...`. Risk: wrong
  commands are harmless (device ignores) but we should avoid flooding the motor.
- Does the device need an "init" command before it reports? (Linux driver sends none; it just
  starts reading. First read after open returns the online status report.)

## 2. Native-mode MIDI layer (from the manual)

All on MIDI channel 1 (status `0x90`, `0xb0`, `0xe0`). Button = note on vel 7f (down) / 00 (up).
The LED for a button uses the same note number on the output side. No local button->LED logic.

| Control | Note / message |
|---|---|
| REW / FFWD / STOP / PLAY / RECORD | 5b 5c 5d 5e 5f |
| SHIFT | 46 |
| TRACK L / TRACK R | 57 / 58 |
| LOOP / FLIP / MUTE / SOLO / REC(arm) | 56 / 32 / 10 / 08 / 00 |
| F1 F2 F3 F4 | 36 37 38 39 |
| PAN / SEND / EQ / PLUG-IN / AUTO | 2a / 29 / 2c / 2b / 4a |
| LED only: ANY SOLO / AUTO WRITE / AUTO READ | 73 / 4b / 4e |
| Footswitch | 67 (7f = down) |
| Encoder touch L/M/R | 78 / 79 / 7a |
| Encoder push L/M/R | 20 / 21 / 22 |
| Encoder turn L/M/R | CC `b0 10/11/12 nn`  nn 01-3f = +ticks, 41-7f = -ticks |
| Fader touch | 68 |
| Fader position (both directions) | pitch bend `e0 yy zz`, 10-bit (yy = 3 LSB << 4, zz = 7 MSB) |
| Touch strip 1 finger / 2 fingers | 74 / 7b |
| Touch strip position | `e9 00 nn`, nn = pos<<2, 0..31 |

SysEx:

```
Force native mode   f0 00 01 40 20 01 00 f7
Device inquiry      f0 7e 00 06 01 f7  ->  f0 7e 00 06 02 00 01 40 20 00 01 00 30 31 30 30 f7
LCD write           f0 00 01 40 20 00 pp c1 .. cn f7     pp = 0..0x1f start pos (0x10 = line 2), n <= 0x20-pp
```

Clear the LCD (fill with 0x20) when the host app quits.

Suggested practice from Frontier: 1-finger strip = timeline scroll, 2-finger strip = shuttle
(initial 2-finger position = zero speed).
