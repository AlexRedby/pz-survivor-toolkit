"""Scenario declarations cannot turn missing/native/unaudited evidence into passes."""
import argparse
import copy
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import check_action_queue as cli
from queue_checks import report, scenarios
from queue_checks.adapters import equipment


class ScenarioTests(unittest.TestCase):
    def setUp(self):
        self.catalog = {'suites': copy.deepcopy(equipment.definitions())}
        self.suite = self.catalog['suites']['equipment']

    def recorded(self, cases=('hands-chain',), **fields):
        return {'run': '/tmp/scenario-unit-fixture', 'status': 'passed',
                'selection': {'suite': 'equipment', 'kind': 'sp', 'mode': 'toolkit', 'clients': 1,
                              'mods': ['PZSurvivorToolkit'], 'cases': list(cases)},
                'functional': {'status': 'passed'}, 'provenance': {'verified': True},
                'execution': {'status': 'completed', 'processes': {'client1': {'pid': 123, 'exit_code': 0}}},
                'coverage': [dict(suite='equipment', case=case, kind='sp', mode='toolkit',
                                  actor='client1', status='passed', outcome=fields.copy()) for case in cases]}

    def row(self, *reports, action='equip-hands', scenario='move-independent', mode='toolkit'):
        return next(row for row in report.matrix(self.catalog, reports)['scenarios']
                    if row['action'] == action and row['scenario'] == scenario and row['kind'] == 'sp' and row['mode'] == mode)

    def test_selection_is_canonical_deduplicated_and_native_control_uses_same_cases(self):
        for mode in ('native', 'toolkit'):
            cases, mods = scenarios.select(self.suite, 'cancel-waiting,move-independent,success-queued',
                                           'equip-hands', 'mp', mode)
            self.assertEqual(cases, ['hands-chain', 'waiting-cancel'])
            self.assertEqual(mods, [])
        self.assertEqual(scenarios.select(self.suite, 'restore-hands', 'tidy-hands', 'sp', 'toolkit'),
                         (['tidy-hands', 'tidy-empty-hands'], ['P4TidyUpMeister']))

    def test_requested_missing_and_inapplicable_scenarios_do_not_silently_run_subset(self):
        for scenario, actions, kind in [('success-empty', 'equip-hands', 'sp'),
                                        ('cancel-waiting', None, 'mp'), ('server-authority', 'equip-hands', 'sp'),
                                        ('success-queued,success-queued', 'equip-hands', 'sp'),
                                        ('typo', 'equip-hands', 'mp'), ('success-queued', 'typo', 'mp')]:
            with self.subTest(scenario=scenario, actions=actions), self.assertRaises(ValueError):
                scenarios.select(self.suite, scenario, actions, kind, 'toolkit')
        self.suite['scenario_actions']['equip-hands']['not_applicable'] = {'success-empty': 'Fixture requires preceding action'}
        with self.assertRaisesRegex(ValueError, 'Fixture requires'):
            scenarios.select(self.suite, 'success-empty', 'equip-hands', 'sp', 'toolkit')

    def test_gaps_control_and_missing_specific_outcome_are_distinct(self):
        self.assertEqual(self.row()['status'], 'not-run')
        self.assertEqual(self.row(scenario='success-empty')['status'], 'unimplemented')
        recorded = self.recorded(policyChecked=True)
        self.assertEqual(self.row(recorded)['status'], 'missing-evidence')
        self.assertEqual(self.row(recorded, mode='native')['status'], 'not-applicable')
        recorded['coverage'][0]['outcome']['independentMoveVerified'] = 1
        self.assertEqual(self.row(recorded)['status'], 'missing-evidence')
        recorded['coverage'][0]['outcome']['independentMoveVerified'] = True
        self.assertEqual(self.row(recorded)['status'], 'passed')

    def test_log_provenance_execution_and_partial_failures_survive_scenario_mapping(self):
        good = self.recorded(independentMoveVerified=True)
        for fault in ('runtime', 'review', 'provenance', 'execution', 'partial', 'actor', 'skipped'):
            bad = copy.deepcopy(good)
            if fault == 'runtime': bad['status'] = 'failed'
            elif fault == 'review': bad['status'] = 'needs-review'
            elif fault == 'provenance': bad['provenance']['verified'] = False
            elif fault == 'execution': bad['execution']['processes']['client1']['exit_code'] = 7
            elif fault == 'partial': bad['coverage'][0]['outcome']['partialCoverage'] = True
            elif fault == 'actor': bad['coverage'][0]['actor'] = 'client2'
            elif fault == 'skipped': bad['coverage'][0]['status'] = 'skipped'
            with self.subTest(fault=fault):
                self.assertNotEqual(self.row(bad)['status'], 'passed')
        self.assertEqual(self.row(good, self.recorded())['status'], 'missing-evidence')

    def test_restore_requires_mod_and_both_occupied_and_empty_hands(self):
        one = self.recorded(('tidy-hands',), restoreVerified=True)
        self.assertEqual(self.row(one, action='tidy-hands', scenario='restore-hands')['status'], 'not-run')
        one['selection']['mods'].append('P4TidyUpMeister')
        self.assertEqual(self.row(one, action='tidy-hands', scenario='restore-hands')['status'], 'not-run')
        both = self.recorded(('tidy-hands', 'tidy-empty-hands'), restoreVerified=True)
        both['selection']['mods'].append('P4TidyUpMeister')
        self.assertEqual(self.row(both, action='tidy-hands', scenario='restore-hands')['status'], 'passed')
        self.assertEqual(self.row(both, action='tidy-hands', scenario='restore-hands', mode='native')['status'], 'not-applicable')

    def test_invalid_contract_fails_and_unmapped_suite_is_visible(self):
        checks = self.suite['scenario_actions']['equip-hands']['checks']
        checks['success-empty'] = {'nonexistent-case': {'success': True}}
        with self.assertRaisesRegex(ValueError, 'known native cases'):
            report.matrix(self.catalog)
        del self.suite['scenario_actions']
        self.assertEqual(report.matrix(self.catalog)['scenarios'][0]['status'], 'unmapped')

    def test_batch_scenario_selection_keeps_control_cases_and_rejects_ambiguous_options(self):
        base = dict(id='equipment', suite='equipment', kind='mp', actions='equip-hands',
                    scenarios='cancel-waiting,success-queued')
        plan = {'mods': 'selected', 'options': {'mp_host': True}}
        control = cli.batch_selection(plan, dict(base, mode='native'), self.catalog, Path('/tmp/plan.json'), {})
        current = cli.batch_selection(plan, dict(base, mode='toolkit'), self.catalog, Path('/tmp/plan.json'), {})
        self.assertEqual(control['cases'], current['cases'])
        self.assertEqual(current['cases'], ['hands-chain', 'waiting-cancel'])
        for invalid in (dict(base, case='hands-chain'), dict(base, actions='tidy-hands', scenarios='restore-hands', mods=['PZSurvivorToolkit']),
                        dict(base, scenarios=''), dict(base, scenarios=None)):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                cli.batch_selection(plan, invalid, self.catalog, Path('/tmp/plan.json'), {})

    def test_shared_helper_is_staged_and_in_source_fingerprints(self):
        helper = ROOT / 'tests/native_queue/support/QueueScenarioChecks.lua'
        selection = dict(suite='equipment', cases=['hands-chain'], kind='sp', mode='toolkit',
                         clients=1, languages=['EN'], mods=['PZSurvivorToolkit'], options={})
        self.assertIn(helper, equipment.sources(ROOT, selection))
        with tempfile.TemporaryDirectory() as tmp:
            shared = Path(tmp) / 'client1/mods/ActionQueueTest/42/media/lua/shared'
            shared.mkdir(parents=True)
            equipment.stage(ROOT, tmp, None, None, selection, {}, {'roles': {'client1': {}}})
            self.assertEqual((shared / helper.name).read_bytes(), helper.read_bytes())

    def test_matrix_cli_filters_both_output_views_without_launching(self):
        with tempfile.TemporaryDirectory() as tmp, patch('sys.stdout', io.StringIO()), \
                patch.object(cli.native, 'prepare') as prepare, patch.object(cli.runner, 'run') as run:
            path = Path(tmp) / 'matrix.json'
            self.assertEqual(cli.main(['matrix', '--scenarios', '--suite', 'equipment', '--kind', 'mp',
                                       '--mode', 'toolkit', '--output', str(path)]), 0)
            value = json.loads(path.read_text())
            self.assertTrue(value['rows'])
            self.assertEqual(value['rows'], value['scenarios'])
            self.assertTrue(all(r['suite'] == 'equipment' and r['kind'] == 'mp' and r['mode'] == 'toolkit' for r in value['rows']))
            prepare.assert_not_called(); run.assert_not_called()
            self.assertEqual(cli.main(['matrix', '--scenarios', '--suite', 'startup', '--kind', 'mp',
                                       '--mode', 'toolkit', '--output', str(path)]), 0)
            self.assertEqual(json.loads(path.read_text())['rows'][0]['status'], 'unmapped')


if __name__ == '__main__':
    unittest.main()
