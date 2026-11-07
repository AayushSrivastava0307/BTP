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
| `noc/mentor/` | Our mentor's NoC LeNet (activation NoC + streaming pooling + systolic MAC rows) and its baseline. Bit-exact with the original, 1.023x fewer clocks; see `noc/mentor/README.md`. |
| `power/` | Vivado power study: energy per digit for the baseline, the NoC design, the NoC design with the NoC removed, and ours, from simulated switching activity. See `power/README.md`. |
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

- Vivado (xc7a100t-1, post-route, out of context): the baseline datapath reaches 6.17 ns
  (~162 MHz). The current build (conv1 systolic in two passes, fc2 x12) reaches 6.87 ns
  (~146 MHz) with every multiplier in a DSP block: 206/240 DSPs, 5,792 LUTs.
  **Real-time speedup 3.24x** (227.8 us vs 70.3 us per digit); 3.61x is the clock-cycle figure.
- Its worst path (conv1's pixel-count compare into a DSP input) is fixed, bit-exact.
  If the next run reaches the baseline's 6.17 ns, the real speedup becomes 3.61x.
- Power: `power/run_power.tcl` measures energy per digit for four designs; awaiting the first run.
- Next: layer pipelining and fc1 (largest layer, 3,001 clocks); shorten conv2's iterator
  address path, which limits both designs.
