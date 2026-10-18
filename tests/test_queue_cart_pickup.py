"""Host cart acceptance requires stable exact ownership on both peers."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import equipment


class CartPickupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.selection = dict(suite='equipment', cases=['cart-pickup'], kind='mp', mode='native', clients=1,
                              languages=['EN'], mods=['PZSurvivorToolkit', 'PZToolkitJavaPatches', 'ZombieBuddy',
                                                     'SaucedCarts', 'saucedwheelbarrow'], options={'mp_host': True})

    def logs(self):
        client_rows, server_rows = [], []
        for index, kind in enumerate(equipment.CART_TYPES, 1):
            for phase in equipment.CART_PHASES:
                ground = phase == 'drop'
                row = dict(index=index, type=kind, phase=phase, id=index * 10, cargoID=index * 10 + 1,
                           cargoWeight=.01, cargoPreserved=True, inventoryCount=0 if ground else 1,
                           worldCount=1 if ground else 0, worldAttached=ground, aiming=False,
                           primaryID=-1 if ground else index * 10, secondaryID=-1 if ground else index * 10,
                           holdMs=500)
                server_rows.append(dict(row, actor='server'))
                client = dict(row, actor='client1', queueEmpty=True, idleUpdates=6,
                              nativeDurations=True, actionStarted=not ground, actionProgress=not ground)
                if not ground:
                    client.update(actionType='ToolkitWoodCartPickup' if index == 2 else 'ISCartPickupAction',
                                  actionDuration=88 if index == 2 else 50)
                client_rows.append(client)
        context = dict(suite='equipment', kind='mp', mode=self.selection['mode'], actor='client1')
        rows = [dict(context, event='setup', cases=['cart-pickup'], expected=1,
                     nativeDurations=True, queueEnabled=self.selection['mode'] == 'toolkit'),
                dict(context, event='case', id='cart-pickup', status='passed', outcome=dict(
                     cartPickup=True, inventoryPreserved=True, equipmentMatches=True, cargoPreserved=True,
                     nativeDurations=True, postprocessingVerified=True, authoritative=True,
                     repeatedPickup=True, nativeDrop=True, cartTypes=equipment.CART_TYPES, phases=9,
                     receipts=client_rows)),
                dict(context, event='complete', cases=['cart-pickup'], expected=1, performed=1, skipped=0, failed=0)]
        def markers(actor, receipts):
            return ['[CART_PICKUP] RECEIPT ' + json.dumps(row) for row in receipts] + [
                '[CART_PICKUP] CLEANED ' + json.dumps(dict(actor=actor, index=index, id=index * 10))
                for index in range(1, 4)]
        client = '\n'.join(markers('client1', client_rows) + ['[QUEUE_CHECK] ' + json.dumps(row) for row in rows]
                           + ['[EQUIPMENT_TEST] RECEIPT case=cart-pickup', '[EQUIPMENT_TEST] COMPLETE'])
        server = '\n'.join(['[EQUIPMENT_TEST] SERVER_READY', '[EQUIPMENT_TEST] TRANSFER_PROBE active=true']
                           + markers('server', server_rows))
        return client, server

    def verify(self, client, server):
        (self.root / 'client1-launch.log').write_text(client)
        (self.root / 'server-launch.log').write_text(server)
        return equipment.verify(self.root, self.selection, {})['issues']

    def test_host_selection_and_catalog(self):
        equipment.validate(self.selection)
        case = next(row for row in equipment.definitions()['equipment']['cases'] if row['id'] == 'cart-pickup')
        self.assertEqual(case['kinds'], ['mp'])
        for change in ({'kind': 'sp'}, {'clients': 2}, {'options': {}}, {'options': {'mp_host': 1}},
                       {'cases': ['hands-chain', 'cart-pickup']}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                equipment.validate(dict(self.selection, **change))
        for mod in self.selection['mods']:
            changed = copy.deepcopy(self.selection)
            changed['mods'].remove(mod)
            with self.subTest(mod=mod), self.assertRaises(ValueError):
                equipment.validate(changed)

    def test_valid_native_and_toolkit_receipts(self):
        for mode in ('native', 'toolkit'):
            self.selection['mode'] = mode
            self.assertEqual(self.verify(*self.logs()), [])

    def test_client_success_cannot_hide_server_drop_or_cargo_loss(self):
        client, server = self.logs()
        for old, new in (('"secondaryID": 10', '"secondaryID": -1'),
                         ('"cargoID": 11', '"cargoID": 12'),
                         ('"worldCount": 0', '"worldCount": 1'),
                         ('"cargoPreserved": true', '"cargoPreserved": false'),
                         ('"holdMs": 500', '"holdMs": 499'),
                         ('"inventoryCount": 1', '"inventoryCount": true')):
            with self.subTest(old=old):
                self.assertTrue(self.verify(client, server.replace(old, new, 1)))

    def test_missing_duplicate_unordered_and_unclean_receipts_fail(self):
        client, server = self.logs()
        lines = server.splitlines()
        for changed in ('\n'.join(lines[:2] + lines[3:]), server + '\n' + lines[2],
                        '\n'.join(lines[:2] + [lines[3], lines[2]] + lines[4:]),
                        server.replace('[CART_PICKUP] CLEANED ', '[IGNORED] CLEANED ', 1),
                        server + '\n[QUEUE_TEST] FAIL cart'):
            self.assertTrue(self.verify(client, changed))
        for changed in (client.replace('"actionProgress": true', '"actionProgress": false', 1),
                        client.replace('"idleUpdates": 6', '"idleUpdates": 2', 1),
                        client.replace('"actionDuration": 88', '"actionDuration": 50', 1),
                        client.replace('"queueEmpty": true', '"queueEmpty": false', 1),
                        client + '\n[EQUIPMENT_TEST] COMPLETE'):
            self.assertTrue(self.verify(changed, server))

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_shared_equipment_selection_accepts_only_standalone_mp_cart_case(self):
        script = r'''
local path=arg[1]..'/tests/native_queue/equipment/shared/QueueEquipmentSelection.lua'
local config={kind='mp',clients=1,mode='native',languages={'EN'},cases={'cart-pickup'}}
package.loaded.QueueTestSelection=config
for _,mode in ipairs({'native','toolkit'}) do
 config.mode=mode
 local selected=dofile(path)
 assert(#selected.cases==1 and selected.cases[1]=='cart-pickup' and selected.kind=='mp' and selected.mode==mode)
end
config.kind='sp';assert(not pcall(dofile,path));config.kind='mp'
for _,cases in ipairs({{'cart-pickup','hands-chain'},{'cart-pickup','cart-pickup'},{'hands-chain','cart-pickup'}}) do
 config.cases=cases;assert(not pcall(dofile,path))
end
config.cases={'waiting-cancel','hands-chain'}
local selected=dofile(path)
assert(selected.cases[1]=='hands-chain' and selected.cases[2]=='waiting-cancel')
'''
        target = self.root / 'selection-check.lua'
        target.write_text(script)
        result = subprocess.run(['luajit', str(target), str(ROOT)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_shared_ownership_checks_exact_cart_cargo_and_world(self):
        script = r'''
package.path=arg[1]..'/tests/native_queue/equipment/shared/?.lua;'..arg[1]..'/tests/native_queue/health/shared/?.lua;'..package.path
local Cart=require 'QueueCartPickup'
ISCartPickupAction={getDuration=function()return 50 end}
ToolkitWoodCartPickup={getDuration=function()return 88 end}
assert(Cart.pickup({Type='ISCartPickupAction',getDuration=ISCartPickupAction.getDuration}))
assert(Cart.pickup({Type='ToolkitWoodCartPickup',getDuration=ToolkitWoodCartPickup.getDuration}))
assert(not Cart.pickup({Type='ISWalkToTimedActionF'}))
assert(not pcall(Cart.pickup,{Type='ToolkitWoodCartPickup',getDuration=function()return 50 end}))
local function list(values)
 return {size=function()return #values end,get=function(_,i)return values[i+1] end}
end
local child={getID=function()return 11 end,getFullType=function()return 'Base.Nails' end,getActualWeight=function()return .01 end}
local cargo={child};local contents={};local worlds={}
local world,cart
cart={getID=function()return 10 end,getFullType=function()return Cart.types[1] end,
 getWorldItem=function()return world end,getInventory=function()return {getItems=function()return list(cargo)end}end}
local primary,secondary
local player={getInventory=function()return {getItems=function()return list(contents)end}end,
 getX=function()return .5 end,getY=function()return .5 end,getZ=function()return 0 end,isAiming=function()return false end,
 getPrimaryHandItem=function()return primary end,getSecondaryHandItem=function()return secondary end}
local square={getWorldObjects=function()return list(worlds)end}
getCell=function()return {getGridSquare=function(_,x,y,z)if x==0 and y==0 and z==0 then return square end end}end
local spec={id=10,cargo=11,type=Cart.types[1],weight=.01,x=0,y=0,z=0,index=1}
world={getItem=function()return cart end};worlds={world}
assert(Cart.matches(Cart.inspect(player,spec),true))
assert(not Cart.matches(Cart.inspect(player,spec),false))
world=nil;worlds={};contents={cart};primary=cart;secondary=cart
assert(Cart.matches(Cart.inspect(player,spec),false))
secondary=nil;assert(not Cart.matches(Cart.inspect(player,spec),false));secondary=cart
cargo={};assert(not Cart.matches(Cart.inspect(player,spec),false));cargo={child}
contents={cart,cart};assert(not Cart.matches(Cart.inspect(player,spec),false));contents={cart}
world={getItem=function()return cart end};worlds={world}
assert(not Cart.matches(Cart.inspect(player,spec),false))
print('PASS exact cart pickup ownership checks')
'''
        target = self.root / 'check.lua'
        target.write_text(script)
        result = subprocess.run(['luajit', str(target), str(ROOT)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
