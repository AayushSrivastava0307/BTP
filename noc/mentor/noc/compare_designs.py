#!/usr/bin/env python3
"""Report measured paired RTL cycles; never modify RTL or synthesize timings."""
import argparse
import json
import re
from pathlib import Path


def analyze(path):
    text = path.read_text()
    if "FATAL:" in text or "** Fatal:" in text or "** Error:" in text:
        raise ValueError("Simulator reported a failure")
    hierarchy = re.findall(r"HIERARCHY (NoC|systolic|pool) (\S+)", text)
    expected = {("NoC", "tb.enhanced.activation_network"),
                ("pool", "tb.enhanced.fused_pool1"),
                ("pool", "tb.enhanced.fused_pool2")}
    expected.update(("systolic", "tb.enhanced." + name)
                    for name in ["conv1", "conv2", "conv_fc1", "conv_fc2", "conv_fc3"])
    if set(hierarchy) != expected or len(hierarchy) != len(expected):
        raise ValueError("Missing or unexpected live NoC/systolic/pooling instances")
    rows = re.findall(r"RESULT frame=(\d+) digit=(\d+) baseline_cycles=(\d+) enhanced_cycles=(\d+)", text)
    passed = re.search(r"PASS frames=(\d+) baseline_cycles=(\d+) enhanced_cycles=(\d+)", text)
    if not passed or not rows:
        raise ValueError("Missing completed self-checking regression; refusing a speedup claim")
    frames, baseline, enhanced = map(int, passed.groups())
    if len(rows) != frames or [int(r[0]) for r in rows] != list(range(frames)):
        raise ValueError("Missing or duplicate frames")
    if sum(int(r[2]) for r in rows) != baseline or sum(int(r[3]) for r in rows) != enhanced:
        raise ValueError("Summary cycles do not agree with per-frame measurements")
    return {"live_instances": [path for _, path in sorted(hierarchy)], "frames": frames, "baseline_cycles": baseline, "enhanced_cycles": enhanced,
            "actual_speedup": baseline / enhanced,
            "baseline_cycles_per_frame": baseline / frames,
            "enhanced_cycles_per_frame": enhanced / frames,
            "clock_assumption_hz": 200_000_000,
            "baseline_images_per_second_at_200mhz": frames * 200_000_000 / baseline,
            "enhanced_images_per_second_at_200mhz": frames * 200_000_000 / enhanced,
            "note": "Cycle-equivalent RTL regression, not labeled MNIST accuracy or post-route Fmax."}


def read_standalone(path, model, expected_frames=None):
    text = path.read_text()
    if re.search(r"FATAL:|\*\*\s+(?:Fatal|Error):", text, re.I):
        raise ValueError(f"{model}: simulator reported a failure")
    runs = re.findall(r"RUN model=(\w+) frames=(\d+) first=(\d+)", text)
    if len(runs) != 1 or runs[0][0] != model or runs[0][2] != "0":
        raise ValueError(f"{model}: expected one run starting at image zero")
    frames = int(runs[0][1])
    if not 1 <= frames <= 900 or (expected_frames is not None and frames != expected_frames):
        raise ValueError(f"{model}: invalid or unexpected requested frame count")
    rows = re.findall(r"RESULT model=(\w+) frame=(\d+) digit=(\d+) cycles=(\d+)", text)
    if len(rows) != frames or any(r[0] != model or int(r[1]) != i
                               for i, r in enumerate(rows)):
        raise ValueError(f"{model}: missing, duplicate, or unordered frames")
    if any(int(r[2]) > 9 or int(r[3]) <= 0 for r in rows):
        raise ValueError(f"{model}: invalid predictions or cycles")
    total = sum(int(r[3]) for r in rows)
    complete = re.findall(r"COMPLETE model=(\w+) frames=(\d+) cycles=(\d+)", text)
    if complete != [(model, str(frames), str(total))]:
        raise ValueError(f"{model}: missing completion or inconsistent cycle total")
    logits = re.findall(r"LOGIT model=(\w+) frame=(\d+) class=(\d+) value=([0-9a-fA-F]{4})\b", text)
    if len(logits) != frames * 10 or any(r[0] != model or int(r[1]) != i // 10
                                 or int(r[2]) != i % 10 for i, r in enumerate(logits)):
        raise ValueError(f"{model}: missing, duplicate, or invalid logits")
    hierarchy = re.findall(r"HIERARCHY (NoC|systolic|pool) (\S+)", text)
    expected = set()
    if model == "noc":
        expected = {("NoC", "comparison_tb.dut.activation_network"),
                    ("pool", "comparison_tb.dut.fused_pool1"),
                    ("pool", "comparison_tb.dut.fused_pool2")}
        expected.update(("systolic", "comparison_tb.dut." + name)
                        for name in ["conv1", "conv2", "conv_fc1", "conv_fc2", "conv_fc3"])
    if set(hierarchy) != expected or len(hierarchy) != len(expected):
        raise ValueError(f"{model}: unexpected live hierarchy")
    return rows, [int(r[3], 16) for r in logits], total


