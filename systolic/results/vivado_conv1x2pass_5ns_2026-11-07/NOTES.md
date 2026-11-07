# conv1 in two passes — the DSP fix worked

Post-route, out-of-context, `xc7a100tcsg324-1`, Vivado 2025.2, `-retiming`.
`SYSTOLIC_CONV1` + `CONV1_PASSES 2`, `PARALLEL_FC2` (`FC2_PAR 12`), `MUL_PIPE` on,
`lenet_roms_bram.v`. Clean run: 0 errors, 0 critical warnings.

## The two numbers you asked for

| | predicted | **measured** |
|---|---|---|
| DSPs | ~205 | **206 / 240 (85.8%)** |
| Required period | vs baseline 6.17 ns | **6.87 ns (~146 MHz)** |

Both land. DSP count is within one of the Yosys estimate, and the design is off the
240 ceiling for the first time.

## Progress across all four runs

| build | required period | max clock | DSPs | LUTs |
|---|---|---|---|---|
| baseline | 6.17 ns | 162 MHz | 144 (60%) | 2,602 |
| conv1 systolic + fc2 x12 (run 1) | 9.13 ns | 110 MHz | 226 (94%) | 40,872 |
| + MUL_PIPE + BRAM ROMs | 10.59 ns | 94 MHz | 240 (100%) | 19,301 |
| **+ conv1 two passes (this run)** | **6.87 ns** | **146 MHz** | **206 (86%)** | **5,792** |

Clock recovered from 94 MHz to 146 MHz, now within 0.70 ns of the baseline. LUTs are
down 70% from the previous build (19,301 -> 5,792) because the multipliers moved into
DSPs instead of being built from logic.

## Real speedup is now 3.2x

| | clocks/frame | period | frame time |
|---|---|---|---|
| baseline | 36,923 | 6.17 ns | 227.8 us |
| previous systolic build | 9,170 | 10.59 ns | 97.1 us (2.35x) |
| **this build** | **10,234** | **6.87 ns** | **70.3 us (3.24x)** |

Giving up ~1,060 clocks per frame to fit in DSPs bought back far more in clock
frequency than it cost in cycles. Clock counts from
`verilator_conv1x2pass_fc2par_900.log` (interval 10,234).

## What is left: the DSP input register

The LUT multipliers are gone. All of the worst paths now end at a DSP:

    conv1/n_reg[15]/C
      ->  conv1/gen_out[2].gen_ky[4].srow/gen_pe[0].pe/p_out_reg/A[24]   (DSP48E1)

The actual delay on that path is only **3.068 ns** (logic 0.704, route 2.364). The
violation comes from the DSP's own input setup requirement:

    DSP48E1 (Setup_dsp48e1_CLK_A[24])    -3.722 ns

**3.722 ns of a 5 ns period is DSP setup time, not logic.** That is the signature of a
DSP48E1 whose A-port input register is bypassed (`AREG = 0`) — the operand arrives
combinationally and has to meet the multiplier's raw setup.

Enabling the DSP's input register on the A port should cut that 3.722 ns to roughly a
flip-flop setup, which on paper is worth far more than the 0.70 ns still separating
this build from the baseline. `MUL_PIPE` added a register *after* the multiply; this
one needs to go *before* it, inside the DSP.

Two supporting details:
- Routing is 77% of the remaining data-path delay (2.364 of 3.068 ns), so the conv1 PE
  array is also spread out; worth a look only after the setup issue is fixed.
- The baseline's own limit, `iterator_conv2` address generation at 5.843 ns, is still
  present in this design and becomes the floor at ~6.17 ns once the DSP path is fixed.

## Resources

| | this run | share |
|---|---|---|
| Slice LUTs | 5,792 | 9.1% |
| Slice registers | 10,160 | 8.0% |
| DSP48E1 | 206 | 85.8% |
| Block RAM tiles | 49 | 36.3% |

Caveat: out-of-context, no pin constraints — logic only, not a full board build.
