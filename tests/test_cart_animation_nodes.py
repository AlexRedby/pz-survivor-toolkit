"""Keep native walking locomotion and the cart's upper-body pose."""

from pathlib import Path
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
ANIMATIONS = ROOT / "PZSurvivorToolkit/42/media/AnimSets/player"
STATES = {"Idle": "idle", "Walk": "movement", "Run": "run", "Sprint": "sprint"}
SPEEDS = {"Idle": 0.48, "Walk": 1.04, "Run": 1.0, "Sprint": 1.0}
FOOTSTEPS = {"Idle": (), "Walk": (0.20, 0.65), "Run": (0.20, 0.65), "Sprint": (0.15, 0.60)}
HAND_TRANSITIONS = {
    "Idle": {"Walk": ("IdleToWalk", 1.6), "Run": ("WalkToRun", 1.3),
             "Sprint": ("WalkToSprint", 1.0)},
    "Walk": {"Run": ("WalkToRun", 1.3), "Sprint": ("WalkToSprint", 1.3)},
    "Run": {"Sprint": ("WalkToSprint", 1.6)},
    "Sprint": {},
}


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
        expected |= {"ToolkitCartPivot" + mode for mode in ("Walk", "Run", "Sprint")}
        self.assertEqual(set(self.nodes), expected)
        self.assertEqual(len(list(ANIMATIONS.rglob("toolkit_cart_*.xml"))), len(expected))
        for state, folder in STATES.items():
            for side in ("", "Left", "Right"):
                with self.subTest(state=state, side=side):
                    path, node = self.nodes["ToolkitCart" + state + side]
                    self.assertEqual(node.tag, "animNode")
                    self.assertEqual(node.findtext("m_maxTorsoTwist"), "0")
                    self.assertEqual(path.parent.name, "masking" + side.lower() if side else folder)
                    clip = "Bob_Walk" if state == "Walk" and not side else "Bob_Cart_" + state
                    self.assertEqual(node.findtext("m_AnimName"), clip)
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
            self.assertEqual(node.findtext("m_deferredBoneAxis"), "Y" if state == "Walk" else "Z")
            for transition in node.findall("m_Transitions"):
                self.assertIsNone(transition.find("m_AnimName"), "body transitions must not mix extraction axes")
                self.assertIsNone(transition.find("m_speedScale"))
            events = node.findall("m_Events")
            self.assertEqual(tuple(float(item.findtext("m_TimePc")) for item in events), FOOTSTEPS[state])
            for event in events:
                self.assertEqual(event.findtext("m_EventName"), "Footstep")
                self.assertEqual(event.findtext("m_ParameterValue"), state.lower())

    def test_pivot_uses_native_side_and_backward_legs_with_a_separate_root_axis(self):
        for mode in ("Walk", "Run", "Sprint"):
            node = self.nodes["ToolkitCartPivot" + mode][1]
            self.assertIn(("ToolkitCartPivot", "BOOL", "true"), conditions(node))
            self.assertIn(("ToolkitCartMotion", "BOOL", "true"), conditions(node))
            self.assertEqual(node.findtext("m_Scalar"), "ToolkitCartStepX")
            self.assertEqual(node.findtext("m_Scalar2"), "ToolkitCartStepY")
            self.assertEqual(node.findtext("m_deferredBoneAxis"), "Y")
            self.assertEqual(node.findtext("m_maxTorsoTwist"), "0")
            self.assertGreater(int(node.findtext("m_ConditionPriority")), 101)
            clips = {blend.findtext("m_AnimName") for blend in node.findall("m_2DBlends")}
            forward = {"Walk": "Bob_Walk", "Run": "Bob_Run", "Sprint": "Bob_Sprint"}[mode]
            self.assertTrue({forward, "Bob_WalkBwdNoAim1Hand", "Bob_StrafeNoAim_Left", "Bob_StrafeNoAim_Right"} <= clips)
            self.assertFalse(any(clip.startswith("Bob_Cart_") for clip in clips))
            self.assertFalse(node.findall("m_Transitions"), "root transitions cannot extract the cart FBX axis")

    def test_walk_uses_native_speed_and_injury_blending(self):
        node = self.nodes["ToolkitCartWalk"][1]
        self.assertNotIn("x_extends", node.attrib)
        self.assertEqual(node.findtext("m_Scalar"), "WalkInjury")
        self.assertEqual(node.findtext("m_Scalar2"), "WalkSpeed")
        blends = node.findall("m_2DBlends")
        self.assertEqual([(blend.attrib["referenceID"], blend.findtext("m_AnimName"),
                           float(blend.findtext("m_XPos")), float(blend.findtext("m_YPos")),
                           float(blend.findtext("m_SpeedScale"))) for blend in blends], [
            ("1", "Bob_WalkLightLimpR", 0.5, 1.0, 0.8),
            ("2", "Bob_WalkLightLimpL", -0.5, 1.0, 0.8),
            ("3", "Bob_WalkHeavyLimpR", 1.0, 1.0, 0.8),
            ("4", "Bob_WalkHeavyLimpL", -1.0, 1.0, 0.8),
            ("5", "Bob_Walk", 0.0, 1.0, 0.8),
            ("6", "Bob_WalkSlow", 0.0, 0.0, 0.8),
        ])
        self.assertEqual([tuple(triangle.findtext("node" + str(index)) for index in (1, 2, 3))
                          for triangle in node.findall("m_2DBlendTri")],
                         [("2", "4", "6"), ("5", "2", "6"), ("6", "1", "5"), ("6", "3", "1")])

    def test_hands_keep_masks_conditions_and_cart_transition_timing(self):
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
                        for timing in ("m_blendInTime", "m_blendOutTime"):
                            self.assertEqual(actual.findtext(timing), original.findtext(timing))
                        target = original.findtext("m_Target").removeprefix("ToolkitCart")
                        clip = HAND_TRANSITIONS[state].get(target)
                        self.assertEqual(actual.findtext("m_AnimName"), "Bob_Cart_" + clip[0] if clip else None)
                        speed = actual.findtext("m_speedScale")
                        self.assertEqual(float(speed) if speed is not None else None,
                                         clip[1] if clip else None)


if __name__ == "__main__":
    unittest.main()
