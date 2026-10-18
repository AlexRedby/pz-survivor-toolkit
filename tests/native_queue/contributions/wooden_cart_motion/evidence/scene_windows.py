"""Selected recording windows and phases from completed native cart captures."""
import json
import math
import re


def record_seconds(bank, name):
    if bank == 'vehicles' and '-full-vehicle-' in name and '-slide-' in name:
        return 15
    return {'interaction': 16, 'wheel': 30, 'interruption': 20,
            'interruption-matrix': 20, 'repeat': 20, 'stop-timing': 16,
            'brace': 18, 'wall-manual-exit': 29,
            'wall-fast-manual-exit': 29}.get(bank, 12)


def contract(bank, names):
    return {'bank': bank, 'scenes': [dict(name=name, recordSeconds=record_seconds(bank, name),
            measurementStartMs=800, measurementEndMs=record_seconds(bank, name) * 1000 - 200)
            for name in names]}


def completed_windows(log, spec):
    scenes = spec['scenes']
    names = [row['name'] for row in scenes]
    if not names or len(set(names)) != len(names):
        raise ValueError('Expected nonempty unique selected scene IDs')
    for row in scenes:
        seconds = row['recordSeconds']
        if (not isinstance(row['name'], str) or not row['name']
                or type(seconds) not in (int, float) or not math.isfinite(seconds)
                or seconds != record_seconds(spec['bank'], row['name'])
                or row['measurementStartMs'] != 800 or row['measurementEndMs'] != seconds * 1000 - 200):
            raise ValueError('Invalid selected scene window')
    log = log.rsplit('[WOOD_BANK] RUN_STARTED', 1)[-1]
    expected = {row['name']: row for row in scenes}
    windows, active, retry = {}, None, None
    completions = []
    for line in log.splitlines():
        if '[WOOD_BANK] FAIL' in line:
            raise ValueError('Cart scenario failed')
        match = re.search(r'\[WOOD_BANK\] RETRY (\S+) reason=', line)
        if match:
            if active is None or active['name'] != match[1]:
                raise ValueError('Retry without an active selected scene')
            retry = (active['name'], active['attempt'] + 1)
            active = None
        match = re.search(r'\[WOOD_BANK\] CASE (\S+) attempt=(\d+) wall=(\d+)', line)
        if match:
            name, attempt, start = match[1], int(match[2]), int(match[3])
            if active is not None or retry is not None and retry != (name, attempt):
                raise ValueError('Unfinished selected attempt replaced without a matching retry')
            if name not in expected or name in windows:
                raise ValueError('Unexpected/repeated selected scene: ' + name)
            active = dict(expected[name], start=start, attempt=attempt, phases=[])
            retry = None
        match = re.search(r'\[WOOD_RAMP_EVENT\] case=(\S+) elapsed=(\d+) gait=(\S+) drive=(-?\d+)(?:\s|$)', line)
        if '[WOOD_RAMP_EVENT]' in line and match is None:
            raise ValueError('Malformed input phase receipt')
        if match:
            if active is None or active['name'] != match[1]:
                raise ValueError('Input phase outside its selected attempt')
            if match[3] not in ('0', '1', '2', 'nil') or not 0 <= int(match[4]) <= 8:
                raise ValueError('Invalid input command in selected scene')
            elapsed = int(match[2])
            gait = match[3]
            if gait == 'nil':
                gait = active['phases'][-1][1].split('gait=')[1] if active['phases'] else '0'
            active['phases'].append((elapsed, 'drive=' + match[4] + ',gait=' + gait))
        if '[CART_PATH_EVENT] ' in line:
            event = json.loads(line.split('[CART_PATH_EVENT] ', 1)[1])
            if active is None or event['case'] != active['name'] or event['start'] != active['start']:
                raise ValueError('Path phase outside its selected attempt')
            if (event['event'] not in ('prepared', 'queued', 'cancelRequested', 'terminal', 'manual', 'manualStopped', 'settled')
                    or type(event['wall']) is not int or type(event['elapsed']) is not int
                    or event['wall'] - active['start'] != event['elapsed']):
                raise ValueError('Invalid path phase in selected scene')
            active['phases'].append((event['elapsed'], event['event']))
        match = re.search(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+) file=.+? frames=(\d+) seconds=([\d.]+)', line)
        if match:
            name, start, frames, seconds = match[1], int(match[2]), int(match[3]), float(match[4])
            if (active is None or active['name'] != name or active['start'] != start
                    or frames <= 0 or abs(seconds - active['recordSeconds']) > .2):
                raise ValueError('Incomplete/mismatched selected scene receipt: ' + name)
            phases = active['phases']
            if (not phases or any(type(t) is not int or not 0 <= t <= active['recordSeconds'] * 1000 + 200 for t, _ in phases)
                    or any(a[0] > b[0] for a, b in zip(phases, phases[1:]))):
                raise ValueError('Missing or unordered selected scene phases: ' + name)
            if windows:
                previous = next(reversed(windows.values()))
                if start < previous['start'] + previous['recordSeconds'] * 1000:
                    raise ValueError('Overlapping selected scene windows')
            windows[name] = active
            active = None
        match = re.search(r'\[WOOD_BANK\] ALL_COMPLETE cases=(\d+)(?:\s|$)', line)
        if match:
            if list(windows) != names or active is not None or retry is not None:
                raise ValueError('Selected scene completion order/coverage differs from the snapshot')
            completions.append(int(match[1]))
    if list(windows) != names or completions != [len(names)] or active is not None or retry is not None:
        raise ValueError('Selected scene completion order/coverage differs from the snapshot')
    return windows


def phase_at(scene, elapsed):
    # Probe files cannot establish ordering against input events in the same tick.
    if any(time == elapsed for time, _ in scene['phases']):
        return 'transition'
    phase = 'idle'
    for time, label in scene['phases']:
        if time > elapsed:
            break
        phase = label
    return phase
