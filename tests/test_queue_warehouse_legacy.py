import copy
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks.adapters import warehouse_legacy as adapter


class LegacyWarehouseTests(unittest.TestCase):
    def selection(self, case):
        return dict(cases=[case], kind='sp', clients=1, mode='toolkit', languages=['EN'],
                    mods=['PZSurvivorToolkit', 'EURY_CONTAINERS', 'organizedCategories_core'],
                    options={'world_template': '/tmp/sealed'} if case == 'legacy-reload' else {})

    def line(self, event, value):
        return adapter.MARKER + event + ' ' + json.dumps(value) + '\n'

    def test_scope_and_template_gate(self):
        for case in adapter.CASES:
            value = self.selection(case); adapter.validate(value)
            for key, wrong in [('kind', 'mp'), ('clients', True), ('languages', ['EN', 'RU'])]:
                bad = copy.deepcopy(value); bad[key] = wrong
                with self.assertRaises(ValueError): adapter.validate(bad)
            bad = copy.deepcopy(value); bad['options'] = {} if value['options'] else {'world_template': '/tmp/x'}
            with self.assertRaises(ValueError): adapter.validate(bad)

    def test_actual_seed_identity_chain_and_migration_order(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); seed, reload = root / 'seed', root / 'reload'; seed.mkdir(); reload.mkdir()
            saved = dict(schema=0, ids=[11, 22, 33, 44], far=5, loaded=4)
            def log(case, rows):
                return (self.line('SETUP', dict(case=case, role='client1')) + ''.join(self.line(*r) for r in rows)
                        + self.line('COMPLETE', dict(case=case, role='client1')))
            seed_log = log('legacy-seed', [('SAVED', saved)])
            (seed / 'selection.json').write_text(json.dumps(self.selection('legacy-seed')))
            (seed / 'client1-launch.log').write_text(seed_log)
            self.assertFalse(adapter.verify(seed, self.selection('legacy-seed'), {})['issues'])
            state = dict(saved, schema=2, ui=9, unknownAge=True, native=True)
            text = self.line('COLD', saved) + log('legacy-reload', [('RESTORED', state)])
            (reload / 'world-template.json').write_text(json.dumps(dict(source_run=str(seed), source_suite='warehouse-manifest', source_cases=['legacy-seed'], kind='sp')))
            shot = reload / 'client1/Screenshots/warehouse-manifest-legacy-reload.png'; shot.parent.mkdir(parents=True)
            shot.write_bytes(b'\x89PNG\r\n\x1a\n' + b'\0\0\0\rIHDR' + struct.pack('>II', 1280, 900) + b'\0' * 9)
            path = reload / 'client1-launch.log'; path.write_text(text)
            self.assertFalse(adapter.verify(reload, self.selection('legacy-reload'), {})['issues'])
            for wrong in (dict(state, ids=[11, 22, 33, 99]), dict(state, ui=True), dict(state, unknownAge=False)):
                path.write_text(self.line('COLD', saved) + log('legacy-reload', [('RESTORED', wrong)]))
                self.assertTrue(adapter.verify(reload, self.selection('legacy-reload'), {})['issues'])
            path.write_text(log('legacy-reload', [('RESTORED', state)]))
            self.assertTrue(adapter.verify(reload, self.selection('legacy-reload'), {})['issues'])

    def test_seed_rejects_boolean_duplicate_and_missing_ids(self):
        base = dict(schema=0, ids=[11, 22, 33, 44], far=5, loaded=4)
        adapter._state(base)
        for wrong in (dict(base, schema=False), dict(base, ids=[11, 11, 33, 44]), dict(base, ids=[True, 22, 33, 44]), dict(base, far=4)):
            with self.assertRaises(ValueError): adapter._state(wrong)
