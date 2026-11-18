# Ableton Live Control Surface script for the Frontier Design AlphaTrack,
# speaking its documented Native-mode MIDI through MacAlphaTrack's virtual ports.
# Modelled on Live's bundled Tranzport script: a plain object, no _Framework.
from __future__ import absolute_import, division, print_function, unicode_literals

import Live
from .consts import *

# Live's own curated parameter banks ("Best of" plus named banks per device type).
try:
    from _Generic.Devices import best_of_parameter_bank, parameter_bank_names, parameter_banks
except ImportError:  # not running inside Live
    best_of_parameter_bank = parameter_bank_names = parameter_banks = None


def _clamp(value, lo, hi):
    return lo if value < lo else hi if value > hi else value


def _abbr(name, width):
    """Fit a parameter name into `width` characters: drop inner vowels and spaces first."""
    name = (name or "").strip()
    if len(name) <= width:
        return name
    return (name[0] + "".join(c for c in name[1:] if c not in "aeiou "))[:width]


def _device_to_appoint(device):
    """A drum rack without macro mappings stands in for the first device of its selected
    chain (same rule as Live's own DeviceProvider)."""
    try:
        if device != None and device.can_have_drum_pads and not device.has_macro_mappings \
                and len(device.chains) > 0:
            chain = device.view.selected_chain
            if chain != None and len(chain.devices) > 0:
                return _device_to_appoint(chain.devices[0])
    except AttributeError:
        pass
    return device


def _encoder_delta(cc_value):
    """01..3f = +ticks, 41..7f = -ticks (Native mode relative encoding)."""
    if 0x01 <= cc_value <= 0x3F:
        return cc_value
    if 0x41 <= cc_value <= 0x7F:
        return -(cc_value - 0x40)
    return 0


def _fader_to_fraction(lsb, msb):
    return ((msb << 3) | (lsb >> 4)) / float(FADER_MAX)


def _fraction_to_fader(fraction):
    pos = int(round(_clamp(fraction, 0.0, 1.0) * FADER_MAX))
    return (PITCHBEND_STATUS, (pos & 0x7) << 4, pos >> 3)


def _lcd_bytes(text, width=LCD_COLS):
    text = (text or "")[:width].ljust(width)
    out = []
    for ch in text:
        code = ord(ch)
        out.append(code if 0x20 <= code <= 0x7E else 0x20)
    return tuple(out)


