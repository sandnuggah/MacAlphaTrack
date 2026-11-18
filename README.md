# MacAlphaTrack

Use a Frontier Design Group **AlphaTrack** control surface on a modern Mac. A menu bar app
replaces Frontier's discontinued driver, and adds a control surface for Ableton Live.

<img src="docs/images/settings.png" width="652" alt="The MacAlphaTrack settings window">

## Install

Requires macOS 13 or later and Xcode.

```sh
Scripts/make-app.sh
```

Move `build/MacAlphaTrack.app` to Applications, open it, and plug in the AlphaTrack.

## Set up your DAW

Open MacAlphaTrack before your DAW.

**Ableton Live:** in MacAlphaTrack's settings click **Install**, then restart Live. In Live's
Preferences › Link, Tempo & MIDI choose Control Surface **AlphaTrack** with Input and Output
**AlphaTrack**. The controls are listed in [LiveRemoteScript/README.md](LiveRemoteScript/README.md).

**Other DAWs:** set up the AlphaTrack in Native mode with the **AlphaTrack** MIDI input and
output.

## More

[Developer notes](docs/DEVELOPMENT.md) · [Protocol](docs/PROTOCOL.md) · [Unlicense](LICENSE)
