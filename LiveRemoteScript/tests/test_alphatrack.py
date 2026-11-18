import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))

import fake_live  # noqa: E402
LIVE = fake_live.install()

from AlphaTrack import create_instance  # noqa: E402
from AlphaTrack.consts import *  # noqa: E402,F403


def lcd(sent, line):
    """Text of the most recent LCD write to `line` (0x00 or 0x10)."""
    prefix = SYSEX_LCD_PREFIX + (line,)
    for msg in reversed(sent):
        if msg[:7] == prefix:
            return "".join(chr(b) for b in msg[7:-1])
    return None


def led(sent, note):
    for msg in reversed(sent):
        if msg[0] == NOTE_ON_STATUS and msg[1] == note:
            return msg[2] == LED_ON
    return None


class AlphaTrackScriptTests(unittest.TestCase):
    def setUp(self):
        eq = fake_live.Device("EQ Eight", [fake_live.DeviceParameter("1 Freq A", 0.5, fmt=lambda v: "%d Hz" % (v * 1000)),
                                           fake_live.DeviceParameter("1 Gain A", 0.5),
                                           fake_live.DeviceParameter("1 Q A", 0.5),
                                           fake_live.DeviceParameter("2 Freq A", 0.5)])
        self.song = fake_live.Song([fake_live.Track("Drums", devices=[eq]), fake_live.Track("Bass"),
                                    fake_live.Track("MIDI", has_audio_output=False)])
        LIVE.Application.get_application().view.visible = "Arranger"
        self.c = fake_live.CInstance(self.song)
        self.script = create_instance(self.c)
        self.sent = self.c.sent

    def press(self, note):
        self.script.receive_midi((NOTE_ON_STATUS, note, 127))

    def release(self, note):
        self.script.receive_midi((NOTE_ON_STATUS, note, 0))

    def tap(self, note):
        self.press(note)
        self.release(note)

    def tick(self, n=1):
        for _ in range(n):
            self.script.update_display()

    # --- startup / plumbing

    def test_startup_forces_native_mode_and_shows_track(self):
        self.assertEqual(self.sent[0], FORCE_NATIVE_MODE)
        self.tick()
        self.assertEqual(lcd(self.sent, LCD_LINE_1), "Drums".ljust(16))
        self.assertEqual(lcd(self.sent, LCD_LINE_2), "0.0 dB         C")
        self.assertTrue(led(self.sent, PAN))
        self.assertFalse(led(self.sent, SEND))
        self.assertFalse(led(self.sent, TRACK_L))
        self.assertTrue(led(self.sent, TRACK_R))
        self.assertEqual(self.script.suggest_input_port(), "AlphaTrack")

    def test_midi_map_forwards_notes_encoders_and_pitchbend(self):
        LIVE.MidiMap.forwarded = []
        self.script.build_midi_map("map")
        f = LIVE.MidiMap.forwarded
        self.assertEqual(len([x for x in f if x[0] == "note"]), 128)
        self.assertEqual(sorted(x[2] for x in f if x[0] == "cc"), [0x10, 0x11, 0x12])
        self.assertIn(("pb", 0), f)
        self.assertIn(("pb", 9), f)

    def test_disconnect_removes_all_listeners_and_clears_display(self):
        self.script.disconnect()
        for obj in [self.song, self.song.view] + self.song.tracks + self.song.return_tracks:
            self.assertEqual(obj.listener_count(), 0, obj)
        t = self.song.tracks[0]
        self.assertEqual(t.mixer_device.volume.listener_count(), 0)
        self.assertEqual(t.view.listener_count(), 0)
        self.assertEqual(self.sent[-1], SYSEX_LCD_PREFIX + (0,) + (32,) * 32 + SYSEX_END)
        self.assertFalse(led(self.sent, RECORD))

    # --- transport

    def test_transport_buttons(self):
        self.tap(PLAY)
        self.assertTrue(self.song.is_playing)
        self.tap(STOP)
        self.assertFalse(self.song.is_playing)
        self.song.current_song_time = 8.0
        self.tap(STOP)  # second stop returns to start
        self.assertEqual(self.song.current_song_time, 0.0)
        self.press(SHIFT)
        self.tap(PLAY)
        self.release(SHIFT)
        self.assertEqual(self.song.continued, 1)
        self.tap(RECORD)
        self.assertTrue(self.song.record_mode)
        self.assertTrue(led(self.sent, RECORD))
        self.tap(LOOP)
        self.assertTrue(self.song.loop)
        self.assertTrue(led(self.sent, LOOP))
        self.tap(FOOTSWITCH)
        self.assertFalse(self.song.is_playing)

    def test_ffwd_nudges_then_spools_while_held(self):
        self.press(FFWD)
        self.assertEqual(self.song.current_song_time, 1.0)
        self.tick(2)
        self.assertGreater(self.song.current_song_time, 3.0)
        t = self.song.current_song_time
        self.release(FFWD)
        self.tick(2)
        self.assertEqual(self.song.current_song_time, t)

    # --- track strip

    def test_track_navigation_and_leds(self):
        self.tap(TRACK_R)
        self.assertEqual(self.song.view.selected_track.name, "Bass")
        self.tick()
        self.assertEqual(lcd(self.sent, LCD_LINE_1), "Bass".ljust(16))
        self.assertTrue(led(self.sent, TRACK_L))
        for _ in range(5):
            self.tap(TRACK_R)
        self.assertIs(self.song.view.selected_track, self.song.master_track)
        self.assertFalse(led(self.sent, TRACK_R))
        self.tap(MUTE)  # master has no mute: must not raise
        self.tap(SOLO)
        self.tick()
        self.assertEqual(lcd(self.sent, LCD_LINE_1), "Master".ljust(16))
        self.assertFalse(led(self.sent, MUTE))
        self.assertFalse(led(self.sent, SOLO))
        self.tap(TRACK_L)
        self.assertEqual(self.song.view.selected_track.name, "Return A")

    def test_mute_solo_arm_follow_and_control_selected_track(self):
        drums = self.song.tracks[0]
        self.tap(MUTE)
        self.assertTrue(drums.mute)
        self.assertTrue(led(self.sent, MUTE))
        self.tap(SOLO)
        self.assertTrue(drums.solo)
        self.assertTrue(led(self.sent, SOLO))
        self.assertTrue(led(self.sent, ANY_SOLO_LED))
        self.tap(REC_ARM)
        self.assertTrue(drums.arm)
        self.assertTrue(led(self.sent, REC_ARM))
        # Changes made in Live are reflected too.
        drums.mute = False
        self.assertFalse(led(self.sent, MUTE))
        self.song.tracks[1].solo = True
        drums.solo = False
        self.assertFalse(led(self.sent, SOLO))
        self.assertTrue(led(self.sent, ANY_SOLO_LED))

    # --- fader

    def test_fader_moves_volume_and_volume_moves_fader(self):
        self.script.receive_midi((PITCHBEND_STATUS, 0x00, 0x40))  # 512/1023
        self.assertAlmostEqual(self.song.tracks[0].mixer_device.volume.value, 512 / 1023.0)
        del self.sent[:]
        self.song.tracks[0].mixer_device.volume.value = 1.0
        self.assertIn((PITCHBEND_STATUS, 0x70, 0x7F), self.sent)

    def test_hand_moves_are_echoed_so_the_fader_holds_its_new_position(self):
        # The unit servos to the last commanded position: every hand move must come
        # straight back as the new setpoint, and the release must resend it.
        self.press(FADER_TOUCH)
        del self.sent[:]
        self.script.receive_midi((PITCHBEND_STATUS, 0x00, 0x40))  # 512
        self.assertEqual([m for m in self.sent if m[0] == PITCHBEND_STATUS], [(PITCHBEND_STATUS, 0x00, 0x40)])
        del self.sent[:]
        self.release(FADER_TOUCH)
        self.assertEqual([m for m in self.sent if m[0] == PITCHBEND_STATUS], [(PITCHBEND_STATUS, 0x00, 0x40)])

    def test_selecting_track_sends_its_fader_position(self):
        self.song.tracks[1].mixer_device.volume.value = 0.0
        del self.sent[:]
        self.tap(TRACK_R)
        self.assertIn((PITCHBEND_STATUS, 0x00, 0x00), self.sent)

    # --- encoders

    def test_pan_mode_encoder_and_push(self):
        pan = self.song.tracks[0].mixer_device.panning
        self.script.receive_midi((CC_STATUS, 0x10, 0x08))  # +8 ticks
        self.assertAlmostEqual(pan.value, 8 * 2.0 / 64)
        self.script.receive_midi((CC_STATUS, 0x10, 0x44))  # -4 ticks
        self.assertAlmostEqual(pan.value, 4 * 2.0 / 64)
        self.tick()
        self.assertTrue(lcd(self.sent, LCD_LINE_2).startswith("Pan"))
        self.tap(ENC_PUSH_L)
        self.assertEqual(pan.value, 0.0)
        # parameter hint times out back to the normal line
        self.tick(20)
        self.assertEqual(lcd(self.sent, LCD_LINE_2), "0.0 dB         C")

    def test_send_mode_and_paging(self):
        self.tap(SEND)
        self.assertTrue(led(self.sent, SEND))
        self.assertFalse(led(self.sent, PAN))
        sends = self.song.tracks[0].mixer_device.sends
        self.script.receive_midi((CC_STATUS, 0x11, 0x10))
        self.assertAlmostEqual(sends[1].value, 16 / 64.0)
        self.script.receive_midi((CC_STATUS, 0x12, 0x10))  # no third send: ignored
        self.tap(ENC_PUSH_M)
        self.assertEqual(sends[1].value, 0.0)
        self.tick(20)
        self.assertEqual(lcd(self.sent, LCD_LINE_2), "0.00 0.00".ljust(16))

    def test_device_mode_pages_parameters(self):
        self.tap(PLUGIN)
        self.tick()
        self.assertEqual(lcd(self.sent, LCD_LINE_2), "EQ Eight".ljust(16))
        params = self.song.tracks[0].devices[0].parameters
        self.script.receive_midi((CC_STATUS, 0x10, 0x01))
        self.assertAlmostEqual(params[1].value, 0.5 + 1 / 64.0)
        self.tick()
        self.assertEqual(lcd(self.sent, LCD_LINE_2), "1 Freq A  515 Hz")
        self.tap(PLUGIN)  # next page
        self.script.receive_midi((CC_STATUS, 0x10, 0x01))
        self.assertAlmostEqual(params[4].value, 0.5 + 1 / 64.0)
        self.script.receive_midi((CC_STATUS, 0x11, 0x01))  # nothing on page 2 slot 2
        self.tap(PLUGIN)  # wraps to page 1
        self.assertEqual(self.script._device_page, 0)

    def test_shift_makes_encoders_fine(self):
        pan = self.song.tracks[0].mixer_device.panning
        self.press(SHIFT)
        self.script.receive_midi((CC_STATUS, 0x10, 0x08))
        self.release(SHIFT)
        self.assertAlmostEqual(pan.value, 8 * 2.0 / 64 / 8)

    def test_midi_track_without_audio_output(self):
        self.tap(TRACK_R)
        self.tap(TRACK_R)
        self.tick()
        self.assertEqual(lcd(self.sent, LCD_LINE_2), "No audio output".ljust(16))
        self.script.receive_midi((PITCHBEND_STATUS, 0x00, 0x40))  # ignored, no crash
        self.script.receive_midi((CC_STATUS, 0x10, 0x01))

    # --- shift display, F-keys, strip

    def test_shift_shows_position_and_tempo(self):
        self.song.current_song_time = 5.0
        self.press(SHIFT)
        self.tick()
        self.assertEqual(lcd(self.sent, LCD_LINE_2), "  2.2.00  120.0bpm"[:16])
        self.assertTrue(led(self.sent, SHIFT))
        self.release(SHIFT)
        self.assertFalse(led(self.sent, SHIFT))

    def test_function_keys(self):
        self.tap(F1)
        self.assertEqual(self.song.undone, 1)
        self.song.can_redo = True
        self.press(SHIFT)
        self.tap(F1)
        self.release(SHIFT)
        self.assertEqual(self.song.redone, 1)
        self.tap(F2)
        self.assertTrue(LIVE.Application.get_application().view.is_view_visible("Session"))
        self.assertTrue(led(self.sent, F2))
        self.tap(F3)
        self.assertEqual(self.song.view.highlighted_clip_slot.fired, 1)
        self.press(SHIFT)
        self.tap(F3)
        self.release(SHIFT)
        self.assertEqual(self.song.scenes[0].fired, 1)
        self.tap(F4)
        self.assertTrue(self.song.metronome)
        self.assertTrue(led(self.sent, F4))
        self.tap(AUTO)
        self.assertTrue(self.song.session_automation_record)
        self.assertTrue(led(self.sent, AUTO))

    def test_strip_scrubs_arrangement_and_scrolls_scenes(self):
        self.press(STRIP_TOUCH_1)
        self.script.receive_midi((STRIP_STATUS, 0, 10 << 2))
        self.script.receive_midi((STRIP_STATUS, 0, 14 << 2))
        self.assertEqual(self.song.current_song_time, 4.0)
        self.release(STRIP_TOUCH_1)
        self.tap(F2)  # Session view
        self.press(STRIP_TOUCH_1)
        self.script.receive_midi((STRIP_STATUS, 0, 3 << 2))
        self.script.receive_midi((STRIP_STATUS, 0, 5 << 2))
        self.assertIs(self.song.view.selected_scene, self.song.scenes[2])
        self.release(STRIP_TOUCH_1)

    def test_flip_swaps_fader_and_left_encoder(self):
        mixer = self.song.tracks[0].mixer_device
        del self.sent[:]
        self.tap(FLIP)
        self.assertTrue(led(self.sent, FLIP))
        # fader jumps to the pan position (centre)
        self.assertIn((PITCHBEND_STATUS, 0x00, 0x40), self.sent)
        self.script.receive_midi((PITCHBEND_STATUS, 0x70, 0x7F))  # fader to top -> pan hard right
        self.assertAlmostEqual(mixer.panning.value, 1.0)
        vol = mixer.volume.value
        self.script.receive_midi((CC_STATUS, 0x10, 0x48))  # left encoder -8 -> volume down
        self.assertAlmostEqual(mixer.volume.value, vol - 8 / 64.0)
        # in device mode the fader follows a parameter that has no listener (polled)
        self.tap(PLUGIN)
        params = self.song.tracks[0].devices[0].parameters
        params[1].value = 0.0
        del self.sent[:]
        self.tick()
        self.assertIn((PITCHBEND_STATUS, 0x00, 0x00), self.sent)
        # unflip: fader returns to the volume
        self.tap(FLIP)
        self.assertFalse(led(self.sent, FLIP))
        self.script.receive_midi((PITCHBEND_STATUS, 0x00, 0x40))
        self.assertAlmostEqual(mixer.volume.value, 512 / 1023.0)

    def test_two_finger_strip_shuttles(self):
        self.song.current_song_time = 100.0
        self.press(STRIP_TOUCH_2)
        self.script.receive_midi((STRIP_STATUS, 0, 10 << 2))   # origin: zero speed
        self.tick()
        self.assertEqual(self.song.current_song_time, 100.0)
        self.script.receive_midi((STRIP_STATUS, 0, 14 << 2))   # 4 steps right
        self.tick(2)
        self.assertEqual(self.song.current_song_time, 104.0)
        self.script.receive_midi((STRIP_STATUS, 0, 8 << 2))    # 2 steps left of origin
        self.tick()
        self.assertEqual(self.song.current_song_time, 103.0)
        self.release(STRIP_TOUCH_2)
        self.tick(3)
        self.assertEqual(self.song.current_song_time, 103.0)

    def test_automation_leds_and_re_enable(self):
        self.assertTrue(led(self.sent, AUTO_READ_LED))
        self.assertFalse(led(self.sent, AUTO_WRITE_LED))
        self.tap(AUTO)
        self.assertTrue(led(self.sent, AUTO_WRITE_LED))
        self.song.re_enable_automation_enabled = True      # user overrode an automated parameter
        self.assertFalse(led(self.sent, AUTO_READ_LED))
        self.press(SHIFT)
        self.tap(AUTO)
        self.release(SHIFT)
        self.assertFalse(self.song.re_enable_automation_enabled)
        self.assertTrue(led(self.sent, AUTO_READ_LED))
        self.assertTrue(self.song.session_automation_record)  # SHIFT+AUTO did not toggle arm

    def test_lcd_only_resent_on_change(self):
        self.tick(3)
        n = len(self.sent)
        self.tick(3)
        self.assertEqual(len(self.sent), n)


if __name__ == "__main__":
    unittest.main()
