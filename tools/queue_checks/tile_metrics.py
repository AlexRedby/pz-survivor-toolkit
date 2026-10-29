"""Validate independent tile-stack wall attribution joined to completed stages."""
from pathlib import Path
import csv
from itertools import zip_longest
import re


# Kept in the native producer's exact CSV order.
GROUPS = ('tiles_internal', 'perform', 'schedule', 'bake', 'precount', 'composite', 'chunk',
          'moving', 'translucent', 'terrain', 'items', 'characters', 'lighting', 'other_world', 'preparation')
OPTIMIZER_ONLY = frozenset(('schedule', 'bake', 'precount'))
MAX_FRAMES = 120000
MAX_CALLS = (1 << 31) - 1
MAX_INTEGER = (1 << 63) - 1
SUMMARY_GROUPS = ('overall', 'stationary', 'moving10', 'moving30', 'phase1', 'phase2', 'phase3')


def _columns():
    return ('frame_id', 'nano_start', 'nano_end', 'wall_ns') + tuple(
        group + suffix for group in GROUPS for suffix in ('_inclusive_ns', '_exclusive_ns', '_calls')) + (
        'other_exclusive_ns',)


TILE_COLUMNS = _columns()


def _integer(value, label, minimum=0, maximum=MAX_INTEGER):
    if not isinstance(value, str) or not re.fullmatch(r'-?(?:0|[1-9][0-9]*)', value):
        raise ValueError('Invalid tile integer: ' + label)
    result = int(value)
    if not minimum <= result <= maximum:
        raise ValueError('Out-of-range tile integer: ' + label)
    return result


def _status(path):
    text = path.read_text(encoding='utf-8')
    if not re.fullmatch(r'[^\s=]+=[^\s=]+(?: [^\s=]+=[^\s=]+)*\n?', text):
        raise ValueError('Invalid tile status record')
    status = {}
    for token in text.rstrip('\n').split(' '):
        key, value = token.split('=')
        if key in status:
            raise ValueError('Duplicate tile status field: ' + key)
        status[key] = value
    required = dict(version='1', max_frames=str(MAX_FRAMES), diagnostic='none',
        coverage='renderTilesInternal-descendants', inclusive='category-union-nonadditive',
        exclusive='tile-stack-only', partition='exclusive-plus-other-equals-wall')
    if set(status) != set(required) | {'complete_frames', 'profile'} or any(
            status.get(key) != value for key, value in required.items()):
        raise ValueError('Incomplete/invalid tile profile status')
    status['complete_frames'] = _integer(status['complete_frames'], 'complete_frames', 1, MAX_FRAMES)
    if status['profile'] not in ('native', 'official'):
        raise ValueError('Invalid tile profiler profile')
    return status


def _rows(path):
    columns = TILE_COLUMNS
    try:
        with path.open(newline='', encoding='utf-8') as source:
            reader = csv.DictReader(source, strict=True)
            if reader.fieldnames != list(columns):
                raise ValueError('Invalid tile CSV columns/order')
            for index, raw in enumerate(reader, 1):
                if index > MAX_FRAMES or set(raw) != set(columns) or any(value is None for value in raw.values()):
                    raise ValueError('Tile CSV row shape/capacity mismatch')
                yield {key: _integer(value, key, -(1 << 63) if key in ('nano_start', 'nano_end') else 0,
                    MAX_CALLS if key.endswith('_calls') else MAX_FRAMES if key == 'frame_id' else MAX_INTEGER)
                    for key, value in raw.items()}
    except csv.Error as error:
        raise ValueError('Malformed tile CSV') from error


def _empty_group():
    return dict(frames=0, frame_wall_ms=0, other_exclusive_ms=0, tile_wall={
        name: dict(inclusive_ms=0, exclusive_ms=0, calls=0,
                   max_frame_inclusive_ms=0, max_frame_exclusive_ms=0) for name in GROUPS})


