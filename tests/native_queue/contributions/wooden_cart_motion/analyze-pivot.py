"""Measured 180-degree relative pivots; cadence is descriptive, visual quality needs review."""
import argparse
import csv
import importlib.util
import json
import math
from pathlib import Path
import re

_spec = importlib.util.spec_from_file_location('stationary_diagnostics', Path(__file__).with_name('analyze-stationary.py'))
_stationary = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_stationary)
wrap = _stationary.wrap
SCENES = [f'{sex}-{load}-pivot-{side}' for sex in ('male', 'female') for load in ('empty', 'full') for side in ('left', 'right')]
PHASES = ['rest', 'pivot', 'pivot-complete', 'released', 'forward-exit', 'moving-entry', 'final-rest', 'clip-complete']


def event(line):
    values = _stationary.fields(line.split('[CART_PIVOT_EVENT] ', 1)[1])
    for key in ('wall', 'elapsed', 'drive'):
        values[key] = int(values[key])
    for key in ('accumulated', 'heading'):
        values[key] = float(values[key])
        assert math.isfinite(values[key]), 'Nonfinite pivot event'
    return values


def distance_range(points):
    return max((math.dist(points[0], point) for point in points), default=0)


def foot_summary(body):
    result = {}
    for side in 'LR':
        matrices = [row['bones']['Bip01_' + side + '_Foot'] for row in body]
        assert all(len(m) == 16 and all(math.isfinite(x) for x in m) for m in matrices), 'Invalid foot matrix'
        points = [tuple(m[i] for i in (12, 13, 14)) for m in matrices]
        # ClearanceProbe stores canonical column-major model poses: Y is vertical.
        # Local maxima are noisy and cannot establish contacts or step counts.
        y = [m[13] for m in matrices]
        result[side] = dict(samples=len(points), displacementRange=distance_range(points),
                            verticalRange=max(y)-min(y) if y else None)
    return result


