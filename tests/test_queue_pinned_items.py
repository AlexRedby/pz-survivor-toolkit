"""Focused selection and result checks for the pinned-items native suite."""
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import get
from queue_checks.adapters import pinned_items


class PinnedItemsTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: shutil.rmtree(self.root))
        self.selection = {'suite': 'pinned-items', 'cases': ['trunk'], 'kind': 'sp',
                          'mode': 'native', 'clients': 1, 'languages': ['EN'],
                          'mods': ['PZSurvivorToolkit', 'EURY_CONTAINERS'], 'options': {}}

    def record(self, scene):
        row = {'scene': scene, 'status': 'passed', 'reason': '', 'truckId': '781',
                'containerType': 'trunk', 'target': 'Base.WaterBottleFull', 'rowOrder': ['Base.WaterBottleFull'],
                'expectedFirst': 'Base.WaterBottleFull', 'selectedPreserved': True,
                'provider': 'BetterContainers', 'organizedPinned': False,
                'splitRows': 0, 'splitCategories': [], 'rowCategories': ['Tools'],
                'itemCountBefore': 1, 'itemCountAfter': 1, 'targetTypeCount': 1}
        if scene == 'startup-order':
            row.update(activeClass='ISInventoryPane', comparatorIdentity='function: 0x1',
                       comparatorName='itemSortByNameInc', searchState='', searchCategoryState='',
                       searchModeState='name', toolkitCategoryState='', toolkitTagState='', toolkitTagRuleActive=False)
        if scene == 'clean-category-filter':
            row.update(target='Base.Screwdriver', expectedFirst='Base.Screwdriver',
                       rowOrder=['Base.Screwdriver', 'Base.Screwdriver_Old'], filterCategory='toolElectrical', filteredTypeCount=2, targetTypeCount=2)
        if scene == 'clean-search-match':
            row.update(rowOrder=['Base.WaterBottleFull', 'Base.Bandage'],
                       searchText='a', matchingTypeCount=2, allRowsMatch=True)
        return row

    def verify(self, rows, mods=None):
        if mods is not None:
            self.selection['mods'] = mods
        log = ''.join('LOG: Lua [PIN_ITEMS] RESULT ' + json.dumps(row) + '\n' for row in rows)
        log += '[PIN_ITEMS] COMPLETE trunk\n'
        (self.root / 'client1-launch.log').write_text(log)
        return pinned_items.verify(self.root, self.selection, {})

    def test_registration_and_supported_selections(self):
        self.assertIs(get('pinned-items'), pinned_items)
        for mode in ('toolkit', 'native'):
            self.selection['mode'] = mode
            pinned_items.validate(self.selection)
        self.assertEqual(['PZSurvivorToolkit', 'EURY_CONTAINERS'],
                         pinned_items.definitions()['pinned-items']['default_mods'])

    def test_selection_rejects_invalid_scope_and_missing_dependency(self):
        for change in ({'cases': ['other']}, {'kind': 'mp'}, {'clients': 2},
                       {'languages': ['EN', 'RU']}, {'options': {'world_template': '/saved'}},
                       {'mods': ['PZSurvivorToolkit']}, {'mode': 'toolkit', 'mods': ['EURY_CONTAINERS']}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                pinned_items.validate(dict(self.selection, **change))
        for value in ('false', 0, None):
            with self.subTest(advanced_categories=value), self.assertRaises(ValueError):
                pinned_items.validate(dict(self.selection, options={'advanced_categories': value}))

    def test_mp_selection_requires_real_two_client_host_scope(self):
        mods = ['PZSurvivorToolkit', 'EURY_CONTAINERS', 'CleanUI', 'organizedCategories_core']
        selection = dict(self.selection, kind='mp', clients=2, languages=['EN', 'RU'], mods=mods,
                         options={'mp_host': True})
        pinned_items.validate(selection)
        for change in ({'options': {'mp_host': False}}, {'clients': 1}, {'languages': ['EN']},
                       {'options': {'mp_host': True, 'startup_connection': {'username': 'peer', 'password': 'x'}}},
                       {'mods': mods[:2]}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                pinned_items.validate(dict(selection, **change))
        with self.assertRaises(ValueError):
            pinned_items.validate(dict(self.selection, options={'mp_host': True}))

    def test_stage_keeps_mod_options_as_runtime_output(self):
        cache = self.root / 'client1'
        roles = {}
        for role in ('server', 'client1', 'client2'):
            (self.root / role / 'mods/ActionQueueTest/42/media/lua/client').mkdir(parents=True)
            (self.root / role / 'mods/ActionQueueTest/42/media/lua/server').mkdir(parents=True)
            (self.root / role).mkdir(exist_ok=True)
            roles[role] = {'cache': str(self.root / role)}
        runtime = {'roles': roles}
        pinned_items.stage(ROOT, self.root, None, None, self.selection, {}, runtime)
        self.assertFalse((cache / 'Lua/ModOptions.ini').exists())
        self.selection['options'] = {'advanced_categories': True}
        pinned_items.stage(ROOT, self.root, None, None, self.selection, {}, runtime)
        self.assertFalse((cache / 'Lua/ModOptions.ini').exists())

    def selection_record(self, mode):
        return {'mode': mode, 'status': 'passed', 'input': 'programmatic-key-predicates',
                'class': 'CleanUI_Clean_ISInventoryPane' if mode == 'clean' else 'CleanUI_Vanilla_ISInventoryPane',
                'stackCount': 55, 'renderedChildren': 50, 'equippedHidden': mode == 'clean',
                'equippedHeaders': 1 if mode == 'clean' else 0,
                'groupRow': 53, 'childRow': 55, 'shiftRow': 54, 'capRow': 52, 'childId': '781',
                'exactSelection': True, 'groupSemantics': True, 'itemSemantics': True,
                'repeatedRefresh': True, 'shiftRange': True}

    def verify_selection(self, rows):
        self.selection.update(cases=['selection'], mods=['PZSurvivorToolkit', 'EURY_CONTAINERS', 'CleanUI'])
        log = ''.join('[PIN_ITEMS] SELECTION ' + json.dumps(row) + '\n' for row in rows)
        (self.root / 'client1-launch.log').write_text(log + '[PIN_ITEMS] COMPLETE selection\n')
        return pinned_items.verify(self.root, self.selection, {})

    def test_inventory_selection_is_an_independent_sp_case(self):
        selection = dict(self.selection, cases=['selection'])
        pinned_items.validate(selection)
        for change in ({'kind': 'mp', 'clients': 2, 'languages': ['EN', 'RU']},
                       {'options': {'mp_host': True}}, {'mods': ['PZSurvivorToolkit']},
                       {'cases': ['trunk', 'selection']}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                pinned_items.validate(dict(selection, **change))

    def test_inventory_selection_requires_both_active_native_classes(self):
        rows = [self.selection_record(mode) for mode in ('clean', 'vanilla')]
        self.assertEqual([], self.verify_selection(rows)['issues'])
        for wrong in (rows[:1], rows[::-1], rows + rows[-1:]):
            with self.subTest(rows=wrong):
                self.assertTrue(self.verify_selection(wrong)['issues'])
        # Without CleanUI the one real ISInventoryPane receipt is sufficient.
        self.verify_selection(rows)
        self.selection['mods'].remove('CleanUI')
        native = dict(rows[1], **{'class': 'ISInventoryPane'})
        (self.root / 'client1-launch.log').write_text(
            '[PIN_ITEMS] SELECTION ' + json.dumps(native) + '\n[PIN_ITEMS] COMPLETE selection\n')
        self.assertEqual([], pinned_items.verify(self.root, self.selection, {})['issues'])

    def test_inventory_selection_rejects_lost_semantics_and_wrong_visible_rows(self):
        rows = [self.selection_record(mode) for mode in ('clean', 'vanilla')]
        for change in ({'exactSelection': False}, {'groupSemantics': False}, {'itemSemantics': False},
                       {'repeatedRefresh': False}, {'shiftRange': False}, {'renderedChildren': 55},
                       {'equippedHeaders': 0}, {'shiftRow': 53}, {'capRow': 55},
                       {'status': 'failed', 'reason': 'Selected entry differs from rendered row 63'}):
            with self.subTest(change=change):
                result = self.verify_selection([dict(rows[0], **change), rows[1]])
                self.assertTrue(result['issues'])
                self.assertEqual('failed', result['outcomes'][0]['status'])
    def test_verifier_accepts_ordered_scenes_and_rejects_missing_duplicate_and_bad_records(self):
        rows = [self.record(scene) for scene in pinned_items.SCENES]
        self.assertEqual([], self.verify(rows)['issues'])
        self.assertTrue(self.verify(rows[:-1])['issues'])
        self.assertTrue(self.verify(rows + [rows[-1]])['issues'])
        bad = [dict(row) for row in rows]
        bad[0]['status'] = 'skipped'
        self.assertTrue(self.verify(bad)['issues'])
        bad[0] = dict(rows[0], status='failed', reason='priority moved below expected first')
        self.assertIn('priority moved below expected first', '; '.join(self.verify(bad)['issues']))
        bad[0] = dict(rows[0], itemCountAfter=0)
        self.assertTrue(self.verify(bad)['issues'])
        bad[0] = dict(rows[0], expectedFirst='Base.OtherItem')
        self.assertTrue(self.verify(bad)['issues'])

    def test_verifier_rejects_malformed_result_json(self):
        (self.root / 'client1-launch.log').write_text(
            '[PIN_ITEMS] RESULT {broken json}\n[PIN_ITEMS] COMPLETE trunk\n')
        self.assertIn('Malformed pinned items result JSON',
                      pinned_items.verify(self.root, self.selection, {})['issues'])
        (self.root / 'client1-launch.log').write_text(
            '[PIN_ITEMS] RESULT []\n[PIN_ITEMS] COMPLETE trunk\n')
        self.assertIn('Pinned items result must be a JSON object',
                      pinned_items.verify(self.root, self.selection, {})['issues'])

    def test_missing_log_reports_failure(self):
        result = pinned_items.verify(self.root, self.selection, {})
        self.assertTrue(result['issues'])
        self.assertEqual([], result['evidence']['scenes'])

    def test_cleanui_selection_requires_all_supported_scenes(self):
        rows = [self.record(scene) for scene in pinned_items.SCENES]
        rows += [self.record(scene) for scene in pinned_items.CLEANUI_SCENES]
        self.assertEqual([], self.verify(rows, ['PZSurvivorToolkit', 'EURY_CONTAINERS', 'CleanUI'])['issues'])
        self.assertTrue(self.verify(rows[:4], ['PZSurvivorToolkit', 'EURY_CONTAINERS', 'CleanUI'])['issues'])

    def test_organized_categories_scenes_are_conditional_and_verified(self):
        mods = ['PZSurvivorToolkit', 'EURY_CONTAINERS', 'CleanUI', 'organizedCategories_core']
        scenes = pinned_items.expected_scenes(dict(self.selection, mods=mods))
        rows = [self.record(scene) for scene in scenes]
        rows[1].update(provider='organizedCategories_core', organizedPinned=True)
        split = next(row for row in rows if row['scene'] == 'category-split')
        split.update(splitRows=2, splitCategories=['toolElectrical', 'toolCarpentry'],
                     rowCategories=['toolCarpentry', 'toolElectrical'],
                     expectedFirstCategory='toolCarpentry')
        self.assertEqual([], self.verify(rows, mods)['issues'])
        split['splitRows'] = 1
        self.assertIn('Organized Categories did not split duplicate items into two rows',
                      '; '.join(self.verify(rows, mods)['issues']))

    def mp_record(self, scene, actor, online_id):
        row = self.record(scene)
        row.update(actor=actor, onlineId=online_id, mp=True,
                   itemSignature='11:Base.Apple|12:Base.Bandage|13:Base.Nails|14:Base.Screwdriver|15:Base.Screwdriver|16:Base.Screwdriver_Old',
                   itemCountBefore=6, itemCountAfter=6, truckId='7821')
        if scene == 'organized-item-pin':
            row.update(provider='organizedCategories_core', organizedPinned=True)
        if scene == 'clean-category-filter':
            row.update(rowOrder=['Base.Screwdriver', 'Base.Screwdriver_Old'], filteredTypeCount=2)
        if scene == 'category-split':
            row.update(splitRows=2, splitCategories=['toolCarpentry', 'toolElectrical'],
                       rowCategories=['toolCarpentry', 'toolElectrical'],
                       expectedFirstCategory='toolCarpentry')
        return row

    def write_mp_logs(self, *, peer_target='Base.WaterBottleFull', oc_peer_target='Base.WaterBottleFull',
                      peer_provider='organizedCategories_core', missing_second_peer=False,
                      changed_signature=False, client2_failed=False, include_server=True):
        mods = ['PZSurvivorToolkit', 'EURY_CONTAINERS', 'CleanUI', 'organizedCategories_core']
        self.selection.update(kind='mp', clients=2, languages=['EN', 'RU'], mods=mods,
                              options={'mp_host': True})
        signature = '11:Base.Apple|12:Base.Bandage|13:Base.Nails|14:Base.Screwdriver|15:Base.Screwdriver|16:Base.Screwdriver_Old'
        changed = '11:Base.Apple|12:Base.Bandage|13:Base.Nails|14:Base.Screwdriver|15:Base.Screwdriver|17:Base.Screwdriver_Old'
        for role, online_id in (('client1', 0), ('client2', 1)):
            rows = [self.mp_record(scene, role, online_id) for scene in pinned_items.expected_scenes(self.selection)]
            if role == 'client2' and client2_failed:
                rows[2]['status'], rows[2]['reason'] = 'failed', 'second client assertion'
            if changed_signature and role == 'client2':
                for row in rows:
                    row['itemSignature'] = changed
            replica = {'actor': role, 'onlineId': online_id, 'truckId': '7821',
                       'itemCount': 6, 'itemSignature': changed if changed_signature and role == 'client2' else signature}
            other = 'client2' if role == 'client1' else 'client1'
            peers = [
                {'actor': role, 'pinner': other, 'provider': 'BetterContainers', 'truckId': '7821',
                 'target': peer_target, 'pinAbsent': True,
                 'itemSignature': changed if changed_signature and role == 'client2' else signature},
                {'actor': role, 'pinner': other, 'provider': peer_provider, 'truckId': '7821',
                 'target': oc_peer_target, 'pinAbsent': True,
                 'itemSignature': changed if changed_signature and role == 'client2' else signature},
            ]
            if missing_second_peer:
                peers.pop()
            log = ''.join('LOG Lua [PIN_ITEMS] RESULT ' + json.dumps(row) + '\n' for row in rows)
            log += 'LOG Lua [PIN_ITEMS] REPLICA ' + json.dumps(replica) + '\n'
            log += ''.join('LOG Lua [PIN_ITEMS] PEER ' + json.dumps(peer) + '\n' for peer in peers)
            log += '[PIN_ITEMS] COMPLETE trunk\n'
            (self.root / (role + '-launch.log')).write_text(log)
        if include_server:
            authority = [{'phase': phase, 'truckId': '7821', 'itemCount': 6,
                          'itemSignature': signature}
                         for phase in ('initial', 'client1-done', 'client2-done')]
            log = '[STARTUP_TEST] SERVER_READY\n'
            log += ''.join('LOG Lua [PIN_ITEMS] AUTHORITY ' + json.dumps(row) + '\n' for row in authority)
            (self.root / 'server-launch.log').write_text(log)

    def test_mp_verifier_accepts_complete_two_client_host_receipts(self):
        self.write_mp_logs()
        result = pinned_items.verify(self.root, self.selection, {})
        self.assertEqual([], result['issues'])
        self.assertEqual(['client1', 'client2'], [row['actor'] for row in result['outcomes']])
        self.assertEqual(15, len(result['evidence']['scenes']['client1']))
        self.assertEqual(3, len(result['evidence']['authority']))

    def test_mp_verifier_rejects_missing_server_peer_mismatch_changed_ids_and_client_failure(self):
        self.write_mp_logs(include_server=False)
        self.assertIn('Missing Host server log', '; '.join(pinned_items.verify(self.root, self.selection, {})['issues']))
        self.write_mp_logs(peer_target='Base.OtherItem')
        self.assertIn('peer pin-absence receipt is invalid', '; '.join(pinned_items.verify(self.root, self.selection, {})['issues']))
        self.write_mp_logs(oc_peer_target='Base.WrongOrganizedTarget')
        self.assertIn('organizedCategories_core peer pin-absence receipt is invalid',
                      '; '.join(pinned_items.verify(self.root, self.selection, {})['issues']))
        self.write_mp_logs(peer_provider='wrong-provider')
        self.assertIn('ordered Better Containers and Organized Categories',
                      '; '.join(pinned_items.verify(self.root, self.selection, {})['issues']))
        self.write_mp_logs(missing_second_peer=True)
        self.assertIn('ordered Better Containers and Organized Categories',
                      '; '.join(pinned_items.verify(self.root, self.selection, {})['issues']))
        self.write_mp_logs(changed_signature=True)
        self.assertIn('changed truck, inventory identity or online ID', '; '.join(pinned_items.verify(self.root, self.selection, {})['issues']))
        self.write_mp_logs(client2_failed=True)
        result = pinned_items.verify(self.root, self.selection, {})
        self.assertIn('second client assertion', '; '.join(result['issues']))
        self.assertTrue(all(row['status'] == 'failed' for row in result['outcomes']))


if __name__ == '__main__':
    unittest.main()
