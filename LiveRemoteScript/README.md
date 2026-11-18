# AlphaTrack Control Surface script for Ableton Live

A Live "MIDI Remote Script" that drives the Frontier AlphaTrack through MacAlphaTrack's
virtual **AlphaTrack** MIDI ports, speaking the unit's documented Native mode. It is
modelled on the Tranzport script that ships with Live (same plain-object style, no
`_Framework` dependency), so it should work on Live 11 and 12.

Status: tested in Live 12.4 Suite on 2026-11-15 (transport, tracks, arm/mute/solo, fader
both ways, encoder modes, FLIP, F-keys, strip scrub and shuttle, automation LEDs, SHIFT display) and on 2026-11-18 (Device mode: blue hand, curated banks, paging). Also unit-tested against a mock of
Live's API: `python3 -m unittest discover -s tests`.

## Install

```sh
./install.sh
```

This symlinks `AlphaTrack/` into `~/Music/Ableton/User Library/Remote Scripts/`.
Start `macalphatrack run` first, then Live. In Preferences > Link, Tempo & MIDI pick
Control Surface **AlphaTrack**, Input **AlphaTrack**, Output **AlphaTrack**.

## Mapping

| Control | Function | SHIFT |
|---|---|---|
| PLAY / STOP | play / stop (STOP again: return to start) | continue from position |
| REW / FFWD | nudge one beat, spool while held | |
| RECORD | arrangement record on/off (LED) | |
| LOOP | loop on/off (LED) | |
| TRACK L / R | previous / next track, returns, master (LEDs show direction available) | |
| REC / MUTE / SOLO | arm / mute / solo selected track (LEDs; ANY SOLO LED) | |
| Fader | selected track volume; motor follows Live, and hand moves are echoed back so the fader holds its position | |
| FLIP | swap fader and left encoder: the fader takes the left encoder's parameter (pan, first send, first device parameter) and the left encoder takes volume (LED) | |
| PAN | encoder mode: L = pan, M = volume; push L = centre pan | |
| SEND | encoder mode: sends A B C; press again for next 3; push = send off | |
| PLUG-IN / EQ | encoder mode: 3 parameters of the blue-hand device, LCD shows their names; PLUG-IN again = next page | previous page |
| Encoders | turn = change, LCD shows name and value briefly | fine steps |
| AUTO | automation arm on/off (AUTO and WRITE LEDs) | re-enable automation |
| READ LED | lit while all automation plays back; dark when a parameter has been overridden | |
| F1 | undo | redo |
| F2 | toggle Session / Arranger (LED = Session) | |
| F3 | fire highlighted clip slot (Session) / selected scene | fire selected scene |
| F4 | metronome on/off (LED) | |
| Touch strip, 1 finger | scrub arrangement (1 beat per step) / scroll scenes in Session | |
| Touch strip, 2 fingers | shuttle: first touch is zero speed, sliding right or left sets forward or backward speed | |
| Footswitch | play / stop | |
| LCD | line 1 track name; line 2 mode info | position and tempo |

Not mapped: EQ has no mode of its own (it selects device mode).

### Device mode

The script gives Live's blue hand to the selected device of the selected track, and follows
it when you click another device or track. Parameters come from Live's own curated banks:
the device's "Best of" bank first, then its named banks, each split into pages of three.
Paging shows the bank name and page number (for example `Best of  2/3`); otherwise the LCD
shows the three parameter names, abbreviated. Devices Live has no banks for fall back to
their parameters in order.
