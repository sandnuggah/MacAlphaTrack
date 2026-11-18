"""A minimal stand-in for Live's Python API, enough to drive the AlphaTrack script.

Only the surface the script touches is modelled. Listener plumbing follows Live's
naming: add_<prop>_listener / remove_<prop>_listener / <prop>_has_listener, with
listeners fired whenever the property is assigned.
"""
import sys
import types


class Observable(object):
    """Attributes listed in `_observed` fire listeners on assignment."""
    _observed = ()

    def __init__(self):
        object.__setattr__(self, "_listeners", {})

    def __setattr__(self, name, value):
        object.__setattr__(self, name, value)
        if name in self._observed:
            for cb in list(self._listeners.get(name, [])):
                cb()

    def __getattr__(self, name):
        # Live raises RuntimeError("Main track has no 'mute' property!") for the master track.
        if self.__dict__.get("is_master", False) and ("mute" in name or "solo" in name):
            raise RuntimeError("Main track has no %r property!" % name)
        for prefix, action in (("add_", "add"), ("remove_", "remove")):
            if name.startswith(prefix) and name.endswith("_listener"):
                prop = name[len(prefix):-len("_listener")]
                if prop in self._observed:
                    return lambda cb: self._change(prop, cb, action)
        if name.endswith("_has_listener"):
            prop = name[:-len("_has_listener")]
            if prop in self._observed:
                return lambda cb: cb in self._listeners.get(prop, [])
        raise AttributeError(name)

    def _change(self, prop, cb, action):
        lst = self._listeners.setdefault(prop, [])
        if action == "add":
            if cb in lst:
                raise RuntimeError("listener added twice for %s" % prop)
            lst.append(cb)
        else:
            lst.remove(cb)

    def listener_count(self):
        return sum(len(v) for v in self._listeners.values())


class DeviceParameter(Observable):
    _observed = ("value",)

    def __init__(self, name, value=0.0, lo=0.0, hi=1.0, quantized=False, fmt=None):
        Observable.__init__(self)
        self.name = name
        self.min = lo
        self.max = hi
        self.is_quantized = quantized
        self._fmt = fmt or (lambda v: "%.2f" % v)
        self.value = value

    def __str__(self):
        return self._fmt(self.value)


class MixerDevice(object):
    def __init__(self, sends=2):
        self.volume = DeviceParameter("Volume", 0.85, fmt=lambda v: "%.1f dB" % ((v - 0.85) * 40))
        self.panning = DeviceParameter("Pan", 0.0, -1.0, 1.0,
                                       fmt=lambda v: "C" if abs(v) < 0.01 else ("%dL" % round(-v * 50) if v < 0 else "%dR" % round(v * 50)))
        self.sends = [DeviceParameter("Send %s" % "ABCDEF"[i], 0.0) for i in range(sends)]


class Device(object):
    def __init__(self, name, params, class_name="Generic"):
        self.name = name
        self.class_name = class_name
        self.parameters = [DeviceParameter("Device On", 1.0, 0.0, 1.0, True)] + params


class TrackView(Observable):
    _observed = ("selected_device",)

    def __init__(self, device):
        Observable.__init__(self)
        self.selected_device = device


class Track(Observable):
    _observed = ("name", "mute", "solo", "arm")

    def __init__(self, name, can_be_armed=True, has_audio_output=True, sends=2, devices=(), is_master=False):
        Observable.__init__(self)
        self.name = name
        self.is_master = is_master
        if not is_master:
            self.mute = False
            self.solo = False
        self.arm = False
        self.can_be_armed = can_be_armed
        self.has_audio_output = has_audio_output
        self.mixer_device = MixerDevice(sends)
        self.devices = list(devices)
        self.view = TrackView(self.devices[0] if self.devices else None)


class Scene(object):
    def __init__(self, name):
        self.name = name
        self.fired = 0

    def fire_as_selected(self):
        self.fired += 1


class ClipSlot(object):
    def __init__(self):
        self.fired = 0

    def fire(self):
        self.fired += 1


class BeatTime(object):
    def __init__(self, bars, beats, ticks):
        self.bars, self.beats, self.ticks = bars, beats, ticks


class SongView(Observable):
    _observed = ("selected_track", "selected_scene")

    def __init__(self, track, scene):
        Observable.__init__(self)
        self.selected_track = track
        self.selected_scene = scene
        self.highlighted_clip_slot = ClipSlot()


