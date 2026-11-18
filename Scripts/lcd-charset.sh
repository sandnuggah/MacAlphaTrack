#!/bin/zsh
# Show the LCD's built-in characters 0x80-0xff, 32 per page, for photographing.
# The lit F-key says which page is up: F1 = 0x80-0x9f, F2 = 0xa0-0xbf, F3 = 0xc0-0xdf,
# F4 = 0xe0-0xff. Top row holds the first 16 codes of the page, bottom row the next 16.
# usage: lcd-charset.sh [seconds per page, default 6]
set -e
ROOT="${0:A:h:h}"
BIN="$ROOT/.build/release/macalphatrack"
HOLD="${1:-6}"
[[ -x "$BIN" ]] || swift build --package-path "$ROOT" --build-system native -c release --product macalphatrack
osascript -e 'tell application "MacAlphaTrack" to quit' >/dev/null 2>&1 || true
sleep 1.5
LEDS=(05 02 15 11)   # light ids of F1 F2 F3 F4
for page in 0 1 2 3; do
  base=$((0x80 + page * 32))
  for cell in 0 1 2 3 4 5 6 7; do
    c=$((base + cell * 4))
    "$BIN" send 00 01 0$cell $(printf '%02x %02x %02x %02x' $c $((c+1)) $((c+2)) $((c+3))) 00 >/dev/null
  done
  for i in 1 2 3 4; do "$BIN" send 00 00 $LEDS[$i] $([[ $i -eq $((page+1)) ]] && echo 01 || echo 00) >/dev/null; done
  printf 'page %d: codes 0x%02x-0x%02x (F%d lit)\n' $((page+1)) $base $((base+31)) $((page+1))
  sleep "$HOLD"
done
for led in $LEDS; do "$BIN" send 00 00 $led 00 >/dev/null; done
[[ -d "$ROOT/build/MacAlphaTrack.app" ]] && open "$ROOT/build/MacAlphaTrack.app"
echo "done; MacAlphaTrack relaunched"
