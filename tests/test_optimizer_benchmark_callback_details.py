"""Only an explicitly requested detail profile changes the owned diagnostic snapshot."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks.adapters import optimizer_benchmark as benchmark


class CallbackDetailStagingTests(unittest.TestCase):
    def fixture(self):
        temporary = tempfile.TemporaryDirectory(prefix='callback-details-')
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        project, cache, mod = root / 'project', root / 'cache', root / 'cache/mods/PZDrivingPerfProbe/42'
        source = project / 'tests/native_queue/optimizer-benchmark/CallbackDetails.lua'
        source.parent.mkdir(parents=True)
        source.write_text('-- diagnostic helper\n')
        shipped = project / 'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/VehicleLightDashboard.lua'
        shipped.parent.mkdir(parents=True)
        shipped.write_text('before\n        original(self, ...)\n        D.bind(self)\nafter\n')
        target = cache / 'mods/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/VehicleLightDashboard.lua'
        target.parent.mkdir(parents=True)
        target.write_text(shipped.read_text())
        return project, cache, mod, shipped, target

    def test_stages_only_owned_copy_and_preserves_surrounding_source(self):
        project, cache, mod, shipped, target = self.fixture()
        original = shipped.read_text()
        benchmark.stage_callback_details(project, cache, mod)
        self.assertEqual(original, shipped.read_text())
        self.assertEqual(original.replace('original(self, ...)', 'PZDrivingCallbackCall(original, self, ...)'), target.read_text())
        self.assertEqual('-- diagnostic helper\n', (mod / 'media/lua/client/ZZZDrivingCallbackDetails.lua').read_text())
        self.assertFalse(target.with_name(target.name + '.callback-details.tmp').exists())
        receipt = benchmark.verify_callback_details(cache)
        self.assertEqual(1, receipt['replacements'])
        self.assertNotEqual(receipt['before_sha256'], receipt['after_sha256'])
        with self.assertRaisesRegex(ValueError, 'boundary changed'):
            benchmark.stage_callback_details(project, cache, mod)

    def test_atomic_patch_cannot_modify_hardlinked_source(self):
        project, cache, mod, shipped, target = self.fixture()
        target.unlink()
        target.hardlink_to(shipped)
        original = shipped.read_text()
        benchmark.stage_callback_details(project, cache, mod)
        self.assertEqual(original, shipped.read_text())
        self.assertNotEqual(shipped.stat().st_ino, target.stat().st_ino)

    def test_rejects_missing_duplicate_and_symbolic_boundaries(self):
        for kind in ('missing', 'duplicate', 'symlink'):
            with self.subTest(kind=kind):
                project, cache, mod, shipped, target = self.fixture()
                if kind == 'missing':
                    target.write_text('changed source')
                elif kind == 'duplicate':
                    target.write_text(target.read_text() * 2)
                else:
                    target.unlink()
                    target.symlink_to(shipped)
                with self.assertRaises(ValueError):
                    benchmark.stage_callback_details(project, cache, mod)
                self.assertFalse((mod / 'media/lua/client/ZZZDrivingCallbackDetails.lua').exists())

    def test_staging_receipt_detects_changed_helper_or_dashboard(self):
        for filename in ('source', 'helper'):
            with self.subTest(filename=filename):
                project, cache, mod, shipped, target = self.fixture()
                receipt = benchmark.stage_callback_details(project, cache, mod)
                path = cache / receipt[filename]
                path.write_text(path.read_text() + '-- changed\n')
                with self.assertRaisesRegex(ValueError, 'staged source changed'):
                    benchmark.verify_callback_details(cache)

    def test_option_requires_callback_profile_and_boolean(self):
        with tempfile.TemporaryDirectory(prefix='callback-detail-option-') as temporary:
            archive = Path(temporary) / 'official.zip'
            archive.write_bytes(b'fixture')
            selection = {'kind': 'sp', 'clients': 1, 'cases': ['drive'], 'languages': ['EN'], 'mode': 'native',
                         'resources': {'exclusive': True},
                         'mods': ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit', 'PZDrivingBench'],
                         'options': {'optimizer_enabled': False, 'optimizer_archive': str(archive),
                                     'world_template': 'sealed', 'stage_profile': True}}
            for value in (True, 1, 'true', None):
                selection['options']['callback_detail_profile'] = value
                with self.assertRaisesRegex(ValueError, 'callback_detail_profile'):
                    benchmark.validate(selection)
            selection['options'].update(callback_profile=True, callback_detail_profile=True)
            benchmark.validate(selection)
            selection['options']['callback_detail_profile'] = False
            benchmark.validate(selection)
            selection['options']['callback_chain_profile'] = True
            with self.assertRaisesRegex(ValueError, 'callback_chain_profile'):
                benchmark.validate(selection)
            selection['options']['callback_detail_profile'] = True
            benchmark.validate(selection)
            for value in (1, 'true', None):
                selection['options']['callback_chain_profile'] = value
                with self.assertRaisesRegex(ValueError, 'callback_chain_profile'):
                    benchmark.validate(selection)
            source = Path('project/tests/native_queue/optimizer-benchmark/CallbackDetails.lua')
            self.assertIn(source, benchmark.sources(Path('project'), selection))


if __name__ == '__main__':
    unittest.main()
