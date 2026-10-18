"""Independent cart footprint oracle rejects missing evidence and measured penetration."""
import hashlib
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

SCRIPT = Path(__file__).parent/'native_queue/contributions/wooden_cart_motion/analyze-footprint.py'
spec = importlib.util.spec_from_file_location('cart_footprint_analyzer', SCRIPT)
analyzer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analyzer)


def lerp(t, knots):
    for (a, x), (b, y) in zip(knots, knots[1:]):
        if t <= b:
            return x+(y-x)*max(0, (t-a)/(b-a))
    return knots[-1][1]


def fixture(profile, slide_stop=5800):
    directory = profile;directory.mkdir(exist_ok=True)
    vertices = np.zeros((8116, 8), dtype='<f4')
    for i in range(1114, 8116):
        vertices[i, :3] = [(-1 if i%2 else 1)*.0026, -.0053 if i%3 else .004, -.001]
    data = vertices.tobytes();sha = hashlib.sha256(data).hexdigest()
    (directory/'WheelbarrowWood.bin').write_bytes(data)
    (directory/'wood-wheel-mesh-proof.json').write_text(json.dumps(dict(sha256=sha, matchesOriginal=True, bytes=len(data), indices=16914)))
    matrix = [76.5, 0, 0, 0, 0, 20.771942, 73.62592, 0, 0, -73.625916, 20.771938, 0, -.006053576, .097179376, -.34652627, 1]
    lines, frames, updates = ['[WOOD_BANK] RUN_STARTED'], [], []
    for i, control in enumerate(('wall', 'corner', 'passage', 'wall-slide-left', 'wall-slide-right')):
        start = 10000+i*10000
        lines.append(f'[CART_COLLISION_CONTROL] START spec={control} wall={start} x=3.5 y=10.5 wallX=0 southY=12 gapY=10')
        slide=control.startswith('wall-slide-')
        duration=6000 if slide else 4000
        for t in range(0, duration, 100):
            x = lerp(t, [(0, 3.5), (3000, -1 if control=='passage' else .3)])
            y = (10.5+(-1 if control.endswith('right') else 1)*t/1000) if slide else lerp(t, [(0, 10.5), (3000, 11.7)]) if control=='corner' else 10.5
            drive=1 if control=='wall-slide-right' else 2 if control in ('corner','wall-slide-left') else 5
            extra=' run=false sprint=false bare=true tracks=Bob_Walk=1@1;' if slide else ''
            lines.append(f'[CART_COLLISION_CONTROL_SAMPLE] spec={control} wall={start+t} elapsed={t} x={x} y={y} heading=3.14159 drive={drive}{extra}')
        lines.append(f'[CART_COLLISION_CONTROL] COMPLETE spec={control} wall={start+duration} x={x} y={y}')
    for i, name in enumerate(sorted(analyzer.EXPECTED)):
        scene, start = name.split('-', 2)[2], 100000+i*15000
        initial = (1.3, 10.82) if scene=='corner-pivot' else (1.8, 10.5) if scene in ('passage', 'door-open') else (.65, 10.5) if scene=='overlap' else (1.4, 10.5) if scene=='gait-contact' else (3.5, 10.5)
        lines.extend([f'[CART_COLLISION_LAYOUT] case={name} wallX=0 southY=12 gapY=10 startX={initial[0]} startY={initial[1]} baselineX=.3 baselineY=11.7',
                      f'[WOOD_BANK] CASE {name} attempt=0 wall={start}'])
        events = [(at, g, (1 if scene=='corner-pivot' else 3 if scene=='wall-slide' else 4 if scene=='wall-slide-right' else 7) if d is None else d) for at, g, d in analyzer.steps(name)]
        previous, phase = initial, 0.
        for t in range(0, 12000, 100):
            command = [e for e in events if e[0] < t]
            _, gait, drive = command[-1] if command else (0, 0, 0)
            heading = -3*math.pi/4 if scene=='wall-slide-right' else analyzer.collision.HEADINGS.get(scene, math.pi)
            reverse_at = events[-2][0]
            if scene in ('passage', 'door-open'):
                x = lerp(t, [(0, 1.8), (1000, 1.8), (events[1][0]-300, -2.), (reverse_at, -2.), (9000, 2.4)])
                y = 10.5
            elif scene=='corner-pivot':
                distance = lerp(t, [(0, 0), (reverse_at, 0), (8000, .7)])
                x, y = initial[0]-distance/math.sqrt(2), initial[1]-distance/math.sqrt(2)
            elif scene=='overlap':
                x = lerp(t, [(0, .65), (reverse_at, .65), (8000, 2.4)]);y=10.5
            elif scene=='gait-contact':
                x = lerp(t, [(0, 1.4), (1000, 1.4), (2500, 1.35), (reverse_at, 1.35), (9500, 2.4)]);y=10.5
            else:
                x = lerp(t, [(0, 3.5), (1000, 3.5), (3000, 1.5), (reverse_at, 1.5), (9000, 2.4)])
                y = 10.5+(-1 if scene.endswith('right') else 1)*lerp(t, [(0, 0), (1000, 0), (slide_stop, 1.5), (reverse_at, 1.5), (9000, 0)]) if scene in ('wall-slide','wall-slide-right') else 10.5
            moving = math.dist(previous, (x, y)) > 1e-8
            phase = analyzer.wrap(phase-((x-previous[0])*math.cos(heading)+(y-previous[1])*math.sin(heading))/analyzer.collision.WHEEL_RADIUS)
            previous=x,y
            reverse = t > reverse_at
            direction = -1 if reverse else 1
            requested = direction if drive else 0
            stationary = scene=='corner-pivot' and 1000<t<4000
            run = gait==1 and moving and scene!='gait-contact'
            clip = 'Bob_WalkBwdNoAim1Hand' if reverse else 'Bob_Run' if run else 'Bob_Idle' if not moving else 'Bob_Walk'
            actual = .002 if moving else 0
            target=-math.pi/4 if stationary else heading
            state = f'heading:{heading},target:{target},stationary:{str(stationary).lower()},stationaryRoot:{str(stationary).lower()},actualDistance:{actual},axle:1,rootTracks:{clip}@1/{t/1000}/1;'
            lines.append(f'[WOOD_BANK_SAMPLE] case={name} wall={start+t} elapsed={t} x={x} y={y} run={str(run).lower()} sprint=false skill=10 speed=.8 drive={drive} requestedGait={gait} '
                f'stepX=0 stepY={direction if moving else 0} pace=1 wheelPhase={phase} bank=0 reversal=direction:{direction},requested:{requested},active:false,braking:false,neutral:0,actualDistance:{actual},brakeTarget:{heading}, '
                f'ramp=speed:{.2 if moving else 0},velocity:0,sprintMomentum:0,load:{1 if "-full-" in name else 0},heading:{heading},target:0, stationary={state} tracks={clip}=1@1;')
            blocked = scene not in ('passage', 'door-open', 'corner-pivot', 'gait-contact') and 1200<=t<reverse_at
            recovering = scene=='overlap' and reverse_at<t<6000
            lines.append(f'[CART_FOOTPRINT_STATE] case={name} wall={start+t} elapsed={t} front={1.62 if gait and scene!='gait-contact' else 1.26} blocked={str(blocked).lower()} recovering={str(recovering).lower()} clear={str(not blocked and not recovering).lower()}')
            frames.append(dict(wallTimeMillis=start+t, female=name.startswith('female-'), cart=list(matrix), slotX=x, slotY=y, slotAngle=heading+math.pi/2))
            updates.append(dict(event='grounding', type='SaucedWheelbarrow.WheelbarrowWood', sequence=len(updates)+1,
                time=(start+t)/1000, wallTimeMillis=start+t, dt=.1, playerX=x, playerY=y, actorHeading=heading))
            for at, g, d in events:
                if at==t: lines.append(f'[WOOD_RAMP_EVENT] case={name} elapsed={at} gait={g} drive={d}')
        lines.append(f'[WOOD_BANK] COMPLETE {name} wall={start}')
    lines.append('[WOOD_BANK] ALL_COMPLETE cases=24')
    (directory/'body-clearance.jsonl').write_text('\n'.join(map(json.dumps, frames)))
    write_updates(directory, updates)
    return '\n'.join(lines), sha


