# Measuring SRAM traffic: baseline versus streaming NoC LeNet

## Purpose

Measure how many logical SRAM reads, writes, and bytes each design requires per
image, then measure inference latency independently. The proposed 9× improvement
is a reduction in selected intermediate SRAM traffic, not a claim of 9× faster
SRAM or 9× faster inference.

Simulation instrumentation is implemented in `tests/comparison_tb.v` for both
models. Run `make comparison` with ModelSim for full transcripts and validated
Python results, or `make baseline` / `make noc` separately. The analytical table
below remains an expectation; reported results are derived from enable-edge
counters, never copied from this table. FPGA instrumentation remains future work.
ModelSim execution of the new instrumentation is unverified in this restricted
environment because its installed tools abort with `Bad system call`.

## 1. Define the measurement boundary

Report three groups separately:

1. **Convolution–pooling boundary SRAM:** the full convolution output buffers
   and pooled-output writes. This is the scope of the theoretical 9× ratio.
2. **All intermediate activation SRAM:** all baseline activation buffers and all
   enhanced NoC scratchpads, including downstream reads and FC buffers.
3. **Additional local work:** streaming pooling row-buffer accesses and NoC
   transfers. These must remain visible so that moving data to local storage is
   not mistaken for eliminating every memory operation.

Input-image memory and weight/bias ROM traffic should be reported separately if
instrumented; they are excluded from the 9× calculation. Neither design's
intermediate on-chip storage should be described as external DDR traffic.

Count an enabled memory operation on its clock edge, even if its address or data
matches the previous cycle. Count simultaneous reads and writes separately.
Logical bytes equal operation count × memory word width / 8. They are not a
measurement of physical BRAM internal bit activity or energy.

## 2. Instrument the actual memory interfaces

The current source paths are `rtl/reference/lenet.v`,
`rtl/reference/bhv_1w1r_sram.v`, `rtl/lenet_noc.v`, `rtl/activation_noc.v`, and
`rtl/streaming_pool.v`.

### Baseline

The SRAM models use active-low enables: a read occurs when `!CENA`, and a write
when `!CENB`. Include the same address-valid conditions as the memory itself;
assert that all scheduled addresses are in range.

| Buffer in `lenet` | Read event | Write event | Bytes/operation |
|---|---|---|---:|
| `conv1_buf` | `!cena_conv1_buf` | `!cenb_conv1_buf` | 12 |
| `relu1_buf` | `!cena_relu1_buf` | `!cenb_relu1_buf` | 12 |
| `conv2_buf` | `!cena_conv2_buf` | `!cenb_conv2_buf` | 32 |
| `relu2_buf` | `!cena_relu2_buf` | `!cenb_relu2_buf` | 32 |
| `relu_fc1_buf` | `!cena_relu_fc1_buf` | `!cenb_relu_fc1_buf` | 2 |
| `relu_fc2_buf` | `!cena_relu_fc2_buf` | `!cenb_relu_fc2_buf` | 2 |

Keep independent read/write counters for every row in this table.

### Enhanced design

Count scratchpad operations at the destination in `activation_noc`, where the
memory actually operates:

| Destination bank | Role | Read event | Write event | Bytes/operation |
|---|---|---|---|---:|
| 0 | Conv1 streaming pool endpoint | No scratchpad | No scratchpad | — |
| 1 | Pooled Conv1 activations | `read_enable[1]` | `delivered_valid[1]` | 12 |
| 2 | Conv2 streaming pool endpoint | No scratchpad | No scratchpad | — |
| 3 | Pooled Conv2 activations | `read_enable[3]` | `delivered_valid[3]` | 32 |
| 4 | FC1 activations | `read_enable[4]` | `delivered_valid[4]` | 2 |
| 5 | FC2 activations | `read_enable[5]` | `delivered_valid[5]` | 2 |

Do not count every scratchpad operation as 32 bytes just because the network
payload is 256 bits. Banks have different logical storage widths.

Also count accepted network injections (`in_valid[p] && in_ready[p]`) and
deliveries (`delivered_valid[b]`) separately. Network transfers are not SRAM
operations. Over a completed, drained inference their totals should agree.

### Pooling local storage

For each `streaming_pool` instance, record:

- Valid input vectors: `valid`.
- Row-buffer write vectors: `valid && y % 2 == 0`.
- Produced output vectors: `valid && x % 2 == 1 && y % 2 == 1`.

