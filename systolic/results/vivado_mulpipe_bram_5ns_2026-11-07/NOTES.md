# What worst_paths.rpt settles

Post-route, out-of-context, `xc7a100tcsg324-1`, Vivado 2025.2, `-retiming`.
Build: conv1 systolic, conv2 original, fc2 x12, `MUL_PIPE` on, `lenet_roms_bram.v`.
Companion run at 6.67 ns in `../vivado_mulpipe_bram_6.67ns_2026-11-07/`.

## The open question: retiming failure, or a different path?

**Both, and the report names them.**

All **ten** of the worst paths have the same shape:

    fc2_par/u_wrom/qa_reg_{1,2,3}/CLKARDCLK   (RAMB36E1)
      ->  fc2_par/lane[{2,6,7}].two_stage.mul_p_reg[25..30]/D   (FDRE)

Slack across the ten: -5.590 ns down to -5.372 ns. Not one of them involves fc1.

1. **A different path is now the slowest.** Run 1's worst path started at a flop
   (`relu_fc1_buf/u/qa_reg[3]_rep__0`). Every run-2 path starts at a block RAM.
2. **Retiming also did not do its job.** The `MUL_PIPE` register sits at the *end* of
   the multiply (`two_stage.mul_p_reg`), not inside it. CARRY4 depth went 6 -> 7: the
   register was added to the path rather than cutting it.

## It is the fc2 weight ROM, not fc1

The culprit is `fc2_par/u_wrom` = `fc2_par_weight_rom` (instantiated in `fc2_par.v`,
192-bit word for P=12). The fc1 ROM does not appear in the top ten paths at all.

## Delay budget on the worst path (10.568 ns total)

| Stage | Delay | Share |
|---|---|---|
| RAMB36E1 clock-to-out (`Prop_ramb36e1_CLKARDCLK_DOADO`) | 2.454 ns | 23% |
| Route BRAM -> first LUT (`fc2_par/out[109]`, fanout 33) | 1.654 ns | 16% |
| LUT-built multiply (2x LUT6, 2x LUT3, 7x CARRY4 + routing) | 6.460 ns | 61% |

The 2.5 ns block-RAM estimate was right — `Prop_ramb36e1_CLKARDCLK_DOADO` measures
**2.454 ns**. But it is only about a quarter of the path. **4.108 ns (39%) is gone
before the multiplier even starts**, and the unregistered LUT multiply is still the
larger half.

So the BRAM read is a genuine contributor, not the whole story: the real problem is
that a slow BRAM output and a full unregistered LUT multiply are in the *same* clock
cycle, with no register between them.

## Loosening the clock does not help

| | 5 ns target | 6.67 ns target |
|---|---|---|
| WNS | -5.590 ns | -3.918 ns |
| Data path delay | 10.568 ns | 10.566 ns |
| Required period | 10.59 ns | 10.59 ns |

Two picoseconds apart. This is a hard combinational limit, not congestion and not
Vivado giving up on an unreachable constraint. A 100 MHz run would miss by ~0.6 ns;
the design tops out near **94 MHz**. The next useful experiment is a design change,
not another clock target.

## On "get every multiplier into a DSP"

Consistent with the reports: DSPs are at **240/240 (100%)**, up from 226 in run 1, so
the overflow multipliers are LUT-built and there is no DSP headroom left for retiming
to hide a register in a DSP MREG.

Worth noting it would not fix this path on its own: a DSP's MREG helps only if the
operand reaches it in time, and 4.1 ns of this path is spent before the multiply.
Registering the ROM read data — moving the `MUL_PIPE` register to the multiplier
*inputs*, or enabling the BRAM's `DOA_REG` output register — attacks the measured
critical path directly and is cheap to try alongside the DSP work.

## Resources

| | run 1 | run 2 (5 ns) |
|---|---|---|
| Slice LUTs | 40,872 (64.5%) | 19,301 (30.4%) |
| Slice registers | 13,081 (10.3%) | 13,487 (10.6%) |
| DSP48E1 | 226 (94.2%) | 240 (100%) |
| Block RAM tiles | 19 (14.1%) | 47 (34.8%) |

The BRAM half of the fix worked: LUT usage halved.

Caveat: out-of-context, no pin constraints — logic only, not a full board build.
