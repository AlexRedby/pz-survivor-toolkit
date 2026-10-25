"""Offline native Manifest adapter validation; synthetic logs never claim a game pass."""
import copy
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import adapters
from queue_checks.adapters import warehouse_manifest as adapter
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None


class WarehouseManifestTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.selection = dict(suite=adapter.SUITE, cases=['snapshot'], kind='mp', mode='toolkit',
                              clients=2, languages=['EN', 'RU'], mods=adapter.MODS, options={'mp_host': True})
        self.prepared = dict(boxes=[dict(x=x, y=20, z=0, object=1, ci=0, key=f'{x},20,0', id=f'{x},20,0/1/0') for x in (10, 11)],
                             ids=[101, 102, 103, 104], category='Material')
        self.mutated = dict(removedId=101, customId=104, addedIds=[105, 106], changedAt=2000)
        self.transfer = dict(id=104, source='11,20,0/1/0', destination='client1')
        self.rows = {}

    def event(self, name, value):
        return adapter.MARKER + name + ' ' + json.dumps(value, ensure_ascii=False) + '\n'

    def snapshot(self, role, phase, index):
        language = self.selection['languages'][0 if role == 'client1' else 1]
        return dict(phase=phase, revision=index + 1, samples=[1000 if index == 0 else 2001] * 2,
                    counts=adapter.COUNTS[index], role=role, language=language,
                    defaultName='Nails' if language == 'EN' else 'Гвозди', customName=adapter.CUSTOM,
                    appearance=True, locations=True, nativeItems=True, rendered=True, searchLocal=True)

    def authority(self, index):
        return dict(phase=adapter.PHASES[index], counts=adapter.COUNTS[index], ids=self.prepared['ids'],
                    addedIds=[] if index == 0 else self.mutated['addedIds'])

    def idle(self, role):
        return dict(role=role, revision=1, polls=2, pages=2, itemEntries=0,
                    initialSamples=[1000, 1000], samples=[[1200, 1200], [1400, 1400]],
                    payloadSame=True, containersSame=True, viewSame=True, rowsSame=True,
                    listItemsSame=True, locationItemsSame=True, sortsSame=True)

    def write(self):
        roles = ['client1', 'client2'] if self.selection['kind'] == 'mp' else ['client1']
        for role in roles:
            rows = [('SETUP', dict(role=role, language=self.selection['languages'][0 if role == 'client1' else 1],
                                   kind=self.selection['kind'], queueEnabled=True))]
            if self.selection['kind'] == 'sp':
                rows.append(('PREPARED', self.prepared))
            rows.append(('MENU', dict(role=role, nativeCallback=True)))
            for index, phase in enumerate(adapter.PHASES):
                if index == 2 and role == 'client1':
                    rows.append(('TRANSFER', dict(self.transfer, progress=True)))
                    if self.selection['kind'] == 'sp':
                        rows.append(('TRANSFER_AUTHORITY', dict(self.transfer, unique=True)))
                width, height = ((640, 600), (480, 440), (800, 700))[index]
                rows.append(('LAYOUT', dict(width=width, height=height, fontHeight=16, footerY=height - 53,
                                           footerHeight=32, glyphBottom=32, resizeTop=height - 13, lines=2)))
                rows += [('SNAPSHOT', self.snapshot(role, phase, index)), ('SHOT', dict(role=role, phase=phase))]
                if index == 0:
                    rows.append(('IDLE', self.idle(role)))
                if self.selection['kind'] == 'sp':
                    rows.append(('AUTHORITY', self.authority(index)))
                    if index == 0:
                        rows.append(('MUTATED', self.mutated))
                shots = self.root / role / 'Screenshots'
                shots.mkdir(parents=True, exist_ok=True)
                # Header-only synthetic PNG: adapter validation is not visual certification.
                (shots / ('warehouse-manifest-' + phase + '.png')).write_bytes(
                    b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR' + struct.pack('>II', 1280, 900) + b'\0' * 9)
            if self.selection['kind'] == 'sp':
                rows.append(('CLEANUP', {'ownedObjects': 2}))
            rows.append(('COMPLETE', dict(case='snapshot', role=role)))
            self.rows[role] = copy.deepcopy(rows)
        if self.selection['kind'] == 'mp':
            self.rows['server'] = [('PREPARED', self.prepared), ('AUTHORITY', self.authority(0)),
                                   ('MUTATED', self.mutated), ('AUTHORITY', self.authority(1)),
                                   ('TRANSFER_AUTHORITY', dict(self.transfer, unique=True)),
                                   ('AUTHORITY', self.authority(2)), ('CLEANUP', {'ownedObjects': 2})]
        self.flush()

    def flush(self):
        for role, rows in self.rows.items():
            text = '[STARTUP_TEST] SERVER_READY\n' if role == 'server' else ''
            text += ''.join(self.event(name, value) for name, value in rows)
            (self.root / (role + '-launch.log')).write_text(text)

    def result(self):
        return adapter.verify(self.root, self.selection, {})

    def test_registration_sp_language_and_two_client_host_contracts(self):
        self.assertIs(adapters.get(adapter.SUITE), adapter)
        self.assertEqual(adapters.definitions()[adapter.SUITE]['clients'], 2)
        adapter.validate(self.selection)
        for changes in ({'clients': 1}, {'clients': True}, {'options': {}}, {'options': {'mp_host': 1}},
                        {'mode': 'native'}, {'languages': ['EN']}, {'cases': ['other']}, {'mods': adapter.MODS[:-1]},
                        {'options': {'mp_host': True, 'world_template': '/tmp/existing'}}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                adapter.validate(dict(self.selection, **changes))
        for language in ('EN', 'RU'):
            adapter.validate(dict(self.selection, kind='sp', clients=1, languages=[language], options={}))
        with self.assertRaises(ValueError):
            adapter.validate(dict(self.selection, kind='sp', clients=1, languages=['EN']))

    def test_fixture_dependencies_staged_for_every_role_and_source_sealed(self):
        runtime = {'roles': {role: {'cache': str(self.root / role)} for role in ('server', 'client1', 'client2')}}
        adapter.stage(ROOT, self.root, None, None, self.selection, {}, runtime)
        sealed = adapter.sources(ROOT, self.selection)
        for side, filename in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua'), ('shared', 'QueueHealthEvents.lua')]:
            source = ROOT / 'tests/native_queue' / ('health' if side == 'shared' else 'startup') / side / filename
            self.assertIn(source, sealed)
            for role in runtime['roles']:
                self.assertEqual((self.root / role / 'mods/ActionQueueTest/42/media/lua' / side / filename).read_bytes(), source.read_bytes())
        own = sorted((ROOT / 'tests/native_queue/warehouse-manifest').rglob('*.lua'))
        self.assertGreaterEqual(len(own), 6)
        self.assertTrue(all(path in sealed for path in own))
        self.assertEqual(runtime['fixture']['failure_markers'], [adapter.MARKER + 'FAIL ', '[WAREHOUSE_PERSIST] FAIL ', '[WAREHOUSE_LEGACY] FAIL '])
        self.assertEqual(runtime['fixture']['client_launch_stagger_seconds'], 8)

    def test_strict_native_counts_both_languages_all_three_snapshots(self):
        self.write()
        self.assertEqual(self.result()['issues'], [])
        self.assertEqual(len(self.result()['evidence']['screenshots']), 6)
        for role in ('client1', 'client2'):
            self.assertTrue(adapter.complete(self.selection, role, (self.root / (role + '-launch.log')).read_text()))
        self.selection.update(kind='sp', clients=1, languages=['RU'], options={})
        self.rows = {}; self.write()
        self.assertEqual(self.result()['issues'], [])
        self.assertEqual(len(self.result()['evidence']['screenshots']), 3)

    def test_footer_clipping_and_missing_layout_evidence_fail(self):
        self.write(); original = copy.deepcopy(self.rows)
        for key, wrong in [('glyphBottom', 33), ('footerY', 558), ('footerHeight', 60),
                           ('resizeTop', 550), ('lines', 1), ('fontHeight', True)]:
            self.rows = copy.deepcopy(original)
            row = next(value for name, value in self.rows['client1'] if name == 'LAYOUT')
            row[key] = wrong; self.flush()
            with self.subTest(key=key):
                self.assertTrue(self.result()['issues'])

    def test_missing_duplicate_reordered_events_and_failure_markers_are_rejected(self):
        self.write(); original = copy.deepcopy(self.rows)
        for role in original:
            for index in range(len(original[role])):
                for mutation in ('missing', 'duplicate'):
                    self.rows = copy.deepcopy(original)
                    if mutation == 'missing':
                        del self.rows[role][index]
                    else:
                        self.rows[role].insert(index, self.rows[role][index])
                    self.flush()
                    with self.subTest(role=role, index=index, mutation=mutation):
                        self.assertTrue(self.result()['issues'])
            self.rows = copy.deepcopy(original); self.rows[role].reverse(); self.flush()
            self.assertTrue(self.result()['issues'])
        self.rows = original; self.flush()
        log = self.root / 'client2-launch.log'
        log.write_text(log.read_text() + adapter.MARKER + 'FAIL observer mismatch\n')
        self.assertTrue(self.result()['issues'])

    def test_unknown_wrong_bool_stale_revision_and_localization_evidence_fail(self):
        self.write(); original = copy.deepcopy(self.rows)
        for key, wrong in [('counts', [True, 1, 1, 0]), ('revision', True), ('revision', 0),
                           ('samples', [0, 0]), ('nativeItems', 1), ('searchLocal', False),
                           ('rendered', False), ('defaultName', ''), ('customName', 'Nails'), ('extra', True)]:
            self.rows = copy.deepcopy(original)
            row = next(value for name, value in self.rows['client2'] if name == 'SNAPSHOT')
            row[key] = wrong; self.flush()
            with self.subTest(key=key, wrong=wrong):
                self.assertTrue(self.result()['issues'])
        self.rows = copy.deepcopy(original)
        snapshots = [value for name, value in self.rows['client2'] if name == 'SNAPSHOT']
        snapshots[1]['revision'] = snapshots[0]['revision']; self.flush()
        self.assertTrue(self.result()['issues'])
        self.rows = copy.deepcopy(original)
        for name, value in self.rows['client2']:
            if name == 'SNAPSHOT':
                value['defaultName'] = 'Nails'
        self.flush(); self.assertTrue(self.result()['issues'])

    def test_idle_requires_two_fresh_polls_without_content_or_cache_invalidation(self):
        self.write(); original = copy.deepcopy(self.rows)
        self.assertEqual(set(self.result()['evidence']['idle']), {'client1', 'client2'})
        for key, wrong in [('role', 'client1'), ('revision', True), ('revision', 2), ('polls', True), ('polls', 1),
                           ('pages', True), ('pages', 1), ('itemEntries', False), ('itemEntries', 1),
                           ('initialSamples', [999, 1000]), ('samples', [[1200, 1200]]),
                           ('samples', [[1000, 1200], [1400, 1400]]),
                           ('samples', [[1200, 1200], [1400, 1200]]),
                           ('samples', [[1200, 1200], [2001, 1400]]),
                           ('samples', [[True, 1200], [1400, 1400]]),
                           *[(key, False) for key in ('payloadSame', 'containersSame', 'viewSame', 'rowsSame',
                                                     'listItemsSame', 'locationItemsSame', 'sortsSame')],
                           ('extra', True)]:
            self.rows = copy.deepcopy(original)
            row = next(value for name, value in self.rows['client2'] if name == 'IDLE')
            row[key] = wrong; self.flush()
            with self.subTest(key=key, wrong=wrong):
                self.assertTrue(self.result()['issues'])

    def test_missing_server_native_transfer_endpoint_or_wrong_custom_id_fail(self):
        self.write(); original = copy.deepcopy(self.rows)
        for event, changes in [('TRANSFER_AUTHORITY', {'destination': 'client2'}), ('MUTATED', {'customId': 999}),
                               ('MUTATED', {'addedIds': [101, 106]}), ('AUTHORITY', {'counts': [4, 0, 0, 0]})]:
            self.rows = copy.deepcopy(original)
            value = next(value for name, value in self.rows['server'] if name == event)
            value.update(changes); self.flush()
            with self.subTest(event=event, changes=changes):
                self.assertTrue(self.result()['issues'])
        self.rows = copy.deepcopy(original); self.flush()
        (self.root / 'client2/Screenshots/warehouse-manifest-transferred.png').unlink()
        self.assertTrue(self.result()['issues'])

    def test_duplicate_json_keys_nonfinite_values_and_malformed_receipts_fail(self):
        self.write()
        path = self.root / 'client1-launch.log'; original = path.read_text()
        for value in ('{"case":"snapshot","case":"snapshot","role":"client1"}',
                      '{"case":"snapshot","role":NaN}', '[]', '{broken'):
            text = original[:original.index(adapter.MARKER + 'COMPLETE ')]
            path.write_text(text + adapter.MARKER + 'COMPLETE ' + value + '\n')
            with self.subTest(value=value):
                self.assertTrue(self.result()['issues'])
                self.assertFalse(adapter.complete(self.selection, 'client1', path.read_text()))


@unittest.skipIf(LuaRuntime is None, 'Lupa is required to execute the native fixture lifecycle')
class WarehouseManifestLifecycleTests(unittest.TestCase):
    def fixture(self, expose_idle=False):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(r"""
now, actor, online, live, sends, gods, ghosts = 0, nil, -1, nil, 0, 0, 0
handlers, receipts, logs = {}, {}, {}
Events = setmetatable({}, {__index = function(self, key)
 local event = {Add = function(callback) handlers[key] = callback end}
 rawset(self, key, event); return event
end})
local player = {getUsername = function() return actor end, getOnlineID = function() return online end,
 isDead = function() return false end, getSquare = function() return {} end,
 setGodMod = function() gods = gods + 1 end, setGhostMode = function() ghosts = ghosts + 1 end}
function setPlayer(value) live = value and player or nil end
getPlayer = function() return live end
getTimestampMs = function() return now end
isIngameState = function() return true end
isClient = function() return true end
sendClientCommand = function(module, command) assert(command == 'Prepare'); sends = sends + 1 end
PZSurvivorToolkit = {Settings = {actionQueue = function() return true end}}
LootSorter = {}
manifestClient = {}
Translator = {getLanguage = function() return {name = function() return 'EN' end} end}
print = function(message) logs[#logs + 1] = message end
require = function(name)
 if name == 'QueueTestSelection' then return {kind = 'mp', mode = 'toolkit', cases = {'snapshot'}} end
 if name == 'WarehouseManifestFixture' then return {module = 'WarehouseManifestTest'} end
 if name == 'PZSurvivorToolkit/ManifestClient' then return manifestClient end
 if name == 'QueueHealthEvents' then return {encode = function(value)
  receipts[#receipts + 1] = value; return 'test-json'
 end} end
 error('Unexpected fixture dependency: ' .. name)
end
""")
        source = (ROOT / 'tests/native_queue/warehouse-manifest/client/ZZWarehouseManifest.lua').read_text()
        if expose_idle:
            # Exercise the fixture's actual local observer without opening game UI or changing its exports.
            source += """
return {start = function(window, target) win = window; packet = target; role = 'client1'; startIdle() end,
 finish = finishIdle, stop = stopIdle}
"""
            lua.globals().idleHarness = lua.execute(source)
        else:
            lua.execute(source)
        return lua

    def idle_fixture(self):
        lua = self.fixture(expose_idle=True)
        lua.execute("""
record = {sampledAt = 10}
payload = {revision = 7, containers = {box = record}}
clientState = {payload = payload, status = 'ready'}
manifestClient.getState = function() return clientState end
row = {n = 3}
window = {view = {payload = payload, rows = {row}, sorts = {count = {row}}},
 listBox = {items = {{item = row}}}, locations = {items = {{item = {container = record}}}}}
rpcCallbacks = {}
originalRpc = function(name, args, callback) rpcCallbacks[#rpcCallbacks + 1] = callback end
LootSorter.callServer = originalRpc
idleHarness.start(window, {boxes = {{id = 'box'}}})
function requestIdle()
 LootSorter.callServer('manifestPage', {revision = 7}, function(verdict, detail)
  assert(verdict == 'ok')
  for id, stamp in pairs(detail.samples or {}) do payload.containers[id].sampledAt = stamp end
 end)
end
function replyIdle(stamp)
 local callback = table.remove(rpcCallbacks, 1)
 callback('ok', {revision = 7, unchanged = true, samples = {box = stamp}})
end
""")
        return lua

    def test_idle_observer_counts_real_completed_replies_then_restores_rpc(self):
        lua = self.idle_fixture()
        lua.execute('requestIdle()')
        self.assertFalse(lua.eval('idleHarness.finish()'))
        lua.execute('replyIdle(20)')
        self.assertFalse(lua.eval('idleHarness.finish()'))
        self.assertFalse(lua.eval('LootSorter.callServer == originalRpc'))
        lua.execute('requestIdle(); replyIdle(30)')
        self.assertTrue(lua.eval('LootSorter.callServer == originalRpc'))
        self.assertTrue(lua.eval('idleHarness.finish()'))
        self.assertEqual(lua.eval('receipts[1].polls'), 2)
        self.assertEqual(lua.eval('receipts[1].pages'), 2)
        self.assertEqual(lua.eval('receipts[1].itemEntries'), 0)
        self.assertEqual(lua.eval('receipts[1].samples[2][1]'), 30)

    def test_idle_observer_detects_rebuild_and_restores_rpc_on_error(self):
        lua = self.idle_fixture()
        lua.execute('requestIdle(); window.listBox.items = {{item = row}}; replyIdle(20)')
        self.assertTrue(lua.eval('LootSorter.callServer == originalRpc'))
        ok, problem = lua.eval('pcall(idleHarness.finish)')
        self.assertFalse(ok)
        self.assertIn('Idle replaced item list', problem)

    def test_idle_observer_rejects_stale_timestamp_and_item_entry_download(self):
        for response, message in (("{revision=7,unchanged=true,samples={box=10}}", 'Idle sample age did not advance'),
                                  ("{revision=7,unchanged=true,samples={box=20},containers={{entries={nail={n=3}}}}}",
                                   'Idle downloaded item entries')):
            with self.subTest(response=response):
                lua = self.idle_fixture()
                lua.execute("requestIdle(); table.remove(rpcCallbacks, 1)('ok', " + response + ")")
                self.assertTrue(lua.eval('LootSorter.callServer == originalRpc'))
                ok, problem = lua.eval('pcall(idleHarness.finish)')
                self.assertFalse(ok)
                self.assertIn(message, problem)

    def test_on_game_start_waits_for_native_actor_then_sets_up_once_before_preparing(self):
        lua = self.fixture()
        lua.execute("handlers.OnGameStart(); handlers.OnTick()")
        self.assertEqual(lua.eval('#receipts'), 0)
        self.assertEqual(lua.eval('sends + gods + ghosts'), 0)
        lua.execute("setPlayer(true); now = 100; handlers.OnTick()")
        self.assertEqual(lua.eval('#receipts'), 0)
        lua.execute("actor = 'temporary'; online = 7; now = 1000; handlers.OnTick()")
        self.assertEqual(lua.eval('#receipts'), 0)
        lua.execute("actor = 'client1'; now = 1500; handlers.OnTick()")
        self.assertEqual(lua.eval('receipts[1].role'), 'client1')
        self.assertEqual(lua.eval('receipts[2].event'), 'setup')
        self.assertEqual(lua.eval('sends'), 1)
        self.assertEqual(lua.eval('gods'), 1)
        self.assertEqual(lua.eval('ghosts'), 1)
        lua.execute("handlers.OnTick(); handlers.OnGameStart(); handlers.OnTick()")
        self.assertEqual(lua.eval('#receipts'), 2)
        self.assertEqual(lua.eval('sends'), 1)
        self.assertEqual(lua.eval('gods'), 1)
        self.assertEqual(lua.eval('ghosts'), 1)
        self.assertFalse(lua.eval("table.concat(logs, ' '):find('FAIL', 1, true) ~= nil"))

    def test_persistent_unknown_actor_has_bounded_failure_without_setup_or_preparation(self):
        lua = self.fixture()
        lua.execute("handlers.OnGameStart(); setPlayer(true); actor = 'foreign'; online = 7; now = 29999; handlers.OnTick()")
        self.assertEqual(lua.eval('#receipts'), 0)
        lua.execute("now = 30000; handlers.OnTick(); handlers.OnTick()")
        self.assertEqual(lua.eval('#receipts'), 0)
        self.assertEqual(lua.eval('sends + gods + ghosts'), 0)
        self.assertEqual(lua.eval('#logs'), 1)
        self.assertIn('Warehouse fixture actor readiness timeout: foreign', lua.eval('logs[1]'))
        self.assertIn('[WAREHOUSE_MANIFEST] FAIL', lua.eval('logs[1]'))


if __name__ == '__main__':
    unittest.main()
