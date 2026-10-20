"""The held effort pose must plant both feet without root travel or reversed knees."""
import json
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


class BraceClipTests(unittest.TestCase):
    def test_stance_has_no_loop_motion_and_keeps_supported_forward_knees(self):
        frames = json.loads((ROOT / 'assets/animations/wood_cart_brace.json').read_text())
        pose = frames[0]['bones']
        self.assertEqual(pose, frames[-1]['bones'], 'held effort cannot introduce a looping bob')
        for side in ('L', 'R'):
            hip, knee, ankle, toe = [pose[f'Bip01_{side}_{part}'][12:15]
                                      for part in ('Thigh', 'Calf', 'Foot', 'Toe0')]
            self.assertLess(abs(toe[1]), .001, 'toe must stay at the native idle floor')
            fraction = (hip[1] - knee[1]) / (hip[1] - ankle[1])
            self.assertLess(knee[2], hip[2] + fraction * (ankle[2] - hip[2]),
                            'knee must bend forwards, not behind the hip-ankle line')
        self.assertLess(pose['Bip01_L_Foot'][14], pose['Bip01_R_Foot'][14] - .08)

    def test_native_brace_nodes_do_not_add_movement_or_step_events(self):
        for folder in ('idle', 'movement', 'run', 'sprint', 'maskingleft', 'maskingright'):
            node = ET.parse(ROOT / f'PZSurvivorToolkit/42/media/AnimSets/player/{folder}/toolkit_wood_cart_brace.xml').getroot()
            self.assertEqual(node.findtext('m_AnimName'), 'Toolkit_WoodCartBrace')
            self.assertEqual(node.findtext('m_useDeferredMovement'), 'false')
            self.assertFalse(node.findall('m_Events'))
            self.assertGreater(float(node.findtext('m_BlendTime')), .1)
            conditions = {(c.findtext('m_Name'), c.findtext('m_Value')) for c in node.findall('m_Conditions')}
            self.assertIn(('ToolkitCartBrace', 'true'), conditions)
            self.assertIn(('ToolkitCartMotion', 'true'), conditions)


if __name__ == '__main__':
    unittest.main()
