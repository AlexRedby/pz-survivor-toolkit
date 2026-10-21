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
                self.assertEqual(list(food.SMART_CASES), scenarios.select(self.suite, 'success-queued', 'eat-smart-portions', kind, mode)[0])
                self.assertEqual(list(food.SMART_CASES), scenarios.select(self.suite, 'repeat-same', 'eat-smart-portions', kind, mode)[0])
                self.assertEqual([food.SMART_MOVE_CASE], scenarios.select(self.suite, 'move-independent', 'eat-smart-portions', kind, mode)[0])
                self.assertEqual([food.SMART_CANCEL_CASE], scenarios.select(self.suite, 'cancel-waiting', 'eat-smart-portions', kind, mode)[0])
                self.assertEqual(list(food.UTENSIL_CASES), scenarios.select(self.suite, 'success-queued', 'eat-utensils', kind, mode)[0])
                self.assertEqual(list(food.UTENSIL_CASES), scenarios.select(self.suite, 'repeat-same', 'eat-utensils', kind, mode)[0])
                self.assertEqual([food.UTENSIL_MOVE_CASE], scenarios.select(self.suite, 'move-independent', 'eat-utensils', kind, mode)[0])
                self.assertEqual([food.UTENSIL_CANCEL_CASE], scenarios.select(self.suite, 'cancel-waiting', 'eat-utensils', kind, mode)[0])
                self.assertEqual(list(food.COOKABLE_CASES), scenarios.select(self.suite, 'success-queued', 'eat-cookable', kind, mode)[0])
                self.assertEqual(list(food.COOKABLE_CASES), scenarios.select(self.suite, 'repeat-same', 'eat-cookable', kind, mode)[0])
                self.assertEqual([food.COOKED_MOVE_CASE, food.RAW_MOVE_CASE], scenarios.select(self.suite, 'move-independent', 'eat-cookable', kind, mode)[0])
                self.assertEqual([food.COOKED_CANCEL_CASE, food.RAW_CANCEL_CASE], scenarios.select(self.suite, 'cancel-waiting', 'eat-cookable', kind, mode)[0])
                self.assertEqual(list(food.REPLACEMENT_CASES), scenarios.select(self.suite, 'success-queued', 'eat-cooking-replacement', kind, mode)[0])
                self.assertEqual(list(food.REPLACEMENT_CASES), scenarios.select(self.suite, 'repeat-same', 'eat-cooking-replacement', kind, mode)[0])
                self.assertEqual([food.REPLACEMENT_MOVE_CASE], scenarios.select(self.suite, 'move-independent', 'eat-cooking-replacement', kind, mode)[0])
                self.assertEqual([food.REPLACEMENT_CANCEL_CASE], scenarios.select(self.suite, 'cancel-waiting', 'eat-cooking-replacement', kind, mode)[0])
                self.assertEqual(list(food.CONSUMPTION_CASES), scenarios.select(self.suite, 'success-queued', 'eat-consumption-replacement', kind, mode)[0])
                self.assertEqual(list(food.CONSUMPTION_CASES), scenarios.select(self.suite, 'repeat-same', 'eat-consumption-replacement', kind, mode)[0])
                self.assertEqual([food.CONSUMPTION_MOVE_CASE], scenarios.select(self.suite, 'move-independent', 'eat-consumption-replacement', kind, mode)[0])
                self.assertEqual([food.CONSUMPTION_CANCEL_CASE], scenarios.select(self.suite, 'cancel-waiting', 'eat-consumption-replacement', kind, mode)[0])
        with self.assertRaisesRegex(ValueError, 'not implemented'):
            scenarios.select(self.suite, 'cancel-active', 'eat-portions', 'sp', 'toolkit')

    def test_measured_effects_and_edit_flags_have_distinct_native_expectations(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                recorded = self.recorded(kind, mode)
                for action in ('eat-portions', 'eat-transfers', 'eat-smart-portions', 'eat-utensils', 'eat-cookable', 'eat-cooking-replacement', 'eat-consumption-replacement'):
                    self.assertEqual('passed', self.row(recorded, action, 'success-queued', kind, mode)['status'])
                    self.assertEqual('passed' if kind == 'mp' else 'not-applicable',
                                     self.row(recorded, action, 'server-authority', kind, mode)['status'])
                for action in ('eat-portions', 'eat-smart-portions', 'eat-utensils', 'eat-cookable', 'eat-cooking-replacement', 'eat-consumption-replacement'):
                    self.assertEqual('passed', self.row(recorded, action, 'repeat-same', kind, mode)['status'])
                for action, scenario in [('eat-portions', 'move-independent'), ('eat-portions', 'cancel-waiting'),
                                         ('eat-transfers', 'move-dependent'), ('eat-portions', 'move-dependent'),
                                         ('eat-smart-portions', 'move-independent'), ('eat-smart-portions', 'cancel-waiting'),
                                         ('eat-utensils', 'move-independent'), ('eat-utensils', 'cancel-waiting'),
                                         ('eat-cookable', 'move-independent'), ('eat-cookable', 'cancel-waiting'),
                                         ('eat-cooking-replacement', 'move-independent'), ('eat-cooking-replacement', 'cancel-waiting'),
                                         ('eat-consumption-replacement', 'move-independent'), ('eat-consumption-replacement', 'cancel-waiting')]:
                    self.assertEqual('passed' if mode == 'toolkit' else 'not-applicable',
                                     self.row(recorded, action, scenario, kind, mode)['status'])

    def test_extra_weight_cases_require_effects_and_actual_queue_edits(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.assertEqual(list(food.EXTRA_WEIGHT_CASES),
                                 scenarios.select(self.suite, 'success-queued', 'eat-extra-weight', kind, mode)[0])
                recorded = self.recorded(kind, mode)
                self.assertEqual('passed', self.row(recorded, 'eat-extra-weight', 'success-queued', kind, mode)['status'])
                for scenario in ('move-independent', 'cancel-waiting'):
                    self.assertEqual('passed' if mode == 'toolkit' else 'not-applicable',
                                     self.row(recorded, 'eat-extra-weight', scenario, kind, mode)['status'])
                self.assertEqual('unimplemented', self.row(recorded, 'eat-extra-weight', 'return-items', kind, mode)['status'])

    def test_custom_weight_cases_have_separate_native_and_toolkit_coverage(self):
        action = 'eat-custom-weight'
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.assertEqual(list(food.CUSTOM_WEIGHT_CASES),
                                 scenarios.select(self.suite, 'success-queued', action, kind, mode)[0])
                recorded = self.recorded(kind, mode)
                for scenario in ('success-queued', 'repeat-same'):
                    self.assertEqual('passed', self.row(recorded, action, scenario, kind, mode)['status'])
                for scenario in ('move-independent', 'cancel-waiting'):
                    self.assertEqual('passed' if mode == 'toolkit' else 'not-applicable',
                                     self.row(recorded, action, scenario, kind, mode)['status'])
                recorded['coverage'] = [row for row in recorded['coverage']
                                        if row['case'] not in food.CUSTOM_WEIGHT_CASES]
                self.assertNotEqual('passed', self.row(recorded, action, 'success-queued', kind, mode)['status'])
        for scenario in ('cancel-active', 'physical-input'):
            with self.assertRaises(ValueError):
                scenarios.select(self.suite, scenario, action, 'sp', 'toolkit')

    def test_smart_scope_and_coverage_remain_separate_from_ordinary_food(self):
        smart = self.suite['scenario_actions']['eat-smart-portions']
        self.assertEqual({'success-queued', 'repeat-same', 'move-independent', 'cancel-waiting', 'server-authority'},
                         set(smart['checks']))
        for phrase in ('ES_subMenuEat', '15 then 5', 'original-food', 'Native controls', 'No physical menu input'):
            self.assertIn(phrase, smart['scope'])
        for action in ('eat-portions', 'eat-transfers'):
            self.assertFalse(set(food.SMART_CASES) & {case for binding in
                             self.suite['scenario_actions'][action]['checks'].values() for case in binding})
        for scenario in ('move-dependent', 'cancel-active', 'presentation', 'physical-input'):
            with self.subTest(scenario=scenario), self.assertRaisesRegex(ValueError, 'not implemented'):
                scenarios.select(self.suite, scenario, 'eat-smart-portions', 'sp', 'toolkit')
        original = self.recorded()
        for case in food.SMART_CASES:
            changed = copy.deepcopy(original)
            changed['coverage'] = [row for row in changed['coverage'] if row['case'] != case]
            self.assertNotEqual('passed', self.row(changed, 'eat-smart-portions', 'success-queued')['status'])
            self.assertEqual('passed', self.row(changed, 'eat-portions', 'success-queued')['status'])
        changed = copy.deepcopy(original)
        for row in changed['coverage']:
            if row['case'] in food.SMART_CASES: row['outcome']['pendingRequestsVerified'] = 1
        self.assertNotEqual('passed', self.row(changed, 'eat-smart-portions', 'repeat-same')['status'])

    def test_utensil_scope_and_coverage_are_separate_and_require_both_exact_cases(self):
        utensil = self.suite['scenario_actions']['eat-utensils']
        self.assertEqual({'success-queued', 'repeat-same', 'move-independent', 'cancel-waiting', 'server-authority'},
                         set(utensil['checks']))
        for phrase in ('Base.OatsRaw', '.625 then .125', 'broken root fork', '232', 'No utensil transfers'):
            self.assertIn(phrase, utensil['scope'])
        for action in ('eat-portions', 'eat-transfers', 'eat-smart-portions'):
            self.assertFalse(set(food.UTENSIL_CASES) & {case for binding in
                             self.suite['scenario_actions'][action]['checks'].values() for case in binding})
        for scenario in ('move-dependent', 'cancel-active', 'presentation', 'physical-input'):
            with self.subTest(scenario=scenario), self.assertRaisesRegex(ValueError, 'not implemented'):
                scenarios.select(self.suite, scenario, 'eat-utensils', 'sp', 'toolkit')
        original = self.recorded()
        for case in food.UTENSIL_CASES:
            changed = copy.deepcopy(original)
            changed['coverage'] = [row for row in changed['coverage'] if row['case'] != case]
            self.assertNotEqual('passed', self.row(changed, 'eat-utensils', 'success-queued')['status'])
            self.assertEqual('passed', self.row(changed, 'eat-portions', 'success-queued')['status'])
            self.assertEqual('passed', self.row(changed, 'eat-smart-portions', 'success-queued')['status'])
        changed = copy.deepcopy(original)
        for row in changed['coverage']:
            if row['case'] in food.UTENSIL_CASES: row['outcome']['pendingRequestsVerified'] = 1
        self.assertNotEqual('passed', self.row(changed, 'eat-utensils', 'repeat-same')['status'])

    def test_cookable_scope_requires_all_four_cases_and_preserves_other_food_coverage(self):
        cookable = self.suite['scenario_actions']['eat-cookable']
        self.assertEqual({'success-queued', 'repeat-same', 'move-independent', 'cancel-waiting', 'server-authority'},
                         set(cookable['checks']))
        for phrase in ('Base.ChickenFillet', 'Base.Cabbage', '.5 then .25', '232', '1.3 multiplier', 'No utensils'):
            self.assertIn(phrase, cookable['scope'])
        for action in ('eat-portions', 'eat-transfers', 'eat-smart-portions', 'eat-utensils'):
            self.assertFalse(set(food.COOKABLE_CASES) & {case for binding in
                             self.suite['scenario_actions'][action]['checks'].values() for case in binding})
        for scenario in ('move-dependent', 'cancel-active', 'presentation', 'physical-input'):
            with self.subTest(scenario=scenario), self.assertRaisesRegex(ValueError, 'not implemented'):
                scenarios.select(self.suite, scenario, 'eat-cookable', 'sp', 'toolkit')
        original = self.recorded()
        for case in food.COOKABLE_CASES:
            changed = copy.deepcopy(original)
            changed['coverage'] = [row for row in changed['coverage'] if row['case'] != case]
            self.assertNotEqual('passed', self.row(changed, 'eat-cookable', 'success-queued')['status'])
            for action in ('eat-portions', 'eat-transfers', 'eat-smart-portions', 'eat-utensils'):
                self.assertEqual('passed', self.row(changed, action, 'success-queued')['status'])
        changed = copy.deepcopy(original)
        for row in changed['coverage']:
            if row['case'] in food.COOKABLE_CASES: row['outcome']['pendingRequestsVerified'] = 1
        self.assertNotEqual('passed', self.row(changed, 'eat-cookable', 'repeat-same')['status'])

    def test_cooking_replacement_scope_is_separate_and_never_claims_active_cooking(self):
        replacement = self.suite['scenario_actions']['eat-cooking-replacement']
        self.assertEqual({'success-queued', 'repeat-same', 'move-independent', 'cancel-waiting', 'server-authority'},
                         set(replacement['checks']))
        for phrase in ('Base.BreadSlices', 'ReplaceOnCooked=Base.Toast', '.5 then .25', '232',
                       'Cooking time stays zero', 'no Toast is added', 'No active or hot cooking', 'cooking callbacks'):
            self.assertIn(phrase, replacement['scope'])
        for action in ('eat-portions', 'eat-transfers', 'eat-smart-portions', 'eat-utensils', 'eat-cookable'):
            self.assertFalse(set(food.REPLACEMENT_CASES) & {case for binding in
                             self.suite['scenario_actions'][action]['checks'].values() for case in binding})
        self.assertFalse(set(food.COOKABLE_CASES) & {case for binding in replacement['checks'].values() for case in binding})
        for scenario in ('move-dependent', 'cancel-active', 'presentation', 'physical-input'):
            with self.subTest(scenario=scenario), self.assertRaisesRegex(ValueError, 'not implemented'):
                scenarios.select(self.suite, scenario, 'eat-cooking-replacement', 'sp', 'toolkit')
        original = self.recorded()
        for case in food.REPLACEMENT_CASES:
            changed = copy.deepcopy(original)
            changed['coverage'] = [row for row in changed['coverage'] if row['case'] != case]
            self.assertNotEqual('passed', self.row(changed, 'eat-cooking-replacement', 'success-queued')['status'])
            for action in ('eat-portions', 'eat-transfers', 'eat-smart-portions', 'eat-utensils', 'eat-cookable'):
                self.assertEqual('passed', self.row(changed, action, 'success-queued')['status'])
        changed = copy.deepcopy(original)
        for row in changed['coverage']:
            if row['case'] in food.REPLACEMENT_CASES: row['outcome']['pendingRequestsVerified'] = 1
        self.assertNotEqual('passed', self.row(changed, 'eat-cooking-replacement', 'repeat-same')['status'])

    def test_consumption_replacement_scope_requires_matched_cases_without_depletion_claims(self):
        consumption = self.suite['scenario_actions']['eat-consumption-replacement']
        self.assertEqual({'success-queued', 'repeat-same', 'move-independent', 'cancel-waiting', 'server-authority'},
                         set(consumption['checks']))
        for phrase in ('Base.CannedPeachesOpen', 'ReplaceOnUse=Base.TinCanEmpty', '.5 then .25', '232',
                       '.2 can', '.6 food', 'no empty can is added', 'No full depletion', 'custom weight', 'extra items'):
            self.assertIn(phrase, consumption['scope'])
        other_actions = ('eat-portions', 'eat-transfers', 'eat-smart-portions', 'eat-utensils', 'eat-cookable', 'eat-cooking-replacement')
        for action in other_actions:
            self.assertFalse(set(food.CONSUMPTION_CASES) & {case for binding in
                             self.suite['scenario_actions'][action]['checks'].values() for case in binding})
        self.assertEqual(set(food.CONSUMPTION_CASES), {case for binding in consumption['checks'].values() for case in binding})
        for scenario in ('move-dependent', 'cancel-active', 'presentation', 'physical-input'):
            with self.subTest(scenario=scenario), self.assertRaisesRegex(ValueError, 'not implemented'):
                scenarios.select(self.suite, scenario, 'eat-consumption-replacement', 'sp', 'toolkit')
        original = self.recorded()
        for case in food.CONSUMPTION_CASES:
            changed = copy.deepcopy(original)
            changed['coverage'] = [row for row in changed['coverage'] if row['case'] != case]
            self.assertNotEqual('passed', self.row(changed, 'eat-consumption-replacement', 'success-queued')['status'])
            for action in other_actions:
                self.assertEqual('passed', self.row(changed, action, 'success-queued')['status'])
        changed = copy.deepcopy(original)
        for row in changed['coverage']:
            if row['case'] in food.CONSUMPTION_CASES: row['outcome']['pendingRequestsVerified'] = 1
        self.assertNotEqual('passed', self.row(changed, 'eat-consumption-replacement', 'repeat-same')['status'])

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
