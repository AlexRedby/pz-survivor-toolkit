"""Host source gates consume selected overlays and require complete receipts."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import borrowing_check as check


class BorrowingCheckTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.project, self.game = self.root / 'project', self.root / 'game'
        self.toolkit, self.p4 = self.root / 'candidate-toolkit', self.root / 'selected-p4'
        self.locations = {'PZSurvivorToolkit': self.toolkit, 'P4TidyUpMeister': self.p4}
        for source in check.sources(self.project):
            self.write(source, 'check source')
        self.upstream = ('media/lua/client/P4TidyUpMeister.lua',
                         'media/lua/shared/TimedActions/P4RestoreAction.lua',
                         'media/lua/shared/TimedActions/P4RestoreFloorAction.lua')
        for name in self.upstream:
            self.write(self.p4 / 'common' / name, 'common ' + name)
        self.write(self.p4 / '42.20' / self.upstream[0], 'selected override')
        self.value = dict(status='passed', require_complete=True, results=[dict(
            test=check.TEST, variant='default', status='passed',
            checks=[dict(id=key, status='passed', reason=None) for key in check.CHECKS])])
        self.commands = []

    @staticmethod
    def write(path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)

    def run_check(self, command, **kwargs):
        self.commands.append((command, kwargs))
        p4 = Path(command[command.index('--p4-source') + 1])
        self.assertEqual('selected override', (p4 / self.upstream[0]).read_text())
        for name in self.upstream[1:]:
            self.assertEqual('common ' + name, (p4 / name).read_text())
        Path(command[command.index('--report') + 1]).write_text(json.dumps(self.value))
        return SimpleNamespace(stdout='source assertions passed\n', stderr='')

    def invoke(self):
        with patch.object(check.preparation_process, 'run', side_effect=self.run_check):
            return check.qualify(self.project, self.game, self.locations)

    def test_selected_candidate_and_effective_p4_layers_are_used_without_rediscovery(self):
        value, log = self.invoke()
        self.assertEqual(self.value, value)
        self.assertIn('source assertions passed', log)
        command, kwargs = self.commands[0]
        self.assertEqual(str(self.toolkit), command[command.index('--toolkit-source') + 1])
        self.assertEqual(str(self.game / 'media/lua'), command[command.index('--native-action-root') + 1])
        self.assertIn('--require-complete', command)
        self.assertEqual(120, kwargs['timeout'])
        self.assertTrue(kwargs['check'])
        self.assertFalse(Path(command[command.index('--p4-source') + 1]).exists(), 'private overlay leaked')

    def test_missing_selected_source_or_harness_refuses_before_child_launch(self):
        (self.p4 / 'common' / self.upstream[1]).unlink()
        with self.assertRaisesRegex(ValueError, 'Missing selected P4'):
            self.invoke()
        self.assertFalse(self.commands)
        check.sources(self.project)[0].unlink()
        with self.assertRaisesRegex(ValueError, 'Missing borrowing composition source'):
            self.invoke()

    def test_partial_or_missing_completion_cannot_qualify_a_host(self):
        original = copy.deepcopy(self.value)
        for mutation in ('partial', 'missing', 'skipped', 'duplicate', 'other-test', 'invalid-row', 'invalid-report'):
            with self.subTest(mutation=mutation):
                self.value = copy.deepcopy(original)
                if mutation == 'partial':
                    self.value['status'] = 'partial'
                elif mutation == 'missing':
                    self.value['results'][0]['checks'].pop()
                elif mutation == 'skipped':
                    self.value['results'][0]['checks'][0]['status'] = 'skipped'
                elif mutation == 'duplicate':
                    self.value['results'][0]['checks'].append(self.value['results'][0]['checks'][0])
                elif mutation == 'other-test':
                    self.value['results'][0]['test'] = 'unrelated.lua'
                elif mutation == 'invalid-row':
                    self.value['results'][0] = None
                else:
                    self.value = []
                with self.assertRaisesRegex(ValueError, 'requires all four'):
                    self.invoke()

    def test_child_failure_is_explicit_and_does_not_become_a_skip(self):
        for error in (subprocess.CalledProcessError(1, ['python'], stderr='pickup not earned'),
                      subprocess.TimeoutExpired(['python'], 120, stderr=b'pickup not earned')):
            with self.subTest(error=type(error)), \
                 patch.object(check.preparation_process, 'run', side_effect=error), \
                 self.assertRaisesRegex(ValueError, 'pickup not earned'):
                check.qualify(self.project, self.game, self.locations)

    def test_only_affected_selected_p4_host_banks_require_the_gate(self):
        base = dict(kind='mp', suite='book-controls', cases=['world.header-cancel'],
                    mods=['PZSurvivorToolkit', 'P4TidyUpMeister'], options={'mp_host': True})
        for change in ({}, {'suite': 'equipment', 'cases': ['tidy-group']},
                       {'suite': 'equipment', 'cases': ['bulk-pickup']},
                       {'suite': 'fitness', 'cases': ['storage-peer-pickup']},
                       {'suite': 'fitness', 'cases': ['multi-storage-closed']}):
            self.assertTrue(check.required(dict(base, **change)))
        for change in ({'kind': 'sp'}, {'options': {}}, {'mods': ['PZSurvivorToolkit']},
                       {'cases': ['root.header-cancel']}, {'suite': 'startup'},
                       {'suite': 'equipment', 'cases': ['cart-pickup']},
                       {'suite': 'fitness', 'cases': ['bodyweight']}):
            self.assertFalse(check.required(dict(base, **change)))


if __name__ == '__main__':
    unittest.main()
