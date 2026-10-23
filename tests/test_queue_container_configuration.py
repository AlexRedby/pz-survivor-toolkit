"""Container-configuration receipts require every expected editor capture and size."""
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import container_configuration as adapter


class ContainerConfigurationAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.category = 'CrateCategory'
        self.value = dict(name='QM supplies', iconKind='pzst-tag', iconValue='food',
                          r=.25, g=.5, b=.75, a=1, category=self.category,
                          categorySelected=True, categoryCount=1, itemCount=0, presetCount=0,
                          priority=6, ruleMode='all', include=['food', 'perishable'],
                          exclude=['meat'], revision=1)
        self.selection = {'kind': 'sp'}

    def test_default_pack_includes_neatui_before_cleanui(self):
        self.assertEqual(['NeatUI_Framework', 'CleanUI', 'PZSurvivorToolkit', 'EURY_CONTAINERS'],
                         adapter.definitions()[adapter.SUITE]['default_mods'])

    @staticmethod
    def marker(event, value):
        return adapter.MARKER + event + ' ' + json.dumps(value, separators=(',', ':'))

    @staticmethod
    def png(width, height):
        return (adapter.PNG + struct.pack('>I', 13) + b'IHDR' + struct.pack('>II', width, height)
                + b'\x08\x02\x00\x00\x00' + b'\x00' * 4)

    def screenshot(self, role, name, width, height):
        directory = self.root / role / 'Screenshots'
        directory.mkdir(parents=True, exist_ok=True)
        (directory / ('container-config-' + name + '.png')).write_bytes(self.png(1280, 720))
        return {'name': name, 'role': role, 'width': width, 'height': height}

    def write_logs(self, kind):
        self.selection = {'kind': kind}
        client1 = []
        server = []
        if kind == 'sp':
            client1.append(self.marker('PREPARED', {'x': 10, 'y': 20, 'z': 0, 'index': 0,
                                                    'category': self.category}))
        shots = [(name, 480, 700) for name in
                 ('empty', 'search', 'no-results', 'checked', 'items', 'presets', 'rule', 'color', 'icon')]
        shots.extend([('edit', 480, 700), ('minimum', 420, 600)])
        shot_receipts = [self.screenshot('client1', *shot) for shot in shots]
        client1.extend(self.marker('SHOT', shot) for shot in shot_receipts[:9])
        client1.append(self.marker('DEFAULTS', {'tag': 'food', 'item': 'Base.Hammer',
                                                'role': 'client1', 'menuClasses': 3}))
        client1.extend(self.marker('SHOT', shot) for shot in shot_receipts[9:])
        client1.extend([
            self.marker('SAVE', {'count': 1, 'role': 'client1'}),
            self.marker('LOCAL', self.value),
        ])
        if kind == 'sp':
            client1.append(self.marker('AUTHORITY', self.value))
            client1.append(self.marker('COMPLETE', {'case': 'edit', 'role': 'client1'}))
        else:
            client1.append(self.marker('COMPLETE', {'case': 'edit', 'role': 'client1'}))
            server = [self.marker('PREPARED', {'x': 10, 'y': 20, 'z': 0, 'index': 0,
                                                'category': self.category}),
                      self.marker('AUTHORITY', self.value)]
            self.root.joinpath('server-launch.log').write_text(
                '[STARTUP_TEST] SERVER_READY\n' + '\n'.join(server) + '\n')
            observer_shot = self.screenshot('client2', 'observer', 480, 700)
            client2 = [self.marker('SHOT', observer_shot),
                       self.marker('OBSERVER', self.value),
                       self.marker('COMPLETE', {'case': 'edit', 'role': 'client2'})]
            self.root.joinpath('client2-launch.log').write_text('\n'.join(client2) + '\n')
        self.root.joinpath('client1-launch.log').write_text('\n'.join(client1) + '\n')
        return shot_receipts

    def test_sp_receipts_require_empty_icon_edit_and_minimum_captures(self):
        self.write_logs('sp')
        result = adapter.verify(self.root, self.selection, {})
        self.assertEqual([], result['issues'])
        self.assertEqual(11, len(result['evidence']['screenshots']))

    def test_host_receipts_require_owner_and_observer_captures(self):
        self.write_logs('mp')
        result = adapter.verify(self.root, self.selection, {})
        self.assertEqual([], result['issues'])
        self.assertEqual(12, len(result['evidence']['screenshots']))

    def test_missing_or_duplicate_shot_receipt_fails(self):
        self.write_logs('sp')
        path = self.root / 'client1-launch.log'
        lines = path.read_text().splitlines()
        target = next(line for line in lines if 'SHOT ' in line and '"name":"empty"' in line)
        path.write_text('\n'.join(line for line in lines if line != target) + '\n')
        self.assertTrue(adapter.verify(self.root, self.selection, {})['issues'])

        self.write_logs('sp')
        path = self.root / 'client1-launch.log'
        with path.open('a') as stream:
            stream.write(target + '\n')
        self.assertTrue(adapter.verify(self.root, self.selection, {})['issues'])

    def test_minimum_capture_requires_exact_window_dimensions(self):
        self.write_logs('sp')
        path = self.root / 'client1-launch.log'
        text = path.read_text()
        text = text.replace('"width":420,"height":600', '"width":419,"height":600')
        path.write_text(text)
        result = adapter.verify(self.root, self.selection, {})
        self.assertTrue(result['issues'])
        self.assertEqual('failed', result['outcomes'][0]['status'])


if __name__ == '__main__':
    unittest.main()
