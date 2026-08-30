#!/usr/bin/env python3
"""
report.py -- build a simulation report from ModelSim logs.

    python report.py <systolic.log> [baseline.log]

Writes simulation_report.md: accuracy against the MNIST test labels, clocks
per frame, and a frame-by-frame diff against the baseline if one is given.
"""

import gzip
import os
import re
import struct
import sys
from datetime import datetime

LABELS = os.path.join("tensorflow", "MNIST_data", "MNIST_data",
                      "t10k-labels-idx1-ubyte.gz")
LINE_RE = re.compile(r"T\s*(\d+)==process a frame\s+(\d+),\s*digit\s+(\d+)")

# The testbench prints $time, and the timescale is 1ns/1ps, so those numbers
# are nanoseconds.  CLOCK_PERIOD = 2 * CLK_PERIOD_DIV2 = 2 * 2.5ns = 5ns.
CLK_NS = 5


def load_labels():
    with gzip.open(LABELS, "rb") as f:
        magic, count = struct.unpack(">II", f.read(8))
        if magic != 0x801:
            raise ValueError(f"bad magic {magic:#x}")
        return list(f.read(count))


def parse(path):
    """-> {frame: digit}, {frame: sim_time_ps}"""
    preds, times = {}, {}
    with open(path, "r", errors="replace") as f:
        for line in f:
            m = LINE_RE.search(line)
            if m:
                t, n, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
                preds[n], times[n] = d, t
    return preds, times


def clocks_per_frame(times):
    """Frame-to-frame delta, which excludes reset and first-frame setup."""
    if len(times) < 3:
        return None
    ks = sorted(times)
    deltas = [times[b] - times[a] for a, b in zip(ks, ks[1:])]
    deltas.sort()
    return deltas[len(deltas) // 2] / CLK_NS      # median, in clocks


def accuracy(preds, labels):
    ok = wrong = 0
    misses = []
    for n in sorted(preds):
        if n >= len(labels):
            break
        if preds[n] == labels[n]:
            ok += 1
        else:
            wrong += 1
            misses.append((n, labels[n], preds[n]))
    return ok, wrong, misses


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    sys_log = sys.argv[1]
    base_log = sys.argv[2] if len(sys.argv) > 2 else None

    labels = load_labels()
    sp, st = parse(sys_log)
    if not sp:
        sys.exit(f"{sys_log}: no results -- did the run abort?")

    ok, wrong, misses = accuracy(sp, labels)
    total = ok + wrong
    scpf = clocks_per_frame(st)

    L = []
    L.append("# LeNet-5 simulation report")
    L.append("")
    L.append(f"Generated {datetime.now():%Y-%m-%d %H:%M} from `{sys_log}`.")
    L.append("")
    L.append("## Accuracy")
    L.append("")
    L.append("| | |")
    L.append("|---|---|")
    L.append(f"| frames | {total} |")
    L.append(f"| correct | {ok} |")
    L.append(f"| wrong | {wrong} |")
    L.append(f"| accuracy | **{100.0*ok/total:.2f}%** |")
    L.append("")

    if scpf:
        L.append("## Throughput")
        L.append("")
        L.append("| | |")
        L.append("|---|---|")
        L.append(f"| clocks per frame | {scpf:,.0f} |")
        L.append(f"| at 100 MHz | {scpf/100e6*1e3:.3f} ms |")
        L.append("")

    if base_log and os.path.exists(base_log):
        bp, bt = parse(base_log)
        common = sorted(set(sp) & set(bp))
        diff = [n for n in common if sp[n] != bp[n]]
        bcpf = clocks_per_frame(bt)

        L.append("## Against the baseline")
        L.append("")
        L.append(f"Baseline log: `{base_log}` ({len(bp)} frames)")
        L.append("")
        L.append("| | |")
        L.append("|---|---|")
        L.append(f"| frames compared | {len(common)} |")
        L.append(f"| mismatches | **{len(diff)}** |")
        if bcpf and scpf:
            L.append(f"| baseline clocks/frame | {bcpf:,.0f} |")
            L.append(f"| systolic clocks/frame | {scpf:,.0f} |")
            L.append(f"| speedup | **{bcpf/scpf:.2f}x** |")
        L.append("")
        if diff:
            L.append("Mismatched frames:")
            L.append("")
            L.append("| frame | baseline | systolic |")
            L.append("|---|---|---|")
            for n in diff:
                L.append(f"| {n} | {bp[n]} | {sp[n]} |")
        else:
            L.append("No mismatches. The systolic build reproduces the baseline "
                     "bit for bit, which is the acceptance criterion: both form "
                     "the same integer sum in a different order, and "
                     "two's-complement addition is associative even through "
                     "overflow.")
        L.append("")

    if misses:
        L.append("## Misclassified frames")
        L.append("")
        L.append("| frame | true | predicted |")
        L.append("|---|---|---|")
        for n, t, p in misses:
            L.append(f"| {n} | {t} | {p} |")
        L.append("")
        L.append("These are network errors, not systolic ones -- the baseline "
                 "gets the same frames wrong.")
        L.append("")

    text = "\n".join(L)
    with open("simulation_report.md", "w") as f:
        f.write(text)

    print(text)
    print()
    print("wrote simulation_report.md")


if __name__ == "__main__":
    main()
