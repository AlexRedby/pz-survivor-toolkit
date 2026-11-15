"""Independent wring evidence failures must survive a single verifier pass."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

from tests import test_queue_wring_clothing as fixtures

a = fixtures.a
evidence = fixtures.evidence


class WringVerifierDiagnosticsTests(unittest.TestCase):
    def assert_domains(self, issues, *domains):
        self.assertEqual(
            list(domains),
            [issue.split('[', 1)[1].split(']', 1)[0] for issue in issues],
            issues,
        )

    def test_reports_physical_execution_edit_and_profile_failures_together(self):
        result = evidence('sp', 'toolkit', 'root')
        row = result[0]
        row['client']['items']['target']['wetness'] = 60
        row['commands'][0]['progress'] = False
        row['queueIdle'] = False
        row['capacityProfile'] = {}
        before = copy.deepcopy(result)

        issues = a.check_case(*result)

        self.assert_domains(issues, 'physical state', 'pending edits', 'native execution', 'capacity profile')
        self.assertIn('wetness effect', issues[0])
        self.assertIn('native wring progress', issues[2])
        self.assertEqual(before, result, 'reporting must not repair or normalize sealed evidence')

    def test_reports_native_loan_and_carried_preparation_rejections_together(self):
        result = fixtures.WringClothingRestorationProfileTests().sample('toolkit')
        row = result[0]
        row['prepared']['moves'] = []
        row['restoration']['samples'][0]['loaded'] = True

        issues = a.check_case(*result)

        self.assert_domains(issues, 'carried preparation', 'restoration')
        self.assertIn('whole native group move', issues[0])
        self.assertIn('provider or exact loan transitions', issues[1])

    def test_restoration_option_must_match_authoritative_fixture(self):
        for mode in ('native', 'toolkit'):
            result = fixtures.WringClothingRestorationProfileTests().sample(mode)
            result[0]['ids']['restoration'] = False
            result[2]['restoration'] = False
            self.assert_domains(a.check_case(*result), 'restoration')

    def test_wear_swap_rejection_does_not_hide_unrequested_capacity_payload(self):
        result = evidence('sp', 'toolkit', 'wear-swap')
        result[0]['wearSwap']['capacityFresh'] = False
        result[0]['capacityProfile'] = {}

        issues = a.check_case(*result)

        self.assert_domains(issues, 'capacity profile', 'wear swap')
        self.assertIn('Wear final freshness missing', issues[1])

    def test_unusable_fixture_or_authority_stops_dependent_diagnostics(self):
        mutations = (
            lambda r: r.__setitem__(0, None),
            lambda r: r.__setitem__(1, []),
            lambda r: r[0].__setitem__('ids', []),
            lambda r: r[0]['ids'].__setitem__('items', []),
            lambda r: r[0]['ids'].__setitem__('source', []),
            lambda r: r[0]['ids']['items'].__setitem__('target', []),
            lambda r: r[1].__setitem__('options', []),
            lambda r: r[0]['server'].__setitem__('case', 'world'),
        )
        for case in ('root', 'wear-swap'):
            for mutation in mutations:
                result = list(evidence('sp', 'toolkit', case))
                result[0]['commands'][0]['progress'] = False
                result[0]['capacityProfile'] = {}
                mutation(result)
                with self.subTest(case=case, mutation=mutation):
                    self.assert_domains(a.check_case(*result), 'fixture')

    def test_incomplete_host_report_keeps_both_sides_diagnostics_without_accepting_them(self):
        from queue_checks.adapters import wring_clothing_verifier as verifier
        selection = dict(kind='mp', mode='toolkit', cases=['worn-bag'])
        failed = dict(phase='running', state=dict(sections=dict(body=dict(canonicalSame=False))))
        authority = dict(command='Verify', state=dict(ready=False, issues=['source count']))
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'client1-launch.log').write_text(a.PREFIX + 'FAILED_STATE ' + json.dumps(failed) + '\n')
            (root / 'server-launch.log').write_text(a.PREFIX + 'AUTHORITY_WAIT ' + json.dumps(authority) + '\n')
            result = verifier.verify(root, selection, {})
        self.assertTrue(result['issues'], 'diagnostics cannot substitute for missing authority/completion')
        self.assertEqual([], result['outcomes'])
        diagnostics = result['evidence']['diagnostics']
        self.assertEqual(failed, diagnostics['client1']['observations'][0]['payload'])
        self.assertEqual(authority, diagnostics['server']['observations'][0]['payload'])

    def test_diagnostics_are_bounded_and_keep_malformed_observations_visible(self):
        from queue_checks.adapters import wring_clothing_verifier as verifier
        text = '\n'.join(a.PREFIX + 'PREPARED_WAIT ' + json.dumps(dict(index=index)) for index in range(20))
        text += '\n' + a.PREFIX + 'FAILED_STATE invalid-json'
        value = verifier._failure_diagnostics(text)
        self.assertEqual(16, len(value['observations']))
        self.assertEqual(5, value['omitted'])
        self.assertIn('error', value['observations'][-1])
        self.assertEqual('invalid-json', value['observations'][-1]['raw'])

    def test_malformed_independent_domains_fail_closed_without_hiding_others(self):
        result = evidence('sp', 'toolkit', 'root')
        result[0]['client'] = []
        result[0]['commands'] = None
        result[0]['restoration'] = []

        issues = a.check_case(*result)

        self.assert_domains(issues, 'physical state', 'native execution', 'restoration')


if __name__ == '__main__':
    unittest.main()
