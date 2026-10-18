"""Equipment reports require native effects and exact selected lifecycle evidence."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import equipment


class EquipmentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.selection = {'suite': 'equipment', 'cases': equipment.CASES, 'kind': 'sp', 'mode': 'toolkit',
                          'clients': 1, 'languages': ['EN'], 'mods': ['PZSurvivorToolkit'], 'options': {}}

    def records(self):
        cases, enabled = self.selection['cases'], self.selection['mode'] == 'toolkit'
        rows = [{'event': 'setup', 'cases': cases, 'expected': len(cases), 'nativeDurations': True, 'queueEnabled': enabled}]
        for case in cases:
            result = dict(inventoryPreserved=True, frontCompleted=True, tailCompleted=True,
                          equipmentMatches=True, nativeDurations=True, postprocessingVerified=True, policyChecked=enabled)
            if case == 'hands-chain':
                result.update(activeProgress=True, activeProtected=enabled)
            if case == 'waiting-cancel':
                result['cancelled'] = enabled
            if case == 'bag-capacity':
                result['capacityBarrier'] = enabled
            if case in ('clothing-chain', 'hotbar-chain'):
                result.update(slotsVerified=True, clothing=case == 'clothing-chain', hotbar=case == 'hotbar-chain')
            if case == 'floor-pickup':
                result.update(floorPickup=True, pickupWorldRemoved=True)
            if case.startswith('bulk-'):
                result.update(bulkPickup=True, exactBulkContainers=True)
                if case == 'bulk-waiting-cancel':
                    result.update(bulkCancelled=True, unrelatedTailPreserved=True)
                else:
                    result.update(lightMerged=True, heavySeparate=True, childrenWiped=True, sharedExecutor=case == 'bulk-mixed')
                if case == 'bulk-mixed':
                    result['borrowedReturned'] = 'P4TidyUpMeister' in self.selection['mods']
            if self.selection['kind'] == 'mp':
                result.update(authoritative=True, receipts=0 if case == 'waiting-cancel' and enabled else equipment.RECEIPTS[case])
                result['receiptStates'] = ['completed'] * result['receipts']
            rows.append({'event': 'case', 'id': case, 'status': 'passed', 'outcome': result})
        rows.append({'event': 'complete', 'cases': cases, 'expected': len(cases), 'performed': len(cases), 'skipped': 0, 'failed': 0})
        return [dict(row, suite='equipment', kind=self.selection['kind'], mode=self.selection['mode'], actor='client1') for row in rows]

    def logs(self, records=None):
        captures=[]
        if self.selection['kind'] == 'mp':
            for case in self.selection['cases']:
                count=0 if case == 'waiting-cancel' and self.selection['mode'] == 'toolkit' else equipment.RECEIPTS[case]
                for _ in range(count):
                    captures.append('[EQUIPMENT_TEST] CAPTURE case=' + case + ' kind=ISEquipWeaponAction token=00000000-0000-0000-0000-' + str(len(captures)+1).zfill(12))
        return '\n'.join(captures + ['[QUEUE_CHECK] ' + json.dumps(row) for row in (records or self.records())]
                         + ['[EQUIPMENT_TEST] RECEIPT case=' + case for case in self.selection['cases']]
                         + ['[EQUIPMENT_TEST] COMPLETE'])

    def verify(self, text):
        (self.root / 'client1-launch.log').write_text(text)
        if self.selection['kind'] == 'mp' and not (self.root / 'server-launch.log').exists():
            (self.root / 'server-launch.log').write_text('[EQUIPMENT_TEST] TRANSFER_PROBE active=true\n[EQUIPMENT_TEST] SERVER_READY\n' + '\n'.join('[EQUIPMENT_TEST] CHECKPOINT case=' + case + '\n[EQUIPMENT_TEST] AUTHORITY case=' + case + ' inventoryPreserved=true equipmentMatches=true tailCompleted=true' for case in self.selection['cases']))
        return equipment.verify(self.root, self.selection, {})

    def test_subset_and_mode_selection(self):
        for mode in ('native', 'toolkit'):
            for cases in ([case] for case in equipment.CASES):
                equipment.validate(dict(self.selection, mode=mode, cases=cases, languages=['RU']))
        for change in ({'cases': []}, {'cases': ['unknown']}, {'cases': ['waiting-cancel', 'hands-chain']},
                       {'cases': ['hands-chain', 'hands-chain']}, {'clients': True}, {'clients': 2},
                       {'kind': 'mp'}, {'mode': 'unknown'}, {'languages': ['EN', 'RU']}, {'mods': []},
                       {'options': {'world_template': '/saved/world'}}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                equipment.validate(dict(self.selection, **change))

    def test_native_and_toolkit_keep_their_distinct_outcomes(self):
        for mode in ('native', 'toolkit'):
            self.selection['mode'] = mode
            self.assertEqual(self.verify(self.logs())['issues'], [])
        self.selection['cases'] = ['bag-capacity']
        self.assertEqual(self.verify(self.logs())['issues'], [])

    def test_mp_requires_server_and_correlated_native_outcomes(self):
        self.selection.update(kind='mp', mods=['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit'])
        equipment.validate(self.selection)
        for mode in ('native', 'toolkit'):
            self.selection['mode'] = mode
            self.assertEqual(self.verify(self.logs())['issues'], [])
            changed = self.records()
            changed[1]['outcome']['authoritative'] = False
            self.assertTrue(self.verify(self.logs(changed))['issues'])
            changed = self.records()
            changed[1]['outcome']['receipts'] = True
            self.assertTrue(self.verify(self.logs(changed))['issues'])
            text = self.logs()
            self.assertTrue(self.verify(text.replace('[EQUIPMENT_TEST] CAPTURE case=hands-chain', '[IGNORED] CAPTURE case=hands-chain', 1))['issues'])
        (self.root / 'server-launch.log').write_text('[EQUIPMENT_TEST] SERVER_READY\n')
        self.assertTrue(self.verify(self.logs())['issues'])

    def test_only_client_owned_hotbar_timer_may_cancel_with_authoritative_effects(self):
        self.selection.update(kind='mp', mods=['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit'])
        rows = self.records()
        hotbar = next(row for row in rows if row.get('id') == 'hotbar-chain')
        hotbar['outcome']['receiptStates'] = ['canceled']
        self.assertEqual(self.verify(self.logs(rows))['issues'], [])
        for states in (['started'], ['rejected'], [], ['completed', 'canceled'], None):
            changed = copy.deepcopy(rows)
            next(row for row in changed if row.get('id') == 'hotbar-chain')['outcome']['receiptStates'] = states
            self.assertTrue(self.verify(self.logs(changed))['issues'])
        for case in ('hands-chain', 'waiting-cancel', 'bag-capacity', 'clothing-chain'):
            changed = copy.deepcopy(rows)
            target = next(row for row in changed if row.get('id') == case)['outcome']
            target['receiptStates'] = ['canceled'] * target['receipts']
            if target['receipts']:
                self.assertTrue(self.verify(self.logs(changed))['issues'])
        hotbar['outcome']['authoritative'] = False
        self.assertTrue(self.verify(self.logs(rows))['issues'])

    def test_mp_stage_pins_read_only_transfer_probe_for_both_roles(self):
        self.selection.update(kind='mp', mods=['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit'])
        for role in ('server', 'client1'):
            (self.root / role / 'mods/ActionQueueTest/42/media/lua/shared').mkdir(parents=True)
        probe = self.root / 'probe.jar'
        probe.write_bytes(b'read-only fixture probe')
        runtime = {'roles': {'server': {}, 'client1': {}}, 'fixture': {'mods': []}}
        with patch.object(equipment, '_transfer_probe', return_value=probe):
            equipment.stage(ROOT, self.root, None, None, self.selection, {}, runtime)
        self.assertEqual(runtime['fixture']['mods'], ['EquipmentTransferProbe'])
        for role in ('server', 'client1'):
            layer = self.root / role / 'mods/EquipmentTransferProbe/42'
            self.assertEqual((layer / 'media/java/EquipmentTransferProbe.jar').read_bytes(), probe.read_bytes())
            self.assertIn('javaPkgName=net.alexredby.equipmentprobe', (layer / 'mod.info').read_text())
        self.assertIn(ROOT / 'tests/native_queue/equipment/java/Main.java', equipment.sources(ROOT, self.selection))

    def test_missing_effect_or_policy_proof_fails(self):
        records = self.records()
        for key in records[1]['outcome']:
            for value in (False, 1, None):
                changed = copy.deepcopy(records)
                changed[1]['outcome'][key] = value
                with self.subTest(key=key, value=value):
                    self.assertTrue(self.verify(self.logs(changed))['issues'])
        for index, key in ((0, 'queueEnabled'), (0, 'nativeDurations'), (-1, 'performed')):
            changed = copy.deepcopy(records)
            changed[index][key] = True if key == 'performed' else 1
            self.assertTrue(self.verify(self.logs(changed))['issues'])

    def test_event_context_duplicates_and_order_fail(self):
        records = self.records()
        for changed in (records[1:], records + [records[-1]], [records[0], records[2], records[1], *records[3:]]):
            self.assertTrue(self.verify(self.logs(changed))['issues'])
        for key, value in (('mode', 'native'), ('actor', 'client2'), ('suite', 'health')):
            changed = copy.deepcopy(records)
            changed[1][key] = value
            self.assertTrue(self.verify(self.logs(changed))['issues'])

    def test_receipts_and_completion_cannot_be_missing_or_duplicated(self):
        text = self.logs()
        for changed in (text.replace('[EQUIPMENT_TEST] RECEIPT case=hands-chain', ''),
                        text + '\n[EQUIPMENT_TEST] RECEIPT case=hands-chain',
                        text.replace('[EQUIPMENT_TEST] COMPLETE', '[EQUIPMENT_TEST] COMPLETE_PENDING'),
                        text + '\n[QUEUE_TEST] FAIL fixture', text + '\n[EQUIPMENT_TEST] COMPLETE'):
            self.assertTrue(self.verify(changed)['issues'])
        self.assertFalse(equipment.complete(self.selection, 'client2', text))

    def test_bulk_requires_merge_cancellation_and_postprocess_evidence(self):
        self.selection['mods'].append('P4TidyUpMeister')
        for mode in ('native', 'toolkit'):
            self.selection['mode'] = mode
            for case in ('bulk-pickup', 'bulk-waiting-cancel', 'bulk-mixed'):
                self.selection['cases'] = [case]
                self.assertEqual(self.verify(self.logs())['issues'], [])
                keys = ['exactBulkContainers']
                keys += ['bulkCancelled', 'unrelatedTailPreserved'] if case == 'bulk-waiting-cancel' else ['lightMerged', 'heavySeparate', 'childrenWiped']
                if case == 'bulk-mixed':
                    keys += ['borrowedReturned', 'sharedExecutor']
                for key in keys:
                    rows = self.records()
                    rows[1]['outcome'][key] = False
                    with self.subTest(mode=mode, case=case, key=key):
                        self.assertTrue(self.verify(self.logs(rows))['issues'])

    def test_stage_pins_shared_json_writer_and_only_equipment_sources(self):
        target = self.root / 'client1/mods/ActionQueueTest/42/media/lua/shared'
        target.mkdir(parents=True)
        runtime = {'fixture': {'mods': []}}
        equipment.stage(ROOT, self.root, None, None, self.selection, {}, runtime)
        self.assertEqual((target / 'QueueHealthEvents.lua').read_bytes(),
                         (ROOT / 'tests/native_queue/health/shared/QueueHealthEvents.lua').read_bytes())
        self.assertEqual(runtime['fixture']['server_ready'], '[EQUIPMENT_TEST] SERVER_READY')
        self.assertTrue((target.parent / 'client/ZZStartup.lua').is_file())
        sources = equipment.sources(ROOT, self.selection)
        self.assertTrue(any('equipment' in path.parts for path in sources))
        self.assertTrue(all('equipment' in path.parts or path.name in ('QueueHealthEvents.lua', 'ZZStartup.lua') for path in sources))


if __name__ == '__main__':
    unittest.main()
