"""Fail-closed receipts for native microwave Grab menu regressions."""
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
from queue_checks import adapters
from queue_checks.adapters import inventory_grab as grab


class InventoryGrabTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.selection = dict(suite='inventory-grab', cases=list(grab.CASES), kind='sp', mode='toolkit',
                              languages=['EN'], clients=1, mods=list(grab.MODS), options={})

    def evidence(self):
        cases = self.selection['cases']
        rows = [dict(event='setup', cases=cases, expected=len(cases), nativeDurations=True,
                     queueEnabled=self.selection['mode']=='toolkit')]
        raw = []
        for index, case in enumerate(cases):
            base = 100 + index * 10
            bag, one = case.startswith('bag-'), case.endswith('-one')
            original = [dict(id=base+n, amount=1, kind='Base.WaterBottle') for n in (1, 2)]
            prep = dict(case=case, bagId=base, bagType='Base.Bag_ALICEpack_Army', bottles=original,
                        x=1, y=2, z=0, index=1, sprite='appliances_cooking_01_28',
                        sourceType='microwave', nativeMicrowave=True)
            target = original[0 if one else 1]['id']
            receipt = dict(case=case, bagId=base, bagType=prep['bagType'], targetId=target,
                           sourceType='microwave', nativeMicrowave=True,
                           bottles=[dict(item, count=1, endpoint=('bag' if bag else 'root') if item['id']==target else 'microwave') for item in original])
            command = dict(targetId=target, selectedRows=1, rowKind='collapsed-group' if one else 'expanded-child',
                           destination='bag' if bag else 'root', menuDispatched=True, transferCount=1,
                           transferProgress=True, backpackWorn=True, queueEmptyBefore=True, adjacent=True,
                           capacityAvailable=True, nativeDurations=True, nativeDuration=-1 if self.selection['kind']=='mp' else 50, progressDuration=50, menuBuilds=2,
                           targetType='table', callbackType='function', callbackFile='ISInventoryPaneContextMenu.lua')
            rows.append(dict(event='case', id=case, status='passed', reason=None, command=command,
                             queueIdle=True, settleMilliseconds=6000, clientIdentityVerified=True, **copy.deepcopy(receipt)))
            raw += [('PREPARED', prep), ('VERIFIED', receipt)]
        rows.append(dict(event='complete', cases=cases, expected=len(cases), performed=len(cases), failed=0, skipped=0))
        return ([dict(row, suite='inventory-grab', actor='client1', kind=self.selection['kind'], mode=self.selection['mode']) for row in rows], raw)

    def verify(self, evidence=None, marker='[INVENTORY_GRAB_TEST] COMPLETE', server=True):
        rows, raw = evidence or self.evidence()
        client = '\n'.join('[QUEUE_CHECK] ' + json.dumps(row) for row in rows) + '\n' + marker
        authority = '\n'.join('[INVENTORY_GRAB_TEST] ' + name + ' ' + json.dumps(value) for name, value in raw)
        if self.selection['kind'] == 'mp':
            (self.root / 'server-launch.log').write_text(authority if server else '')
            if not server:
                client += '\n' + authority
        else:
            client += '\n' + authority
        (self.root / 'client1-launch.log').write_text(client)
        return grab.verify(self.root, self.selection, {})

    def test_registration_native_toolkit_sp_and_host(self):
        self.assertIs(adapters.get('inventory-grab'), grab)
        self.assertEqual([row['id'] for row in adapters.definitions()['inventory-grab']['cases']], grab.CASES)
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                grab.validate(self.selection)
                self.assertEqual(self.verify()['issues'], [])

    def test_subset_selection_and_rejections(self):
        for case in grab.CASES:
            grab.validate(dict(self.selection, cases=[case]))
        for changes in ({'cases': []}, {'cases': ['unknown']}, {'cases': ['root-one', 'root-grab']},
                        {'cases': ['root-grab', 'root-grab']}, {'clients': True}, {'clients': 2},
                        {'kind': 'invalid'}, {'mode': 'invalid'}, {'languages': ['RU']}, {'mods': []},
                        {'options': {'world_template': '/existing'}}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                grab.validate(dict(self.selection, **changes))

    def test_exact_untouched_bottle_endpoint_volume_and_identity(self):
        for field, value in [('id', 999), ('count', 2), ('endpoint', 'bag'), ('amount', .9), ('kind', 'Base.Apple')]:
            evidence = self.evidence()
            # Modify server and client together: matching claims cannot waive the exact expected effect.
            evidence[0][1]['bottles'][0][field] = value
            evidence[1][1][1]['bottles'][0][field] = value
            with self.subTest(field=field):
                self.assertTrue(self.verify(evidence)['issues'])
        evidence = self.evidence()
        evidence[0][1]['bottles'][1]['id'] = 999
        self.assertTrue(self.verify(evidence)['issues'])

    def test_dispatch_progress_empty_start_and_delayed_settle_are_required(self):
        for field in ('menuDispatched', 'transferProgress', 'backpackWorn', 'queueEmptyBefore',
                      'adjacent', 'capacityAvailable', 'nativeDurations'):
            evidence = self.evidence()
            evidence[0][1]['command'][field] = False
            self.assertTrue(self.verify(evidence)['issues'], field)
        for field, value in [('transferCount', 0), ('transferCount', 2), ('selectedRows', 2),
                             ('rowKind', 'collapsed-group'), ('nativeDuration', 0), ('targetType', 'userdata')]:
            evidence = self.evidence();evidence[0][1]['command'][field] = value
            self.assertTrue(self.verify(evidence)['issues'], field)
        for field, value in [('queueIdle', False), ('clientIdentityVerified', False), ('settleMilliseconds', 5999)]:
            evidence = self.evidence();evidence[0][1][field] = value
            self.assertTrue(self.verify(evidence)['issues'], field)

    def test_authority_cannot_be_client_only_or_reordered(self):
        self.selection['kind'] = 'mp'
        self.assertTrue(self.verify(server=False)['issues'])
        evidence = self.evidence();evidence[1].reverse()
        self.assertTrue(self.verify(evidence)['issues'])
        evidence = self.evidence();evidence[1].append(evidence[1][-1])
        self.assertTrue(self.verify(evidence)['issues'])
        evidence = self.evidence();evidence[0][1]['kind'] = 'sp'
        self.assertTrue(self.verify(evidence)['issues'])

    def test_missing_or_duplicate_completion_and_failure_are_rejected(self):
        for marker in ('', '[INVENTORY_GRAB_TEST] COMPLETE_PENDING',
                       '[INVENTORY_GRAB_TEST] COMPLETE\n[INVENTORY_GRAB_TEST] COMPLETE',
                       '[INVENTORY_GRAB_TEST] COMPLETE\n[QUEUE_TEST] FAIL native transfer'):
            self.assertTrue(self.verify(marker=marker)['issues'])
        self.assertFalse(grab.complete(self.selection, 'client2', '[INVENTORY_GRAB_TEST] COMPLETE'))

    def test_lua_receipt_resolves_replicated_identity_and_rejects_wrong_live_endpoint(self):
        lua = shutil.which('luajit') or shutil.which('lua')
        if not lua:
            self.skipTest('Lua interpreter unavailable')
        fixture = ROOT / 'tests/native_queue/inventory-grab/shared/QueueInventoryGrabFixture.lua'
        script = r"""
local Fixture=dofile(FIXTURE)
instanceof=function(item,kind)return item.class==kind end
local function container(kind)
 local value={items={},kind=kind}
 function value:getItems()
  return {size=function()return #self.items end,get=function(_,i)return self.items[i+1]end}
 end
 function value:getType()return self.kind end
 function value:getItemById(id)
  for _,item in ipairs(self.items)do
   if item:getID()==id then return item end
   if item.class=='InventoryContainer'then
    local nested=item:getItemContainer():getItemById(id);if nested then return nested end
   end
  end
 end
 return value
end
local function bottle(id,owner)
 return {class='InventoryItem',owner=owner,amount=1,id=id,
  getID=function(self)return self.id end,
  getContainer=function(self)return self.owner end,
  getFullType=function()return 'Base.WaterBottle'end,
  getFluidContainer=function(self)return {getAmount=function()return self.amount end}end}
end
local function run(case,fault)
 local root,source,bagContents=container('inventory'),container('microwave'),container('bag')
 local bag={class='InventoryContainer',getID=function()return 10 end,
  getFullType=function()return Fixture.bagType end,getContainer=function()return root end,
  getItemContainer=function()return bagContents end}
 root.items={bag}
 local player={getInventory=function()return root end,getClothingItem_Back=function()return bag end}
 local object={class='IsoStove',getContainer=function()return source end,isMicrowave=function()return true end}
 local selected=12;local destination=Fixture.spec(case).bag and bagContents or root
 local liveDestination=destination
 if fault=='endpoint'then liveDestination=destination==root and bagContents or root end
 local untouched=bottle(11,source);local stale=bottle(selected,source)
 local live=bottle(selected,liveDestination)
 source.items={untouched};table.insert(liveDestination.items,live)
 if fault=='duplicate'then table.insert(source.items,bottle(selected,source))end
 if fault=='volume'then live.amount=.5 end
 local state={player=player,case=case,object=object,bag=bag,bottles={untouched,stale},
  ids={case=case,bagId=10,bagType=Fixture.bagType,bottles={{id=11,amount=1,kind='Base.WaterBottle'},
   {id=selected,amount=1,kind='Base.WaterBottle'}}}}
 local ok,result=pcall(Fixture.receipt,state,selected)
 if fault then assert(not ok or result==nil,'receipt accepted wrong live '..fault..' in '..case);return end
 assert(ok,result)
 assert(result and state.verified,'same-ID replicated live item must produce a verified receipt')
 assert(stale~=live and stale:getContainer()==source and live:getContainer()==destination,
  'test must retain old source proxy separately from committed destination item')
 assert(#result.bottles==2 and result.bottles[1].id==11 and result.bottles[1].endpoint=='microwave')
 assert(result.bottles[2].id==selected and result.bottles[2].count==1 and result.bottles[2].amount==1)
 assert(result.bottles[2].endpoint==(destination==root and 'root'or 'bag'))
end
for _,case in ipairs({'root-grab','root-one','bag-grab','bag-one'})do
 run(case)
 for _,fault in ipairs({'endpoint','duplicate','volume'})do run(case,fault)end
end
""".replace('FIXTURE', json.dumps(str(fixture)), 1)
        result = subprocess.run([lua, '-e', script], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_native_lua_sources_parse_without_loading_game(self):
        lua = shutil.which('luajit') or shutil.which('lua')
        if not lua:
            self.skipTest('Lua interpreter unavailable')
        paths = sorted((ROOT / 'tests/native_queue/inventory-grab').rglob('*.lua'))
        self.assertEqual(len(paths), 3)
        script = ';'.join('assert(loadfile(' + json.dumps(str(path)) + '))' for path in paths)
        result = subprocess.run([lua, '-e', script], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
