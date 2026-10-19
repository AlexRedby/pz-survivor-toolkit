"""Negative controls for relative native obstacle motion and independent mesh gates."""
import copy
import csv
import importlib.util
import json
import math
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
HERE = ROOT/'tests/native_queue/contributions/wooden_cart_motion'
SCRIPT = HERE/'analyze-obstacle-matrix.py'
spec = importlib.util.spec_from_file_location('obstacle_matrix_test', SCRIPT)
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)


def lerp(t, points):
    for (t0, x0), (t1, x1) in zip(points, points[1:]):
        if t <= t1:
            return x0 + (x1-x0)*max(0, t-t0)/(t1-t0)
    return points[-1][1]


def emit(event, row):
    return a.PREFIX + event + ' ' + json.dumps(row, allow_nan=False)


def layout(spec, name=None):
    wx, gy, sy = 100, 100, 106
    h = 3*math.pi/4 if spec in ('slide-left', 'corner') else -3*math.pi/4 if spec == 'slide-right' else math.pi
    row = dict(wallX=wx,gapY=gy,southY=sy,minY=65,maxY=135,owned=87 if spec=='corner' else 71,
               doors=int(spec.startswith('door-')),startX=101.8 if spec=='door-open' else 103.8,
               startY=88.5 if spec=='slide-left' else 112.5 if spec=='slide-right' else 102.2 if spec=='corner' else 100.5,heading=h)
    row['case' if name else 'spec'] = name or spec
    return row


def door(spec):
    return emit('DOOR',dict(spec=spec,x=100,y=100,axis='W',open=spec=='door-open',blocked=spec!='door-open',blockedForward=spec!='door-open',blockedBackward=spec!='door-open',
                           sprite='fixtures_doors_01_2' if spec=='door-open' else 'fixtures_doors_01_0'))


