"""Check dependency discovery before build output can be replaced."""
import contextlib
import io
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

BUILD = Path(__file__).resolve().parents[1] / 'build.py'


class BuildPaths(unittest.TestCase):
    def setUp(self):
        self.cache = tempfile.TemporaryDirectory()
        self.addCleanup(self.cache.cleanup)
        self.root = Path(self.cache.name)
        self.script = self.root / 'build.py'
        shutil.copyfile(BUILD, self.script)
        self.sentinel = self.root / 'build/classes/keep.txt'
        self.sentinel.parent.mkdir(parents=True)
        self.sentinel.write_text('previous build')

    def run_build(self, platform, *args):
        stderr = io.StringIO()
        with patch.object(sys, 'platform', platform), patch.object(Path, 'home', return_value=self.root), \
             patch.dict(os.environ, {'ProgramFiles(x86)': str(self.root / 'program files'), 'JAVA_HOME': str(self.root / 'jdk')}), \
             patch.object(sys, 'argv', [str(self.script), *args]), \
             patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0)) as run, \
             contextlib.redirect_stderr(stderr), contextlib.redirect_stdout(io.StringIO()):
            try:
                runpy.run_path(str(self.script), run_name='__main__')
            except SystemExit as error:
                return error.code, stderr.getvalue(), run.call_args_list
        return 0, stderr.getvalue(), run.call_args_list

    def test_platform_defaults_and_missing_game_preserve_output(self):
        defaults = {
            'win32': self.root / 'program files/Steam/steamapps/common/ProjectZomboid',
            'darwin': self.root / 'Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java',
            'linux': self.root / '.steam/steam/steamapps/common/ProjectZomboid/projectzomboid',
        }
        for platform, expected in defaults.items():
            with self.subTest(platform=platform):
                code, error, calls = self.run_build(platform)
                self.assertEqual(code, 2)
                self.assertIn(str(expected), error)
                self.assertIn('projectzomboid.jar', error)
                self.assertIn('--game', error)
                self.assertFalse(calls)
                self.assertEqual(self.sentinel.read_text(), 'previous build')

    def test_custom_game_overrides_default_and_supplies_classpath(self):
        game = self.root / 'custom steam library'
        game.mkdir()
        for name in ('projectzomboid.jar', 'ZombieBuddy.jar'):
            (game / name).touch()
        code, error, calls = self.run_build('win32', '--game', str(game))
        self.assertEqual(code, 0, error)
        command = calls[0].args[0]
        self.assertEqual(command[command.index('-cp') + 1], os.pathsep.join(str(game / name) for name in ('projectzomboid.jar', 'ZombieBuddy.jar')))
        self.assertTrue((self.root / 'build/PZNetworkFix/42/mod.info').is_file())

    def test_missing_zombiebuddy_is_explained_before_compiling(self):
        (self.root / 'projectzomboid.jar').touch()
        code, error, calls = self.run_build('win32', '--game', str(self.root))
        self.assertEqual(code, 2)
        self.assertIn('ZombieBuddy.jar', error)
        self.assertIn('Install the ZombieBuddy loader', error)
        self.assertFalse(calls)
        self.assertTrue(self.sentinel.is_file())

    def test_unknown_platform_requires_explicit_game(self):
        code, error, calls = self.run_build('unknown')
        self.assertEqual(code, 2)
        self.assertIn('--game', error)
        self.assertFalse(calls)


if __name__ == '__main__':
    unittest.main()
