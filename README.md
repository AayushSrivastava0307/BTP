# LeNet-5 accelerator on FPGA

16-bit fixed-point LeNet-5 (MNIST digits) in Verilog, for the Nexys 4 DDR board
(Artix-7 XC7A100T-1CSG324C). B.Tech project, IIT Kharagpur:
Aayush Srivastava (23EE10080), Uday Keshav (23EE10083).

| Folder | Contents |
|---|---|
| `original/` | Baseline design, as received |
| `systolic/` | Our accelerator: systolic-array conv1 (two passes), 12-lane fc2, pipelined multipliers |
| `noc/` | NoC design: activation NoC, streaming pooling, zero-skipping MAC rows; `noc/baseline/` is the matching baseline |
| `power/` | Vivado power study of four designs |
| `experiments/` | 32-bit variant, early NoC mesh |
| `docs/`, `reference/` | conv1 walkthrough page; board manual and notes |

## Results (Vivado 2025.2, post-route)

| | Baseline | Ours |
|---|---|---|
| Clock period | 6.17 ns | 5.88 ns |
| Clocks per digit | 36,923 | 10,236 |
| Time per digit | 227.8 µs | 60.2 µs (3.8x faster) |
| DSP / LUT | 144 / 2,602 | 206 / 5,799 |
| Energy per digit (100 MHz) | 77.5 µJ | 35.8 µJ |

Predictions are bit-identical to the baseline: 888/900 test digits correct.
