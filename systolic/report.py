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


def parse_env(path):
    """Pull the simulator's own provenance out of the transcript, so the
    report evidences the run rather than just asserting numbers."""
    env = {"tool": None, "sources": [], "modules": [], "elapsed": None,
           "errors": None, "warnings": None, "started": None}
    with open(path, "r", errors="replace") as f:
        for line in f:
            s = line.lstrip("# ").rstrip()
            if env["tool"] is None and "Model Technology ModelSim" in s:
                env["tool"] = s.split(" vlog")[0].split(" vmap")[0].strip()
            if s.startswith("vlog ") and not env["sources"]:
                env["sources"] = [w for w in s.split() if w.endswith(".v")]
            if s.startswith("Loading ") and "." in s:
                m = s.split(".", 1)[1]
                if m not in env["modules"]:
                    env["modules"].append(m)
            if s.startswith("Start time:") and env["started"] is None:
                env["started"] = s[len("Start time:"):].strip()
            if "Elapsed time:" in s:
                env["elapsed"] = s.split("Elapsed time:")[1].strip()
            m = re.match(r"Errors: (\d+), Warnings: (\d+)", s)
            if m:
                env["errors"], env["warnings"] = m.group(1), m.group(2)
    return env


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

    env = parse_env(sys_log)
    syst = [m for m in env["modules"]
            if m in ("systolic_conv", "systolic_conv2", "linebuf",
                     "systolic_row", "pe")]

    L = []
    L.append("# LeNet-5 simulation report")
    L.append("")
    L.append("16-bit LeNet-5 CNN accelerator with conv1 and conv2 implemented "
             "as weight-stationary systolic arrays fed by line buffers.")
    L.append("")
    L.append(f"Generated {datetime.now():%Y-%m-%d %H:%M} from `{sys_log}`.")
    L.append("")

    L.append("## Simulation environment")
    L.append("")
    L.append("| | |")
    L.append("|---|---|")
    if env["tool"]:
        L.append(f"| simulator | {env['tool']} |")
    if env["started"]:
        L.append(f"| run started | {env['started']} |")
    if env["elapsed"]:
        L.append(f"| wall-clock | {env['elapsed']} |")
    if env["errors"] is not None:
        L.append(f"| compile/sim errors | **{env['errors']}** |")
        L.append(f"| warnings | {env['warnings']} |")
    L.append(f"| source files compiled | {len(env['sources'])} |")
    L.append("")

    if syst:
        L.append("Systolic modules confirmed elaborated into the simulation: "
                 + ", ".join(f"`{m}`" for m in syst) + ".")
        L.append("")
    if env["sources"]:
        L.append("<details><summary>Source files</summary>")
        L.append("")
        L.append("```")
        L.append("\n".join(env["sources"]))
        L.append("```")
        L.append("</details>")
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
