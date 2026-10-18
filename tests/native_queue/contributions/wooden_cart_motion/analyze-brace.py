"""Independent blocked wooden-cart stance, guarded wall removal and restart proof."""
import argparse
import importlib.util
import json
import math
from pathlib import Path
import re
import numpy as np

_spec=importlib.util.spec_from_file_location('brace_footprint',Path(__file__).with_name('analyze-footprint.py'))
footprint=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(footprint)
collision=footprint.collision
fields,wrap=collision.fields,collision.wrap
EXPECTED={f'{sex}-{cargo}-{spec}' for sex in ('male','female') for cargo in ('empty','full') for spec in ('wall-release','wall-restart')}
DURATION=18000
FEET=tuple(f'Bip01_{side}_{part}' for side in ('L','R') for part in ('Foot','Toe0'))


def steps(name):
    return [(1000,0,5),(14000,0,0)] if name.endswith('wall-release') else [(1000,0,5),(6500,0,0),(7500,0,7),(10000,0,0),(10800,0,5),(15500,0,0)]


def finite(raw,keys):
    row={k:float(raw[k]) for k in keys}
    assert all(math.isfinite(v) for v in row.values()),'Nonfinite brace measurement'
    return row


def boolean(raw,key):
    assert raw[key] in ('true','false'),'Invalid brace boolean: '+key
    return raw[key]=='true'


def observation(raw):
    row=finite(raw,('wall','elapsed','brace'))
    assert 0<=row['brace']<=1,'Brace blend outside unit interval'
    row.update(nativeBlocked=boolean(raw,'nativeBlocked'),wantsMove=boolean(raw,'wantsMove'))
    return row


def parse(text):
    assert '[WOOD_BANK] RUN_STARTED' in text,'Missing brace run boundary'
    log=text.rsplit('[WOOD_BANK] RUN_STARTED',1)[1]
    assert '[WOOD_BANK] FAIL' not in log,'Brace fixture reported failure'
    starts,ends,cases,layouts={},{},{},{};active=None
    for line in log.splitlines():
        if '[CART_COLLISION_LAYOUT] ' in line:
            raw=fields(line.split('[CART_COLLISION_LAYOUT] ',1)[1]);name=raw.pop('case')
            assert name in EXPECTED and name not in layouts,'Unexpected/duplicate brace layout'
            layouts[name]=finite(raw,('wallX','southY','gapY','startX','startY','baselineX','baselineY'))
            layouts[name]['ownedWalls']=int(raw.get('ownedWalls','49'))
            assert layouts[name]['ownedWalls'] in (3,49) and (name.endswith('wall-release') or layouts[name]['ownedWalls']==49),'Invalid declared brace wall count'
        match=re.search(r'\[WOOD_BANK\] CASE (\S+) attempt=(\d+) wall=(\d+)',line)
        if match:
            name=match[1];assert name in layouts and name not in starts and active is None,'Unexpected/duplicate brace scene'
            starts[name]=int(match[3]);cases[name]=dict(rows=[],states=[],brace=[],events=[],removals=[],terminal={k:[] for k in ('rows','states','brace')},layout=layouts[name]);active=name
        match=re.search(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)',line)
        if match:
            name=match[1];assert name==active and int(match[2])==starts[name],'Brace completion disagrees with start'
            ends[name]=int(match[2]);active=None
        for prefix,key in (('[WOOD_BANK_SAMPLE] ','rows'),('[CART_FOOTPRINT_STATE] ','states'),('[CART_BRACE_SAMPLE] ','brace'),('[WOOD_RAMP_EVENT] ','events'),('[CART_BRACE_REMOVE] ','removals')):
            if prefix not in line:continue
            raw=fields(line.split(prefix,1)[1]);name=raw['case'];assert name==active and active is not None,'Brace measurement outside scene'
            if key=='rows':row=collision.sample(line)
            elif key=='states':
                row=finite(raw,('wall','elapsed','front'));assert row['front']==1.26,'Brace requires Walk envelope'
                row.update(blocked=boolean(raw,'blocked'),clear=boolean(raw,'clear'),recovering=boolean(raw,'recovering'))
            elif key=='events':row=finite(raw,('elapsed','gait','drive'))
            else:
                row=observation(raw)
                if key=='removals':row.update(phase=raw['phase'],**finite(raw,('owned','drive')))
            if key in ('rows','states','brace'):
                assert 0<=row['elapsed']<=DURATION+500 and abs(row['wall']-starts[name]-row['elapsed'])<=5,'Brace sample clocks disagree'
                if row['elapsed']>=DURATION:
                    cases[name]['terminal'][key].append(row);continue
            cases[name][key].append(row)
    complete=re.findall(r'\[WOOD_BANK\] ALL_COMPLETE cases=(\d+)',log)
    assert len(complete)==1 and int(complete[0])==len(starts) and starts and starts.keys()==ends.keys() and active is None,'Incomplete brace run'
    assert set(layouts)==set(starts) and '[CART_COLLISION] CLEANUP_COMPLETE' in log,'Missing brace layout/cleanup'
    for case in cases.values():
        terminal=case['terminal']
        assert [(r['wall'],r['elapsed']) for r in terminal['rows']]==[(r['wall'],r['elapsed']) for r in terminal['states']]==[(r['wall'],r['elapsed']) for r in terminal['brace']],'Misaligned terminal brace diagnostics'
    return log,starts,cases


