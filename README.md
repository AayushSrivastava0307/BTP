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

## Results (5 ns clock, 900 MNIST test digits)

| | `original/` | first systolic build | **current `systolic/`** |
|---|---|---|---|
| What changed | baseline | conv1 + conv2 systolic | conv1 systolic, conv2 original, fc2 x12 parallel |
| Clocks per frame | 36,924 | 17,299 | **~9,169** |
| Speedup | 1x | 2.13x | **4.03x** |
| DSP blocks (Yosys estimate; board has 240) | 129 | 573 | **280** |
| Correct digits | 888 / 900 | 888 / 900 | 888 / 900 |

Predictions are bit-identical in all three builds. The first two columns are ModelSim
runs; the current build was run in Verilator (`systolic/verilator/`), whose testbench counts
one clock fewer per frame than ModelSim's, hence ~9,169. Details in `systolic/README_systolic.md`.

## Running

From `systolic/`, with ModelSim Intel Starter Edition 20.1 (to run the baseline, comment out
`SYSTOLIC_CONV1` and `SYSTOLIC_CONV2` in `systolic/global.v`):

    sim.bat            all 900 frames, then scored against the MNIST labels
    sim.bat 20         first 20 frames
    vsim -c -do run_unit.do    unit tests for the systolic blocks

## Status

- Synthesis has not been run in Vivado yet. The current build needs about 280 DSP blocks
  (Yosys estimate) against the board's 240; Vivado will build the rest from LUTs.
- Next: Vivado synthesis and timing at 5 ns, then fc1 (now the largest layer, 3,001 clocks).
