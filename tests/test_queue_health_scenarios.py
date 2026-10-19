"""Unit checks of health scenario selection/evidence parsing, not live game coverage."""
import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import report, scenarios


ACTION = 'bandage-health-panel'
INVENTORY_ACTION = 'bandage-inventory'
INVENTORY_CASES = ['inventoryBandage', 'inventoryRepeatSame', 'inventoryReplaceSupply']
CASES = ['bandageEmpty', 'bandageApply', 'waitingCancel', 'waitingMove', 'missingSupply']


class HealthScenarioTests(unittest.TestCase):
    def setUp(self):
        catalog = json.loads((ROOT / 'tests/native_queue/catalog.json').read_text())
        self.suite = catalog['suites']['health']
        self.catalog = {'suites': {'health': self.suite}}
        self.checks = self.suite['scenario_actions'][ACTION]['checks']
        self.inventory_action = self.suite['scenario_actions'][INVENTORY_ACTION]
        self.inventory_checks = self.inventory_action['checks']

    def recorded(self, bindings, *, kind='sp', mode='toolkit'):
        """Synthetic completed report solely for exercising matrix admission rules."""
        actors = ['client1', 'client2'] if kind == 'mp' else ['client1']
        processes = {actor: {'pid': index + 123, 'exit_code': 0}
                     for index, actor in enumerate(actors)}
        execution = {'status': 'completed', 'processes': processes}
        selection = dict(suite='health', kind=kind, mode=mode, clients=len(actors),
                         mods=['PZSurvivorToolkit'], cases=list(bindings), options={})
        if kind == 'mp':
            selection['options']['mp_host'] = True
            processes['server'] = {'pid': 125, 'parent_role': 'client1',
                                   'cache': '/tmp/health-scenario-unit-fixture/client1'}
            execution['host_cleanup'] = {'remaining_pids': []}
        return dict(run='/tmp/health-scenario-unit-fixture', status='passed', selection=selection,
                    functional={'status': 'passed'}, provenance={'verified': True}, execution=execution,
                    coverage=[dict(suite='health', case=case, kind=kind, mode=mode,
                                   actor=actor, status='passed', outcome=copy.deepcopy(fields))
                              for actor in actors for case, fields in bindings.items()])

    def row(self, scenario, *reports, kind='sp', mode='toolkit', action=ACTION):
        return next(row for row in report.matrix(self.catalog, reports)['scenarios']
                    if row['action'] == action and row['scenario'] == scenario
                    and row['kind'] == kind and row['mode'] == mode)

    def test_actual_catalog_resolves_canonical_same_cases_for_both_modes_and_kinds(self):
        requested = 'lost-before-start,move-independent,cancel-waiting,success-queued,success-empty'
        canonical = [case['id'] for case in self.suite['cases'] if case['id'] in CASES]
        self.assertEqual(set(canonical), set(CASES))
        for kind in ('sp', 'mp'):
            for mode in ('toolkit', 'native'):
                with self.subTest(kind=kind, mode=mode):
                    self.assertEqual(scenarios.select(self.suite, requested, ACTION, kind, mode),
                                     (canonical, ['PZSurvivorToolkit']))
        self.assertEqual(scenarios.select(self.suite, 'server-authority', ACTION, 'mp', 'native'),
                         (canonical, ['PZSurvivorToolkit']))
        with self.assertRaisesRegex(ValueError, 'requires MP'):
            scenarios.select(self.suite, 'server-authority', ACTION, 'sp', 'toolkit')

    def test_each_mapped_contract_needs_every_exact_boolean_proof(self):
        for scenario, bindings in self.checks.items():
            kind = 'mp' if scenario == 'server-authority' else 'sp'
            good = self.recorded(bindings, kind=kind)
            with self.subTest(scenario=scenario):
                self.assertEqual(self.row(scenario, good, kind=kind)['status'], 'passed')
            for case, fields in bindings.items():
                for field in fields:
                    for fault in ('missing', False, 1, 'true', None):
                        bad = copy.deepcopy(good)
                        evidence = next(row for row in bad['coverage'] if row['case'] == case)
                        if fault == 'missing':
                            del evidence['outcome'][field]
                        else:
                            evidence['outcome'][field] = fault
                        with self.subTest(scenario=scenario, case=case, field=field, fault=fault):
                            self.assertEqual(self.row(scenario, bad, kind=kind)['status'],
                                             'missing-evidence')

    def test_native_controls_cannot_claim_toolkit_queue_edits(self):
        for scenario in ('cancel-waiting', 'move-independent', 'lost-before-start'):
            native = self.recorded(self.checks[scenario], mode='native')
            row = self.row(scenario, native, mode='native')
            self.assertEqual(row['status'], 'not-applicable')
            self.assertIn('controls', row['reason'])
        for scenario in ('success-empty', 'success-queued'):
            native = self.recorded(self.checks[scenario], mode='native')
            self.assertEqual(self.row(scenario, native, mode='native')['status'], 'passed')

    def test_repeat_replacement_and_return_remain_unimplemented(self):
        for scenario in ('repeat-same', 'repeat-independent', 'replaced-target', 'return-items'):
            for mode in ('toolkit', 'native'):
                with self.subTest(scenario=scenario, mode=mode):
                    self.assertEqual(self.row(scenario, mode=mode)['status'], 'unimplemented')
                    with self.assertRaisesRegex(ValueError, 'not implemented'):
                        scenarios.select(self.suite, scenario, ACTION, 'sp', mode)

    def test_no_report_and_old_body_only_outcome_do_not_prove_coverage(self):
        self.assertEqual(self.row('success-queued')['status'], 'not-run')
        old = self.recorded({'bandageApply': {'body': {'bandaged': True}, 'tailCompleted': True}})
        self.assertEqual(self.row('success-queued', old)['status'], 'missing-evidence')

    def test_host_authority_requires_all_five_cases_and_both_doctors(self):
        bindings = self.checks['server-authority']
        good = self.recorded(bindings, kind='mp')
        self.assertEqual(self.row('server-authority', good, kind='mp')['status'], 'passed')
        for fault in ('case', 'doctor', 'skipped', 'authority-proof'):
            bad = copy.deepcopy(good)
            if fault == 'case':
                bad['coverage'] = [row for row in bad['coverage'] if row['case'] != 'missingSupply']
            elif fault == 'doctor':
                bad['coverage'] = [row for row in bad['coverage'] if row['actor'] == 'client1']
            elif fault == 'skipped':
                bad['coverage'][-1]['status'] = 'skipped'
            else:
                bad['coverage'][-1]['outcome']['serverAuthorityVerified'] = False
            with self.subTest(fault=fault):
                self.assertNotEqual(self.row('server-authority', bad, kind='mp')['status'], 'passed')

    def test_failed_unverified_or_unclean_reports_do_not_become_scenario_passes(self):
        good = self.recorded(self.checks['success-empty'])
        for fault in ('failed', 'review', 'provenance', 'execution', 'partial'):
            bad = copy.deepcopy(good)
            if fault == 'failed': bad['status'] = 'failed'
            elif fault == 'review': bad['status'] = 'needs-review'
            elif fault == 'provenance': bad['provenance']['verified'] = False
            elif fault == 'execution': bad['execution']['processes']['client1']['exit_code'] = 7
            else: bad['coverage'][0]['outcome']['partialCoverage'] = True
            with self.subTest(fault=fault):
                self.assertNotEqual(self.row('success-empty', bad)['status'], 'passed')

    def test_inventory_action_selects_exact_controls_for_both_kinds_and_modes(self):
        requested = 'success-queued,repeat-same,move-dependent,lost-before-start'
        for kind in ('sp', 'mp'):
            for mode in ('toolkit', 'native'):
                with self.subTest(kind=kind, mode=mode):
                    self.assertEqual(scenarios.select(self.suite, requested, INVENTORY_ACTION, kind, mode),
                                     (INVENTORY_CASES, ['PZSurvivorToolkit']))
        self.assertEqual(scenarios.select(self.suite, 'server-authority', INVENTORY_ACTION, 'mp', 'native'),
                         (INVENTORY_CASES, ['PZSurvivorToolkit']))
        with self.assertRaisesRegex(ValueError, 'requires MP'):
            scenarios.select(self.suite, 'server-authority', INVENTORY_ACTION, 'sp', 'toolkit')

    def test_inventory_contract_requires_exact_boolean_and_request_count_proofs(self):
        for scenario, bindings in self.inventory_checks.items():
            kind = 'mp' if scenario == 'server-authority' else 'sp'
            good = self.recorded(bindings, kind=kind)
            self.assertEqual(self.row(scenario, good, kind=kind, action=INVENTORY_ACTION)['status'], 'passed')
            for case, fields in bindings.items():
                for field, expected in fields.items():
                    faults = ('missing', False, 1, 'true', None) if expected is True else ('missing', True, 1, '2', 2.0, None)
                    for fault in faults:
                        bad = copy.deepcopy(good)
                        evidence = next(row for row in bad['coverage'] if row['case'] == case)
                        if fault == 'missing':
                            del evidence['outcome'][field]
                        else:
                            evidence['outcome'][field] = fault
                        with self.subTest(scenario=scenario, case=case, field=field, fault=fault):
                            self.assertEqual(self.row(scenario, bad, kind=kind, action=INVENTORY_ACTION)['status'],
                                             'missing-evidence')

    def test_inventory_native_controls_do_not_claim_repeat_loss_or_queue_edits(self):
        self.assertEqual(set(self.inventory_action['toolkit_only']), {'repeat-same', 'lost-before-start'})
        self.assertIn('move-dependent', scenarios.QUEUE_ONLY)
        for scenario in ('repeat-same', 'lost-before-start', 'move-dependent'):
            native = self.recorded(self.inventory_checks[scenario], mode='native')
            row = self.row(scenario, native, mode='native', action=INVENTORY_ACTION)
            self.assertEqual(row['status'], 'not-applicable')
            self.assertIn('controls', row['reason'])
        native = self.recorded(self.inventory_checks['success-queued'], mode='native')
        self.assertEqual(self.row('success-queued', native, mode='native', action=INVENTORY_ACTION)['status'], 'passed')
        self.assertEqual(self.row('repeat-same', action=INVENTORY_ACTION)['status'], 'not-run')

    def test_inventory_host_authority_requires_all_three_cases_and_both_self_patients(self):
        good = self.recorded(self.inventory_checks['server-authority'], kind='mp')
        self.assertEqual(self.row('server-authority', good, kind='mp', action=INVENTORY_ACTION)['status'], 'passed')
        for fault in ('case', 'doctor', 'skipped', 'authority-proof'):
            bad = copy.deepcopy(good)
            if fault == 'case':
                bad['coverage'] = [row for row in bad['coverage'] if row['case'] != 'inventoryReplaceSupply']
            elif fault == 'doctor':
                bad['coverage'] = [row for row in bad['coverage'] if row['actor'] == 'client1']
            elif fault == 'skipped':
                bad['coverage'][-1]['status'] = 'skipped'
            else:
                bad['coverage'][-1]['outcome']['serverAuthorityVerified'] = False
            with self.subTest(fault=fault):
                self.assertNotEqual(self.row('server-authority', bad, kind='mp', action=INVENTORY_ACTION)['status'], 'passed')

    def test_inventory_scope_does_not_claim_reused_identity_replay_or_return_coverage(self):
        for scenario in ('replaced-target', 'duplicate-response', 'return-items', 'repeat-independent'):
            for mode in ('native', 'toolkit'):
                with self.subTest(scenario=scenario, mode=mode):
                    kind = 'mp' if scenario == 'duplicate-response' else 'sp'
                    self.assertEqual(self.row(scenario, kind=kind, mode=mode, action=INVENTORY_ACTION)['status'], 'unimplemented')
                    with self.assertRaisesRegex(ValueError, 'not implemented'):
                        scenarios.select(self.suite, scenario, INVENTORY_ACTION, kind, mode)
        repeat = self.inventory_checks['repeat-same']['inventoryRepeatSame']
        self.assertEqual(repeat['requestCount'], 2)
        self.assertNotIn('replayVerified', repeat)
        self.assertNotIn('reusedIdVerified', repeat)

    def test_shipped_lua_native_selection_runs_only_the_new_paired_controls(self):
        try:
            from lupa import LuaRuntime
        except ImportError:
            self.skipTest('Lupa unavailable; Python selection/matrix unit checks still run')
        shared = ROOT / 'tests/native_queue/health/shared'
        for kind in ('sp', 'mp'):
            lua = LuaRuntime(unpack_returned_tuples=True)
            lua.globals().shared_path = str(shared)
            lua.globals().selected_kind = kind
            lua.execute("""
local cases=dofile(shared_path..'/QueueHealthCases.lua')
local config={kind=selected_kind,mode='native',cases={
 'bandageEmpty','bandageApply','waitingCancel','waitingMove','missingSupply',
 'inventoryBandage','inventoryRepeatSame','inventoryReplaceSupply',
 'changedHelper','reassignedPanel','expandedCancel','miniWaitingCancel'}}
require=function(name)
 if name=='QueueTestSelection' then return config end
 if name=='QueueHealthCases' then return cases end
 error('unexpected module '..name)
end
getActivatedMods=function()return {contains=function(_,id)return id=='MiniHealthPlus'end}end
local selection=dofile(shared_path..'/QueueHealthSelection.lua')
for i,spec in ipairs(selection.cases) do
 local reason=selection.skipReason(spec,'client1')
 if i<=8 then assert(reason==nil,spec.id..' incorrectly skipped')
 else assert(type(reason)=='string' and #reason>0,spec.id..' unsupported control admitted') end
end
""")


if __name__ == '__main__':
    unittest.main()
