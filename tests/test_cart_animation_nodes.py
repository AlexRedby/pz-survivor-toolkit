"""Keep the cart's body and prop tracks synchronized without changing locomotion."""

from pathlib import Path
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
ANIMATIONS = ROOT / "PZSurvivorToolkit/42/media/AnimSets/player"
STATES = {"Idle": "idle", "Walk": "movement", "Run": "run", "Sprint": "sprint"}
SPEEDS = {"Idle": 0.48, "Walk": 1.04, "Run": 1.0, "Sprint": 1.0}
FOOTSTEPS = {"Idle": (), "Walk": (0.20, 0.65), "Run": (0.20, 0.65), "Sprint": (0.15, 0.60)}


def signature(element):
    return element.tag, (element.text or "").strip(), tuple(map(signature, element))


def conditions(node):
    return {(item.findtext("m_Name"), item.findtext("m_Type"), item.findtext("m_Value"))
            for item in node.findall("m_Conditions")}


class CartAnimationNodes(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.nodes = {node.findtext("m_Name"): (path, node)
                     for path in ANIMATIONS.rglob("toolkit_cart_*.xml")
                     for node in [ET.parse(path).getroot()]}

    def test_all_tracks_are_opt_in_and_keep_existing_clip_timing(self):
        expected = {"ToolkitCart" + state + side for state in STATES for side in ("", "Left", "Right")}
        self.assertEqual(set(self.nodes), expected)
        self.assertEqual(len(list(ANIMATIONS.rglob("toolkit_cart_*.xml"))), len(expected))
        for state, folder in STATES.items():
            for side in ("", "Left", "Right"):
                with self.subTest(state=state, side=side):
                    path, node = self.nodes["ToolkitCart" + state + side]
                    self.assertEqual(node.tag, "animNode")
                    self.assertEqual(path.parent.name, "masking" + side.lower() if side else folder)
                    self.assertEqual(node.findtext("m_AnimName"), "Bob_Cart_" + state)
                    self.assertEqual(float(node.findtext("m_SpeedScale")), SPEEDS[state])
                    self.assertEqual(node.findtext("m_SyncTrackingEnabled"), "true")
                    self.assertIn(("ToolkitCartMotion", "BOOL", "true"), conditions(node))
                    self.assertEqual(node.findtext("m_Priority"), "10")
                    self.assertGreater(int(node.findtext("m_ConditionPriority")), 100 if not side else 10)
                    self.assertIsNone(node.find("m_speedScale"), "wrong case silently loses the speed setting")
                    self.assertIsNone(node.find("m_SpeedScaleVariable"))
                    self.assertIsNone(node.find("m_useDeferredMovement"))

    def test_body_keeps_injury_guards_and_original_footsteps_only(self):
        for state in STATES:
            node = self.nodes["ToolkitCart" + state][1]
            self.assertIn(("Weapon", "STRING", "cart"), conditions(node))
            if state in ("Walk", "Run"):
                self.assertIn(("WalkInjury", "LESS", "0.15"), conditions(node))
                self.assertIn(("WalkInjury", "GTR", "-0.15"), conditions(node))
            if state == "Walk":
                self.assertIn(("isMoving", "BOOL", "true"), conditions(node))
            self.assertEqual(node.findtext("m_deferredBoneAxis"), "Z")
            events = node.findall("m_Events")
            self.assertEqual(tuple(float(item.findtext("m_TimePc")) for item in events), FOOTSTEPS[state])
            for event in events:
                self.assertEqual(event.findtext("m_EventName"), "Footstep")
                self.assertEqual(event.findtext("m_ParameterValue"), state.lower())

    def test_hands_keep_masks_conditions_and_matching_transition_clips(self):
        for state in STATES:
            body = self.nodes["ToolkitCart" + state][1]
            for side, prop in (("Left", "Bip01_Prop2"), ("Right", "Bip01_Prop1")):
                with self.subTest(state=state, side=side):
                    node = self.nodes["ToolkitCart" + state + side][1]
                    checks = conditions(node)
                    self.assertIn((side + "HandMask", "STRING", "holdingcart" + side.lower()), checks)
                    self.assertIn(("isMoving", "BOOL", "false" if state == "Idle" else "true"), checks)
                    if state != "Idle":
                        for variable in ("Aim", "sneaking"):
                            self.assertIn((variable, "BOOL", "false"), checks)
                        self.assertIn(("isRunning", "BOOL", "true" if state == "Run" else "false"), checks)
                        self.assertIn(("isSprinting", "BOOL", "true" if state == "Sprint" else "false"), checks)
                    self.assertEqual(node.findtext("m_BlendTime"), body.findtext("m_BlendTime"))
                    self.assertEqual(node.findall("m_Events"), [], "hand tracks must not duplicate footstep events")
                    weights = {item.findtext("boneName"): item for item in node.findall("m_SubStateBoneWeights")}
                    self.assertEqual(weights[prop].findtext("weight"), "1.00")
                    self.assertNotIn("Bip01_Prop1" if side == "Left" else "Bip01_Prop2", weights)
                    if state in ("Walk", "Run"):
                        for bone in ("Bip01_Spine", "Bip01_Spine1"):
                            self.assertEqual(weights[bone].findtext("includeDescendants"), "false")
                        self.assertIn("Bip01_" + side[0] + "_Clavicle", weights)
                    else:
                        self.assertEqual(weights["Bip01"].findtext("weight"), "0.00")
                    root_transitions = body.findall("m_Transitions")
                    hand_transitions = node.findall("m_Transitions")
                    self.assertEqual(len(hand_transitions), 3)
                    for original, actual in zip(root_transitions, hand_transitions):
                        self.assertEqual(actual.findtext("m_Target"), original.findtext("m_Target") + side)
                        self.assertIn(actual.findtext("m_Target"), self.nodes)
                        self.assertEqual([signature(item) for item in actual if item.tag != "m_Target"],
                                         [signature(item) for item in original if item.tag != "m_Target"])


if __name__ == "__main__":
    unittest.main()