def analyze(text, wheel, body, grip, scenes=None, mesh=None):
    scenes = SCENES if scenes is None else scenes
    assert scenes and len(set(scenes)) == len(scenes) and all(name in SCENES for name in scenes), 'Invalid scene selection'
    assert '[WOOD_BANK] RUN_STARTED' in text, 'Missing run boundary'
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[-1]
    assert '[WOOD_BANK] FAIL' not in log, 'Scenario failed'
    complete = re.findall(r'\[WOOD_BANK\] ALL_COMPLETE cases=(\d+)', log)
    assert complete == [str(len(scenes))], 'Missing/duplicate completion'
    clips = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+) file=.+? frames=(\d+) seconds=([\d.]+)', log)
    assert [r[0] for r in clips] == scenes, 'Missing/reordered/duplicate videos'
    samples = [_stationary.sample(line) for line in log.splitlines() if '[WOOD_BANK_SAMPLE]' in line]
    events = [event(line) for line in log.splitlines() if '[CART_PIVOT_EVENT]' in line]
    failures, summaries = [], []
    for name, start, frames, seconds in clips:
        start, seconds = int(start), float(seconds)
        assert 0 < int(frames) and 4 < seconds < 20, 'Invalid dynamic clip duration'
        starts = re.findall(r'\[WOOD_BANK\] CASE ' + re.escape(name) + r' attempt=0 wall=(\d+)', log)
        assert starts == [str(start)], 'Missing/duplicate recording start'
        ev = [r for r in events if r['case'] == name]
        assert [r['event'] for r in ev] == PHASES, 'Missing/reordered phase-complete proof'
        assert all(r['wall'] == start+r['elapsed'] for r in ev), 'Event clocks disagree'
        assert all(a['elapsed'] <= b['elapsed'] for a,b in zip(ev, ev[1:])), 'Event clocks regress'
        assert abs(seconds * 1000-ev[-1]['elapsed']) < 250, 'Video does not end with completed phases'
        phases = {r['event']:r for r in ev}
        rows = [r for r in samples if r['case'] == name]
        assert len(rows) >= 35 and all(abs(r['wall']-start-r['elapsed'])<=5 for r in rows), 'Missing samples/clock mismatch'
        gaps = [b['wall']-a['wall'] for a,b in zip(rows,rows[1:])]
        assert min(gaps)>0 and max(gaps)<=350 and rows[0]['elapsed']<200 and rows[-1]['elapsed']>ev[-1]['elapsed']-200, 'Incomplete sample coverage'
        left = name.endswith('-left')
        sign = -1 if left else 1
        pivot_drive, moving_drive = (2, 5) if left else (3, 8)
        assert [r['drive'] for r in ev] == [0,pivot_drive,pivot_drive,0,1,moving_drive,0,0], 'Wrong relative control sequence'
        def window(label, margin=0):
            begin = phases[label]['elapsed']+margin
            end = ev[PHASES.index(label)+1]['elapsed']
            return [r for r in rows if begin <= r['elapsed'] < end]
        # Samples printed before the input event in the same tick have unknown ordering.
        # Exclude only the exact start boundary; later missing input/engagement is a failure.
        pivot = [r for r in window('pivot') if r['elapsed'] > phases['pivot']['elapsed']]
        assert len(pivot)>=5, 'Missing pivot samples'
        yaw = sum(wrap(b['heading']-a['heading']) for a,b in zip(pivot,pivot[1:]))
        # Event includes the final update that crosses 180; independently integrate samples plus endpoints.
        angles = [phases['pivot']['heading']] + [r['heading'] for r in pivot] + [phases['pivot-complete']['heading']]
        yaw = sum(wrap(b-a) for a,b in zip(angles,angles[1:]))
        if not math.pi <= sign*phases['pivot-complete']['accumulated'] <= math.radians(195) or abs(yaw-phases['pivot-complete']['accumulated'])>.02:
            failures.append((name,'180-degree measured completion disagrees with samples'))
        if any(r['drive'] != pivot_drive for r in pivot) or not all(r['stationary'] for r in pivot):
            failures.append((name,'continuous stationary turn did not stay engaged'))
        anchors = [(r['x']+r['axle']*math.cos(r['heading']),r['y']+r['axle']*math.sin(r['heading'])) for r in pivot[2:]]
        axle = distance_range(anchors)
        if axle>.025: failures.append((name,'stationary axle drift',axle))
        w = [r for r in wheel if start+pivot[2]['elapsed'] <= float(r['wallTimeMillis']) <= start+pivot[-1]['elapsed']]
        assert len(w)>=5, 'Missing native wheel coverage'
        assert all(math.isfinite(float(r[k])) for r in w for k in ('wallTimeMillis','wheelX','wheelY','phase')), 'Nonfinite wheel measurement'
        wheel_times = sorted(set(float(r['wallTimeMillis']) for r in w))
        assert wheel_times[0]<=start+pivot[2]['elapsed']+250 and wheel_times[-1]>=start+pivot[-1]['elapsed']-250 and max(b-a for a,b in zip(wheel_times,wheel_times[1:]))<=500, 'Incomplete native wheel coverage'
        wheel_drift = distance_range([(float(r['wheelX']),float(r['wheelY'])) for r in w])
        roll = 0; max_roll = 0
        for a,b in zip(w,w[1:]):
            roll += wrap(float(b['phase'])-float(a['phase']))
            max_roll=max(max_roll,abs(roll)*.001062454*76.5*1.5)
        if wheel_drift>.05 or max_roll>.05: failures.append((name,'native wheel moves/rolls during pivot',wheel_drift,max_roll))
        quiet = window('released',800)
        assert len(quiet)>=3, 'Missing settled interval'
        heading_drift = max(abs(wrap(r['heading']-quiet[0]['heading'])) for r in quiet)
        root_drift = distance_range([(r['x'],r['y']) for r in quiet])
        if any(r['stationary'] for r in quiet) or heading_drift>math.radians(1) or root_drift>.01:
            failures.append((name,'release did not settle root/heading'))
        forward = window('forward-exit',200)
        moving = window('moving-entry',200)
        assert len(forward)>=3 and len(moving)>=3, 'Missing exit/control samples'
        forward_travel = math.dist((forward[0]['x'],forward[0]['y']),(forward[-1]['x'],forward[-1]['y']))
        moving_travel = math.dist((moving[0]['x'],moving[0]['y']),(moving[-1]['x'],moving[-1]['y']))
        moving_yaw = sum(wrap(b['heading']-a['heading']) for a,b in zip(moving,moving[1:]))
        if forward_travel<.05 or moving_travel<.03 or sign*moving_yaw<.02 or any(r['stationary'] for r in forward+moving):
            failures.append((name,'forward exit/moving turn entry failed'))
        selected = {}
        for label, records in [('body',body),('grip',grip)]:
            selected[label]=[r for r in records if start <= r['wallTimeMillis'] <= start+ev[-1]['elapsed']]
            stamps=sorted(set(r['wallTimeMillis'] for r in selected[label]))
            assert len(stamps)>=10 and stamps[0]<=start+300 and stamps[-1]>=start+ev[-1]['elapsed']-300 and max(b-a for a,b in zip(stamps,stamps[1:]))<=500, 'Incomplete '+label+' probes'
        assert all(r.get('female') is name.startswith('female-') for r in selected['body']), 'Body sex differs from scene'
        assert all(len(r['cart'])==16 and all(math.isfinite(v) for v in r['cart']) for r in selected['body']), 'Invalid cart matrix'
        def floor_error(r):
            c=r['cart']
            lowest=c[1]*(-6.642862e-6)+c[5]*(-.0041269097)+c[9]*(-.0010569958)+c[13]-.001062454*math.hypot(c[5],c[9])-.00024333253*abs(c[1])
            return abs(lowest-.008)
        wheel_floor=max(floor_error(r) for r in selected['body'])
        assert all(type(r['result']) is bool for r in selected['grip']), 'Invalid grip probe'
        grip_failures=sum(not r['result'] for r in selected['grip'])
        if grip_failures: failures.append((name,'native grip probe failed',grip_failures))
        quiet_body=[r for r in selected['body'] if start+phases['released']['elapsed']+800 <= r['wallTimeMillis'] < start+phases['forward-exit']['elapsed']]
        assert len(quiet_body)>=3, 'Missing settled foot probes'
        quiet_feet=foot_summary(quiet_body)
        if any(r['displacementRange']>.04 for r in quiet_feet.values()): failures.append((name,'feet do not settle after release'))
        pivot_body=[r for r in selected['body'] if start+phases['pivot']['elapsed'] <= r['wallTimeMillis'] < start+phases['pivot-complete']['elapsed']]
        tracks={}
        for row in pivot:
            for clip in row['clips']:
                if clip['weight']>.1:
                    tracks.setdefault(clip['name'],[]).append((row['elapsed'],clip['time'],clip['weight'],clip['speed']))
        cadence={}
        for clip, points in tracks.items():
            changes=[b[1]-a[1] for a,b in zip(points,points[1:])]
            cadence[clip]=dict(samples=len(points),timeMin=min(p[1] for p in points),timeMax=max(p[1] for p in points),
                 observedWraps=sum(d<-.001 for d in changes),progressingSamples=sum(d>.001 for d in changes),
                 weightRange=[min(p[2] for p in points),max(p[2] for p in points)],speedRange=[min(p[3] for p in points),max(p[3] for p in points)])
        if not any(r['progressingSamples']>=3 for clip,r in cadence.items() if 'strafe' in clip.lower() or 'pivot' in clip.lower()):
            failures.append((name,'actual native pivot/strafe clip phase does not progress'))
        meshes={}
        for kind,records in (mesh or {}).items():
            values=[r for r in records if start<=r['time']<=start+ev[-1]['elapsed']]
            assert values, 'Missing '+kind+' mesh frames'
            assert all(math.isfinite(r[k]) and r[k]>=0 for r in values for k in ('L','R')), 'Invalid mesh intersection measurement'
            meshes[kind]=dict(samples=len(values),intersections=sum(r['L']>0 or r['R']>0 for r in values))
        summaries.append(dict(case=name,recordSeconds=seconds,pivotSeconds=(phases['pivot-complete']['elapsed']-phases['pivot']['elapsed'])/1000,
            accumulatedYawDegrees=math.degrees(yaw),axleDriftTiles=axle,wheelDriftTiles=wheel_drift,wheelRollTiles=max_roll,
            releasedHeadingDriftDegrees=math.degrees(heading_drift),releasedRootDriftTiles=root_drift,settledFeet=quiet_feet,wheelFloorMaxError=wheel_floor,
            forwardExitTiles=forward_travel,movingEntryTiles=moving_travel,movingEntryYawDegrees=math.degrees(moving_yaw),
            nativeClipCadence=cadence,pivotFeet=foot_summary(pivot_body),gripSamples=len(selected['grip']),gripFailures=grip_failures,mesh=meshes))
    return dict(complete=True,caseCount=len(summaries),cases=summaries,failures=failures,motionPass=not failures,
        animationEquivalencePass=False,limit='macOS capture samples only; unresolved motion between samples is unknown. Native clip wraps are descriptive and do not prove planted contacts, six placements, weight transfer or naturalness. Inspect video, grip, body/pants mesh diagnostics and full-mod behavior separately. No universal visual PASS is inferred.')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile',type=Path,required=True)
    parser.add_argument('--log',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--scene',action='append')
    parser.add_argument('--mesh-analysis',type=Path)
    args=parser.parse_args()
    def rows(file): return [json.loads(line) for line in (args.profile/file).read_text().splitlines()]
    with (args.profile/'wood-wheel-native.csv').open() as stream:
        wheel=[r for r in csv.DictReader(stream) if r['event']=='grounding']
    mesh={} if args.mesh_analysis is None else {kind:json.loads((args.mesh_analysis/file).read_text()) for kind,file in [('body','hip-triangle-frames.json'),('pants','pants-triangle-frames.json')]}
    report=analyze(args.log.read_text(),wheel,rows('body-clearance.jsonl'),rows('wood-grip-poses.jsonl'),args.scene,mesh)
    with args.output.open('x') as stream: json.dump(report,stream,indent=2,allow_nan=False);stream.write('\n')
    print(json.dumps(report,indent=2,allow_nan=False))
    return 0 if report['motionPass'] else 1


if __name__=='__main__': raise SystemExit(main())
