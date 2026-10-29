"""Scoped starter staging and executable Lua lane-selection contracts."""
from pathlib import Path
import shutil
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters.optimizer_benchmark import route_source


class ApproachLaneTests(unittest.TestCase):
    def setUp(self):
        self.original = (ROOT / 'tests/driving_benchmark/mods/PZDrivingBench/42/media/lua/shared/DrivingBenchFixture.lua').read_text()

    def test_muldraugh_retains_original_search_and_only_wraps_new_creation(self):
        staged = route_source(self.original, 'muldraugh-extinction')
        self.assertEqual(staged.count('local function originalSpawnSquare(player)'), 1)
        self.assertEqual(staged.count('local function spawnSquare(player)'), 1)
        before = self.original.split('local function spawnSquare(player)')[1].split('local function initialize(vehicle)')[0]
        expected = before.replace('{{0,1,"N",180},{1,0,"E",90}}', '{{0,1,"N",180}}')
        self.assertIn('local function originalSpawnSquare(player)' + expected, staged)
        self.assertIn('options.approach_tiles or 40', staged)
        self.assertIn('START_X=10594, START_Y=10650', staged)
        after = self.original.split('local function initialize(vehicle)')[1].replace('Base.CarNormal', 'Base.SportsCar')
        self.assertEqual(staged.split('local function initialize(vehicle)')[1], after)

    def test_other_scenarios_do_not_gain_lane_selection(self):
        for scenario in ('highway', None, 'west-point-extinction'):
            with self.subTest(scenario=scenario):
                staged = route_source(self.original, scenario)
                self.assertNotIn('DrivingApproachLane', staged)
                self.assertNotIn('originalSpawnSquare', staged)
        west = route_source(self.original, 'west-point-extinction')
        self.assertIn('return street(F.START_X,F.START_Y), "E", 90', west)

    def test_changed_muldraugh_boundary_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'boundary changed'):
            route_source(self.original.replace('{{0,1,"N",180},{1,0,"E",90}}', '{{0,1,"N",180}}'), 'muldraugh-extinction')

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT is not installed')
    def test_executable_selector_and_saved_receipt(self):
        base = ROOT / 'tests/native_queue/optimizer-benchmark'
        result = subprocess.run([shutil.which('luajit'), str(base / 'checks/approach_lane.lua'), str(base / 'ApproachLane.lua')],
                                cwd=ROOT, text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('APPROACH_LANE_CHECKS_PASS', result.stdout)


if __name__ == '__main__':
    unittest.main()
