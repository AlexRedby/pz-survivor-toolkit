#!/usr/bin/env python3
"""Sampled wooden-cart trajectories, without an aesthetic acceptance threshold.

--candidate PROFILE --windows JSON [--baseline PROFILE --baseline-windows JSON]
reads native successful `draw` rows and final `held` wheel-roll matrices. Windows
are an array of {name,start,end} with absolute wall milliseconds, or the archived
temporal-render-confirmation JSON with `windows` containing {name,lo,hi}.
Each probe retains its own monotonic clock. No cross-probe clock joining occurs.
Legacy held matrices without nanoTime are explicitly incomplete. Scene completion
and every displayed frame are not verified: even full sampled coverage is partial
evidence, never an aesthetic PASS. Units are tiles and seconds, not metres.
"""
import argparse
import csv
import gzip
import hashlib
import json
import math
from pathlib import Path
import statistics
import sys

WHEEL = (-6.642862e-6, -.0041269097, -.0010569958)
HANDLE = (-5e-9, .00541905, -.00342593)
PEAKS = ('peakStepTiles', 'peakVelocityTilesPerSecond', 'peakAccelerationTilesPerSecondSquared')


def number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        raise ValueError('Invalid numeric value')
    value = float(value)
    if not math.isfinite(value):
        raise ValueError('Nonfinite measurement')
    return value


def integer(value):
    value = number(value)
    if value < 0 or value != int(value):
        raise ValueError('Invalid sequence')
    return int(value)


def load_json(text):
    def reject(value):
        raise ValueError('Nonfinite JSON literal: ' + value)
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('Duplicate JSON key: ' + key)
            result[key] = value
        return result
    return json.loads(text, parse_constant=reject, object_pairs_hook=unique)


def windows_from(data):
    rows = data['windows'] if isinstance(data, dict) else data
    result = {}
    for row in rows:
        name = row['name']
        if not isinstance(name, str) or not name or name in result:
            raise ValueError('Expected unique nonempty window names')
        start = number(row['start'] if 'end' in row else row['lo'])
        end = number(row['end'] if 'end' in row else row['hi'])
        if end <= start:
            raise ValueError('Invalid window interval')
        result[name] = dict(name=name, start=start, end=end)
    ordered = sorted(result.values(), key=lambda row: row['start'])
    if not result or any(a['end'] >= b['start'] for a, b in zip(ordered, ordered[1:])):
        raise ValueError('Empty or overlapping windows')
    return result


def source_path(profile, name):
    paths = [p for p in (profile / name, profile / (name + '.gz')) if p.exists()]
    if len(paths) > 1:
        raise ValueError('Ambiguous capture sources: ' + name)
    return paths[0] if paths else None


def open_source(path):
    return gzip.open(path, 'rt') if path.suffix == '.gz' else path.open()


def fingerprint(path):
    with path.open('rb') as stream:
        return dict(path=str(path.resolve()), sha256=hashlib.file_digest(stream, 'sha256').hexdigest())


def native_channels(row):
    v = {key: number(row[key]) for key in ('playerX', 'playerY', 'wheelX', 'wheelY', 'slotX', 'slotY', 'slotAngle', 'actorHeading')}
    if not row['type'].endswith('.WheelbarrowWood'):
        raise ValueError('Expected WheelbarrowWood capture')
    dx, dy = v['wheelX'] - v['playerX'], v['wheelY'] - v['playerY']
    sx, sy = v['wheelX'] - v['slotX'], v['wheelY'] - v['slotY']
    h, a = v['actorHeading'], v['slotAngle']
    return dict(wheelWorld=(v['wheelX'], v['wheelY']), actorWorld=(v['playerX'], v['playerY']),
                wheelActorForeAft=(dx * math.cos(h) + dy * math.sin(h),),
                wheelRenderForeAft=(sx * math.sin(a) - sy * math.cos(a),),
                slotActorForeAft=((v['slotX'] - v['playerX']) * math.cos(h) + (v['slotY'] - v['playerY']) * math.sin(h),))


def matrix_channels(row):
    m = row['cart']
    if not isinstance(m, list) or len(m) != 16:
        raise ValueError('Expected 16-element column-major cart matrix')
    m = [number(value) for value in m]
    x, y, a = (number(row[key]) for key in ('x', 'y', 'angle'))
    if any(abs(m[i]) > 1e-6 for i in (3, 7, 11)) or abs(m[15] - 1) > 1e-6:
        raise ValueError('Expected affine cart matrix')
    result = dict(slotWorld=(x, y))
    # Same calibrated model points/conversion as WoodenWheelNativeProbe.world.
    for label, point in (('cartOrigin', (0, 0, 0)), ('wheel', WHEEL), ('handle', HANDLE)):
        local = [sum(m[axis + 4 * i] * point[i] for i in range(3)) + m[axis + 12] for axis in range(3)]
        result[label + 'RenderForeAft'] = (-1.5 * local[2],)
        result[label + 'World'] = (x + 1.5 * (-local[0] * math.cos(a) - local[2] * math.sin(a)),
                                  y + 1.5 * (-local[0] * math.sin(a) + local[2] * math.cos(a)))
    return result


