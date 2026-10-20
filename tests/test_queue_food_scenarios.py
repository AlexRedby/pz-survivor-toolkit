"""Food mappings retain matched controls and never invent native execution coverage."""
import copy
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import report, scenarios
from queue_checks.adapters import food
import test_queue_food as fixtures


class FoodScenarioTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.FoodAdapterTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.catalog = {'suites': food.definitions()}
        self.suite = self.catalog['suites']['food']

    def recorded(self, kind='sp', mode='toolkit'):
        self.fixture.selection.update(kind=kind, mode=mode)
        checked = self.fixture.verify()
        self.assertEqual([], checked['issues'])
        return dict(run='/tmp/food-contract-unit', status='passed', selection=copy.deepcopy(self.fixture.selection),
                    functional={'status': 'passed'}, provenance={'verified': True},
                    execution={'status': 'completed', 'processes': {role: {'pid': 123 + index, 'exit_code': 0}
                               for index, role in enumerate(['client1', 'server'] if kind == 'mp' else ['client1'])}},
                    coverage=[dict(suite='food', kind=kind, mode=mode, **row) for row in checked['outcomes']])

    def row(self, recorded, action, scenario, kind='sp', mode='toolkit'):
        return next(row for row in report.matrix(self.catalog, [recorded])['scenarios']
                    if (row['action'], row['scenario'], row['kind'], row['mode']) == (action, scenario, kind, mode))

    def test_selected_cases_and_queue_disabled_controls_match(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                cases, mods = scenarios.select(self.suite, 'success-queued', None, kind, mode)
                self.assertEqual(food.CASES, cases)
                self.assertEqual(sorted(food.MODS), mods)
                self.assertEqual([food.MOVE_CASE], scenarios.select(self.suite, 'move-independent', 'eat-portions', kind, mode)[0])
                self.assertEqual([food.CANCEL_CASE], scenarios.select(self.suite, 'cancel-waiting', 'eat-portions', kind, mode)[0])
                self.assertEqual([food.DEPLETION_CASE], scenarios.select(self.suite, 'move-dependent', 'eat-portions', kind, mode)[0])
                self.assertEqual([food.BAG_CASE], scenarios.select(self.suite, 'move-dependent', 'eat-transfers', kind, mode)[0])
        with self.assertRaisesRegex(ValueError, 'not implemented'):
            scenarios.select(self.suite, 'cancel-active', 'eat-portions', 'sp', 'toolkit')

    def test_measured_effects_and_edit_flags_have_distinct_native_expectations(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                recorded = self.recorded(kind, mode)
                for action in ('eat-portions', 'eat-transfers'):
                    self.assertEqual('passed', self.row(recorded, action, 'success-queued', kind, mode)['status'])
                    self.assertEqual('passed' if kind == 'mp' else 'not-applicable',
                                     self.row(recorded, action, 'server-authority', kind, mode)['status'])
                self.assertEqual('passed', self.row(recorded, 'eat-portions', 'repeat-same', kind, mode)['status'])
                for action, scenario in [('eat-portions', 'move-independent'), ('eat-portions', 'cancel-waiting'),
                                         ('eat-transfers', 'move-dependent'), ('eat-portions', 'move-dependent')]:
                    self.assertEqual('passed' if mode == 'toolkit' else 'not-applicable',
                                     self.row(recorded, action, scenario, kind, mode)['status'])

    def test_partial_claims_wrong_types_or_unselected_mods_do_not_gain_passes(self):
        original = self.recorded()
        for fault in ('flag', 'missing-case', 'runtime', 'mod', 'execution', 'provenance'):
            changed = copy.deepcopy(original)
            if fault == 'flag': changed['coverage'][0]['outcome']['pendingRequestsVerified'] = 1
            elif fault == 'missing-case': changed['coverage'].pop(0)
            elif fault == 'runtime': changed['status'] = 'needs-review'
            elif fault == 'mod': changed['selection']['mods'].remove('EatSmartInt')
            elif fault == 'execution': changed['execution']['status'] = 'failed'
            else: changed['provenance']['verified'] = False
            with self.subTest(fault=fault):
                self.assertNotEqual('passed', self.row(changed, 'eat-portions', 'success-queued')['status'])


if __name__ == '__main__':
    unittest.main()