def foot_positions(frame):
    values={}
    for name in FEET:
        matrix=np.asarray(frame['bones'][name],dtype=float)
        assert matrix.shape==(16,) and np.isfinite(matrix).all() and np.allclose(matrix[[3,7,11,15]],[0,0,0,1],atol=1e-5),'Invalid rendered foot matrix'
        values[name]=matrix[12:15].tolist()
    return values


def cadence_ramp(rows,before,clear):
    pre=[r for r in rows if before-500<=r['wall']<=before]
    early=[r for r in rows if clear<=r['wall']<=clear+650]
    steady=[r['rampSpeed'] for r in rows if clear+1800<=r['wall']<clear+3000]
    assert len(pre)>=3 and len(early)>=4 and steady,'Missing removal cadence samples'
    assert early[0]['wall']-clear<=100 and early[-1]['wall']-clear>=500 and all(b['wall']-aa['wall']<=200 for aa,b in zip(early,early[1:])),'Incomplete early removal cadence window'
    speed=float(np.median(steady));assert speed>0,'Missing steady Walk cadence after removal'
    ratios=[r['rampSpeed']/speed for r in early]
    fall=sum(max(0,aa-b) for aa,b in zip(ratios,ratios[1:]))
    bounded=all(b-aa<=.25+4*(rb['wall']-ra['wall'])/1000 for aa,b,ra,rb in zip(ratios,ratios[1:],early,early[1:]))
    valid=(max(r['rampSpeed'] for r in pre)<=.05*speed and max(r['pace'] for r in pre)<=.02
           and ratios[0]<=.5 and any(.05<r<.9 for r in ratios) and max(ratios)<=1.1
           and ratios[-1]>ratios[0]+.1 and fall<=.05 and bounded)
    return valid,dict(steadyWalkSpeed=speed,preclearMaximumSpeed=max(r['rampSpeed'] for r in pre),
        normalizedEarlySpeeds=ratios,earlyElapsedMs=[r['wall']-clear for r in early],normalizedBacktracking=fall,boundedRise=bounded)


