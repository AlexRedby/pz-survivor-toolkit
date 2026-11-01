"""Validate completed loot-fill intervals and inclusive call counters against stages."""
from pathlib import Path
import csv
import re


MAX_FILLS = 120000
MAX_DEPTH = 256
MAX_INT = (1 << 31) - 1
MAX_LONG = (1 << 63) - 1
STAGES = ('logic', 'render', 'chunk', 'loot', 'lua', 'tiles', 'ui')
EXCLUSIVE = tuple(name + '_exclusive_ns' for name in STAGES)
COUNTERS = ('chance_calls', 'factory_calls', 'factory_nonnull', 'bag_roll_calls',
    'direct_roll_calls', 'plain_translation_calls', 'other_translation_calls')
LOOT_COLUMNS = ('frame_id', 'fill_index', 'token', 'depth', 'container_type',
    'nano_start', 'nano_end', 'wall_ns') + EXCLUSIVE + COUNTERS
SUMMARY_GROUPS = ('overall', 'phase1', 'phase2', 'phase3')


def _integer(value, label, minimum=0, maximum=MAX_LONG):
    if not isinstance(value, str) or not re.fullmatch(r'-?(?:0|[1-9][0-9]*)', value):
        raise ValueError('Invalid loot integer: ' + label)
    result = int(value)
    if not minimum <= result <= maximum:
        raise ValueError('Out-of-range loot integer: ' + label)
    return result


def _add(left, right, label):
    value = left + right
    if value > MAX_LONG:
        raise ValueError('Overflowing loot total: ' + label)
    return value


def _status(path):
    text = path.read_text(encoding='utf-8')
    if not re.fullmatch(r'[^\s=]+=[^\s=]+(?: [^\s=]+=[^\s=]+)*\n?', text):
        raise ValueError('Invalid loot status record')
    status = {}
    for field in text.rstrip('\n').split(' '):
        key, value = field.split('=')
        if key in status:
            raise ValueError('Duplicate loot status field: ' + key)
        status[key] = value
    required = dict(version='1', capacity=str(MAX_FILLS), max_depth=str(MAX_DEPTH),
        diagnostic='none', semantics='per_fill_inclusive_wall_exclusive_stage_partition',
        nested_rows='overlap', counters='inclusive_calls_not_items')
    if set(status) != set(required) | {'complete_fills', 'omitted_fills'} or any(
            status.get(key) != value for key, value in required.items()):
        raise ValueError('Incomplete/invalid loot profile status')
    status['complete_fills'] = _integer(status['complete_fills'], 'complete_fills', 0, MAX_FILLS)
    status['omitted_fills'] = _integer(status['omitted_fills'], 'omitted_fills', 0, MAX_INT)
    return status


def _rows(path):
    try:
        with path.open(newline='', encoding='utf-8') as source:
            reader = csv.DictReader(source, strict=True)
            if reader.fieldnames != list(LOOT_COLUMNS):
                raise ValueError('Invalid loot CSV columns/order')
            for index, raw in enumerate(reader, 1):
                if index > MAX_FILLS or set(raw) != set(LOOT_COLUMNS) or any(
                        value is None for value in raw.values()):
                    raise ValueError('Loot CSV row shape/capacity mismatch')
                row = {'container_type': raw['container_type']}
                for key, value in raw.items():
                    if key == 'container_type':
                        continue
                    minimum, maximum = 0, MAX_LONG
                    if key in ('nano_start', 'nano_end'):
                        minimum = -(1 << 63)
                    elif key in ('frame_id', 'fill_index'):
                        minimum, maximum = 1, MAX_FILLS
                    elif key == 'token':
                        minimum, maximum = 1, MAX_INT
                    elif key == 'depth':
                        minimum, maximum = 1, MAX_DEPTH
                    row[key] = _integer(value, key, minimum, maximum)
                if row['fill_index'] != index:
                    raise ValueError('Loot fill indices are not contiguous entry order')
                if row['factory_nonnull'] > row['factory_calls']:
                    raise ValueError('Successful loot factory calls exceed factory calls')
                yield row
    except csv.Error as error:
        raise ValueError('Malformed loot CSV') from error


