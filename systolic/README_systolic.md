# Systolic array implementation — 16-bit LeNet-5

conv1 and conv2 rebuilt as weight-stationary systolic arrays fed by line
buffers. Everything else (pooling, relu, fc1–fc3, all ROMs, all SRAMs) is
untouched.

## Current build (Nov 2026): conv1 systolic, conv2 original, fc2 parallel

Synthesis estimates showed the conv2 array costs about 300 extra DSP blocks for a 1.77x
gain on conv2 (about 1,090 clocks per frame), and the XC7A100T has only 240 DSPs. With conv1
fast, fc2 had become 58% of every frame, because it does one multiply per clock. So the
default build in `global.v` is now:

| Switch | Setting | Engine |
|---|---|---|
| `SYSTOLIC_CONV1` | on | `systolic_conv.v` (150 PEs) |
| `SYSTOLIC_CONV2` | **off** | original iterator + conv/acc/mac |
| `PARALLEL_FC2`, `FC2_PAR 12` | **on** | `fc2_par.v`: 12 neurons per group |

| | original | conv1+conv2 systolic | **current** |
|---|---|---|---|
| conv1 | 19,601 | 1,065 | 1,065 |
| conv2 | 2,501 | 1,412 | 2,501 |
| fc2 | 10,081 | 10,081 | **862** |
| frame interval | 36,923 | 17,298 | **9,168** |
| vs original | 1x | 2.13x | **4.03x** |
| DSP blocks (Yosys est., board has 240) | 129 | 573 | **280** |
| MNIST, 900 digits | 888 | 888 | 888 |

Clock counts are from `verilator/run_verilator.sh` (logs in `results/verilator_*_900.log`).
That testbench counts one clock fewer per frame than `lenet_tb.v` in ModelSim (17,298 vs
17,299 for the same build), so expect about 9,169 from `sim.bat`. Predictions are identical
across all three builds for all 900 digits.

**How fc2_par works.** fc2 has 120 inputs and 84 outputs. The original walks the 84 neurons
one at a time, one multiply per clock (10,080 clocks). `fc2_par` reads each input once and
feeds it to 12 multiply-accumulate lanes, each building a different neuron, so the layer is
7 groups of 120 clocks. 12 is the largest number that divides both 84 and 120. The 12 sums of
a group leave one per clock, neuron 0 first, through the same `q`/`q_en` interface as the old
`conv_fc2`, while the next group is already accumulating, so `relu_fc2`, `relu_fc2_buf` and
fc3 are untouched.

The weights are the same 10,080 values, repacked 12 per ROM word by `gen_fc2_par_rom.py`
into `fc2_par_rom.v` (840 words x 192 bits). Each lane forms `bias + SUM x*w` in the same
order as the original `acc`, in a 32-bit register, and keeps the same slice `[30:15]`, so
every output is bit-identical. `run_fc2_unit.do` checks this directly: it runs the original
fc2 and `fc2_par` side by side on 9 input sets and compares all 84 outputs.

**Resources.** 280 DSPs is still 40 over the board. Vivado builds the extra multipliers from
LUTs (roughly 250-300 LUTs each, about 10-12k in total, against 63,400 available). Those
LUT multipliers are the timing risk at 5 ns on a -1 part; a Vivado run with a 5 ns
clock constraint will show whether they need a pipeline register.

## Vivado results and timing fixes (6 Nov 2026)

First routed run of the current build (Vivado 2025.2, xc7a100tcsg324-1, 5 ns clock, out of context):

| Resource | Used | Available | |
|---|---|---|---|
| DSP blocks | 226 | 240 | 94% |
| LUTs | 40,872 | 63,400 | 64% |
| Flip-flops | 13,081 | 126,800 | 10% |
| Block RAM tiles | 19 | 135 | 14% |

Timing failed: WNS = -4.128 ns, so the slowest path needs 9.13 ns (about 109 MHz); 13,282 of
39,519 endpoints missed 5 ns. All ten worst paths end in multipliers that did not get a DSP
block and were built from LUTs (6-9 CARRY4 stages), in `fc2_par` lanes and in conv2's `mac`;
about 60% of each path is routing. Only 19 block RAMs were used because Vivado built the
packed-array weight ROMs of `lenet_roms.v` as LUT multiplexers.

Two fixes, both bit-exact (all 900 digits identical to the original in Verilator, both reset
styles; with `MUL_PIPE` off the design is exactly as before):

1. **Weight ROMs in block RAM.** `gen_bram_roms.py` rewrites `lenet_roms.v` as
   `lenet_roms_bram.v`: the same 10 modules in the standard inferable ROM form, with
   `rom_style = "block"` for ROMs of 256 words or more (fc1, fc2, fc3 weights) and
   `"distributed"` for the small ones. All 14,186 words were compared between the two files.
   `fc2_par_rom.v` gets the same attributes. `run_vivado.tcl` and `verilator/` use
   `lenet_roms_bram.v`; ModelSim's `run.do` still uses `lenet_roms.v`.
2. **Two registers per multiplier** (`MUL_PIPE` in `global.v`). In `cnn.v`'s `mac` and in
   `fc2_par`, the product passes through an extra register with no reset, and the control
   delays move by one clock to match. With `synth_design -retiming` (now in `run_vivado.tcl`),
   Vivado can move that register into the middle of a LUT-built multiplier, or into the DSP's
   MREG. `ready` now waits 7 clocks after fc3 instead of 6. Cost: 2 clocks per frame
   (9,170 instead of 9,168).

Next run: `vivado -mode batch -source run_vivado.tcl` (5 ns) and, if it still fails,
`-tclargs 6.67` (150 MHz) or `-tclargs 10` (100 MHz).

## Why

The baseline walks `(batch, row, col, ky, kx)` and does **one** multiply per
clock. Each source pixel is re-read from SRAM once per kernel tap, so a 5×5
kernel fetches every pixel ~25 times over.

A systolic array unrolls the kernel taps into *hardware* instead of into
*time*: one PE per tap, all firing every clock. The line buffer reads each
pixel exactly **once** and holds the K−1 rows still needed. Compute scales
with the number of PEs; memory traffic does not. That is the whole point.

## Results of the first systolic build (conv1 + conv2)

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
| `fc2_par.v` | fc2 with `FC2_PAR` neurons per group |
| `fc2_par_rom.v` | fc2 weights and biases repacked for `fc2_par` (generated) |
| `gen_fc2_par_rom.py` | Regenerates `fc2_par_rom.v` from `lenet_roms.v` |
| `lenet_roms_bram.v` | `lenet_roms.v` in block-RAM ROM form, used for synthesis (generated) |
| `gen_bram_roms.py` | Regenerates `lenet_roms_bram.v` from `lenet_roms.v` |
| `run_vivado.tcl` | Synthesis + place + route + timing; `-tclargs <period ns>` |
| `tb_fc2_par.v`, `run_fc2_unit.do` | Original fc2 vs `fc2_par`, bit for bit |
| `verilator/` | Fast full-network simulation (900 digits in seconds) |

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
vsim -c -do run_fc2_unit.do    fc2_par vs original fc2
verilator/run_verilator.sh 900  same 900-frame run in Verilator (Linux/WSL)
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

DFX, loop tiling, FINN, pruning. No Vivado run yet: resource figures are Yosys estimates and
clock counts are simulation, not post-route results. Next candidates: fc1 (now the largest
layer at 3,001 clocks; 32 lanes would save about 1,500) and a smaller conv2 array that reuses
fewer PEs over several passes.