def compare_transcripts(baseline_path, noc_path, expected_frames=None):
    baseline, baseline_logits, baseline_cycles = read_standalone(baseline_path, "baseline", expected_frames)
    noc, noc_logits, noc_cycles = read_standalone(noc_path, "noc", expected_frames)
    frames = len(baseline)
    if len(noc) != frames:
        raise ValueError("Baseline and NoC frame counts differ")
    for i, (base, enhanced) in enumerate(zip(baseline, noc)):
        if base[2] != enhanced[2] or baseline_logits[i*10:(i+1)*10] != noc_logits[i*10:(i+1)*10]:
            raise ValueError(f"Prediction or logit mismatch at frame {i}")
    return {"sram_traffic": compare_traffic(baseline_path, noc_path, frames),
            "frames": frames, "simulator": "modelsim",
            "baseline_transcript": str(baseline_path), "noc_transcript": str(noc_path),
            "baseline_cycles": baseline_cycles, "noc_cycles": noc_cycles,
            "actual_speedup": baseline_cycles / noc_cycles,
            "baseline_cycles_per_frame": baseline_cycles / frames,
            "noc_cycles_per_frame": noc_cycles / frames,
            "matching_predictions": frames, "matching_logits": frames * 10,
            "note": "Measured RTL cycles from sequential completed simulations; prediction agreement is not labeled accuracy or post-route Fmax."}


BANK_BYTES = dict(conv1=12, pool1=12, conv2=32, pool2=32, fc1=2, fc2=2)


