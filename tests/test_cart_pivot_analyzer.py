"""Reject false completion, moving wheel and stale native animation in the focused bank."""
import importlib.util
import math
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
SPEC=importlib.util.spec_from_file_location('pivot_analyzer', ROOT/'tests/native_queue/contributions/wooden_cart_motion/analyze-pivot.py')
analyzer=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(analyzer)


def evidence(side='left'):
    name='male-empty-pivot-'+side
    left=side=='left'
    sign=-1 if left else 1
    pivot_drive,moving_drive=(2,5) if left else (3,8)
    start=100000
    phases=[('rest',0,0),('pivot',700,pivot_drive),('pivot-complete',3700,pivot_drive),
            ('released',3700,0),('forward-exit',5100,1),('moving-entry',6200,moving_drive),('final-rest',7200,0),('clip-complete',8200,0)]
    def heading(t): return sign*(math.pi*min(1,max(0,(t-700)/3000))+.3*min(1,max(0,(t-6200)/1000)))
    lines=['[WOOD_BANK] RUN_STARTED',f'[WOOD_BANK] CASE {name} attempt=0 wall={start}']
    for label,t,drive in phases:
        accumulated=sign*math.pi*min(1,max(0,(t-700)/3000))
        lines.append(f'[CART_PIVOT_EVENT] case={name} wall={start+t} elapsed={t} event={label} drive={drive} accumulated={accumulated} heading={heading(t)}')
    wheel=[];body=[];grip=[]
    for t in range(0,8201,100):
        active=[(label,drive) for label,stamp,drive in phases if stamp<=t][-1]
        stage,drive=active
        pivot=700<=t<3700
        h=heading(t)
        moving=max(0,min(2.1,(t-5100)/1000))
        x,y=1-math.cos(h)+moving,-math.sin(h)
        clip='Bob_StrafeNoAim_'+('Left' if left else 'Right')
        tracks=f'{clip}@1/{((t-700)/1000)%1}/1;' if pivot else ''
        state=f'heading:{h},target:{h+.1},stationary:{str(pivot).lower()},stationaryRoot:{str(pivot).lower()},actualDistance:0,axle:1,rootTracks:{tracks}'
        lines.append(f'[WOOD_BANK_SAMPLE] case={name} wall={start+t} elapsed={t} x={x} y={y} run=false sprint=false drive={drive} requestedGait=0 stepX=0 stepY=0 bank=0 stationary={state} tracks=')
        wheel.append(dict(wallTimeMillis=start+t,wheelX=1,wheelY=0,phase=0))
        matrix=[0.0]*16;matrix[0]=matrix[5]=matrix[10]=matrix[15]=1
        matrix[13]=.1*abs(math.sin(t/200)) if pivot else 0
        cart=[0.0]*16;cart[13]=.008
        body.append(dict(wallTimeMillis=start+t,female=False,cart=cart,bones={f'Bip01_{s}_Foot':matrix.copy() for s in 'LR'}))
        grip.append(dict(wallTimeMillis=start+t,result=True))
    lines.extend([f'[WOOD_BANK] COMPLETE {name} wall={start} file=test.mp4 frames=246 seconds=8.2','[WOOD_BANK] ALL_COMPLETE cases=1'])
    return '\n'.join(lines),wheel,body,grip,[name]


class PivotAnalyzerTests(unittest.TestCase):
    def test_both_directions_measure_yaw_and_real_track_cadence(self):
        for side in ('left','right'):
            report=analyzer.analyze(*evidence(side))
            self.assertTrue(report['motionPass'],report['failures'])
            self.assertAlmostEqual(abs(report['cases'][0]['accumulatedYawDegrees']),180)
            self.assertFalse(report['animationEquivalencePass'])
            signed_yaw=report['cases'][0]['accumulatedYawDegrees']
            self.assertLess(signed_yaw,0) if side=='left' else self.assertGreater(signed_yaw,0)

    def test_only_same_tick_precommand_sample_is_exempt(self):
        log,w,b,g,n=evidence('left')
        def alter_sample(at):
            return '\n'.join(line.replace('drive=2 ', 'drive=0 ').replace('stationary:true', 'stationary:false')
                if '[WOOD_BANK_SAMPLE]' in line and f'elapsed={at} ' in line else line for line in log.splitlines())
        self.assertTrue(analyzer.analyze(alter_sample(700),w,b,g,n)['motionPass'])
        self.assertFalse(analyzer.analyze(alter_sample(800),w,b,g,n)['motionPass'])

    def test_left_key_is_independent_of_negative_yaw_sign(self):
        log,w,b,g,n=evidence('left')
        with self.assertRaisesRegex(AssertionError,'Wrong relative control sequence'):
            analyzer.analyze(log.replace('drive=2 ', 'drive=3 '),w,b,g,n)

    def test_fixed_time_marker_cannot_fake_180(self):
        log,w,b,g,n=evidence()
        log=log.replace('event=pivot-complete drive=2 accumulated=-3.141592653589793','event=pivot-complete drive=2 accumulated=-1.57')
        self.assertFalse(analyzer.analyze(log,w,b,g,n)['motionPass'])

    def test_native_clip_time_must_progress(self):
        log,w,b,g,n=evidence()
        import re
        log=re.sub(r'(@1/)[^/;]+(/1;)',r'\g<1>0\g<2>',log)
        self.assertFalse(analyzer.analyze(log,w,b,g,n)['motionPass'])

    def test_wheel_and_released_feet_are_observed(self):
        log,w,b,g,n=evidence()
        w[20]['wheelX']=1.2
        self.assertFalse(analyzer.analyze(log,w,b,g,n)['motionPass'])
        log,w,b,g,n=evidence()
        b[48]['bones']['Bip01_L_Foot'][12]=.2
        self.assertFalse(analyzer.analyze(log,w,b,g,n)['motionPass'])

    def test_missing_phase_and_probe_window_are_rejected(self):
        log,w,b,g,n=evidence()
        with self.assertRaisesRegex(AssertionError,'phase-complete'):
            analyzer.analyze('\n'.join(line for line in log.splitlines() if 'event=pivot-complete ' not in line),w,b,g,n)
        with self.assertRaisesRegex(AssertionError,'Incomplete body'):
            analyzer.analyze(log,w,b[10:],g,n)

    def test_vertical_foot_range_uses_model_y_not_fore_aft_z(self):
        rows=[]
        for y,z in ((.06,-.08),(.09,.2),(.07,-.3)):
            matrix=[0.0]*16;matrix[13]=y;matrix[14]=z
            rows.append({'bones':{f'Bip01_{side}_Foot':matrix.copy() for side in 'LR'}})
        summary=analyzer.foot_summary(rows)
        for foot in summary.values():
            self.assertAlmostEqual(foot['verticalRange'],.03)
            self.assertNotIn('sampledLiftPeaks',foot)

    def test_adapter_registers_eight_exact_scene_ids(self):
        import sys
        sys.path.insert(0,str(ROOT/'tools'))
        from queue_checks.adapters import carts
        self.assertEqual(carts.SP_CASES['pivot'],('scenario-pivot.lua',8))
        self.assertEqual(carts.scene_names('pivot'),analyzer.SCENES)


if __name__=='__main__': unittest.main()