def evidence(names=None):
    names = a.EXPECTED if names is None else names
    lines = ['[WOOD_BANK] RUN_STARTED']
    for i, spec in enumerate(a.SPECS):
        lo = layout(spec)
        if spec.startswith('door-'):
            lines.append(door(spec))
        lines.append(emit('CONTROL_LAYOUT', lo))
        start = 10000 + i*8000
        for t in range(100, 6100, 100):
            x = lerp(t, [(0,lo['startX']),(2500,100.3)]) if spec!='door-open' else lerp(t, [(0,101.8),(6000,96.5)])
            y = lerp(t, [(0,lo['startY']),(2500,105.7)]) if spec=='corner' else lo['startY']+(1 if spec=='slide-left' else -1 if spec=='slide-right' else 0)*t/2000
            lines.append(emit('CONTROL_SAMPLE',dict(spec=spec,wall=start+t,elapsed=t,x=x,y=y,heading=lo['heading'],bare=True,run=False,sprint=False,
                          drive=2 if spec in ('slide-left','corner') else 1 if spec=='slide-right' else 5,tracks='Bob_Walk=1@1;')))
        lines.append(emit('CONTROL_END',dict(spec=spec,wall=start+6000,elapsed=6000,x=x,y=y)))
    for index, name in enumerate(names):
        spec = a.spec_of(name)
        lo = layout(spec, name)
        start = 100000 + index*20000
        if spec.startswith('door-'):
            lines.append(door(spec))
        lines.extend([f'[WOOD_BANK] CASE {name} attempt=0 wall={start}',emit('LAYOUT',lo)])
        plan = a.planned(name)
        if spec=='door-open':
            plan[2] = (2600,0,0)
        reverse_at=plan[3][0]
        previous = lo['startX'],lo['startY']
        for t in range(0,16000,100):
            for at,g,d in plan:
                if t==at:
                    lines.append(emit('PHASE',dict(case=name,wall=start+t,elapsed=t,gait=g,drive=d,neutralMs=t-plan[2][0] if d==4 and reverse_at==4000 else 0)))
            _, gait, drive = [step for step in plan if step[0]<=t][-1]
            front=1.26 if name.split('-',3)[2]=='walk' else 1.62
            contact_heading=math.pi/2 if spec=='slide-left' else -math.pi/2 if spec=='slide-right' else lo['heading']
            support=a.native_support(dict(acceptedHeading=contact_heading,front=front),'west')
            contact_x=99 if spec=='door-open' else 100+support
            x = lerp(t, [(0,lo['startX']),(800,lo['startX']),(2600,contact_x),(reverse_at,contact_x),(13000,102.5 if spec=='door-open' else 103.8)])
            if spec.startswith('slide-') and t>=8000:
                x=contact_x
            if spec=='corner':
                y = lerp(t, [(0,lo['startY']),(800,lo['startY']),(2600,106-support),(8000,106-support),(13000,lo['startY'])])
            elif spec.startswith('slide-'):
                sign = 1 if spec=='slide-left' else -1
                y = lo['startY']+sign*lerp(t, [(0,0),(800,0),(6800,3),(8000,3),(13000,.5)])
            else:
                y=lo['startY']
            distance=math.dist(previous,(x,y));previous=x,y
            reverse=t>=reverse_at
            moving=distance>1e-7
            clip='Bob_WalkBwdNoAim1Hand' if reverse else ('Bob_Walk','Bob_Run','Bob_Sprint')[gait]
            h=lerp(t,[(0,lo['heading']),(800,lo['heading']),(2600,contact_heading)])
            contact=spec!='door-open' and 2600<=t<8000
            row=dict(case=name,wall=start+t,elapsed=t,frame=t//100,x=x,y=y,heading=h,acceptedHeading=h,drive=drive,gait=gait,
                     run=gait==1 and moving,sprint=gait==2 and moving,forward=drive==1,backward=drive==4,left=False,right=False,runKey=gait==1,sprintKey=gait==2,skill=10,id=42,cargoIDs='501' if '-full-' in name else 'empty',cargoWeight=25 if '-full-' in name else 0,
                     root=f'heading:{h},target:{h},stationary:false,stationaryRoot:false,actualDistance:{distance},axle:1,rootTracks:{clip}@1/{t/1000}/1;',
                     reversal=f'direction:{-1 if reverse else 1},requested:{-1 if drive==4 else 1 if drive==1 else 0}',
                     footprint=f'front={1.26 if gait==0 else 1.62} blocked={str(contact).lower()} recovering=false clear=true',
                     brace=f'brace={int(contact)} nativeBlocked={str(spec!="door-open").lower()} wantsMove={str(bool(drive)).lower()}')
            lines.append(emit('SAMPLE',row))
        lines.append(f'[WOOD_BANK] COMPLETE {name} wall={start} file=/tmp/{name}.mp4 frames=960 seconds=16')
    return '\n'.join(lines+[a.PREFIX+'CLEANUP_COMPLETE',f'[WOOD_BANK] ALL_COMPLETE cases={len(names)}'])


def change(log, case, callback):
    output=[]
    for line in log.splitlines():
        if a.PREFIX+'SAMPLE ' in line:
            row=json.loads(line.split('SAMPLE ',1)[1])
            if row['case']==case:
                row=callback(row)
                line=emit('SAMPLE',row) if row is not None else ''
        output.append(line)
    return '\n'.join(output)


class ObstacleMatrixTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.log=evidence()

    def reasons(self, log):
        return [reason for _,reason in a.analyze_motion(log)[3]]

    def test_complete_72_variant_bank_requires_six_independent_controls(self):
        starts,cases,controls,failures,_=a.analyze_motion(self.log)
        self.assertEqual((len(starts),len(cases),len(controls)),(72,72,6))
        self.assertEqual(failures,[])

    def test_missing_or_duplicate_completion_and_sparse_sampling_fail(self):
        complete=next(line for line in self.log.splitlines() if '[WOOD_BANK] COMPLETE ' in line)
        variants=(self.log.replace(complete,''),self.log+'\n'+complete,
                  change(self.log,a.EXPECTED[0],lambda row: None if 3000<row['elapsed']<3800 else row))
        for log in variants:
            with self.subTest(),self.assertRaises(AssertionError):
                a.analyze_motion(log)

    def test_native_control_cannot_be_held_cart_or_skip_contact(self):
        with self.assertRaisesRegex(AssertionError,'bare Walk'):
            a.analyze_motion(self.log.replace('"bare": true','"bare": false',1))
        lines=[]
        for line in self.log.splitlines():
            if a.PREFIX+'CONTROL_' in line and ' {' in line:
                kind,raw=line.split(a.PREFIX,1)[1].split(' ',1);row=json.loads(raw)
                if row['spec']=='frontal' and kind!='CONTROL_LAYOUT':
                    row['x']=103.8;line=emit(kind,row)
            lines.append(line)
        self.assertIn('bare actor never reaches native wall contact',self.reasons('\n'.join(lines)))

    def test_real_door_state_and_fresh_receipt_are_required(self):
        with self.assertRaisesRegex(AssertionError,'door state'):
            a.analyze_motion(self.log.replace('"open": true, "blocked": false','"open": false, "blocked": false',1))
        # Removing one selected scene's receipt cannot reuse a bare-control receipt.
        selected='male-empty-walk-door-open'
        lines=self.log.splitlines()
        at=lines.index(f'[WOOD_BANK] CASE {selected} attempt=0 wall=200000')
        self.assertTrue(lines[at-1].startswith(a.PREFIX+'DOOR '))
        del lines[at-1]
        bad='\n'.join(lines)
        with self.assertRaisesRegex(AssertionError,'current native door receipt'):
            a.analyze_motion(bad)

    def test_wrong_commands_identity_and_nonfinite_evidence_fail(self):
        name=a.EXPECTED[0]
        for modify in (lambda r:dict(r,drive=4) if r['elapsed']==3000 else r,
                       lambda r:dict(r,id=43) if r['elapsed']==3000 else r,
                       lambda r:dict(r,cargoIDs='other') if r['elapsed']==3000 else r):
            with self.assertRaises(AssertionError):
                a.analyze_motion(change(self.log,name,modify))
        bad=self.log.replace('"x": 103.8','"x": NaN',1)
        with self.assertRaises(AssertionError):
            a.analyze_motion(bad)

    def test_no_contact_no_reverse_and_fake_native_gait_fail(self):
        name='male-empty-run-frontal'
        no_clip=change(self.log,name,lambda r:dict(r,root=r['root'].replace('Bob_Run@','Bob_Idle@')))
        self.assertIn('requested native approach gait never progresses',self.reasons(no_clip))
        no_reverse=change(self.log,name,lambda r:dict(r,root=r['root'].replace('Bob_WalkBwdNoAim1Hand@','Bob_Idle@')))
        self.assertIn('manual native reverse gait never progresses',self.reasons(no_reverse))
        no_contact=change(self.log,name,lambda r:dict(r,footprint='front=1.26 blocked=false recovering=false clear=true',brace='brace=0 nativeBlocked=true wantsMove=true'))
        self.assertIn('cart never reaches measured obstacle contact',self.reasons(no_contact))

    def test_slide_requires_measured_tangent_and_reverse_requires_backoff(self):
        name='female-full-sprint-slide-left'
        no_slide=change(self.log,name,lambda r:dict(r,y=88.5))
        self.assertIn('cart never sustains tangential wall slide at contact',self.reasons(no_slide))
        frontal='female-full-sprint-frontal'
        stuck=change(self.log,frontal,lambda r:dict(r,x=101.64) if r['elapsed']>=8000 else r)
        self.assertIn('manual reverse does not back away from wall',self.reasons(stuck))
        auto=change(self.log,name,lambda r:dict(r,reversal='direction:-1,requested:1') if r['elapsed']==2000 else r)
        self.assertIn('automatic reverse occurs before manual reverse command',self.reasons(auto))

    def test_gait_flags_clip_and_contact_progress_must_coincide(self):
        name='male-empty-run-slide-left'
        def separate(row):
            if row['gait']==1 and row['elapsed']%200==0:
                row=dict(row,run=False)
            elif row['gait']==1:
                row=dict(row,root=row['root'].replace('Bob_Run@','Bob_Idle@'))
            return row
        self.assertIn('requested native approach gait never progresses',self.reasons(change(self.log,name,separate)))
        no_contact=change(self.log,name,lambda r:dict(r,run=False,root=r['root'].replace('Bob_Run@','Bob_Walk@')) if 3500<=r['elapsed']<6800 else r)
        self.assertIn('requested native gait is not sustained at wall-slide contact',self.reasons(no_contact))

    def test_backwards_clip_and_net_east_travel_cannot_hide_forward_motion(self):
        name='male-empty-walk-frontal'
        def turn_forward(row):
            if row['elapsed']>=8000:
                row=dict(row,heading=0,acceptedHeading=0,root=row['root'].replace(f'heading:{math.pi},target:{math.pi}', 'heading:0,target:0'))
            return row
        reasons=self.reasons(change(self.log,name,turn_forward))
        self.assertIn('manual backward input produces forward displacement',reasons)
        self.assertIn('manual reverse lacks measured signed backward travel',reasons)

    def test_fake_far_contact_and_mismatched_layout_fail(self):
        name='male-full-sprint-frontal'
        far=change(self.log,name,lambda r:dict(r,x=r['x']+1) if 4800<=r['elapsed']<6800 else r)
        self.assertIn('cart contact disagrees with current native envelope support',self.reasons(far))
        lines=self.log.splitlines()
        for i,line in enumerate(lines):
            if a.PREFIX+'LAYOUT ' in line and f'"case": "{name}"' in line:
                row=json.loads(line.split(' LAYOUT ',1)[1]);row['wallX']+=1;lines[i]=emit('LAYOUT',row)
        with self.assertRaisesRegex(AssertionError,'matching independent native control'):
            a.analyze_motion('\n'.join(lines))

    def test_bare_control_cannot_jump_or_cross_closed_boundaries(self):
        lines=self.log.splitlines()
        for i,line in enumerate(lines):
            if a.PREFIX+'CONTROL_SAMPLE ' in line:
                row=json.loads(line.split(' CONTROL_SAMPLE ',1)[1])
                if row['spec']=='corner' and row['elapsed']==3000:
                    row.update(x=99,y=107);lines[i]=emit('CONTROL_SAMPLE',row)
        reasons=self.reasons('\n'.join(lines))
        self.assertIn('bare native control position jumps between samples',reasons)
        self.assertIn('bare actor crosses closed native wall',reasons)
        self.assertIn('bare actor crosses native corner wall',reasons)

    def test_tangent_reverse_is_mobility_without_claiming_normal_escape(self):
        name='female-empty-run-slide-right'
        starts,cases,_,_,_=a.analyze_motion(self.log)
        held_x=next(r['x'] for r in cases[name]['rows'] if r['elapsed']==7900)
        log=change(self.log,name,lambda r:dict(r,x=held_x) if r['elapsed']>=8000 else r)
        _,_,_,failures,summaries=a.analyze_motion(log)
        self.assertEqual(failures,[])
        summary=next(row for row in summaries if row['case']==name)
        self.assertEqual(summary['reverseBackoff'],0)
        self.assertLess(summary['signedReverseTravel'],-.3)
        self.assertEqual(summary['reverseScope'],'tangent mobility at wall contact')

    def profile(self, directory, log, names):
        root=Path(directory)
        starts,cases,_,_,_=a.analyze_motion(log,names)
        with (root/'body-clearance.jsonl').open('w') as out, (root/'wood-wheel-native.csv').open('w') as native:
            writer=csv.DictWriter(native,fieldnames=('event','type','sequence','time','wallTimeMillis','dt','playerX','playerY','actorHeading'))
            writer.writeheader();sequence=0
            for name,case in cases.items():
                for row in case['rows']:
                    x,y=row['x'],row['y']
                    # Keep geometry fixture explicit: all wooden vertices and tire support are represented by bounds.
                    bounds=dict(minX=x-1.26,maxX=x+.2,minY=y-.35,maxY=y+.35)
                    if a.spec_of(name)=='corner':
                        bounds['maxY']=y+1.26
                    out.write(json.dumps(dict(wallTimeMillis=row['wall'],female=name.startswith('female-'),slotX=x,slotY=y,slotAngle=row['heading']+math.pi/2,bounds=bounds))+'\n')
                    sequence+=1
                    writer.writerow(dict(event='grounding',type='SaucedWheelbarrow.WheelbarrowWood',sequence=sequence,time=sequence/10,wallTimeMillis=row['wall'],dt=.1,playerX=x,playerY=y,actorHeading=row['heading']))
        return root

    def test_geometry_reports_separate_wheel_jamb_and_full_reverse_gates(self):
        names=['male-empty-walk-door-open']
        log=evidence(names)
        with tempfile.TemporaryDirectory() as directory:
            profile=self.profile(directory,log,names)
            with patch.object(a.footprint,'mesh',return_value=(None,'verified-test-mesh')),patch.object(a.footprint,'world_bounds',side_effect=lambda f,v:f['bounds']):
                result=a.analyze(log,profile,names)
                self.assertTrue(result['motionPass'],result['motionFailures'])
                self.assertTrue(result['footprintPass'],result['footprintFailures'])
                self.assertIsNone(result['visualPass'])
                file=profile/'body-clearance.jsonl'
                frames=[json.loads(line) for line in file.read_text().splitlines()]
                frame=next(f for f in frames if f['bounds']['minX']<100<f['bounds']['maxX'])
                frame['bounds']['maxY']=101.1
                file.write_text('\n'.join(json.dumps(f) for f in frames))
                result=a.analyze(log,profile,names)
                self.assertTrue(result['motionPass'])
                self.assertIn('wooden mesh or continuous wheel crosses an open-door jamb',[reason for _,reason in result['footprintFailures']])
                for frame in frames:
                    if frame['wallTimeMillis']>=114000:
                        frame['bounds']['minX']=100.05
                file.write_text('\n'.join(json.dumps(f) for f in frames))
                result=a.analyze(log,profile,names)
                self.assertIn('manual reverse never clears whole wooden mesh and continuous wheel',[reason for _,reason in result['footprintFailures']])

    def test_native_update_budget_remains_independent_from_lua_motion(self):
        names=[a.EXPECTED[0]];log=evidence(names)
        with tempfile.TemporaryDirectory() as directory:
            profile=self.profile(directory,log,names)
            file=profile/'wood-wheel-native.csv'
            lines=file.read_text().splitlines();row=lines[25].split(',');row[6]='1000';lines[25]=','.join(row);file.write_text('\n'.join(lines)+'\n')
            with patch.object(a.footprint,'mesh',return_value=(None,'verified-test-mesh')),patch.object(a.footprint,'world_bounds',side_effect=lambda f,v:f['bounds']):
                result=a.analyze(log,profile,names)
                self.assertFalse(result['motionPass'])
                self.assertIn('position jumps outside native update budget',[reason for _,reason in result['motionFailures']])

    def test_full_load_requires_positive_weight_and_nonempty_cargo_ids(self):
        name='male-full-walk-frontal'
        for modify in (lambda r:dict(r,cargoWeight=0),lambda r:dict(r,cargoIDs='empty')):
            with self.assertRaisesRegex(AssertionError,'load variant'):
                a.analyze_motion(change(self.log,name,modify))

    def test_release_cannot_automatically_reverse_before_manual_command(self):
        name='male-full-walk-frontal'
        def backward(row, native_flag):
            elapsed=row['elapsed']
            if elapsed>=6800:
                row=dict(row,x=row['x']+min(.5,(elapsed-6800)/4000))
            if native_flag and 6900<=elapsed<8000:
                row=dict(row,reversal='direction:-1,requested:0',root=row['root'].replace('actualDistance:0.0,','actualDistance:.01,'))
            return row
        for flag in (False,True):
            reasons=self.reasons(change(self.log,name,lambda r:backward(r,flag)))
            self.assertIn('automatic reverse occurs before manual reverse command',reasons)

    def test_one_native_clock_change_does_not_cover_a_frozen_approach(self):
        name='male-empty-run-slide-left'
        def frozen(row):
            if row['drive']!=1:
                return row
            time=1 if row['elapsed']<=1200 else 2
            prefix=row['root'].split(',rootTracks:',1)[0]
            return dict(row,root=prefix+f',rootTracks:Bob_Run@1/{time}/1;')
        self.assertIn('Matching native gait clock froze through more than 500ms of measured movement',self.reasons(change(self.log,name,frozen)))

    def test_fast_open_door_reverse_is_earlier_without_shortening_walk_or_other_cases(self):
        for name in a.EXPECTED:
            plan=a.planned(name)
            fast=a.spec_of(name)=='door-open' and '-walk-' not in name
            self.assertEqual(plan[3][0],4000 if fast else 8000)
        name='male-full-sprint-door-open'
        # The original five-second reverse schedule is deliberately no longer
        # accepted as coverage of a complete loaded fast return.
        lines=[]
        for line in self.log.splitlines():
            if a.PREFIX+'PHASE ' in line:
                row=json.loads(line.split(' PHASE ',1)[1])
                if row.get('case')==name and row['drive']==4:
                    row.update(elapsed=8000,wall=row['wall']+4000);line=emit('PHASE',row)
            lines.append(line)
        with self.assertRaisesRegex(AssertionError,'Late obstacle input phase'):
            a.analyze_motion('\n'.join(lines))

    def test_open_door_crossing_uses_neutral_boundary_pose_but_needs_real_plane_evidence(self):
        name='male-empty-run-door-open'
        # Reproduce the native100ms sample straddling an early release: the
        # last forward pose is east of the plane; the first neutral pose is west.
        def bracket(row):
            if row['elapsed']==2500:
                return dict(row,x=99.3)
            return row
        log=change(self.log,name,bracket)
        self.assertNotIn('open-door forward crossing never reaches release plane',self.reasons(log))
        missing=change(log,name,lambda r:dict(r,x=99.3) if r['elapsed']==2600 else r)
        self.assertIn('open-door forward crossing never reaches release plane',self.reasons(missing))
        delayed=change(log,name,lambda r:None if 2600<=r['elapsed']<=2800 else r)
        self.assertIn('open-door forward crossing never reaches release plane',self.reasons(delayed))

    def test_fast_door_reverse_requires_measured_quiet_window_and_live_receipt(self):
        name='female-full-sprint-door-open'
        # Native motion can persist despite identical rounded actor coordinates
        # and a fixture claiming a long quiet interval.
        moving=change(self.log,name,lambda r:dict(r,root=r['root'].replace('actualDistance:0.0,','actualDistance:.01,')) if 3200<=r['elapsed']<4000 else r)
        self.assertIn('fast open-door reverse lacks 500ms measured settled neutral pose',self.reasons(moving))
        lines=[]
        for line in self.log.splitlines():
            if a.PREFIX+'PHASE ' in line:
                row=json.loads(line.split(' PHASE ',1)[1])
                if row.get('case')==name and row['drive']==4:
                    row['neutralMs']=499;line=emit('PHASE',row)
            lines.append(line)
        self.assertIn('fast open-door reverse lacks 500ms measured settled neutral pose',self.reasons('\n'.join(lines)))
        drift=change(self.log,name,lambda r:dict(r,x=r['x']+.1*(r['elapsed']-3200)/800) if 3200<=r['elapsed']<4000 else r)
        self.assertIn('fast open-door reverse lacks 500ms measured settled neutral pose',self.reasons(drift))

    def test_fixture_lua_syntax_and_no_recording_actor_reset(self):
        compiler=shutil.which('luajit')
        if compiler:
            with tempfile.TemporaryDirectory() as directory:
                run=subprocess.run([compiler,'-b',str(HERE/'scenario-obstacle-matrix.lua'),str(Path(directory)/'fixture.luac')],capture_output=True,text=True)
                self.assertEqual(run.returncode,0,run.stderr)
        source=(HERE/'scenario-obstacle-matrix.lua').read_text()
        measured=source.split(' local elapsed=now-recordStart',1)[1].split('WoodPrototypeTick=function()',1)[0]
        for forbidden in ('p:setX','p:setY','cartLabPoseHeading','area.setObstacles','area.clearObstacles'):
            self.assertNotIn(forbidden,measured)
        self.assertIn("c.spec=='door-open' and stage==2 and p:getX()<=wx-1",measured)


if __name__=='__main__':
    unittest.main()
