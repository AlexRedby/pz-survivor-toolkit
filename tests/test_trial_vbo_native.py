"""Opt-in test of a built trial and the official release against the installed game's JVM classes."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
import zipfile

INPUTS = ('PZ_GAME', 'PZ_JDK', 'PZ_TRIAL_PACKAGE', 'PZ_OPTIMIZER_ZIP')
SOURCE = Path(__file__).parent / 'optimizer_trial/current/VboQuadParity.java'


@unittest.skipUnless(all(os.environ.get(name) for name in INPUTS), 'requires game, JDK, built package and official ZIP')
class NativeQuadComparison(unittest.TestCase):
    def test_effective_classes_and_emitted_buffers(self):
        game, jdk, package, archive = (Path(os.environ[name]).resolve() for name in INPUTS)
        manifest = json.loads((package / 'current-trial-manifest.json').read_bytes())
        self.assertEqual(hashlib.sha256(archive.read_bytes()).hexdigest(), manifest['release_sha256'])
        with tempfile.TemporaryDirectory(prefix='pz current VBO ') as temp:
            root = Path(temp).resolve()
            classes, runtime = root / 'fixture', root / 'runtime'
            classes.mkdir()
            with zipfile.ZipFile(archive) as release:
                for name, expected in manifest['selected_files'].items():
                    data = release.read(name)
                    self.assertEqual(hashlib.sha256(data).hexdigest(), expected, name)
                    path = runtime / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(data)
            stock = game / 'projectzomboid.jar'
            subprocess.run([jdk / 'bin/javac', '-cp', stock, '-d', classes, SOURCE], check=True)
            profile = root / 'profile.args'
            profile.write_text(''.join(f'-Dpzopt.{key}={value}\n'
                                       for key, value in manifest['runtime']['properties'].items()))
            outputs = {}
            for name, observed_arm, with_upstream in [
                    ('native', 'Control', False), ('optimized', 'Optimized', True), ('missing-agent', 'Optimized', False)]:
                home = root / name
                home.mkdir()
                classpath = [classes, stock]
                vm = []
                if with_upstream:
                    classpath.append(runtime)
                    vm += ['-javaagent:' + str(runtime / manifest['runtime']['path']), '@' + str(profile)]
                vm += ['-javaagent:' + str(package / 'TrialProbe.jar'),
                       '-javaagent:' + str(game / 'ZombieBuddy.jar') + '=config_dir=' + str(home) + ',policy=deny-new',
                       '-Duser.home=' + str(home), '-Dpz.optimizerTrial.arm=' + observed_arm]
                run = subprocess.run([jdk / 'bin/java', *vm, '-cp', os.pathsep.join(map(str, classpath)),
                                      'VboQuadParity', str(with_upstream).lower()], cwd=home,
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60)
                self.assertEqual(run.returncode, 0, run.stdout)
                verified = '[OptimizerTrial] effective classes verified mode=' + observed_arm
                if name == 'missing-agent':
                    self.assertNotIn(verified, run.stdout)
                    self.assertIn('[OptimizerTrial] effective classes failed', run.stdout)
                    continue
                self.assertIn(verified, run.stdout)
                if with_upstream:
                    for marker in manifest['runtime']['ready_markers']:
                        self.assertIn(marker, run.stdout)
                result = re.search(r'^VBO_QUAD_PARITY ([0-9a-f]{64}) fast=(true|false)$', run.stdout, re.M)
                self.assertIsNotNone(result, run.stdout)
                self.assertEqual(result[2], str(with_upstream).lower())
                outputs[name] = result[1]
            self.assertEqual(outputs['native'], outputs['optimized'])
