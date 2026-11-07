# noc/ — LeNet with an activation NoC

`lenet_noc.v` is the baseline LeNet with three additions:

- `activation_noc.v`: a single-hop, 6-port crossbar NoC with registered ingress flits and
  round-robin arbitration. The between-layer scratchpad banks sit at its outputs.
- `streaming_pool.v`: 2x2 max-pool + ReLU done as each conv result arrives, keeping one row
  instead of the whole conv1 / conv2 output map.
- `systolic_array.v`: the multiply-accumulate rows as skewed systolic chains (same multiplier
  count and schedule as the baseline) with zero-operand isolation.

`baseline/` is the matching baseline in the same code style (functionally the design in
`original/`). `Makefile` / `compare_designs.py` run both in ModelSim (Linux) and compare SRAM
traffic; they need `test_900.yuv` next to them (a copy is in `power/`).

## Measured (Verilator, all 900 test digits)

| | baseline | noc | noc without the NoC (`power/activation_noc_bypass.v`) |
|---|---|---|---|
| Predictions / logits | — | 900/900, 9,000/9,000 identical | identical |
| Clocks per digit | 36,917 | 36,081 (1.023x) | 36,075 |
| conv→pool memory traffic per digit | 28,368 B | 3,152 B (9x less) | 3,152 B |
| All between-layer memory traffic per digit | 176,616 B | 151,400 B (−14%) + 6,304 B row buffers | same as noc |

Every source has a fixed destination (`net_dest[i] = i`), so the crossbar never arbitrates;
the traffic and clock savings come from streaming pooling. Vivado (`power/`): both noc builds
need about 10.75 ns (limit in `systolic_array.v`, bank read -> zero gate -> DSP), and the NoC
block itself costs about 1 mW, 374 LUTs and 740 flip-flops.
