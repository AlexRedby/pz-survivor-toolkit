"""A charge investigation must prove real crafts and exact input identities."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks.adapters import plastic_battery as adapter


def rows():
    result = []
    for provider in ('base', 'damn'):
        for operation in ('insert', 'remove'):
            for charge in (0, 0.37, 1):
                index = len(result) + 1
                available = operation == 'insert' or charge > 0
                result.append(dict(index=index, provider=provider, operation=operation,
                    requestedCharge=charge, available=available, queueDrained=True,
                    before=[], after=[], gunID=index * 10, batteryID=index * 10 + 1,
                    inputIDs=[index * 10, index * 10 + 1] if operation == 'insert' else [index * 10],
                    actionObserved=available, nativeDuration=available, performCalls=int(available)))
    return result


def verify(values):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        text = '\n'.join(adapter.MARKER + 'PHASE ' + json.dumps(row) for row in values)
        text += '\n' + adapter.MARKER + 'COMPLETE ' + json.dumps(dict(phases=12, restored=True))
        (root / 'client1-launch.log').write_text(text)
        return adapter.verify(root, {}, {})


class PlasticBatteryCaptureTests(unittest.TestCase):
    def test_complete_matrix_is_capture_not_a_conservation_pass(self):
        result = verify(rows())
        self.assertEqual(result['issues'], [])
        self.assertEqual(result['outcomes'][0]['status'], 'captured')

    def test_all_unavailable_cannot_pass_without_standard_positive_controls(self):
        values = rows()
        for row in values:
            row.update(available=False, actionObserved=False, nativeDuration=False, performCalls=0)
        self.assertTrue(verify(values)['issues'])

    def test_canceled_duplicate_or_wrong_input_craft_is_rejected(self):
        for field, value in [('performCalls', 0), ('performCalls', 2), ('inputIDs', [999]),
                             ('actionObserved', False), ('nativeDuration', False)]:
            values = rows(); values[0][field] = value
            with self.subTest(field=field, value=value):
                self.assertTrue(verify(values)['issues'])

    def test_missing_or_duplicate_phase_is_rejected(self):
        values = rows()
        self.assertTrue(verify(values[:-1])['issues'])
        duplicate = copy.deepcopy(values); duplicate[-1] = duplicate[0]
        self.assertTrue(verify(duplicate)['issues'])


def fixed_receipts(kind='sp'):
    local, authority, native = [], [], []
    for operation in ('insert', 'remove'):
        for charge in (0, .37, 1):
            index = len(local) + 1
            gun_id, battery_id, output_id = index * 10, index * 10 + 1, index * 10 + 2
            def item(identity, kind, uses):
                return dict(id=identity, type=kind, uses=uses,
                            maxUses=1111 if kind == 'damnCraft.PlasticWeldingGun' else 142)
            gun = 'damnCraft.PlasticWeldingGun'
            if operation == 'insert':
                source = int(142 * charge + .5)
                before = [item(gun_id, gun, 0), item(battery_id, 'Base.Battery', source)]
                after = [item(gun_id, gun, source * 1111 // 142)]
                inputs = [gun_id, battery_id]
            else:
                source = int(1111 * charge + .5)
                battery_id = -1
                before = [item(gun_id, gun, source)]
                after = [item(gun_id, gun, 0)]
                if charge:
                    after.append(item(output_id, 'Base.Battery', source * 142 // 1111))
                inputs = [gun_id]
            recipe = 'Base.InsertBattery' if operation == 'insert' else 'Base.RemoveBattery'
            row = dict(index=index, operation=operation, requestedCharge=charge,
                       gunID=gun_id, batteryID=battery_id, recipe=recipe, before=before, after=after,
                       gunUseDelta=adapter._float32(.0009),effectRole='authority',
                       nativeTransferUses=source * (1111 if operation == 'insert' else 142) // (142 if operation == 'insert' else 1111),
                       stockStatsCodec='none')
            row['expectedObservedUses'] = row['nativeTransferUses']
            local.append(copy.deepcopy(row))
            local[-1]['effectRole'] = 'local'
            if kind == 'mp' and operation == 'insert' and charge:
                observed = adapter._stock_stats_uses(row['nativeTransferUses'], row['gunUseDelta'], 1111)
                local[-1]['after'][0]['uses'] = observed
                local[-1].update(expectedObservedUses=observed,stockStatsCodec='native-item-stats')
            authority.append(dict(copy.deepcopy(row), performCalls=int(charge > 0),
                                  inputIDs=inputs if charge else [], nativeDuration=charge > 0,
                                  observerIntact=True))
            native.append(dict(index=index, recipe=recipe, gunID=gun_id, available=charge > 0,
                               menu=[dict(recipe=recipe, enabled=True)] if charge else [],
                               queueDrained=True, craftObserved=charge > 0, nativeDuration=charge > 0,
                               duration=150 if charge else 0))
    return dict(local=local, authority=authority, native=native)


def fixed_verify(values=None, kind='sp', recipes=None, complete=True):
    values = values or fixed_receipts(kind)
    def line(event, row):
        return adapter.MARKER + event + ' ' + json.dumps(row) + '\n'
    def registry(role):
        return line('RECIPES', recipes or dict(role=role, customAbsent=True, basePresent=True))
    def lifecycle(role):
        return line('COMPLETE', dict(case='native-recipes', role=role, phases=6, restored=True)) if complete else ''
    client = registry('client1')
    client += ''.join(line('LOCAL', row) for row in values['local'])
    client += ''.join(line('NATIVE', row) for row in values['native'])
    authority = ''.join(line('AUTHORITY', row) for row in values['authority'])
    server = registry('server') + authority + lifecycle('server')
    client += (authority if kind == 'sp' else '') + lifecycle('client1')
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / 'client1-launch.log').write_text(client)
        if kind == 'mp':
            (root / 'server-launch.log').write_text(server)
        return adapter.verify(root, dict(cases=['native-recipes'], kind=kind), {})


class PlasticBatteryNativeTests(unittest.TestCase):
    def test_sp_and_host_exact_native_effects_pass(self):
        for kind in ('sp', 'mp'):
            with self.subTest(kind=kind):
                result = fixed_verify(kind=kind)
                self.assertEqual(result['issues'], [])
                self.assertEqual(result['outcomes'][0]['status'], 'passed')
        self.assertEqual(fixed_receipts()['local'][1]['after'][0]['uses'], 414)
        self.assertEqual(fixed_receipts()['local'][4]['after'][1]['uses'], 52)

    def test_authoritative_inputs_observer_and_native_lifecycle_are_required(self):
        for key, value in [('performCalls', 0), ('performCalls', 2), ('inputIDs', [999]),
                           ('inputIDs', [20, 21, 21]), ('nativeDuration', False), ('observerIntact', False)]:
            data = fixed_receipts('mp'); data['authority'][1][key] = value
            with self.subTest(key=key, value=value):
                self.assertTrue(fixed_verify(data, kind='mp')['issues'])
        for key, value in [('queueDrained', False), ('craftObserved', False), ('nativeDuration', False),
                           ('duration', 1), ('gunID', 999), ('available', False), ('menu', [])]:
            data = fixed_receipts(); data['native'][1][key] = value
            with self.subTest(key=key, value=value):
                self.assertTrue(fixed_verify(data)['issues'])

    def test_charge_identity_consumption_and_duplicate_outputs_are_verified(self):
        for index, mutate in [
            (1, lambda row: row['after'][0].update(uses=415)),
            (1, lambda row: row['after'][0].update(id=999)),
            (1, lambda row: row['after'].append(copy.deepcopy(row['before'][1]))),
            (1, lambda row: row['before'][1].update(uses=54)),
            (2, lambda row: row['before'][1].update(uses=143)),
            (3, lambda row: row['after'][0].update(uses=1)),
            (4, lambda row: row['after'][1].update(uses=142)),
            (4, lambda row: row['after'][0].update(uses=411)),
            (4, lambda row: row['after'].append(dict(id=999, type='Base.Battery', uses=52, maxUses=142))),
            (0, lambda row: row['after'].append(dict(id=999, type='Base.Battery', uses=0, maxUses=142))),
        ]:
            data = fixed_receipts('mp')
            mutate(data['local'][index])
            # Mutate both roles: a client/server agreement must not conceal a bad effect.
            for key in adapter._EFFECT_KEYS:
                data['authority'][index][key] = copy.deepcopy(data['local'][index][key])
            with self.subTest(index=index, mutate=mutate):
                self.assertTrue(fixed_verify(data, kind='mp')['issues'])

    def test_authoritative_effects_cannot_be_replaced_with_client_claims(self):
        data = fixed_receipts('mp'); data['authority'][1]['after'][0]['uses'] += 1
        self.assertTrue(fixed_verify(data, kind='mp')['issues'])
        data = fixed_receipts('mp'); data['authority'].clear()
        self.assertTrue(fixed_verify(data, kind='mp')['issues'])
        data = fixed_receipts('mp'); data['authority'][1] = copy.deepcopy(data['local'][1])
        self.assertTrue(fixed_verify(data, kind='mp')['issues'])

    def test_custom_registry_or_menu_paths_and_missing_phases_are_rejected(self):
        self.assertTrue(fixed_verify(recipes=dict(role='client1', customAbsent=False, basePresent=True))['issues'])
        self.assertTrue(fixed_verify(complete=False)['issues'])
        for section in ('local', 'authority', 'native'):
            data = fixed_receipts(); data[section].pop()
            self.assertTrue(fixed_verify(data)['issues'])
            data = fixed_receipts(); data[section][-1] = copy.deepcopy(data[section][0])
            self.assertTrue(fixed_verify(data)['issues'])
        data = fixed_receipts()
        data['native'][4]['menu'].append(dict(recipe=adapter._CUSTOM[1], enabled=True))
        self.assertTrue(fixed_verify(data)['issues'])
        data = fixed_receipts(); data['native'][4]['menu'] *= 2
        self.assertTrue(fixed_verify(data)['issues'])

    def test_stock_codec_is_exact_and_limited_to_mp_kept_gun_insert(self):
        self.assertEqual(adapter._stock_stats_uses(414, adapter._float32(.0009), 1111), 413)
        self.assertEqual(adapter._stock_stats_uses(1111, adapter._float32(.0009), 1111), 1110)
        result = fixed_verify(kind='mp')
        self.assertEqual([(r['authorityUses'], r['clientUses'], r['chargeMismatch'])
                          for r in result['evidence']['stockStatsReplication']],
                         [(414, 413, True), (1111, 1110, True)])
        for kind, index, section, delta in [
            ('sp', 1, 'local', -1), ('sp', 2, 'local', -1),
            ('mp', 1, 'local', -1), ('mp', 1, 'local', 1),
            ('mp', 2, 'local', -1), ('mp', 2, 'local', 1),
            ('mp', 1, 'authority', -1), ('mp', 2, 'authority', -1),
            ('mp', 4, 'local', -1), ('mp', 5, 'local', -1),
        ]:
            data = fixed_receipts(kind)
            item = -1 if index >= 4 else 0
            data[section][index]['after'][item]['uses'] += delta
            with self.subTest(kind=kind, index=index, section=section, delta=delta):
                self.assertTrue(fixed_verify(data, kind=kind)['issues'])
        for field, value in [('effectRole', 'authority'), ('stockStatsCodec', 'none'),
                             ('nativeTransferUses', 413), ('expectedObservedUses', 414),
                             ('gunUseDelta', .0009)]:
            data = fixed_receipts('mp'); data['local'][1][field] = value
            with self.subTest(field=field):
                self.assertTrue(fixed_verify(data, kind='mp')['issues'])
        data = fixed_receipts('mp'); del data['local'][1]['stockStatsCodec']
        self.assertTrue(fixed_verify(data, kind='mp')['issues'])

    def test_fresh_sp_host_selection_and_capabilities(self):
        cases = adapter.definitions()['plastic-battery']['cases']
        self.assertEqual([(c['id'], c['capability']) for c in cases],
                         [('charge-matrix', 'capture'), ('native-recipes', 'effect')])
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                selection = dict(cases=['native-recipes'], kind=kind, mode=mode, clients=1,
                                 languages=['EN'], mods=['damnlib'], options=dict(mp_host=kind == 'mp'))
                adapter.validate(selection)
                for key, value in [('clients', 2), ('languages', ['RU']), ('mods', []),
                                   ('cases', ['charge-matrix', 'native-recipes'])]:
                    with self.subTest(key=key), self.assertRaises(ValueError):
                        adapter.validate(dict(selection, **{key: value}))
                for options in (dict(seed_run='old'), dict(world_template='old')):
                    with self.assertRaises(ValueError):
                        adapter.validate(dict(selection, options=options))
                if kind == 'mp':
                    with self.assertRaises(ValueError):
                        adapter.validate(dict(selection, options={}))
                    with self.assertRaises(ValueError):
                        adapter.validate(dict(selection, cases=['charge-matrix']))

    def test_stage_installs_common_startup_and_health_support_for_both_roles(self):
        project = Path(__file__).resolve().parents[1]
        selection = dict(cases=['native-recipes'], kind='mp', mode='native', clients=1,
                         languages=['EN'], mods=['damnlib'], options=dict(mp_host=True))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runtime = dict(roles={role: dict(cache=str(root / role)) for role in ('client1', 'server')})
            adapter.stage(project, root, None, None, selection, {}, runtime)
            for role in runtime['roles']:
                lua = root / role / 'mods/ActionQueueTest/42/media/lua'
                self.assertTrue((lua / 'client/ZZStartup.lua').is_file())
                self.assertTrue((lua / 'server/ZZStartupServer.lua').is_file())
                self.assertTrue((lua / 'shared/QueueHealthEvents.lua').is_file())
            self.assertEqual(runtime['fixture']['server_ready'], '[STARTUP_TEST] SERVER_READY')
            sources = adapter.sources(project, selection)
            self.assertIn(project / 'tests/native_queue/plastic-battery/shared/PlasticBatteryFixture.lua', sources)
            self.assertIn(project / 'tests/native_queue/plastic-battery/server/ZZPlasticBatteryServer.lua', sources)

    def test_lua_bounded_codec_constants_match_independent_ieee32_verifier(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute("require=function()end;ISHandcraftAction={performRecipe=function()end};mp=false;isClient=function()return mp end")
        fixture = Path(__file__).parent / 'native_queue/plastic-battery/shared/PlasticBatteryFixture.lua'
        helper = lua.execute(fixture.read_text())
        for kind in ('sp', 'mp'):
            lua.globals().mp = kind == 'mp'
            for row in fixed_receipts(kind)['local']:
                packet = lua.table_from({k: v for k, v in row.items() if k not in ('before', 'after')})
                packet.before = lua.table_from([lua.table_from(item) for item in row['before']])
                expected = helper.expected(lua.table_from(dict(packet=packet)), 'local')
                self.assertEqual(expected.nativeTransferUses, row['nativeTransferUses'])
                self.assertEqual(expected.expectedObservedUses, row['expectedObservedUses'])
                self.assertEqual(expected.stockStatsCodec, row['stockStatsCodec'])
                authority = helper.expected(lua.table_from(dict(packet=packet)), 'authority')
                self.assertEqual(authority.expectedObservedUses, row['nativeTransferUses'])
                self.assertEqual(authority.stockStatsCodec, 'none')

    def test_scoped_fixture_lua_syntax(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime()
        root = Path(__file__).parent / 'native_queue/plastic-battery'
        for source in root.rglob('*.lua'):
            with self.subTest(source=source.name):
                lua.execute('assert(loadstring(...))', source.read_text())


if __name__ == '__main__':
    unittest.main()
