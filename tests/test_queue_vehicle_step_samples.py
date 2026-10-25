"""A changing pose alone must not certify a planted-foot step."""
from pathlib import Path
import math
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from queue_checks.vehicle_step_samples import analyze
from queue_checks.vehicle_pose_samples import FULL


def capture():
    lines=[]
    for case in FULL:
        entering=case.startswith('enter-')
        lead='R' if case.endswith('driver') else 'L'
        trail='L' if lead=='R' else 'R'
        lines.append(f'[VEHICLE_POSE] CONTACT_BASE {case} LY=0 RY=0')
        for i in range(4,41):
            t=i/40
            def step(a,b): return max(0,min(1,(t-a)/(b-a)))
            if entering:
                a=step(.1,.36);b=step(.52,.9)
                ankles={lead:(.1+.2*a,.12*math.sin(math.pi*a),0),trail:(-.1+.4*b,.12*math.sin(math.pi*b),0)}
                pelvis=(.35*t,.45-.15*t,0)
            else:
                a=step(.08,.4);b=step(.42,.86)
                ankles={lead:(.3-.2*a,.12*math.sin(math.pi*a),0),trail:(.3-.4*b,.12*math.sin(math.pi*b),0)}
                pelvis=(.35*(1-t),.3+.15*t,0)
            bones={'Bip01_Pelvis':pelvis,'Bip01_Head':(pelvis[0],pelvis[1]+.3,0)}
            for side in ('L','R'):
                hip=(pelvis[0]+(.05 if side=='L' else -.05),pelvis[1],0)
                ankle=ankles[side]
                dx,dy=ankle[0]-hip[0],ankle[1]-hip[1]
                distance=math.hypot(dx,dy)
                height=math.sqrt(.35**2-(distance/2)**2)
                knee=((hip[0]+ankle[0])/2-height*dy/distance,(hip[1]+ankle[1])/2+height*dx/distance,0)
                bones['Bip01_'+side+'_Thigh']=hip;bones['Bip01_'+side+'_Calf']=knee;bones['Bip01_'+side+'_Foot']=ankle
            text=' '.join(name+'='+','.join(map(str,p)) for name,p in bones.items())
            lines.append(f'[VEHICLE_POSE] BONES {case} ms={i} phase={t} {text} skins=2 skinError=0.000001')
    return '\n'.join(lines)


class VehicleStepSamples(unittest.TestCase):
    def test_accepts_observed_contacts_with_preserved_bone_lengths(self):
        self.assertEqual(analyze(capture())[0],[])

    def test_missing_phase_and_palette_data_fail(self):
        self.assertTrue(analyze('')[0])
        self.assertTrue(analyze('\n'.join(line for line in capture().splitlines() if 'phase=0.5 ' in line))[0])

    def test_body_alone_cannot_certify_clothing(self):
        self.assertTrue(analyze(capture().replace('skins=2','skins=1'))[0])

    def test_pre_action_takeoff_is_required(self):
        self.assertTrue(analyze('\n'.join(line for line in capture().splitlines() if 'CONTACT_BASE' not in line))[0])

    def test_disagreement_between_body_and_clothing_fails(self):
        self.assertTrue(analyze(capture().replace('skinError=0.000001','skinError=0.03'))[0])

    def test_every_frame_moving_feet_cannot_pass_as_a_step(self):
        import re
        def drift(match):
            x,y,z=map(float,match[2].split(','))
            return match[1]+f'{x+.02*float(self.phase)},{y},{z}'
        lines=[]
        for line in capture().splitlines():
            if 'CONTACT_BASE' in line:
                lines.append(line);continue
            self.phase=re.search(r'phase=([^ ]+)',line)[1]
            lines.append(re.sub(r'(Bip01_[LR]_Foot=)([^ ]+)',drift,line))
        self.assertTrue(analyze('\n'.join(lines))[0])

    def test_flat_foot_slide_has_no_swing_clearance(self):
        import re
        text=re.sub(r'(Bip01_[LR]_Foot=[^, ]+),[^, ]+,([^ ]+)',r'\1,0,\2',capture())
        self.assertTrue(analyze(text)[0])


if __name__=='__main__': unittest.main()
