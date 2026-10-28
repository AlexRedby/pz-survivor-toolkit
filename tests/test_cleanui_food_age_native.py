"""Opt-in Workshop CleanUI/native Food regression against the shipped Java correction."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'JavaPatches'))
from build import require_current_patch_jar


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


@unittest.skipUnless(os.environ.get('PZ_NATIVE_FOOD_AGE_CHECK') == '1',
                     'opt-in native Food check: PZ_NATIVE_FOOD_AGE_CHECK=1, PZ_GAME, PZ_JDK, PZ_CLEANUI_PANE, PZ_PATCH_JAR')
class NativeCleanUiFoodAgeTests(unittest.TestCase):
    def test_current_source_starves_tail_and_shipped_patch_preserves_native_age(self):
        keys = ('PZ_GAME', 'PZ_JDK', 'PZ_CLEANUI_PANE', 'PZ_PATCH_JAR')
        missing = [key for key in keys if not os.environ.get(key)]
        self.assertFalse(missing, 'Native Food check opted in but required inputs are missing: ' + ', '.join(missing))
        game, jdk, original_pane, patch_jar = (Path(os.environ[key]).expanduser().resolve() for key in keys)
        jar = game / 'projectzomboid.jar'
        for path in (jar, jdk / 'bin/java', jdk / 'bin/javac', original_pane, patch_jar):
            self.assertTrue(path.is_file(), 'Required native Food input is missing: ' + str(path))
        require_current_patch_jar(patch_jar, ROOT / 'JavaPatches')
        original_hash = sha256(original_pane)
        classpath = os.pathsep.join(map(str, (jar, patch_jar)))
        java_source = ROOT / 'tests/native_food_age/FoodAgeChecks.java'
        environment = {key: value for key, value in os.environ.items()
                       if key not in ('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS', 'DYLD_INSERT_LIBRARIES')}
        with tempfile.TemporaryDirectory(prefix='pz-food-age-regression-') as directory:
            private = Path(directory)
            compiled = subprocess.run([str(jdk / 'bin/javac'), '--release', '25', '-cp', classpath,
                                       '-d', str(private), str(java_source)], cwd=game, env=environment,
                                      capture_output=True, text=True, timeout=30)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            result = subprocess.run([str(jdk / 'bin/java'), '-Djava.awt.headless=true', '-Dzomboid.steam=0',
                                     '-cp', str(private) + os.pathsep + classpath, 'FoodAgeChecks',
                                     str(original_pane), str(private / 'cache')],
                                    cwd=game, env=environment, capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            results = [json.loads(line.removeprefix('FOOD_AGE_RESULT ')) for line in result.stdout.splitlines()
                       if line.startswith('FOOD_AGE_RESULT ')]
            summaries = [json.loads(line.removeprefix('FOOD_AGE_NATIVE_PASS ')) for line in result.stdout.splitlines()
                         if line.startswith('FOOD_AGE_NATIVE_PASS ')]
            self.assertEqual(len(summaries), 1, result.stdout + result.stderr)
            self.assertEqual(summaries[0]['cases'], 27)
            self.assertEqual({(row['fixed'], row['size'], row['container']) for row in results},
                             {(fixed, size, kind) for fixed in (False, True)
                              for size in (200, 10000) for kind in ('crate', 'fridge')})
            self.assertEqual(len(results), 8)
            for row in results:
                self.assertEqual(row['helper_events'], int(row['fixed']))
                self.assertEqual(row['tail_after_helper'] == row['tail_after_catchup'], row['fixed'])
            self.assertEqual(sha256(original_pane), original_hash, 'Workshop input changed')
            print(json.dumps({'native_food_age': summaries[0], 'observations': results,
                              'provenance': {'game_jar_sha256': sha256(jar), 'probe_sha256': sha256(java_source),
                                             'patch_jar_sha256': sha256(patch_jar),
                                             'input_sha256': original_hash}}))


if __name__ == '__main__':
    unittest.main()
