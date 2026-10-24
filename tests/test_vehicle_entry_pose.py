"""Vehicle transitions stay seated and retain the native completion contract.

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
    times = re.findall(r"^\s*(\d+)\s*;\s*[34]\s*;", source[animation.end():], re.M)
    if not times or int(ticks[1]) <= 0:
        raise ValueError("Missing or invalid animation keys in " + name)
    duration = max(map(int, times)) / int(ticks[1])
    if duration <= 0:
        raise ValueError("Empty animation in " + name)
    return duration


class VehicleEntryPose(unittest.TestCase):
    def test_both_states_finish_once_without_blending_from_standing(self):
        for state, finished in STATES.items():
            with self.subTest(state=state):
                node = node_at(MOD, state)
                self.assertEqual(node.tag, "animNode")
                self.assertEqual(node.findtext("m_Name"), "default")
                self.assertEqual(node.findtext("m_AnimName"), "Bob_IdleDriving")
                self.assertEqual(node.findtext("m_Looped"), "false")
                self.assertEqual(float(node.findtext("m_BlendTime")), 0)
                speed = float(node.findtext("m_SpeedScale"))
                self.assertTrue(math.isfinite(speed) and speed > 0)
                self.assertEqual(event_values(node), [("SetVariable", "End", finished)],
                                 "Native maxTime=-1 actions require their exact End signal")
                self.assertFalse(node.findall("m_Conditions"),
                                 "The default fix must also apply to ordinary SP vehicles")


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

    def test_only_pose_blend_and_speed_change_and_native_duration_is_preserved(self):
        changed_fields = {"m_AnimName", "m_BlendTime", "m_SpeedScale"}
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
                replacement_time = clip_duration(self.game, replacement.findtext("m_AnimName")) / float(
                    replacement.findtext("m_SpeedScale"))
                self.assertAlmostEqual(replacement_time, native_time, delta=1e-6,
                                       msg="A seated clip must not change entry/exit duration")


if __name__ == "__main__":
    unittest.main()