def tile_metrics(cache, stage_evidence):
    """Validate tile artifacts against already validated stage evidence, without revalidating JFR."""
    cache = Path(cache)
    csv_path, status_path = cache / 'driving-tiles.csv', cache / 'driving-tiles-status.txt'
    for path in (csv_path, status_path):
        if not path.is_file():
            raise ValueError('Missing tile profile artifact: ' + path.name)
    status = _status(status_path)
    if status['complete_frames'] != stage_evidence['complete_frames']:
        raise ValueError('Tile/stage completed frame count mismatch')
    if status['profile'] != stage_evidence.get('tile_profile'):
        raise ValueError('Tile/stage profiler profile mismatch')
    summaries = {name: _empty_group() for name in SUMMARY_GROUPS}
    # Stage validation has checked the full CSV, including phase, speed and ordering.
    # Stream the join so the 120000-frame capacity does not require a second copy.
    with (cache / 'driving-stages.csv').open(newline='', encoding='utf-8') as source:
        stages = csv.DictReader(source, strict=True)
        for stage, row in zip_longest(stages, _rows(csv_path)):
            if stage is None or row is None:
                raise ValueError('Tile frames do not match every completed stage frame')
            if any(row[key] != int(stage[key]) for key in ('frame_id', 'nano_start', 'nano_end', 'wall_ns')):
                raise ValueError('Tile frames do not match every completed stage frame')
            wall = row['wall_ns']
            if wall <= 0 or row['nano_end'] - row['nano_start'] != wall:
                raise ValueError('Invalid tile frame wall timing')
            root = GROUPS[0]
            root_inclusive, root_calls = row[root + '_inclusive_ns'], row[root + '_calls']
            for name in GROUPS:
                inclusive, exclusive, calls = (row[name + suffix] for suffix in ('_inclusive_ns', '_exclusive_ns', '_calls'))
                if not 0 <= exclusive <= inclusive <= root_inclusive <= wall:
                    raise ValueError('Invalid tile timing/call bounds: ' + name)
                if calls == 0 and (inclusive or exclusive):
                    raise ValueError('Tile timing without a call: ' + name)
                if name != root and calls and not root_calls:
                    raise ValueError('Tile child call without root call: ' + name)
                if status['profile'] == 'native' and name in OPTIMIZER_ONLY and calls:
                    raise ValueError('Optimizer-only tile calls in native profile: ' + name)
            exclusive = sum(row[name + '_exclusive_ns'] for name in GROUPS)
            if exclusive + row['other_exclusive_ns'] != wall:
                raise ValueError('Tile exclusive partition does not equal frame wall')
            if exclusive != root_inclusive:
                raise ValueError('Tile exclusive partition does not equal root inclusive')
            names = ['overall', 'phase' + stage['phase']]
            speed = float(stage['speed_kmh'])
            if speed < 1:
                names.append('stationary')
            if speed >= 10:
                names.append('moving10')
            if speed >= 30:
                names.append('moving30')
            for name in names:
                summary = summaries[name]
                summary['frames'] += 1
                summary['frame_wall_ms'] += wall / 1e6
                summary['other_exclusive_ms'] += row['other_exclusive_ns'] / 1e6
                for category, values in summary['tile_wall'].items():
                    values['calls'] += row[category + '_calls']
                    for timing in ('inclusive', 'exclusive'):
                        milliseconds = row[category + '_' + timing + '_ns'] / 1e6
                        values[timing + '_ms'] += milliseconds
                        key = 'max_frame_' + timing + '_ms'
                        values[key] = max(values[key], milliseconds)
    if summaries['overall']['frames'] != status['complete_frames']:
        raise ValueError('Tile CSV/status complete frame count mismatch')
    for summary in summaries.values():
        for values in summary['tile_wall'].values():
            for timing in ('inclusive', 'exclusive'):
                values['mean_per_frame_' + timing + '_ms'] = (
                    values[timing + '_ms'] / summary['frames'] if summary['frames'] else None)
            values['mean_calls_per_frame'] = values['calls'] / summary['frames'] if summary['frames'] else None
    return dict(complete_frames=status['complete_frames'], profile=status['profile'], groups=summaries,
        attribution='Owner-thread elapsed wall time at selected renderTilesInternal method boundaries. '
                    'Inclusive time is a per-category union and is nonadditive; exclusive time excludes tile-stack children only.',
        limits=['Only explicitly instrumented descendants of renderTilesInternal are attributed; other_exclusive_ns covers the remaining frame wall.',
                'Nested reentry of a category contributes union time, so category inclusive totals must not be added.',
                'Instrumentation adds overhead. These timings are not CPU costs and do not establish optimization gain.'])
