"""Run the real Lua peer placement/coordinator paths without a native launch."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]


class QueueTransferPeersPlacementRuntimeTests(unittest.TestCase):
    def test_centered_placement_and_phase_barriers(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().ProjectRoot = str(ROOT)
        lua.execute((ROOT / "tests/test_queue_transfer_peers_placement.lua").read_text())