Multiply a vector by 12 bytes for pool1 and 32 bytes for pool2. These vector
counts cover all channels together, so do not multiply by channel count again.

The current RTL computes a maximum combinationally using row-buffer entries at
`x` and, when `x > 0`, `x-1`. It does not define a simple clock-enabled SRAM read
port for those arrays. Consequently, do not present output-event counts as
measured physical row-buffer read transactions. Report row writes and useful
pooling work, and inspect synthesis mapping before assigning physical read or
energy costs. Keep left-sample registers separate from SRAM traffic.

## 3. Counter implementation and measurement window

Use synthesizable 64-bit event counters. For a single memory, the counting core
can follow this pattern; `clear`, `measure`, `read_event`, and `write_event` must
be supplied by the experiment wrapper:

```systemverilog
always @(posedge clk) begin
    if (!rstn || clear) begin
        read_count  <= 64'd0;
        write_count <= 64'd0;
    end else if (measure) begin
        if (read_event)  read_count  <= read_count  + 64'd1;
        if (write_event) write_count <= write_count + 64'd1;
    end
end
```

Calculate bytes from latched counts on the host; byte counters are optional.
Do not add multiple nonblocking increments to the same counter in one clock
cycle: sum per-bank increments first or keep counters separate.

For each image:

1. Load the input before measurement and ensure the design and network are idle.
2. Clear counters on a separate clock edge before asserting `go`.
3. Enable measurement before the edge that accepts `go`.
4. Record elapsed cycles through the edge observing inference completion.
5. Keep traffic counting enabled through any outstanding operations. Confirm
   no occupied ingress entries or pending writes remain, then freeze counters.
6. Read a stable snapshot and save the prediction and all ten logits.

Do not assume the ready pulse alone drains every instrumented interface. If a
completion-edge memory event occurs, include it; snapshotting counters on that
same edge must account for nonblocking assignment timing. Reading frozen values
on a later edge avoids dropping the last increment. Use each design's own
completion and drain state when both designs run in one simulation.

## 4. Expected boundary SRAM numbers

Conv1 produces `28 × 28 × 6 = 4,704` values; Conv2 produces
`10 × 10 × 16 = 1,600` values. Each value is 2 bytes. Non-overlapping 2×2 pooling
reduces the number of values by four.

| Boundary operation, per image | Baseline vector operations | Baseline bytes | Enhanced vector operations | Enhanced bytes |
|---|---:|---:|---:|---:|
| Conv1 full-map writes | 784 | 9,408 | 0 | 0 |
| Conv1 full-map reads for pooling | 784 | 9,408 | 0 | 0 |
| Pool1 output writes | 196 | 2,352 | 196 | 2,352 |
| Conv2 full-map writes | 100 | 3,200 | 0 | 0 |
| Conv2 full-map reads for pooling | 100 | 3,200 | 0 | 0 |
| Pool2 output writes | 25 | 800 | 25 | 800 |
| **Total** | **1,989** | **28,368** | **221** | **3,152** |

Expected calculations:

```text
Traffic ratio = 28,368 / 3,152 = 9×
Traffic reduction = (1 - 3,152 / 28,368) × 100 = 88.89%
Bytes avoided per image = 25,216
Bytes avoided over 900 images = 22,694,400
```

The enhanced row buffers additionally receive 392 pool1 vector writes and 50
pool2 vector writes: `392 × 12 + 50 × 32 = 6,304` logical bytes/image. These are
excluded from the boundary SRAM table. Their existence is why 88.89% must not
be described as the reduction in all local memory activity.

For the all-intermediate-SRAM result, include downstream pooled-buffer reads
and FC accesses in both designs. Compute its reduction from measured totals;
do not reuse the boundary's 9× ratio.

## 5. Validate in simulation first

The implemented monitor in `tests/comparison_tb.v` probes each selected design's
memory interfaces. It resets counts before `go`, counts through completion and
four drain cycles, checks for remaining memory/network activity, and prints
per-image records plus batch totals. Latency excludes the added drain interval.
The monitor does not change the design's computation or memory schedule.

Run the full independent ModelSim simulations and compare:

```bash
make comparison
```

Or run each design independently, then compare the logs:

```bash
make baseline
make noc
python3 scripts/compare_designs.py --baseline results/baseline_modelsim_900.log --noc results/noc_modelsim_900.log
```

