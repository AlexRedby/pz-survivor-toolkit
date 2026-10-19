"""Synthetic MP hotkey evidence/protocol checks; no native game launch."""
import copy
import json
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'tests/native_queue/contributions/wooden_cart_multiplayer'
ANALYZER = runpy.run_path(str(SOURCE / 'analyze.py'))
FIXTURE = runpy.run_path(str(SOURCE / 'self_check.py'))['fixture']
PREFIX = '[CART_MP_ACTION] '


class CartMPHotkeyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        FIXTURE(self.root, actions=True, variant='wooden-wheelbarrow')
        selection = json.loads((self.root / 'selection.json').read_text())
        selection['options']['cart_hotkey_setdown'] = True
        (self.root / 'selection.json').write_text(json.dumps(selection))
        self.logs = {}
        self.poses = {1: dict(x=1.25, y=2.75, z=0, rotation=90),
                      3: dict(x=1.5, y=2.5, z=0, rotation=135),
                      4: dict(x=2.25, y=3.75, z=0, rotation=180)}
        for role in ('client1', 'server', 'client2'):
            entries = []
            for line in (self.root / (role + '-launch.log')).read_text().splitlines():
                if not line.startswith(PREFIX):
                    entries.append(line)
                    continue
                kind, raw = line[len(PREFIX):].split(' ', 1)
                row = json.loads(raw)
                index = row.get('index')
                if kind == 'BEGIN':
                    row['inputRoute'] = 'hotkey' if index in self.poses else 'menu'
                if kind in ('RECEIPT', 'SERVER_RECEIPT', 'SERVER_ACK') and index in (1, 4, 5):
                    row['expectedWorld'] = copy.deepcopy(self.poses[1 if index == 1 else 4])
                    row['worldPose'] = copy.deepcopy(row['expectedWorld'])
                entries.append((kind, row))
            self.logs[role] = entries
        owner = self.rows('client1', 'RECEIPT')
        for begin in self.rows('client1', 'BEGIN'):
            index = begin['index']
            if index not in self.poses:
                continue
            base = dict(actor='client1', index=index, phase=begin['phase'], id=42)
            pose = self.poses[index]
            self.logs['client1'].append(('INPUT', dict(base, wall=begin['wall']+1, inputRoute='hotkey', event='OnKeyStartPressed', key=47,
                rebound=False, events=['OnKeyStartPressed', 'OnCustomUIKeyPressed'])))
            self.logs['client1'].append(('QUEUED', dict(base, wall=begin['wall']+2, inputRoute='hotkey', actionType='ToolkitWoodCartDrop', maxTime=88)))
            self.logs['client1'].append(('RELEASED', dict(base, wall=begin['wall']+51,key=47,actionType='ToolkitWoodCartDrop',
                queuedCount=1,sameAction=True,events=['OnKeyPressed','OnCustomUIKey','OnCustomUIKeyReleased'])))
            self.logs['client1'].append(('SERIALIZED', dict(base, wall=begin['wall']+50, actionType='ToolkitWoodCartDrop', maxTime=88,
                started=True, sqX=int(pose['x']), sqY=int(pose['y']), sqZ=0,
                xoffset=pose['x']%1, yoffset=pose['y']%1, zoffset=0, rotation=pose['rotation'], isMultiple=False,
                expectedWorld=copy.deepcopy(pose), plannedWorld=copy.deepcopy(pose))))
        for row in owner:
            observation = {key: copy.deepcopy(value) for key, value in row.items()
                           if key not in ('ok', 'held', 'ground', 'holdMs', 'cancelled', 'nativeProgress',
                                          'presentationProgress', 'recoveryEnded', 'recoveryObserved', 'elapsed')}
            observation.pop('inventoryCount', None)
            observation.update(actor='client2', wall=row['wall']+50, worldAttached=row['worldCount'] == 1,
                inventoryScope='remote-hand-snapshot',itemSource='world' if row['worldCount'] else 'hands',handSameItem=row['worldCount']==0)
            self.logs['client2'].append(('OBSERVER_RECEIPT', observation))
            self.logs['server'].append(('SERVER_OBSERVATION', copy.deepcopy(observation)))

    def rows(self, role, kind):
        return [entry[1] for entry in self.logs[role] if isinstance(entry, tuple) and entry[0] == kind]

    def analyze(self):
        for role, entries in self.logs.items():
            (self.root / (role + '-launch.log')).write_text('\n'.join(
                entry if isinstance(entry, str) else PREFIX + entry[0] + ' ' + json.dumps(entry[1]) for entry in entries) + '\n')
        return ANALYZER['analyze'](self.root)

    def test_native_input_started_fields_and_three_replication_endpoints(self):
        report = self.analyze()['actions']
        self.assertTrue(report['hotkeySetdown']['evidenceComplete'])
        self.assertEqual(report['hotkeySetdown']['worldEndpointRoles'], ['client1', 'server', 'client2'])
        self.assertEqual(len(report['phases']['client2']), 6)
        self.assertIn('palmHandleErrorMax', report['phases']['client2'][0])
        self.assertIn('wheelFloorRange', report['phases']['client2'][0])

    def test_rejects_missing_duplicate_or_fabricated_input_and_constructor(self):
        original = copy.deepcopy(self.logs)
        mutations = (
            ('INPUT', 'event', 'OnKeyPressed'), ('INPUT', 'key', 0), ('INPUT', 'events', ['OnKeyStartPressed']),
            ('RELEASED', 'key', 100), ('RELEASED', 'events', ['OnKeyPressed']), ('RELEASED', 'queuedCount', 2),
            ('RELEASED', 'sameAction', False), ('RELEASED', 'wall', 0), ('QUEUED', 'actionType', 'ToolkitWoodCartSetdown'),
            ('SERIALIZED', 'started', False), ('SERIALIZED', 'sqX', 99), ('SERIALIZED', 'rotation', 10),
            ('SERIALIZED', 'xoffset', 0), ('SERIALIZED', 'isMultiple', True), ('SERIALIZED', 'maxTime', 15),
        )
        for kind, field, value in mutations:
            with self.subTest(kind=kind, field=field):
                self.logs = copy.deepcopy(original)
                self.rows('client1', kind)[0][field] = value
                with self.assertRaises(ValueError):
                    self.analyze()
        for kind in ('INPUT', 'QUEUED', 'SERIALIZED', 'RELEASED'):
            for duplicate in (False, True):
                with self.subTest(kind=kind, duplicate=duplicate):
                    self.logs = copy.deepcopy(original)
                    target = next(entry for entry in self.logs['client1'] if isinstance(entry, tuple) and entry[0] == kind)
                    if duplicate:
                        self.logs['client1'].append(copy.deepcopy(target))
                    else:
                        self.logs['client1'].remove(target)
                    with self.assertRaises(ValueError):
                        self.analyze()

    def test_rejects_each_wrong_world_endpoint_and_observer_timing_or_identity(self):
        original = copy.deepcopy(self.logs)
        for role, kind in (('client1', 'RECEIPT'), ('server', 'SERVER_RECEIPT'), ('client2', 'OBSERVER_RECEIPT')):
            for field in ('x', 'y', 'z', 'rotation'):
                with self.subTest(role=role, field=field):
                    self.logs = copy.deepcopy(original)
                    self.rows(role, kind)[0]['worldPose'][field] += .1
                    with self.assertRaises(ValueError):
                        self.analyze()
        for field, value in (('id', 43), ('cargoPreserved', False), ('worldCount', 2), ('wall', 999999), ('nativeActions', 1), ('inventoryCount', 1), ('handSameItem', True), ('inventoryScope', 'owner-inventory')):
            with self.subTest(field=field):
                self.logs = copy.deepcopy(original)
                self.rows('client2', 'OBSERVER_RECEIPT')[0][field] = value
                with self.assertRaises(ValueError):
                    self.analyze()
        self.logs = copy.deepcopy(original)
        self.rows('client2', 'OBSERVER_RECEIPT')[4]['worldPose']['x'] += .1
        with self.assertRaises(ValueError):
            self.analyze()

    def test_native_float_tolerance_and_wrapped_yaw(self):
        for role, kind in (('client1', 'RECEIPT'), ('server', 'SERVER_RECEIPT'), ('client2', 'OBSERVER_RECEIPT'), ('server', 'SERVER_OBSERVATION')):
            self.rows(role, kind)[0]['worldPose']['x'] += .001
            self.rows(role, kind)[0]['worldPose']['rotation'] += 360
        self.assertTrue(self.analyze()['actions']['hotkeySetdown']['evidenceComplete'])

    def test_lua_dispatch_records_started_fields_and_observer_waits_for_replication(self):
        lua = shutil.which('luajit') or shutil.which('lua')
        if not lua:
            self.skipTest('Lua interpreter unavailable')
        code = r"""
for _,name in ipairs({'SaucedCarts/ContextMenu','ISUI/ISContextMenu','ISUI/ISInventoryPaneContextMenu','TimedActions/ISTimedActionQueue'}) do
 package.preload[name]=function() return {} end
end
package.preload.QueueTestSelection=function() return {disposable=true,options={cart_hotkey_setdown=true,cart_hotkey_key=100}} end
package.preload.CartMPJSON=function() return dofile(JSON_SOURCE) end
local function list(values) return {size=function() return #values end,get=function(_,i) return values[i+1] end} end
local now,held,started,worldX,active,observations,remoteOnly=1000,true,false,9,true,0,false
local q={queue={}}
local cargo={getID=function() return 99 end,getFullType=function() return 'Base.Log' end,getActualWeight=function() return 70 end}
local cargoInventory={getItems=function() return list({cargo}) end}
local world
local cart={getID=function() return 42 end,getFullType=function() return 'SaucedWheelbarrow.WheelbarrowWood' end,
 getInventory=function() return cargoInventory end,getWorldItem=function() return not held and world or nil end,
 getWorldZRotation=function() return 90 end}
world={getItem=function() return cart end,getWorldPosX=function() return worldX end,
 getWorldPosY=function() return 2.75 end,getWorldPosZ=function() return 0 end}
local sq={getX=function() return 1 end,getY=function() return 2 end,getZ=function() return 0 end,
 getWorldObjects=function() return list(not held and {world} or {}) end}
local inventory={getItems=function() assert(not remoteOnly,'Observer tried to read an unreplicated owner inventory list');return list(held and {cart} or {}) end}
local native={size=function() return 0 end,isEmpty=function() return true end}
local player={getInventory=function() return inventory end,getPrimaryHandItem=function() return held and cart or nil end,
 getSecondaryHandItem=function() return held and cart or nil end,getX=function() return 1 end,getY=function() return 2 end,
 getZ=function() return 0 end,getPlayerNum=function() return 0 end,getCharacterActions=function() return native end,
 hasPath=function() return false end,isTimedActionInstant=function() return false end}
getCell=function() return {getGridSquare=function(_,x,y,z) if x==1 and y==2 and z==0 then return sq end end} end
getTimestampMs=function() return now end
ISTimedActionQueue={getTimedActionQueue=function() return q end}
PZSurvivorToolkit={ActionQueueOperations={run=function(fn) fn() end}}
local binding=47
PZAPI={ModOptions={save=function() error('Fixture saved a runtime test binding') end,
 getOptions=function(_,id) assert(id=='SaucedCarts');return {getOption=function(_,key)
  assert(key=='PushCart');return {getValue=function() return binding end,setValue=function(_,value) binding=value end} end} end}}
ISInventoryPaneContextMenu={onUnEquip=function() error('Menu bypassed requested hotkey') end}
local drop={Type='ToolkitWoodCartDrop',item=cart,maxTime=88,sq=sq,xoffset=.5,yoffset=.5,zoffset=0,rotation=0,isMultiple=false,
 isStarted=function() return started end,getJobDelta=function() return .2 end,
 toolkitDropX=1.25,toolkitDropY=2.75,toolkitDropZ=0,toolkitDropRotation=90}
local events={}
triggerEvent=function(event,key)
 assert(key==100 and binding==100);events[#events+1]=event
 if event=='OnKeyStartPressed' then q.queue={drop};q.current=drop end
end
sendClientCommand=function(_,command,row)
 if command=='ActionObservation' then
  observations=observations+1;assert(row.actor=='client2' and row.inventoryCount==nil)
  if row.index==1 then assert(row.worldPose.x==1.25)
  else assert(row.itemSource=='hands' and row.handSameItem and row.cargoPreserved) end
 end
end
toolkitWoodCartStatus=function() return {active=active,progress=active and .2 or 0} end
local actions=dofile(ACTIONS_SOURCE)
actions.tick(player,{cartId=42},now)
assert(q.queue[1]==drop and drop.xoffset==.5,'Input fixture overwrote native constructor fields')
assert(#events==2 and events[1]=='OnKeyStartPressed' and events[2]=='OnCustomUIKeyPressed','Press events/release tick differ')
started=true;drop.xoffset=.25;drop.yoffset=.75;drop.rotation=90;now=1100
actions.tick(player,{cartId=42},now)
assert(#events==5 and events[3]=='OnKeyPressed' and events[4]=='OnCustomUIKey' and events[5]=='OnCustomUIKeyReleased',
 'Native release sequence differs or was repeated')
-- A separate observer instance reads native state and never changes owner hands or items.
local observer=dofile(ACTIONS_SOURCE)
remoteOnly=true
observer.command('ActionPhase',{index=1,phase='drop-complete',id=42})
observer.command('ActionAudit',{index=1,phase='drop-complete',id=42,cargoID=99,cargoWeight=70,
 expectedWorld={x=1.25,y=2.75,z=0,rotation=90}})
observer.sample(player,'client2');assert(observations==0,'Held state was accepted as replicated ground placement')
held=false;q.queue={};q.current=nil;active=false;now=1200
observer.sample(player,'client2');assert(observations==0,'Incorrect replicated placement was accepted')
worldX=1.25;now=1300
observer.sample(player,'client2');assert(observations==1,'Settled exact native world receipt missing')
now=1400;observer.sample(player,'client2');assert(observations==1,'Observer duplicated native receipt')
observer.command('ActionAck',{index=1,phase='drop-complete',id=42,ok=true})
observer.command('ActionPhase',{index=2,phase='pickup-complete',id=42})
observer.command('ActionAudit',{index=2,phase='pickup-complete',id=42,cargoID=99,cargoWeight=70})
held=true;now=1500;observer.sample(player,'client2')
assert(observations==2,'Exact replicated hand/cargo snapshot was not accepted without an inventory list')
"""
        code = code.replace('JSON_SOURCE', json.dumps(str(SOURCE / 'json.lua'))).replace('ACTIONS_SOURCE', json.dumps(str(SOURCE / 'actions.lua')))
        result = subprocess.run([lua, '-e', code], check=True, capture_output=True, text=True)
        rows = [line[len(PREFIX):].split(' ', 1) for line in result.stdout.splitlines() if line.startswith(PREFIX)]
        started = [json.loads(raw) for kind, raw in rows if kind == 'SERIALIZED']
        self.assertEqual(len(started), 1)
        self.assertEqual(started[0]['xoffset'], .25)
        self.assertEqual(started[0]['expectedWorld'], self.poses[1])
        self.assertEqual(started[0]['plannedWorld'], self.poses[1])
        self.assertEqual(len([kind for kind, _ in rows if kind == 'INPUT']), 1)
        released = [json.loads(raw) for kind, raw in rows if kind == 'RELEASED']
        self.assertEqual(len(released), 1)
        self.assertEqual(released[0]['key'], 100)
        self.assertEqual(released[0]['queuedCount'], 1)
        self.assertEqual(len([kind for kind, _ in rows if kind == 'OBSERVER_RECEIPT']), 2)
        duplicate = code.replace(
            "if event=='OnKeyStartPressed' then q.queue={drop};q.current=drop end",
            "if event=='OnKeyStartPressed' then q.queue={drop};q.current=drop end\n if event=='OnKeyPressed' then q.queue[2]=drop end")
        rejected = subprocess.run([lua, '-e', duplicate], capture_output=True, text=True)
        self.assertNotEqual(rejected.returncode, 0)
        self.assertIn('Key release changed or duplicated', rejected.stderr)

    def test_server_waits_for_observer_and_independent_exact_world_placement(self):
        lua = shutil.which('luajit') or shutil.which('lua')
        if not lua:
            self.skipTest('Lua interpreter unavailable')
        code = r"""
package.preload.QueueTestSelection=function() return {disposable=true,options={cart_actions=true,cart_hotkey_setdown=true}} end
package.preload.CartMPJSON=function() return dofile(JSON_SOURCE) end
package.preload.CartMPPlacement=function() return function() return {x=1,y=2,z=0} end end
local callbacks={}
Events={}
for _,name in ipairs({'OnServerStarted','OnClientCommand','OnTick'}) do
 Events[name]={Add=function(fn) callbacks[name]=fn end}
end
local function list(values) return {size=function() return #values end,get=function(_,i) return values[i+1] end} end
local now,held,worldX,acks=1000,true,1.25,0
getTimestampMs=function() return now end
sendServerCommand=function(_,_,command) if command=='ActionAck' then acks=acks+1 end end
sendAddItemToContainer=function() end
cartMPSeedSprinting=function() return 10 end
cartMPState=function() return '{}' end;cartMPTraffic=function() return '{}' end
Perks={Sprinting='sprint'}
local cargo={getID=function() return 99 end,getFullType=function() return 'Base.Log' end,getActualWeight=function() return 70 end,
 setActualWeight=function() end,setCustomWeight=function() end}
local cargoInventory={getItems=function() return list({cargo}) end,AddItem=function() return cargo end,getEffectiveCapacity=function() return 70 end}
local world
local cart={getID=function() return 42 end,getFullType=function() return 'SaucedWheelbarrow.WheelbarrowWood' end,
 getInventory=function() return cargoInventory end,getWorldItem=function() return not held and world or nil end,
 getWorldZRotation=function() return 90 end}
world={getItem=function() return cart end,getWorldPosX=function() return worldX end,
 getWorldPosY=function() return 2.75 end,getWorldPosZ=function() return 0 end}
local sq={getWorldObjects=function() return list(not held and {world} or {}) end}
getCell=function() return {getGridSquare=function(_,x,y,z) if x==1 and y==2 and z==0 then return sq end end} end
local inventory={AddItem=function() return cart end,getItems=function() return list(held and {cart} or {}) end}
local function player(user)
 return {getUsername=function() return user end,getCurrentSquare=function() return sq end,getInventory=function() return inventory end,
  getPrimaryHandItem=function() return held and cart or nil end,getSecondaryHandItem=function() return held and cart or nil end,
  getX=function() return 1 end,getY=function() return 2 end,getZ=function() return 0 end,
  getPerkLevel=function() return 10 end,teleportTo=function() end,
  getCharacterActions=function() return {size=function() return 0 end} end,hasPath=function() return false end}
end
local owner,observer=player('client1'),player('client2')
dofile(SERVER_SOURCE)
local function command(name,p,args) callbacks.OnClientCommand('CartMP',name,p,args or {}) end
command('Ready',owner);command('Ready',observer)
command('Armed',owner,{sprintLevel=10});command('Armed',observer,{sprintLevel=0})
now=41000
local pose={x=1.25,y=2.75,z=0,rotation=90}
command('ActionBegin',owner,{index=1,phase='drop-complete',id=42})
held=false
command('ActionCheck',owner,{index=1,phase='drop-complete',id=42,expectedWorld=pose})
callbacks.OnTick();now=41200;callbacks.OnTick();assert(acks==0,'Server acknowledged before native observer receipt')
command('ActionObservation',observer,{actor='client2',index=1,phase='drop-complete',id=42,cargoID=99,
 cargoPreserved=true,cargoWeight=70,inventoryScope='remote-hand-snapshot',itemSource='world',handSameItem=false,
 luaActions=0,nativeActions=0,hasPath=false,worldAttached=true,worldCount=1,primaryID=-1,secondaryID=-1,worldPose=pose})
worldX=2.25;now=41300;callbacks.OnTick();now=41500;callbacks.OnTick()
assert(acks==0,'Observer receipt masked wrong independent server placement')
worldX=1.25;now=41600;callbacks.OnTick();assert(acks==0,'Server skipped stable native endpoint hold')
now=41701;callbacks.OnTick();assert(acks==2,'Native replicated server endpoint did not acknowledge both roles')
"""
        code = code.replace('JSON_SOURCE', json.dumps(str(SOURCE / 'json.lua'))).replace('SERVER_SOURCE', json.dumps(str(SOURCE / 'server.lua')))
        result = subprocess.run([lua, '-e', code], check=True, capture_output=True, text=True)
        self.assertNotIn('[QUEUE_TEST] FAIL', result.stdout)
        self.assertEqual(result.stdout.count('[CART_MP_ACTION] SERVER_RECEIPT '), 1)

    def test_exact_native_duration_after_fractional_physiological_adjustment(self):
        original = copy.deepcopy(self.logs)
        actual = (88.01349067687988, 88.00900077819824, 88.00698661804199)
        for kind in ('QUEUED', 'SERIALIZED'):
            for row, value in zip(self.rows('client1', kind), actual):
                row['maxTime'] = value
        report = self.analyze()['actions']['hotkeySetdown']
        self.assertEqual(report['nativeDurationTicks'], 88)
        self.assertIn('Double.intValue', report['durationConversion'])
        # An adjusted value can be anywhere inside the same native integer bucket;
        # this is the engine conversion, not a tolerance fitted to this recording.
        for kind in ('QUEUED', 'SERIALIZED'):
            self.rows('client1', kind)[0]['maxTime'] = 88.999
        self.assertTrue(self.analyze()['actions']['hotkeySetdown']['evidenceComplete'])
        for queued, started in ((87, 87), (89, 89), (88.01, 88.02),
                                (float('inf'), float('inf')), (float('nan'), float('nan'))):
            with self.subTest(queued=queued, started=started):
                self.logs = copy.deepcopy(original)
                self.rows('client1', 'QUEUED')[0]['maxTime'] = queued
                self.rows('client1', 'SERIALIZED')[0]['maxTime'] = started
                with self.assertRaises(ValueError):
                    self.analyze()

    def test_frozen_key_matches_real_input_and_release(self):
        path = self.root / 'selection.json'
        selection = json.loads(path.read_text())
        selection['options']['cart_hotkey_key'] = 100
        path.write_text(json.dumps(selection))
        with self.assertRaises(ValueError):
            self.analyze()
        for row in self.rows('client1', 'INPUT'):
            row.update(key=100, rebound=True)
        for row in self.rows('client1', 'RELEASED'):
            row['key'] = 100
        report = self.analyze()['actions']['hotkeySetdown']
        self.assertEqual(report['configuredKey'], 100)
        self.assertTrue(report['completeTap'])
        for key in (None, True, 0, 256, 100.5):
            with self.subTest(key=key):
                selection['options']['cart_hotkey_key'] = key
                path.write_text(json.dumps(selection))
                with self.assertRaises(ValueError):
                    self.analyze()

    def test_hotkey_option_requires_boolean_and_actions(self):
        selection_path = self.root / 'selection.json'
        selection = json.loads(selection_path.read_text())
        for options in (dict(cart_hotkey_setdown=1, cart_actions=True), dict(cart_hotkey_setdown=True, cart_actions=False)):
            selection['options'] = options
            selection_path.write_text(json.dumps(selection))
            with self.assertRaises(ValueError):
                self.analyze()


if __name__ == '__main__':
    unittest.main()
