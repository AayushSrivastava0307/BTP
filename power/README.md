# power/ — energy per digit, measured in Vivado

Compares four designs on the XC7A100T-1CSG324C with Vivado's `report_power`, using switching
activity from a real simulation of MNIST digits (not Vivado's default guess):

| Name | What it is | Why it is in the study |
|---|---|---|
| `baseline` | mentor's baseline (`noc/mentor/baseline/`, = the original LeNet) | reference point |
| `noc` | mentor's NoC design (`noc/mentor/noc/`): activation NoC + streaming pooling + systolic MAC rows with zero-skipping | the design being evaluated |
| `noc_bypass` | the same NoC design with the NoC taken out (`activation_noc_bypass.v`); everything else identical | separates what the **NoC itself** costs or saves from what streaming pooling and zero-skipping do |
| `ours` | `systolic/` as committed (conv1 systolic in 2 passes, fc2 x12, MUL_PIPE) | our design |

All four give bit-identical predictions (checked on 900 digits in Verilator; the testbench
here re-checks every digit it runs).

## How to run (Vivado Tcl Shell, in this folder)

    vivado -mode batch -source run_power.tcl -tclargs baseline
    vivado -mode batch -source run_power.tcl -tclargs noc
    vivado -mode batch -source run_power.tcl -tclargs noc_bypass
    vivado -mode batch -source run_power.tcl -tclargs ours

Optional arguments after the design name: clock period in ns (default 10) and number of
digits to simulate (default 10, max 50). Use the same period for all four.

Each run can take 30–60 minutes (the simulation step is the slow part; use fewer digits, e.g. `-tclargs noc 10 5`, to shorten it). It does three things:

1. **Simulate** (xsim): runs the digits through the RTL and writes `activity.saif`, a record
   of how often every signal toggled. Stops if any prediction is wrong.
2. **Build**: synthesis, place and route, out of context (logic only, no I/O pins), with the
   same options as `systolic/run_vivado.tcl`.
3. **Power**: loads the activity file and runs `report_power`, then
   energy per digit = total power × (clocks per digit × clock period).

## What comes out

- `results.csv`: one line per run: WNS, clocks and time per digit, total / dynamic / static
  power, energy per digit, and how well the activity file matched the netlist.
- `out_<design>_<period>ns/power.rpt`: the full power report. Its hierarchy section gives
  power per block, e.g. `activation_network` (the NoC), `fused_pool1`, `conv1`.
- `out_<design>_<period>ns/utilization*.rpt`, `timing.rpt`: area and timing.

## Reading the numbers

- **Static power** (~0.1 W) is the same chip-wide leakage for every design. It is paid for
  as long as a digit takes, so faster designs use less of it per digit.
- **Dynamic power** comes from switching. This is where streaming pooling (fewer memory
  accesses) and zero-skipping (multipliers fed zeros do not switch) show up.
- **The NoC's own effect** = `noc` minus `noc_bypass`. Also look at the `activation_network`
  line in `out_noc_*/power.rpt`.
- "Confidence" and "nets matched" say how much of the netlist the RTL activity covered.
  RTL-level activity matches registers well but not every internal net; the comparison
  between designs is fair because all four are measured the same way.