def read_stream(path, windows, native):
    rows = {name: [] for name in windows}
    counts = {name: dict(ignoredUpdatesOrWorldDraws=0, duplicateRecords=0) for name in windows}
    previous = None
    if path is None:
        return rows, counts
    with open_source(path) as stream:
        if native:
            reader = csv.DictReader(stream)
            required = {'sequence', 'time', 'event', 'wallTimeMillis', 'type', 'playerX', 'playerY', 'wheelX', 'wheelY', 'slotX', 'slotY', 'slotAngle', 'actorHeading'}
            if not reader.fieldnames or len(set(reader.fieldnames)) != len(reader.fieldnames) or not required <= set(reader.fieldnames):
                raise ValueError('Malformed native CSV header')
        else:
            reader = (load_json(line) for line in stream)
        for raw in reader:
            if native and (None in raw or any(value is None for value in raw.values())):
                raise ValueError('Malformed native CSV row')
            wall = number(raw['wallTimeMillis' if native else 'wall'])
            name = next((name for name, w in windows.items() if w['start'] <= wall <= w['end']), None)
            if name is None:
                continue
            source = raw['event' if native else 'source']
            if source not in (('draw', 'grounding', 'snapshot') if native else ('held', 'world')):
                raise ValueError('Unknown probe source')
            if source != ('draw' if native else 'held'):
                counts[name]['ignoredUpdatesOrWorldDraws'] += 1
                continue
            if not native and raw.get('result', True) is not True:
                raise ValueError('Failed final draw')
            time = number(raw['time']) if native else number(raw['nanoTime']) / 1e9 if 'nanoTime' in raw else None
            sample = dict(time=time, sequence=integer(raw['sequence']) if 'sequence' in raw else None,
                          wall=wall, channels=native_channels(raw) if native else matrix_channels(raw))
            for channel in sample['channels'].values():
                magnitude(channel)
            if previous is not None:
                if sample == previous:
                    counts[name]['duplicateRecords'] += 1
                    continue
                if wall < previous['wall']:
                    raise ValueError('Regressing wall clock')
                if time is not None and previous['time'] is not None and time <= previous['time']:
                    raise ValueError('Non-increasing monotonic draw clock')
                if sample['sequence'] is not None and previous['sequence'] is not None and sample['sequence'] <= previous['sequence']:
                    raise ValueError('Non-increasing draw sequence')
            rows[name].append(sample)
            previous = sample
    return rows, counts


def magnitude(vector):
    value = math.hypot(*vector)
    if not math.isfinite(value):
        raise ValueError('Nonfinite derived trajectory metric')
    return value


def metrics(rows, key):
    positions = [row['channels'][key] for row in rows]
    dt = [b['time'] - a['time'] for a, b in zip(rows, rows[1:])]
    steps = [tuple(y - x for x, y in zip(a, b)) for a, b in zip(positions, positions[1:])]
    velocity = [tuple(value / seconds for value in delta) for delta, seconds in zip(steps, dt)]
    # Interval velocities live at midpoints, including irregular sample spacing.
    acceleration = [tuple((y - x) / ((dt[i] + dt[i + 1]) / 2) for x, y in zip(a, b))
                    for i, (a, b) in enumerate(zip(velocity, velocity[1:]))]
    result = dict(zip(PEAKS, (max(map(magnitude, steps)), max(map(magnitude, velocity)),
                              max(map(magnitude, acceleration)) if acceleration else None)))
    index = max(range(len(steps)), key=lambda i: magnitude(steps[i]))
    result['peakStepInterval'] = dict(beforeWallTimeMillis=rows[index]['wall'], afterWallTimeMillis=rows[index + 1]['wall'], durationSeconds=dt[index])
    return result


def summarize(rows, window, counts, max_gap):
    result = dict(samples=len(rows), **counts, coverage=False, reasons=[], metrics={})
    if not rows:
        result['reasons'].append('missing_final_draw_samples')
        return result
    if len(rows) < 3:
        result['reasons'].append('fewer_than_three_final_draw_samples')
    missing = [row['time'] is None for row in rows]
    if any(missing):
        result['reasons'].append('missing_monotonic_clock')
        if not all(missing):
            raise ValueError('Mixed clock availability in a final draw stream')
    result['wallRangeMillis'] = [rows[0]['wall'], rows[-1]['wall']]
    if rows[0]['wall'] - window['start'] > max_gap * 1000 or window['end'] - rows[-1]['wall'] > max_gap * 1000:
        result['reasons'].append('missing_window_edges')
    if len(rows) >= 2 and not any(missing):
        dt = [b['time'] - a['time'] for a, b in zip(rows, rows[1:])]
        result['intervalSeconds'] = dict(minimum=min(dt), median=statistics.median(dt), maximum=max(dt))
        if max(dt) > max_gap:
            result['reasons'].append('sampling_gap')
        result['metrics'] = {key: metrics(rows, key) for key in rows[0]['channels']}
    result['coverage'] = not result['reasons']
    return result


