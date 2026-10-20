"""Packaging/evidence checks only; these do not establish native UI PASS."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent


def load(name):
    spec = importlib.util.spec_from_file_location('inventory_tooltips_' + name, HERE / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


packaging = load('prepare')
verifier = load('verify')


class FixtureTests(unittest.TestCase):
    def test_prepare_pins_owned_sources_and_copies_fixture_without_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'Toolkit/42/media/lua/client/PZSurvivorToolkit'
            source.mkdir(parents=True)
            for name in packaging.MODULES:
                (source / (name + '.lua')).write_text('return {}\n')
            output = root / 'helper'
            packaging.prepare(root / 'Toolkit', output)
            manifest = json.loads((output / 'fixture-manifest.json').read_text())
            self.assertEqual(manifest['scenario'], 'inventory-tooltips')
            self.assertEqual(set(manifest['source_sha256']), set(packaging.MODULES))
            self.assertIn('InventoryClothingTooltip', manifest['source_sha256'])
            self.assertTrue(all(len(digest) == 64 for digest in manifest['source_sha256'].values()))
            self.assertEqual((output / '42/media/lua/client/ZZInventoryTooltipNative.lua').read_bytes(),
                             (HERE / 'ZZInventoryTooltipNative.lua').read_bytes())
            with self.assertRaises(FileExistsError):
                packaging.prepare(root / 'Toolkit', output)

    def test_missing_product_is_rejected_before_output_is_created(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(ValueError, 'Missing owned'):
                packaging.prepare(root / 'missing', root / 'helper')
            self.assertFalse((root / 'helper').exists())

    def test_missing_clothing_adapter_is_rejected_before_output_is_created(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'Toolkit/42/media/lua/client/PZSurvivorToolkit'
            source.mkdir(parents=True)
            for name in packaging.MODULES:
                if name != 'InventoryClothingTooltip':
                    (source / (name + '.lua')).write_text('return {}\n')
            with self.assertRaisesRegex(ValueError, 'Missing owned module: InventoryClothingTooltip'):
                packaging.prepare(root / 'Toolkit', root / 'helper')
            self.assertFalse((root / 'helper').exists())

    def evidence(self, root, recipes=1, both='true'):
        manifest = json.loads((HERE / 'manifest.json').read_text())
        lines = [f'[INVENTORY_TOOLTIP] MEDIA id=native-id skills=1 recipes={recipes} bothAvailable={both}']
        lines += manifest['assertion_markers']
        lines += ['[INVENTORY_TOOLTIP] SHOT ' + name for name in manifest['expected_screenshots']]
        lines.append(manifest['completion_marker'])
        shots = root / 'client1/Screenshots'
        shots.mkdir(parents=True, exist_ok=True)
        for name in manifest['expected_screenshots']:
            (shots / name).write_bytes(verifier.PNG)
        return '\n'.join(lines)

    def test_verifier_requires_complete_unique_receipts_and_screenshot_order(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            text = self.evidence(root)
            self.assertEqual(len(verifier.verify(root, text)['screenshots']), 9)
            for changed in (text.replace('measure=1 draw=1', 'measure=1 draw=2', 1),
                            text + '\n' + text.splitlines()[1],
                            text.replace('replaced=true', 'replaced=false'),
                            text.replace('heightRestored=true', 'heightRestored=false'),
                            text.replace('nonoverlap=true', 'nonoverlap=false', 1),
                            text + '\n[INVENTORY_TOOLTIP] FAIL timeout',
                            text.replace('02-vhs.png', 'unexpected.png')):
                with self.assertRaises(ValueError):
                    verifier.verify(root, changed)
            (root / 'client1/Screenshots/inventory-tooltip-02-vhs.png').write_bytes(b'broken')
            with self.assertRaisesRegex(ValueError, 'Missing/invalid screenshot'):
                verifier.verify(root, text)

    def test_verifier_records_missing_combined_native_media_as_a_limit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            text = self.evidence(root, recipes=0, both='false')
            self.assertIn('skills only', verifier.verify(root, text)['limits'][-1])
            with self.assertRaisesRegex(ValueError, 'was not selected'):
                verifier.verify(root, text.replace('bothAvailable=false', 'bothAvailable=true'))


if __name__ == '__main__':
    unittest.main()
