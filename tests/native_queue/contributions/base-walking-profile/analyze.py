#!/usr/bin/env python3
"""Compare complete native frames, including tile-crossing witnesses from Lua."""
import argparse
import bisect
import csv
import json
import math
from pathlib import Path

STAGES = ('logic', 'render', 'chunk', 'loot', 'lua', 'tiles', 'ui', 'other')


def percentile(values, fraction):
    values = sorted(values)
    return values[max(0, math.ceil(len(values) * fraction) - 1)] if values else None


def summary(rows):
    if not rows:
        return {'frames': 0}
    wall = [r['wall_ns'] / 1e6 for r in rows]
    total = sum(r['wall_ns'] for r in rows)
    cpu = [r['cpu_ns'] for r in rows if r['cpu_ns'] >= 0]
    return {'frames': len(rows), 'wall_ms': {'p50': percentile(wall, .5),
            'p95': percentile(wall, .95), 'p99': percentile(wall, .99), 'max': max(wall)},
            'over_16_7_ms': sum(v > 16.7 for v in wall),
            'over_33_3_ms': sum(v > 33.3 for v in wall),
            'over_50_ms': sum(v > 50 for v in wall),
            'cpu_fraction': sum(cpu) / total if len(cpu) == len(rows) and total else None,
            'exclusive_fraction': {name: sum(r[name + '_exclusive_ns'] for r in rows) / total
                                   for name in STAGES},
            'inclusive_ms_per_frame': {name: sum(r[name + '_inclusive_ns'] for r in rows) / len(rows) / 1e6
                                       for name in STAGES if name != 'other'}}


def analyze(cache):
    with (cache / 'base-walking-stages.csv').open() as source:
        rows = [{k: float(v) if k == 'speed_kmh' else int(v) for k, v in r.items()}
                for r in csv.DictReader(source)]
    if not rows:
        raise ValueError('No complete native frames')
    if len({r['frame_id'] for r in rows}) != len(rows):
        raise ValueError('Duplicate native frame IDs')
    for row in rows:
        if sum(row[name + '_exclusive_ns'] for name in STAGES) != row['wall_ns']:
            raise ValueError('Exclusive timer accounting mismatch')
    motion = [json.loads(line) for line in (cache / 'Lua/base-walking-motion.jsonl.txt').read_text().splitlines()]
    crossings = {r['frame'] for r in motion if r['tileChanged'] and r['frame'] > 0}
    moving = {r['frame'] for r in motion if r['moving'] and r['frame'] > 0}
    phases = {}
    measured = []
    for phase, name in ((1, 'stationary'), (2, 'walking'), (3, 'post_stationary')):
        source = [r for r in rows if r['phase'] == phase]
        if not source:
            raise ValueError('Missing phase ' + str(phase))
        # First hook invocation has a one-time diagnostic marker; exclude startup.
        selected = [r for r in source if r['nano_start'] - source[0]['nano_start'] >= 2_000_000_000]
        phases[name] = summary(selected)
        measured.extend(selected)
    walking = [r for r in measured if r['phase'] == 2]
    crossing_neighbors = crossings | {value + 1 for value in crossings}
    starts = sorted(r['nano_start'] for r in rows if r['frame_id'] in crossings)
    # UIManager updates on a 100 ms cadence. The actual discovery callback can
    # arrive several rendered frames after the movement tick.
    def after_crossing(row):
        index = bisect.bisect_right(starts, row['nano_start']) - 1
        return index >= 0 and row['nano_start'] - starts[index] <= 120_000_000
    tail = [r for r in measured if r['wall_ns'] > 33_300_000]
    return {'limits': ['Mac Host measurements are not frame-time predictions for a weaker remote PC.',
                       'frameStep CPU/wall durations exclude external frame pacing; inspect JFR swap intervals too.',
                       'Native timed walking is a movement witness, not physical keyboard input.',
                       'The first two seconds of each phase are excluded from aggregates.'],
            'phases': phases,
            'walking_tile_crossing_or_next_frame': summary([r for r in walking if r['frame_id'] in crossing_neighbors]),
            'walking_other_frames': summary([r for r in walking if r['frame_id'] not in crossing_neighbors]),
            'walking_post_tile_120ms': summary([r for r in walking if after_crossing(r)]),
            'walking_outside_post_tile_120ms': summary([r for r in walking if not after_crossing(r)]),
            'walking_moving_frames': summary([r for r in walking if r['frame_id'] in moving]),
            'long_frames': summary(tail),
            'largest_frames': sorted(measured, key=lambda r: r['wall_ns'], reverse=True)[:25],
            'motion': {'rows': len(motion), 'tile_crossing_frames': len(crossings),
                       'moving_frames': len(moving), 'rows_without_frame': sum(r['frame'] <= 0 for r in motion)},
            'profiler_status': (cache / 'base-walking-stages-status.txt').read_text()}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('cache', type=Path)
    args = parser.parse_args()
    print(json.dumps(analyze(args.cache), indent=2))
