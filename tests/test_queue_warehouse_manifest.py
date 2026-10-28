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


def native_identities(category='Material'):
    """Synthetic native-shaped descriptors; source lifecycle tests use real Model.item."""
    result = {}
    for kind, name in (('default', ''), ('custom', adapter.CUSTOM)):
        row = dict(ft='Base.Nails', cat=category, n=1, ingredient=False, cookingState=False, usageState='00000000000000')
        if name:
            row['name'] = name
        row['key'] = ''.join(str(len(value)) + ':' + value for value in ('Base.Nails', name, category, ''))
        row['key'] += ':ingredient:false:cookingState:false:usageState:00000000000000'
        result[kind] = row
    return result


class WarehouseManifestTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.selection = dict(suite=adapter.SUITE, cases=['snapshot'], kind='mp', mode='toolkit',
                              clients=2, languages=['EN', 'RU'], mods=adapter.MODS, options={'mp_host': True})
        self.prepared = dict(boxes=[dict(x=x, y=20, z=0, object=1, ci=0, key=f'{x},20,0', id=f'{x},20,0/1/0') for x in (10, 11)],
                             ids=[101, 102, 103, 104], category='Material', identities=native_identities())
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

    def test_current_pack_uses_toolkit_categories_without_organized_categories(self):
        from queue_checks import native
        mods = native._metadata(ROOT / 'SurvivorQoL-selected.ini')['Mods'].split(';')
        self.assertNotIn('organizedCategories_core', mods)
        adapter.validate(dict(self.selection, mods=mods))
        adapter.validate(dict(self.selection, mods=mods, kind='sp', clients=1, languages=['EN'], options={}))

    def test_authoritative_native_state_schema_and_full_keys_fail_closed(self):
        self.write(); original = copy.deepcopy(self.rows)
        for field, bad in (('key', 'legacy-key'), ('n', True), ('n', 2), ('name', 'Localized default'),
                           ('ingredient', 0), ('cookingState', True), ('fluidState', 'fuel'),
                           ('usageState', 'invalid'), ('usageState', '????'), ('mediaIndex', True), ('extra', False)):
            self.rows = copy.deepcopy(original)
            self.rows['server'][0][1]['identities']['default'][field] = bad
            self.flush()
            with self.subTest(field=field): self.assertTrue(self.result()['issues'])
        self.rows = copy.deepcopy(original)
        del self.rows['server'][0][1]['identities']
        self.flush(); self.assertTrue(self.result()['issues'])

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
class WarehouseManifestIdentityTests(unittest.TestCase):
    def fixture(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(r'''
PZSurvivorToolkit={};selection={cases={'snapshot'}}
ItemType={FOOD='food'}
local function list(values)
 values=values or{};values.size=function(self)return #self end;values.get=function(self,i)return self[i+1]end
 return values
end
local script={isItemType=function()return false end}
local nextId=100
local function pool()
 local result={items=list()}
 function result:getItems()return self.items end
 function result:setType(value)self.kind=value end
 function result:getType()return self.kind end
 function result:setCapacity()end;function result:setExplored()end
 function result:AddItem(kind)
  nextId=nextId+1
  local item={id=nextId,ft=kind,container=self,name='Nails',category='Material'}
  function item:getID()return self.id end;function item:getFullType()return self.ft end
  function item:getContainer()return self.container end;function item:getScriptItem()return script end
  function item:IsFood()return false end
  function item:getDisplayCategory()return self.category end
  function item:isCustomName()return self.custom==true end
  function item:setCustomName(v)self.custom=v end
  function item:setName(v)self.name=v end
  function item:getName()return self.name end;function item:getDisplayName()return self.name end
  self.items[#self.items+1]=item;return item
 end
 function result:getItemById(id)for _,item in ipairs(self.items)do if item.id==id then return item end end end
 function result:Remove(item)for i,value in ipairs(self.items)do if value==item then table.remove(self.items,i);item.container=nil;return end end end
 return result
end
local squares={}
cell={getGridSquare=function(_,x,y,z)
 local key=x..','..y..','..z
 if not squares[key]then
  local square={x=x,y=y,z=z,objects=list()}
  function square:getX()return self.x end;function square:getY()return self.y end;function square:getZ()return self.z end
  function square:canStand()return true end;function square:isFree()return true end
  function square:getObjects()return self.objects end
  function square:AddSpecialObject(object)self.objects[#self.objects+1]=object end
  squares[key]=square
 end
 return squares[key]
end}
getCell=function()return cell end
player={inventory=pool(),getSquare=function()return cell:getGridSquare(10,20,0)end,
 getInventory=function(self)return self.inventory end}
instanceItem=function(kind)return pool():AddItem(kind)end
IsoThumpable={new=function(_,square)
 local object={square=square,pool=pool(),data={}}
 function object:getSquare()return self.square end
 function object:getContainer()return self.pool end
 function object:getObjectIndex()for i,value in ipairs(self.square.objects)do if value==self then return i-1 end end end
 function object:getModData()return self.data end;function object:hasModData()return true end
 function object:setIsContainer()end;function object:setBlockAllTheSquare()end
 return object
end}
LootSorter={isAuthority=function()return true end,serverFns={addCoord=function()return 'ok'end}}
isServer=function()return false end
package.preload['QueueTestSelection']=function()return selection end
package.preload['PZSurvivorToolkit/ItemCategories']=function()return {prepareItem=function()end}end
package.preload['PZSurvivorToolkit/TagCustomization']=function()return {itemDelta=function(item)return item.delta end}end
package.preload['PZSurvivorToolkit/ItemCookingTags']=function()return {read=function()return false end}end
package.preload['PZSurvivorToolkit/ItemFluidTags']=function()return {read=function()return nil end}end
package.preload['PZSurvivorToolkit/ItemUsageTags']=function()return {
 read=function(_,item)return item.usage or '00000000000000'end,encode=function(value)return value end}end
package.preload['PZSurvivorToolkit/ContainerAppearance']=function()return {apply=function()end}end
''')
        shared = ROOT / 'PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit'
        for name in ('ItemCookingStates', 'ManifestModel'):
            lua.execute("package.preload[%r]=function()\n%s\nend" % ('PZSurvivorToolkit/' + name, (shared / (name + '.lua')).read_text()))
        lua.execute("model=require('PZSurvivorToolkit/ManifestModel')")
        lua.globals().fixture = lua.execute((ROOT / 'tests/native_queue/warehouse-manifest/shared/WarehouseManifestFixture.lua').read_text())
        lua.execute('state,packet=fixture.prepare(player)')
        lua.execute('''
getTimestampMs=function()return 2000 end
function payloadFromSeed()
 local payload={schema=model.SCHEMA,revision=1,containers={}}
 for i,point in ipairs(packet.boxes)do
  local record={kind='crate',name=i==1 and fixture.appearance.name or 'Warehouse fixture B',
   loaded=true,sampledAt=1000,entries={},icon=i==1 and fixture.appearance.icon or nil,
   color=i==1 and fixture.appearance.color or nil}
  for key,value in pairs(point)do record[key]=value end
  for kind,identity in pairs(packet.identities)do
   if kind=='default'or i==1 then
    local entry={};for key,value in pairs(identity)do entry[key]=value end
    entry.n=kind=='default'and(i==1 and 2 or 1)or 1
    record.entries[identity.key]=entry
   end
  end
  payload.containers[point.id]=record
 end
 return payload
end
''')
        return lua

    def test_authority_uses_current_model_keys_from_exact_seeded_native_items(self):
        lua = self.fixture()
        lua.execute('''
local ordinary=state.boxes[1]:getContainer():getItemById(packet.ids[1])
local named=state.boxes[1]:getContainer():getItemById(packet.ids[4])
assert(fixture.identity(packet)==model.item(ordinary).key,'default fixture key omitted current native states')
assert(fixture.identity(packet,true)==model.item(named).key,'custom fixture key omitted current native states')
assert(fixture.identity(packet)~=model.identity(fixture.ft,nil,packet.category),'test failed to exercise state suffixes')
assert(fixture.native(state.boxes,packet,'initial',player))
assert(fixture.snapshot(payloadFromSeed(),packet,'initial'))
''')
        def primitive(value):
            return {key: primitive(item) for key, item in value.items()} if hasattr(value, 'items') else value
        adapter._item_identities(primitive(lua.globals().packet.identities), lua.globals().packet.category)

    def test_native_key_validator_preserves_utf16_custom_tag_state_encoding(self):
        lua = self.fixture()
        lua.execute('''
for kind,id in pairs({default=packet.ids[1],custom=packet.ids[4]})do
 local item=state.boxes[1]:getContainer():getItemById(id)
 item.delta={['category:tool']='remove',['category:😀']='add'}
 packet.identities[kind]=model.item(item)
end
''')
        def primitive(value):
            return {key: primitive(item) for key, item in value.items()} if hasattr(value, 'items') else value
        # This runtime indexes UTF-8; native Kahlua counts UTF-16. Use a native
        # shaped key from the same captured primitive state for that boundary.
        value = primitive(lua.globals().packet.identities)
        for row in value.values():
            tag = '13:category:tool:remove11:category:😀:add'
            row['tagKey'] = tag
            row['key'] = row['key'].split(':usageState:')[0] + ':usageState:' + row['usageState'] + str(len(tag.encode('utf-16-le')) // 2) + ':' + tag
        adapter._item_identities(value, lua.globals().packet.category)

    def test_snapshot_and_native_guards_reject_state_drift_and_legacy_keys(self):
        lua = self.fixture()
        lua.execute('''
local payload=payloadFromSeed();local record=payload.containers[packet.boxes[1].id]
record.entries[fixture.identity(packet)].cookingState=true
assert(not pcall(fixture.snapshot,payload,packet,'initial'),'snapshot accepted changed native state under the same key')
payload=payloadFromSeed();record=payload.containers[packet.boxes[1].id]
local entry=record.entries[fixture.identity(packet)]
record.entries[fixture.identity(packet)]=nil
entry.key=model.identity(fixture.ft,nil,packet.category);record.entries[entry.key]=entry
assert(not pcall(fixture.snapshot,payload,packet,'initial'),'snapshot accepted a legacy bare key')
local ordinary=state.boxes[1]:getContainer():getItemById(packet.ids[1])
ordinary.usage='00000000000001'
assert(not pcall(fixture.native,state.boxes,packet,'initial',player),'native identity ignored changed usage state')
''')


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
