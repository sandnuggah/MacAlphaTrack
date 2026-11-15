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
| Class | vendor-specific (not USB-MIDI, not HID) | confirmed (Linux driver binds generic USB) |
| Endpoints | 1x interrupt IN, 1x interrupt OUT, wMaxPacketSize 64 | confirmed |
| Input report | 12 bytes | confirmed |
| Output command | 8 bytes | confirmed |
| Driver dedupes identical consecutive input reports | yes (device re-sends state) | confirmed |

### Input report (12 bytes, device -> host)

```
byte 0    : 0x00 (unknown / always zero on TranzPort)
byte 1    : status  0x00 = normal event, 0x01 = came online, 0xff = offline
bytes 2-5 : 32-bit button/touch bitmask, big-endian (byte2 = MSB)
byte 6    : encoder delta ("datawheel" on TranzPort; 01-3f fwd, 41-7f back) -- WHICH encoder: unverified
bytes 7-8 : unknown (likely other encoders and/or touch-strip position)
bytes 9-11: fader position ("last 3 bytes are the slider position; 0x40 flag = fader moving, MSBs, 3 LSBs")
```

Button bitmask as published in `alphatrack.h` (treat as **hints, must be verified on hardware**;
the table was adapted from the TranzPort and has obvious duplicates):

```
PLAY        0x08000000   STOP      0x10000000   REW      0x01000000   FFWD     0x04000000
RECORD      0x02000000   SHIFT     0x20000000   LOOP     0x00010000   FLIP     0x40000000
TRACKLEFT   0x80000000   TRACKRIGHT 0x00020000
TRACKREC    0x00001000   TRACKMUTE 0x00040000   TRACKSOLO 0x00800000 (same bit listed for PUNCH)
F1 0x00100000  F2 0x00400000  F3 0x00200000  F4 0x00080000
PAN 0x00000200  SEND 0x00000800  EQ 0x00004000 (same bit listed for "BATTERY")  PLUGIN 0x00000400  AUTO 0x00000100
ENCODER TOUCH 1/2/3   0x00000008 / 0x00000010 / 0x00000020
ENCODER PRESS 1/2/3   0x00000009 / 0x00008010 / 0x00002020   (press = touch bit + another bit)
FOOTSWITCH  unknown
TOUCH STRIP unknown
```

### Output commands (8 bytes, host -> device)

```
LED on/off :  00 00 nn ss 00 00 00 00      nn = light id 0..22, ss = 01 on / 00 off      confirmed
LCD write  :  00 01 cc a0 a1 a2 a3 00      cc = cell 0..7 (4 chars each; 0-3 = top row,   confirmed
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

### Open questions (need the unit plugged in)

- Exact bit for every button; footswitch bit; FLIP/F-keys; which bits are encoder touch vs press.
- Byte layout of the 3 encoder deltas and the touch strip (2 touch flags + 0..31 position).
- Fader position encoding (10-bit per the MIDI layer) in bytes 9-11, and the fader-touch bit.
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