def _empty_group():
    return dict(frames=0, fills=0, top_level_fills=0, wall_ms=0,
        max_single_fill_ms=0, max_single_fill=None, max_frame_fills=0,
        stage_exclusive_ms={name: 0 for name in STAGES},
        counter_totals=dict.fromkeys(COUNTERS, 0))


def _maximum(summary, row):
    if summary['max_single_fill'] is None or row['wall_ns'] > summary['max_single_fill']['wall_ns']:
        summary['max_single_fill_ms'] = row['wall_ns'] / 1e6
        summary['max_single_fill'] = {key: row[key] for key in
            ('frame_id', 'fill_index', 'token', 'depth', 'container_type', 'nano_start',
             'nano_end', 'wall_ns') + COUNTERS}


def loot_metrics(cache, stage_evidence):
    """Join bounded fill rows to validated completed frames, without double counting.

    Row counters include nested calls. Only depth-one rows contribute wall, stage
    and call totals; fill counts and maximum single-fill cost include every row.
    Raw per-frame fills retain intervals for a later chunk-interval join.
    """
    cache = Path(cache)
    csv_path, status_path = cache / 'driving-loot.csv', cache / 'driving-loot-status.txt'
    for path in (csv_path, status_path, cache / 'driving-stages.csv'):
        if not path.is_file():
            raise ValueError('Missing loot profile artifact: ' + path.name)
    status = _status(status_path)
    summaries = {name: _empty_group() for name in SUMMARY_GROUPS}
    per_frame = []
    rows = iter(_rows(csv_path))
    row = next(rows, None)
    consumed, previous_frame = 0, 0
    with (cache / 'driving-stages.csv').open(newline='', encoding='utf-8') as source:
        for stage in csv.DictReader(source, strict=True):
            if len(per_frame) >= MAX_FILLS:
                raise ValueError('Loot stage frame capacity exceeded')
            frame_id = _integer(stage['frame_id'], 'stage frame_id', 1, MAX_FILLS)
            phase = _integer(stage['phase'], 'stage phase', 1, 3)
            if frame_id <= previous_frame:
                raise ValueError('Loot stage frames are out of order')
            previous_frame = frame_id
            start = _integer(stage['nano_start'], 'stage nano_start', -(1 << 63))
            end = _integer(stage['nano_end'], 'stage nano_end', -(1 << 63))
            frame_stages = {key: _integer(stage[key], 'stage ' + key) for key in EXCLUSIVE}
            frame = _empty_group()
            frame.update(frame_id=frame_id, phase=phase, frames=1, invocations=[])
            stack, tokens = [], set()
            top_wall, top_stages = 0, dict.fromkeys(EXCLUSIVE, 0)
            while row is not None and row['frame_id'] == frame_id:
                if row['token'] in tokens:
                    raise ValueError('Duplicate loot token within frame')
                tokens.add(row['token'])
                if not start <= row['nano_start'] <= row['nano_end'] <= end or (
                        row['nano_end'] - row['nano_start'] != row['wall_ns']):
                    raise ValueError('Loot interval is outside its completed frame or has invalid wall time')
                if sum(row[key] for key in EXCLUSIVE) != row['wall_ns']:
                    raise ValueError('Loot exclusive partition does not equal fill wall')
                if any(row[key] > frame_stages[key] for key in EXCLUSIVE):
                    raise ValueError('Loot exclusive counter exceeds its completed frame')
                while stack and row['depth'] <= stack[-1]['row']['depth']:
                    previous = stack.pop()['row']
                    if previous['nano_end'] > row['nano_start']:
                        raise ValueError('Loot sibling/top-level intervals overlap or are out of entry order')
                if row['depth'] != len(stack) + 1:
                    raise ValueError('Invalid loot nesting depth or missing parent')
                if stack:
                    parent = stack[-1]
                    if not parent['row']['nano_start'] <= row['nano_start'] <= row['nano_end'] <= parent['row']['nano_end']:
                        raise ValueError('Nested loot interval exceeds its parent')
                    parent['child_wall'] = _add(parent['child_wall'], row['wall_ns'], 'child wall')
                    for key in EXCLUSIVE + COUNTERS:
                        parent['children'][key] = _add(parent['children'][key], row[key], key)
                    if parent['child_wall'] > parent['row']['wall_ns'] or any(
                            parent['children'][key] > parent['row'][key] for key in EXCLUSIVE + COUNTERS):
                        raise ValueError('Loot sibling counters exceed their parent')
                else:
                    top_wall = _add(top_wall, row['wall_ns'], 'top-level wall')
                    frame['top_level_fills'] += 1
                    for key in EXCLUSIVE:
                        top_stages[key] = _add(top_stages[key], row[key], key)
                    for key in COUNTERS:
                        frame['counter_totals'][key] = _add(frame['counter_totals'][key], row[key], key)
                stack.append(dict(row=row, child_wall=0, children=dict.fromkeys(EXCLUSIVE + COUNTERS, 0)))
                frame['fills'] += 1
                frame['invocations'].append(row)
                _maximum(frame, row)
                consumed += 1
                row = next(rows, None)
            if row is not None and row['frame_id'] < frame_id:
                raise ValueError('Loot rows reference missing/out-of-order completed frames')
            if frame['fills'] != _integer(stage['loot_calls'], 'stage loot_calls'):
                raise ValueError('Loot fill count does not match completed stage frame')
            if top_wall != _integer(stage['loot_inclusive_ns'], 'stage loot_inclusive_ns'):
                raise ValueError('Top-level loot wall union does not match stage loot inclusive time')
            if top_stages['loot_exclusive_ns'] != frame_stages['loot_exclusive_ns'] or any(
                    top_stages[key] > frame_stages[key] for key in EXCLUSIVE):
                raise ValueError('Top-level loot exclusive counters do not match completed stage frame')
            frame['wall_ms'] = top_wall / 1e6
            frame['stage_exclusive_ms'] = {name: top_stages[name + '_exclusive_ns'] / 1e6 for name in STAGES}
            frame['max_frame_fills'] = frame['fills']
            per_frame.append(frame)
            for name in ('overall', 'phase' + str(phase)):
                summary = summaries[name]
                for key in ('frames', 'fills', 'top_level_fills', 'wall_ms'):
                    summary[key] += frame[key]
                summary['max_frame_fills'] = max(summary['max_frame_fills'], frame['fills'])
                if frame['max_single_fill'] is not None:
                    _maximum(summary, frame['max_single_fill'])
                for category in STAGES:
                    summary['stage_exclusive_ms'][category] += frame['stage_exclusive_ms'][category]
                for key in COUNTERS:
                    summary['counter_totals'][key] = _add(summary['counter_totals'][key], frame['counter_totals'][key], key)
    if row is not None:
        raise ValueError('Loot rows reference absent completed stage frames')
    if consumed != status['complete_fills']:
        raise ValueError('Loot CSV/status complete fill count mismatch')
    if len(per_frame) != stage_evidence['complete_frames']:
        raise ValueError('Loot/stage completed frame count mismatch')
    for summary in summaries.values():
        frames = summary['frames']
        summary['mean_fills_per_frame'] = summary['fills'] / frames if frames else None
        summary['mean_wall_per_frame_ms'] = summary['wall_ms'] / frames if frames else None
    return dict(complete_frames=len(per_frame), complete_fills=consumed,
        omitted_fills=status['omitted_fills'], groups=summaries, per_frame=per_frame,
        attribution='Owner-thread elapsed wall time and inclusive call counts per completed loot fill. '
                    'Totals use the disjoint top-level union; nested fill rows overlap.',
        limits=['Elapsed wall time is not CPU time and does not establish optimization gain.',
                'Counters are inclusive method calls while a fill is active, not distinct items or RNG draws.',
                'Only completed frame fills are joined; omitted_fills records excluded incomplete fills.'])
