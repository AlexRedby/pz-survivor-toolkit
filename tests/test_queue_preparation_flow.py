"""Heavy snapshot and campaign input work must execute inside preparation admission."""
import json
import unittest
from unittest.mock import patch

from tests import test_queue_native_snapshot as snapshots
from queue_checks import admission, native


class PreparationFlowTests(unittest.TestCase):
    def setUp(self):
        self.fixture = snapshots.NativeSnapshotTests(methodName='runTest')
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)

    def test_hash_copy_and_compile_share_one_lease_until_snapshot_is_complete(self):
        output = self.fixture.root / 'run'
        original_sources, original_copy = native._source_inputs, native.snapshot_copy.copy_file
        original_compile = self.fixture.compile
        stages = []

        def observe(stage):
            preparations = admission.status()['preparing']
            self.assertEqual([str(output)], [item['root'] for item in preparations])
            stages.append(stage)

        def sources(*args, **kwargs):
            observe('sources')
            return original_sources(*args, **kwargs)

        def copy(*args, **kwargs):
            observe('copy')
            return original_copy(*args, **kwargs)

        def compile(*args, **kwargs):
            observe('compile')
            return original_compile(*args, **kwargs)

        self.fixture.compile_mock.side_effect = compile
        with patch.object(native, '_source_inputs', side_effect=sources), \
                patch.object(native.snapshot_copy, 'copy_file', side_effect=copy), \
                patch.object(admission, 'preparing', wraps=admission.preparing) as lease:
            result = self.fixture.prepare()
        self.assertEqual(result, output)
        self.assertTrue((result / 'snapshot-hashes.json').is_file())
        self.assertEqual(set(stages), {'sources', 'copy', 'compile'})
        self.assertEqual(lease.call_count, 1)
        self.assertEqual(admission.status()['preparing'], [])

    def test_exclusive_owner_blocks_preparation_before_source_resolution_or_output(self):
        output = self.fixture.root / 'blocked'
        owner = self.fixture.root / 'measurement'
        selection = dict(self.fixture.selection, resources={'exclusive': True})
        with admission.preparing(owner, selection, wait=0), \
                patch.object(native, '_source_inputs') as sources:
            with self.assertRaisesRegex(RuntimeError, 'exclusive'):
                native.prepare(self.fixture.project, output, self.fixture.game, self.fixture.jdk,
                               self.fixture.selection, resource_wait=0)
            sources.assert_not_called()
            self.fixture.compile_mock.assert_not_called()
            self.assertFalse(output.exists())

    def test_standalone_input_preflight_is_admitted_and_cleans_up_after_failure(self):
        def rejected(*args, **kwargs):
            self.assertEqual(len(admission.status()['preparing']), 1)
            raise ValueError('changed source input')

        with patch.object(native, '_source_inputs', side_effect=rejected):
            with self.assertRaisesRegex(ValueError, 'changed source input'):
                native.source_inputs(self.fixture.project, self.fixture.game, self.fixture.jdk,
                                     self.fixture.selection, resource_wait=0)
        self.assertEqual(admission.status()['preparing'], [])
        self.assertEqual(admission.status()['waiting'], [])
        self.fixture.compile_mock.assert_not_called()

    def test_adapter_validation_runs_under_lease_after_seed_port_normalization(self):
        seed = self.fixture.root / 'seed'
        seed.mkdir()
        ports = [24000, 24001]
        (seed / 'selection.json').write_text(json.dumps({'ports': ports}))
        output = self.fixture.root / 'reload'
        adapter = self.fixture.fixture_adapter(lambda *args: None)
        validated = []

        def validate(selection):
            self.assertEqual([str(output)], [item['root'] for item in admission.status()['preparing']])
            self.assertEqual(selection['ports'], ports)
            validated.append(selection)

        adapter.validate = validate
        with patch.object(native.adapters, 'get', return_value=adapter):
            self.fixture.prepare('reload', ports_auto=True, options={'seed_run': str(seed)})
        self.assertTrue(validated)
        self.assertEqual(admission.status()['preparing'], [])


if __name__ == '__main__':
    unittest.main()
