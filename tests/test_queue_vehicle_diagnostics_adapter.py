"""Diagnostics acceptance requires live Host authority and both actual trace files."""
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import vehicle_diagnostics as adapter


class VehicleDiagnosticsAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.selection = dict(cases=['controls'], kind='mp', mode='toolkit', clients=1,
                              languages=['EN'], mods=adapter.MODS, options={'mp_host': True})
        client = ''.join(adapter.MARKER + 'PASS ' + check + '\n' for check in adapter.CHECKS)
        client += adapter.MARKER + 'COMPLETE controls\n'
        self.paths = {}
        for side in ('client', 'server'):
            path = self.root / 'client1/Logs/PZToolkitVehicleTrace' / side / 'vehicle-sync.log'
            path.parent.mkdir(parents=True)
            path.write_text('[VEHICLE_SYNC] t=1 event=session state=active\n'
                            '[VEHICLE_SYNC] t=2 side=' + side + ' event=state vehicle=42 local=-1 driver=0 owner=0 auth=Local\n'
                            '[VEHICLE_SYNC] t=3 event=session state=off\n')
            self.paths[side] = path
            client += adapter.MARKER + 'PATH ' + side + '=' + str(path) + '\n'
        (self.root / 'client1-launch.log').write_text(client)
        (self.root / 'server-launch.log').write_text(adapter.MARKER + 'SPAWN id=42\n'
            + adapter.MARKER + 'AUTHORITY state=active id=42 driver=0\n'
            + adapter.MARKER + 'AUTHORITY state=off id=42 driver=0\n')
        screenshots = self.root / 'client1/Screenshots'
        screenshots.mkdir()
        for shot in adapter.SHOTS:
            (screenshots / shot).write_bytes(b'capture')

    def verify(self):
        return adapter.verify(self.root, self.selection, {})

    def test_accepts_both_live_trace_files_and_authority(self):
        adapter.validate(self.selection)
        self.assertEqual(self.verify()['issues'], [])
        self.assertEqual(self.verify()['evidence']['sample_counts'], {'client': 1, 'server': 1})

    def test_rejects_non_host_sp_and_missing_patches(self):
        for changes in ({'kind': 'sp'}, {'options': {}}, {'clients': 2}, {'mods': ['PZSurvivorToolkit']},
                        {'options': {'mp_host': True, 'world_template': '/tmp/world'}}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                adapter.validate(dict(self.selection, **changes))

    def test_session_markers_without_real_samples_cannot_pass(self):
        path = self.paths['server']
        path.write_text('\n'.join(line for line in path.read_text().splitlines() if 'event=state' not in line))
        self.assertTrue(self.verify()['issues'])

    def test_copied_client_samples_cannot_certify_server(self):
        self.paths['server'].write_text(self.paths['client'].read_text())
        self.assertTrue(self.verify()['issues'])

    def test_requires_original_vehicle_and_actual_driver(self):
        for before, after in (('vehicle=42', 'vehicle=43'), ('driver=0', 'driver=-1')):
            with self.subTest(after=after):
                path = self.paths['server']; original = path.read_text()
                path.write_text(original.replace(before, after))
                self.assertTrue(self.verify()['issues'])
                path.write_text(original)

    def test_requires_stop_at_end_of_each_file(self):
        path = self.paths['client']
        path.write_text(path.read_text() + '[VEHICLE_SYNC] t=4 side=client event=state vehicle=42 local=0 driver=0 \n')
        self.assertTrue(self.verify()['issues'])

    def test_separate_host_cache_trace_paths_are_required(self):
        log = self.root / 'client1-launch.log'
        log.write_text(log.read_text().replace(str(self.paths['server']), str(self.paths['client'])))
        self.assertTrue(self.verify()['issues'])

    def test_requires_unique_completion_and_ordered_server_observations(self):
        for role, extra in (('client1', adapter.MARKER + 'COMPLETE controls\n'),
                            ('server', adapter.MARKER + 'AUTHORITY state=off id=42 driver=0\n')):
            with self.subTest(role=role):
                log = self.root / (role + '-launch.log'); original = log.read_text()
                log.write_text(original + extra)
                self.assertTrue(self.verify()['issues'])
                log.write_text(original)


if __name__ == '__main__':
    unittest.main()
