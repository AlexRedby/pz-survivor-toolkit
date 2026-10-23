"""The complete native catalog uses the same selected-INI rules as preparation."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

# Redirect only the input file. A fresh process must import every adapter, just
# like the CLI, without an earlier import hiding an import-time parser failure.
CATALOG_PROBE = """
from pathlib import Path
import sys
from unittest.mock import patch
import check_action_queue as cli

original = Path.read_text
fixture = Path(sys.argv[1])
def read(path, *args, **kwargs):
    return original(fixture if path.name == 'SurvivorQoL-selected.ini' else path, *args, **kwargs)
with patch.object(Path, 'read_text', read):
    result = cli.main(['matrix', '--suite', 'engine'])
    if result == 0:
        catalog = cli.adapters.definitions()
        for suite in ('food', 'fitness', 'radio-settings', 'shelf-book-tv'):
            assert catalog[suite]['default_mods'] == ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit']
    raise SystemExit(result)
"""


class CatalogSelectionTests(unittest.TestCase):
    def probe(self, text):
        with tempfile.TemporaryDirectory() as directory:
            ini = Path(directory) / 'selected.ini'
            ini.write_text(text, encoding='utf-8')
            environment = dict(os.environ, PYTHONPATH=str(ROOT / 'tools'), PYTHONDONTWRITEBYTECODE='1')
            return subprocess.run([sys.executable, '-c', CATALOG_PROBE, str(ini)],
                                  cwd=directory, env=environment, text=True, capture_output=True)

    def test_catalog_accepts_selected_ini_formatting_without_changing_order(self):
        mods = 'ZombieBuddy;PZToolkitJavaPatches;PZSurvivorToolkit'
        for text in ('Mods=' + mods + '\n', ' # selected pack\n  Mods = ' + mods + '  \n',
                     '\ufeffMods=' + mods + '\r\n'):
            with self.subTest(text=text):
                result = self.probe(text)
                self.assertEqual(0, result.returncode, result.stderr)
                self.assertIn('engine | ', result.stdout)

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