def analyze_capture(profile, windows, max_gap_seconds=.15):
    profile = Path(profile)
    windows = windows_from(list(windows.values()) if isinstance(windows, dict) else windows)
    max_gap_seconds = number(max_gap_seconds)
    if max_gap_seconds <= 0:
        raise ValueError('Max gap must be positive')
    scenes, sources = {name: dict(window=window) for name, window in windows.items()}, []
    for label, filename, native in (('nativeDraw', 'wood-wheel-native.csv', True), ('finalMatrix', 'wheel-roll-draws.jsonl', False)):
        path = source_path(profile, filename)
        rows, counts = read_stream(path, windows, native)
        if path:
            sources.append(fingerprint(path))
        for name, window in windows.items():
            scenes[name][label] = summarize(rows[name], window, counts[name], max_gap_seconds)
    return dict(status='partial', aestheticPass=None, completionVerified=False,
                coverageComplete=all(row[k]['coverage'] for row in scenes.values() for k in ('nativeDraw', 'finalMatrix')),
                calibration='WheelbarrowWood B42.21', maxGapSeconds=max_gap_seconds, sources=sources, scenes=scenes)


def compare(candidate, baseline):
    result = dict(status='partial', aestheticPass=None, scenes={})
    for name in sorted(set(candidate['scenes']) | set(baseline['scenes'])):
        row = dict(comparable=False, reasons=[], streams={})
        result['scenes'][name] = row
        if name not in candidate['scenes'] or name not in baseline['scenes']:
            row['reasons'].append('window_missing_from_one_capture')
            continue
        c, b = candidate['scenes'][name], baseline['scenes'][name]
        if not math.isclose(c['window']['end'] - c['window']['start'], b['window']['end'] - b['window']['start'], abs_tol=1e-6, rel_tol=0):
            row['reasons'].append('different_window_durations')
        if candidate['maxGapSeconds'] != baseline['maxGapSeconds']:
            row['reasons'].append('different_sampling_gap_limits')
        for stream in ('nativeDraw', 'finalMatrix'):
            if not c[stream]['coverage'] or not b[stream]['coverage']:
                row['reasons'].append(stream + '_incomplete_coverage')
                continue
            row['streams'][stream] = {key: {metric: dict(candidate=value[metric], baseline=b[stream]['metrics'][key][metric], delta=value[metric] - b[stream]['metrics'][key][metric])
                    for metric in PEAKS} for key, value in c[stream]['metrics'].items()}
        row['comparable'] = not row['reasons']
    result['coverageComplete'] = all(row['comparable'] for row in result['scenes'].values())
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--windows', type=Path, required=True)
    parser.add_argument('--baseline', type=Path)
    parser.add_argument('--baseline-windows', type=Path)
    parser.add_argument('--max-gap-seconds', type=float, default=.15)
    parser.add_argument('--output', type=Path, help='New JSON file; existing output is preserved')
    args = parser.parse_args(argv)
    try:
        if bool(args.baseline) != bool(args.baseline_windows):
            raise ValueError('Baseline requires its own named absolute windows')
        result = {}
        for label, profile, window_path in (('candidate', args.candidate, args.windows), ('baseline', args.baseline, args.baseline_windows)):
            if profile is not None:
                result[label] = analyze_capture(profile, windows_from(load_json(window_path.read_text())), args.max_gap_seconds)
                result[label]['windowSource'] = fingerprint(window_path)
        if args.baseline:
            result['comparison'] = compare(result['candidate'], result['baseline'])
        covered = all(row['coverageComplete'] for row in result.values())
        result['analyzer'] = fingerprint(Path(__file__))
        result['limits'] = ['Explicit windows do not verify scene completion, equivalent input commands or every displayed frame.',
                            'Independent probe epochs are never joined. Intermediate updates do not count as final draws.',
                            'Finite differences depend on capture spacing; no aesthetic acceptance threshold or visual PASS.',
                            'No gameplay, multiplayer, clearance or video-alignment checks.']
        output = json.dumps(result, indent=2, allow_nan=False) + '\n'
        if args.output:
            with args.output.open('x') as stream:
                stream.write(output)
        else:
            print(output, end='')
        return 0 if covered else 2
    except (ValueError, KeyError, TypeError, OSError, OverflowError) as error:
        print('cart trajectory evidence invalid: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
