"""Pre-launch wring recipes and failure observations, using the actual fixture Lua."""
import copy
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

from tests import test_queue_wring_clothing as fixtures

SHARED = Path(__file__).resolve().parent / 'native_queue/wring-clothing/shared'


class WringFixtureDiagnosticsTests(unittest.TestCase):
    def runtime(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute('package.loaded.QueueEnergyPlacement={}')
        fixture = lua.execute((SHARED / 'QueueWringClothing.lua').read_text())
        lua.globals().F = fixture
        lua.execute("package.loaded.QueueWringClothing=F")
        return lua, fixture

    def state(self, lua, result):
        row = result[0]
        state = lua.table_from(dict(ids=row['ids'], wearBaseline=True,
                                   unequipTransitions=row['client'].get('unequipTransitions', []),
                                   swapTransition=row['client'].get('swapTransition', False)), recursive=True)
        lua.globals().snapshot = lua.table_from(copy.deepcopy(row['client']), recursive=True)
        lua.execute('F.snapshot=function()return snapshot end')
        return state

    def test_shared_recipe_rejects_wrong_tail_or_missing_native_preparation(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().S = lua.execute((SHARED / 'QueueWringScenario.lua').read_text())
        lua.execute('''
for _,mode in ipairs({'native','toolkit'})do
 local commands=S.plan(mode)
 S.check(commands,mode)
 assert(commands[1].name=='front'and commands[1].type=='ISWringClothing')
 assert(commands[#commands].name=='tail'and commands[#commands].type=='ISWringClothing')
 commands[#commands].type='ISReadABook'
 assert(not pcall(S.check,commands,mode),'book tail hid the wring dependency boundary')
 local producer={};for _,kind in ipairs(S.producer(mode,'target'))do producer[#producer+1]={Type=kind}end
 S.checkProducer(producer,mode,'target')
 table.remove(producer,1)
 assert(not pcall(S.checkProducer,producer,mode,'target'),'missing carried preparation accepted')
end
assert(not pcall(S.plan,'unknown'))
''')

    def test_final_observer_preserves_selected_and_native_return_outcomes(self):
        lua, fixture = self.runtime()
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                for case in ('root', 'worn', 'world', 'worn-bag', 'worn-prepared', 'wear-swap'):
                    with self.subTest(kind=kind, mode=mode, case=case):
                        state = self.state(lua, fixtures.evidence(kind, mode, case))
                        receipt, issues, observed = fixture.verify(state)
                        self.assertIsNotNone(receipt)
                        self.assertEqual(0, len(issues))
        for mode in ('native', 'toolkit'):
            state = self.state(lua, fixtures.WringClothingRestorationProfileTests().sample(mode))
            receipt, issues, observed = fixture.verify(state)
            self.assertIsNotNone(receipt)
            self.assertEqual(0, len(issues))

    def test_final_observer_collects_independent_failures_without_repair(self):
        lua, fixture = self.runtime()
        result = fixtures.evidence('sp', 'toolkit', 'root')
        result[0]['ids']['nativeWearSetup'] = True
        item = result[0]['client']['items']['target']
        item['counts'].update(root=0, source=0)
        item.update(worn=True, wetness=90)
        result[0]['client']['items']['tail']['wetness'] = 90
        state = self.state(lua, result)
        state.wearBaseline = False
        receipt, issues, observed = fixture.verify(state)
        self.assertIsNone(receipt)
        failures = {(i['name'], i['field']) for _, i in issues.items()}
        self.assertEqual({('setup', 'wearBaseline'), ('target', 'counts.root'), ('target', 'counts.source'),
                          ('target', 'worn'), ('target', 'wetness'), ('tail', 'wetness')}, failures)
        self.assertEqual(0, observed['items']['target']['counts']['root'])
        self.assertEqual(90, observed['items']['target']['wetness'])

    def test_failure_capture_is_bounded_and_preserves_other_sections_on_error(self):
        lua, fixture = self.runtime()
        lua.globals().D = lua.execute((SHARED / 'QueueWringDiagnostics.lua').read_text())
        lua.execute('''
local root={};local current
local function item()return{getID=function()return 71 end,getFullType=function()return 'Base.Socks_Ankle'end,getContainer=function()return root end}end
local old=item();current=item();root.getItemById=function(_,id)assert(id==71);return current end
local body={Type='ISWringClothing',item=old,action={}}
local player={getInventory=function()return root end}
local queue={queue={},current=body}
for index=1,40 do queue.queue[index]={Type='ISWringClothing'}end
queue.queue[1]=body
local ids={case='worn-bag',items={target={id=71,type='Base.Socks_Ankle'}}}
F.preparedDiagnostic=function()error('unavailable prepared item')end
F.verify=function()return nil,{{name='target',field='wetness',actual=90,expected=10}},{marker='observed'}end
PZSurvivorToolkit={ActionQueueSettlement={operationState=function()error('diagnostics queried ledger')end},
 ActionQueueExecution={blockedReturns=function()error('diagnostics queried debts')end}}
local observations={case='worn-bag',point='drained',observedAt=123,ledger={optionalReturnState='blocked',optionalReturnDetail='source'},debts={{id=71,state='blocked'}}}
-- Calling native validity or changing a queue/item would destroy this evidence.
body.isValid=function()error('diagnostics called native admission')end
queue.onCompleted=function()error('diagnostics advanced the queue')end
local result=D.capture(player,ids,{},queue,body,queue.queue[40],observations)
assert(result.schema==1 and not result.sections.prepared.ok)
assert(result.sections.prepared.error:find('unavailable prepared item',1,true))
assert(result.sections.final.ok and not result.sections.final.value.ready)
assert(result.sections.final.value.issues[1].field=='wetness')
assert(result.sections.ledger.value.snapshot.optionalReturnDetail=='source')
assert(result.sections.ledger.value.point=='drained'and result.sections.ledger.value.observedAt==123)
assert(result.sections.debts.value.snapshot[1].state=='blocked')
assert(result.sections.body.value.rootOwned and not result.sections.body.value.canonicalSame)
assert(result.sections.body.value.itemRef~=result.sections.body.value.canonicalRef)
assert(result.sections.queue.value.count==40 and #result.sections.queue.value.items==32 and result.sections.queue.value.truncated)
assert(body.item==old and queue.current==body and #queue.queue==40)
-- An unavailable old snapshot stays unavailable; never invoke lazy getters.
local nextResult=D.capture(player,ids,{},queue,body)
assert(nextResult.sections.ledger.ok and not nextResult.sections.ledger.value.available)
assert(nextResult.sections.body.ok and nextResult.sections.debts.ok and not nextResult.sections.debts.value.available)
observations.case='other-case'
local stale=D.capture(player,ids,{},queue,body,nil,observations)
assert(not stale.sections.ledger.value.available)
local server=D.capture(player,ids,{})
assert(server.sections.queue.ok and server.sections.queue.value.available==false)
F.preparedDiagnostic=function()return nil end
local missing=D.capture(player,ids,{})
assert(missing.sections.prepared.ok and missing.sections.prepared.value==false)
''')


if __name__ == '__main__':
    unittest.main()