class AlphaTrack(object):

    def __init__(self, c_instance):
        self._c = c_instance
        self._shift = False
        self._fader_touched = False
        self._mode = MODE_PAN
        self._device_page = 0
        self._send_page = 0
        self._rew_held = False
        self._ffwd_held = False
        self._spool = 1.0
        self._strip_pos = None
        self._strip_fingers = 0
        self._shuttle_origin = None
        self._shuttle_speed = 0
        self._flip = False
        self._pages_cache = None  # (device, pages)
        self._locked_device = None
        self._last_lines = (None, None)
        self._pending_lines = ("", "")
        self._param_hint = None  # (text, ticks_to_live)
        self._track = None
        self._song_listeners = []
        self._track_listeners = []
        self._all_track_solo_listeners = []
        self._last_fader_sent = None

        self.send_midi(FORCE_NATIVE_MODE)
        if hasattr(self._c, "update_locks"):
            self._c.update_locks()   # tell Live to re-read can_lock_to_devices()
        self._install_song_listeners()
        self._attach_track(self.song().view.selected_track)
        self._set_lines("    AlphaTrack  ", " Ableton  Live  ")
        self._flush_lcd()
        self.refresh_state()

    # ----- Live plumbing -------------------------------------------------

    def application(self):
        return Live.Application.get_application()

    def song(self):
        return self._c.song()

    def send_midi(self, midi_bytes):
        self._c.send_midi(tuple(midi_bytes))

    def log(self, message):
        try:
            self._c.log_message("AlphaTrack: %s" % message)
        except Exception:
            pass

    def suggest_input_port(self):
        return "AlphaTrack"

    def suggest_output_port(self):
        return "AlphaTrack"

    def suggest_map_mode(self, *_):
        return Live.MidiMap.MapMode.relative_signed_bit

    # Device support. Live only shows the blue hand on the appointed device for a surface
    # that declares it can lock to devices, so the lock protocol is implemented in full.
    def can_lock_to_devices(self):
        return True

    def lock_to_device(self, device):
        """Live asks us to stay on `device` regardless of the selection."""
        self._locked_device = device
        self._on_appointed_device_changed()

    def unlock_from_device(self, device):
        self._locked_device = None
        self._appoint_selected_device()

    def restore_bank(self, bank_index):
        pass  # pages are kept per session only

    def toggle_lock(self):
        self._c.toggle_lock()

    def connect_script_instances(self, instanciated_scripts):
        pass

    def request_rebuild_midi_map(self):
        self._c.request_rebuild_midi_map()

    def build_midi_map(self, midi_map_handle):
        script_handle = self._c.handle()
        for note in range(128):
            Live.MidiMap.forward_midi_note(script_handle, midi_map_handle, 0, note)
        for cc in ENC_CC:
            Live.MidiMap.forward_midi_cc(script_handle, midi_map_handle, 0, cc)
        Live.MidiMap.forward_midi_pitchbend(script_handle, midi_map_handle, 0)
        Live.MidiMap.forward_midi_pitchbend(script_handle, midi_map_handle, 9)

    def disconnect(self):
        self._remove_song_listeners()
        self._detach_track()
        for note in (RECORD, REC_ARM, MUTE, SOLO, ANY_SOLO_LED, LOOP, SHIFT, AUTO,
                     TRACK_L, TRACK_R, F2, F4, PAN, SEND, EQ, PLUGIN, FLIP,
                     AUTO_READ_LED, AUTO_WRITE_LED):
            self._led(note, False)
        self.send_midi(SYSEX_LCD_PREFIX + (LCD_LINE_1,) + _lcd_bytes("") + _lcd_bytes("") + SYSEX_END)

    # ----- listeners ------------------------------------------------------

    def _install_song_listeners(self):
        song = self.song()
        pairs = (
            (song.view, "selected_track", self._on_selected_track_changed),
            (song, "record_mode", self._update_record_led),
            (song, "loop", self._update_loop_led),
            (song, "metronome", self._update_f4_led),
            (song, "session_automation_record", self._update_auto_led),
            (song, "re_enable_automation_enabled", self._update_auto_led),
            (song, "appointed_device", self._on_appointed_device_changed),
            (song, "tracks", self._on_tracks_changed),
            (song, "tempo", self._request_line2),
            (song.view, "selected_scene", self._request_line2),
        )
        for obj, name, cb in pairs:
            if not hasattr(obj, "add_%s_listener" % name):
                continue
            getattr(obj, "add_%s_listener" % name)(cb)
            self._song_listeners.append((obj, name, cb))
        self._listen_all_solos()

    def _remove_song_listeners(self):
        for obj, name, cb in self._song_listeners:
            if getattr(obj, "%s_has_listener" % name)(cb):
                getattr(obj, "remove_%s_listener" % name)(cb)
        self._song_listeners = []
        for track in self._all_track_solo_listeners:
            if track.solo_has_listener(self._update_any_solo_led):
                track.remove_solo_listener(self._update_any_solo_led)
        self._all_track_solo_listeners = []

    def _listen_all_solos(self):
        for track in list(self.song().tracks) + list(self.song().return_tracks):
            if not track.solo_has_listener(self._update_any_solo_led):
                track.add_solo_listener(self._update_any_solo_led)
                self._all_track_solo_listeners.append(track)

    def _attach_track(self, track):
        self._track = track
        if track is None:
            return
        pairs = [("name", self._request_line1)]
        if track is not self.song().master_track:
            # Live's master track has no mute/solo properties at all.
            pairs += [("mute", self._update_mute_led), ("solo", self._update_solo_led)]
        if track.can_be_armed:
            pairs.append(("arm", self._update_arm_led))
        for name, cb in pairs:
            getattr(track, "add_%s_listener" % name)(cb)
            self._track_listeners.append((track, name, cb))
        if track.has_audio_output:
            mixer = track.mixer_device
            mixer.volume.add_value_listener(self._on_volume_changed)
            mixer.panning.add_value_listener(self._request_line2)
            self._track_listeners.append((mixer.volume, "value", self._on_volume_changed))
            self._track_listeners.append((mixer.panning, "value", self._request_line2))
            for send in mixer.sends:
                send.add_value_listener(self._request_line2)
                self._track_listeners.append((send, "value", self._request_line2))
        track.view.add_selected_device_listener(self._on_device_changed)
        self._track_listeners.append((track.view, "selected_device", self._on_device_changed))
        self._appoint_selected_device()

    def _detach_track(self):
        for obj, name, cb in self._track_listeners:
            try:
                if getattr(obj, "%s_has_listener" % name)(cb):
                    getattr(obj, "remove_%s_listener" % name)(cb)
            except Exception:
                pass
        self._track_listeners = []
        self._track = None

    def _on_selected_track_changed(self):
        self._detach_track()
        self._attach_track(self.song().view.selected_track)
        self._device_page = 0
        self._send_page = 0
        self.refresh_state()

    def _on_tracks_changed(self):
        self._listen_all_solos()
        self._update_any_solo_led()
        self._update_track_leds()

    def _on_device_changed(self):
        """The track's selected device changed: give it Live's blue hand."""
        self._appoint_selected_device()

    def _appoint_selected_device(self):
        t = self._track
        song = self.song()
        if t is None or not hasattr(song, "appointed_device"):
            return
        device = t.view.selected_device
        if device == None and len(t.devices) > 0:
            device = t.devices[0]
        device = _device_to_appoint(device)
        if song.appointed_device != device:
            try:
                song.appointed_device = device   # fires _on_appointed_device_changed
                return
            except RuntimeError as e:            # Live refused the change at this moment
                self.log("could not appoint device: %r" % (e,))
        self._on_appointed_device_changed()

    def _on_appointed_device_changed(self):
        """The blue-hand device changed (by us, by a click in Live, or another surface)."""
        self._pages_cache = None
        self._device_page = 0
        if self._mode == MODE_DEVICE:
            device = self._selected_device()
            self._hint(device.name if device != None else "No device")
        self._send_fader_position()
        self._request_line2()

    def _on_volume_changed(self):
        self._send_fader_position()
        self._request_line2()

    def _request_line1(self):
        self._pending_lines = (None, self._pending_lines[1])

    def _request_line2(self):
        self._pending_lines = (self._pending_lines[0], None)

    # ----- state -> device -------------------------------------------------

    def refresh_state(self):
        self._last_lines = (None, None)
        self._update_record_led()
        self._update_loop_led()
        self._update_arm_led()
        self._update_mute_led()
        self._update_solo_led()
        self._update_any_solo_led()
        self._update_auto_led()
        self._update_f4_led()
        self._update_f2_led()
        self._update_mode_leds()
        self._update_track_leds()
        self._led(SHIFT, self._shift)
        self._led(FLIP, self._flip)
        self._last_fader_sent = None
        self._send_fader_position()
        self._pending_lines = (None, None)

    def _led(self, note, on):
        self.send_midi((NOTE_ON_STATUS, note, LED_ON if on else LED_OFF))

    def _update_record_led(self):
        self._led(RECORD, self.song().record_mode)

    def _update_loop_led(self):
        self._led(LOOP, self.song().loop)

    def _update_auto_led(self):
        """AUTO and WRITE show automation arm; READ is lit while Live is playing back all
        automation, and goes dark when some automated parameter has been overridden
        (Live's "Re-Enable Automation" button lights up). SHIFT+AUTO re-enables it."""
        song = self.song()
        armed = bool(song.session_automation_record)
        self._led(AUTO, armed)
        self._led(AUTO_WRITE_LED, armed)
        self._led(AUTO_READ_LED, not getattr(song, "re_enable_automation_enabled", False))

    def _update_f4_led(self):
        self._led(F4, self.song().metronome)

    def _update_f2_led(self):
        self._led(F2, self.application().view.is_view_visible("Session"))

    def _update_arm_led(self):
        t = self._track
        self._led(REC_ARM, bool(t is not None and t.can_be_armed and t.arm))

    def _update_mute_led(self):
        t = self._track
        self._led(MUTE, bool(t is not None and t is not self.song().master_track and t.mute))

    def _update_solo_led(self):
        t = self._track
        self._led(SOLO, bool(t is not None and t is not self.song().master_track and t.solo))

    def _update_any_solo_led(self):
        soloed = any(t.solo for t in list(self.song().tracks) + list(self.song().return_tracks))
        self._led(ANY_SOLO_LED, soloed)

    def _update_mode_leds(self):
        self._led(PAN, self._mode == MODE_PAN)
        self._led(SEND, self._mode == MODE_SEND)
        self._led(PLUGIN, self._mode == MODE_DEVICE)
        self._led(EQ, False)

    def _update_track_leds(self):
        tracks = self._all_tracks()
        index = tracks.index(self._track) if self._track in tracks else -1
        self._led(TRACK_L, index > 0)
        self._led(TRACK_R, 0 <= index < len(tracks) - 1)

    def _send_fader_position(self, force=False):
        """Tell the fader where Live's volume is. The AlphaTrack servos the fader to the
        last position it was sent, so while the user moves it by hand Live's new value
        must be echoed straight back (as Frontier's and REAPER's drivers do); otherwise
        the fader springs back to the stale setpoint when the hand lets go."""
        param = self._fader_param()
        if param is None:
            return
        span = param.max - param.min
        msg = _fraction_to_fader((param.value - param.min) / span if span else 0.0)
        if force or msg != self._last_fader_sent:
            self._last_fader_sent = msg
            self.send_midi(msg)

    # ----- LCD ---------------------------------------------------------------

    def update_display(self):
        """Called by Live about 10 times a second."""
        if self._rew_held or self._ffwd_held:
            self._spool = min(self._spool + 0.25, 8.0)
            self.song().jump_by((1 if self._ffwd_held else -1) * self._spool)
        if self._shuttle_speed:
            self.song().jump_by(self._shuttle_speed * SHUTTLE_BEATS_PER_TICK)
        # Parameters without a value listener (device parameters under FLIP) are polled.
        self._send_fader_position()
        if self._param_hint is not None:
            text, ttl = self._param_hint
            self._param_hint = (text, ttl - 1) if ttl > 1 else None
            if self._param_hint is None:
                self._request_line2()
        line1, line2 = self._pending_lines
        if line1 is None:
            line1 = self._line1_text()
        if line2 is None:
            line2 = self._line2_text()
        self._set_lines(line1, line2)
        self._flush_lcd()

    def _set_lines(self, line1, line2):
        self._pending_lines = (line1, line2)

    def _flush_lcd(self):
        line1, line2 = self._pending_lines
        if line1 is None or line2 is None:
            return
        if line1 != self._last_lines[0]:
            self.send_midi(SYSEX_LCD_PREFIX + (LCD_LINE_1,) + _lcd_bytes(line1) + SYSEX_END)
        if line2 != self._last_lines[1]:
            self.send_midi(SYSEX_LCD_PREFIX + (LCD_LINE_2,) + _lcd_bytes(line2) + SYSEX_END)
        self._last_lines = (line1, line2)

    def _line1_text(self):
        if self._track is None:
            return "No track"
        return self._track.name

    def _line2_text(self):
        if self._shift:
            return self._position_text()
        if self._param_hint is not None:
            return self._param_hint[0]
        track = self._track
        if self._mode == MODE_DEVICE:
            return self._device_line()
        if track is None or not track.has_audio_output:
            return "No audio output"
        mixer = track.mixer_device
        if self._mode == MODE_PAN:
            return ("%-9s %6s" % (str(mixer.volume)[:9], str(mixer.panning)[:6]))
        if self._mode == MODE_SEND:
            sends = self._visible_sends()
            if not sends:
                return "No sends"
            return " ".join(("%-4s" % str(s)[:4]) for s in sends)[:LCD_COLS]
        return ""

    def _device_line(self):
        """Device mode: the three parameter names under the encoders."""
        device = self._selected_device()
        if device == None:
            return "No device"
        pages = self._device_pages()
        if not pages:
            return device.name
        params = pages[self._device_page % len(pages)][3]
        names = [p.name if p != None else "" for p in params] + ["", "", ""]
        return "%-5s %-5s %-4s" % (_abbr(names[0], 5), _abbr(names[1], 5), _abbr(names[2], 4))

    def _position_text(self):
        song = self.song()
        if self.application().view.is_view_visible("Session"):
            scenes = list(song.scenes)
            scene = song.view.selected_scene
            idx = scenes.index(scene) + 1 if scene in scenes else 0
            return "Scene%3d %6.1fbpm" % (idx, song.tempo)
        bt = song.get_current_beats_song_time()
        return "%3d.%d.%02d %6.1fbpm" % (bt.bars, bt.beats, bt.ticks, song.tempo)

    def _show_param(self, name, value_text):
        self._hint("%-8s%8s" % (name[:8], value_text[:8]))

    def _hint(self, text):
        """Show `text` on line 2 for about 1.5 s."""
        self._param_hint = (text, 15)
        self._pending_lines = (self._pending_lines[0], None)

    # ----- device -> state ---------------------------------------------------

    def receive_midi(self, midi_bytes):
        status = midi_bytes[0] & 0xF0
        if status in (NOTE_ON_STATUS, NOTE_OFF_STATUS):
            note, velocity = midi_bytes[1], midi_bytes[2]
            down = status == NOTE_ON_STATUS and velocity > 0
            self._on_button(note, down)
        elif status == CC_STATUS and midi_bytes[1] in ENC_CC:
            self._on_encoder(ENC_CC.index(midi_bytes[1]), _encoder_delta(midi_bytes[2]))
        elif midi_bytes[0] == PITCHBEND_STATUS:
            self._on_fader(_fader_to_fraction(midi_bytes[1], midi_bytes[2]))
        elif midi_bytes[0] == STRIP_STATUS:
            self._on_strip(midi_bytes[2] >> 2)

    def _on_button(self, note, down):
        song = self.song()
        if note == SHIFT:
            self._shift = down
            self._led(SHIFT, down)
            self._request_line2()
            return
        if note == FADER_TOUCH:
            self._fader_touched = down
            if not down:
                self._send_fader_position(force=True)
            return
        if note in (STRIP_TOUCH_1, STRIP_TOUCH_2):
            fingers = 1 if note == STRIP_TOUCH_1 else 2
            if down or self._strip_fingers == fingers:
                self._strip_fingers = fingers if down else 0
                self._strip_pos = None
                self._shuttle_origin = None
                self._shuttle_speed = 0
            return
        if note in ENC_TOUCH:
            return
        if note in (REW, FFWD):
            self._on_spool(note == FFWD, down)
            return
        if not down:
            return
        # Momentary buttons: act on press only.
        if note == PLAY:
            if self._shift:
                song.continue_playing()
            else:
                song.is_playing = True
        elif note == STOP:
            if song.is_playing:
                song.is_playing = False
            else:
                song.current_song_time = 0.0
        elif note == RECORD:
            song.record_mode = not song.record_mode
        elif note == FOOTSWITCH:
            song.is_playing = not song.is_playing
        elif note == LOOP:
            song.loop = not song.loop
        elif note == TRACK_L:
            self._select_track(-1)
        elif note == TRACK_R:
            self._select_track(1)
        elif note == REC_ARM:
            t = self._track
            if t is not None and t.can_be_armed:
                t.arm = not t.arm
        elif note == MUTE:
            t = self._track
            if t is not None and t is not song.master_track:
                t.mute = not t.mute
        elif note == SOLO:
            t = self._track
            if t is not None and t is not song.master_track:
                t.solo = not t.solo
        elif note == PAN:
            self._set_mode(MODE_PAN)
        elif note == SEND:
            if self._mode == MODE_SEND:
                self._send_page += 1
                if self._send_page * 3 >= len(self._all_sends()):
                    self._send_page = 0
                self._send_fader_position()
                self._request_line2()
            else:
                self._set_mode(MODE_SEND)
        elif note in (PLUGIN, EQ):
            if self._mode == MODE_DEVICE and note == PLUGIN:
                self._page_device(-1 if self._shift else 1)
            else:
                self._set_mode(MODE_DEVICE)
                device = self._selected_device()
                self._hint(device.name if device != None else "No device")
        elif note == AUTO:
            if self._shift:
                if hasattr(song, "re_enable_automation"):
                    song.re_enable_automation()
            else:
                song.session_automation_record = not song.session_automation_record
        elif note == F1:
            if self._shift:
                if song.can_redo:
                    song.redo()
            elif song.can_undo:
                song.undo()
        elif note == F2:
            view = self.application().view
            view.show_view("Arranger" if view.is_view_visible("Session") else "Session")
            self._update_f2_led()
            self._request_line2()
        elif note == F3:
            self._fire()
        elif note == F4:
            song.metronome = not song.metronome
        elif note in ENC_PUSH:
            self._on_encoder_push(ENC_PUSH.index(note))
        elif note == FLIP:
            self._flip = not self._flip
            self._led(FLIP, self._flip)
            self._send_fader_position()
            self._request_line2()

    def _on_spool(self, forward, down):
        if down:
            self.song().jump_by(1 if forward else -1)
            self._spool = 1.0
        if forward:
            self._ffwd_held = down
        else:
            self._rew_held = down

    def _set_mode(self, mode):
        self._mode = mode
        self._param_hint = None
        self._update_mode_leds()
        self._send_fader_position()
        self._request_line2()

    def _page_device(self, direction):
        pages = self._device_pages()
        if not pages:
            return
        self._device_page = (self._device_page + direction) % len(pages)
        bank, index, count, _ = pages[self._device_page]
        self._hint("%-12s%4s" % (bank[:12], "%d/%d" % (index, count)))
        self._send_fader_position()

    def _fire(self):
        song = self.song()
        if self.application().view.is_view_visible("Session"):
            if self._shift:
                song.view.selected_scene.fire_as_selected()
            else:
                slot = song.view.highlighted_clip_slot
                if slot is not None:
                    slot.fire()
        else:
            song.view.selected_scene.fire_as_selected()

    def _on_fader(self, fraction):
        param = self._fader_param()
        if param is None:
            return
        param.value = _clamp(param.min + fraction * (param.max - param.min), param.min, param.max)
        self._send_fader_position()  # echo the new setpoint (a no-op if a listener already did)
        if self._flip:
            self._show_param(param.name, str(param))

    def _on_encoder(self, index, ticks):
        if ticks == 0:
            return
        param = self._encoder_param(index)
        if param is None:
            return
        self._nudge(param, ticks)
        self._show_param(param.name, str(param))

    def _on_encoder_push(self, index):
        param = self._encoder_param(index)
        if param is None:
            return
        if self._mode == MODE_PAN and index == 0:
            param.value = 0.0
        elif self._mode == MODE_SEND:
            param.value = param.min
        else:
            return
        self._show_param(param.name, str(param))

    def _nudge(self, param, ticks):
        span = param.max - param.min
        if param.is_quantized:
            step = 1.0
        else:
            step = span / ENCODER_STEPS
            if self._shift:
                step /= 8.0
        param.value = _clamp(param.value + ticks * step, param.min, param.max)

    def _on_strip(self, position):
        if self._strip_fingers == 2:
            # Shuttle: the first two-finger position is zero speed; offset sets the speed.
            if self._shuttle_origin is None:
                self._shuttle_origin = position
            self._shuttle_speed = position - self._shuttle_origin
            return
        if self._strip_pos is None:
            self._strip_pos = position
            return
        delta = position - self._strip_pos
        self._strip_pos = position
        if delta == 0:
            return
        song = self.song()
        if self.application().view.is_view_visible("Session"):
            scenes = list(song.scenes)
            if song.view.selected_scene in scenes:
                idx = _clamp(scenes.index(song.view.selected_scene) + delta, 0, len(scenes) - 1)
                song.view.selected_scene = scenes[idx]
        else:
            song.jump_by(delta * STRIP_BEATS_PER_STEP)

    # ----- helpers --------------------------------------------------------------

    def _all_tracks(self):
        song = self.song()
        return list(song.visible_tracks) + list(song.return_tracks) + [song.master_track]

    def _select_track(self, direction):
        tracks = self._all_tracks()
        if self._track not in tracks:
            return
        idx = _clamp(tracks.index(self._track) + direction, 0, len(tracks) - 1)
        self.song().view.selected_track = tracks[idx]

    def _all_sends(self):
        t = self._track
        if t is None or not t.has_audio_output:
            return []
        return list(t.mixer_device.sends)

    def _visible_sends(self):
        sends = self._all_sends()
        start = self._send_page * 3
        return sends[start:start + 3]

    def _selected_device(self):
        """The device the encoders act on: Live's appointed (blue hand) device, falling back
        to the track's selected or first device."""
        if self._locked_device != None:
            return self._locked_device
        appointed = getattr(self.song(), "appointed_device", None)
        if appointed != None:
            return appointed
        t = self._track
        if t is None:
            return None
        device = t.view.selected_device
        if device == None and len(t.devices) > 0:
            device = t.devices[0]
        return device

    def _device_pages(self):
        """Pages of up to three parameters: Live's "Best of" bank first, then its named banks,
        each bank split in threes. A page is (bank name, index in bank, pages in bank, params)."""
        device = self._selected_device()
        if device == None:
            return []
        if self._pages_cache is not None and self._pages_cache[0] == device:
            return self._pages_cache[1]
        banks = []
        if parameter_banks is not None:
            try:
                named = [list(b) for b in parameter_banks(device)]
                names = list(parameter_bank_names(device))
                best = list(best_of_parameter_bank(device))
                if named and [p for p in best if p != None] != [p for p in named[0] if p != None]:
                    banks.append(("Best of", best))
                for n, bank in enumerate(named):
                    banks.append((names[n] if n < len(names) else "Bank %d" % (n + 1), bank))
            except Exception as e:  # fall back to the raw parameter list
                self.log("bank lookup failed for %s: %r" % (getattr(device, "class_name", "?"), e))
                banks = []
        if not banks:
            raw = list(device.parameters)[1:]  # parameter 0 is Device On
            banks = [("Bank %d" % (n // 8 + 1), raw[n:n + 8]) for n in range(0, len(raw), 8)]
        pages = []
        for name, bank in banks:
            params = [p for p in bank if p != None]
            count = (len(params) + 2) // 3
            for k in range(count):
                pages.append((name, k + 1, count, params[k * 3:k * 3 + 3]))
        self._pages_cache = (device, pages)
        return pages

    def _volume_param(self):
        t = self._track
        if t is None or not t.has_audio_output:
            return None
        return t.mixer_device.volume

    def _fader_param(self):
        """What the fader controls: track volume, or under FLIP the left encoder's parameter."""
        return self._mode_param(0) if self._flip else self._volume_param()

    def _encoder_param(self, index):
        """What an encoder controls; under FLIP the left encoder takes over the volume."""
        if self._flip and index == 0:
            return self._volume_param()
        return self._mode_param(index)

    def _mode_param(self, index):
        t = self._track
        if t is None:
            return None
        if self._mode == MODE_PAN:
            if not t.has_audio_output:
                return None
            mixer = t.mixer_device
            return (mixer.panning, mixer.volume, None)[index]
        if self._mode == MODE_SEND:
            sends = self._visible_sends()
            return sends[index] if index < len(sends) else None
        pages = self._device_pages()
        if not pages:
            return None
        params = pages[self._device_page % len(pages)][3]
        return params[index] if index < len(params) else None
