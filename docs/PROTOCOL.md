# AlphaTrack protocol reference

Everything MacAlphaTrack knows about the Frontier Design Group AlphaTrack, verified on a
real unit on 2026-11-15 unless marked otherwise. Two layers:

1. **Raw USB**: what the hardware speaks. Frontier never documented it. The starting point
   was the Linux staging driver (`drivers/staging/frontier/alphatrack.c`, David Täht, 2007)
   and Täht's Ardour surface code (github.com/harryhaaren/Alphatrack-Linux-Kernel-module);
   the gaps (fader motor, strip, LED map, device behaviour) were filled by probing.
2. **Native-mode MIDI**: what Frontier's driver exposed to DAWs, documented in
   Frontier's *AlphaTrack Native Mode MIDI Interface Description* (rev 1.0, 2006-12-21; not
   included in this repository). MacAlphaTrack's virtual
   CoreMIDI ports speak exactly this.

The Swift source of truth is `Sources/AlphaTrackKit` (`USBProtocol.swift`,
`InputReport.swift`, `NativeMIDI.swift`), whose tests use bytes captured from the unit.

## 1. Raw USB

| Item | Value |
|---|---|
| Vendor / product id | `0x165b` / `0xfad1` ("Frontier Design Group" / "AlphaTrack") |
| Class | vendor-specific (0xFF). Not USB-MIDI, not HID. Full speed, one configuration, one interface |
| Endpoints | interrupt IN `0x81`, interrupt OUT `0x02`, both wMaxPacketSize 64, bInterval 10 |
| Input report | 12 bytes, sent every ~8 ms whether or not anything changed |
| Output command | 8 bytes |

### Opening the device on macOS

- macOS leaves the device unconfigured. Open the `IOUSBHostDevice`, call
  `configure(withValue: 1, matchInterfaces: true)`, then open the `IOUSBHostInterface`
  that appears and copy the two pipes. Redundant configure calls are harmless.
- IOUSBHost rejects any non-zero completion timeout on interrupt pipes: read with timeout 0
  and abort the pipe to cancel.
- After open the first report arrives after ~1.9 s and carries status `0x01` (online).
- Reads occasionally fail with `kIOReturnNotResponding`; clearing the stall and retrying
  usually recovers. The unit also re-enumerates itself now and then (new IORegistry id,
  then IOUSBHost error `0x10000003` on every read). The driver must treat that as a
  disconnect, reopen when the device returns, and replay LEDs, LCD and fader position.
- No init command is needed; the device reports as soon as it is read.

### Input report (device → host, 12 bytes)

```
byte 0     0x00
byte 1     status: 0x00 normal · 0x01 came online (first report) · 0xff offline
bytes 2-5  32-bit switch mask, big-endian (byte 2 holds bits 31..24)
byte 6     fader position bits 9..2    }  position = (b6 << 2) | (b7 >> 6), 0 bottom … 1023 top
byte 7     fader position bits 1..0 in bits 7-6 }
byte 8     left encoder delta since the previous report, signed: +1 clockwise, -1 (0xff) counter-clockwise
byte 9     middle encoder delta
byte 10    right encoder delta
byte 11    touch strip position: 0x00…0xf8 in steps of 8 → position = byte >> 3 (0…31, left to right);
           holds its last value after the finger lifts
```

Switch mask bits:

```
31 TRACK L      30 FLIP         29 SHIFT        28 STOP         27 PLAY
26 FFWD         25 RECORD       24 REW          23 SOLO         22 F2
21 F3           20 F1           19 F4           18 MUTE         17 TRACK R
16 LOOP         15 enc M push   14 EQ           13 enc R push   12 REC (arm)
11 SEND         10 PLUG-IN       9 PAN           8 AUTO          7 (never seen; presumably FOOTSWITCH)
 6 FADER touch   5 enc R touch   4 enc M touch   3 enc L touch
 2 STRIP 2 fingers   1 STRIP 1 finger   0 enc L push
```

Notes:

- An encoder push always comes together with that encoder's touch bit.
- The fader position bytes only change when a hand moves the fader. Motor-driven moves are
  **not** reported, and after a reset they read 0 until the fader is touched.
- The capacitive touch sensors react to proximity. With a hand anywhere over the unit,
  neighbouring touch bits oscillate (~120-200 ms on, ~40-120 ms off) while a real touch
  holds for 500 ms or more. This only happens with the Mac on battery: measured on
  2026-11-18 with a hovering hand, the three encoder touch bits gave 39 false touches in
  20 s on battery (typically ~190 ms, longest 1.2 s) and none on mains power; the fader and
  strip sensors stayed quiet either way. The manual's calibration (hold SHIFT+STOP, press F4) does not
  change this. MacAlphaTrack asserts a touch after ~210 ms continuously on and releases
  after ~260 ms continuously off, and asserts fader touch immediately when the fader moves.
