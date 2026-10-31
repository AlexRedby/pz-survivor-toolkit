"""Validate completed chunk-invocation wall intervals against the stage ledger."""
from pathlib import Path
import csv
import re


MAX_CHUNKS = 120000
MAX_DEPTH = 256
MAX_INT = (1 << 31) - 1
MAX_LONG = (1 << 63) - 1
STAGES = ('logic', 'render', 'chunk', 'loot', 'lua', 'tiles', 'ui')
EXCLUSIVE = tuple(name + '_exclusive_ns' for name in STAGES)
CHUNK_COLUMNS = ('frame_id', 'chunk_index', 'token', 'depth', 'wx', 'wy',
    'queue_depth_before', 'queue_depth_after', 'nano_start', 'nano_end', 'wall_ns') + EXCLUSIVE
SUMMARY_GROUPS = ('overall', 'phase1', 'phase2', 'phase3')


def _integer(value, label, minimum=0, maximum=MAX_LONG):
    if not isinstance(value, str) or not re.fullmatch(r'-?(?:0|[1-9][0-9]*)', value):
        raise ValueError('Invalid chunk integer: ' + label)
    result = int(value)
    if not minimum <= result <= maximum:
        raise ValueError('Out-of-range chunk integer: ' + label)
    return result


def _status(path):
    text = path.read_text(encoding='utf-8')
    if not re.fullmatch(r'[^\s=]+=[^\s=]+(?: [^\s=]+=[^\s=]+)*\n?', text):
        raise ValueError('Invalid chunk status record')
    status = {}
    for field in text.rstrip('\n').split(' '):
        key, value = field.split('=')
        if key in status:
            raise ValueError('Duplicate chunk status field: ' + key)
        status[key] = value
    required = dict(version='1', capacity=str(MAX_CHUNKS), max_depth=str(MAX_DEPTH),
        diagnostic='none', semantics='per_chunk_inclusive_wall_exclusive_stage_partition',
        nested_rows='overlap', queue_depth='O1_observed_after_dequeue_not_wait')
    if set(status) != set(required) | {'complete_chunks', 'omitted_chunks'} or any(
            status.get(key) != value for key, value in required.items()):
        raise ValueError('Incomplete/invalid chunk profile status')
    status['complete_chunks'] = _integer(status['complete_chunks'], 'complete_chunks', 0, MAX_CHUNKS)
    status['omitted_chunks'] = _integer(status['omitted_chunks'], 'omitted_chunks', 0, MAX_INT)
    return status


def _rows(path):
    try:
        with path.open(newline='', encoding='utf-8') as source:
            reader = csv.DictReader(source, strict=True)
            if reader.fieldnames != list(CHUNK_COLUMNS):
                raise ValueError('Invalid chunk CSV columns/order')
            for index, raw in enumerate(reader, 1):
                if index > MAX_CHUNKS or set(raw) != set(CHUNK_COLUMNS) or any(
                        value is None for value in raw.values()):
                    raise ValueError('Chunk CSV row shape/capacity mismatch')
                row = {}
                for key, value in raw.items():
                    minimum, maximum = 0, MAX_LONG
                    if key in ('wx', 'wy', 'queue_depth_before', 'queue_depth_after'):
                        minimum, maximum = -(1 << 31), MAX_INT
                    elif key in ('nano_start', 'nano_end'):
                        minimum = -(1 << 63)
                    elif key in ('frame_id', 'chunk_index'):
                        minimum, maximum = 1, MAX_CHUNKS
                    elif key == 'token':
                        minimum, maximum = 1, MAX_INT
                    elif key == 'depth':
                        minimum, maximum = 1, MAX_DEPTH
                    row[key] = _integer(value, key, minimum, maximum)
                if row['chunk_index'] != index:
                    raise ValueError('Chunk indices are not contiguous entry order')
                yield row
    except csv.Error as error:
        raise ValueError('Malformed chunk CSV') from error


def _empty_group():
    return dict(frames=0, chunks=0, top_level_chunks=0, wall_ms=0,
        max_single_chunk_ms=0, max_single_chunk=None, max_frame_chunks=0,
        min_queue_depth=None, max_queue_depth=None,
        stage_exclusive_ms={name: 0 for name in STAGES})


def _extrema(summary, row):
    values = row['queue_depth_before'], row['queue_depth_after']
    lower, upper = min(values), max(values)
    summary['min_queue_depth'] = (lower if summary['min_queue_depth'] is None
        else min(summary['min_queue_depth'], lower))
    summary['max_queue_depth'] = (upper if summary['max_queue_depth'] is None
        else max(summary['max_queue_depth'], upper))
    if summary['max_single_chunk'] is None or row['wall_ns'] > summary['max_single_chunk']['wall_ns']:
        summary['max_single_chunk_ms'] = row['wall_ns'] / 1e6
        summary['max_single_chunk'] = {key: row[key] for key in
            ('frame_id', 'chunk_index', 'token', 'depth', 'wx', 'wy', 'wall_ns')}


