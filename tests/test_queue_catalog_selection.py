"""The complete native catalog uses the same selected-INI rules as preparation."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

# Redirect only the input file. A fresh process prevents cached imports from
# hiding import-time dependencies or parser failures.
CATALOG_PROBE = """
from pathlib import Path
import json
import sys
from unittest.mock import patch
import check_action_queue as cli

original = Path.read_text
fixture = Path(sys.argv[1])
def read(path, *args, **kwargs):
    return original(fixture if path.name == 'SurvivorQoL-selected.ini' else path, *args, **kwargs)
with patch.object(Path, 'read_text', read):
    command = json.loads(sys.argv[2])
    with patch.object(cli.native, 'prepare') as prepare:
        result = cli.main(command)
        if result == 0 and command[0] == 'prepare':
            assert prepare.call_args.args[4]['suite'] == 'engine'
    if result == 0 and command == ['matrix']:
        catalog = cli.adapters.definitions()
        for suite in ('food', 'fitness', 'radio-settings', 'shelf-book-tv', 'custom-tags'):
            assert catalog[suite]['default_mods'] == ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit']
        for suite, scenario in (('queue-recovery', 'cancelled-remainder'),
                                ('approach-queue', 'native-cursor-approach')):
            expected = ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit']
            assert catalog[suite]['default_mods'] == expected
            assert catalog[suite]['scenario_actions'][scenario]['mods'] == expected
            # Run the real registration assertions against the alternate INI too.
            from importlib import import_module
            test = import_module('tests.test_queue_recovery_adapter' if suite == 'queue-recovery'
                                 else 'tests.test_queue_approach_adapter')
            case = (test.RecoveryAdapterTests('test_registration_full_pack_selection_and_staging')
                    if suite == 'queue-recovery' else
                    test.ApproachAdapterTests('test_registration_selected_pack_and_staging'))
            case.debug()
    raise SystemExit(result)
"""


class CatalogSelectionTests(unittest.TestCase):
    def probe(self, text, command=None):
        with tempfile.TemporaryDirectory() as directory:
            ini = Path(directory) / 'selected.ini'
            if text is not None:
                ini.write_text(text, encoding='utf-8')
            environment = dict(os.environ, PYTHONPATH=os.pathsep.join(map(str, (ROOT / 'tools', ROOT))),
                               PYTHONDONTWRITEBYTECODE='1')
            return subprocess.run([sys.executable, '-c', CATALOG_PROBE, str(ini), json.dumps(command or ['matrix'])],
                                  cwd=directory, env=environment, text=True, capture_output=True)

    def test_catalog_accepts_selected_ini_formatting_without_changing_order(self):
        mods = 'ZombieBuddy;PZToolkitJavaPatches;PZSurvivorToolkit'
        for text in ('Mods=' + mods + '\n', ' # selected pack\n  Mods = ' + mods + '  \n',
                     '\ufeffMods=' + mods + '\r\n'):
            with self.subTest(text=text):
                result = self.probe(text)
                self.assertEqual(0, result.returncode, result.stderr)
                self.assertIn('engine | ', result.stdout)

    def test_selected_commands_do_not_read_an_unrelated_pack(self):
        for command in (['matrix', '--suite', 'engine'],
                        ['matrix', '--suite', 'engine', '--suite', 'startup'],
                        ['prepare', '/unused/run', '--suite', 'engine', '--game', '/game', '--jdk', '/jdk']):
            for text in ('Mods=Duplicate;Duplicate\n', None):
                with self.subTest(command=command, text=text):
                    result = self.probe(text, command)
                    self.assertEqual(0, result.returncode, result.stderr)
                    self.assertNotIn('food | ', result.stdout)

    def test_selected_pack_adapter_keeps_its_own_input_validation(self):
        result = self.probe('Mods=Duplicate;Duplicate\n', ['matrix', '--suite', 'food'])
        self.assertEqual(1, result.returncode)
        self.assertIn('ERROR: Selected pack contains invalid or duplicate Mod IDs', result.stderr)
        self.assertNotIn('Traceback', result.stderr)
        self.assertEqual('', result.stdout)

    def test_unknown_suite_is_reported_before_unrelated_adapter_imports(self):
        result = self.probe('Mods=Duplicate;Duplicate\n', ['matrix', '--suite', 'typo'])
        self.assertEqual(1, result.returncode)
        self.assertIn('Unknown suites: typo', result.stderr)
        self.assertIn('food', result.stderr)
        self.assertIn('health', result.stderr)
        self.assertNotIn('Traceback', result.stderr)
        self.assertEqual('', result.stdout)

    def test_catalog_reports_invalid_selected_ids_without_an_import_traceback(self):
        for mods in ('First;First', 'First;;Second', 'First; Second', '../First', ''):
            with self.subTest(mods=mods):
                result = self.probe('Mods=' + mods + '\n')
                self.assertEqual(1, result.returncode)
                self.assertIn('ERROR: Selected pack contains invalid or duplicate Mod IDs', result.stderr)
                self.assertNotIn('Traceback', result.stderr)
                self.assertEqual('', result.stdout)


if __name__ == '__main__':
    unittest.main()