Only ModelSim is supported. `make smoke`/`make batch` use the older paired
functional regression and do not emit the new standalone traffic records.
Inside either extracted ZIP, `make` runs all 900 images with ModelSim and writes
`build/simulation.log` and `build/measurements.json`. Each ZIP includes the same
Python analyzer for single-run validation and cross-design comparison.

Check that:

- All images complete, with matching logits and predictions.
- Each boundary counter matches the table, for every image.
- There are no out-of-range memory operations or dropped packets.
- Delivered packet counts per image are `[784, 196, 100, 25, 120, 84]` for banks
  0 through 5, respectively.
- The sum of per-image counts equals the batch total.

Investigate mismatches rather than replacing measured counts with the analytical
expectation. Include actual enabled operations even if they appear redundant.

## 6. Run on the FPGA

1. Select one FPGA board and a common clock frequency that both designs meet
   after place and route. Use equivalent constraints and counter instrumentation.
2. Provide synthesizable input/weight memories and a board wrapper for clock,
   reset, start, result capture, and counter readout. Existing simulation file I/O
   and behavioral delays are not a complete FPGA implementation.
3. Build and program baseline and enhanced designs separately if they do not fit
   together. Use the same images and exclude host upload time from core latency.
4. Expose frozen counters through UART, processor-readable registers, or vendor
   debug probes. An AMD/Xilinx ILA or Intel Signal Tap can inspect snapshots;
   continuous traces of all 900 images are unnecessary.
5. Run a small set first, then the complete 900-image set. Save one row per image
   with design, image index, clock frequency, latency cycles, each memory's read
   and write counts, network counts, and output checks.
6. Save implementation timing and BRAM/LUT/register/DSP utilization reports.
   Record how the pooling arrays map to registers, distributed RAM, or BRAM.

Observe stable snapshots across clock domains using a proper handshake; do not
sample a changing multi-bit counter directly into an unrelated clock domain.
Keep debug overhead comparable and verify timing with instrumentation present.

## 7. Report traffic and time separately

Use the measured FPGA clock and counters:

```text
Logical SRAM bytes = sum(read_count × read_word_bytes
                       + write_count × write_word_bytes)
Inference seconds = elapsed_cycles / clock_hz
Latency speedup = baseline_seconds / enhanced_seconds
Average selected SRAM traffic rate = selected_SRAM_bytes / inference_seconds
```

The average traffic rate describes demand during inference, not peak SRAM
bandwidth. Lower traffic does not imply lower access latency: both designs can
use one-cycle on-chip memory accesses while performing different numbers of them.
Memory operations can overlap computation and each other, so dividing bytes by
an assumed bandwidth does not establish actual inference time.

| Reported result | Baseline | Enhanced |
|---|---|---|
| Boundary SRAM bytes/image | Measure; expected 28,368 | Measure; expected 3,152 |
| All intermediate SRAM bytes/image | Measure | Measure |
| Pooling local row writes/image | Not applicable | Measure separately |
| NoC injections/deliveries | Not applicable | Measure separately |
| Inference cycles/image | Measure | Measure |
| Clock frequency and latency | Measure | Measure |
| BRAM, LUT, registers, DSPs | Implementation report | Implementation report |
| Logits versus baseline | Reference | Must match |

A suitable final statement, once counters confirm it, is:

> Streaming pooling reduced measured logical SRAM traffic at the two
> convolution–pooling boundaries from 28,368 to 3,152 bytes/image, an 88.89%
> reduction (9× lower traffic). Local pooling storage and network activity were
> accounted for separately. At a common FPGA clock of [frequency], measured
> inference latency changed from [baseline] to [enhanced], giving [ratio]× speedup.

Do not call the traffic ratio a measured 9× inference speedup, or infer a power
reduction from byte counts alone.

## Selecting the initial image count

Use `make comparison FRAMES=90` (or `make comparision FRAMES=90`) to run both
models on images 0–89. Valid counts are 1–900; omitting `FRAMES` runs 900.
`make baseline FRAMES=90` and `make noc FRAMES=90` also accept the count and
write `results/baseline_modelsim_90.log` and `results/noc_modelsim_90.log`.
Inside each extracted ZIP use `make FRAMES=90`.

The analyzer reads the declared run size and requires every frame, ten logits
per frame, and complete traffic records. Both models must use the same size.
`--frames 90` additionally checks the requested size explicitly; the Makefile
flows pass this check automatically. Totals and per-image averages use the
actual selected count, never a fixed divisor of 900.
