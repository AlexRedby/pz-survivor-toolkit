"""Packaging/evidence checks only; these do not establish native gameplay PASS."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent


def load(name):
    spec = importlib.util.spec_from_file_location('smart_deposit_' + name, HERE / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


prepare = load('prepare').prepare
verifier = load('verify')


class FixtureTests(unittest.TestCase):
    def test_prepare_copies_fixture_and_pins_source_without_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'Toolkit/42/media/lua/client/PZSurvivorToolkit/SmartDeposit.lua'
            source.parent.mkdir(parents=True)
            source.write_text('return {}\n')
            output = root / 'helper'
            prepare(root / 'Toolkit', output)
            manifest = json.loads((output / 'fixture-manifest.json').read_text())
            self.assertEqual(manifest['scenario'], 'smart-deposit')
            self.assertEqual(len(manifest['smart_deposit_sha256']), 64)
            self.assertEqual((output / '42/media/lua/client/ZZSmartDepositNative.lua').read_bytes(),
                             (HERE / 'ZZSmartDepositNative.lua').read_bytes())
            with self.assertRaises(FileExistsError):
                prepare(root / 'Toolkit', output)

    def test_prepare_rejects_missing_product_before_creating_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(ValueError, 'Missing owned'):
                prepare(root / 'missing', root / 'helper')
            self.assertFalse((root / 'helper').exists())

    def evidence(self, root):
        manifest = json.loads((HERE / 'manifest.json').read_text())
        lines = ['[SMART_DEPOSIT] SETUP SP native=true storage=3']
        for mode in ('clean', 'vanilla'):
            lines += [
                f'[SMART_DEPOSIT] PREVIEW {mode} accepted=3 rejected=1 pane=true page=true exact=true category=true fallback=true',
                f'[SMART_DEPOSIT] SHOT smart-deposit-{mode}-partial.png',
                f'[SMART_DEPOSIT] QUEUED {mode} nativeActions=3 rejected=false durationUnchanged=true',
                f'[SMART_DEPOSIT] EFFECT {mode} moved=3 retained=1 unique=true seeds=true capacity=true',
                f'[SMART_DEPOSIT] FULL {mode} accepted=0 rejected=4 pane=false page=false nativeActions=0',
            ]
        lines.append(manifest['completion_marker'])
        shots = root / 'client1/Screenshots'
        shots.mkdir(parents=True)
        for name in manifest['expected_screenshots']:
            (shots / name).write_bytes(verifier.PNG)
        return '\n'.join(lines)

    def test_verifier_requires_native_effect_and_unique_preview_receipts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            text = self.evidence(root)
            self.assertEqual(len(verifier.verify(root, text)['screenshots']), 2)
            for changed in (text.replace('moved=3 retained=1', 'moved=2 retained=2'),
                            text + '\n' + text.splitlines()[1],
                            text + '\n[SMART_DEPOSIT] FAIL timeout'):
                with self.assertRaises(ValueError):
                    verifier.verify(root, changed)
            (root / 'client1/Screenshots/smart-deposit-clean-partial.png').write_bytes(b'broken')
            with self.assertRaisesRegex(ValueError, 'Missing/invalid screenshot'):
                verifier.verify(root, text)


if __name__ == '__main__':
    unittest.main()
