"""Offline evidence checks for native world streaming/rejoin/restart fixtures."""
import copy
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import warehouse_manifest as common
from queue_checks.adapters import warehouse_persistence as adapter
from tests import test_queue_warehouse_manifest as identity_fixture
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None


class WarehousePersistenceTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.selection = dict(suite=common.SUITE, cases=['persist-seed'], kind='mp', mode='toolkit',
                              clients=2, languages=['EN', 'RU'], mods=common.MODS, options={'mp_host': True})
        self.packet = dict(ids=[101, 102, 103, 104], category='Material', identities=identity_fixture.native_identities(),
                           boxes=[dict(x=x, y=20, z=0, object=1, ci=0, key=f'{x},20,0', id=f'{x},20,0/1/0') for x in (10, 11)])
        self.prepared = dict(packet=self.packet, home=dict(x=12, y=20, z=0), away=dict(x=612, y=220, z=0))
        self.samples = dict(initial=1000, unloaded=1500, revisited=3000, rejoined=3500, saved=4000, restored=4000)
        self.rows = {}
        self.seed = dict(schema=2, samples=[4000, 4000], counts=[2, 1, 1, 0], ids=self.packet['ids'],
                         boxes=self.packet['boxes'], identities=self.packet['identities'], category=self.packet['category'],
                         loaded=False, completedAt=6000)

    def receipt(self, stage, role=None):
        loaded = stage in ('initial', 'revisited', 'rejoined')
        sample = self.samples[stage]
        result = dict(stage=stage, revision=sample, loaded=loaded, samples=[sample, sample], ages=[1000, 1000],
                      observedAt=sample + 1000, counts=[2, 1, 1, 0], worldAbsent=not loaded, nativeIds=loaded)
        if role:
            result.update(role=role, language='EN' if role == 'client1' else 'RU', windowCount=4)
        return result

    def build(self, case='persist-seed'):
        self.selection['cases'] = [case]
        stages = adapter.SEED_STAGES if case == 'persist-seed' else adapter.RELOAD_STAGES
        self.rows = {'server': [('PREPARED', self.prepared)]}
        for index, stage in enumerate(stages):
            if stage == 'rejoined':
                self.rows['server'] += [('RECONNECT', {'oldOnlineID': 2}), ('DISCONNECTED', dict(oldOnlineID=2, oldPlayerAbsent=True)),
                                        ('REJOIN', dict(oldOnlineID=2, newOnlineID=2, newPlayer=True))]
            self.rows['server'].append(('AUTHORITY', self.receipt(stage)))
        if case == 'persist-seed':
            self.rows['server'].append(('PERSISTED', self.seed))
        else:
            cold = self.receipt('restored'); cold['stage'] = 'cold'
            del cold['worldAbsent']; del cold['nativeIds']
            self.rows['server'].insert(0, ('COLD', cold))
            self.rows['server'].append(('CLEANUP', {'ownedObjects': 2}))
        for role, language, online in [('client1', 'EN', 1), ('client2', 'RU', 2)]:
            rows = [('SETUP', dict(case=case, role=role, language=language, onlineID=online))]
            for stage in stages:
                if stage == 'rejoined' and role == 'client2':
                    rows += [('DISCONNECT', dict(role=role, onlineID=2, nativeExitToMenu=True)),
                             ('REJOIN', dict(role=role, onlineID=2, nativeConnected=True))]
                rows += [('STATE', self.receipt(stage, role)), ('SHOT', dict(role=role, stage=stage))]
                path = self.root / role / 'Screenshots' / ('warehouse-persist-' + stage + '.png')
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR' + struct.pack('>II', 1280, 900) + b'\0' * 9)
            rows.append(('COMPLETE', dict(case=case, role=role))); self.rows[role] = rows
        self.rows = copy.deepcopy(self.rows); self.flush()

    def flush(self):
        for role, rows in self.rows.items():
            value = '[STARTUP_TEST] SERVER_READY\n' if role == 'server' else ''
            value += ''.join(adapter.MARKER + event + ' ' + json.dumps(row) + '\n' for event, row in rows)
            (self.root / (role + '-launch.log')).write_text(value)

    def verify(self):
        return adapter.verify(self.root, self.selection, {})

    def test_seed_requires_native_unload_revisit_and_real_observer_rejoin(self):
        self.build()
        self.assertEqual(self.verify()['issues'], [])
        self.assertEqual(len(self.verify()['evidence']['screenshots']), 10)
        self.assertTrue(adapter.complete(self.selection, 'client2', (self.root / 'client2-launch.log').read_text()))
        original = copy.deepcopy(self.rows)
        for role in original:
            for index in range(len(original[role])):
                for action in ('missing', 'duplicate'):
                    self.rows = copy.deepcopy(original)
                    if action == 'missing': del self.rows[role][index]
                    else: self.rows[role].insert(index, self.rows[role][index])
                    self.flush()
                    with self.subTest(role=role, index=index, action=action): self.assertTrue(self.verify()['issues'])

    def test_reused_numeric_online_id_is_valid_but_missing_native_disconnect_is_not(self):
        self.build(); self.assertEqual(self.verify()['issues'], [])
        for event, key, value in [('DISCONNECTED', 'oldPlayerAbsent', False), ('REJOIN', 'newPlayer', False), ('REJOIN', 'newOnlineID', True)]:
            self.build()
            row = next(row for name, row in self.rows['server'] if name == event); row[key] = value
            self.flush(); self.assertTrue(self.verify()['issues'])

    def test_reload_preserves_cold_timestamps_ids_counts_then_samples_again(self):
        self.samples['revisited'] = 7000
        self.build('persist-reload')
        self.selection['options']['world_template'] = '/tmp/sealed-native-world'
        with patch.object(adapter, '_seed', return_value=(self.root / 'seed', self.seed)):
            self.assertEqual(self.verify()['issues'], [])
            cold = self.rows['server'][0][1]
            cold['samples'] = [4001, 4001]; cold['ages'] = [999, 999]; self.flush()
            self.assertTrue(self.verify()['issues'])
            self.build('persist-reload')
            prepared = next(row for event, row in self.rows['server'] if event == 'PREPARED')
            prepared['packet']['ids'][0] = 999; self.flush()
            self.assertTrue(self.verify()['issues'])

    def test_reload_preserves_exact_authoritative_native_state_descriptors(self):
        self.samples['revisited'] = 7000
        self.build('persist-reload');self.selection['options']['world_template'] = '/tmp/sealed-native-world'
        prepared = next(value for event, value in self.rows['server'] if event == 'PREPARED')
        identity = prepared['packet']['identities']['default']
        identity['ingredient'] = True
        identity['key'] = identity['key'].replace(':ingredient:false', ':ingredient:true')
        self.flush()
        with patch.object(adapter, '_seed', return_value=(self.root / 'seed', copy.deepcopy(self.seed))):
            self.assertIn('Reload replaced original persisted native item states', self.verify()['issues'])

    def test_seed_rejects_missing_native_state_and_state_key_disagreement(self):
        for mutation in ('missing', 'state', 'persisted'):
            self.build()
            prepared = self.rows['server'][0][1]['packet']
            if mutation == 'missing':
                del prepared['identities']
            elif mutation == 'state':
                prepared['identities']['default']['cookingState'] = 'cooked'
            else:
                next(value for event, value in self.rows['server'] if event == 'PERSISTED')['identities'] = {}
            self.flush()
            with self.subTest(mutation=mutation): self.assertTrue(self.verify()['issues'])

    def test_wrong_last_known_age_counts_bool_and_missing_screenshots_fail(self):
        for key, value in [('counts', [True, 1, 1, 0]), ('loaded', True), ('samples', [0, 0]), ('ages', [-1, -1]),
                           ('worldAbsent', False), ('nativeIds', True), ('windowCount', True)]:
            self.build()
            row = next(row for event, row in self.rows['client2'] if event == 'STATE' and row['stage'] == 'unloaded')
            row[key] = value; self.flush()
            with self.subTest(key=key): self.assertTrue(self.verify()['issues'])
        self.build(); (self.root / 'client2/Screenshots/warehouse-persist-saved.png').unlink()
        self.assertTrue(self.verify()['issues'])

    def test_cases_route_to_existing_runner_and_reject_world_restore_on_seed(self):
        common.validate(self.selection)
        self.assertEqual([case['id'] for case in common.definitions()[common.SUITE]['cases']],
                         ['snapshot', 'persist-seed', 'persist-reload', 'legacy-seed', 'legacy-reload'])
        for changes in ({'options': {}}, {'clients': 1}, {'clients': True}, {'kind': 'sp'},
                        {'languages': ['EN']}, {'options': {'mp_host': True, 'world_template': '/tmp/existing'}}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                common.validate(dict(self.selection, **changes))
        with self.assertRaises(ValueError):
            common.validate(dict(self.selection, cases=['persist-reload']))
        sources = common.sources(ROOT, self.selection)
        self.assertIn(Path(adapter.__file__), sources)
        self.assertIn(ROOT / 'tests/native_queue/warehouse-manifest/shared/WarehouseManifestPersistence.lua', sources)


@unittest.skipIf(LuaRuntime is None, 'Lupa is required to execute the persistence client fixture')
class WarehousePersistenceClientSamplesTests(unittest.TestCase):
    def test_authority_fixture_does_not_register_cold_load_on_a_client(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute("""
isServer = function() return false end
require = function(name)
 if name == 'QueueTestSelection' then return {cases = {'persist-reload'}} end
 error('Client must not initialize authority fixture dependency ' .. name)
end
Events = setmetatable({}, {__index = function() error('Client must not register authority fixture events') end})
""")
        lua.execute((ROOT / 'tests/native_queue/warehouse-manifest/server/ZZWarehouseManifestPersistenceServer.lua').read_text())

    def test_loaded_accepts_advancing_samples_but_unloaded_requires_exact_samples_and_age(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(r"""
now, x, y, shots = 3000, 12, 20, 0
handlers, receipts = {}, {}
Events = setmetatable({}, {__index = function(self, key)
 local event = {Add = function(callback) handlers[key] = callback end}
 rawset(self, key, event); return event
end})
local player = {getUsername = function() return 'client1' end, getOnlineID = function() return 0 end,
 isDead = function() return false end, getSquare = function() return {} end,
 getX = function() return x end, getY = function() return y end, getZ = function() return 0 end,
 setGodMod = function() end, setGhostMode = function() end}
getPlayer = function() return player end
getTimestampMs = function() return now end
getFileReader = function() return nil end
isClient = function() return true end
isIngameState = function() return true end
sendClientCommand = function() end
getCore = function() return {TakeFullScreenshot = function() shots = shots + 1 end} end
PZSurvivorToolkit = {Settings = {actionQueue = function() return true end}}
Translator = {getLanguage = function() return {name = function() return 'EN' end} end}
LootSorter = {toggleManifest = function()
 LootSorter._manifestWin = {listBox = {items = {{item = {n = 3}}, {item = {n = 1}}}}}
end}
fixture = {ft = 'Base.Nails', custom = 'Warehouse custom nails', appearance = {
 name = 'Warehouse fixture A', icon = {kind = 'item', value = 'Base.Nails'}, color = {r = .25, g = .5, b = .75, a = 1}},
 identity = function(_, custom) return custom and 'custom' or 'default' end, assertIdentity = function() end,
 counts = function() return {2, 1, 1, 0} end}
packet = {category = 'Material', boxes = {}, identities = {default = {}, custom = {}}}
payload = {schema = 2, revision = 1, containers = {}}
for i = 1, 2 do
 local point = {id = tostring(i), key = tostring(i), x = 9 + i, y = 20, z = 0, object = 1, ci = 0}
 packet.boxes[i] = point
 local record = {kind = 'crate', name = i == 1 and 'Warehouse fixture A' or 'Warehouse fixture B',
  icon = fixture.appearance.icon, color = fixture.appearance.color, loaded = true, sampledAt = 2000, entries = {}}
 for key, value in pairs(point) do record[key] = value end
 record.entries.default = {key = 'default', ft = fixture.ft, cat = packet.category, n = i == 1 and 2 or 1}
 if i == 1 then record.entries.custom = {key = 'custom', ft = fixture.ft, cat = packet.category, name = fixture.custom, n = 1} end
 payload.containers[point.id] = record
end
print = function(message) assert(not message:find('FAIL', 1, true), message) end
require = function(name)
 if name == 'QueueTestSelection' then return {cases = {'persist-seed'}, kind = 'mp', mode = 'toolkit'} end
 if name == 'WarehouseManifestFixture' then return fixture end
 if name == 'PZSurvivorToolkit/ManifestModel' then return {SCHEMA = 2} end
 if name == 'WarehouseManifestPersistence' then return persistence end
 if name == 'PZSurvivorToolkit/ManifestClient' then return {getState = function() return {payload = payload} end} end
 if name == 'QueueHealthEvents' then return {encode = function(value)
  receipts[#receipts + 1] = value; return 'test-json'
 end} end
 error('Unexpected fixture dependency ' .. name)
end
function stateCount()
 local count = 0
 for _, value in ipairs(receipts) do if value.stage and value.windowCount then count = count + 1 end end
 return count
end
""")
        lua.globals().persistence = lua.execute((ROOT / 'tests/native_queue/warehouse-manifest/shared/WarehouseManifestPersistence.lua').read_text())
        lua.execute("persistence.native = function() return true end; persistence.absent = function() return true end")
        lua.execute((ROOT / 'tests/native_queue/warehouse-manifest/client/ZZWarehouseManifestPersistence.lua').read_text())
        lua.execute("""
handlers.OnGameStart(); handlers.OnTick()
handlers.OnServerCommand(persistence.module, 'Prepared', {role = 'client1', packet = packet,
 home = {x = 12, y = 20, z = 0}, away = {x = 612, y = 220, z = 0}, stage = 'initial'})
handlers.OnTick()
handlers.OnServerCommand(persistence.module, 'Phase', {packet = packet, stage = 'initial', loaded = true, samples = {1000, 1000}})
handlers.OnTick(); now = 3900; handlers.OnTick()
""")
        self.assertEqual(lua.eval('stateCount()'), 1, 'A later live sample must not be pinned to the server phase timestamp')
        self.assertEqual(lua.eval('shots'), 1)
        lua.execute("""
handlers.OnServerCommand(persistence.module, 'Travel', {stage = 'unloaded', point = {x = 612, y = 220, z = 0}})
x, y, now = 612, 220, 7000
for _, record in pairs(payload.containers) do record.loaded = false; record.sampledAt = 5001 end
handlers.OnTick()
handlers.OnServerCommand(persistence.module, 'Phase', {packet = packet, stage = 'unloaded', loaded = false, samples = {5000, 5000}})
handlers.OnTick(); now = 8000; handlers.OnTick()
""")
        self.assertEqual(lua.eval('stateCount()'), 1, 'Unloaded samples must retain the exact authority timestamp')
        lua.execute("""
now = 10200
for _, record in pairs(payload.containers) do record.sampledAt = 10000 end
handlers.OnServerCommand(persistence.module, 'Phase', {packet = packet, stage = 'unloaded', loaded = false, samples = {10000, 10000}})
handlers.OnTick()
""")
        self.assertEqual(lua.eval('stateCount()'), 1, 'A too-young sample must not establish last-known age')
        lua.execute("now = 10700; handlers.OnTick(); now = 11600; handlers.OnTick()")
        self.assertEqual(lua.eval('stateCount()'), 2)
        self.assertEqual(lua.eval('shots'), 2)


@unittest.skipIf(LuaRuntime is None, 'Lupa is required to execute the persistence native menu lifecycle')
class WarehousePersistenceNativeIdentityTests(unittest.TestCase):
    def test_last_known_and_restored_records_keep_authoritative_native_states(self):
        lua = identity_fixture.WarehouseManifestIdentityTests().fixture()
        lua.execute("selection.cases={'persist-seed'};package.preload['WarehouseManifestFixture']=function()return fixture end")
        lua.globals().persistence = lua.execute((ROOT / 'tests/native_queue/warehouse-manifest/shared/WarehouseManifestPersistence.lua').read_text())
        lua.execute('''
local payload=payloadFromSeed()
assert(persistence.receipt(payload,packet,'initial',true))
for _,record in pairs(payload.containers)do record.loaded=false end
assert(persistence.receipt(payload,packet,'unloaded',false,{1000,1000}))
local function primitive(value)
 if type(value)~='table'then return value end
 local result={};for key,item in pairs(value)do result[key]=primitive(item)end;return result
end
local savedPacket,savedPayload=primitive(packet),primitive(payload)
assert(savedPacket.identities.default.cookingState==false,'known false native state was dropped')
assert(persistence.receipt(savedPayload,savedPacket,'restored',false,{1000,1000}))
local entry=savedPayload.containers[savedPacket.boxes[1].id].entries[fixture.identity(savedPacket)]
entry.ingredient=true
assert(not pcall(persistence.receipt,savedPayload,savedPacket,'restored',false,{1000,1000}),
 'restored record accepted changed native state with the original key')
savedPacket=primitive(packet);savedPacket.identities=nil
assert(not pcall(persistence.receipt,payload,savedPacket,'restored',false,{1000,1000}),
 'legacy seed without frozen native states was accepted')
''')


@unittest.skipIf(LuaRuntime is None, 'Lupa is required to execute the persistence native menu lifecycle')
class WarehousePersistenceNativeMenuTests(unittest.TestCase):
    def fixture(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(r"""
now, inGame, staleClient, fileFlag, pauseCalls, exitCalls, connects = 1000, true, true, nil, 0, 0, 0
handlers, logs, receipts = {}, {}, {}
Events = setmetatable({}, {__index = function(self, key)
 local event = {Add = function(callback) handlers[key] = callback end}; rawset(self, key, event); return event
end})
local player = {getUsername = function() return 'client2' end, getOnlineID = function() return 4 end,
 isDead = function() return false end, getSquare = function() return {} end,
 setGodMod = function() end, setGhostMode = function() end}
getPlayer = function() return player end
getTimestampMs = function() return now end
isClient = function() return staleClient end
isIngameState = function() return inGame end
getFileReader = function()
 if not fileFlag then return end
 return {readLine = function() return fileFlag end, close = function() end}
end
getFileWriter = function(name, create, append)
 assert(name == 'warehouse-manifest-rejoin.txt' and create == true and append == false)
 return {write = function(_, value) fileFlag = value end, close = function() end}
end
getCore = function() return {getKey = function(_, binding) assert(binding == 'MAIN_MENU'); return 77 end} end
KeybindId, Keyboard = {MAIN_MENU = 'MAIN_MENU'}, {KEY_ESCAPE = 27}
MainScreen = {instance = {inGame = true, visible = false, isVisible = function(self) return self.visible end}}
MainScreen.instance.exitOption = {internal = 'EXIT', onMouseDown = function(option, x, y)
 assert(option == MainScreen.instance.exitOption and MainScreen.instance.visible and pauseCalls == 1)
 assert(x == 0 and y == 0); exitCalls = exitCalls + 1
end}
ToggleEscapeMenu = function(key)
 assert(key == 77 and inGame and MainScreen.instance.inGame)
 pauseCalls = pauseCalls + 1; MainScreen.instance.visible = true
end
ConnectToServer = {instance = {connect = function(_, screen, title, username, password, ip, localIP, port)
 assert(screen == MainScreen.instance and username == 'client2' and password == 'smoke-local-only')
 assert(not inGame and screen.inGame == false and screen.visible)
 assert(ip == '127.0.0.1' and localIP == '' and port == '17343')
 connects = connects + 1
end}}
PZSurvivorToolkit = {Settings = {actionQueue = function() return true end}}
LootSorter = {}
Translator = {getLanguage = function() return {name = function() return 'RU' end} end}
sendClientCommand = function() end
print = function(message) logs[#logs + 1] = message end
require = function(name)
 if name == 'QueueTestSelection' then return {cases = {'persist-seed'}, kind = 'mp', mode = 'toolkit', port = 17343} end
 if name == 'WarehouseManifestPersistence' then return {module = 'WarehouseManifestPersistenceTest'} end
 if name == 'WarehouseManifestFixture' or name == 'PZSurvivorToolkit/ManifestClient' then return {} end
 if name == 'QueueHealthEvents' then return {encode = function(value) receipts[#receipts + 1] = value; return 'test-json' end} end
 error('Unexpected menu lifecycle dependency ' .. name)
end
""")
        lua.execute((ROOT / 'tests/native_queue/warehouse-manifest/client/ZZWarehouseManifestPersistence.lua').read_text())
        lua.execute('handlers.OnGameStart(); handlers.OnTick()')
        return lua

    def test_native_pause_exit_dispatch_is_deferred_and_stale_client_flag_allows_menu_rejoin(self):
        lua = self.fixture()
        lua.execute("handlers.OnServerCommand('WarehouseManifestPersistenceTest', 'Reconnect', {})")
        self.assertEqual(lua.eval('pauseCalls + exitCalls'), 0, 'Packet callbacks may only request native UI exit')
        self.assertIsNone(lua.eval('fileFlag'))
        lua.execute('handlers.OnTickEvenPaused()')
        self.assertEqual(lua.eval('pauseCalls'), 1)
        self.assertEqual(lua.eval('exitCalls'), 0, 'Native pause UI must become visible before Exit dispatch')
        lua.execute('handlers.OnTickEvenPaused()')
        self.assertEqual(lua.eval('exitCalls'), 1)
        self.assertEqual(lua.eval('fileFlag'), 'pending')
        lua.execute('handlers.OnPreUIDraw()')
        self.assertEqual(lua.eval('connects'), 0, 'In-game native state must block menu reconnect')
        lua.execute('inGame = false; MainScreen.instance.inGame = false; MainScreen.instance.visible = false; handlers.OnPreUIDraw()')
        self.assertEqual(lua.eval('connects'), 0, 'An invisible native menu must not initiate a connection')
        lua.execute('MainScreen.instance.visible = true; handlers.OnMainMenuEnter(); handlers.OnPreUIDraw()')
        self.assertTrue(lua.eval('staleClient'))
        self.assertEqual(lua.eval('connects'), 1, 'The stale isClient flag must not block a ready native main menu')
        self.assertFalse(lua.eval("table.concat(logs, ' '):find('FAIL', 1, true) ~= nil"))

    def test_missing_native_exit_option_fails_without_direct_exit_fallback(self):
        lua = self.fixture()
        lua.execute("handlers.OnServerCommand('WarehouseManifestPersistenceTest', 'Reconnect', {}); handlers.OnTickEvenPaused()")
        lua.execute('MainScreen.instance.exitOption = nil; handlers.OnTickEvenPaused(); handlers.OnTickEvenPaused()')
        self.assertEqual(lua.eval('exitCalls'), 0)
        self.assertIsNone(lua.eval('fileFlag'))
        self.assertEqual(lua.eval('connects'), 0)
        self.assertIn('Native pause Exit option unavailable', lua.eval('logs[#logs]'))
        self.assertIn('[WAREHOUSE_PERSIST] FAIL', lua.eval('logs[#logs]'))


if __name__ == '__main__': unittest.main()
