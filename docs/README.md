# docs/ — published page

`index.html` is a standalone, interactive walkthrough of the weight-stationary
systolic array in `16bit/`. Served by GitHub Pages from this folder:

    https://aayushsrivastava0307.github.io/BTP/

It is a single self-contained file — no build step, no libraries, no images. The
only external reference is Google Fonts. Open it directly in a browser and it
works.

## What it shows

- **conv1, clock by clock** — 32×32 image streaming past a fixed 5×5 array of
  150 PEs, with the line buffer, the window, and the 28×28 output filling in.
- **A 6×6 worked example** — the same machine with K=3 and real numbers, small
  enough to check on a calculator. Runs the whole thing: weight load, line
  buffer filling, first answer, flush.
- **Pipeline overlap** — which output each PE is feeding on each clock, which is
  the part people trip on.

## Where the numbers come from

Every clock figure is the RTL's own timing, not an estimate. The page was
checked against a cycle-accurate model of `systolic_conv.v`'s control path,
which in turn reproduces ModelSim exactly:

| | model | ModelSim (ASE 20.1) |
|---|---|---|
| first `q_en` | 169 | 169 |
| valid outputs | 784 | 784 |
| `ready` | 1065 | 1065 |
| output bursts | 28 × 28, gap 32 | 28 × 28, gap 32 |

Per-layer counts measured by probing `go`/`ready` on each layer engine, one
clock being 5 ns (`CLOCK_PERIOD` in `global.v`):

    conv1   19,601 -> 1,065   18.4x
    conv2    2,501 -> 1,412   1.77x
    frame   36,924 -> 17,299  2.13x

The small example is audited the same way: every PE's product is checked against
the output it claims to be feeding, at every clock.
