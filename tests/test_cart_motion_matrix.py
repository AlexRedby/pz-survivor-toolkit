"""Relative movement contracts reject plausible-looking input/animation-only evidence."""
import importlib.util
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT=Path(__file__).parent/'native_queue/contributions/wooden_cart_motion/analyze-motion-matrix.py'
spec=importlib.util.spec_from_file_location('cart_motion_matrix',SCRIPT)
analyzer=importlib.util.module_from_spec(spec)
spec.loader.exec_module(analyzer)
SMALL=('male-empty-walk-arcs','female-full-run-slalom-up','female-full-sprint-slalom-down')

def evidence(names=SMALL,inertia=False):
    lines=['[WOOD_BANK] RUN_STARTED']
    def emit(kind,row):
        lines.append('[CART_MATRIX] '+kind+' '+json.dumps(row,separators=(',',':')))
    for number,name in enumerate(names):
        _,load,gait,scenario=name.split('-',3)
        start=100000+number*150000
        now=start
        x=y=100.
        heading=math.pi/4 if scenario=='slalom-down' else -3*math.pi/4
        frame=1
        turn_rate=0.
        lines.append(f'[WOOD_BANK] CASE {name} attempt=0 wall={start}')
        for index,phase in enumerate(analyzer.schedule(name),1):
            begin=now
            target=phase['target']
            duration=math.ceil(abs(target)/.8*1000/100)*100 if target else phase['duration']
            if phase['phase']=='tail':
                duration=start+analyzer.DURATIONS[scenario]-now
            meta=dict(case=name,index=index,wall=now,**phase)
            if phase['phase']=='tail':
                meta.update(duration=duration,deadline=duration+500)
            emit('PHASE',meta)
            lines.append(f"[WOOD_RAMP_EVENT] case={name} elapsed={now-start} gait={phase['gait']} drive={phase['drive']}")
            elapsed=0
            previous_yaw=0
            while True:
                if inertia and phase['phase'].startswith('slalom'):
                    yaw=previous_yaw
                    requested_rate=(-1 if phase['drive']==5 else 1)*(1.6-.3*(load=='full'))
                    if elapsed:
                        # Native integration, independent of the analyzer's residual-yaw bound.
                        for _ in range(10):
                            turn_rate+=max(-.06,min(.06,requested_rate-turn_rate))
                            yaw+=turn_rate*.01
                else:
                    turn_rate=0.
                    yaw=target*elapsed/duration if target else ((-.8 if phase['drive']==5 else .8)*elapsed/1000 if phase['phase'].startswith('slalom') else 0)
                delta=yaw-previous_yaw
                if elapsed:
                    if phase['drive']:
                        speed=(1.1,3.,4.5)[phase['gait']]
                        dt=min(100,elapsed)/1000
                        x+=speed*dt*math.cos(heading+delta/2)
                        y+=speed*dt*math.sin(heading+delta/2)
                    heading=analyzer.wrap(heading+delta)
                    frame+=1
                requested=phase['gait']
                drive=phase['drive']
                clip=('Bob_Walk','Bob_Run','Bob_Sprint')[requested] if drive else 'Bob_Idle'
                row=dict(case=name,index=index,phase=phase['phase'],wall=now,elapsed=now-start,phaseElapsed=elapsed,
                         frame=frame,x=x,y=y,heading=heading,acceptedHeading=heading,yaw=yaw,
                         drive=drive,gait=requested,run=requested==1,sprint=requested==2,skill=10,
                         stepX=0,stepY=1 if drive else 0,
                         forward=drive in (1,5,8),backward=False,left=drive==5,right=drive==8,
                         runKey=requested==1,sprintKey=requested==2,
                         root=f'heading:{heading},rootTracks:{clip}@1/{now/1000%1}/1;',
                         id=number+1,cargoIDs='123' if load=='full' else 'empty',cargoWeight=30 if load=='full' else 0)
                emit('SAMPLE',row)
                previous_yaw=yaw
                if elapsed==duration:
                    break
                interval=min(100,duration-elapsed)
                now+=interval
                elapsed+=interval
            emit('END',dict(case=name,index=index,phase=phase['phase'],wall=now,elapsed=duration,yaw=previous_yaw))
        lines.append(f'[WOOD_BANK] COMPLETE {name} wall={start} file=test.mp4 frames=100 seconds={analyzer.DURATIONS[scenario]/1000}')
    lines.append(f'[WOOD_BANK] ALL_COMPLETE cases={len(names)}')
    return '\n'.join(lines)

