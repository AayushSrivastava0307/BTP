# noc/mentor/ — NoC LeNet from our BTP mentor

Two designs as received (sources unchanged):

- `baseline/` — the original LeNet (`lenet.v`), reformatted.
- `noc/` — `lenet_noc.v`, the same network with three additions:
  - `activation_noc.v`: a single-hop, 6-port crossbar NoC with registered ingress flits and
    round-robin arbitration. The between-layer scratchpad banks sit at its outputs.
  - `streaming_pool.v`: 2x2 max-pool + ReLU done as each conv result arrives, keeping one row
    instead of the whole conv1 / conv2 output map.
  - `systolic_array.v`: the multiply-accumulate rows rebuilt as skewed systolic chains
    (same multiplier count and schedule as the baseline) with zero-operand isolation.

`Makefile` / `compare_designs.py` are the mentor's ModelSim flow (Linux). It needs
`test_900.yuv` next to it; a copy is in `power/`.

## Measured (Verilator, all 900 test digits)

| | baseline | noc | noc with the NoC removed (`power/activation_noc_bypass.v`) |
|---|---|---|---|
| Predictions / logits | — | 900/900, 9,000/9,000 identical | identical |
| Clocks per digit | 36,917 | 36,081 (1.023x) | 36,075 |
| conv→pool memory traffic per digit | 28,368 B | 3,152 B (9x less) | 3,152 B |
| All between-layer memory traffic per digit | 176,616 B | 151,400 B (−14%) + 6,304 B row buffers | same as noc |

Every source has a fixed destination (`net_dest[i] = i`), so the crossbar never arbitrates;
the traffic and clock savings come from streaming pooling. The NoC's effect on power is
measured in `power/` (`noc` vs `noc_bypass`).
