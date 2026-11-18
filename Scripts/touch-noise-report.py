#!/usr/bin/env python3
"""Summarise touch-bit activity in captures made by touch-noise.sh.
usage: touch-noise-report.py build/touch-*.log"""
import re, statistics, sys

BITS = {6: "fader", 3: "enc L", 4: "enc M", 5: "enc R", 1: "strip 1", 2: "strip 2"}
ANSI = re.compile(r"\x1b\[[0-9;]*m")
LINE = re.compile(r"\[\s*([\d.]+)\]((?: [0-9a-f]{2}){12})")

def runs(samples):
    """[(state, duration_ms)] for consecutive equal states."""
    out, start, state = [], samples[0][0], samples[0][1]
    for t, s in samples[1:]:
        if s != state:
            out.append((state, (t - start) * 1000)); start, state = t, s
    out.append((state, (samples[-1][0] - start) * 1000))
    return out

for path in sys.argv[1:]:
    rows = []
    for line in open(path):
        m = LINE.search(ANSI.sub("", line))
        if m:
            b = [int(x, 16) for x in m.group(2).split()]
            rows.append((float(m.group(1)), int.from_bytes(bytes(b[2:6]), "big")))
    print(f"{path}: {len(rows)} reports, {rows[-1][0] - rows[0][0]:.1f} s")
    print(f"  {'sensor':8} {'on %':>6} {'episodes':>9} {'median on ms':>13} {'median off ms':>14} {'longest on ms':>14}")
    for bit, name in BITS.items():
        r = runs([(t, bool(mask >> bit & 1)) for t, mask in rows])
        on = [d for s, d in r if s]; off = [d for s, d in r[1:-1] if not s]
        total = sum(d for _, d in r) or 1
        med = lambda v: f"{statistics.median(v):.0f}" if v else "-"
        print(f"  {name:8} {100 * sum(on) / total:6.1f} {len(on):9d} {med(on):>13} {med(off):>14} {max(on, default=0):14.0f}")
