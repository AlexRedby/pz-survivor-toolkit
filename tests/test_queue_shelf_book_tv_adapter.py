"""Strict log-contract checks for the shelf-book/TV live fixture."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import shelf_book_tv as adapter


STAMP = '2026-10-20 12:00:00 '
MARK = '[SHELF_TV] '


class ShelfBookTVAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def selection(self, kind='sp', mode='toolkit', case='demote-and-control'):
        return dict(suite='shelf-book-tv', cases=[case], kind=kind, mode=mode,
                    clients=1, languages=['EN'], mods=list(adapter.MODS),
                    options={'mp_host': True} if kind == 'mp' else {})

    def client_log(self, mode='toolkit', case='demote-and-control'):
        lines = [
            'PREPARED shelfId=11 bookId=22 tv=10,20,0 tapeId=33 mediaIndex=44 mediaType=1 power=electric daylight=true',
            'PROGRESS authority=server pagesBefore=16 pagesCommitted=17',
            'READ started=true pagesBefore=16 pagesCommitted=17',
            'COMMANDS power=ISRadioAction insert=ISDeviceMediaAction play=ISRadioAction',
        ]
        lines += (['PROMOTED current=ISReadABook target=ISRadioAction after=true accepted=true'] if mode == 'toolkit' else
                  ['CONTROL queueOff=true naturalReadBeforeTV=true', 'NATURAL_ORDER readerFinishedBeforeTV=true'])
        lines += [
            'POWER_EFFECT command=ToggleOnOff turnedOn=true',
            'INSERT_EFFECT command=ISDeviceMediaAction exactTape=true mediaIndex=44 mediaType=1',
            'PLAY_EFFECT command=TogglePlayMedia mediaPlaying=true',
        ]
        if mode == 'toolkit':
            lines.append('RESUMED sameAction=false sameBook=true sameOperation=true pagesBefore=17 pagesAfter=18')
        lines += [
            'ACTIONS powerStarted=true powered=true insertStarted=true exactTape=true playStarted=true mediaMatched=true',
            'RETURN sameBook=true exactCount=1',
            'MEDIA tapeDebited=true exactTape=true mediaIndex=44 mediaType=1 title=Carzone playing=true',
            'COMPLETE case=demote-and-control',
        ]
        if case == 'worn-bag':
            lines.insert(1, 'BAG_PREPARED bagId=55 location=Back tapeId=33 worn=true root=true tapeInBag=true')
            lines.insert(lines.index('COMMANDS power=ISRadioAction insert=ISDeviceMediaAction play=ISRadioAction') + 1,
                         'PICKUP_QUEUED type=ISInventoryTransferAction sourceBag=55 tapeId=33 destination=main grouped='
                         + str(mode == 'toolkit').lower() + ' menu=true nativeDurations=true')
            lines.insert(lines.index('POWER_EFFECT command=ToggleOnOff turnedOn=true') + 1,
                         'PICKUP_EFFECT sourceBag=55 tapeId=33 exactTape=true root=true')
            lines.insert(lines.index('RETURN sameBook=true exactCount=1'),
                         'BAG_AUTHORITY bagId=55 location=Back worn=true root=true sameContainer=true empty=true tapeRemoved=true actor=client1')
            lines[-1] = 'COMPLETE case=worn-bag'
        return '\n'.join(STAMP + MARK + line for line in lines) + '\n'

    def server_log(self, case='demote-and-control'):
        lines = [
            'PREPARED shelfId=11 bookId=22 tv=10,20,0 tapeId=33 mediaIndex=44 mediaType=1 power=electric daylight=true',
            'AUTH_PROGRESS pagesBefore=16 pagesCommitted=17 actor=client1',
            'AUTHORITY pagesComplete=true bookReturned=true exactBookCount=1 tapeRemoved=true mediaIndex=44 mediaType=1 tvMedia=Carzone playing=true actor=client1',
        ]
        if case == 'worn-bag':
            lines.insert(1, 'BAG_PREPARED bagId=55 location=Back tapeId=33 worn=true root=true tapeInBag=true')
            lines.append('BAG_AUTHORITY bagId=55 location=Back worn=true root=true sameContainer=true empty=true tapeRemoved=true actor=client1')
        return '\n'.join(STAMP + MARK + line for line in lines) + '\n'

    def verify(self, kind='sp', mode='toolkit', client=None, server=None, case='demote-and-control'):
        (self.root / 'client1-launch.log').write_text(self.client_log(mode, case) if client is None else client)
        if kind == 'mp':
            (self.root / 'server-launch.log').write_text(self.server_log(case) if server is None else server)
        return adapter.verify(self.root, self.selection(kind, mode, case), {})

    def test_timestamped_success_for_sp_and_host_native_and_toolkit(self):
        for case in adapter.CASES:
            for kind in ('sp', 'mp'):
                for mode in ('native', 'toolkit'):
                    with self.subTest(case=case, kind=kind, mode=mode):
                        result = self.verify(kind, mode, case=case)
                        self.assertEqual(result['issues'], [])
                        self.assertEqual(result['outcomes'][0]['case'], case)

    def test_case_selection_requires_one_known_case(self):
        self.assertEqual([case['id'] for case in adapter.definitions()['shelf-book-tv']['cases']], list(adapter.CASES))
        for case in adapter.CASES:
            adapter.validate(self.selection(case=case))
        for cases in ([], ['unknown'], list(adapter.CASES)):
            with self.subTest(cases=cases), self.assertRaises(ValueError):
                adapter.validate(dict(self.selection(), cases=cases))

    def test_worn_bag_requires_real_grouped_pickup_and_exact_identity(self):
        client = self.client_log(case='worn-bag')
        for old, new in (
                ('sourceBag=55 tapeId=33', 'sourceBag=56 tapeId=33'),
                ('sourceBag=55 tapeId=33 exactTape', 'sourceBag=55 tapeId=34 exactTape'),
                ('grouped=true', 'grouped=false'),
                ('menu=true nativeDurations=true', 'menu=false nativeDurations=true'),
                ('bagId=55 location=Back worn=true', 'bagId=55 location=Belt worn=true'),
                ('sameContainer=true empty=true', 'sameContainer=true empty=false')):
            with self.subTest(old=old):
                self.assertTrue(self.verify(client=client.replace(old, new, 1), case='worn-bag')['issues'])
        self.assertFalse(adapter.complete(self.selection(), 'client1', client))
        self.assertTrue(adapter.complete(self.selection(case='worn-bag'), 'client1', client))

    def test_worn_bag_requires_unique_matching_server_preparation_and_final_receipts(self):
        server = self.server_log('worn-bag')
        for changed in (
                server.replace(MARK + 'BAG_AUTHORITY', MARK + 'OMITTED_AUTHORITY'),
                server.replace('bagId=55 location=Back tapeId=33', 'bagId=55 location=Back tapeId=34'),
                server.replace('bagId=55 location=Back worn=true', 'bagId=56 location=Back worn=true'),
                server.replace('bookId=22', 'bookId=23'),
                server + STAMP + MARK + 'BAG_AUTHORITY bagId=55 location=Back worn=true root=true sameContainer=true empty=true tapeRemoved=true actor=client1\n'):
            with self.subTest(server=changed):
                self.assertTrue(self.verify('mp', server=changed, case='worn-bag')['issues'])

    def test_worn_bag_pickup_must_precede_insertion(self):
        client = self.client_log(case='worn-bag')
        pickup = STAMP + MARK + 'PICKUP_EFFECT sourceBag=55 tapeId=33 exactTape=true root=true\n'
        client = client.replace(pickup, '').replace(STAMP + MARK + 'PLAY_EFFECT', pickup + STAMP + MARK + 'PLAY_EFFECT')
        self.assertTrue(any('out of order' in issue for issue in self.verify(client=client, case='worn-bag')['issues']))

    def test_worn_bag_receipt_checks_actual_worn_identity_and_recursive_debit(self):
        lua = shutil.which('luajit') or shutil.which('lua')
        if not lua:
            self.skipTest('Lua runtime unavailable')
        script = r'''
local Fixture=assert(loadfile(arg[1]))()
local function action(duration)
 return {maxTime=duration,getDuration=function()return duration end}
end
local insert,power,play=action(30),action(30),action(30)
local durations=Fixture.captureDurations({maxTime=-1},insert,power,play,true)
assert(durations.pickup==-1 and durations.insert==30)
durations=Fixture.captureDurations({maxTime=72},insert,power,play,false)
assert(durations.pickup==72)
local changed=action(90)
assert(Fixture.captureDurations({maxTime=-1},changed,power,play,true).insert==90)
assert(not pcall(Fixture.captureDurations,{maxTime=-1},insert,power,play,false))
assert(not pcall(Fixture.captureDurations,{maxTime=72},insert,power,play,true))
insert.maxTime=1
assert(not pcall(Fixture.captureDurations,{maxTime=-1},insert,power,play,true))
insert.maxTime=30;insert.action={}
assert(not pcall(Fixture.captureDurations,{maxTime=-1},insert,power,play,true))
function instanceof(item,kind) return kind=='InventoryContainer' and item.container~=nil end
local function container(items)
 local value={items=items or {}}
 function value:getItems()
  local values=self.items
  return {size=function()return #values end,get=function(_,index)return values[index+1]end}
 end
 function value:getItemById(id)
  for _,item in ipairs(self.items)do if item:getID()==id then return item end end
 end
 return value
end
local root=container()
local bag={container=container()}
function bag:getID()return 55 end
function bag:getContainer()return root end
function bag:getItemContainer()return self.container end
function bag:canBeEquipped()return 'Back' end
root.items={bag}
local worn=bag
local player={getInventory=function()return root end,getWornItem=function(_,location)assert(location=='Back');return worn end}
local state={bag=bag,bagSource=bag.container,player=player,ids={bag=55,bagLocation='Back',tape=33}}
assert(Fixture.bagReceipt(state)=='bagId=55 location=Back worn=true root=true sameContainer=true empty=true tapeRemoved=true')
worn=nil;assert(not pcall(Fixture.bagReceipt,state));worn=bag
root.items={bag,bag};assert(not pcall(Fixture.bagReceipt,state));root.items={bag}
local other={container=container({{getID=function()return 33 end}}),getID=function()return 66 end}
function other:getItemContainer()return self.container end
root.items={bag,other};assert(not pcall(Fixture.bagReceipt,state));root.items={bag}
state.bagSource=container();assert(not pcall(Fixture.bagReceipt,state))
'''
        checked = subprocess.run([lua, '-', str(ROOT / 'tests/native_queue/shelf-book-tv/shared/QueueShelfBookTV.lua')],
                                 input=script, capture_output=True, text=True)
        self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)

    def test_pickup_accepts_only_exact_native_host_replica_and_preserves_sp_identity(self):
        lua = shutil.which('luajit') or shutil.which('lua')
        if not lua:
            self.skipTest('Lua runtime unavailable')
        script = r'''
local Fixture=assert(loadfile(arg[1]))()
local client=true
function isClient()return client end
function instanceof(item,kind)return kind=='InventoryContainer' and item.children~=nil end
local function container()
 local value={items={}}
 function value:getItems()
  return {size=function()return #self.items end,get=function(_,index)return self.items[index+1]end}
 end
 function value:getItemById(id)
  for _,item in ipairs(self.items)do
   if item:getID()==id then return item end
   if item.children then local found=item.children:getItemById(id);if found then return found end end
  end
 end
 return value
end
local root,bagSource=container(),container()
local bag={children=bagSource,getID=function()return 55 end,getItemContainer=function(self)return self.children end}
local function tape(owner)
 return {owner=owner,id=33,index=44,mediaType=1,fullType='Base.VHS_Retail',
  getContainer=function(self)return self.owner end,getID=function(self)return self.id end,
  getFullType=function(self)return self.fullType end,isRecordedMedia=function()return true end,
  getRecordedMediaIndex=function(self)return self.index end,getMediaType=function(self)return self.mediaType end}
end
local old=tape(bagSource)
root.items={bag};bagSource.items={old}
local state={player={getInventory=function()return root end},tape=old,bagSource=bagSource,
 ids={tape=33,mediaIndex=44,mediaType=1}}
local insert={secondaryItem=old}
assert(root:getItemById(33)==old and not Fixture.pickupArrived(state,insert),'recursive root lookup is not pickup')
-- Native Remove packet nulls the old owner; Add creates a new same-ID item and
-- ActionManager rebinds the direct insertion field, leaving fixture refs alone.
old.owner=nil;bagSource.items={}
local replica=tape(root);root.items={bag,replica};insert.secondaryItem=replica
assert(Fixture.pickupArrived(state,insert) and state.pickedTape==replica and state.tape==old)
replica.id=34;assert(not Fixture.pickupArrived(state,insert));replica.id=33
replica.index=45;assert(not Fixture.pickupArrived(state,insert));replica.index=44
replica.mediaType=2;assert(not Fixture.pickupArrived(state,insert));replica.mediaType=1
replica.fullType='Base.VHS_Home';assert(not Fixture.pickupArrived(state,insert));replica.fullType='Base.VHS_Retail'
replica.owner=bagSource;assert(not Fixture.pickupArrived(state,insert));replica.owner=root
insert.secondaryItem=old;assert(not Fixture.pickupArrived(state,insert));insert.secondaryItem=replica
root.items={bag,replica,replica};assert(not pcall(Fixture.pickupArrived,state,insert));root.items={bag,replica}
bagSource.items={old};assert(not Fixture.pickupArrived(state,insert));bagSource.items={}
client=false;assert(not Fixture.pickupArrived(state,insert),'SP must retain its original object')
old.owner=root;root.items={bag,old};insert.secondaryItem=old
assert(Fixture.pickupArrived(state,insert) and state.pickedTape==old and state.tape==old)
'''
        checked = subprocess.run([lua, '-', str(ROOT / 'tests/native_queue/shelf-book-tv/shared/QueueShelfBookTV.lua')],
                                 input=script, capture_output=True, text=True)
        self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
        client = self.client_log(case='worn-bag').replace('exactTape=true root=true\n',
                                                        'exactTape=true root=true replicaChanged=true\n')
        self.assertEqual(self.verify('mp', client=client, case='worn-bag')['issues'], [])

    def test_stage_registers_fixture_failure_marker(self):
        cache = self.root / 'cache'
        runtime = {'roles': {'client1': {'cache': str(cache)}}}
        adapter.stage(ROOT, self.root / 'output', self.root / 'game', self.root / 'jdk',
                      self.selection(), {}, runtime)
        self.assertIn('[QUEUE_TEST] FAIL shelf-book-tv', runtime['fixture']['failure_markers'])

    def test_rejects_missing_duplicate_and_out_of_order_markers(self):
        client = self.client_log().replace(MARK + 'PLAY_EFFECT', MARK + 'OMITTED_EFFECT')
        self.assertTrue(self.verify(client=client)['issues'])
        client = self.client_log() + STAMP + MARK + 'COMPLETE case=demote-and-control\n'
        self.assertTrue(self.verify(client=client)['issues'])
        client = self.client_log()
        client = client.replace(MARK + 'POWER_EFFECT', MARK + 'HOLD_POWER', 1)
        client = client.replace(MARK + 'PLAY_EFFECT', MARK + 'POWER_EFFECT', 1)
        client = client.replace(MARK + 'HOLD_POWER', MARK + 'PLAY_EFFECT', 1)
        self.assertTrue(any('out of order' in issue for issue in self.verify(client=client)['issues']))

    def test_rejects_non_increasing_or_mismatched_page_receipts(self):
        client = self.client_log().replace('pagesCommitted=17', 'pagesCommitted=16', 1)
        self.assertTrue(any('committed increase' in issue for issue in self.verify(client=client)['issues']))
        client = self.client_log().replace('READ started=true pagesBefore=16 pagesCommitted=17',
                                           'READ started=true pagesBefore=16 pagesCommitted=18')
        self.assertTrue(any('does not match' in issue for issue in self.verify(client=client)['issues']))
        client = self.client_log().replace('pagesBefore=17 pagesAfter=18', 'pagesBefore=16 pagesAfter=18')
        self.assertTrue(any('previously committed' in issue for issue in self.verify(client=client)['issues']))

    def test_rejects_server_progress_and_media_identity_mismatches(self):
        server = self.server_log().replace('pagesCommitted=17', 'pagesCommitted=18')
        self.assertTrue(any('server-committed page progress' in issue for issue in self.verify('mp', server=server)['issues']))
        server = self.server_log().replace('mediaIndex=44 mediaType=1 tvMedia=Carzone',
                                           'mediaIndex=45 mediaType=1 tvMedia=Carzone')
        self.assertTrue(any('differs from exact prepared tape' in issue for issue in self.verify('mp', server=server)['issues']))
        client = self.client_log().replace('mediaIndex=44 mediaType=1 title=Carzone',
                                           'mediaIndex=45 mediaType=1 title=Carzone')
        self.assertTrue(any('differs from the exact prepared tape' in issue for issue in self.verify(client=client)['issues']))


if __name__ == '__main__':
    unittest.main()
