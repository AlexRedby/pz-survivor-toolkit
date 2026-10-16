import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks.adapters import animal_fixes


class AnimalFixAdapterTests(unittest.TestCase):
    def test_markers_and_screenshots_are_required(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'client1').mkdir()
            log = root / 'client1-launch.log'
            log.write_text(''.join('[QUEUE_TEST] PASS ' + case + '\n' for case in animal_fixes.CASES)
                           + '[ANIMAL_FIX_TEST] COMPLETE\n')
            self.assertTrue(animal_fixes.verify(root, {}, {})['issues'])
            for name in animal_fixes.SHOTS:
                (root / 'client1' / name).write_bytes(b'\x89PNG\r\n\x1a\n')
            self.assertFalse(animal_fixes.verify(root, {}, {})['issues'])
            log.write_text(log.read_text() + '[QUEUE_TEST] PASS animal-info\n')
            self.assertTrue(animal_fixes.verify(root, {}, {})['issues'])

    def test_scope(self):
        selection = dict(cases=animal_fixes.CASES, kind='sp', mode='toolkit', languages=['EN'])
        animal_fixes.validate(selection)
        with self.assertRaises(ValueError):
            animal_fixes.validate(dict(selection, kind='mp'))
