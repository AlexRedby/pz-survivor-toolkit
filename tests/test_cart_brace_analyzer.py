"""Brace evidence requires planted rendered feet, a real wall transition and full-window budgets."""
import csv
import importlib.util
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import numpy as np

SCRIPT=Path(__file__).parent/'native_queue/contributions/wooden_cart_motion/analyze-brace.py'
spec=importlib.util.spec_from_file_location('brace_analyzer_test',SCRIPT)
a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
VERTICES=np.array([[x,0,z,1] for x in (-.001,.001) for z in (-.009,-.002)])


def lerp(t,knots):
    for (ta,va),(tb,vb) in zip(knots,knots[1:]):
        if t<=tb:return va+(vb-va)*max(0,(t-ta)/(tb-ta))
    return knots[-1][1]


def fixture(profile):
    lines=['[WOOD_BANK] RUN_STARTED'];frames=[];updates=[];starts={}
    for index,name in enumerate(('wall','corner','passage','wall-slide-left','wall-slide-right')):
        start=10000+index*10000;slide=name.startswith('wall-slide-');duration=6000 if slide else 4000
        lines.append(f'[CART_COLLISION_CONTROL] START spec={name} wall={start} x=3.5 y=10.5 wallX=0 southY=12 gapY=10')
        for t in range(0,duration,100):
            x=lerp(t,[(0,3.5),(3000,-1 if name=='passage' else .3)])
            y=10.5+(-1 if name.endswith('right') else 1)*t/1000 if slide else lerp(t,[(0,10.5),(3000,11.7)]) if name=='corner' else 10.5
            drive=1 if name.endswith('right') else 2 if slide or name=='corner' else 5
            extra=' run=false sprint=false bare=true tracks=Bob_Walk=1@1;' if slide else ''
            lines.append(f'[CART_COLLISION_CONTROL_SAMPLE] spec={name} wall={start+t} elapsed={t} x={x} y={y} heading=3.14159 drive={drive}{extra}')
        lines.append(f'[CART_COLLISION_CONTROL] COMPLETE spec={name} wall={start+duration} x={x} y={y}')
    for index,name in enumerate(sorted(a.EXPECTED)):
        start=100000+index*20000;starts[name]=start;release=name.endswith('wall-release');events=a.steps(name)
        lines.extend((f'[CART_COLLISION_LAYOUT] case={name} wallX=0 southY=12 gapY=10 startX=1.8 startY=10.5 baselineX=.3 baselineY=11.7 ownedWalls={3 if release else 49}',f'[WOOD_BANK] CASE {name} attempt=0 wall={start}'))
        last=1.8;wheel=0
        for t in range(0,a.DURATION,100):
            commands=[e for e in events if e[0]<=t];drive=commands[-1][2] if commands else 0
            knots=[(0,1.8),(1000,1.8),(3000,1.13),(8000,1.13),(14000,-.9),(18000,-.9)] if release else [(0,1.8),(1000,1.8),(3000,1.13),(7500,1.13),(10000,2),(10800,2),(13500,1.13),(18000,1.13)]
            x=lerp(t,knots);distance=abs(x-last);wheel+=(x-last)/a.collision.WHEEL_RADIUS;last=x
            reverse=drive==4;direction=-1 if reverse else 1;moving=distance>0
            clip='Bob_WalkBwdNoAim1Hand' if reverse else 'Bob_Walk' if moving else 'Bob_Idle'
            cadence=(lerp(t,[(8000,0),(8100,.15),(8200,.3),(8300,.43),(8400,.49),(8500,.5)]) if release and 8000<=t<14000 else .5 if moving else 0)
            state=f'heading:{math.pi},target:{math.pi},stationary:false,stationaryRoot:false,actualDistance:{distance},axle:1,rootTracks:{clip}@1/{t/1000}/1;'
            lines.append(f'[WOOD_BANK_SAMPLE] case={name} wall={start+t} elapsed={t} x={x} y=10.5 run=false sprint=false skill=10 speed=.5 drive={drive} requestedGait=0 stepX=0 stepY={int(moving)} pace={cadence/.5} wheelPhase={wheel} bank=0 reversal=direction:{direction},requested:{direction if drive else 0},active:false,braking:false,neutral:0,actualDistance:{distance},brakeTarget:0 ramp=speed:{cadence},heading:{math.pi} stationary={state} tracks={clip}=1@1;')
            blocked=drive==1 and not moving and (not release or t<8000);blend=1 if blocked else 0;nativeBlocked=not release or t<8000
            lines.append(f'[CART_FOOTPRINT_STATE] case={name} wall={start+t} elapsed={t} front=1.26 blocked={str(blocked).lower()} clear=true recovering=false')
            lines.append(f'[CART_BRACE_SAMPLE] case={name} wall={start+t} elapsed={t} brace={blend} nativeBlocked={str(nativeBlocked).lower()} wantsMove={str(drive!=0).lower()}')
            if release and t==8000:
                for phase,owned,native in [('before',3,'true'),('after',0,'false')]:lines.append(f'[CART_BRACE_REMOVE] case={name} phase={phase} wall={start+t} elapsed={t} owned={owned} drive=1 brace=1 nativeBlocked={native} wantsMove=true')
            for at,gait,key in events:
                if t==at:lines.append(f'[WOOD_RAMP_EVENT] case={name} elapsed={at} gait={gait} drive={key}')
            bones={}
            for bone in a.FEET:
                matrix=[1,0,0,0,0,1,0,0,0,0,1,0,0,.07 if bone.endswith('Foot') else .02,0,1];bones[bone]=matrix
            frames.append(dict(wallTimeMillis=start+t,female=name.startswith('female-'),cart=[76.5,0,0,0,0,76.5,0,0,0,0,76.5,0,0,0,0,1],slotX=x,slotY=10.5,slotAngle=3*math.pi/2,bones=bones))
            updates.append(dict(event='grounding',type='SaucedWheelbarrow.WheelbarrowWood',sequence=len(updates)+1,time=(start+t)/1000,wallTimeMillis=start+t,dt=.1,playerX=x,playerY=10.5,actorHeading=math.pi))
        lines.append(f'[WOOD_BANK] COMPLETE {name} wall={start} frames=540 seconds=18')
    lines.extend(('[CART_COLLISION] CLEANUP_COMPLETE',f'[WOOD_BANK] ALL_COMPLETE cases={len(starts)}'))
    (profile/'body-clearance.jsonl').write_text('\n'.join(map(json.dumps,frames)))
    write_updates(profile,updates)
    return '\n'.join(lines),starts


