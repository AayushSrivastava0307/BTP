# BTP: LeNet-5 accelerator on FPGA

A 16-bit fixed-point LeNet-5 (MNIST digit classifier) in Verilog, sped up by rebuilding its
convolution layers as weight-stationary systolic arrays. Target board: Digilent Nexys 4 DDR
(Xilinx Artix-7 XC7A100T-1CSG324C).

## Folders

| Folder | What it holds |
|---|---|
| `original/` | The untouched baseline LeNet-5, as first committed. One multiply per clock in conv1. |
| `systolic/` | Our design: conv1 as a systolic array, fc2 computing 12 neurons at once; conv2 can also be switched to a systolic array. See `systolic/README_systolic.md`. |
| `systolic/results/` | ModelSim logs behind every number below (900-frame run, per-layer timing probe, Xilinx-build runs). |
| `noc/` | Network-on-chip work in progress: a 5-port router, a 3x3 mesh and an 8x8 systolic array. **Not yet connected to the LeNet datapath.** |
| `experiments/32bit/` | A 32-bit-weight variant of the baseline. |
| `docs/` | Interactive walkthrough of the conv1 systolic array, served by GitHub Pages. |
| `reference/` | CNN notes and the Nexys 4 DDR reference manual. |

## Results (clock cycles in simulation, 900 MNIST test digits)

| | `original/` | first systolic build | **current `systolic/`** |
|---|---|---|---|
| What changed | baseline | conv1 + conv2 systolic | conv1 systolic (2 passes), conv2 original, fc2 x12 parallel |
| Clocks per frame | 36,924 | 17,299 | **~10,235** |
| Speedup in clocks | 1x | 2.13x | **3.61x** |
| DSP blocks (Yosys estimate; board has 240) | 129 | 573 | **205** |
| Correct digits | 888 / 900 | 888 / 900 | 888 / 900 |

Predictions are bit-identical in all three builds. The first two columns are ModelSim
runs; the current build was run in Verilator (`systolic/verilator/`), whose testbench counts
one clock fewer per frame than ModelSim's, hence ~10,235. Details in `systolic/README_systolic.md`.

## Running

From `systolic/`, with ModelSim Intel Starter Edition 20.1 (to run the baseline, comment out
`SYSTOLIC_CONV1` and `SYSTOLIC_CONV2` in `systolic/global.v`):

    sim.bat            all 900 frames, then scored against the MNIST labels
    sim.bat 20         first 20 frames
    vsim -c -do run_unit.do    unit tests for the systolic blocks

## Status

- Vivado (xc7a100t-1, post-route): the baseline datapath reaches ~162 MHz (6.17 ns). The
  conv1-systolic + fc2-parallel build reached only ~94 MHz (10.59 ns), because ~280
  multipliers do not fit in 240 DSP blocks and the LUT-built ones are slow. Real-time
  speedup so far: 2.35x (227.8 us vs 97.1 us per digit); 4.03x is the clock-cycle figure.
- Fix in place, verified bit-exact: conv1's array runs in two passes (`CONV1_PASSES 2`,
  205 DSPs), fc2's inputs are registered. 10,234 clocks per frame (3.61x in clocks).
  Awaiting the next Vivado run.
- Next: layer pipelining and fc1 (largest layer, 3,001 clocks); shorten conv2's iterator
  address path, which limits both designs.