def analyze(text,profile,selected=None):
    log,starts,cases=parse(text);native,failures=collision.controls(log,wall_offset=3)
    full_count=len(starts)
    if selected is not None:
        assert selected and len(set(selected))==len(selected) and set(selected)<=starts.keys(),'Invalid explicit brace scene selection'
        starts={n:t for n,t in starts.items() if n in selected};cases={n:c for n,c in cases.items() if n in selected}
    assert max(c['end']['wall'] for c in native.values())<min(starts.values()),'Brace controls must precede scenes'
    vertices,sha=footprint.mesh(profile)
    updates,budget_failures=footprint.native_updates(profile,starts,{n:DURATION for n in starts});failures.extend(budget_failures)
    windows=sorted((start,name) for name,start in starts.items())
    assert all(b-a>=DURATION for (a,_),(b,_) in zip(windows,windows[1:])),'Overlapping brace scenes'
    measured={n:[] for n in starts}
    with (profile/'body-clearance.jsonl').open() as source:
        for line in source:
            frame=json.loads(line);at=frame['wallTimeMillis'];assert type(at) in (int,float) and math.isfinite(at),'Invalid brace render time'
            for start,name in windows:
                if start<=at<start+DURATION:
                    assert type(frame['female']) is bool and frame['female']==name.startswith('female-'),'Wrong brace render sex'
                    measured[name].append(dict(wall=at,elapsed=at-start,**footprint.world_bounds(frame,vertices),slotX=frame['slotX'],slotY=frame['slotY'],slotAngle=frame['slotAngle'],feet=foot_positions(frame)));break
    geometry_failures=[];summaries=[]
    def fail(name,reason,geometry=False):
        target=geometry_failures if geometry else failures
        if (name,reason) not in target:target.append((name,reason))
    for name,start in starts.items():
        case=cases[name];rows,states,brace,events,removals,layout=(case[k] for k in ('rows','states','brace','events','removals','layout'));frames=measured[name]
        for stream,label in ((rows,'motion'),(states,'footprint'),(brace,'brace'),(frames,'render')):collision.coverage(stream,start,DURATION,'brace '+label+' '+name,100)
        assert [(r['wall'],r['elapsed']) for r in rows]==[(r['wall'],r['elapsed']) for r in states]==[(r['wall'],r['elapsed']) for r in brace],'Misaligned brace diagnostics'
        assert all(layout[k]==native['wall']['start'][k] for k in ('wallX','southY','gapY')),'Brace geometry disagrees with bare controls'
        assert abs(layout['startX']-layout['wallX']-1.8)<.002 and abs(layout['startY']-native['wall']['start']['y'])<.002,'Wrong brace initial position'
        initial=[r for r in rows if r['elapsed']<1000]
        assert initial[0]['elapsed']<=200 and initial[-1]['elapsed']>=800 and initial[-1]['elapsed']-initial[0]['elapsed']>=800,'Missing brace pre-input window'
        if collision.spread(initial)>.025 or collision.angle_drift(initial,'heading')>math.radians(1.5):fail(name,'brace moves before input')
        assert abs(wrap(rows[0]['heading']-math.pi))<.05,'Wrong brace approach heading'
        planned=steps(name)
        assert len(events)==len(planned) and all(abs(r['elapsed']-t)<=500 and r['gait']==g and r['drive']==d for r,(t,g,d) in zip(events,planned)),'Wrong brace input stages'
        for aa,b in zip([dict(elapsed=0,gait=0,drive=0),*events],[*events,dict(elapsed=DURATION,gait=0,drive=0)]):
            stage=[r for r in rows if aa['elapsed']+150<=r['elapsed']<b['elapsed']-150]
            assert stage and all(r['requestedGait']==0 and r['drive']==aa['drive'] for r in stage),'Brace input/sample disagreement'
        assert all(not r['run'] and not r['sprint'] for r in rows),'Brace requires native Walk'
        times=[r['wall'] for r in rows]
        for frame in frames:
            assert footprint.slot_matches(frame,rows,times),'Brace rendered cart disagrees with actor'
        removal=None
        if name.endswith('wall-release'):
            assert len(removals)==2 and [r['phase'] for r in removals]==['before','after'],'Missing guarded brace removal receipts'
            before,after=removals;assert 8000<=before['elapsed']<=8500 and 0<=after['wall']-before['wall']<=1000,'Invalid native wall removal timing'
            assert all(abs(r['wall']-start-r['elapsed'])<=5 and r['drive']==5 and r['wantsMove'] for r in removals),'Removal changed held forward input'
            assert before['owned']==layout['ownedWalls'] and after['owned']==0 and before['nativeBlocked'] and not after['nativeBlocked'],'Removal lacks actual owned native wall transition'
            removal=before['wall']
        else:assert not removals,'Restart must retain standing wall'
        for frame in frames:
            if (removal is None or frame['wall']<removal) and frame['minX']<layout['wallX']-.005:fail(name,'rendered mesh or continuous wheel enters standing wall',True)
            if layout['ownedWalls']==3 and frame['wall']<removal and not (layout['gapY']-1<=frame['minY'] and frame['maxY']<=layout['gapY']+2):fail(name,'rendered cart leaves finite brace wall span',True)
        for row in brace:
            expected=True if removal is None or row['wall']<removal else False
            if removal is None or row['wall']<removal or row['wall']>removals[-1]['wall']:
                assert row['nativeBlocked']==expected,'Native wall oracle disagrees with guarded removal'
        baseline=[f for f in frames if 200<=f['elapsed']<900];assert len(baseline)>=3,'Missing rendered planted baseline'
        standing={bone:np.median([f['feet'][bone] for f in baseline],axis=0) for bone in FEET}
        contacts=[(5000,7500)] if removal else [(5000,6300),(14500,15300)]
        contact_summary=[]
        for begin,end in contacts:
            quiet=[r for r in rows if begin<=r['elapsed']<end];diagnostics=[r for r in brace if begin<=r['elapsed']<end];blocked=[r for r in states if begin<=r['elapsed']<end];pose=[f for f in frames if begin<=f['elapsed']<end]
            assert quiet and quiet[-1]['elapsed']-quiet[0]['elapsed']>=end-begin-500 and len(pose)>=5,'Incomplete blocked stance window'
            if collision.spread(quiet)>.015 or collision.angle_drift(quiet,'heading')>math.radians(1) or collision.wheel_roll_error(quiet)>.01:fail(name,'blocked brace stance moves root heading or wheel')
            if not all(r['nativeBlocked'] and r['wantsMove'] and r['brace']>=.95 for r in diagnostics):fail(name,'blocked contact lacks sustained planted brace')
            if min(f['minX']-layout['wallX'] for f in pose)>.65:fail(name,'brace never approaches rendered wall contact')
            raised=max(f['feet'][bone][1]-standing[bone][1] for f in pose for bone in FEET)
            offset=max(abs(f['feet'][bone][1]-standing[bone][1]) for f in pose for bone in FEET)
            jitter=max(float(np.linalg.norm(np.ptp([f['feet'][bone] for f in pose],axis=0))) for bone in FEET)
            horizontal=max(float(np.linalg.norm((np.asarray(f['feet'][bone])-standing[bone])[[0,2]])) for f in pose for bone in FEET)
            if offset>.025 or jitter>.012:fail(name,'rendered blocked feet remain raised or move instead of planting')
            contact_summary.append(dict(begin=begin,end=end,footRaiseAboveStanding=raised,footOffsetFromStanding=offset,footPositionRangeXYZ=jitter,horizontalStanceOffset=horizontal,rootSpread=collision.spread(quiet),footprintSamples=len(blocked),footprintBlockedSamples=sum(r['blocked'] for r in blocked),footprintClearSamples=sum(r['clear'] for r in blocked)))
        ramp=None
        if removal:
            smooth,ramp=cadence_ramp(rows,removals[0]['wall'],removals[-1]['wall'])
            if not smooth:fail(name,'held forward cadence jumps or fails to ramp after wall removal')
            resumed=[r for r in rows if removals[-1]['elapsed']+500<=r['elapsed']<14000]
            if not resumed or resumed[0]['x']-resumed[-1]['x']<.5 or min(r['x'] for r in resumed)>layout['wallX']-.2 or not footprint.progressing(resumed,{'Bob_Walk'}):fail(name,'held forward does not resume smoothly after wall removal')
            late=[r for r in resumed if r['elapsed']>=13400]
            if len(late)<2 or late[0]['x']-late[-1]['x']<.05 or sum(max(0,b['x']-aa['x']) for aa,b in zip(resumed,resumed[1:]))>.025 or collision.angle_drift(resumed,'heading')>math.radians(1):fail(name,'resumed forward motion freezes reverses or turns after wall removal')
            if not any(r['brace']<.05 for r in brace if 9000<=r['elapsed']<10000):fail(name,'brace remains latched after obstacle removal')
        else:
            reverse=[r for r in rows if 7800<=r['elapsed']<10000]
            if reverse[-1]['x']-reverse[0]['x']<.3 or not any(r['direction']<0 and r['actualDistance']>1e-6 for r in reverse) or not footprint.progressing(reverse,{'Bob_WalkBwdNoAim1Hand'}):fail(name,'reverse does not leave blocked stance')
            forward=[r for r in rows if 11100<=r['elapsed']<14500]
            if forward[0]['x']-forward[-1]['x']<.3 or not footprint.progressing(forward,{'Bob_Walk'}):fail(name,'forward restart does not return to wall contact')
        quiet=[r for r in rows if 17300<=r['elapsed']<DURATION]
        if collision.spread(quiet)>.015 or collision.angle_drift(quiet,'heading')>math.radians(1) or collision.wheel_roll_error(quiet)>.01 or any(r['brace']>.05 or r['wantsMove'] for r in brace if 17300<=r['elapsed']<DURATION):fail(name,'final brace release does not settle')
        summaries.append(dict(case=name,durationMs=DURATION,samples=len(rows),frames=len(frames),nativeUpdates=len(updates[name]),terminalSamples=len(case['terminal']['rows']),standingFootPositions={n:v.tolist() for n,v in standing.items()},contact=contact_summary,removalCadence=ramp,minimumStandingWallGap=min(f['minX']-layout['wallX'] for f in frames if removal is None or f['wall']<removal)))
    return dict(complete=True,caseCount=len(starts),fullSceneCount=full_count,scope='full-matrix' if selected is None else 'selected-scenes',selectedScenes=sorted(starts),controlCount=len(native),motionPass=not failures,footprintPass=not geometry_failures,motionFailures=failures,footprintFailures=geometry_failures,meshSha256=sha,cases=summaries,limit='Sampled real wooden mesh plus continuous wheel support against standing native wall; foot/toe vertical offset and blocked-window XYZ jitter are gated. Static horizontal stance changes are reported for review. Between-frame geometry, grip/body/clothing, runtime and manual video quality remain separate gates.')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--profile',type=Path,required=True);p.add_argument('--log',type=Path);p.add_argument('--output',type=Path,required=True);p.add_argument('--scene',action='append');args=p.parse_args()
    assert args.profile.is_dir() and not args.output.exists(),'Missing brace profile or existing immutable report'
    result=analyze((args.log or args.profile/'console.txt').read_text(),args.profile,args.scene)
    args.output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k!='cases'},indent=2));raise SystemExit(0 if result['motionPass'] and result['footprintPass'] else 1)


if __name__=='__main__':main()
