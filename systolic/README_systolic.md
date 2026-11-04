# Systolic array implementation — 16-bit LeNet-5

conv1 and conv2 rebuilt as weight-stationary systolic arrays fed by line
buffers. Everything else (pooling, relu, fc1–fc3, all ROMs, all SRAMs) is
untouched.

## Why

The baseline walks `(batch, row, col, ky, kx)` and does **one** multiply per
clock. Each source pixel is re-read from SRAM once per kernel tap, so a 5×5
kernel fetches every pixel ~25 times over.

A systolic array unrolls the kernel taps into *hardware* instead of into
*time*: one PE per tap, all firing every clock. The line buffer reads each
pixel exactly **once** and holds the K−1 rows still needed. Compute scales
with the number of PEs; memory traffic does not. That is the whole point.

## Results

| | baseline | systolic | |
|---|---|---|---|
| conv1 clocks | 19,601 | 1,065 | **18.4×** |
| conv2 clocks | 2,501 | 1,412 | **1.77×** |
| whole network | 36,924 | 17,299 | **2.13×** |
| conv1 multipliers | 6 | 150 | |
| conv2 multipliers | 96 | 400 | |

Measured in ModelSim, not estimated. Per-layer counts are `go` to `ready` on each
layer engine; the network row is the interval between successive frames, constant
across every frame of the run. One clock is 5 ns (`CLOCK_PERIOD` in `global.v`).

Subtracting the conv layers leaves the same non-conv remainder in both builds —
**14,822 clocks either way** — which is the check that nothing outside conv moved.

Predictions are **bit-identical** to the baseline — see *Verification*.

## Files

| File | Contents |
|---|---|
| `pe.v` | The PE (multiplier + adder + registered edges) and `systolic_row`, a K-PE chain |
| `linebuf.v` | K−1 row delays producing the K vertical taps of a K×K window |
| `systolic_conv.v` | conv1 layer — single input channel, one pass |
| `systolic_conv2.v` | conv2 layer — six input channels, one pass each, partial sums held between passes |
| `tb_systolic.v` | Unit tests for the blocks above |

Selected by `SYSTOLIC_CONV1` / `SYSTOLIC_CONV2` in `global.v`. Comment either
out to fall back to the baseline `iterator` + `conv/acc/mac` path for that
layer — both builds must produce identical output.

## How it works

**Weight stationary.** Each PE latches one kernel tap at the start of a frame
and holds it. The weight ROM is read K×K times per layer instead of once per
multiply.

**Timing — 2:1 delay ratio.** Data is delayed *twice* per PE, partial sums
*once*. With `x(t)` the pixel entering PE0 at clock `t`:

```
p_out(j,t) = p_out(j-1,t-1) + w[j]*x(t-1-2j)
           = SUM_m w[m] * x(t-(1+j)-m)
```

Every term shares one window only because the sum marches half as fast as the
data. A 1:1 ratio makes each PE add a different tap of the *same* sample —
the classic mistake. A consequence: `w[0]` meets the **newest** sample, so
horizontal taps are loaded reversed (PE `j` holds `kx = K-1-j`). Vertical taps
are not reversed — systolic row `r` holds `ky = r`.

**Line buffer.** Only the vertical dimension. The horizontal K comes free from
the pixel marching PE to PE, so this is K−1 row delays, not a K×K register
file. On Xilinx the row delays map to SRL16/SRL32 LUT shift registers.

**conv2's six input channels.** A 5×5 array holds one input channel's taps at a
time, and interleaving channels cycle-by-cycle would break the chain (it
assumes consecutive clocks carry consecutive columns of one stream). So the
14×14 plane is streamed once per channel, weights reloaded each pass, with
partial sums held in a 100 × 16 × 32-bit store between passes.

## Verification

The baseline forms `bias + SUM(25 products)` in a 32-bit register with **no
saturation**. This forms the same sum in a different order. Two's-complement
addition is associative *even through overflow*, so the 32-bit total is
identical bit for bit and the same slice `[30:15]` is taken.

So the acceptance criterion is exact equality, not "close enough" — any
mismatch is a bug.

```
run_unit.do      290 checks on pe / systolic_row / linebuf
                 against an independent golden model
sim.bat 40       40/40 predictions identical to the baseline
```

## Running it

```
sim.bat            all 900 frames  -> result.log, then scored
sim.bat 20         first 20 frames (fast check)
sim.bat gui        open the ModelSim GUI
vsim -c -do run_unit.do    block-level unit tests
```

Needs `test_900f.yuv`; `sim.bat` generates it from `test_900.png` via
`png_to_yuv.py` if missing. `score.py` grades a log against the real MNIST
test labels — frame *k* is MNIST test image *k*.

## Two traps, for anyone extending this

1. **The pixel index needs two cycles of delay, not one.** The address register
   and the SRAM read are each a clock.
2. **`lenet.v` gates the weight *and bias* ROMs with the same enable as the
   source SRAM** (`cena_src` for conv1, `cena_relu1_buf` for conv2). A layer
   engine must assert it during weight load too, or every PE latches zero.

## Not done yet

DFX, loop tiling, FINN, pruning. Synthesis has not been re-run — all timing
figures above are simulation clock counts, not post-route results.