class Song(Observable):
    _observed = ("record_mode", "loop", "metronome", "session_automation_record", "re_enable_automation_enabled", "appointed_device", "tracks", "tempo", "is_playing")

    def __init__(self, tracks, returns=1):
        Observable.__init__(self)
        self.tracks = list(tracks)
        self.return_tracks = [Track("Return %s" % "AB"[i], can_be_armed=False, sends=0) for i in range(returns)]
        self.master_track = Track("Master", can_be_armed=False, sends=0, is_master=True)
        self.scenes = [Scene("Scene %d" % i) for i in range(1, 5)]
        self.view = SongView(self.tracks[0], self.scenes[0])
        self.record_mode = False
        self.loop = False
        self.metronome = False
        self.session_automation_record = False
        self.tempo = 120.0
        self.is_playing = False
        self.current_song_time = 0.0
        self.can_undo = True
        self.can_redo = False
        self.appointed_device = None  # the device carrying Live's blue hand
        self.re_enable_automation_enabled = False  # True once automation has been overridden
        self.undone = 0
        self.redone = 0
        self.continued = 0

    @property
    def visible_tracks(self):
        return self.tracks

    def jump_by(self, beats):
        self.current_song_time = max(0.0, self.current_song_time + beats)

    def continue_playing(self):
        self.continued += 1
        self.is_playing = True

    def undo(self):
        self.undone += 1

    def re_enable_automation(self):
        self.re_enable_automation_enabled = False

    def redo(self):
        self.redone += 1

    def get_current_beats_song_time(self):
        bars = int(self.current_song_time // 4) + 1
        beats = int(self.current_song_time % 4) + 1
        return BeatTime(bars, beats, 0)


class ApplicationView(object):
    def __init__(self):
        self.visible = "Arranger"

    def is_view_visible(self, name):
        return self.visible == name

    def show_view(self, name):
        self.visible = name


class Application(object):
    def __init__(self):
        self.view = ApplicationView()


_app = Application()


class CInstance(object):
    """What Live hands to create_instance: song(), send_midi(), handle(), log_message()."""

    def __init__(self, song):
        self._song = song
        self.sent = []
        self.log = []
        self.rebuilds = 0

    def song(self):
        return self._song

    def send_midi(self, midi_bytes):
        self.sent.append(tuple(midi_bytes))

    def handle(self):
        return "handle"

    def request_rebuild_midi_map(self):
        self.rebuilds += 1

    def update_locks(self):
        self.lock_updates = getattr(self, "lock_updates", 0) + 1

    def toggle_lock(self):
        self.lock_toggles = getattr(self, "lock_toggles", 0) + 1

    def log_message(self, message):
        self.log.append(message)


def install():
    """Register a fake `Live` module so `import Live` works."""
    live = types.ModuleType("Live")
    app_mod = types.ModuleType("Live.Application")
    app_mod.get_application = lambda: _app
    midimap = types.ModuleType("Live.MidiMap")
    midimap.forwarded = []
    midimap.forward_midi_note = lambda h, m, ch, n: midimap.forwarded.append(("note", ch, n))
    midimap.forward_midi_cc = lambda h, m, ch, cc: midimap.forwarded.append(("cc", ch, cc))
    midimap.forward_midi_pitchbend = lambda h, m, ch: midimap.forwarded.append(("pb", ch))
    midimap.MapMode = types.SimpleNamespace(relative_signed_bit="relative_signed_bit")
    live.Application = app_mod
    live.MidiMap = midimap
    sys.modules["Live"] = live
    sys.modules["Live.Application"] = app_mod
    sys.modules["Live.MidiMap"] = midimap

    # Stand-in for Live's _Generic.Devices: curated banks by device class name, with the
    # same fallbacks as the real module for unknown devices.
    generic = types.ModuleType("_Generic")
    devices = types.ModuleType("_Generic.Devices")
    devices.DEVICE_DICT = {}
    devices.BANK_NAME_DICT = {}
    devices.DEVICE_BOB_DICT = {}

    def by_name(device, name):
        for p in device.parameters:
            if p.name == name:
                return p
        return None

    def parameter_banks(device):
        if device.class_name in devices.DEVICE_DICT:
            return [[by_name(device, n) for n in bank] for bank in devices.DEVICE_DICT[device.class_name]]
        raw = device.parameters[1:]
        return [raw[i:i + 8] for i in range(0, len(raw), 8)]

    def parameter_bank_names(device):
        if device.class_name in devices.BANK_NAME_DICT:
            return devices.BANK_NAME_DICT[device.class_name]
        return ["Bank %d" % (i + 1) for i in range(len(parameter_banks(device)))]

    def best_of_parameter_bank(device):
        if device.class_name in devices.DEVICE_BOB_DICT:
            return [by_name(device, n) for n in devices.DEVICE_BOB_DICT[device.class_name][0]]
        return device.parameters[1:9]

    devices.parameter_banks = parameter_banks
    devices.parameter_bank_names = parameter_bank_names
    devices.best_of_parameter_bank = best_of_parameter_bank
    generic.Devices = devices
    sys.modules["_Generic"] = generic
    sys.modules["_Generic.Devices"] = devices
    return live