def write_updates(profile, rows):
    with (profile/'wood-wheel-native.csv').open('w', newline='') as target:
        writer=csv.DictWriter(target, fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)


def read_updates(profile):
    with (profile/'wood-wheel-native.csv').open() as source:
        return list(csv.DictReader(source))


class FootprintTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.log, sha=fixture(self.root)
        self.hash_patch=patch.object(analyzer, 'MESH_SHA', sha);self.hash_patch.start();self.addCleanup(self.hash_patch.stop)

    def report(self, log=None):
        return analyzer.analyze(self.log if log is None else log, self.root)

    def mutate_frames(self, name, update):
        start=int(re.search(r'COMPLETE '+name+r' wall=(\d+)', self.log)[1])
        path=self.root/'body-clearance.jsonl'
        rows=[json.loads(line) for line in path.read_text().splitlines()]
        for row in rows:
            if start<=row['wallTimeMillis']<start+12000: update(row, row['wallTimeMillis']-start)
        path.write_text('\n'.join(map(json.dumps, rows)))

    def mutate_updates(self, name, update):
        start=int(re.search(r'COMPLETE '+name+r' wall=(\d+)', self.log)[1])
        rows=read_updates(self.root)
        for row in rows:
            if start<=float(row['wallTimeMillis'])<start+12000: update(row, float(row['wallTimeMillis'])-start)
        write_updates(self.root, rows)

    def test_full_matrix_separates_motion_mesh_and_pose_runtime(self):
        report=self.report()
        self.assertTrue(report['motionPass'], report['motionFailures'])
        self.assertTrue(report['footprintPass'], report['footprintFailures'])
        self.assertEqual((report['caseCount'], report['controlCount']), (24, 5))
        self.assertIn('runtime errors', report['limit'])
        self.assertIn('not an initial-clearance PASS', report['limit'])

    def test_both_wall_slide_directions_measure_contact_against_bare_walk(self):
        report=self.report()
        for name in ('male-empty-wall-slide', 'female-full-wall-slide-right'):
            scene=next(c for c in report['cases'] if c['case']==name)
            comparison=scene['slideComparison']
            self.assertEqual(comparison['requestedGait'], 'Run')
            for metrics in (comparison['cart'], comparison['bareWalk']):
                self.assertGreaterEqual(metrics['durationMs'], 500)
                self.assertGreater(metrics['tangent'], .15)
                self.assertGreater(metrics['tangentPerSecond'], 0)

    def test_diagonal_approach_does_not_count_as_sliding_after_contact(self):
        log,_=fixture(self.root, slide_stop=2500)
        report=self.report(log)
        for name in ('male-empty-wall-slide', 'female-full-wall-slide-right'):
            self.assertIn((name, 'wall slide has no accepted tangential movement at contact'), report['motionFailures'])
        self.assertTrue(report['footprintPass'], report['footprintFailures'])

    def test_early_contact_progress_cannot_hide_a_late_wall_slide_freeze(self):
        log,_=fixture(self.root, slide_stop=4200)
        report=self.report(log)
        for name in ('male-empty-wall-slide', 'female-full-wall-slide-right'):
            scene=next(c for c in report['cases'] if c['case']==name)
            self.assertEqual(scene['slideComparison']['cart']['tangent'], 0)
            self.assertIn((name, 'wall slide has no accepted tangential movement at contact'), report['motionFailures'])
        self.assertTrue(report['footprintPass'], report['footprintFailures'])

    def test_bare_diagonal_can_contact_closer_than_frontal_padding(self):
        lines=[]
        for line in self.log.splitlines():
            if 'spec=wall-slide-' in line and ('CONTROL_SAMPLE]' in line and int(re.search(r'elapsed=(\d+)',line)[1])>=3000 or 'CONTROL] COMPLETE' in line):
                line=re.sub(r' x=[^ ]+', ' x=.05', line)
            lines.append(line)
        log='\n'.join(lines)
        report=self.report(log)
        self.assertTrue(report['motionPass'], report['motionFailures'])
        crossing='\n'.join(re.sub(r' x=[^ ]+', ' x=-.003', line) if 'spec=wall-slide-' in line and 'elapsed=3500 ' in line else line for line in lines)
        self.assertIn('native control crosses a closed wall', [reason for _,reason in self.report(crossing)['motionFailures']])
        no_contact='\n'.join(re.sub(r' x=[^ ]+', ' x=3.5', line) if 'spec=wall-slide-' in line else line for line in lines)
        self.assertIn('native Walk has no sustained wall slide at contact', [reason for _,reason in self.report(no_contact)['motionFailures']])

    def test_slide_native_gait_and_rejection_must_continue_at_contact(self):
        name='male-empty-wall-slide'
        no_gait='\n'.join(line.replace('Bob_Run@','Bob_Idle@') if f'case={name} ' in line
            and '[WOOD_BANK_SAMPLE]' in line and 3000<=int(re.search(r'elapsed=(\d+)',line)[1])<5800 else line for line in self.log.splitlines())
        self.assertIn((name, 'native requested fast gait does not progress at wall contact'), self.report(no_gait)['motionFailures'])
        no_rejection='\n'.join(line.replace('blocked=true','blocked=false') if f'case={name} ' in line
            and '[CART_FOOTPRINT_STATE]' in line and 2500<=int(re.search(r'elapsed=(\d+)',line)[1])<5800 else line for line in self.log.splitlines())
        self.assertIn((name, 'wall slide contact never reports normal rejection'), self.report(no_rejection)['motionFailures'])

    def test_slide_controls_require_bare_walk_progress_and_reject_penetration(self):
        for old,new in (('run=false sprint=false bare=true tracks=Bob_Walk', 'run=true sprint=false bare=true tracks=Bob_Walk'),
                        ('bare=true tracks=Bob_Walk', 'bare=false tracks=Bob_Walk'),
                        ('tracks=Bob_Walk=1@1;', 'tracks=Bob_Idle=1@1;'),
                        ('tracks=Bob_Walk=1@1;', 'tracks=Bob_Walk=nan@1;')):
            with self.subTest(new=new):
                try:
                    report=self.report(self.log.replace(old,new))
                except AssertionError:
                    continue
                self.assertTrue(report['motionFailures'])
        control='wall-slide-right'
        log='\n'.join(re.sub(r' y=[^ ]+', ' y=10.5', line) if f'spec={control} ' in line else line for line in self.log.splitlines())
        self.assertIn('native Walk has no sustained wall slide at contact', [reason for _,reason in self.report(log)['motionFailures']])
        log='\n'.join(re.sub(r' x=[^ ]+', ' x=-.1', line) if f'spec={control} ' in line and 'elapsed=3500 ' in line else line for line in self.log.splitlines())
        self.assertIn('native control crosses a closed wall', [reason for _,reason in self.report(log)['motionFailures']])

    def test_wall_corner_and_gap_penetration_is_measured_from_render_matrix(self):
        for name, reason, update in (
            ('male-empty-wall-block', 'wooden mesh enters closed wall', lambda r: r['cart'].__setitem__(14, -2.)),
            ('male-empty-wall-slide', 'wooden mesh enters closed wall', lambda r: r['cart'].__setitem__(14, -2.)),
            ('female-full-wall-slide-right', 'wooden mesh enters closed wall', lambda r: r['cart'].__setitem__(14, -2.)),
            ('male-empty-gait-contact', 'wooden mesh enters closed wall', lambda r: r['cart'].__setitem__(14, -2.)),
            ('male-empty-corner-pivot', 'wooden mesh enters corner wall', lambda r: r['cart'].__setitem__(14, -2.)),
            ('male-empty-passage', 'wooden mesh crosses outside open gap', lambda r: r['cart'].__setitem__(12, 1.)),
            ('male-empty-door-open', 'wooden mesh crosses outside open gap', lambda r: r['cart'].__setitem__(12, 1.))):
            with self.subTest(name=name):
                original=(self.root/'body-clearance.jsonl').read_bytes()
                at=1500 if name.endswith(('passage', 'door-open')) else 4000 if name.endswith('gait-contact') else 2000
                self.mutate_frames(name, lambda r,t: update(r) if t==at else None)
                self.assertIn(reason, [v[1] for v in self.report()['footprintFailures']])
                (self.root/'body-clearance.jsonl').write_bytes(original)

    def test_missing_nonfinite_wrong_sex_slot_and_frame_windows_fail(self):
        path=self.root/'body-clearance.jsonl';original=path.read_bytes()
        mutations=(lambda r,t: r.pop('slotX') if t==2000 else None,
                   lambda r,t: r.__setitem__('slotAngle', float('nan')) if t==2000 else None,
                   lambda r,t: r['cart'].__setitem__(0, float('nan')) if t==2000 else None,
                   lambda r,t: r.__setitem__('female', True) if t==2000 else None,
                   lambda r,t: r.__setitem__('wallTimeMillis', r['wallTimeMillis']+50000),
                   lambda r,t: r.__setitem__('slotX', 100) if t==2000 else None)
        for mutation in mutations:
            with self.subTest(mutation=mutation), self.assertRaises((AssertionError, KeyError)):
                self.mutate_frames('male-empty-wall-block', mutation);self.report()
            path.write_bytes(original)

    def test_mesh_proof_hash_and_native_layout_are_required(self):
        path=self.root/'wood-wheel-mesh-proof.json';original=path.read_text()
        for field, value in (('sha256', 'bad'), ('matchesOriginal', False), ('bytes', 1), ('indices', 3)):
            proof=json.loads(original);proof[field]=value;path.write_text(json.dumps(proof))
            with self.assertRaises(AssertionError): self.report()
        path.write_text(original)
        data=self.root/'WheelbarrowWood.bin';data.write_bytes(data.read_bytes()[:-32])
        with self.assertRaises(AssertionError): self.report()

    def test_controls_diagnostics_stages_finiteness_and_completion_are_strict(self):
        variants=(self.log.replace('ALL_COMPLETE cases=24', 'ALL_COMPLETE cases=16'),
                  '\n'.join(l for l in self.log.splitlines() if 'CONTROL_SAMPLE]' not in l),
                  self.log.replace('front=1.26 ', 'front=nan ', 1),
                  self.log.replace('blocked=false ', 'blocked=none ', 1),
                  self.log.replace('wheelPhase=0.0 ', 'wheelPhase=nan ', 1),
                  '\n'.join(l for l in self.log.splitlines() if 'CART_FOOTPRINT_STATE]' not in l),
                  '\n'.join(l for l in self.log.splitlines() if 'WOOD_RAMP_EVENT]' not in l))
        for log in variants:
            with self.subTest(log=log[:80]), self.assertRaises((AssertionError, ValueError)): self.report(log)

    def test_overlap_requires_real_initial_penetration_and_clear_reverse_exit(self):
        path=self.root/'body-clearance.jsonl';original=path.read_bytes()
        self.mutate_frames('male-empty-overlap', lambda r,t: r['cart'].__setitem__(14, .5) if t==0 else None)
        self.assertIn('initial overlap not demonstrated', [v[1] for v in self.report()['footprintFailures']])
        path.write_bytes(original)
        self.mutate_frames('male-empty-overlap', lambda r,t: r['cart'].__setitem__(14, -2) if t>=9000 else None)
        self.assertIn('overlap never clears wooden mesh', [v[1] for v in self.report()['footprintFailures']])

    def test_overlap_requires_observed_guard_engagement(self):
        name='male-empty-overlap'
        log='\n'.join(line.replace('blocked=true', 'blocked=false') if '[CART_FOOTPRINT_STATE]' in line and f'case={name} ' in line else line
                      for line in self.log.splitlines())
        self.assertIn('overlap forward request never reports rejection', [v[1] for v in self.report(log)['motionFailures']])

    def test_gait_promotion_denial_uses_actual_gait_and_clear_pose(self):
        name='male-empty-gait-contact'
        report=self.report()
        self.assertTrue(report['motionPass'], report['motionFailures'])
        for old,new in (('run=false','run=true'), ('Bob_Idle@','Bob_Run@'),
                        ('direction:1,','direction:-1,'), ('stationaryRoot:false,','stationaryRoot:true,'),
                        ('front=1.26','front=1.62'), ('clear=true','clear=false')):
            log='\n'.join(line.replace(old,new) if f'case={name} ' in line and 'elapsed=' in line
                and 3700<=int(re.search(r'elapsed=(\d+)',line)[1])<6300 else line for line in self.log.splitlines())
            with self.subTest(new=new):
                self.assertIn((name, 'gait promotion at contact was not denied'), self.report(log)['motionFailures'])

    def test_denied_fast_promotion_cannot_accept_walking_movement(self):
        name='male-empty-gait-contact'
        def offset(t): return min(.1, max(0, (t-3700)/20000)) if 3700<=t<6300 else 0
        self.mutate_frames(name, lambda r,t: r.__setitem__('slotY', r['slotY']+offset(t)))
        self.mutate_updates(name, lambda r,t: r.__setitem__('playerY', float(r['playerY'])+offset(t)))
        lines=[]
        for line in self.log.splitlines():
            if '[WOOD_BANK_SAMPLE]' in line and f'case={name} ' in line:
                t=int(re.search(r'elapsed=(\d+)',line)[1])
                line=re.sub(r' y=([^ ]+)', lambda m: ' y='+str(float(m[1])+offset(t)), line)
            lines.append(line)
        self.assertIn((name, 'gait promotion at contact moves actor or wheel'), self.report('\n'.join(lines))['motionFailures'])

    def test_unjustified_wheel_spin_and_dynamic_wrong_reverse_fail(self):
        name='male-empty-wall-block'
        def change(line):
            if '[WOOD_BANK_SAMPLE]' in line and f'case={name} ' in line and 'elapsed=4000 ' in line:
                return re.sub(r'wheelPhase=[^ ]+', 'wheelPhase=2', line)
            return line
        report=self.report('\n'.join(map(change, self.log.splitlines())))
        self.assertIn('wheel spins without wheel-center movement', [v[1] for v in report['motionFailures']])
        log='\n'.join(line.replace('drive=7', 'drive=5') if f'case={name} ' in line else line for line in self.log.splitlines())
        self.assertIn('reverse key is not opposite accepted heading', [v[1] for v in self.report(log)['motionFailures']])

    def test_blocked_passage_and_missing_native_gaits_fail(self):
        name='male-empty-passage'
        path=self.root/'body-clearance.jsonl';original=path.read_bytes()
        budget=self.root/'wood-wheel-native.csv';original_budget=budget.read_bytes()
        def blocked(line):
            if '[WOOD_BANK_SAMPLE]' in line and f'case={name} ' in line:
                return re.sub(r' x=[^ ]+', ' x=1.8', line)
            return line
        self.mutate_frames(name, lambda r,t: r.__setitem__('slotX', 1.8))
        self.mutate_updates(name, lambda r,t: r.__setitem__('playerX', 1.8))
        report=self.report('\n'.join(map(blocked, self.log.splitlines())))
        self.assertIn('opening never crossed west', [v[1] for v in report['motionFailures']])
        path.write_bytes(original)
        budget.write_bytes(original_budget)
        for name, clip in (('male-empty-wall-block', 'Bob_Run@'), ('male-empty-door-closed', 'Bob_WalkBwdNoAim1Hand@')):
            log='\n'.join(line.replace(clip, 'Bob_Idle@') if f'case={name} ' in line else line for line in self.log.splitlines())
            self.assertTrue(any('gait does not progress' in reason for _,reason in self.report(log)['motionFailures']))
        name='male-empty-wall-block'
        self.mutate_frames(name, lambda r,t: r.__setitem__('slotX', 1.5) if t>7000 else None)
        self.mutate_updates(name, lambda r,t: r.__setitem__('playerX', 1.5) if t>7000 else None)
        log='\n'.join(re.sub(r' x=[^ ]+', ' x=1.5', line) if '[WOOD_BANK_SAMPLE]' in line and f'case={name} ' in line
                     and int(re.search(r'elapsed=(\d+)', line)[1])>7000 else line for line in self.log.splitlines())
        self.assertIn('reverse does not escape obstacle', [v[1] for v in self.report(log)['motionFailures']])

    def test_corner_requires_unresolved_held_intent_or_cart_rejection(self):
        name='male-empty-corner-pivot'
        log='\n'.join(line.replace(f'target:{-math.pi/4},', f'target:{math.pi/4},')
            if '[WOOD_BANK_SAMPLE]' in line and f'case={name} ' in line else line for line in self.log.splitlines())
        self.assertIn('corner contact not demonstrated under held input', [v[1] for v in self.report(log)['motionFailures']])

    def test_native_budget_handles_deferred_catchup_but_rejects_actual_jump(self):
        rows=[dict(event='grounding', type='SaucedWheelbarrow.WheelbarrowWood', sequence=i+1, time=t/1000,
                   wallTimeMillis=t, dt=.01, playerX=0 if t<=1000 else .6005859375, playerY=0, actorHeading=0)
              for i,t in enumerate(range(0,12000,100))]
        rows[10]['dt']=.0725333
        rows[11:11]=[dict(rows[10], time=1.014, wallTimeMillis=1014, dt=.0833333, playerX=.279296875),
                      dict(rows[10], time=1.025, wallTimeMillis=1025, dt=.0139766, playerX=.6005859375)]
        for i,row in enumerate(rows): row['sequence']=i+1
        write_updates(self.root, rows)
        native, failures=analyzer.native_updates(self.root, {'catchup':0})
        self.assertEqual(failures, [])
        self.assertEqual(len(native['catchup']), 122)
        # Snapshot/draw duplicates supply no movement budget, even when their dt is large.
        duplicates=[dict(r, event='draw', dt=100) for r in rows]
        write_updates(self.root, [item for pair in zip(rows, duplicates) for item in pair])
        self.assertEqual(analyzer.native_updates(self.root, {'catchup':0})[1], [])
        rows[11]['playerX']=2
        write_updates(self.root, rows)
        self.assertIn(('catchup','position jumps outside native update budget'), analyzer.native_updates(self.root, {'catchup':0})[1])
        rows[11]['playerX']=.279296875;rows[20]['actorHeading']=2
        write_updates(self.root, rows)
        self.assertIn(('catchup','heading snaps outside native update budget'), analyzer.native_updates(self.root, {'catchup':0})[1])

    def test_native_budget_missing_nonfinite_and_nonmonotonic_fail(self):
        path=self.root/'wood-wheel-native.csv';original=path.read_bytes()
        path.unlink()
        with self.assertRaises(FileNotFoundError): self.report()
        path.write_bytes(original)
        for mutate in (lambda r: r.__setitem__('dt','nan'), lambda r: r.__setitem__('dt',-.1),
                       lambda r: r.__setitem__('sequence',0), lambda r: r.__setitem__('time',0)):
            rows=read_updates(self.root);mutate(rows[20]);write_updates(self.root,rows)
            with self.assertRaises(AssertionError): self.report()
            path.write_bytes(original)
        rows=read_updates(self.root)
        write_updates(self.root, [r for r in rows if not 100000<=float(r['wallTimeMillis'])<101000])
        with self.assertRaises(AssertionError): self.report()
        path.write_bytes(original)
        rows=read_updates(self.root)
        write_updates(self.root, [r for r in rows if not 102000<=float(r['wallTimeMillis'])<102600])
        with self.assertRaises(AssertionError): self.report()

    def test_lua_actor_teleport_cannot_hide_behind_native_budget(self):
        # Change only a well-formed actor coordinate, leaving the native stream untouched.
        log='\n'.join(re.sub(r' x=[^ ]+', ' x=999', line) if '[WOOD_BANK_SAMPLE]' in line
            and 'case=male-empty-wall-block ' in line and 'elapsed=2000 ' in line else line for line in self.log.splitlines())
        with self.assertRaisesRegex(AssertionError,'Same-frame slot disagrees'): self.report(log)

    def test_render_slot_may_match_either_actor_bracket_but_both_fields_must_match(self):
        # The renderer has already consumed the next native movement while the earlier Lua row is closer in time.
        before=dict(wall=100,x=0,y=0,heading=0)
        after=dict(wall=133,x=.186,y=0,heading=.2)
        frame=dict(wall=116,slotX=.186,slotY=0,slotAngle=.2+math.pi/2)
        self.assertTrue(analyzer.slot_matches(frame,[before,after],[100,133]))
        # Position matches only the after row, heading only the before row: the pair must fail.
        frame['slotAngle']=math.pi/2
        self.assertFalse(analyzer.slot_matches(frame,[before,after],[100,133]))

    def test_continuous_wheel_support_not_only_static_vbo_vertices(self):
        frame=dict(cart=np.eye(4).ravel().tolist(), slotX=0, slotY=0, slotAngle=0)
        frame['cart']=[76.5,0,0,0,0,76.5,0,0,0,0,76.5,0,0,0,0,1]
        vertices=np.array([[0,0,0,1.]])
        bounds=analyzer.world_bounds(frame, vertices)
        self.assertLess(bounds['minY'], 1.5*76.5*(analyzer.CENTER[2]-analyzer.RADIUS)+1e-10)
        self.assertGreater(bounds['maxX'], 0)

    def test_cli_refuses_overwrite_before_reading_capture(self):
        output=self.root/'report.json';output.write_text('immutable')
        result=subprocess.run([sys.executable, str(SCRIPT), '--profile', str(self.root), '--log', str(self.root/'missing.log'), '--output', str(output)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Refuse to overwrite', result.stderr)
        self.assertEqual(output.read_text(), 'immutable')


if __name__=='__main__': unittest.main()
