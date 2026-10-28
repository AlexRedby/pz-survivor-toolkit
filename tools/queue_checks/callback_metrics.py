"""Validate bounded callback wall attribution joined to completed stage frames."""
from pathlib import Path
import csv
import re

from .adapters.optimizer_benchmark import stage_metrics


SOURCE_COLUMNS = ('callback_id', 'kind', 'filename', 'file', 'name', 'line_first_instruction')
CALLBACK_COLUMNS = ('frame_id', 'callback_id', 'calls', 'inclusive_ns', 'exclusive_ns', 'max_call_ns')
FRAME_COLUMNS = ('frame_id', 'nano_start', 'nano_end', 'callbacks', 'rows', 'exclusive_ns')
MAX_FRAMES, MAX_ROWS, MAX_IDENTITIES, MAX_DEPTH = 6000, 1200000, 2048, 64
MAX_INTEGER = (1 << 31) - 1
GROUPS = ('overall', 'stationary', 'moving10', 'moving30', 'phase1', 'phase2', 'phase3')


def _integer(value, label, minimum=0, maximum=(1 << 63) - 1):
    if not isinstance(value, str) or not re.fullmatch(r'-?(?:0|[1-9][0-9]*)', value):
        raise ValueError('Invalid callback integer: ' + label)
    result = int(value)
    if not minimum <= result <= maximum:
        raise ValueError('Out-of-range callback integer: ' + label)
    return result


def _rows(path, columns, capacity):
    with path.open(newline='', encoding='utf-8') as source:
        reader = csv.DictReader(source, strict=True)
        if reader.fieldnames != list(columns):
            raise ValueError('Invalid callback CSV columns/order: ' + path.name)
        for index, row in enumerate(reader, 1):
            if index > capacity or set(row) != set(columns) or any(value is None for value in row.values()):
                raise ValueError('Callback CSV row shape/capacity mismatch: ' + path.name)
            yield row


def _status(path):
    text = path.read_text(encoding='utf-8')
    if not re.fullmatch(r'[^\s=]+=[^\s=]+(?: [^\s=]+=[^\s=]+)*\n?', text):
        raise ValueError('Invalid callback status record')
    status = {}
    for token in text.rstrip('\n').split(' '):
        key, value = token.split('=')
        if key in status:
            raise ValueError('Duplicate callback status field: ' + key)
        status[key] = value
    version = status.get('version')
    row_cap = 1000000 if version == '1' else MAX_ROWS
    required = {
        'version': version, 'max_frames': str(MAX_FRAMES), 'max_rows': str(row_cap),
        'max_identities': str(MAX_IDENTITIES), 'max_depth': str(MAX_DEPTH),
        'diagnostic': 'none', 'coverage': 'LuaCaller-native-terminal-overloads',
        'inclusive': 'identity-union-nonadditive', 'exclusive': 'callback-stack-only'}
    if version not in ('1', '2'):
        raise ValueError('Unsupported callback status version')
    if version == '2':
        if status.get('detail_spans') not in ('enabled', 'disabled'):
            raise ValueError('Invalid callback inner-span status')
        required['detail_spans'] = status['detail_spans']
    counts = ('complete_frames', 'rows', 'identities', 'omitted_incomplete_frames')
    if set(status) != set(required) | set(counts) | {'stopped'} or any(
            status.get(key) != value for key, value in required.items()):
        raise ValueError('Incomplete/invalid callback profile status')
    for key, cap in zip(counts, (MAX_FRAMES, row_cap, MAX_IDENTITIES, (1 << 63) - 1)):
        status[key] = _integer(status[key], key, maximum=cap)
    if status['stopped'] not in ('frame-limit', 'finish') or (
            (status['stopped'] == 'frame-limit') != (status['complete_frames'] == MAX_FRAMES)):
        raise ValueError('Invalid callback stopping status')
    status.setdefault('detail_spans', 'disabled')
    return status


