import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from tools.queue_checks.snapshot_defaults import default_store


class SnapshotDefaultsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.env = patch.dict(os.environ, {}, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)
        self.home = patch.object(Path, "home", return_value=self.root / "home")
        self.home.start()
        self.addCleanup(self.home.stop)

    def git_result(self, path):
        return subprocess.CompletedProcess([], 0, stdout=str(path) + "\n", stderr="")

    @patch("tools.queue_checks.snapshot_defaults.subprocess.run")
    def test_worktrees_share_common_dir_and_different_repos_do_not(self, run):
        common = self.root / "repo.git"
        run.side_effect = [self.git_result(common), self.git_result(common), self.git_result(self.root / "other.git")]
        first = default_store(self.root / "worktree1")
        self.assertEqual(first, default_store(self.root / "worktree2"))
        self.assertNotEqual(first, default_store(self.root / "worktree3"))
        self.assertEqual(first.name, hashlib.sha256(os.fsencode(str(common))).hexdigest())
        self.assertFalse(first.exists())

    @patch("tools.queue_checks.snapshot_defaults.subprocess.run")
    def test_override_is_canonical_and_bypasses_git(self, run):
        with patch.dict(os.environ, {"PZ_NATIVE_SNAPSHOT_STORE": str(self.root / "a" / ".." / "store")}):
            self.assertEqual(default_store(self.root), self.root / "store")
        run.assert_not_called()
        self.assertFalse((self.root / "store").exists())

    def test_relative_environment_paths_are_rejected(self):
        for name in ("PZ_NATIVE_SNAPSHOT_STORE", "XDG_DATA_HOME"):
            with self.subTest(name=name), patch.dict(os.environ, {name: "relative"}), patch(
                "tools.queue_checks.snapshot_defaults.subprocess.run", return_value=self.git_result(self.root / "git")
            ):
                with self.assertRaisesRegex(ValueError, name):
                    default_store(self.root)

    @patch("tools.queue_checks.snapshot_defaults.subprocess.run", side_effect=subprocess.CalledProcessError(1, "git"))
    def test_export_fallback_and_git_marker_error(self, run):
        project = self.root / "export"
        project.mkdir()
        with patch.dict(os.environ, {"XDG_DATA_HOME": str(self.root / "data")}):
            store = default_store(project)
        self.assertEqual(store.name, hashlib.sha256(os.fsencode(str(project))).hexdigest())
        self.assertEqual(store.parent.parent.parent, self.root / "data")
        (project / ".git").write_text("gitdir: missing")
        with self.assertRaisesRegex(RuntimeError, "Git common directory"):
            default_store(project)
        self.assertFalse(store.exists())


if __name__ == "__main__":
    unittest.main()
