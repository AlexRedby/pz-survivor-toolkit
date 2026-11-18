import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from queue_checks.adapters.loot_demand_drive import census


class RoadCensusTests(unittest.TestCase):
    def test_current_and_archived_unwatched_captures(self):
        status = "schema=1\narm=observe\ncapacity=1\nobjects=0\noverflow=0\nactive=0\n"
        columns = ("type,x,y,z,object_index,sprite,auto_visits,first_auto_ns,first_fill_ns,"
                   "fill_kind,fill_ns,fill_failed,reentries,repeat_fills,active_depth\n")
        log = "[LOOT_ROUTE] START clock=1\n[LOOT_ROUTE] END clock=2\n"
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "loot-demand-drive-census.csv").write_text(columns)
            capture = root / "loot-demand-drive-status.txt"
            for suffix in ("", "watched=0\n"):
                with self.subTest(suffix=suffix):
                    capture.write_text(status + suffix)
                    self.assertEqual(census(root, "observe", log)["window_objects"], [])
            for suffix in ("watched=1\n", "watched=0\nwatched=0\n", "unknown=0\n"):
                with self.subTest(suffix=suffix):
                    capture.write_text(status + suffix)
                    with self.assertRaises(ValueError):
                        census(root, "observe", log)
