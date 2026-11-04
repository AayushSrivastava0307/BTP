# BTP: LeNet-5 accelerator on FPGA

A 16-bit fixed-point LeNet-5 (MNIST digit classifier) in Verilog, sped up by rebuilding its
convolution layers as weight-stationary systolic arrays. Target board: Digilent Nexys 4 DDR
(Xilinx Artix-7 XC7A100T-1CSG324C).

## Folders

| Folder | What it holds |
|---|---|
| `original/` | The untouched baseline LeNet-5, as first committed. One multiply per clock in conv1. |
| `systolic/` | Our design: conv1 and conv2 rebuilt as systolic arrays fed by line buffers. Everything else unchanged. See `systolic/README_systolic.md`. |
| `systolic/results/` | ModelSim logs behind every number below (900-frame run, per-layer timing probe, Xilinx-build runs). |
| `noc/` | Network-on-chip work in progress: a 5-port router, a 3x3 mesh and an 8x8 systolic array. **Not yet connected to the LeNet datapath.** |
| `experiments/32bit/` | A 32-bit-weight variant of the baseline. |
| `docs/` | Interactive walkthrough of the conv1 systolic array, served by GitHub Pages. |
| `reference/` | CNN notes and the Nexys 4 DDR reference manual. |

## Results (ModelSim, 5 ns clock)

| | `original/` | `systolic/` | |
|---|---|---|---|
| conv1 | 19,601 clocks | 1,065 | 18.4x |
| conv2 | 2,501 | 1,412 | 1.77x |
| One frame (one digit) | 36,924 | 17,299 | 2.13x |

Predictions are bit-identical between the two builds; the systolic build classifies 888 of 900
MNIST test digits correctly (98.7%).

## Running

From `systolic/`, with ModelSim Intel Starter Edition 20.1 (to run the baseline, comment out
`SYSTOLIC_CONV1` and `SYSTOLIC_CONV2` in `systolic/global.v`):

    sim.bat            all 900 frames, then scored against the MNIST labels
    sim.bat 20         first 20 frames
    vsim -c -do run_unit.do    unit tests for the systolic blocks

## Status

- Synthesis has not been run in Vivado yet. A Yosys estimate shows the full systolic build needs
  about 573 DSP blocks against the board's 240; conv1-only needs about 271.
- Next: parallelise fc2 (now 58% of each frame), then synthesise for the board.
