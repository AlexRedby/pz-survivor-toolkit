"""Vehicle transitions move between standing and driving while retaining native completion.

Set PZ_GAME to the game's Java directory to compare with installed native XML
and animation sources. An explicitly configured but unavailable game is an error.
"""

import math
import os
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
ANIMATIONS = Path("media/AnimSets/player-vehicle")
MOD = ROOT / "PZSurvivorToolkit/42"
STATES = {"enter": "EnterAnimationFinished=true", "exit": "ExitAnimationFinished=true"}


def node_at(root, state):
    return ET.parse(root / ANIMATIONS / state / "default.xml").getroot()


def event_values(node):
    return [(event.findtext("m_EventName"), event.findtext("m_Time"),
             event.findtext("m_ParameterValue")) for event in node.findall("m_Events")]


def clip_duration(game, name):
    source = (game / "media/anims_X/Bob" / (name + ".x")).read_text()
    ticks = re.search(r"\bAnimTicksPerSecond\s*\{\s*(\d+)\s*;", source)
    animation = re.search(r"\bAnimationSet\s+" + re.escape(name) + r"\s*\{", source)
    if ticks is None or animation is None:
        raise ValueError("Missing animation timing in " + name)
    # X animation keys use time;component-count;values. Restrict the search to
    # the named AnimationSet so model/mesh declarations cannot supply a time.
    times = re.findall(r"^\s*(\d+)\s*;\s*(?:3|4|16)\s*;", source[animation.end():], re.M)
    if not times or int(ticks[1]) <= 0:
        raise ValueError("Missing or invalid animation keys in " + name)
    duration = max(map(int, times)) / int(ticks[1])
    if duration <= 0:
        raise ValueError("Empty animation in " + name)
    return duration


class VehicleEntryPose(unittest.TestCase):
    def test_reversible_transition_retains_native_completion(self):
        for state, finished in STATES.items():
            with self.subTest(state=state):
                node = node_at(MOD, state)
                self.assertEqual(node.tag, "animNode")
                self.assertEqual(node.findtext("m_Name"), "default")
                self.assertEqual(node.findtext("m_AnimName"), "Bob_ToolkitVehicleEnter")
                self.assertEqual(node.findtext("m_Looped"), "false")
                self.assertEqual(node.findtext("m_AnimReverse"), "true" if state == "exit" else None)
                self.assertEqual(float(node.findtext("m_BlendTime")), 0)
                speed = float(node.findtext("m_SpeedScale"))
                self.assertTrue(math.isfinite(speed) and speed > 0)
                self.assertEqual(event_values(node), [("SetVariable", "End", finished)],
                                 "Native maxTime=-1 actions require their exact End signal")
                self.assertFalse(node.findall("m_Conditions"),
                                 "The default fix must also apply to ordinary SP vehicles")


    def test_authored_clip_starts_standing_and_finishes_in_driving_origin(self):
        # Inspect the actual exported local matrices, recomposing the complete
        # native hierarchy; a renamed seated idle cannot satisfy this contract.
        import sys
        sys.path.insert(0, str(ROOT / "tools"))
        from cart_clip_bake import multiply, template_parts
        clip = (MOD / "media/anims_X/Bob/Bob_ToolkitVehicleEnter.x").read_text()
        _, parents = template_parts(clip)
        animation = clip[clip.index("AnimationSet Bob_ToolkitVehicleEnter") :]
        tracks = {}
        for match in re.finditer(r"Animation\s*\{\s*\{\s*(\w+)\s*\}\s*AnimationKey\s*\{\s*4;\s*\d+;(.*?)\n\s*\}\s*\}", animation, re.S):
            tracks[match[1]] = [(int(key[1]), list(map(float, key[2].split(','))))
                               for key in re.finditer(r"(\d+);16;([^;]+);;", match[2])]
        self.assertEqual(tracks.keys(), parents.keys())
        poses = []
        for endpoint in (0, -1):
            models = {}
            def model(bone):
                if bone not in models:
                    local = tracks[bone][endpoint][1]
                    models[bone] = multiply(model(parents[bone]), local) if parents[bone] else local
                return models[bone]
            poses.append({bone: model(bone) for bone in parents})
        start, end = poses
        self.assertGreater(start["Bip01_Head"][13], .8)
        self.assertGreater(start["Bip01"][13], .5)
        self.assertGreater(start["Bip01_L_Foot"][13], .06)
        for component in end["Bip01"][12:15]:
            self.assertAlmostEqual(component, 0, delta=2e-6)
        self.assertAlmostEqual(end["Bip01_Head"][13], .3127, delta=1e-4)
        self.assertLess(end["Bip01_L_Foot"][13], -.15)
        self.assertGreater(start["Bip01_Head"][13] - end["Bip01_Head"][13], .5)


class NativeVehicleEntryTiming(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get("PZ_GAME")
        if configured is None:
            raise unittest.SkipTest("Set PZ_GAME for native animation timing verification")
        if not configured.strip():
            raise ValueError("PZ_GAME was explicitly set but is empty")
        cls.game = Path(configured).expanduser()
        if not (cls.game / "projectzomboid.jar").is_file():
            raise FileNotFoundError("PZ_GAME must contain projectzomboid.jar: " + str(cls.game))

    def test_only_pose_direction_and_blend_change_and_native_duration_is_preserved(self):
        changed_fields = {"m_AnimName", "m_BlendTime", "m_SpeedScale", "m_AnimReverse"}
        for state in STATES:
            with self.subTest(state=state):
                native = node_at(self.game, state)
                replacement = node_at(MOD, state)
                self.assertEqual(event_values(replacement), event_values(native))
                native_fields = [(field.tag, (field.text or "").strip()) for field in native
                                 if field.tag not in changed_fields and field.tag != "m_Events"]
                replacement_fields = [(field.tag, (field.text or "").strip()) for field in replacement
                                      if field.tag not in changed_fields and field.tag != "m_Events"]
                self.assertEqual(replacement_fields, native_fields)
                native_time = clip_duration(self.game, native.findtext("m_AnimName")) / float(
                    native.findtext("m_SpeedScale"))
                replacement_time = clip_duration(MOD, replacement.findtext("m_AnimName")) / float(
                    replacement.findtext("m_SpeedScale"))
                self.assertAlmostEqual(replacement_time, native_time, delta=1e-6,
                                       msg="The transition must not change native entry/exit duration")


if __name__ == "__main__":
    unittest.main()
