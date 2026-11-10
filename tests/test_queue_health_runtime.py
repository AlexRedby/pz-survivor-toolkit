"""Behavioral coverage of shipped health fixture Lua; no game/runtime claim."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
HEALTH = ROOT / "tests" / "native_queue" / "health"


class HealthRuntimeTests(unittest.TestCase):
    def execute(self, path):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().arg = lua.table_from([str(HEALTH)])
        lua.globals().script = str(path)
        # Suppress diagnostic fixture receipts while keeping Lua assertion failures.
        lua.execute("print=function()end; assert(loadfile(script))()")

    def test_clinical_resources_and_scenario_lifecycle(self):
        self.execute(HEALTH / "check.lua")

    def test_centered_settled_placement_protocol(self):
        self.execute(ROOT / "tests" / "test_queue_health_placement.lua")


if __name__ == "__main__":
    unittest.main()
