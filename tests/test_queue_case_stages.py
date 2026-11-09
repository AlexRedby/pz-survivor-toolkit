"""Case boundaries classify fixture failures independently of initial readiness."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks.case_stages import CaseStages, PREFIX, audit


class CaseStageTests(unittest.TestCase):
    def setUp(self):
        self.runtime = {'fixture': {'case_stages': {'version': 1}, 'preflight': {'token': 'a' * 32}}}
        self.selection = dict(suite='device-target-loss', kind='sp', cases=['tv-remove', 'radio-move'])
        self.execution = dict(status='running')

    def receipt(self, stage='setup', status='started', case='tv-remove', role='client1', **fields):
        row = dict(token='a' * 32, suite=self.selection['suite'], role=role, case=case, stage=stage, status=status)
        row.update(fields)
        return PREFIX + json.dumps(row) + '\n'

    def timeline(self, case='tv-remove', role='client1'):
        return ''.join(self.receipt(stage, status, case, role) for stage, status in (
            ('setup', 'started'), ('gameplay', 'started'), ('cleanup', 'started'), ('cleanup', 'passed')))

    def check(self, text, *, final=False, **logs):
        return CaseStages(self.runtime, self.selection).check(dict(client1=text, **logs), self.execution, final=final)

    def test_both_cases_with_native_stamps_complete_and_repeated_scans_are_idempotent(self):
        text = self.timeline() + self.timeline('radio-move')
        text = ''.join('LOG  : Lua, 123> ' + line + '\n' for line in text.splitlines())
        self.execution['status'] = 'completed'
        for _ in range(2):
            self.check(text, final=True)
            self.assertEqual(8, len(self.execution['case_stages']['receipts']['client1']))
            self.assertNotIn('setup_failure', self.execution)

    def test_per_case_setup_failure_is_not_erased_by_generic_completion(self):
        text = self.timeline() + self.receipt(case='radio-move')
        text += self.receipt(status='failed', case='radio-move', reason='No clear loaded native device walking corridor')
        text += '[QUEUE_CHECK] {"event":"complete"}\n'
        with self.assertRaisesRegex(RuntimeError, 'corridor'):
            self.check(text)
        finding = self.execution['setup_failure']
        self.assertEqual(('fixture-case-setup', 'fixture-setup', 'radio-move', 'client1'),
            tuple(finding[key] for key in ('kind', 'phase', 'case', 'role')))
        self.assertEqual(6, finding['evidence']['line'])
        original = copy.deepcopy(finding)
        with self.assertRaises(RuntimeError):
            self.check(text, final=True)
        self.assertEqual(original, self.execution['setup_failure'])

    def test_cleanup_failure_is_infrastructure_and_preserves_first_failure(self):
        text = self.timeline().rsplit(PREFIX, 1)[0] + self.receipt('cleanup', 'failed', reason='owned objects remain')
        with self.assertRaisesRegex(RuntimeError, 'owned objects'):
            self.check(text)
        self.assertEqual('fixture-case-cleanup', self.execution['setup_failure']['kind'])
        first = self.execution['setup_failure']
        with self.assertRaises(RuntimeError):
            self.check(self.receipt() + self.receipt(status='failed', reason='later'))
        self.assertIs(first, self.execution['setup_failure'])

    def test_gameplay_failure_stays_functional_even_with_setup_words(self):
        for final in (False, True):
            with self.subTest(final=final):
                self.execution = dict(status='failed')
                text = self.receipt() + self.receipt('gameplay')
                text += self.receipt('gameplay', 'failed', reason='fixture setup mentioned by gameplay assertion')
                with self.assertRaisesRegex(RuntimeError, 'gameplay assertion'):
                    self.check(text, final=final)
                self.assertNotIn('setup_failure', self.execution)

    def test_failed_execution_is_classified_from_active_stage_not_error_words(self):
        for stage in ('setup', 'gameplay', 'cleanup'):
            with self.subTest(stage=stage):
                self.execution = dict(status='failed', error='process exited')
                text = self.receipt()
                if stage != 'setup': text += self.receipt('gameplay')
                if stage == 'cleanup': text += self.receipt('cleanup')
                if stage == 'gameplay':
                    self.check(text, final=True)
                    self.assertNotIn('setup_failure', self.execution)
                else:
                    with self.assertRaisesRegex(RuntimeError, 'process exited'):
                        self.check(text, final=True)
                    self.assertEqual('fixture-case-' + stage, self.execution['setup_failure']['kind'])

    def test_failed_gameplay_after_verified_cleanup_may_leave_next_case_unstarted(self):
        self.execution.update(status='failed', error='safe target outcome not observed')
        self.check(self.timeline(), final=True)
        self.assertNotIn('setup_failure', self.execution)

    def test_streaming_partial_waits_but_terminal_partial_is_invalid(self):
        text = self.receipt() + PREFIX + '{"stage":'
        self.check(text)
        self.assertNotIn('setup_failure', self.execution)
        with self.assertRaisesRegex(RuntimeError, 'Malformed'):
            self.check(text, final=True)
        self.assertEqual('fixture-case-stage-protocol', self.execution['setup_failure']['kind'])

    def test_receipts_cannot_change_their_run_role_suite_or_selected_case(self):
        for fields in ({'token': 'b' * 32}, {'role': 'server'}, {'suite': 'other'}, {'case': 'unselected'},
                       {'case': 'radio-move'}, {'reason': 'unexpected'}):
            with self.subTest(fields=fields):
                self.execution = dict(status='running')
                with self.assertRaisesRegex(RuntimeError, 'Mismatched'):
                    self.check(self.receipt(**fields))

    def test_duplicate_reversed_and_incomplete_transitions_fail_closed(self):
        for text in (self.receipt('gameplay'), self.receipt() * 2,
                     self.receipt() + self.receipt('cleanup'),
                     self.receipt() + self.receipt('setup', 'passed'),
                     self.timeline() + self.timeline(), self.receipt(status='failed', reason='no start'),
                     self.receipt() + self.receipt(status='failed', reason='')):
            with self.subTest(text=text):
                self.execution = dict(status='running')
                with self.assertRaises(RuntimeError): self.check(text)
                self.assertEqual('fixture-case-stage-protocol', self.execution['setup_failure']['kind'])
        for text in ('', self.receipt(), self.timeline()):
            self.execution = dict(status='completed')
            with self.assertRaisesRegex(RuntimeError, 'Missing required'):
                self.check(text, final=True)

    def test_missing_peer_receipts_are_not_hidden_by_other_peer_gameplay(self):
        self.selection.update(kind='mp', clients=2)
        self.execution['status'] = 'failed'
        with self.assertRaisesRegex(RuntimeError, 'Missing required'):
            self.check(self.timeline(), final=True)
        self.assertEqual('client2', self.execution['setup_failure']['role'])

    def test_missing_peer_receipts_also_win_over_explicit_gameplay_failure(self):
        self.selection.update(kind='mp', clients=2)
        self.execution['status'] = 'failed'
        text = self.receipt() + self.receipt('gameplay') + self.receipt('gameplay', 'failed', reason='gameplay')
        with self.assertRaisesRegex(RuntimeError, 'Missing required'):
            self.check(text, final=True)
        self.assertEqual('client2', self.execution['setup_failure']['role'])

    def test_report_metadata_corruption_produces_auditable_protocol_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / 'runtime.json'
            for content in ('{', '[]', '{"fixture":null}', '{"fixture":{"case_stages":null}}'):
                with self.subTest(content=content):
                    path.write_text(content)
                    failure, issues = audit(root, self.selection, self.execution)
                    self.assertEqual('fixture-case-stage-protocol', failure['kind'])
                    self.assertTrue(issues)

    def test_other_peer_setup_failure_wins_over_gameplay_failure(self):
        self.selection.update(kind='mp', clients=2)
        text = self.receipt() + self.receipt('gameplay') + self.receipt('gameplay', 'failed', reason='gameplay')
        peer = self.receipt(role='client2') + self.receipt(role='client2', status='failed', reason='peer setup')
        with self.assertRaisesRegex(RuntimeError, 'peer setup'):
            self.check(text, client2=peer)
        self.assertEqual('client2', self.execution['setup_failure']['role'])

    def test_legacy_is_opt_in_and_malformed_declaration_never_silently_disables_it(self):
        CaseStages({}, self.selection).check({'client1': PREFIX + 'bad'}, self.execution, final=True)
        self.assertNotIn('case_stages', self.execution)
        for contract in (None, {}, {'version': True}, {'version': 2}, {'version': 1, 'extra': True}):
            with self.subTest(contract=contract), self.assertRaises(ValueError):
                CaseStages({'fixture': dict(self.runtime['fixture'], case_stages=contract)}, self.selection)

    def test_report_audit_uses_sealed_logs_and_keeps_execution_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'runtime.json').write_text(json.dumps(self.runtime))
            text = self.receipt() + self.receipt(status='failed', reason='late setup failure')
            (root / 'client1-launch.log').write_text(text)
            execution = dict(status='completed')
            failure, issues = audit(root, self.selection, execution)
            self.assertEqual('fixture-case-setup', failure['kind'])
            self.assertIn('late setup failure', issues[0])
            self.assertEqual({'status': 'completed'}, execution)
            (root / 'client1-launch.log').write_text(self.receipt() + self.receipt('gameplay')
                + self.receipt('gameplay', 'failed', reason='gameplay'))
            failure, issues = audit(root, self.selection, {'status': 'failed'})
            self.assertIsNone(failure)
            self.assertTrue(issues)


if __name__ == '__main__':
    unittest.main()
