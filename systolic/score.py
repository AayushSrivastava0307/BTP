#!/usr/bin/env python3
"""
score.py -- grade a ModelSim run against the MNIST test labels.

    python score.py [result.log]

The testbench prints one line per classified frame:

    T<time>==process a frame     <n>, digit  <d> =============

Frame n corresponds to MNIST test image n: export_png.ipynb tiled the grid as
X_test[30*i + j] and png_to_yuv.py reads the tiles back in the same order, so
the mapping is the identity.

Also writes predictions.txt -- one digit per line -- which is the file to diff
between the baseline and the systolic build.  Because the systolic version only
reschedules the same integer arithmetic, that diff must be empty.
"""

import gzip
import os
import re
import struct
import sys

LABELS = os.path.join("tensorflow", "MNIST_data", "MNIST_data",
                      "t10k-labels-idx1-ubyte.gz")
LINE_RE = re.compile(r"process a frame\s+(\d+),\s*digit\s+(\d+)")


def load_labels(path):
    with gzip.open(path, "rb") as f:
        magic, count = struct.unpack(">II", f.read(8))
        if magic != 0x801:
            raise ValueError(f"{path}: bad magic {magic:#x}")
        return list(f.read(count))


def parse_predictions(path):
    preds = {}
    with open(path, "r", errors="replace") as f:
        for line in f:
            m = LINE_RE.search(line)
            if m:
                preds[int(m.group(1))] = int(m.group(2))
    return preds


def main():
    log = sys.argv[1] if len(sys.argv) > 1 else "result.log"

    if not os.path.exists(log):
        sys.exit(f"no such log: {log}")
    if not os.path.exists(LABELS):
        sys.exit(f"MNIST labels not found at {LABELS}")

    labels = load_labels(LABELS)
    preds = parse_predictions(log)

    if not preds:
        sys.exit(f"{log}: no 'process a frame' lines -- did the run abort?")

    frames = sorted(preds)
    correct = wrong = 0
    misses = []
    for n in frames:
        if n >= len(labels):
            break
        if preds[n] == labels[n]:
            correct += 1
        else:
            wrong += 1
            misses.append((n, labels[n], preds[n]))

    total = correct + wrong
    print(f"log         : {log}")
    print(f"frames      : {total}")
    print(f"correct     : {correct}")
    print(f"wrong       : {wrong}")
    print(f"accuracy    : {100.0 * correct / total:.2f}%" if total else "n/a")

    if misses:
        print(f"\nmisclassified ({len(misses)}):")
        print("  frame   true   predicted")
        for n, t, p in misses:
            print(f"  {n:5d}   {t:4d}   {p:9d}")

    with open("predictions.txt", "w") as f:
        for n in frames:
            f.write(f"{n} {preds[n]}\n")
    print(f"\nwrote predictions.txt ({len(frames)} frames)")


if __name__ == "__main__":
    main()
