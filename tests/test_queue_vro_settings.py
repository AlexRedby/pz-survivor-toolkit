"""Native receipts must prove declared settings and real injected recipe times."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

from tools.queue_checks.adapters import vro_settings as adapter

ROOT = Path(__file__).resolve().parents[1]


def selection(kind='sp'):
    return dict(suite=adapter.SUITE, cases=['custom-controls'], kind=kind, mode='toolkit',
                clients=1, languages=['EN'], mods=adapter.MODS,
                options={'mp_host': True} if kind == 'mp' else {})


def logs(kind='sp'):
    result = {}
    for role in (['client1'] if kind == 'sp' else ['server', 'client1']):
        def emit(event, row):
            return adapter.MARKER + event + ' ' + json.dumps(row) + '\n'
        text = adapter.PATCH_MARKER + '\n' + emit('OBSERVE', adapter.expected(role))
        if role == 'client1' and kind == 'mp':
            text += emit('AUTHORITY', adapter.expected('server'))
        result[role] = text + emit('COMPLETE', dict(case='custom-controls', role=role))
    return result


def verify(values, kind='sp'):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        for role, text in values.items():
            (root / (role + '-launch.log')).write_text(text)
        return adapter.verify(root, selection(kind), {})


class VROSettingsTests(unittest.TestCase):
    def test_sp_and_host_require_real_settings_recipe_and_authority(self):
        for kind in ('sp', 'mp'):
            self.assertEqual([], verify(logs(kind), kind)['issues'])
        for field, value in [('optionEnabled', True), ('luaEnabled', True), ('effectiveEnabled', True),
                             ('recipeTime', 600), ('effectiveTime', 600), ('legacyAbsent', False),
                             ('optionEnabled', 0), ('effectiveEnabled', 0)]:
            values = logs()
            row = adapter.expected('client1'); row[field] = value
            values['client1'] = values['client1'].replace(json.dumps(adapter.expected('client1')), json.dumps(row))
            with self.subTest(field=field, value=value):
                self.assertTrue(verify(values)['issues'])
        for event in ('OBSERVE', 'AUTHORITY', 'COMPLETE'):
            values = logs('mp')
            line = next(line for line in values['client1'].splitlines(True) if adapter.MARKER + event + ' ' in line)
            for replacement in ('', line + line):
                with self.subTest(event=event, replacement=replacement):
                    altered = copy.deepcopy(values); altered['client1'] = altered['client1'].replace(line, replacement)
                    self.assertTrue(verify(altered, 'mp')['issues'])
        values = logs('mp'); values['server'] = values['server'].replace(adapter.PATCH_MARKER, '')
        self.assertTrue(verify(values, 'mp')['issues'])
        values = logs('mp'); values['client1'] = values['client1'].replace(adapter.PATCH_MARKER, 'SERVER: ' + adapter.PATCH_MARKER)
        self.assertTrue(verify(values, 'mp')['issues'])
        values = logs(); values['client1'] = adapter.PATCH_MARKER + '\n' + values['client1']
        self.assertEqual([], verify(values)['issues'])
        values = logs(); lines = values['client1'].splitlines(True)
        values['client1'] = ''.join(reversed(lines))
        self.assertTrue(verify(values)['issues'])

    def test_staging_sets_native_options_before_sp_world_and_host_server(self):
        for kind in ('sp', 'mp'):
            value = selection(kind); adapter.validate(value)
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                runtime = {'roles': {role: {'cache': str(root / role)}
                                    for role in (['client1'] if kind == 'sp' else ['server', 'client1'])}}
                adapter.stage(ROOT, root, None, None, value, {}, runtime)
                self.assertEqual(False, runtime['fixture']['sandbox']['VSO_EnableFullVehicleSalvaging'])
                self.assertEqual(120, runtime['fixture']['sandbox']['VSO_SalvageTime_Doors'])
                text = (root / 'client1/mods/ActionQueueTest/42/media/lua/client/ZZStartup.lua').read_text()
                if kind == 'sp':
                    self.assertLess(text.index("getOptionByName('VSO_EnableFullVehicleSalvaging'):setValue(false)"),
                                    text.index('MainScreen.instance.createWorld=true'))
        for update in ({'clients': 2}, {'mods': adapter.MODS[:-1]}, {'options': {'world_template': 'old'}},
                       {'cases': ['other']}):
            with self.subTest(update=update), self.assertRaises(ValueError):
                adapter.validate(dict(selection(), **update))
