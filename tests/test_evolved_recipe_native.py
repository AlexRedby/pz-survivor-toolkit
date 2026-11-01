"""Opt-in no-GUI characterization of the installed evolved-recipe parser.

PZ_GAME=/path/to/game/Java PZ_JDK=/path/to/jdk python3 -m unittest \\
    tests.test_evolved_recipe_native

Compiles a temporary harness against projectzomboid.jar only. No game launch,
installation, Java patch build or user-profile state is needed.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.environ.get('PZ_GAME') and os.environ.get('PZ_JDK'),
                     'PZ_GAME/PZ_JDK required for installed evolved-recipe parser test')
class NativeEvolvedRecipeTests(unittest.TestCase):
    def test_cookable_key_presence_and_item_boolean_contrast(self):
        game = Path(os.environ['PZ_GAME']).resolve()
        jdk = Path(os.environ['PZ_JDK']).resolve()
        executable = '.exe' if os.name == 'nt' else ''
        jar = game / 'projectzomboid.jar'
        self.assertTrue(jar.is_file(), f'Installed game JAR not found: {jar}')
        with tempfile.TemporaryDirectory(prefix='pz-evolved-recipe-native-') as temporary:
            build = Path(temporary)
            home = build / 'home'
            home.mkdir()
            # Prevent inherited agents/options from replacing or instrumenting
            # the native classes under observation, including during javac.
            env = {key: value for key, value in os.environ.items()
                   if key not in ('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS',
                                  '_JAVA_OPTIONS', 'DYLD_INSERT_LIBRARIES')}
            env.update(HOME=str(home), USERPROFILE=str(home))
            compiled = subprocess.run([
                str(jdk / 'bin' / ('javac' + executable)),
                '-cp', str(jar), '-d', str(build),
                str(ROOT / 'tests/native_evolved_recipe/EvolvedRecipeChecks.java'),
            ], cwd=build, env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            result = subprocess.run([
                str(jdk / 'bin' / ('java' + executable)),
                '-Djava.awt.headless=true', f'-Duser.home={home}',
                '-cp', os.pathsep.join((str(build), str(jar))), 'EvolvedRecipeChecks',
            ], cwd=build, env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for row in (
                'Cookable=absent EvolvedRecipe=false Item.IsCookable=false',
                'Cookable=true EvolvedRecipe=true Item.IsCookable=true',
                'Cookable=false EvolvedRecipe=true Item.IsCookable=false',
                'EVOLVED_RECIPE_NATIVE_PASS',
            ):
                self.assertIn(row, result.stdout)


if __name__ == '__main__':
    unittest.main()
