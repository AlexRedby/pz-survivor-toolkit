"""Exercise the macOS Host launcher without a Java VM or a game window."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

LAUNCHER = Path(__file__).resolve().parents[1] / 'start-host.command'


class MacHostLauncher(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.game = self.root / "custom Steam library's/Project Zomboid.app/Contents/Java"
        self.game.mkdir(parents=True)
        for name in ('projectzomboid.jar', 'ZombieBuddy.jar'):
            (self.game / name).touch()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        uname = self.bin / 'uname'
        uname.write_text('#!/bin/sh\nif [ "$1" = -s ]; then echo Darwin; else echo "$PZ_TEST_ARCH"; fi\n')
        uname.chmod(0o755)
        for runtime in ('jre-aarch64', 'jre-x86_64'):
            java = self.game.parent / f'PlugIns/{runtime}/Contents/Home/bin/java'
            java.parent.mkdir(parents=True)
            java.write_text('#!/bin/sh\nprintf "%s\\n" "$0" "$PWD" "$JDK_JAVA_OPTIONS" "$JAVA_TOOL_OPTIONS" "$_JAVA_OPTIONS" "$SteamAppId" "$SteamGameId" "$@"\n/bin/sh -c \'printf "child=%s\\n" "$JDK_JAVA_OPTIONS"\'\n')
            java.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        PZ_TEST_ARCH='arm64', JDK_JAVA_OPTIONS='-Dexisting=1 -Dpz.vehicle.trace=true',
                        JAVA_TOOL_OPTIONS='-Dtool=2', _JAVA_OPTIONS='-Dlegacy=3')

    def run_launcher(self, *args, **env):
        return subprocess.run(['/bin/bash', str(LAUNCHER), *args],
                              env=dict(self.env, **env), capture_output=True, text=True)

    def test_space_path_both_architectures_and_inherited_environment(self):
        expected_agent = f'-Dexisting=1 -Dpz.vehicle.trace=true -javaagent:"{self.game}/ZombieBuddy.jar"'
        for arch, runtime in (('arm64', 'jre-aarch64'), ('x86_64', 'jre-x86_64')):
            with self.subTest(arch=arch):
                result = self.run_launcher(str(self.game), PZ_TEST_ARCH=arch)
                self.assertEqual(result.returncode, 0, result.stderr)
                lines = result.stdout.splitlines()[1:]
                self.assertIn(f'/PlugIns/{runtime}/Contents/Home/bin/java', lines[0])
                self.assertEqual(lines[1:7], [str(self.game), expected_agent, '-Dtool=2', '-Dlegacy=3', '108600', '108600'])
                self.assertEqual(lines[-1], 'child=' + expected_agent)
                self.assertIn('-XstartOnFirstThread', lines)
                self.assertIn('--enable-native-access=ALL-UNNAMED', lines)
                self.assertEqual(lines[-4:-1], ['-cp', 'projectzomboid.jar', 'zombie.gameStates.MainScreenState'])
        self.assertEqual(self.env['JDK_JAVA_OPTIONS'], '-Dexisting=1 -Dpz.vehicle.trace=true')

    def test_default_steam_path(self):
        default = self.root / 'Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java'
        default.parent.mkdir(parents=True)
        default.symlink_to(self.game, target_is_directory=True)
        result = self.run_launcher(HOME=str(self.root), JDK_JAVA_OPTIONS='')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('-javaagent:', result.stdout)

    def test_existing_agent_is_refused_in_each_jvm_environment(self):
        for variable in ('JDK_JAVA_OPTIONS', 'JAVA_TOOL_OPTIONS', '_JAVA_OPTIONS'):
            for agent in ('-javaagent:ZombieBuddy.jar', '-agentpath:/game/zbNative.dll'):
                with self.subTest(variable=variable, agent=agent):
                    result = self.run_launcher(str(self.game), **{variable: agent})
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('avoid loading it twice', result.stderr)
                    self.assertNotIn('child=', result.stdout)

    def test_missing_inputs_fail_before_runtime(self):
        (self.game / 'ZombieBuddy.jar').unlink()
        result = self.run_launcher(str(self.game))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Missing ZombieBuddy.jar', result.stderr)
        self.assertNotIn('child=', result.stdout)


if __name__ == '__main__':
    unittest.main()
