"""Vehicle evidence must prove native contact, independent mesh clearance and recovery."""
import csv
import importlib.util
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import numpy as np

SCRIPT=Path(__file__).parent/'native_queue/contributions/wooden_cart_motion/analyze-vehicles.py'
spec=importlib.util.spec_from_file_location('cart_vehicle_analyzer',SCRIPT)
a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
VERTICES=np.array([[x,0,z,1] for x in (-.001,.001) for z in (-.009,-.002)])


def interpolate(t,knots):
    for (ta,va),(tb,vb) in zip(knots,knots[1:]):
        if t<=tb:return va+(vb-va)*max(0,(t-ta)/(tb-ta))
    return knots[-1][1]


def fixture(profile):
    lines=['[WOOD_BANK] RUN_STARTED'];frames=[];native=[];sequence=0;starts={}
    for index,name in enumerate([*sorted(a.CONTROLS),*sorted(a.EXPECTED)]):
        bare=name in a.CONTROLS;yaw=45 if 'yaw45' in name else 0
        angle=math.radians(yaw);normal=np.array([math.cos(angle),-math.sin(angle)]);tangent=np.array([math.sin(angle),math.cos(angle)])
        direction=-1 if name.endswith('right') else 1;front=name.endswith('front')
        shape=np.array([normal*n+tangent*t for n,t in ((-1,-2),(1,-2),(1,2),(-1,2))])
        receipt=f'id={index+1} z=7 static=true active=false bodyBlocked=true crossBlocked=true hull='+','.join(map(str,shape.ravel()))
        start=100000+index*17000;starts[name]=start;duration=7000 if bare else a.duration(name);extra=duration-12000 if not bare else 0
        initial=math.atan2(-normal[1]+(0 if front else direction*tangent[1]),-normal[0]+(0 if front else direction*tangent[0]))
        drive=min(a.footprint.ANGLES,key=lambda k:abs(a.wrap(a.footprint.ANGLES[k]-initial)))
        final_heading=math.atan2(-normal[1],-normal[0]) if front else math.atan2(direction*tangent[1],direction*tangent[0])
        reverse=min(a.footprint.ANGLES,key=lambda k:abs(a.wrap(a.footprint.ANGLES[k]-final_heading-math.pi)))
        def pose(t):
            if bare:
                n=interpolate(t,[(0,1.9),(1000,1.9),(2200,1.16),(7000,1.16)])
                v=direction*interpolate(t,[(0,-1.4),(1000,-1.4),(2200,-1),(7000,1.7)])
                heading=initial
            elif front:
                n=interpolate(t,[(0,3.2),(1000,3.2),(2500,2.05),(9300,2.05),(11000,2.75),(12000,2.75)])
                v=0;heading=final_heading
            else:
                n=interpolate(t,[(0,3.2),(1000,3.2),(3000,1.13),(7000,1.13),(8200,.85),(12000+extra,.85)])
                v=direction*interpolate(t,[(0,-1.4),(1000,-1.4),(3000,-1),(7600,3.2),(9300+extra,3.2),(11000+extra,2.4),(12000+extra,2.4)])
                heading=initial+a.wrap(final_heading-initial)*max(0,min(1,(t-1800)/1000))
            return normal*n+tangent*v,heading
        first,_=pose(0)
        lines.append(f'[CART_VEHICLE_CONTROL] START {name} wall={start}' if bare else f'[WOOD_BANK] CASE {name} attempt=0 wall={start}')
        lines.append(f'[CART_VEHICLE_LAYOUT] case={name} yaw={yaw} x=0 y=0 z=7 nx={normal[0]} ny={normal[1]} tx={tangent[0]} ty={tangent[1]} width=1 length=2 startX={first[0]} startY={first[1]} {receipt}')
        last=first;wheel=0
        for t in range(0,duration,100):
            position,heading=pose(t);x,y=position;distance=float(np.linalg.norm(position-last));travel=float((position-last)@np.array([math.cos(heading),math.sin(heading)]));last=position
            wheel-=travel/a.collision.WHEEL_RADIUS
            stage=1 if 1000<=t<8500+extra else 3 if 9300+extra<=t<11000+extra else 0
            if bare:stage=1 if t>=1000 else 0
            requested=drive if stage==1 else reverse if stage==3 else 0
            if not bare and t in (1000,8500+extra,9300+extra,11000+extra):lines.append(f'[WOOD_RAMP_EVENT] case={name} elapsed={t} gait=0 drive={requested}')
            prefix='CART_VEHICLE_CONTROL_SAMPLE' if bare else 'CART_VEHICLE_SAMPLE'
            lines.append(f'[{prefix}] case={name} wall={start+t} elapsed={t} x={x} y={y} heading={heading} drive={requested} bare={str(bare).lower()} run=false sprint=false tracks=Bob_Walk=1@1; {receipt}')
            if bare:continue
            direction_state=-1 if stage==3 else 1;clip='Bob_WalkBwdNoAim1Hand' if stage==3 else 'Bob_Walk' if stage==1 else 'Bob_Idle'
            lines.append(f'[WOOD_BANK_SAMPLE] case={name} wall={start+t} elapsed={t} x={x} y={y} run=false sprint=false skill=10 speed=.6 drive={requested} requestedGait=0 stepX=0 stepY=.5 pace=1 wheelPhase={wheel} bank=0 reversal=direction:{direction_state},requested:{direction_state},active:false,braking:false,neutral:0,actualDistance:{distance},brakeTarget:0 ramp=speed:.6,heading:{heading} stationary=heading:{heading},target:{heading},stationary:false,stationaryRoot:false,actualDistance:{distance},axle:1,rootTracks:{clip}@1/{t/1000}/1; tracks={clip}=1@1;')
            lines.append(f'[CART_FOOTPRINT_STATE] case={name} wall={start+t} elapsed={t} front=1.26 blocked={str(2000<=t<6500).lower()} recovering=false clear=true')
            frames.append(dict(wallTimeMillis=start+t,female=False,cart=[76.5,0,0,0,0,76.5,0,0,0,0,76.5,0,0,0,0,1],slotX=float(x),slotY=float(y),slotAngle=heading+math.pi/2))
            sequence+=1;native.append(dict(event='grounding',type='SaucedWheelbarrow.WheelbarrowWood',sequence=sequence,time=(start+t)/1000,wallTimeMillis=start+t,dt=.1,playerX=x,playerY=y,actorHeading=heading))
        lines.append(f'[CART_VEHICLE_CONTROL] COMPLETE {name} wall={start+duration}' if bare else f'[WOOD_BANK] COMPLETE {name} wall={start} file=video.mp4 frames={duration//1000*30} seconds={duration/1000}')
    lines.extend(('[CART_VEHICLE] CLEANUP_COMPLETE',f'[WOOD_BANK] ALL_COMPLETE cases={len(a.EXPECTED)}'))
    (profile/'body-clearance.jsonl').write_text('\n'.join(map(json.dumps,frames)))
    with (profile/'wood-wheel-native.csv').open('w') as target:
        writer=csv.DictWriter(target,fieldnames=native[0]);writer.writeheader();writer.writerows(native)
    return '\n'.join(lines),starts


class VehicleAnalyzerTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.log,self.starts=fixture(self.root)
        self.mesh=patch.object(a.footprint,'mesh',return_value=(VERTICES,'synthetic'));self.mesh.start();self.addCleanup(self.mesh.stop)
    def report(self,log=None):return a.analyze(self.log if log is None else log,self.root)
    def test_layout_checks_declared_and_measured_levels_without_duplicate_waiver(self):
        self.assertEqual(a.layout_fields('case=probe z=7 id=1 z=7.0')['z'],'7.0')
        for text in ('case=probe z=7 id=1 z=6', 'case=probe z=7 z=7 id=1 z=7',
                     'case=probe z=7 id=1 id=1 z=7', 'case=probe z=nan id=1 z=nan',
                     'case=probe z=7 yaw=0 id=1 z=7 yaw=0'):
            with self.subTest(text=text),self.assertRaises(AssertionError):a.layout_fields(text)

    def mutate_heading(self,name,change):
        start=self.starts[name];lines=[]
        for line in self.log.splitlines():
            if f'case={name} ' in line and ('[WOOD_BANK_SAMPLE]' in line or '[CART_VEHICLE_SAMPLE]' in line):
                elapsed=int(re.search(r'elapsed=(\d+)',line)[1])
                match=re.search(r'heading[:=]([^, ]+)',line);heading=change(elapsed,float(match[1]))
                line=re.sub(r'heading:[^, ]+',f'heading:{heading}',line)
                line=re.sub(r'heading=[^ ]+',f'heading={heading}',line)
            lines.append(line)
        path=self.root/'body-clearance.jsonl';frames=[json.loads(line) for line in path.read_text().splitlines()]
        for frame in frames:
            elapsed=frame['wallTimeMillis']-start
            if 0<=elapsed<a.duration(name):frame['slotAngle']=change(elapsed,frame['slotAngle']-math.pi/2)+math.pi/2
        path.write_text('\n'.join(map(json.dumps,frames)))
        path=self.root/'wood-wheel-native.csv'
        with path.open() as source:reader=csv.DictReader(source);keys=reader.fieldnames;rows=list(reader)
        for row in rows:
            elapsed=float(row['wallTimeMillis'])-start
            if 0<=elapsed<a.duration(name):row['actorHeading']=change(elapsed,float(row['actorHeading']))
        with path.open('w') as target:writer=csv.DictWriter(target,fieldnames=keys);writer.writeheader();writer.writerows(rows)
        return '\n'.join(lines)

    def test_missing_aligned_contact_and_yaw_flutter_fail(self):
        name='male-empty-vehicle-yaw0-slide-left'
        log=self.mutate_heading(name,lambda t,h:math.pi/2+.2 if 3000<=t<8500 else h)
        self.assertIn((name,'rendered cart never sustains vehicle contact'),self.report(log)['motionFailures'])
        self.log,self.starts=fixture(self.root)
        log=self.mutate_heading(name,lambda t,h:math.pi/2+(.03 if t%200==0 else -.03) if 3800<=t<8000 else h)
        self.assertIn((name,'vehicle contact heading chatters'),self.report(log)['motionFailures'])

    def test_complete_twelve_scene_matrix_requires_four_bare_controls(self):
        result=self.report()
        self.assertEqual((result['caseCount'],result['controlCount']),(12,4))
        self.assertTrue(result['motionPass'],result['motionFailures']);self.assertTrue(result['footprintPass'],result['footprintFailures'])
        self.assertEqual({r['case'] for r in result['cases']},a.EXPECTED)
        self.assertTrue(all(r['geometrySamples'] and r['nativeUpdates']>=80 for r in result['cases']))
    def test_full_slide_tails_keep_native_budgets_and_coverage_after_twelve_seconds(self):
        name='male-full-vehicle-yaw45-slide-left';start=self.starts[name]
        self.assertEqual(a.duration(name),15000)
        self.assertEqual(a.duration('male-empty-vehicle-yaw45-slide-left'),12000)
        path=self.root/'wood-wheel-native.csv'
        with path.open() as source:reader=csv.DictReader(source);keys=reader.fieldnames;original=list(reader)
        def write(rows):
            with path.open('w') as target:
                writer=csv.DictWriter(target,fieldnames=keys);writer.writeheader();writer.writerows(rows)
        rows=[dict(r) for r in original]
        next(r for r in rows if float(r['wallTimeMillis'])==start+12500)['playerX']='100'
        write(rows)
        self.assertIn((name,'position jumps outside native update budget'),self.report()['motionFailures'])
        write([r for r in original if not start+12500<=float(r['wallTimeMillis'])<=start+13100])
        with self.assertRaisesRegex(AssertionError,'Incomplete or non-monotonic native grounding'):self.report()
        write([r for r in original if not start+12000<=float(r['wallTimeMillis'])<start+15000])
        with self.assertRaisesRegex(AssertionError,'Incomplete native grounding sample edges'):self.report()
        write(original)
    def test_full_slide_final_quiet_window_covers_fifteen_second_tail(self):
        name='male-full-vehicle-yaw45-slide-left'
        log=self.mutate_positions(name,lambda t,x,y:(x+.05*math.sin(t/100),y) if 14600<=t<15000 else (x,y))
        self.assertIn((name,'final vehicle release does not settle'),self.report(log)['motionFailures'])
    def test_pre_settle_displacement_uses_stable_measured_start(self):
        log='\n'.join(re.sub(r' startX=([^ ]+)',lambda m:' startX='+str(float(m[1])+.25),line)
                      if '[CART_VEHICLE_LAYOUT]' in line else line for line in self.log.splitlines())
        result=self.report(log)
        self.assertTrue(result['motionPass'],result['motionFailures'])
        self.assertTrue(result['footprintPass'],result['footprintFailures'])
    def test_measured_pre_input_motion_and_short_window_are_rejected(self):
        name='yaw0-slide-left'
        log='\n'.join(re.sub(r' x=([^ ]+)',lambda m:' x='+str(float(m[1])+.05),line)
                      if '[CART_VEHICLE_CONTROL_SAMPLE]' in line and f'case={name} ' in line and 'elapsed=500 ' in line else line
                      for line in self.log.splitlines())
        with self.assertRaisesRegex(AssertionError,'moves during measured pre-input'):self.report(log)
        name='male-empty-vehicle-yaw0-front'
        log=self.mutate_positions(name,lambda t,x,y:(x+.05,y) if t==500 else (x,y))
        with self.assertRaisesRegex(AssertionError,'moves during measured pre-input'):self.report(log)
        with self.assertRaisesRegex(AssertionError,'Missing stable pre-input'):
            a.measured_start([dict(elapsed=t,wall=t,x=0,y=0,heading=0,drive=0) for t in range(200,1000,100)])
    def test_empty_missing_control_queries_identity_hull_and_level_fail(self):
        variants=('', '[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] ALL_COMPLETE cases=12',
                  '\n'.join(l for l in self.log.splitlines() if 'CONTROL' not in l),
                  self.log.replace('bodyBlocked=true','bodyBlocked=false'),self.log.replace('crossBlocked=true','crossBlocked=false'),
                  self.log.replace(' static=true',' static=false'),self.log.replace(' active=false',' active=true'))
        for log in variants:
            with self.subTest(log=log[:50]),self.assertRaises((AssertionError,KeyError)):self.report(log)
        name='male-empty-vehicle-yaw0-front'
        for old,new in (('id=','id=99'),('z=7','z=6'),('hull=','hull=nan,')):
            lines=self.log.splitlines();index=next(i for i,l in enumerate(lines) if f'case={name} ' in l and 'elapsed=2000 ' in l and '[CART_VEHICLE_SAMPLE]' in l)
            lines[index]=lines[index].replace(old,new)
            with self.subTest(new=new),self.assertRaises((AssertionError,ValueError)):self.report('\n'.join(lines))
    def test_actor_contact_cannot_be_replaced_with_free_space_walk(self):
        log='\n'.join(re.sub(r' x=[^ ]+',' x=10',line) if '[CART_VEHICLE_CONTROL_SAMPLE]' in line and int(re.search(r'elapsed=(\d+)',line)[1])>=1000 else line for line in self.log.splitlines())
        result=self.report(log)
        self.assertIn('bare Walk lacks sustained vehicle contact slide',[why for _,why in result['motionFailures']])
    def test_cart_slide_freeze_backtracking_and_contact_rejection_are_required(self):
        name='male-empty-vehicle-yaw0-slide-left'
        log='\n'.join(line.replace('blocked=true','blocked=false') if f'case={name} ' in line else line for line in self.log.splitlines())
        self.assertIn((name,'vehicle contact never rejects normal movement'),self.report(log)['motionFailures'])
        contact=[dict(wall=t,x=1.13,y=math.sin(t/100)*.1) for t in range(1000,3000,100)]
        self.assertGreater(a.contact_metrics(contact,dict(nx=1,ny=0,tx=0,ty=1),1)['backtracking'],.04)
    def mutate_positions(self,name,change):
        start=self.starts[name]
        lines=[]
        for line in self.log.splitlines():
            if f'case={name} ' in line and ('[WOOD_BANK_SAMPLE]' in line or '[CART_VEHICLE_SAMPLE]' in line):
                elapsed=int(re.search(r'elapsed=(\d+)',line)[1]);x=float(re.search(r' x=([^ ]+)',line)[1]);y=float(re.search(r' y=([^ ]+)',line)[1])
                x,y=change(elapsed,x,y);line=re.sub(r' x=[^ ]+ y=[^ ]+',f' x={x} y={y}',line)
            lines.append(line)
        path=self.root/'body-clearance.jsonl';frames=[json.loads(l) for l in path.read_text().splitlines()]
        for frame in frames:
            elapsed=frame['wallTimeMillis']-start
            if 0<=elapsed<a.duration(name):frame['slotX'],frame['slotY']=change(elapsed,frame['slotX'],frame['slotY'])
        path.write_text('\n'.join(map(json.dumps,frames)))
        path=self.root/'wood-wheel-native.csv'
        with path.open() as source:reader=csv.DictReader(source);keys=reader.fieldnames;rows=list(reader)
        for row in rows:
            elapsed=float(row['wallTimeMillis'])-start
            if 0<=elapsed<a.duration(name):row['playerX'],row['playerY']=change(elapsed,float(row['playerX']),float(row['playerY']))
        with path.open('w') as target:writer=csv.DictWriter(target,fieldnames=keys);writer.writeheader();writer.writerows(rows)
        return '\n'.join(lines)
    def test_early_tangent_progress_cannot_hide_late_freeze_or_missing_end_release(self):
        name='male-empty-vehicle-yaw0-slide-left'
        log=self.mutate_positions(name,lambda t,x,y:(x,min(y,0)) if t>=3500 else (x,y))
        failures=self.report(log)['motionFailures']
        self.assertIn((name,'cart lacks sustained tangent progress at vehicle contact'),failures)
        self.assertIn((name,'cart does not clear finite vehicle end'),failures)
    def test_stationary_reverse_and_frontal_chatter_fail(self):
        name='male-empty-vehicle-yaw0-front'
        log=self.mutate_positions(name,lambda t,x,y:(2.05,y) if t>=9300 else (x,y))
        self.assertIn((name,'native reverse does not escape vehicle'),self.report(log)['motionFailures'])
        self.log,self.starts=fixture(self.root)
        log=self.mutate_positions(name,lambda t,x,y:(x+.02*math.sin(t/100),y) if 5000<=t<8000 else (x,y))
        self.assertIn((name,'frontal vehicle contact chatters'),self.report(log)['motionFailures'])
    def test_render_matrix_penetration_detected_for_both_hull_yaws(self):
        path=self.root/'body-clearance.jsonl';original=path.read_text()
        for yaw in (0,45):
            name=f'male-empty-vehicle-yaw{yaw}-front';at=self.starts[name]+5000
            frames=[json.loads(l) for l in original.splitlines()]
            row=next(r for r in frames if r['wallTimeMillis']==at)
            # Translate the actual rendered cart through the native hull without changing actor telemetry.
            row['cart'][14]=-.02
            path.write_text('\n'.join(map(json.dumps,frames)))
            result=self.report();self.assertIn((name,'rendered wooden mesh enters native vehicle hull'),result['footprintFailures'])
        path.write_text(original)
    def test_wheel_support_is_continuous_and_independent_of_static_body_vertices(self):
        frame=dict(cart=[76.5,0,0,0,0,76.5,0,0,0,0,76.5,0,0,0,0,1],slotX=1.02,slotY=0,slotAngle=math.pi)
        vehicle=[[-1,-2],[1,-2],[1,2],[-1,2]]
        geometry=a.geometry(frame,np.array([[.001,0,-.009,1],[.002,0,-.009,1],[.001,0,-.008,1]]),vehicle)
        self.assertGreater(geometry['bodyGap'],0)
        self.assertLess(geometry['wheelGap'],-.005)
    def test_frame_native_stream_and_events_cannot_be_omitted(self):
        for marker in ('[WOOD_RAMP_EVENT]','[CART_FOOTPRINT_STATE]','[WOOD_BANK_SAMPLE]'):
            log='\n'.join(l for l in self.log.splitlines() if marker not in l)
            with self.subTest(marker=marker),self.assertRaises(AssertionError):self.report(log)
        (self.root/'wood-wheel-native.csv').unlink()
        with self.assertRaises(FileNotFoundError):self.report()
    @unittest.skipUnless(shutil.which('luajit') or shutil.which('lua'),'Lua interpreter unavailable')
    def test_pad_guard_requires_exact_allowlist_and_preserves_foreign_rejections(self):
        root=SCRIPT.parents[4].resolve()
        code='ProjectRoot='+json.dumps(str(root))+';dofile('+json.dumps(str(root/'tests/test_cart_vehicle_guards.lua'))+')'
        subprocess.run([shutil.which('luajit') or shutil.which('lua'),'-e',code],check=True,capture_output=True,text=True)
    def test_nonfinite_geometry_missing_proof_and_cli_overwrite_fail(self):
        with self.assertRaises(AssertionError):a.receipt(dict(id='1',z='7',static='true',active='false',bodyBlocked='true',crossBlocked='true',hull='nan,0,1,0,1,1,0,1'))
        self.mesh.stop()
        with self.assertRaises(FileNotFoundError):self.report()
        self.mesh.start()
        report=self.root/'report.json';report.write_text('immutable')
        result=subprocess.run([sys.executable,str(SCRIPT),'--profile',str(self.root),'--output',str(report)],capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0);self.assertIn('Refuse to overwrite',result.stderr);self.assertEqual(report.read_text(),'immutable')


if __name__=='__main__':unittest.main()
