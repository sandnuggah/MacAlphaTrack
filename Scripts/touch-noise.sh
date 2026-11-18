#!/bin/zsh
# Capture 20 s of raw reports while a hand hovers over the unit, to compare touch-sensor
# noise between power sources (TODO: grounding test). Quit MacAlphaTrack.app first.
# Output: build/touch-<ac|battery>-<time>.log
set -e
ROOT="${0:A:h:h}"
BIN="$ROOT/.build/release/macalphatrack"
[[ -x "$BIN" ]] || swift build --package-path "$ROOT" --build-system native -c release --product macalphatrack
power() { if pmset -g batt | head -1 | grep -q "AC Power"; then echo ac; else echo battery; fi }
SRC=$(power)
OUT="$ROOT/build/touch-$SRC-$(date +%H%M%S).log"
mkdir -p "$ROOT/build"
for n in 3 2 1; do "$BIN" lcd "Hover hand in $n" "do not touch" >/dev/null; sleep 1; done
"$BIN" lcd "HOVER NOW 20s" "power: $SRC" >/dev/null
"$BIN" dump --all -t 20 > "$OUT"
"$BIN" lcd "Done" "power: $SRC" >/dev/null
END=$(power)
if [[ "$END" != "$SRC" ]]; then
  mv "$OUT" "${OUT%.log}-MIXED.log"; OUT="${OUT%.log}-MIXED.log"
  echo "power source changed during the run ($SRC -> $END): discard this capture"
fi
echo "saved $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
