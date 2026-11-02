"""Recovery selection diagnostics through both adapters and CLI defaults."""
import argparse
import copy
import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import grooming_recovery, queue_recovery

spec = importlib.util.spec_from_file_location('recovery_selection_cli', ROOT / 'tools/check_action_queue.py')
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)
ADAPTERS = (queue_recovery, grooming_recovery)


class RecoverySelectionTests(unittest.TestCase):
    def selection(self, adapter, kind='mp', mode='toolkit'):
        return dict(cases=list(adapter.CASES), kind=kind, mode=mode, languages=['EN'], clients=1,
                    mods=list(adapter.MODS), options=dict(mp_host=True, grooming_recovery=True))

    def rejection(self, adapter, selection):
        with self.assertRaises(ValueError) as error:
            adapter.validate(selection)
        message = str(error.exception)
        self.assertTrue(message.startswith(next(iter(adapter.definitions())) + ' selection rejected: '))
        return message.split(' selection rejected: ', 1)[1]

    def test_each_failed_constraint_reports_actual_and_expected_without_unrelated_fields(self):
        for adapter in ADAPTERS:
            changes = [
                ('cases', [adapter.CASES[0]]), ('cases', list(reversed(adapter.CASES))),
                ('cases', list(adapter.CASES) + [adapter.CASES[0]]), ('cases', tuple(adapter.CASES)),
                ('kind', 'server'), ('mode', 'other'), ('languages', ['RU']), ('languages', ('EN',)),
                ('clients', True), ('clients', 1.0), ('clients', 2),
                ('mods', []), ('mods', list(reversed(adapter.MODS))), ('mods', tuple(adapter.MODS)),
                ('options.world_template', 'old-world'), ('options.mp_host', False), ('options.mp_host', 1),
                ('options', None), ('options', []),
            ]
            if adapter is grooming_recovery:
                changes.extend([('options.grooming_recovery', False), ('options.grooming_recovery', 1)])
            for field, value in changes:
                with self.subTest(adapter=adapter.__name__, field=field, value=value):
                    selection = self.selection(adapter)
                    target, key = (selection['options'], field[8:]) if field.startswith('options.') else (selection, field)
                    target[key] = value
                    message = self.rejection(adapter, selection)
                    self.assertTrue(message.startswith(f'{field}: actual={value!r}; expected='), message)
                    self.assertEqual(message.count('actual='), 1)
                    if field in ('cases', 'mods', 'languages'):
                        expected = list(adapter.CASES) if field == 'cases' else adapter.MODS if field == 'mods' else ['EN']
                        self.assertIn('expected=' + repr(expected), message)

    def test_missing_fields_and_multiple_failures_are_diagnosed(self):
        for adapter in ADAPTERS:
            for field in ('cases', 'kind', 'mode', 'languages', 'clients', 'mods', 'options.mp_host'):
                with self.subTest(adapter=adapter.__name__, field=field):
                    selection = self.selection(adapter)
                    target, key = (selection['options'], field[8:]) if field.startswith('options.') else (selection, field)
                    del target[key]
                    self.assertTrue(self.rejection(adapter, selection).startswith(f'{field}: actual=None; expected='))
            selection = self.selection(adapter)
            selection.update(cases=[], languages=['RU'], clients=True)
            message = self.rejection(adapter, selection)
            self.assertEqual(message.count('actual='), 3)
            for field in ('cases', 'languages', 'clients'):
                self.assertIn(field + ': actual=', message)

    def test_all_supported_topologies_modes_and_falsey_world_templates_remain_valid(self):
        for adapter in ADAPTERS:
            for kind in ('sp', 'mp'):
                for mode in ('native', 'toolkit'):
                    for template in (None, False, '', 0, []):
                        with self.subTest(adapter=adapter.__name__, kind=kind, mode=mode, template=template):
                            selection = self.selection(adapter, kind, mode)
                            selection['options']['world_template'] = template
                            if kind == 'sp':
                                selection['options'].pop('mp_host')
                            before = copy.deepcopy(selection)
                            adapter.validate(selection)
                            self.assertEqual(selection, before)
            if adapter is queue_recovery:
                selection = self.selection(adapter, 'sp')
                del selection['options']
                adapter.validate(selection)
            else:
                selection = self.selection(adapter)
                del selection['options']['grooming_recovery']
                self.assertTrue(self.rejection(adapter, selection).startswith('options.grooming_recovery: actual=None; expected=True'))
            selection = self.selection(adapter, 'sp')
            selection['options']['mp_host'] = 'unused in SP'
            adapter.validate(selection)

    def test_cli_defaults_to_en_but_first_case_requires_complete_bank(self):
        catalog = {'suites': cli.adapters.definitions()}
        for adapter in ADAPTERS:
            for language in (None, 'EN'):
                for kind in ('sp', 'mp'):
                    with self.subTest(adapter=adapter.__name__, language=language, kind=kind):
                        args = argparse.Namespace(suite=next(iter(adapter.definitions())), kind=kind, mode='toolkit',
                            language=language, cases=None, mods=None, config=None, mod_source=[], timeout=900, ports=None)
                        options = dict(mp_host=True, grooming_recovery=True)
                        selection = cli.selection(args, catalog, options)
                        self.assertEqual(selection['languages'], ['EN'])
                        message = self.rejection(adapter, selection)
                        self.assertTrue(message.startswith('cases: actual='))
                        self.assertEqual(message.count('actual='), 1)
                        args.cases = ','.join(adapter.CASES)
                        adapter.validate(cli.selection(args, catalog, options))
                        args.language = 'RU'
                        self.assertTrue(self.rejection(adapter, cli.selection(args, catalog, options)).startswith(
                            "languages: actual=['RU']; expected=['EN']"))

    def test_shared_validation_source_is_sealed_for_both_suites(self):
        helper = ROOT / 'tools/queue_checks/adapters/recovery_selection.py'
        for adapter in ADAPTERS:
            with self.subTest(adapter=adapter.__name__):
                self.assertIn(helper, adapter.sources(ROOT, self.selection(adapter)))


if __name__ == '__main__':
    unittest.main()
