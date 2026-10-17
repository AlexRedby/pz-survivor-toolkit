"""Native route lifecycle and independent sampled cart/world clearance."""
import argparse
import importlib.util
import json
import math
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('cart_path_footprint', Path(__file__).with_name('analyze-footprint.py'))
footprint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(footprint)
SPECS = ('straight', 'corner', 'door-open', 'door-closed', 'overlap', 'cancel')
CASES = {f'{sex}-{load}-{case}' for sex in ('male', 'female') for load in ('empty', 'full') for case in SPECS}


def motion(text, lifecycle):
    assert '[WOOD_BANK] RUN_STARTED' in text, 'Missing native path run boundary'
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[1]
    completed = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)', log)
    assert len(completed) == 24 and {n for n, _ in completed} == CASES, 'Missing/duplicate path cases'
    assert re.search(r'\[WOOD_BANK\] ALL_COMPLETE cases=24(?:\s|$)', log) and '[WOOD_BANK] FAIL' not in log, 'Path scenario incomplete/failed'
    records = []
    for index, line in enumerate(log.splitlines()):
        match = re.search(r'\[CART_PATH_(SAMPLE|EVENT)\] (\{.*\})', line)
        if match:
            row = json.loads(match[2])
            row['_order'] = index
            row['_sample'] = match[1] == 'SAMPLE'
            for value in row.values():
                if type(value) in (float, int):
                    assert math.isfinite(value), 'Nonfinite path measurement'
            records.append(row)
    summaries, cases = [], {}
    for name, timestamp in completed:
        start = int(timestamp)
        selected = [r for r in records if r['case'] == name and r['start'] == start]
        rows = [r for r in selected if r['_sample']]
        events = [r for r in selected if not r['_sample']]
        kind = name.split('-', 2)[2]
        expected = ['prepared', 'queued'] + (['cancelRequested'] if kind == 'cancel' else []) + ['terminal', 'manual', 'manualStopped', 'settled']
        assert [r['event'] for r in events] == expected, 'Missing/reordered path receipts: ' + name
        event = {r['event']: r for r in events}
        assert len(rows) >= 100 and rows[0]['elapsed'] < 200 and rows[-1]['elapsed'] >= 11900, 'Missing path sample window'
        assert all(0 < b['wall']-a['wall'] <= 500 for a, b in zip(rows, rows[1:])), 'Path sampling gap'
        first = events[0]
        assert all(r['wall']-start == r['elapsed'] and r['female'] is name.startswith('female-') and r['id'] == first['id']
                   and r['z'] == first['z'] and r['cargo'] == first['cargo'] for r in selected), 'Path changed sex/cart/cargo/level'
        assert (first['cargo'] > 0) == ('-full-' in name), 'Wrong path cargo'
        queued, terminal, manual, stopped, settled = (event[k] for k in ('queued', 'terminal', 'manual', 'manualStopped', 'settled'))
        assert 950 <= queued['elapsed'] <= 1500 and 0 < terminal['wall']-queued['wall'] < 8500, 'Unbounded/missing native path termination'
        assert manual['wall']-terminal['wall'] >= 200 and stopped['wall']-manual['wall'] >= 850, 'Missing manual recovery window'
        assert all(r['drive'] == 0 for r in rows if r['_order'] < manual['_order']), 'Keyboard input masqueraded as native path'
        assert all(r['drive'] == manual['drive'] and r['drive'] in range(1, 9) for r in rows
                   if manual['_order'] < r['_order'] < stopped['_order']), 'Manual recovery input missing'
        assert all(r['drive'] == 0 for r in rows if r['_order'] > stopped['_order']), 'Manual input not released'
        path = [r for r in rows if queued['_order'] < r['_order'] < terminal['_order'] and r['hasPath']]
        if kind in ('straight', 'corner', 'door-open', 'cancel'):
            assert len(path) >= 3, 'Native path never became active: ' + name
        assert all(r['motion'] for r in path), 'Path disabled cart visual gate'
        assert all(not r['pivot'] for r in path if r['wall'] >= path[0]['wall']+100), 'Manual pivot controller took over native path'
        assert all(not r['hasPath'] and r['luaActions'] == r['nativeActions'] == 0 for r in (terminal, manual, stopped, settled)), 'Native path/action leaked after termination'
        resumed = [r for r in rows if manual['wall']+150 <= r['wall'] < stopped['wall']]
        assert len(resumed) >= 3 and all(r['motion'] and r['pivot'] for r in resumed), 'Manual cart controller did not resume'
        native = [r for r in lifecycle if queued['wall'] <= r['wallTimeMillis'] <= terminal['wall']+100
                  and r['metaType'] == 'ISWalkToTimedActionF']
        success = terminal['result'] == 'Succeeded'
        assert [r['event'] for r in native] == (['start', 'perform', 'complete'] if success else ['start', 'stop']), 'Wrong native path lifecycle: ' + name
        assert len({r['nativeActionId'] for r in native}) == 1 and all(r['threw'] is None for r in native), 'Native path identity/exception failure'
        assert all(r['primaryHandItemId'] == first['id'] and r['secondaryHandItemId'] == first['id'] for r in native), 'Native path changed held cart'
        if kind in ('straight', 'door-open'):
            assert success, 'Clear native route did not reach its goal: ' + name
        elif kind == 'door-closed':
            assert terminal['result'] == 'Failed' and not any(r['doorOpen'] for r in selected), 'Locked door opened or route succeeded'
        elif kind == 'cancel':
            assert not success and event['cancelRequested']['_order'] < terminal['_order']
            assert event['cancelRequested']['wall'] <= terminal['wall'] and native[-1]['wallTimeMillis'] >= event['cancelRequested']['wall'], 'Native cancellation did not stop route'
        else:
            assert terminal['result'] in ('Succeeded', 'Failed'), 'Route lacks authoritative result'
        if success:
            assert math.dist((terminal['x'], terminal['y']), (first['goalX'], first['goalY'])) < .15, 'Native success outside target tolerance'
        if kind in ('straight', 'door-open', 'cancel'):
            assert math.dist((terminal['x'], terminal['y']), (first['startX'], first['startY'])) > .1, 'Native route did not move'
        if kind in ('straight', 'overlap', 'cancel'):
            assert math.dist((manual['x'], manual['y']), (stopped['x'], stopped['y'])) > .03, 'Manual recovery did not move'
        summaries.append(dict(case=name, result=terminal['result'], nativeActionId=native[0]['nativeActionId'],
                              pathSamples=len(path), durationMs=terminal['wall']-queued['wall']))
        cases[name] = dict(start=start, rows=rows, events=event, first=first, spec=kind)
    return dict(motionPass=True, caseCount=24, failures=[], cases=summaries), cases