def traffic_report(path, model, frames=900):
    """Validate measured operation records and derive bytes without expected-count substitution."""
    text = path.read_text()
    records = {}
    totals = {}
    scopes = {}
    for raw in text.splitlines():
        line = re.sub(r'^\s*#\s?', '', raw).strip()
        if line.startswith('SRAM_SCOPE '):
            try:
                fields = line.split()[1:]
                data = dict(field.split('=') for field in fields)
                if len(data) != len(fields) or data.pop('model') != model:
                    raise ValueError('Wrong scope model or duplicate fields')
                frame = int(data.pop('frame'))
                if frame in scopes or set(data) != {'boundary_bytes', 'all_intermediate_bytes', 'local_row_write_bytes'}:
                    raise ValueError('Duplicate or invalid scope')
                scopes[frame] = {k: int(v) for k, v in data.items()}
            except (KeyError, ValueError) as error:
                raise ValueError(f'{model}: invalid scope record') from error
            continue
        if not line.startswith(('SRAM ', 'SRAM_TOTAL ', 'LOCAL_ROW ', 'LOCAL_ROW_TOTAL ',
                                'NETWORK ', 'NETWORK_TOTAL ')):
            continue
        kind, *fields = line.split()
        try:
            pairs = [field.split('=') for field in fields]
            data = dict(pairs)
            if len(data) != len(pairs) or data.pop('model') != model:
                raise ValueError('Duplicate fields or wrong model')
            identifier = 'pool' if kind.startswith('LOCAL_ROW') else 'bank'
            bank = data.pop(identifier)
            is_total = kind.endswith('_TOTAL')
            frame = None if is_total else int(data.pop('frame'))
            values = {k: int(v) for k, v in data.items()}
            if any(v < 0 for v in values.values()):
                raise ValueError('Negative count')
            group = kind.removesuffix('_TOTAL')
            if group == 'SRAM':
                if set(values) != {'reads', 'writes', 'word_bytes', 'read_bytes', 'write_bytes'}:
                    raise ValueError('Invalid SRAM fields')
                if values['word_bytes'] != BANK_BYTES[bank]:
                    raise ValueError('Wrong SRAM width')
                if (values['read_bytes'] != values['reads'] * BANK_BYTES[bank] or
                        values['write_bytes'] != values['writes'] * BANK_BYTES[bank]):
                    raise ValueError('Byte count disagrees with operation count')
            elif group == 'LOCAL_ROW':
                width = {'1': 12, '2': 32}[bank]
                if (model != 'noc' or set(values) != {'writes', 'word_bytes', 'write_bytes'} or
                        values['word_bytes'] != width or values['write_bytes'] != values['writes'] * width):
                    raise ValueError('Invalid local row record')
            elif (model != 'noc' or bank not in [str(i) for i in range(6)] or
                  set(values) != {'injected', 'delivered'} or values['injected'] != values['delivered']):
                raise ValueError('Invalid or undrained network record')
            target = totals if is_total else records
            key = (group, bank) if is_total else (frame, group, bank)
            if key in target:
                raise ValueError('Duplicate traffic record')
            target[key] = values
        except (KeyError, TypeError, ValueError) as error:
            raise ValueError(f'{model}: invalid traffic line: {line}') from error
    groups = [('SRAM', bank) for bank in BANK_BYTES]
    if model == 'noc':
        groups += [('LOCAL_ROW', str(i)) for i in (1, 2)]
        groups += [('NETWORK', str(i)) for i in range(6)]
    if set(records) != {(f, g, b) for f in range(frames) for g, b in groups} or set(totals) != set(groups):
        raise ValueError(f'{model}: missing or unexpected traffic records; rerun instrumented simulation')
    for group, bank in groups:
        for field, value in totals[group, bank].items():
            expected = (records[0, group, bank][field] if field == 'word_bytes' else
                        sum(records[f, group, bank][field] for f in range(frames)))
            if value != expected:
                raise ValueError(f'{model}: traffic summary disagrees with frames: {group}/{bank}/{field}')
    per_frame = []
    for f in range(frames):
        sram = {b: records[f, 'SRAM', b] for b in BANK_BYTES}
        # This scope includes full-map reads/writes and ONLY pooled-output writes.
        boundary = sum(sram[b]['read_bytes'] + sram[b]['write_bytes'] for b in ('conv1', 'conv2'))
        boundary += sum(sram[b]['write_bytes'] for b in ('pool1', 'pool2'))
        per_frame.append(dict(frame=f, boundary_sram_bytes=boundary,
                              all_intermediate_sram_bytes=sum(v['read_bytes'] + v['write_bytes'] for v in sram.values()),
                              local_row_write_bytes=sum(records[f, 'LOCAL_ROW', str(i)]['write_bytes'] for i in (1, 2)) if model == 'noc' else 0))
    if set(scopes) != set(range(frames)):
        raise ValueError(f'{model}: missing or unexpected SRAM scope records')
    for row in per_frame:
        if scopes[row['frame']] != dict(boundary_bytes=row['boundary_sram_bytes'],
                                       all_intermediate_bytes=row['all_intermediate_sram_bytes'],
                                       local_row_write_bytes=row['local_row_write_bytes']):
            raise ValueError(f'{model}: SRAM scope summary disagrees with measured bank records')
    return dict(frames=frames, banks={b: totals['SRAM', b] for b in BANK_BYTES},
                network={str(i): totals['NETWORK', str(i)] for i in range(6)} if model == 'noc' else {},
                local_rows={str(i): totals['LOCAL_ROW', str(i)] for i in (1, 2)} if model == 'noc' else {},
                boundary_sram_bytes=sum(r['boundary_sram_bytes'] for r in per_frame),
                all_intermediate_sram_bytes=sum(r['all_intermediate_sram_bytes'] for r in per_frame),
                local_row_write_bytes=sum(r['local_row_write_bytes'] for r in per_frame),
                per_frame=per_frame)


def compare_traffic(baseline_path, noc_path, frames):
    base = traffic_report(baseline_path, 'baseline', frames)
    noc = traffic_report(noc_path, 'noc', frames)
    result = {'baseline': base, 'noc': noc}
    for scope in ('boundary_sram_bytes', 'all_intermediate_sram_bytes'):
        b, n = base[scope], noc[scope]
        result[scope] = dict(baseline_total=b, noc_total=n,
                             baseline_per_image=b / base['frames'], noc_per_image=n / noc['frames'],
                             baseline_over_noc=b / n if n else None,
                             reduction_percent=100 * (b - n) / b if b else None)
    result['scope_note'] = ('Logical enabled memory operations. Boundary includes conv1/conv2 full-map accesses '
                            'and pool1/pool2 writes only. All-intermediate includes downstream and FC accesses. '
                            'Local row writes and NoC transfers are separate; row-buffer combinational reads, '
                            'input memory, and weight/bias ROMs are excluded. Traffic ratios are not latency speedups.')
    return result


