# Native-mode MIDI map of the Frontier Design AlphaTrack, from the
# "AlphaTrack Native Mode MIDI Interface Description" rev 1.0.
from __future__ import absolute_import, print_function, unicode_literals

NOTE_ON_STATUS = 0x90
NOTE_OFF_STATUS = 0x80
CC_STATUS = 0xB0
PITCHBEND_STATUS = 0xE0
STRIP_STATUS = 0xE9  # touch strip position: e9 00 nn, nn = pos << 2, pos 0..31

LED_ON = 127
LED_OFF = 0

# Buttons (notes on channel 1). Buttons with LEDs use the same note for the LED.
REC_ARM = 0x00
SOLO = 0x08
MUTE = 0x10
ENC_PUSH_L = 0x20
ENC_PUSH_M = 0x21
ENC_PUSH_R = 0x22
SEND = 0x29
PAN = 0x2A
PLUGIN = 0x2B
EQ = 0x2C
FLIP = 0x32
F1 = 0x36
F2 = 0x37
F3 = 0x38
F4 = 0x39
SHIFT = 0x46
AUTO = 0x4A
AUTO_WRITE_LED = 0x4B
AUTO_READ_LED = 0x4E
LOOP = 0x56
TRACK_L = 0x57
TRACK_R = 0x58
REW = 0x5B
FFWD = 0x5C
STOP = 0x5D
PLAY = 0x5E
RECORD = 0x5F
FOOTSWITCH = 0x67
FADER_TOUCH = 0x68
ANY_SOLO_LED = 0x73
STRIP_TOUCH_1 = 0x74
ENC_TOUCH_L = 0x78
ENC_TOUCH_M = 0x79
ENC_TOUCH_R = 0x7A
STRIP_TOUCH_2 = 0x7B

ENC_PUSH = (ENC_PUSH_L, ENC_PUSH_M, ENC_PUSH_R)
ENC_TOUCH = (ENC_TOUCH_L, ENC_TOUCH_M, ENC_TOUCH_R)
MODE_BUTTONS = (PAN, SEND, EQ, PLUGIN)

# Encoder turns: CC 0x10/0x11/0x12, value 01..3f = +ticks, 41..7f = -ticks
ENC_CC = (0x10, 0x11, 0x12)

FADER_MAX = 1023  # 10-bit position in pitch bend: e0 yy zz, yy = (pos & 7) << 4, zz = pos >> 3

LCD_COLS = 16
LCD_LINE_1 = 0x00
LCD_LINE_2 = 0x10
SYSEX_LCD_PREFIX = (0xF0, 0x00, 0x01, 0x40, 0x20, 0x00)
SYSEX_END = (0xF7,)
FORCE_NATIVE_MODE = (0xF0, 0x00, 0x01, 0x40, 0x20, 0x01, 0x00, 0xF7)

# Encoder modes
MODE_PAN = 0
MODE_SEND = 1
MODE_DEVICE = 2
MODE_NAMES = ("Pan", "Send", "Device")

ENCODER_STEPS = 64.0  # ticks for a full parameter sweep
STRIP_BEATS_PER_STEP = 1.0
