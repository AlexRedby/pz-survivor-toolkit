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
        self.custom_id = 'custom:01234567-89ab-cdef-0123-456789abcdef'
        self.value = dict(name='QM supplies', iconKind='pzst-tag', iconValue='edible',
                          r=.25, g=.5, b=.75, a=1, category=self.category,
                          categorySelected=True, categoryCount=1, itemCount=0, presetCount=0,
                          priority=6, ruleMode='', include=[], exclude=[], groups=[
                              {'include': ['edible', 'perishable'], 'exclude': ['meat']},
                              {'include': ['mechanics'], 'exclude': ['vehiclepart']},
                              {'include': [self.custom_id], 'exclude': []},
                          ], customId=self.custom_id, customName=adapter.CUSTOM_NAME, revision=1)
        self.selection = {'kind': 'sp'}

    def test_default_pack_includes_neatui_before_cleanui(self):
        self.assertEqual(['NeatUI_Framework', 'CleanUI', 'PZSurvivorToolkit', 'EURY_CONTAINERS'],
                         adapter.definitions()[adapter.SUITE]['default_mods'])

    def test_opening_profile_requires_exclusive_admission(self):
        selection = dict(kind='sp', clients=1, cases=['edit'], mode='toolkit', languages=['EN'],
                         mods=adapter.MODS, options={'profile_container_open': True})
        for resources in (None, {}, {'exclusive': False}, {'exclusive': 1}):
            with self.subTest(resources=resources):
                selection['resources'] = resources
                with self.assertRaisesRegex(ValueError, 'exclusive'):
                    adapter.validate(selection)
        selection['resources'] = {'exclusive': True}
        adapter.validate(selection)

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
                                                    'category': self.category, 'customId': self.custom_id,
                                                    'customName': adapter.CUSTOM_NAME}))
        shots = [(name, 480, 700) for name in
                 ('empty', 'search', 'no-results', 'checked', 'items', 'presets', 'rule', 'color',
                  'tag-checked', 'tag-scroll', 'tag-dropdown', 'icon', 'tags', 'custom-tags', 'rules')]
        shots.extend([('edit', 480, 700), ('minimum', 420, 600)])
        shot_receipts = [self.screenshot('client1', *shot) for shot in shots]
        client1.extend(self.marker('SHOT', shot) for shot in shot_receipts[:11])
        client1.append(self.marker('TAGUI', dict(oneClick=True, checked=True, advancedApplied=True, foreground=True)))
        client1.extend(self.marker('SHOT', shot) for shot in shot_receipts[11:15])
        client1.append(self.marker('DEFAULTS', {'tag': 'edible', 'item': 'Base.Hammer',
                                                'role': 'client1', 'menuClasses': 3}))
        client1.extend(self.marker('SHOT', shot) for shot in shot_receipts[15:])
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
                                                'category': self.category, 'customId': self.custom_id,
                                                'customName': adapter.CUSTOM_NAME}),
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
        self.assertEqual(17, len(result['evidence']['screenshots']))

    def test_host_receipts_require_owner_and_observer_captures(self):
        self.write_logs('mp')
        result = adapter.verify(self.root, self.selection, {})
        self.assertEqual([], result['issues'])
        self.assertEqual(18, len(result['evidence']['screenshots']))

    def test_retired_visible_tag_and_incoherent_authority_or_observer_fail(self):
        for role, old, new in (
                ('client1', '"tag":"edible"', '"tag":"food"'),
                ('client1', '"iconValue":"edible"', '"iconValue":"food"'),
                ('server', '"include":["edible","perishable"]', '"include":["food","perishable"]'),
                ('client2', '"categorySelected":true', '"categorySelected":false')):
            with self.subTest(role=role, field=old):
                self.write_logs('mp')
                path = self.root / (role + '-launch.log')
                text = path.read_text()
                self.assertIn(old, text)
                path.write_text(text.replace(old, new))
                self.assertTrue(adapter.verify(self.root, self.selection, {})['issues'])

    def test_custom_uuid_label_and_actor_identity_are_required(self):
        for invalid_id in ('custom:fixture', 'custom:01234567-89ab-cdef-0123-456789abcde',
                           'custom:01234567-89ab-cdef-0123-456789abcdeG'):
            with self.subTest(invalid_id=invalid_id):
                self.write_logs('sp')
                path = self.root / 'client1-launch.log'
                path.write_text(path.read_text().replace(self.custom_id, invalid_id))
                self.assertTrue(adapter.verify(self.root, self.selection, {})['issues'])
        for role, event in (('client1', 'LOCAL'), ('server', 'AUTHORITY'), ('client2', 'OBSERVER')):
            for field, replacement in (('customName', 'Other custom tag'),
                                       ('customId', 'custom:ffffffff-ffff-ffff-ffff-ffffffffffff')):
                with self.subTest(role=role, field=field):
                    self.write_logs('mp')
                    path = self.root / (role + '-launch.log')
                    original = self.marker(event, self.value)
                    changed = dict(self.value, **{field: replacement})
                    path.write_text(path.read_text().replace(original, self.marker(event, changed)))
                    self.assertTrue(adapter.verify(self.root, self.selection, {})['issues'])

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

    def test_tag_ui_receipt_requires_direct_selection_apply_and_foreground(self):
        self.write_logs('sp')
        path = self.root / 'client1-launch.log'
        original = path.read_text()
        tagui = next(line for line in original.splitlines() if 'TAGUI ' in line)
        for replacement in ('', tagui.replace('"foreground":true', '"foreground":false'), tagui + '\n' + tagui):
            path.write_text(original.replace(tagui, replacement))
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

    @staticmethod
    def opening_samples():
        samples = []
        for name in ('idle', 'containerCold', 'ruleCold', 'chooserCold',
                     'chooserWarm', 'ruleWarm', 'containerWarm', 'tagCatalogCold', 'tagCatalogWarm'):
            sample = dict(name=name, started=1000, callbackMs=2, firstUiPassMs=18,
                          frameGaps=[16] * 5, uiMs=[3] * 5,
                          functions=[] if name == 'idle' else {
                              name + '.render': dict(calls=5, totalMs=5, maxMs=1)})
            if name != 'idle':
                sample['firstTargetRenderMs'] = 18
                sample['readyRenderMs'] = 36
            samples.append(sample)
        return samples

    def test_opening_profile_requires_ordered_stages_and_target_renders(self):
        samples = self.opening_samples()
        text = self.marker('PERF', {'samples': samples})
        self.assertEqual(samples, adapter._opening_profile(text))
        for mutate in (
                lambda rows: rows.reverse(),
                lambda rows: rows[1].pop('firstTargetRenderMs'),
                lambda rows: rows[1].pop('readyRenderMs'),
                lambda rows: rows[1].update(readyRenderMs=17),
                lambda rows: rows[2].update(frameGaps=[16] * 4),
                lambda rows: rows[3].update(callbackMs=True),
                lambda rows: rows[4]['functions'].update(bad=dict(calls=0, totalMs=0, maxMs=0)),
                lambda rows: rows.pop(),
                lambda rows: rows[7].pop('firstTargetRenderMs'),
                lambda rows: rows[8].pop('firstTargetRenderMs')):
            with self.subTest(mutation=mutate):
                changed = self.opening_samples()
                mutate(changed)
                with self.assertRaises(ValueError):
                    adapter._opening_profile(self.marker('PERF', {'samples': changed}))

    def test_profile_receipt_precedes_ui_probes_in_sp_and_host(self):
        for kind in ('sp', 'mp'):
            with self.subTest(kind=kind):
                self.write_logs(kind)
                self.selection['options'] = {'profile_container_open': True}
                self.selection['resources'] = {'exclusive': True}
                path = self.root / 'client1-launch.log'
                lines = path.read_text().splitlines()
                perf = self.marker('PERF', {'samples': self.opening_samples()})
                lines.insert(1 if kind == 'sp' else 0, perf)
                path.write_text('\n'.join(lines) + '\n')
                result = adapter.verify(self.root, self.selection, {})
                self.assertEqual([], result['issues'])
                self.assertEqual(9, len(result['evidence']['openingProfile']))
                lines.remove(perf)
                lines.append(perf)
                path.write_text('\n'.join(lines) + '\n')
                self.assertTrue(adapter.verify(self.root, self.selection, {})['issues'])

    def test_optional_script_choice_parity_follows_profile_and_precedes_ui(self):
        for kind in ('sp', 'mp'):
            for profile in (False, True):
                with self.subTest(kind=kind, profile=profile):
                    self.write_logs(kind)
                    self.selection['options'] = {'check_script_choice_parity': True,
                                                 'profile_container_open': profile}
                    self.selection['resources'] = {'exclusive': True}
                    path = self.root / 'client1-launch.log'
                    lines = path.read_text().splitlines()
                    position = 1 if kind == 'sp' else 0
                    if profile:
                        lines.insert(position, self.marker('PERF', {'samples': self.opening_samples()}))
                        position += 1
                    parity = self.marker('CHOICEPARITY', {'scripts': 12345})
                    lines.insert(position, parity)
                    original = '\n'.join(lines) + '\n'
                    path.write_text(original)
                    result = adapter.verify(self.root, self.selection, {})
                    self.assertEqual([], result['issues'])
                    self.assertEqual({'scripts': 12345}, result['evidence']['scriptChoiceParity'])
                    for replacement in ('', parity + '\n' + parity,
                                        self.marker('CHOICEPARITY', {'scripts': 0}),
                                        self.marker('CHOICEPARITY', {'scripts': True}),
                                        self.marker('CHOICEPARITY', {'scripts': 1, 'extra': True})):
                        path.write_text(original.replace(parity, replacement))
                        self.assertTrue(adapter.verify(self.root, self.selection, {})['issues'])
                    path.write_text(original.replace(parity + '\n', '') + parity + '\n')
                    self.assertTrue(adapter.verify(self.root, self.selection, {})['issues'])
                    path.write_text(original)
                    self.selection['options']['check_script_choice_parity'] = False
                    self.assertTrue(adapter.verify(self.root, self.selection, {})['issues'])


if __name__ == '__main__':
    unittest.main()