def callback_metrics(cache):
    """Return diagnostic evidence only; invalid stage or callback artifacts fail closed."""
    cache = Path(cache)
    # This must run first: phase/speed and all stage timings inherit its validation.
    stage_evidence = stage_metrics(cache)
    paths = {name: cache / ('driving-' + name + '.csv')
             for name in ('callback-sources', 'callbacks', 'callback-frames')}
    status_path = cache / 'driving-callback-status.txt'
    for path in (*paths.values(), status_path):
        if not path.is_file():
            raise ValueError('Missing callback profile artifact: ' + path.name)
    status = _status(status_path)
    if status['complete_frames'] > stage_evidence['complete_frames']:
        raise ValueError('Callback frame count exceeds completed stage frames')

    identities = {}
    for row in _rows(paths['callback-sources'], SOURCE_COLUMNS, MAX_IDENTITIES):
        callback_id = _integer(row['callback_id'], 'callback_id', maximum=MAX_IDENTITIES - 1)
        if callback_id in identities or row['kind'] not in ('lua', 'java', 'other', 'null'):
            raise ValueError('Invalid/duplicate callback identity')
        if any('\0' in row[key] or len(row[key].encode('utf-16-le')) // 2 > 4096
               for key in ('kind', 'filename', 'file', 'name')):
            raise ValueError('Callback source string exceeds bound')
        identities[callback_id] = dict(row, callback_id=callback_id,
            line_first_instruction=_integer(row['line_first_instruction'], 'line_first_instruction', -1, MAX_INTEGER))
    if set(identities) != set(range(len(identities))) or len(identities) != status['identities']:
        raise ValueError('Callback source IDs/count mismatch')

    # Read only the bounded prefix after stage_metrics has checked the whole file.
    stages = []
    with (cache / 'driving-stages.csv').open(newline='') as source:
        for row in csv.DictReader(source, strict=True):
            if len(stages) == status['complete_frames']:
                break
            stages.append(dict(frame_id=int(row['frame_id']), nano_start=int(row['nano_start']),
                nano_end=int(row['nano_end']), wall_ns=int(row['wall_ns']),
                phase=int(row['phase']), speed_kmh=float(row['speed_kmh'])))
    frames = {}
    for index, raw in enumerate(_rows(paths['callback-frames'], FRAME_COLUMNS, MAX_FRAMES)):
        row = {key: _integer(value, key, -(1 << 63) if key in ('nano_start', 'nano_end') else 0,
                             MAX_INTEGER if key == 'callbacks' else (1 << 63) - 1)
               for key, value in raw.items()}
        if index >= len(stages) or any(row[key] != stages[index][key]
                for key in ('frame_id', 'nano_start', 'nano_end')):
            raise ValueError('Callback frames do not match completed stage prefix')
        stage = stages[index]
        if row['exclusive_ns'] > stage['wall_ns'] or row['rows'] > MAX_IDENTITIES:
            raise ValueError('Invalid callback frame bounds')
        frames[row['frame_id']] = dict(stage, expected=row, actual_rows=0, actual_calls=0, actual_exclusive=0)
    if len(frames) != status['complete_frames']:
        raise ValueError('Callback frame CSV/status count mismatch')

    groups = {name: dict(frames=0, frame_wall_ms=0, calls=0, callback_rows=0,
                         callback_exclusive_ms=0, callback_inclusive_ms_nonadditive=0, sources={})
              for name in GROUPS}
    for frame in frames.values():
        frame['groups'] = ['overall', 'phase' + str(frame['phase'])]
        if frame['speed_kmh'] < 1:
            frame['groups'].append('stationary')
        if frame['speed_kmh'] >= 10:
            frame['groups'].append('moving10')
        if frame['speed_kmh'] >= 30:
            frame['groups'].append('moving30')
        for name in frame['groups']:
            groups[name]['frames'] += 1
            groups[name]['frame_wall_ms'] += frame['wall_ns'] / 1e6
    previous, row_count = None, 0
    for raw in _rows(paths['callbacks'], CALLBACK_COLUMNS, int(status['max_rows'])):
        row = {key: _integer(value, key, maximum=MAX_INTEGER if key == 'calls' else (1 << 63) - 1)
               for key, value in raw.items()}
        key = row['frame_id'], row['callback_id']
        if previous is not None and key <= previous:
            raise ValueError('Unordered/duplicate callback rows')
        previous = key
        frame = frames.get(row['frame_id'])
        if frame is None or row['callback_id'] not in identities:
            raise ValueError('Callback row references an unknown frame/source')
        if (row['calls'] <= 0 or not 0 <= row['exclusive_ns'] <= row['inclusive_ns'] <= frame['wall_ns']
                or row['max_call_ns'] > row['inclusive_ns']):
            raise ValueError('Invalid callback timing/call bounds')
        frame['actual_rows'] += 1
        frame['actual_calls'] += row['calls']
        frame['actual_exclusive'] += row['exclusive_ns']
        row_count += 1
        for name in frame['groups']:
            group = groups[name]
            group['calls'] += row['calls']
            group['callback_rows'] += 1
            group['callback_exclusive_ms'] += row['exclusive_ns'] / 1e6
            group['callback_inclusive_ms_nonadditive'] += row['inclusive_ns'] / 1e6
            source = group['sources'].setdefault(row['callback_id'], dict(identities[row['callback_id']],
                frames=0, calls=0, inclusive_ms=0, exclusive_ms=0, max_call_ms=0))
            source['frames'] += 1
            source['calls'] += row['calls']
            source['inclusive_ms'] += row['inclusive_ns'] / 1e6
            source['exclusive_ms'] += row['exclusive_ns'] / 1e6
            source['max_call_ms'] = max(source['max_call_ms'], row['max_call_ns'] / 1e6)
    if row_count != status['rows']:
        raise ValueError('Callback row CSV/status count mismatch')
    for frame in frames.values():
        if (frame['expected']['rows'] != frame['actual_rows']
                or frame['expected']['callbacks'] != frame['actual_calls']
                or frame['expected']['exclusive_ns'] != frame['actual_exclusive']
                or frame['actual_exclusive'] > frame['wall_ns']):
            raise ValueError('Callback frame summary/row mismatch')
    for group in groups.values():
        sources = list(group.pop('sources').values())
        for field in ('exclusive', 'inclusive'):
            group['top_by_' + field] = sorted(sources,
                key=lambda source: (-source[field + '_ms'], source['callback_id']))[:20]
    return dict(complete_frames=status['complete_frames'], rows=row_count, identities=len(identities),
        omitted_incomplete_frames=status['omitted_incomplete_frames'], stopped=status['stopped'],
        detail_spans=status['detail_spans'],
        attribution=('Owner-thread elapsed wall time at LuaCaller native terminal overloads'
                    + (' and explicitly selected inner Lua spans' if status['detail_spans'] == 'enabled' else '') + '. ')
                    + 'Inclusive time is a per-identity union and is nonadditive across identities; '
                    'exclusive time excludes nested callback-stack work only.', groups=groups,
        limits=['Synchronous Java work and nested Lua executed within a callback are included.',
                'This is not VM instruction timing, exact CPU cost, or a full Lua callback census.',
                'Instrumentation adds overhead. Captures cover only the completed-frame prefix; omitted incomplete frames are excluded.',
                'Callback attribution and mod-subset failures do not qualify performance or establish optimization gain.'])
