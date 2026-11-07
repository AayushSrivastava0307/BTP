# Baseline control run at 5 ns — the answer is the opposite of the guess

Post-route, out-of-context, `xc7a100tcsg324-1`, Vivado 2025.2, `-retiming`.
`SYSTOLIC_CONV1`, `SYSTOLIC_CONV2`, `PARALLEL_FC2` and `MUL_PIPE` all commented out in
`global.v`. Clean run: 0 errors, 0 critical warnings.

**Caveat on what "baseline" means here:** `run_vivado.tcl` still reads
`lenet_roms_bram.v`, so this is the *original datapath with BRAM weight ROMs*, not the
untouched original. That holds the ROM style constant and isolates the
systolic/parallel/pipeline changes, which is the better control for this question — but
it is not `original/` as committed.

## Result

| | required period | implied max clock | WNS @ 5 ns |
|---|---|---|---|
| **baseline (this run)** | **6.17 ns** | **~162 MHz** | -1.167 ns |
| systolic + MUL_PIPE + BRAM | 10.59 ns | ~94 MHz | -5.590 ns |
| systolic, pre-fix (run 1) | 9.13 ns | ~110 MHz | -4.128 ns |

The hypothesis was that the original would miss 200 MHz too, showing 200 MHz was never
realistic for this codebase. **It does miss — but only by 1.167 ns.** The baseline runs
at 162 MHz against the systolic build's 94 MHz.

So 200 MHz was ambitious rather than impossible, and the conclusion flips: the
accelerator work is not held back by a codebase-wide ceiling. **The systolic and fc2
changes are themselves what cost 1.72x in clock frequency.**

## The baseline bottleneck is not a multiplier

    iterator_conv2/batch_cnt_reg[2]/C  ->  iterator_conv2/aa_weight_reg[4]_rep__8/D
    5.843 ns, 7 logic levels (CARRY4=5, LUT2=2), logic 3.184 / route 2.659

Address generation in the conv2 iterator — a counter feeding a weight-address
calculation. Completely different from the systolic build, where all ten worst paths run
block-RAM output -> LUT multiply. The baseline never has a multiply on its critical path
because conv1 and fc2 do one multiply per clock and all 144 of them fit in DSPs.

## Resources

| | baseline | systolic+fixes | note |
|---|---|---|---|
| Slice LUTs | **2,602 (4.1%)** | 19,301 (30.4%) | 7.4x |
| Slice registers | 6,690 (5.3%) | 13,487 (10.6%) | 2.0x |
| DSP48E1 | **144 (60%)** | 240 (100%) | saturated in the accelerator |
| Block RAM tiles | 50.5 (37.4%) | 47 (34.8%) | about equal |

The baseline fits in 144 DSPs with headroom to spare. The accelerator needs more
multipliers than the chip has, and the overflow goes to LUTs — which is the whole
timing problem.

## What this does to the speedup claim

Clock count alone says 4.03x. Multiplying by the clock period each build can actually
achieve:

| | clocks/frame | period | frame time |
|---|---|---|---|
| baseline | 36,923 | 6.17 ns | **227.8 us** |
| systolic + MUL_PIPE + BRAM | 9,170 | 10.59 ns | **97.1 us** |

**Real speedup ≈ 2.35x, not 4.03x.** Roughly 42% of the clock-count win is given back
by the slower clock.

Clock counts are the Verilator 900-frame runs
(`verilator_original_900.log` interval 36,923; `verilator_conv1sys_fc2par_mulpipe_900.log`
interval 9,170). Periods are post-route from these Vivado runs.

This is the number that belongs on the slide. 4.03x is a simulation result; 2.35x is
what the hardware would do.

## Suggested next step

Since the baseline closes at 162 MHz and the accelerator at 94 MHz, the honest common
clock for a like-for-like comparison is the slower of the two. Getting the accelerator's
LUT multipliers under control — fewer parallel lanes so everything fits in DSPs, and a
register between the BRAM read and the multiply — would raise both the clock and the
real speedup at the same time.
