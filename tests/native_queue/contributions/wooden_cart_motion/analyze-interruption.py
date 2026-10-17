"""Check ordinary SP cancellation, native lifecycle and exact-item retry receipts."""
import argparse
import json
from pathlib import Path
import re
import runpy

shared = runpy.run_path(str(Path(__file__).with_name('analyze-interaction.py')))
decode, finite = shared['_decode'], shared['_finite']
CASES = tuple(f'{action}-{phase}-{route}' for action in ('pickup', 'drop')
              for phase in ('early', 'contact', 'late') for route in ('cancel', 'walk'))
TYPES = {'pickup': 'ToolkitWoodCartPickup', 'drop': 'ToolkitWoodCartSetdown'}
THRESHOLDS = {'early': .15, 'contact': .55, 'late': .88}


def analyze(text, lifecycle, body, grip, world):
    assert '[WOOD_BANK] RUN_STARTED' in text, 'Missing cancellation run boundary'
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[-1]
    completed = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)', log)
    assert len(completed) == len(CASES) and {name for name, _ in completed} == set(CASES), 'Missing/duplicate cancellation cases'
    assert re.search(r'\[WOOD_BANK\] ALL_COMPLETE cases=12(?:\s|$)', log), 'Cancellation run incomplete'
    assert '[WOOD_BANK] FAIL' not in log, 'Cancellation scenario failed'
    samples, events = [], []
    for line in log.splitlines():
        match = re.search(r'\[WOOD_INTERACTION_(SAMPLE|EVENT)\] (\{.*\})', line)
        if match:
            (samples if match[1] == 'SAMPLE' else events).append(decode(match[2]))
    failures, summaries = [], []
    for name, stamp in completed:
        start = int(stamp)
        rows = [r for r in samples if r['case'] == name and r['start'] == start]
        receipts = [r for r in events if r['case'] == name and r['start'] == start]
        assert len(rows) >= 100 and rows[0]['elapsed'] < 500 and rows[-1]['elapsed'] >= 19500, 'Missing sample window: ' + name
        assert all(0 < b['wall']-a['wall'] <= 500 for a,b in zip(rows,rows[1:])), 'Cancellation sampling gap: ' + name
        action, phase, route = name.split('-')
        expected = ['prepared', 'pickupQueued']
        if action == 'drop': expected += ['pickedUp', 'dropQueued']
        expected += ['cancelRequested', 'cancelled', 'retryQueued']
        expected += ['pickedUp', 'dropQueued', 'dropped'] if action == 'pickup' else ['dropped']
        assert [r['event'] for r in receipts] == expected, 'Missing/reordered cancellation events: ' + name
        lookup = {r['event']: r for r in receipts}
        request, cancelled, retry = [lookup[key] for key in ('cancelRequested','cancelled','retryQueued')]
        assert TYPES[action] == request['actionType'] and THRESHOLDS[phase] <= request['progress'] < THRESHOLDS[phase]+.1, 'Wrong cancellation phase: ' + name
        assert 0 <= cancelled['wall']-request['wall'] < 1000 and retry['wall']-cancelled['wall'] >= 850, 'Missing cancellation/retry tail'
        first = receipts[0]
        for row in rows + receipts:
            finite(row)
            assert row['wall']-row['start'] == row['elapsed'], 'Cancellation clocks disagree'
            if (row['id'], row['cargoIDs'], row['cargoCount']) != (first['id'],first['cargoIDs'],first['cargoCount']) or abs(row['cargo']-first['cargo']) > .001:
                failures.append((name, 'item identity/cargo changed')); break
        for row in rows + receipts:
            if (row['worldCount'] not in (0,1) or row['inventoryCount'] not in (0,1)
                or row['worldCount']+row['inventoryCount'] != 1 or row['woodWorldCount'] != row['worldCount']
                or row['worldID'] != (row['id'] if row['worldCount'] else -1)
                or row['worldCount'] and (row['heldID'] != -1 or row['secondaryID'] != -1)
                or row['inventoryCount'] and row['heldID'] != row['id']
                or row['inventoryCount'] and row['secondaryID'] != row['id'] or row['worldAlpha'] < .99):
                failures.append((name, 'ownership/visibility invariant failed')); break
        tail = [r for r in rows if cancelled['wall'] <= r['wall'] < retry['wall']]
        assert len(tail) >= 10, 'Missing settled cancellation samples'
        for row in tail + [cancelled, retry]:
            if row['nativeActions'] or row['luaActions'] or row['actionType'] or row['active'] or row['rendered'] or row['ToolkitWoodCartAction'] or row['PerformingAction'] or row['IsPerformingAnAction']:
                failures.append((name, 'native/Lua/presentation cleanup incomplete')); break
        owned = action == 'drop'
        if any(r['inventoryCount'] != int(owned) or r['worldCount'] != int(not owned) for r in tail):
            failures.append((name, 'cancellation transferred ownership'))
        if any(r['condition'] != request['condition'] for r in tail):
            failures.append((name, 'cancellation changed cart condition'))
        if not owned and any(abs(r[key]-request[key]) > .0001 for r in tail for key in ('worldX','worldY','worldZ','worldRotation','worldObjectAlpha')):
            failures.append((name, 'pickup cancellation moved/mutated the ground cart'))
        native = [r for r in lifecycle if start <= r['wallTimeMillis'] < retry['wall'] and r['metaType'] == TYPES[action]]
        assert [r['event'] for r in native] == ['start','stop'], 'Cancelled native action completed or lifecycle evidence missing: ' + name
        assert native[0]['nativeActionId'] == native[1]['nativeActionId'] and not native[1]['finished'] and not native[1]['threw'], 'Invalid native stop: ' + name
        stop = native[1]['wallTimeMillis']
        assert request['wall'] <= stop <= cancelled['wall'], 'Native stop outside cancellation window'
        resumed = [r for r in lifecycle if retry['wall'] <= r['wallTimeMillis'] <= start+20000 and r['metaType'] == TYPES[action]]
        assert [r['event'] for r in resumed] == ['start','perform','complete'], 'Retry did not complete exactly once: ' + name
        assert len({r['nativeActionId'] for r in resumed}) == 1 and resumed[0]['nativeActionId'] != native[0]['nativeActionId'] and all(not r['threw'] for r in resumed), 'Retry reused stopped native action'
        summary = dict(case=name, id=first['id'], nativeStopId=native[0]['nativeActionId'],
                       retryId=resumed[0]['nativeActionId'], cancelledProgress=request['progress'],
                       cancellationLatencyMs=cancelled['wall']-request['wall'], tailSamples=len(tail))
        if owned:
            first_frames = [i for i,r in enumerate(body) if r.get('afterStopActionId') == native[0]['nativeActionId']]
            assert len(first_frames) == 1, 'Missing unique first post-stop render receipt'
            frames = [r for r in body[first_frames[0]:] if stop <= r['wallTimeMillis'] < retry['wall']]
            assert len(frames) >= 10 and 0 <= frames[0]['wallTimeMillis']-stop <= 100, 'Missing first post-stop cart render'
            assert max(b['wallTimeMillis']-a['wallTimeMillis'] for a,b in zip(frames,frames[1:])) <= 100, 'Post-stop render sampling gap'
            ys = [r['cart'][13] for r in frames]
            summary.update(firstRenderDelayMs=frames[0]['wallTimeMillis']-stop, cartYRange=[min(ys),max(ys)])
            if any(abs(y-.097179376) > .005 for y in ys): failures.append((name, 'held cart jumped after native stop'))
            grips = [r for r in grip if stop+300 <= r['wallTimeMillis'] < retry['wall']]
            assert len(grips) >= 5, 'Missing restored held grip coverage'
            if any(r['result'] is not True or r['threw'] is not False for r in grips): failures.append((name, 'restored held grip failed'))
            if any(not r['ToolkitCartMotion'] for r in tail if r['wall'] >= stop+100): failures.append((name, 'held visual gate not restored'))
        else:
            renders = [r for r in world if r['itemId']==first['id'] and stop+300 <= r['wallTimeMillis'] < retry['wall']]
            assert renders and any(r.get('renderStatus')=='Ready' and r.get('alpha',0)>.99 for r in renders), 'Missing restored world draw'
            if any(r.get('transitionHidden') is True for r in renders): failures.append((name, 'world cart remained hidden after cancellation'))
        dropped = lookup['dropped']
        assert dropped['worldCount']==1 and dropped['inventoryCount']==0 and rows[-1]['wall']-dropped['wall']>=1000, 'Missing successful retry/end state'
        summaries.append(summary)
    return dict(functionalPass=not failures, failures=failures, cases=summaries,
        limit='SP ordinary cancellation through CancelAction and injected movement keys, before transfer. Native blend-out, geometry and visual quality require video review; MP and exceptional interruptions remain separate.')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile',type=Path,required=True)
    parser.add_argument('--log',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    assert not args.output.exists(), 'Refuse to overwrite report'
    def read(name): return [decode(line) for line in (args.profile/name).read_text().splitlines()]
    result=analyze(args.log.read_text(errors='replace'), read('action-lifecycle.jsonl'),
                   read('body-clearance.jsonl'),read('wood-grip-poses.jsonl'),read('world-cart-poses.jsonl'))
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')
    print(json.dumps(result,indent=2,allow_nan=False))
    return 0 if result['functionalPass'] else 1


if __name__=='__main__': raise SystemExit(main())