def comparison_summary(result):
    """Format only validated, measured counters; keep local storage scope explicit."""
    traffic = result['sram_traffic']
    frames = result['frames']
    banks = {model: traffic[model]['banks'] for model in ('baseline', 'noc')}
    lines = [f"Final comparison: {frames:,} images",
             f"Cycles: baseline={result['baseline_cycles']:,}, NoC={result['noc_cycles']:,}; "
             f"speedup={result['actual_speedup']:.6f}x",
             "", "SRAM traffic totals (all intermediate activation banks)",
             f"{'Bank':<10} {'Baseline reads':>16} {'NoC reads':>16} "
             f"{'Baseline writes':>16} {'NoC writes':>16} "
             f"{'Baseline bytes':>16} {'NoC bytes':>16}"]
    totals = {model: dict(reads=0, writes=0, bytes=0) for model in banks}
    for bank in BANK_BYTES:
        values = []
        for model in banks:
            row = banks[model][bank]
            byte_count = row['read_bytes'] + row['write_bytes']
            totals[model]['reads'] += row['reads']
            totals[model]['writes'] += row['writes']
            totals[model]['bytes'] += byte_count
            values.append((row['reads'], row['writes'], byte_count))
        base, noc = values
        lines.append(f"{bank:<10} {base[0]:>16,} {noc[0]:>16,} "
                     f"{base[1]:>16,} {noc[1]:>16,} {base[2]:>16,} {noc[2]:>16,}")
    base, noc = totals['baseline'], totals['noc']
    lines.append(f"{'TOTAL':<10} {base['reads']:>16,} {noc['reads']:>16,} "
                 f"{base['writes']:>16,} {noc['writes']:>16,} "
                 f"{base['bytes']:>16,} {noc['bytes']:>16,}")
    for field in ('reads', 'writes', 'bytes'):
        reduction = f"{100 * (base[field] - noc[field]) / base[field]:.2f}%" if base[field] else 'N/A'
        lines.append(f"SRAM {field} reduction: {reduction}; per image: "
                     f"baseline={base[field] / frames:,.2f}, NoC={noc[field] / frames:,.2f}")
    boundary = traffic['boundary_sram_bytes']
    reduction = boundary['reduction_percent']
    reduction_text = f"{reduction:.2f}%" if reduction is not None else 'N/A'
    lines += ["", f"Boundary SRAM bytes: baseline={boundary['baseline_total']:,}, "
              f"NoC={boundary['noc_total']:,}; reduction={reduction_text}",
              "NoC pooling local row-buffer writes (separate from SRAM totals):"]
    for pool, row in traffic['noc']['local_rows'].items():
        lines.append(f"  pool{pool}: {row['writes']:,} writes, {row['write_bytes']:,} bytes")
    lines.append(f"  Total: {traffic['noc']['local_row_write_bytes']:,} bytes "
                 f"({traffic['noc']['local_row_write_bytes'] / frames:,.2f} bytes/image)")
    lines += ["Scope: intermediate activation SRAM only; input memory, weight/bias ROMs,",
              "NoC transfers and pooling local row-buffer operations are excluded from SRAM totals.",
              "Row-buffer combinational reads are not counted. Traffic reduction is not measured energy savings."]
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path, nargs="?")
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--noc", type=Path)
    parser.add_argument("--validate", type=Path, help="Validate one complete instrumented transcript")
    parser.add_argument("--model", choices=("baseline", "noc"))
    parser.add_argument("--frames", type=int, help="Require exactly this many initial images (1–900)")
    parser.add_argument("--summary-file", type=Path,
                        help="Write a readable final comparison including SRAM traffic")
    args = parser.parse_args()
    if args.summary_file and (not args.baseline or not args.noc or args.validate):
        parser.error("--summary-file requires --baseline and --noc")
    if args.frames is not None and not 1 <= args.frames <= 900:
        parser.error("--frames must be between 1 and 900")
    if args.validate:
        if not args.model or args.log or args.baseline or args.noc:
            parser.error("--validate requires --model only")
        rows, logits, cycles = read_standalone(args.validate, args.model, args.frames)
        print(json.dumps(dict(model=args.model, frames=len(rows), cycles=cycles,
                              sram_traffic=traffic_report(args.validate, args.model, len(rows))), indent=2))
        return
    if args.model:
        parser.error("--model requires --validate")
    if args.baseline or args.noc:
        if not args.baseline or not args.noc or args.log:
            parser.error("supply both --baseline and --noc, without a paired log")
        result = compare_transcripts(args.baseline, args.noc, args.frames)
    elif args.log:
        result = analyze(args.log)
        if args.frames is not None and result['frames'] != args.frames:
            parser.error("Paired log does not match --frames")
    else:
        parser.error("supply a paired log or --baseline and --noc")
    if args.summary_file:
        args.summary_file.write_text(comparison_summary(result))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