def write_updates(profile,rows):
    with (profile/'wood-wheel-native.csv').open('w') as f:
        writer=csv.DictWriter(f,fieldnames=rows[0]);writer.writeheader();writer.writerows(rows)


class BraceAnalyzerTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name);self.log,self.starts=fixture(self.root)
        self.mesh=patch.object(a.footprint,'mesh',return_value=(VERTICES,'synthetic'));self.mesh.start();self.addCleanup(self.mesh.stop)
    def report(self,log=None):return a.analyze(self.log if log is None else log,self.root)
    def frames(self,name,change):
        p=self.root/'body-clearance.jsonl';rows=[json.loads(l) for l in p.read_text().splitlines()];start=self.starts[name]
        for r in rows:
            if start<=r['wallTimeMillis']<start+a.DURATION:change(r,r['wallTimeMillis']-start)
        p.write_text('\n'.join(map(json.dumps,rows)))
    def test_all_eight_stances_and_five_native_controls_pass(self):
        d=self.report();self.assertEqual((d['caseCount'],d['controlCount']),(8,5));self.assertTrue(d['motionPass'],d['motionFailures']);self.assertTrue(d['footprintPass'],d['footprintFailures'])
        ramps=[c['removalCadence'] for c in d['cases'] if c['removalCadence'] is not None]
        self.assertEqual(len(ramps),4)
        self.assertTrue(all(r['preclearMaximumSpeed']==0 and any(0<v<1 for v in r['normalizedEarlySpeeds']) for r in ramps))
    def test_instantaneous_post_clear_cadence_cannot_hide_behind_later_walk(self):
        name='male-full-wall-release'
        log='\n'.join(re.sub(r'ramp=speed:[^,]+','ramp=speed:.5',l) if '[WOOD_BANK_SAMPLE]' in l and f'case={name} ' in l and 8100<=int(re.search(r'elapsed=(\d+)',l)[1])<=8600 else l for l in self.log.splitlines())
        self.assertIn((name,'held forward cadence jumps or fails to ramp after wall removal'),self.report(log)['motionFailures'])
    def test_preclear_pace_and_nonmonotonic_early_cadence_fail(self):
        name='female-empty-wall-release'
        for at,change in [(7900,lambda l:re.sub(r' pace=[^ ]+',' pace=.3',l)),
                          (8300,lambda l:re.sub(r'ramp=speed:[^,]+','ramp=speed:.05',l))]:
            log='\n'.join(change(l) if '[WOOD_BANK_SAMPLE]' in l and f'case={name} ' in l and f'elapsed={at} ' in l else l for l in self.log.splitlines())
            with self.subTest(elapsed=at):self.assertIn((name,'held forward cadence jumps or fails to ramp after wall removal'),self.report(log)['motionFailures'])
    def test_missing_control_completion_stream_and_removal_fail(self):
        for marker in ('[CART_COLLISION_CONTROL]','[CART_BRACE_SAMPLE]','[CART_FOOTPRINT_STATE]','[CART_BRACE_REMOVE]','[WOOD_BANK] ALL_COMPLETE'):
            with self.subTest(marker=marker),self.assertRaises(AssertionError):self.report('\n'.join(l for l in self.log.splitlines() if marker not in l))
    def test_fake_removal_wrong_owned_object_and_changed_input_fail(self):
        for old,new in [('phase=after wall=','phase=before wall='),('owned=0 drive=1','owned=1 drive=1'),('owned=0 drive=1','owned=0 drive=0'),('owned=3 drive=1 brace=1 nativeBlocked=true','owned=3 drive=1 brace=1 nativeBlocked=false')]:
            with self.subTest(new=new),self.assertRaises(AssertionError):self.report(self.log.replace(old,new))
    def test_brace_scalar_cannot_hide_a_raised_or_moving_foot(self):
        name='female-full-wall-release'
        self.frames(name,lambda f,t:f['bones']['Bip01_L_Foot'].__setitem__(13,.17) if 5000<=t<7500 else None)
        self.assertIn((name,'rendered blocked feet remain raised or move instead of planting'),self.report()['motionFailures'])
    def test_horizontal_foot_and_toe_shuffle_is_rejected(self):
        name='male-full-wall-restart'
        for bone,index in [('Bip01_L_Foot',12),('Bip01_R_Toe0',14)]:
            self.log,self.starts=fixture(self.root)
            self.frames(name,lambda f,t:f['bones'][bone].__setitem__(index,.1 if t%200==0 else -.1) if 5000<=t<6300 else None)
            with self.subTest(bone=bone):self.assertIn((name,'rendered blocked feet remain raised or move instead of planting'),self.report()['motionFailures'])
    def test_static_horizontal_stance_change_is_reported_and_later_offset_fails(self):
        name='female-empty-wall-restart'
        self.frames(name,lambda f,t:f['bones']['Bip01_L_Foot'].__setitem__(12,.04) if 5000<=t<6300 else None)
        result=self.report();self.assertTrue(result['motionPass'],result['motionFailures'])
        case=next(c for c in result['cases'] if c['case']==name)
        self.assertGreaterEqual(case['contact'][0]['horizontalStanceOffset'],.04)
        self.frames(name,lambda f,t:f['bones']['Bip01_L_Foot'].__setitem__(12,.14) if 5500<=t<6300 else None)
        self.assertIn((name,'rendered blocked feet remain raised or move instead of planting'),self.report()['motionFailures'])
    def terminal_tick(self,name,elapsed):
        start=self.starts[name];terminal=[]
        for line in self.log.splitlines():
            if f'case={name} ' in line and 'elapsed=17900 ' in line and any(p in line for p in ('[WOOD_BANK_SAMPLE]','[CART_FOOTPRINT_STATE]','[CART_BRACE_SAMPLE]')):
                terminal.append(re.sub(r' wall=\d+ elapsed=17900 ',f' wall={start+elapsed} elapsed={elapsed} ',line))
        self.assertEqual(len(terminal),3)
        marker=f'[WOOD_BANK] COMPLETE {name} wall={start}'
        return self.log.replace(marker,'\n'.join(terminal)+'\n'+marker)
    def test_boundary_tick_is_validated_then_excluded_from_synchronized_window(self):
        name='male-full-wall-restart'
        for elapsed in (18000,18033):
            log=self.terminal_tick(name,elapsed);result=self.report(log)
            self.assertTrue(result['motionPass'],result['motionFailures'])
            case=next(c for c in result['cases'] if c['case']==name)
            self.assertEqual((case['samples'],case['terminalSamples']),(180,1))
        log=self.terminal_tick(name,18000)
        with self.assertRaisesRegex(AssertionError,'sample clocks disagree'):
            self.report(log.replace(f'wall={self.starts[name]+18000} elapsed=18000',f'wall={self.starts[name]+19000} elapsed=18000'))
        with self.assertRaisesRegex(AssertionError,'Misaligned terminal'):
            self.report('\n'.join(l for l in log.splitlines() if not ('[CART_BRACE_SAMPLE]' in l and 'elapsed=18000 ' in l)))
    def test_explicit_partial_selection_preserves_real_full_run_boundary(self):
        selected=sorted(n for n in self.starts if n.endswith('wall-restart'))
        result=a.analyze(self.log,self.root,selected)
        self.assertEqual((result['caseCount'],result['fullSceneCount'],result['scope']),(4,8,'selected-scenes'))
        self.assertEqual(result['selectedScenes'],selected)
        with self.assertRaisesRegex(AssertionError,'Invalid explicit'):
            a.analyze(self.log,self.root,[selected[0],selected[0]])
    def test_missing_native_contact_or_idle_blend_is_rejected(self):
        name='male-empty-wall-restart'
        log='\n'.join(l.replace('brace=1','brace=0') if f'case={name} ' in l else l for l in self.log.splitlines())
        self.assertIn((name,'blocked contact lacks sustained planted brace'),self.report(log)['motionFailures'])
        log='\n'.join(l.replace('wantsMove=true','wantsMove=false') if f'case={name} ' in l and '[CART_BRACE_SAMPLE]' in l else l for l in self.log.splitlines())
        self.assertIn((name,'blocked contact lacks sustained planted brace'),self.report(log)['motionFailures'])
        with self.assertRaisesRegex(AssertionError,'Native wall oracle'):
            self.report('\n'.join(l.replace('nativeBlocked=true wantsMove','nativeBlocked=false wantsMove') if f'case={name} ' in l and '[CART_BRACE_SAMPLE]' in l else l for l in self.log.splitlines()))
    def test_zero_displacement_rejection_flag_does_not_define_a_planted_brace(self):
        log=self.log.replace('blocked=true clear=true','blocked=false clear=true')
        result=self.report(log);self.assertTrue(result['motionPass'],result['motionFailures'])
        self.assertTrue(all(c['footprintBlockedSamples']==0 for case in result['cases'] for c in case['contact']))
    def test_rendered_wall_penetration_before_removal_and_after_restart_fail(self):
        for name,at in [('male-empty-wall-release',5000),('female-full-wall-restart',15000)]:
            self.frames(name,lambda f,t:f['cart'].__setitem__(14,-.2) if t==at else None)
            self.assertIn((name,'rendered mesh or continuous wheel enters standing wall'),self.report()['footprintFailures'])
    def test_post_removal_geometry_is_free_and_not_a_fictional_standing_wall(self):
        result=self.report();self.assertTrue(result['footprintPass']);self.assertTrue(result['motionPass'])
        name='male-full-wall-release';self.frames(name,lambda f,t:f['bones'].__setitem__('Bip01_L_Foot',[float('nan')]*16) if t==17000 else None)
        with self.assertRaisesRegex(AssertionError,'Invalid rendered foot'):self.report()
    def test_native_late_jump_gap_and_truncated_tail_fail(self):
        name='male-full-wall-restart';start=self.starts[name];p=self.root/'wood-wheel-native.csv'
        with p.open() as f:original=list(csv.DictReader(f))
        rows=[dict(r) for r in original];next(r for r in rows if float(r['wallTimeMillis'])==start+16000)['playerX']='100';write_updates(self.root,rows)
        self.assertIn((name,'position jumps outside native update budget'),self.report()['motionFailures'])
        write_updates(self.root,[r for r in original if not start+16000<=float(r['wallTimeMillis'])<=start+16700])
        with self.assertRaisesRegex(AssertionError,'Incomplete or non-monotonic'):self.report()
        write_updates(self.root,[r for r in original if not start+17000<=float(r['wallTimeMillis'])<start+18000])
        with self.assertRaisesRegex(AssertionError,'Incomplete native grounding sample edges'):self.report()
    def test_frozen_gait_cannot_pass_resumed_forward(self):
        name='male-empty-wall-release'
        log='\n'.join(re.sub('rootTracks:Bob_Walk@1/[^/]+/1;','rootTracks:Bob_Idle@1/0/1;',l) if f'case={name} ' in l and '[WOOD_BANK_SAMPLE]' in l else l for l in self.log.splitlines())
        self.assertIn((name,'held forward does not resume smoothly after wall removal'),self.report(log)['motionFailures'])
    def test_early_post_removal_progress_cannot_hide_late_root_freeze(self):
        name='male-empty-wall-release';start=self.starts[name];frozen=lerp(10000,[(8000,1.13),(14000,-.9)])
        lines=[]
        for line in self.log.splitlines():
            if '[WOOD_BANK_SAMPLE]' in line and f'case={name} ' in line and int(re.search(r'elapsed=(\d+)',line)[1])>=10000:
                line=re.sub(r' x=([^ ]+)',lambda m:' x='+str(max(frozen,float(m[1]))),line)
            lines.append(line)
        self.frames(name,lambda f,t:f.__setitem__('slotX',max(frozen,f['slotX'])) if t>=10000 else None)
        p=self.root/'wood-wheel-native.csv'
        with p.open() as f:rows=list(csv.DictReader(f))
        for row in rows:
            if start+10000<=float(row['wallTimeMillis'])<start+a.DURATION:row['playerX']=str(max(frozen,float(row['playerX'])))
        write_updates(self.root,rows)
        self.assertIn((name,'resumed forward motion freezes reverses or turns after wall removal'),self.report('\n'.join(lines))['motionFailures'])
    def test_reverse_forward_restart_and_final_settle_cannot_be_omitted(self):
        name='male-full-wall-restart'
        def changed(begin,end,replace):
            return '\n'.join(replace(l) if '[WOOD_BANK_SAMPLE]' in l and f'case={name} ' in l and begin<=int(re.search(r'elapsed=(\d+)',l)[1])<end else l for l in self.log.splitlines())
        log=changed(7800,10000,lambda l:l.replace('reversal=direction:-1','reversal=direction:1'))
        self.assertIn((name,'reverse does not leave blocked stance'),self.report(log)['motionFailures'])
        log=changed(11100,14500,lambda l:re.sub('rootTracks:Bob_Walk@1/[^/]+/1;','rootTracks:Bob_Idle@1/0/1;',l))
        self.assertIn((name,'forward restart does not return to wall contact'),self.report(log)['motionFailures'])
        log=changed(17400,17500,lambda l:re.sub(r'wheelPhase=([^ ]+)',lambda m:'wheelPhase='+str(float(m[1])+1),l))
        self.assertIn((name,'final brace release does not settle'),self.report(log)['motionFailures'])
    def test_moving_toes_and_missing_late_render_tail_fail(self):
        name='male-full-wall-restart'
        self.frames(name,lambda f,t:f['bones']['Bip01_R_Toe0'].__setitem__(13,.02+(.02 if t%200==0 else -.02)) if 5000<=t<6300 else None)
        self.assertIn((name,'rendered blocked feet remain raised or move instead of planting'),self.report()['motionFailures'])
        p=self.root/'body-clearance.jsonl';start=self.starts[name]
        p.write_text('\n'.join(l for l in p.read_text().splitlines() if not start+17000<=json.loads(l)['wallTimeMillis']<start+18000))
        with self.assertRaisesRegex(AssertionError,'Incomplete brace render .* sample edges'):self.report()
    def test_missing_foot_geometry_wrong_sex_and_cli_overwrite_fail(self):
        name='female-empty-wall-restart';self.frames(name,lambda f,t:f.__setitem__('female',False) if t==15000 else None)
        with self.assertRaisesRegex(AssertionError,'Wrong brace render sex'):self.report()
        output=self.root/'immutable.json';output.write_text('keep')
        r=subprocess.run([sys.executable,str(SCRIPT),'--profile',str(self.root),'--output',str(output)],capture_output=True,text=True)
        self.assertNotEqual(r.returncode,0);self.assertIn('immutable',r.stderr);self.assertEqual(output.read_text(),'keep')


if __name__=='__main__':unittest.main()