def chunk_metrics(cache, stage_evidence):
    """Join bounded invocation records to an already validated completed-frame CSV.

    Nested rows overlap. Only depth-one rows contribute elapsed-wall and exclusive
    totals; invocation counts and maximum single-call time include every row.
    """
    cache = Path(cache)
    csv_path, status_path = cache / 'driving-chunks.csv', cache / 'driving-chunks-status.txt'
    for path in (csv_path, status_path):
        if not path.is_file():
            raise ValueError('Missing chunk profile artifact: ' + path.name)
    status = _status(status_path)
    summaries = {name: _empty_group() for name in SUMMARY_GROUPS}
    per_frame = []
    rows = iter(_rows(csv_path))
    row = next(rows, None)
    consumed = 0
    with (cache / 'driving-stages.csv').open(newline='', encoding='utf-8') as source:
        for stage in csv.DictReader(source, strict=True):
            if len(per_frame) >= MAX_CHUNKS:
                raise ValueError('Chunk stage frame capacity exceeded')
            frame_id = int(stage['frame_id'])
            start, end = int(stage['nano_start']), int(stage['nano_end'])
            frame_counters = {key: int(stage[key]) for key in EXCLUSIVE}
            frame = _empty_group()
            frame.update(frame_id=frame_id, phase=int(stage['phase']))
            frame['frames'] = 1
            stack, tokens = [], set()
            top_wall, top_counters = 0, dict.fromkeys(EXCLUSIVE, 0)
            while row is not None and row['frame_id'] == frame_id:
                if row['token'] in tokens:
                    raise ValueError('Duplicate chunk token within frame')
                tokens.add(row['token'])
                if not start <= row['nano_start'] <= row['nano_end'] <= end or (
                        row['nano_end'] - row['nano_start'] != row['wall_ns']):
                    raise ValueError('Chunk interval is outside its completed frame or has invalid wall time')
                if sum(row[key] for key in EXCLUSIVE) != row['wall_ns']:
                    raise ValueError('Chunk exclusive partition does not equal invocation wall')
                if any(row[key] > frame_counters[key] for key in EXCLUSIVE):
                    raise ValueError('Chunk exclusive counter exceeds its completed frame')
                while stack and row['depth'] <= stack[-1]['row']['depth']:
                    previous = stack.pop()['row']
                    if previous['nano_end'] > row['nano_start']:
                        raise ValueError('Chunk sibling/top-level intervals overlap or are out of entry order')
                if row['depth'] != len(stack) + 1:
                    raise ValueError('Invalid chunk nesting depth or missing parent')
                if stack:
                    parent = stack[-1]
                    if not parent['row']['nano_start'] <= row['nano_start'] <= row['nano_end'] <= parent['row']['nano_end']:
                        raise ValueError('Nested chunk interval exceeds its parent')
                    parent['child_wall'] += row['wall_ns']
                    for key in EXCLUSIVE:
                        parent['children'][key] += row[key]
                    if parent['child_wall'] > parent['row']['wall_ns'] or any(
                            parent['children'][key] > parent['row'][key] for key in EXCLUSIVE):
                        raise ValueError('Chunk sibling counters exceed their parent')
                else:
                    top_wall += row['wall_ns']
                    frame['top_level_chunks'] += 1
                    for key in EXCLUSIVE:
                        top_counters[key] += row[key]
                stack.append(dict(row=row, child_wall=0, children=dict.fromkeys(EXCLUSIVE, 0)))
                frame['chunks'] += 1
                _extrema(frame, row)
                consumed += 1
                row = next(rows, None)
            if row is not None and row['frame_id'] < frame_id:
                raise ValueError('Chunk rows reference missing/out-of-order completed frames')
            if frame['chunks'] != int(stage['chunk_calls']):
                raise ValueError('Chunk invocation count does not match completed stage frame')
            if top_wall != int(stage['chunk_inclusive_ns']):
                raise ValueError('Top-level chunk wall union does not match stage chunk inclusive time')
            if top_counters['chunk_exclusive_ns'] != frame_counters['chunk_exclusive_ns'] or any(
                    top_counters[key] > frame_counters[key] for key in EXCLUSIVE):
                raise ValueError('Top-level chunk exclusive counters do not match completed stage frame')
            frame['wall_ms'] = top_wall / 1e6
            frame['stage_exclusive_ms'] = {name: top_counters[name + '_exclusive_ns'] / 1e6 for name in STAGES}
            frame['max_frame_chunks'] = frame['chunks']
            per_frame.append(frame)
            for name in ('overall', 'phase' + stage['phase']):
                summary = summaries[name]
                for key in ('frames', 'chunks', 'top_level_chunks', 'wall_ms'):
                    summary[key] += frame[key]
                summary['max_frame_chunks'] = max(summary['max_frame_chunks'], frame['chunks'])
                if frame['max_single_chunk'] is not None:
                    record = frame['max_single_chunk']
                    # Queue extrema encompass all invocation rows, including nested ones.
                    _extrema(summary, dict(record, queue_depth_before=frame['min_queue_depth'],
                        queue_depth_after=frame['max_queue_depth']))
                for category in STAGES:
                    summary['stage_exclusive_ms'][category] += frame['stage_exclusive_ms'][category]
    if row is not None:
        raise ValueError('Chunk rows reference absent completed stage frames')
    if consumed != status['complete_chunks']:
        raise ValueError('Chunk CSV/status complete invocation count mismatch')
    if len(per_frame) != stage_evidence['complete_frames']:
        raise ValueError('Chunk/stage completed frame count mismatch')
    for summary in summaries.values():
        frames = summary['frames']
        summary['mean_chunks_per_frame'] = summary['chunks'] / frames if frames else None
        summary['mean_wall_per_frame_ms'] = summary['wall_ms'] / frames if frames else None
    return dict(complete_frames=len(per_frame), complete_chunks=consumed,
        omitted_chunks=status['omitted_chunks'], groups=summaries, per_frame=per_frame,
        attribution='Owner-thread elapsed wall time per completed chunk invocation. '
                    'Totals use the disjoint top-level union; nested invocation rows overlap.',
        limits=['Elapsed wall time is not CPU time and does not establish optimization gain.',
                'Queue depth is an O(1) concurrent snapshot after dequeue, not queue wait or exact queue inventory; signed values are retained.',
                'Only completed frame invocations are joined; omitted_chunks records excluded incomplete invocations.'])
