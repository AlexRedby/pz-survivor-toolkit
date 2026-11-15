"""Execute real Fitness producer/Policy permissions in the installed game VM."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class FitnessKahluaContractTests(unittest.TestCase):
    def test_native_metadata_accepts_exact_producer_and_rejects_source_role_owner_changes(self):
        game_value, jdk_value = os.environ.get('PZ_GAME'), os.environ.get('PZ_JDK')
        if not game_value or not jdk_value:
            self.skipTest('PZ_GAME and PZ_JDK are required for installed-Kahlua execution')
        game, jdk = Path(game_value), Path(jdk_value)
        jar = game / 'projectzomboid.jar'
        source = ROOT / 'tests/native_queue/fitness/java/KahluaContractChecks.java'
        with tempfile.TemporaryDirectory(prefix='pz-fitness-kahlua-') as temporary:
            subprocess.run([str(jdk / 'bin/javac'), '--release', '25', '-cp', str(jar),
                            '-d', temporary, str(source)], check=True, capture_output=True, text=True, timeout=60)
            result = subprocess.run([str(jdk / 'bin/java'), '-cp', os.pathsep.join((temporary, str(jar))),
                                     'KahluaContractChecks', str(ROOT), str(game)],
                                    capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for variant in ('verified-producer', 'FitnessTestEquipmentSourceChanged',
                        'FitnessTestEquipmentRoleChanged', 'FitnessTestEquipmentOwnerChanged',
                        'old-declaration-line-rejected', 'old-environment-lookups-rejected'):
            self.assertIn('FITNESS_STOCK_KAHLUA_CONTRACT_PASS ' + variant, result.stdout)


if __name__ == '__main__':
    unittest.main()