def analyze(text, profile):
    profile = Path(profile)
    read = lambda name: [json.loads(line) for line in (profile/name).read_text().splitlines()]
    report, cases = motion(text, read('action-lifecycle.jsonl'))
    vertices, sha = footprint.mesh(profile)
    frames = read('body-clearance.jsonl')
    failures = []
    for name, case in cases.items():
        start, first, kind = case['start'], case['first'], case['spec']
        measured = [r for r in frames if start <= r['wallTimeMillis'] < start+12000]
        assert len(measured) >= 80 and measured[0]['wallTimeMillis'] <= start+200 and measured[-1]['wallTimeMillis'] >= start+11800, 'Incomplete path geometry window'
        assert all(0 < b['wallTimeMillis']-a['wallTimeMillis'] <= 500 for a, b in zip(measured, measured[1:])), 'Path geometry sampling gap'
        previous = None
        cleared = kind != 'overlap'
        initial = None
        for frame in measured:
            assert frame['female'] is name.startswith('female-'), 'Wrong geometry actor'
            bounds = footprint.world_bounds(frame, vertices)
            if previous:
                dt = (frame['wallTimeMillis']-previous['wallTimeMillis'])/1000
                assert math.dist((frame['slotX'], frame['slotY']), (previous['slotX'], previous['slotY'])) <= 8*dt+.03, 'Path position jumped outside native motion budget'
            previous = frame
            wx, gy = first['wallX'], first['gapY']
            crossing = bounds['minX'] < wx-.004 and bounds['maxX'] > wx+.004
            hit = False
            if kind == 'corner':
                hit = crossing and bounds['maxY'] > gy-2+.004 and bounds['minY'] < gy+3-.004
            elif kind == 'door-open':
                hit = crossing and (bounds['minY'] < gy-.004 or bounds['maxY'] > gy+1+.004)
            elif kind == 'door-closed':
                hit = crossing
            elif kind == 'overlap':
                intrusion = max(0, wx-bounds['minX'])
                if initial is None:
                    initial = intrusion
                    assert initial > .1, 'Overlap fixture did not intersect wall'
                hit = crossing and (cleared or intrusion > initial+.004)
                initial = min(initial, intrusion)
                if intrusion <= .004:
                    cleared = True
            if hit:
                failures.append((name, 'rendered cart crossed fixture wall'))
                break
        if not cleared:
            failures.append((name, 'initial overlap was not safely cleared'))
    report.update(footprintVerified=not failures, meshSha256=sha, failures=failures)
    report['motionPass'] = not failures
    report['limit'] = 'SP native paths; conservative sampled mesh bounds and wheel support. Body/grip/runtime and visual review remain separate.'
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    assert not args.output.exists(), 'Preserve existing path analysis'
    try:
        result = analyze(args.log.read_text(errors='replace'), args.profile)
    except (AssertionError, OSError, ValueError, KeyError) as error:
        result = dict(motionPass=False, footprintVerified=False, failures=[str(error)], cases=[])
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'cases'}, indent=2))
    raise SystemExit(0 if result['motionPass'] and result['footprintVerified'] else 1)