def transform(log,kind,predicate,change):
    result=[]
    prefix='[CART_MATRIX] '+kind+' '
    for line in log.splitlines():
        if line.startswith(prefix):
            row=json.loads(line[len(prefix):])
            if predicate(row):
                row=change(row)
                if row is None:
                    continue
                line=prefix+json.dumps(row,separators=(',',':'))
        result.append(line)
    return '\n'.join(result)

def update(row,**values):
    return dict(row,**values)

def collapse_phase_motion(log,case,phase):
    prefix='[CART_MATRIX] SAMPLE '
    rows=[json.loads(line[len(prefix):]) for line in log.splitlines() if line.startswith(prefix)]
    chosen=[r for r in rows if r['case']==case and r['phase']==phase]
    first,last=chosen[0],chosen[-1]
    dx,dy=first['x']-last['x'],first['y']-last['y']
    def change(row):
        if row['case']!=case:
            return row
        if row['phase']==phase:
            return update(row,x=first['x'],y=first['y'])
        if row['index']>first['index']:
            return update(row,x=row['x']+dx,y=row['y']+dy)
        return row
    return transform(log,'SAMPLE',lambda r:True,change)

class MotionMatrixTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.log=evidence()

    def analyze(self,log=None):
        return analyzer.analyze(self.log if log is None else log,SMALL)

    def reject(self,log):
        try:
            result=self.analyze(log)
        except (AssertionError,ValueError,KeyError,TypeError):
            return
        self.assertFalse(result['motionPass'],result)

    def test_canonical_gaits_preserve_native_clocks_and_reject_unknown_or_wrong_gait(self):
        log = self.log.replace('Bob_Walk@', 'Toolkit_CartPivot_Walk@').replace('Bob_Run@', 'Toolkit_CartPivot_Run@').replace('Bob_Sprint@', 'Toolkit_CartPivot_Sprint@')
        self.assertTrue(self.analyze(log)['motionPass'])
        self.assertIn('Toolkit_CartPivot_Run', analyzer.tracks('state,rootTracks:Toolkit_CartPivot_Run@1/.2/1;'))
        for wrong in ('Toolkit_CartPivot_Rnu', 'Toolkit_CartPivot_Walk', 'Toolkit_CartPivot_StopRun'):
            self.reject(log.replace('Toolkit_CartPivot_Run@', wrong + '@'))

    def test_complete_matrix_and_exact_angles(self):
        result=analyzer.analyze(evidence(analyzer.SCENES))
        self.assertTrue(result['motionPass'],result['motionFailures'])
        self.assertEqual(result['caseCount'],36)
        self.assertTrue(result['matrixComplete'])
        arcs=result['cases'][0]['phases']
        turns=[r['signedYaw'] for r in arcs if r['phase'].startswith('arc-')]
        for measured,wanted in zip(turns,(-45,-90,-135,-180,45,90,135,180)):
            self.assertAlmostEqual(math.degrees(measured),wanted)
        self.assertNotIn('visualPass',result)
        self.assertNotIn('footprintPass',result)

    def test_direct_opposite_slaloms_allow_braking_but_report_unmet_rapid_response(self):
        result=self.analyze(evidence(inertia=True))
        self.assertTrue(result['motionPass'],result['motionFailures'])
        self.assertFalse(result['rapidResponsePass'])
        self.assertTrue(result['rapidResponseLimitations'])
        for case in result['cases']:
            for phase in case['phases']:
                if not phase['phase'].startswith('slalom-'):
                    continue
                self.assertIn('sampledOppositeExcursion',phase)
                if phase['phase'].startswith(('slalom-600-','slalom-900-')):
                    self.assertTrue(phase['requestedDirectionAchieved'],phase)
        unmet=[p for c in result['cases'] for p in c['phases']
               if p.get('directOppositeInput') and p.get('netRequestedYaw',1)<0]
        self.assertTrue(unmet)
        self.assertTrue(all(not p['requestedDirectionAchieved'] for p in unmet))

    def test_slalom_braking_bounds_reject_persistent_wrong_yaw_and_excess_excursion(self):
        def rows(rate,stop=900):
            return [dict(phaseElapsed=t,acceptedHeading=rate*t/1000) for t in range(0,stop+1,100)]
        for load in ('empty','full'):
            for rate in (-.8,-1.6):
                response,failures=analyzer.slalom_response(rows(rate),load,1,True)
                self.assertFalse(response['requestedDirectionAchieved'])
                self.assertIn('Long slalom hold did not settle in the requested direction',failures)
                self.assertTrue(any('bounded braking' in f for f in failures))
        # Even a 300ms rapid hold cannot disguise an unbraked capped old rate.
        response,failures=analyzer.slalom_response(rows(-1.6,300),'empty',1,True)
        self.assertTrue(any('bounded braking' in f for f in failures))
        # Positive eventual net yaw cannot excuse a large first old-direction jump.
        jump=[dict(phaseElapsed=t,acceptedHeading=h) for t,h in ((0,0),(100,-.3),(200,-.2),(300,0),(400,.2),(500,.4),(600,.6))]
        response,failures=analyzer.slalom_response(jump,'empty',1,True)
        self.assertTrue(response['requestedDirectionAchieved'])
        self.assertTrue(any('bounded braking' in f for f in failures))

    def test_sampled_slalom_crossing_is_bracketed_and_requires_settled_observations(self):
        rows=[dict(phaseElapsed=t,acceptedHeading=h) for t,h in
              ((0,0),(100,-.12),(200,-.18),(300,-.17),(400,-.09),(500,.05),(600,.21))]
        response,failures=analyzer.slalom_response(rows,'empty',1,True)
        self.assertEqual(failures,[])
        self.assertEqual(response['responseCrossingBracketMs'],[100,300])
        self.assertGreater(response['terminalSignedRate'],0)
        self.assertAlmostEqual(response['oldYawDeadlineMs'],100+1600/6)
        sparse=[dict(phaseElapsed=t,acceptedHeading=h) for t,h in ((0,0),(300,-.1),(600,.3))]
        self.assertIn('Insufficient samples after slalom braking deadline',analyzer.slalom_response(sparse,'empty',1,True)[1])
        recross=rows+[dict(phaseElapsed=700,acceptedHeading=.15)]
        self.assertIn('Slalom returned to the old direction after sampled response',analyzer.slalom_response(recross,'empty',1,True)[1])

    def test_native_clock_cannot_advance_once_then_freeze_while_actor_moves(self):
        def freeze(row):
            if not row['drive']:
                return row
            boundary=1000 if row['phase']=='straight' else 200
            time=1 if row['phaseElapsed']<=boundary else 2
            clip=('Bob_Walk','Bob_Run','Bob_Sprint')[row['gait']]
            return update(row,root=f'heading:{row["heading"]},rootTracks:{clip}@1/{time}/1;')
        result=self.analyze(transform(self.log,'SAMPLE',lambda r:True,freeze))
        self.assertFalse(result['motionPass'])
        self.assertTrue(any('clock froze' in f['reason'] for f in result['motionFailures']))

    def test_clock_freeze_budget_survives_consecutive_short_phase_edges(self):
        state={};values=[]
        # A 700ms freeze spans multiple 300ms steering phases. Same-tick
        # phase-edge copies must not erase the accumulated moving time.
        for time in range(0,701,100):
            row=dict(wall=time,x=time/100000,y=0)
            values.append(analyzer.moving_clock_stall(state,row,'Bob_Walk',[.25]))
            if time in (300,600):
                values.append(analyzer.moving_clock_stall(state,row,'Bob_Walk',[.25]))
        self.assertGreater(max(values),500)
        self.assertEqual(values[-1],700)

    def test_clock_progress_accepts_loop_wrap_and_slow_loaded_advance(self):
        state={}
        for i,time in enumerate((.99998,.00001,.00002,.00003,.00004,.00005,.00006,.00007)):
            row=dict(wall=i*100,x=i/1000,y=0)
            self.assertEqual(analyzer.moving_clock_stall(state,row,'Bob_Walk',[time]),0)
        # A real nonmoving/gait-transition gap resets the moving-time budget.
        row=dict(wall=800,x=.007,y=0)
        self.assertEqual(analyzer.moving_clock_stall(state,row,'Bob_Walk',[.00007]),0)
        self.assertEqual(analyzer.moving_clock_stall(state,dict(wall=900,x=.008,y=0),'Bob_Run',[]),0)

    def test_selected_diagnostic_scope(self):
        result=self.analyze()
        self.assertTrue(result['motionPass'],result['motionFailures'])
        self.assertFalse(result['matrixComplete'])
        self.assertEqual(result['scope'],'selected-scenes')

    def test_missing_duplicate_reordered_case_boundaries(self):
        for bad in (self.log.replace('[WOOD_BANK] RUN_STARTED',''),self.log.replace('ALL_COMPLETE cases=3','ALL_COMPLETE cases=2'),
                    self.log.replace('[WOOD_BANK] COMPLETE male-empty-walk-arcs','[WOOD_BANK] MISSING male-empty-walk-arcs'),
                    self.log+'\n[WOOD_BANK] ALL_COMPLETE cases=3',self.log+'\n[WOOD_BANK] FAIL injected'):
            with self.subTest(tail=bad[-70:]):
                self.reject(bad)

    def test_missing_or_reordered_phases(self):
        self.reject(transform(self.log,'PHASE',lambda r:r['phase']=='straight',lambda r:None))
        self.reject(transform(self.log,'PHASE',lambda r:r['phase']=='straight',lambda r:update(r,index=r['index']+1)))
        self.reject(transform(self.log,'END',lambda r:r['phase']=='stop',lambda r:None))
        self.reject(transform(self.log,'END',lambda r:r['phase']=='straight',lambda r:update(r,phase='idle')))

    def test_wrong_declared_and_actual_controls(self):
        self.reject(transform(self.log,'PHASE',lambda r:r['phase']=='arc-left45',lambda r:update(r,drive=4)))
        self.reject(transform(self.log,'SAMPLE',lambda r:r['phase']=='arc-left45',lambda r:update(r,backward=True)))
        self.reject(transform(self.log,'SAMPLE',lambda r:r['phase']=='straight',lambda r:update(r,drive=2)))
        self.reject(transform(self.log,'SAMPLE',lambda r:r['phase']=='straight',lambda r:update(r,runKey=not r['runKey'])))

    def test_missing_yaw_and_motionless_arc(self):
        self.reject(transform(self.log,'SAMPLE',lambda r:r['phase']=='arc-left45',lambda r:update(r,acceptedHeading=-3*math.pi/4)))
        result=self.analyze(collapse_phase_motion(self.log,'male-empty-walk-arcs','arc-right90'))
        self.assertTrue(any(f['reason']=='Arc rotated without measured forward motion' for f in result['motionFailures']))
        self.reject(transform(self.log,'END',lambda r:r['phase']=='arc-left45',lambda r:update(r,yaw=0)))

    def test_wrong_gait_or_nonprogressing_native_clip(self):
        self.reject(transform(self.log,'SAMPLE',lambda r:r['case'].endswith('run-slalom-up') and r['phase']=='straight',lambda r:update(r,run=False)))
        self.reject(transform(self.log,'SAMPLE',lambda r:r['case'].endswith('sprint-slalom-down') and r['phase']=='straight',lambda r:update(r,root='heading:0,rootTracks:Bob_Walk@1/.5/1;')))
        self.reject(transform(self.log,'SAMPLE',lambda r:r['phase']=='straight',lambda r:update(r,root='heading:0,rootTracks:Bob_Walk@1/.5/1;')))
        self.reject(transform(self.log,'SAMPLE',lambda r:True,lambda r:update(r,skill=0)))

    def test_stop_clip_is_not_forward_run_progression(self):
        result=self.analyze(transform(self.log,'SAMPLE',lambda r:r['case'].endswith('run-slalom-up') and r['phase']=='straight',
                                     lambda r:update(r,root=r['root'].replace('Bob_Run@','Bob_RunToStop2H_Heavy@'))))
        self.assertTrue(any(f['reason']=='Requested gait was not sustained in native flags/root clips' for f in result['motionFailures']))

    def test_sustained_gait_not_one_good_flag(self):
        self.reject(transform(self.log,'SAMPLE',lambda r:r['case'].endswith('sprint-slalom-down') and r['phase']=='straight' and r['phaseElapsed']>1100,
                              lambda r:update(r,sprint=False)))

    def test_reverse_and_sideways_travel_fail(self):
        result=self.analyze(transform(self.log,'SAMPLE',lambda r:r['case']=='male-empty-walk-arcs',lambda r:update(r,x=200-r['x'],y=200-r['y'])))
        self.assertTrue(any(f['reason']=='Forward input moved backward' for f in result['motionFailures']))
        result=self.analyze(transform(self.log,'SAMPLE',lambda r:r['case']=='male-empty-walk-arcs',lambda r:update(r,x=200-r['y'],y=r['x'])))
        self.assertTrue(any(f['reason']=='Missing measured forward motion' for f in result['motionFailures']))

    def test_steering_release_and_stop_must_settle(self):
        result=self.analyze(transform(self.log,'SAMPLE',lambda r:r['phase']=='release',lambda r:update(r,acceptedHeading=r['acceptedHeading']+.2*math.sin(math.pi*r['phaseElapsed']/800),yaw=.2*math.sin(math.pi*r['phaseElapsed']/800))))
        self.assertTrue(any(f['reason']=='Steering continued after release' for f in result['motionFailures']))
        result=self.analyze(transform(self.log,'SAMPLE',lambda r:r['phase']=='stop',lambda r:update(r,x=r['x']+.4*math.sin(math.pi*r['phaseElapsed']/3500))))
        self.assertTrue(any(f['reason']=='Neutral state did not settle' for f in result['motionFailures']))
        self.reject(transform(self.log,'SAMPLE',lambda r:r['phase']=='tail',lambda r:update(r,run=True)))

    def test_cadence_edges_and_truncated_fixed_window(self):
        self.reject(transform(self.log,'SAMPLE',lambda r:r['phase']=='straight' and 500<r['phaseElapsed']<1200,lambda r:None))
        self.reject(transform(self.log,'SAMPLE',lambda r:r['phase']=='tail' and r['phaseElapsed']>1000,lambda r:None))
        self.reject(transform(self.log,'SAMPLE',lambda r:r['phase']=='straight' and r['phaseElapsed']==0,lambda r:None))

    def test_nan_flags_identity_and_in_capture_resets(self):
        self.reject(transform(self.log,'SAMPLE',lambda r:r['phase']=='straight',lambda r:update(r,x=float('nan'))))
        self.reject(transform(self.log,'SAMPLE',lambda r:r['phase']=='straight',lambda r:update(r,run='false')))
        self.reject(transform(self.log,'SAMPLE',lambda r:r['phase']=='straight',lambda r:update(r,id=r['id']+1)))
        self.reject(transform(self.log,'SAMPLE',lambda r:r['phase']=='straight',lambda r:update(r,x=r['x']+1)))

    def test_rejected_video_attempt_does_not_mix_into_selected_attempt(self):
        rejected='\n'.join(['[WOOD_BANK] CASE male-empty-walk-arcs attempt=0 wall=10',
                           '[CART_MATRIX] PHASE {"case":"male-empty-walk-arcs","phase":"wrong"}'])
        log=self.log.replace('[WOOD_BANK] CASE male-empty-walk-arcs attempt=0 wall=100000',
                             rejected+'\n[WOOD_BANK] CASE male-empty-walk-arcs attempt=1 wall=100000')
        self.assertTrue(self.analyze(log)['motionPass'])

    def test_cli_refuses_overwrite_and_supports_selected_scenes(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            log=root/'native.log';log.write_text(self.log)
            output=root/'report.json'
            command=[sys.executable,str(SCRIPT),'--profile',str(root),'--log',str(log),'--scenes',json.dumps(SMALL),'--output',str(output)]
            good=subprocess.run(command,capture_output=True,text=True)
            self.assertEqual(good.returncode,0,good.stderr)
            self.assertTrue(json.loads(output.read_text())['motionPass'])
            self.assertNotEqual(subprocess.run(command,capture_output=True).returncode,0)

    def test_lua_uses_relative_keys_fixed_windows_and_no_reset_in_tick(self):
        source=SCRIPT.with_name('scenario-motion-matrix.lua').read_text()
        self.assertIn('assert(#cases==36)',source)
        self.assertIn("c.spec=='arcs' and 90000 or 20000",source)
        self.assertIn("side=='left' and 5 or 8",source)
        self.assertIn('cartLabSteeringHeading()',source)
        self.assertIn('[WOOD_RAMP_EVENT]',source)
        self.assertIn("for _,side in ipairs({'left','right'}) do for _,degrees in ipairs({45,90,135,180}) do",source)
        self.assertIn("PZAPI.ModOptions:getOptions('MiniHealthPlus')",source)
        self.assertIn("option:getValue()~=true",source)
        self.assertIn("option:setValue(true)",source)
        self.assertIn('TwisTonFire_MHP_RefreshModOptions()',source)
        self.assertNotIn('ModOptions:save',source)
        self.assertNotIn('cartLabPoseHeading(',source.split('local function tick()',1)[1])
        self.assertNotIn('setX(',source.split('local function tick()',1)[1])

if __name__=='__main__':
    unittest.main()
