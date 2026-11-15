#!/bin/sh
# Install (symlink) the AlphaTrack Control Surface script into Live's User Library.
# Live lists folders in "Remote Scripts" by name in Preferences > Link, Tempo & MIDI.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)/AlphaTrack"
DEST_DIR="$HOME/Music/Ableton/User Library/Remote Scripts"
mkdir -p "$DEST_DIR"
if [ -e "$DEST_DIR/AlphaTrack" ] && [ ! -L "$DEST_DIR/AlphaTrack" ]; then
  echo "A real folder already exists at $DEST_DIR/AlphaTrack; remove it first." >&2
  exit 1
fi
ln -sfn "$SRC" "$DEST_DIR/AlphaTrack"
echo "Linked $SRC -> $DEST_DIR/AlphaTrack"
echo "Restart Live, then: Preferences > Link, Tempo & MIDI > Control Surface: AlphaTrack, Input/Output: AlphaTrack."
