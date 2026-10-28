from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks.vehicle_pose_samples import analyze, FULL


def capture(static=False):
    lines=[]
    for case in FULL:
        for phase in ('before', 'after', 'settled'):
            lines.append(f'[VEHICLE_POSE] SAMPLE {case} {phase} ms=1')
        for i in range(11):
            phase=i/10
            name='Bob_IdleDriving' if static else 'ToolkitVehicleTransition'
            height=.3 if static else .3+.8*phase
            lines.append(f'[VEHICLE_POSE] SAMPLE {case} active ms={i+1} Bip01_Head=0,{height},0 track={name},1,{phase},false')
            lines.append(f'[VEHICLE_POSE] RENDER {case} ms={i+1} inVehicle=true local={0 if static else phase},0,0')
    return '\n'.join(lines)


class VehiclePoseSamples(unittest.TestCase):
    def test_requires_real_pose_change_and_rendered_transfer(self):
        self.assertEqual(analyze(capture())[0], [])
        self.assertTrue(analyze(capture(static=True))[0])
        self.assertEqual(analyze(capture(static=True), baseline=True)[0], [])

    def test_a_single_active_sample_cannot_certify_transition(self):
        text='\n'.join(line for line in capture().splitlines() if ' active ' not in line or 'ms=6 ' in line)
        self.assertTrue(analyze(text)[0])

    def test_missing_late_phase_or_settled_boundary_fails(self):
        for remove in ('ms=9 ', ' settled '):
            text='\n'.join(line for line in capture().splitlines() if remove not in line)
            if remove=='ms=9 ': # Remove the whole late portion, not just one sample.
                text='\n'.join(line for line in text.splitlines() if ' active ' not in line or not any(f'ms={n} ' in line for n in (10,11)))
            self.assertTrue(analyze(text)[0])

    def test_static_rendering_cannot_pass_with_valid_pose_motion(self):
        text='\n'.join(line.split('local=')[0]+'local=0,0,0' if ' RENDER ' in line else line for line in capture().splitlines())
        self.assertTrue(analyze(text)[0])

    def test_native_endpoint_teleport_is_not_a_smooth_doorway_transfer(self):
        text='\n'.join(line.split('local=')[0]+('local=1,0,0' if 'ms=11 ' in line else 'local=0,0,0')
                       if ' RENDER ' in line else line for line in capture().splitlines())
        self.assertTrue(analyze(text)[0])

    def test_vertical_root_motion_does_not_prove_doorway_transfer(self):
        text='\n'.join(line.split('local=')[0]+'local=0,'+line.split('local=')[1].split(',')[0]+',0'
                       if ' RENDER ' in line else line for line in capture().splitlines())
        self.assertTrue(analyze(text)[0])


if __name__=='__main__': unittest.main()