- Local functions handled by the unit itself: hold SHIFT+STOP and turn the left knob for
  LCD contrast, middle knob for backlight, right knob for idle timeout; SHIFT+STOP+F4
  starts touch/fader calibration. While SHIFT+STOP is held the unit sends a fresh online
  status report.

### Output commands (host → device, 8 bytes)

```
LED         00 00 nn ss 00 00 00 00    nn = light id (below), ss = 01 on / 00 off
LCD cell    00 01 cc a0 a1 a2 a3 00    cc = cell 0…7, four character codes; cells 0-3 are the
                                       top row, 4-7 the bottom row (16×2)
Fader       00 02 pp qq 00 00 00 00    pp = position bits 9..2, qq = bits 1..0 << 6
                                       (qq assumed to mirror the input encoding; a 3/1023 step
                                       cannot be verified by eye)
```

Light ids (ids 7 and 8 exist in the Linux enum but drive nothing):

```
 0 EQ        1 TRACK R   2 F2        3 SEND      4 TRACK L   5 F1        6 PAN
 9 SHIFT    10 MUTE     11 SOLO     12 REC(arm) 13 AUTO READ 14 AUTO WRITE 15 ANY SOLO
16 AUTO     17 F4       18 RECORD   19 FLIP     20 PLUG-IN  21 F3       22 LOOP
```

Fader semantics: the fader servos to the last position it was commanded, with the motor
released while the fader is touched. When the hand lets go it returns to that setpoint.
A host must therefore echo every hand-moved position straight back as the new setpoint;
REAPER's surface and the bundled Live script both do. Commanding the fader while it is
touched does not fight the hand.

LCD: the character set is the display's own; printable ASCII renders as expected. Codes
0x00-0x07 are eight custom glyphs in the 5×8 cell (verified 2026-11-18). Each has the
middle pixel row lit across the whole cell and a full-height vertical bar:

```
code   bar                         code   bar
0x00   right 4 columns             0x04   left 1 column
0x01   right 3 columns             0x05   left 2 columns
0x02   right 2 columns             0x06   left 3 columns
0x03   right 1 column              0x07   left 4 columns
```

They read as a horizontal bargraph or pan indicator: 0x04…0x07 fill a cell from its left
edge, 0x00…0x03 from its right edge. None is a completely full cell. (Täht's Ardour code
treated 0x07 as a full block and 0x03 as a left half block; on this unit neither is exact.)

### Open points

- Footswitch bit (presumably 7). Needs a footswitch.

## 2. Native-mode MIDI

Channel 1 throughout. A button sends `90 nn 7f` on press and `90 nn 00` on release; the
LED that belongs to a button is driven by the same note number sent to the device. The
unit has no local button-to-LED logic.

| Control | Message |
|---|---|
| REW / FFWD / STOP / PLAY / RECORD | notes 5b 5c 5d 5e 5f (RECORD has an LED) |
| SHIFT | 46 (LED) |
| TRACK L / TRACK R | 57 / 58 (LEDs) |
| LOOP / FLIP / MUTE / SOLO / REC (arm) | 56 / 32 / 10 / 08 / 00 (LEDs) |
| F1 F2 F3 F4 | 36 37 38 39 (LEDs) |
| PAN / SEND / EQ / PLUG-IN / AUTO | 2a / 29 / 2c / 2b / 4a (LEDs) |
| LED only: ANY SOLO / AUTO WRITE / AUTO READ | 73 / 4b / 4e |
| Footswitch | 67 (7f = pressed) |
| Encoder touch L / M / R | 78 / 79 / 7a |
| Encoder push L / M / R | 20 / 21 / 22 |
| Encoder turn L / M / R | `b0 10/11/12 nn`, nn 01-3f = +ticks, 41-7f = −ticks |
| Fader touch | 68 |
| Fader position, both directions | `e0 yy zz`: 10-bit, yy = (pos & 7) << 4, zz = pos >> 3 |
| Touch strip 1 finger / 2 fingers | 74 / 7b |
| Touch strip position | `e9 00 nn`, nn = position << 2 (position 0…31) |

SysEx:

```
Force native mode   f0 00 01 40 20 01 00 f7                (accepted and ignored: always native)
Device inquiry      f0 7e 00 06 01 f7
  reply             f0 7e 00 06 02 00 01 40 20 00 01 00 30 31 30 30 f7   ("v01.00")
LCD write           f0 00 01 40 20 00 pp c1 … cn f7        pp = 0…0x1f start position
                                                            (0x10 = start of line 2), n ≤ 0x20 − pp
```

How MacAlphaTrack maps the two layers: the LCD SysEx is rendered through a 32-byte shadow
into the cell commands it touches; LED notes become LED commands via the light-id table;
fader pitch bend becomes the fader command; everything else goes the other way. Hosts are
expected to clear the LCD when they quit; MacAlphaTrack also blanks LEDs and LCD itself on
exit and replays its shadow when the unit reconnects.

Frontier's suggested use of the strip: one finger scrolls the timeline, two fingers shuttle
with the initial two-finger position as zero speed.
