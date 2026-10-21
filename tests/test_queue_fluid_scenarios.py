"""Fluid contracts require measured dispatch state, not merely an old successful receipt."""
import copy
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import report, scenarios
from queue_checks.adapters import fluid
import test_queue_fluid as fixtures


class FluidScenarioTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.FluidAdapterTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.catalog = {'suites': fluid.definitions()}
        self.suite = self.catalog['suites']['fluid']

    def recorded(self, kind='sp', mode='toolkit'):
        self.fixture.selection.update(kind=kind, mode=mode)
        checked = self.fixture.verify()
        self.assertEqual([], checked['issues'])
        return dict(run='/tmp/fluid-contract-unit', status='passed', selection=copy.deepcopy(self.fixture.selection),
                    functional={'status': 'passed'}, provenance={'verified': True},
                    execution={'status': 'completed', 'processes': {role: {'pid': 123 + index, 'exit_code': 0}
                               for index, role in enumerate(['client1', 'server'] if kind == 'mp' else ['client1'])}},
                    coverage=[dict(suite='fluid', kind=kind, mode=mode, **row) for row in checked['outcomes']])

    def row(self, recorded, action='drink-portions', scenario='success-empty', kind='sp', mode='toolkit'):
        return next(row for row in report.matrix(self.catalog, [recorded])['scenarios']
                    if (row['action'], row['scenario'], row['kind'], row['mode']) == (action, scenario, kind, mode))

    def test_selects_canonical_cases_and_identical_disabled_queue_controls(self):
        for mode in ('native', 'toolkit'):
            cases, mods = scenarios.select(self.suite, 'server-authority', None, 'mp', mode)
            self.assertEqual(fluid.CASES, cases)
            self.assertEqual(sorted(fluid.MODS), mods)
            empty_start_actions = ','.join(self.suite['scenario_actions'])
            self.assertEqual([case for case in fluid.CASES if case not in fluid.EMPTY_CASES],
                             scenarios.select(self.suite, 'success-empty', empty_start_actions, 'mp', mode)[0])
            self.assertEqual(['fluid-bag-pair-queued-favorite'],
                             scenarios.select(self.suite, 'repeat-independent', 'drink-portions', 'mp', mode)[0])
            self.assertEqual(['fluid-bag-same-serial-favorite', 'fluid-root-same-queued-favorite'],
                             scenarios.select(self.suite, 'repeat-same', 'drink-portions', 'mp', mode)[0])
            self.assertEqual(['fluid-root-cancel-waiting-favorite', 'fluid-bag-cancel-waiting-favorite'],
                             scenarios.select(self.suite, 'cancel-waiting', 'drink-portions', 'mp', mode)[0])
        for action, scenario in [('drink-smart', 'repeat-independent'), ('drink-sip', 'physical-input')]:
            with self.subTest(action=action, scenario=scenario), self.assertRaisesRegex(ValueError, 'not implemented'):
                scenarios.select(self.suite, scenario, action, 'mp', 'toolkit')

    def test_exact_effects_support_enabled_and_disabled_queue_contracts(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                recorded = self.recorded(kind, mode)
                for action in self.suite['scenario_actions']:
                    scenario = 'success-queued' if action == 'empty-water' else 'success-empty'
                    self.assertEqual('passed', self.row(recorded, action=action, scenario=scenario, kind=kind, mode=mode)['status'])
                    self.assertEqual('passed' if kind == 'mp' else 'not-applicable',
                                     self.row(recorded, action=action, scenario='server-authority', kind=kind, mode=mode)['status'])
                self.assertEqual('passed', self.row(recorded, scenario='repeat-independent', kind=kind, mode=mode)['status'])
                self.assertEqual('passed', self.row(recorded, scenario='repeat-same', kind=kind, mode=mode)['status'])
                self.assertEqual('passed' if mode == 'toolkit' else 'not-applicable',
                                 self.row(recorded, scenario='cancel-waiting', kind=kind, mode=mode)['status'])
                self.assertEqual('passed' if mode == 'toolkit' else 'not-applicable',
                                 self.row(recorded, scenario='move-independent', kind=kind, mode=mode)['status'])

    def test_pending_transfer_case_selects_matched_controls_and_requires_its_own_evidence(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                selected, _ = scenarios.select(self.suite, 'success-queued,move-dependent', 'drink-transfers', kind, mode)
                self.assertEqual([fluid.EDIT_CASE], selected)
                recorded = self.recorded(kind, mode)
                for scenario in ('success-queued', 'move-dependent'):
                    row = self.row(recorded, action='drink-transfers', scenario=scenario, kind=kind, mode=mode)
                    self.assertEqual('passed' if mode == 'toolkit' else 'not-applicable', row['status'])
                if mode == 'native': continue
                for field in ('pendingTransferEditVerified', 'dependentPickupProtected'):
                    bad = copy.deepcopy(recorded)
                    record = next(record for record in bad['coverage'] if record['case'] == fluid.EDIT_CASE)
                    record['outcome'][field] = 1
                    scenario = 'success-queued' if field == 'pendingTransferEditVerified' else 'move-dependent'
                    self.assertNotEqual('passed', self.row(bad, action='drink-transfers', scenario=scenario, kind=kind)['status'])

    def test_empty_water_scenarios_require_their_own_matched_native_effects(self):
        action = 'empty-water'
        binding = self.suite['scenario_actions'][action]
        self.assertEqual({'success-empty', 'success-queued', 'move-independent', 'cancel-waiting', 'move-dependent', 'server-authority'}, set(binding['checks']))
        for phrase in ('Raw native ISFluidEmptyAction', 'clean-water', 'captured amount', 'constructor durations',
                       'discarded water', 'No empty-menu or physical input', 'active cancellation', 'transfer-capacity'):
            self.assertIn(phrase, binding['scope'])
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.assertEqual(list(fluid.EMPTY_CASES), scenarios.select(self.suite, 'success-queued', action, kind, mode)[0])
                for scenario, case in [('move-independent', fluid.EMPTY_MOVE_CASE), ('cancel-waiting', fluid.EMPTY_CANCEL_CASE),
                                       ('move-dependent', fluid.EMPTY_DEPENDENCY_CASE)]:
                    self.assertEqual([case], scenarios.select(self.suite, scenario, action, kind, mode)[0])
                    recorded = self.recorded(kind, mode)
                    self.assertEqual('passed' if mode == 'toolkit' else 'not-applicable',
                                     self.row(recorded, action, scenario, kind, mode)['status'])
                with self.assertRaisesRegex(ValueError, 'not implemented'):
                    scenarios.select(self.suite, 'physical-input', action, kind, mode)
        recorded = self.recorded()
        for case in fluid.EMPTY_CASES:
            bad = copy.deepcopy(recorded)
            bad['coverage'] = [row for row in bad['coverage'] if row['case'] != case]
            self.assertNotEqual('passed', self.row(bad, action, 'success-queued')['status'])
            self.assertEqual('passed', self.row(bad, 'drink-portions', 'success-empty')['status'])
        bad = copy.deepcopy(recorded)
        next(row for row in bad['coverage'] if row['case'] == fluid.EMPTY_DEPENDENCY_CASE)['outcome']['dependentEmptyProtected'] = 1
        self.assertNotEqual('passed', self.row(bad, action, 'move-dependent')['status'])

    def test_direct_scenarios_require_their_own_case_and_do_not_borrow_pending_anchor_coverage(self):
        for action, case in [('empty-water', fluid.DIRECT_EMPTY_CASE), ('drink-all-tail', fluid.DIRECT_ALL_CASE)]:
            for kind in ('sp', 'mp'):
                for mode in ('native', 'toolkit'):
                    with self.subTest(action=action, kind=kind, mode=mode):
                        self.assertEqual([case], scenarios.select(self.suite, 'success-empty', action, kind, mode)[0])
                        recorded = self.recorded(kind, mode)
                        self.assertEqual('passed', self.row(recorded, action, 'success-empty', kind, mode)['status'])
                        bad = copy.deepcopy(recorded)
                        bad['coverage'] = [row for row in bad['coverage'] if row['case'] != case]
                        self.assertNotEqual('passed', self.row(bad, action, 'success-empty', kind, mode)['status'])
                        if action == 'empty-water':
                            self.assertEqual('passed', self.row(bad, action, 'success-queued', kind, mode)['status'])
                        for value in (None, False, 1):
                            bad = copy.deepcopy(recorded)
                            target = next(row for row in bad['coverage'] if row['case'] == case)['outcome']
                            if value is None: target.pop('directFluidTailVerified')
                            else: target['directFluidTailVerified'] = value
                            self.assertNotEqual('passed', self.row(bad, action, 'success-empty', kind, mode)['status'])
            self.assertEqual([case] if action == 'drink-all-tail' else [*fluid.EMPTY_CASES, case],
                             scenarios.select(self.suite, 'server-authority', action, 'mp', 'toolkit')[0])
        binding = self.suite['scenario_actions']['drink-all-tail']
        self.assertEqual({'success-empty', 'server-authority'}, set(binding['checks']))
        for scenario in ('success-queued', 'move-independent', 'cancel-waiting', 'repeat-same', 'physical-input'):
            with self.subTest(scenario=scenario), self.assertRaisesRegex(ValueError, 'not implemented'):
                scenarios.select(self.suite, scenario, 'drink-all-tail', 'mp', 'toolkit')

    def test_historical_and_partial_receipts_do_not_gain_new_coverage(self):
        recorded = self.recorded()
        for fault in ('missing', 'wrong-type', 'missing-case', 'runtime', 'mod'):
            bad = copy.deepcopy(recorded)
            if fault == 'missing':
                for row in bad['coverage']:
                    for field in ('emptyStartVerified', 'effectsVerified', 'wornBagVerified'):
                        row['outcome'].pop(field)
            elif fault == 'wrong-type': bad['coverage'][0]['outcome']['emptyStartVerified'] = 1
            elif fault == 'missing-case': bad['coverage'].pop(0)
            elif fault == 'runtime': bad['status'] = 'needs-review'
            else: bad['selection']['mods'].remove('Drink_Smart')
            with self.subTest(fault=fault):
                self.assertNotEqual('passed', self.row(bad)['status'])
        serial = copy.deepcopy(recorded)
        serial['coverage'] = [row for row in serial['coverage'] if row['case'] != 'fluid-bag-pair-queued-favorite']
        self.assertNotEqual('passed', self.row(serial, scenario='repeat-independent')['status'])

    def test_repeated_and_cancelled_cases_require_their_own_verified_evidence(self):
        recorded = self.recorded()
        for scenario, field, missing_case in (
                ('repeat-same', 'sameBottleRequestsVerified', 'fluid-root-same-queued-favorite'),
                ('cancel-waiting', 'waitingCancelVerified', 'fluid-bag-cancel-waiting-favorite'),
                ('move-independent', 'independentMoveVerified', 'fluid-root-cancel-waiting-favorite')):
            for fault in ('missing', 'integer', 'missing-case'):
                bad = copy.deepcopy(recorded)
                if fault == 'missing-case':
                    bad['coverage'] = [row for row in bad['coverage'] if row['case'] != missing_case]
                else:
                    for row in bad['coverage']:
                        if fault == 'missing': row['outcome'].pop(field)
                        else: row['outcome'][field] = 1
                with self.subTest(scenario=scenario, fault=fault):
                    self.assertNotEqual('passed', self.row(bad, scenario=scenario)['status'])
        for kind in ('sp', 'mp'):
            native = self.recorded(kind, 'native')
            for row in native['coverage']:
                row['outcome']['waitingCancelVerified'] = True
            self.assertEqual('not-applicable', self.row(native, scenario='cancel-waiting', kind=kind, mode='native')['status'],
                             'disabled queue controls cannot claim Toolkit cancellation coverage')


if __name__ == '__main__':
    unittest.main()
