"""Full native replacement receipts retain controls and reject fabricated depletion."""
import copy
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import food
from queue_checks import scenarios
import test_queue_food as fixtures


def family_evidence(case, index, mode):
    enabled = mode == 'toolkit'
    cancelled = enabled and case == food.FULL_CANCEL_CASE
    quarter = case == food.FULL_QUARTER_CASE
    base = 100 + index * 10
    pan = dict(id=base + 4, weight=1.3, normal=True, fluid=False, root=True)
    prep = dict(case=case, bagId=base, bagType='Base.Bag_ALICEpack_Army', bagCount=1,
                foodId=base + 1, foodType='Base.PanFriedVegetables2', baseHunger=-.1, remaining=-.1,
                source='root', foodCount=1, foodTypeCount=1, deleted=False,
                anchorId=base + 2, anchorType='Base.WaterBottle', anchorAmount=1.0,
                anchorCount=1, anchorThirstChange=-.5, hunger=.8, thirst=.8, foodTimer=0, foodLevel=0,
                tailId=base + 3, tailType='Base.WaterBottle', tailAmount=1.0, tailThirstChange=-.5, tailCount=1,
                fixturePanId=base + 4, pans=[pan], panCount=1, foodWeight=1.3,
                sourceFood=True, sourcePlain=True, consumptionReplacementType='Base.RoastingPan')
    receipt = {key: copy.deepcopy(value) for key, value in prep.items() if key not in ('foodTimer', 'foodLevel')}
    receipt.update(remaining=-.1 if cancelled else 0, source='root' if cancelled else 'deleted',
                   foodCount=int(cancelled), foodTypeCount=int(cancelled), deleted=not cancelled,
                   anchorAmount=.5, anchorThirstChange=-.25, tailAmount=.5, tailThirstChange=-.25,
                   hunger=.8 if cancelled else .7, thirst=.3, foodWeight=1.3 if cancelled else 0,
                   sourceFood=cancelled, sourcePlain=cancelled)
    if not cancelled:
        receipt['pans'].append(dict(pan, id=base + 5))
        receipt['panCount'] += 1
    portions = [.25, 1, .5] if quarter else [1, .5]
    commands = []
    for n, portion in enumerate(portions):
        tail = n == len(portions) - 1
        commands.append(dict(id=base + 3 if tail else base + 1, portion=portion,
                             baseHunger=0 if tail else -.1, dispatchRemaining=0 if tail else -.1,
                             dispatchSource='root', menuDispatched=not tail, nativeDuration=460 if tail else 232,
                             progress=not (cancelled and not tail), cancelled=cancelled and not tail, pickupObserved=False))
    order = [1, 2, 3] if quarter else [2] if cancelled else [2, 1] if enabled and case == food.FULL_MOVE_CASE else [1, 2]
    labels = ['anchor'] + [('quarter', 'full', 'tail')[n - 1] if quarter else ('full', 'tail')[n - 1] for n in order]
    edit = dict(emptyStart=True, anchorRunning=True, anchorProgress=True, anchorDuration=460,
                contractsVerified=enabled, reordered=enabled and case == food.FULL_MOVE_CASE, waitingCancel=cancelled,
                moveRejected=enabled and quarter, cancelRejected=False, manualPickup=False,
                untouchedBefore=True, nativeDurationsUnchanged=True, order=order, startOrder=labels,
                completionOrder=list(labels), denialReason='edit_resource_amount' if enabled and quarter else 'not-requested')
    row = dict(event='case', id=case, status='passed', commands=commands, editEvidence=edit,
               client=copy.deepcopy(receipt), **copy.deepcopy(receipt))
    return row, [('PREPARED', prep), ('VERIFIED', receipt)]


class FullReplacementTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.FoodAdapterTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)

    def evidence(self, case=food.FULL_MOVE_CASE, mode='toolkit', kind='sp'):
        self.fixture.selection.update(cases=[case], mode=mode, kind=kind)
        return self.fixture.evidence()

    def test_three_cases_have_matched_sp_host_and_queue_off_controls(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                for case in food.FULL_CASES:
                    with self.subTest(case=case, kind=kind, mode=mode):
                        evidence = self.evidence(case, mode, kind)
                        result = self.fixture.verify(evidence)
                        self.assertEqual([], result['issues'])
                        self.assertIs(result['outcomes'][0]['outcome']['serverAuthorityVerified'], kind == 'mp')
                        self.assertIs(result['outcomes'][0]['outcome']['pendingEditsVerified'], mode == 'toolkit')

    def test_exact_original_new_pan_and_retained_pan_provenance_are_required(self):
        faults = [('foodCount', 1), ('foodTypeCount', 1), ('deleted', False), ('source', 'root'),
                  ('remaining', -.1), ('foodWeight', 1.3), ('sourceFood', True), ('sourcePlain', True),
                  ('panCount', 1), ('fixturePanId', 999), ('foodId', 999), ('consumptionReplacementType', 'Base.Bowl')]
        for field, value in faults:
            rows, raw = self.evidence()
            for endpoint in (rows[1], rows[1]['client'], raw[1][1]): endpoint[field] = value
            with self.subTest(field=field): self.assertTrue(self.fixture.verify((rows, raw))['issues'])
        for fault in ('lost-old', 'duplicate', 'source-id', 'nested', 'fluid', 'wrong-class', 'weight', 'extra-output', 'missing-output'):
            rows, raw = self.evidence()
            for endpoint in (rows[1], rows[1]['client'], raw[1][1]):
                pans = endpoint['pans']
                if fault == 'lost-old': pans[0]['id'] = 999
                elif fault == 'duplicate': pans[1]['id'] = pans[0]['id']
                elif fault == 'source-id': pans[1]['id'] = endpoint['foodId']
                elif fault == 'nested': pans[1]['root'] = False
                elif fault == 'fluid': pans[1]['fluid'] = True
                elif fault == 'wrong-class': pans[1]['normal'] = False
                elif fault == 'weight': pans[1]['weight'] = 2
                elif fault == 'extra-output': pans.append(dict(pans[-1], id=999));endpoint['panCount'] += 1
                else: pans.pop();endpoint['panCount'] -= 1
            with self.subTest(fault=fault): self.assertTrue(self.fixture.verify((rows, raw))['issues'])

    def test_cancel_requires_original_untouched_and_no_new_output_while_tail_completes(self):
        for field, value in [('remaining', -.075), ('deleted', True), ('foodWeight', 1), ('sourcePlain', False),
                             ('panCount', 2), ('tailAmount', 1), ('tailCount', 0), ('hunger', .7)]:
            rows, raw = self.evidence(food.FULL_CANCEL_CASE)
            for endpoint in (rows[1], rows[1]['client'], raw[1][1]): endpoint[field] = value
            with self.subTest(field=field): self.assertTrue(self.fixture.verify((rows, raw))['issues'])
        rows, raw = self.evidence(food.FULL_CANCEL_CASE)
        rows[1]['commands'][0].update(progress=True, cancelled=False)
        self.assertTrue(self.fixture.verify((rows, raw))['issues'])

    def test_all_native_commands_fields_types_portions_durations_and_both_orders_required(self):
        for case in food.FULL_CASES:
            for field in food.COMMAND_KEYS:
                rows, raw = self.evidence(case);del rows[1]['commands'][0][field]
                with self.subTest(case=case, missing=field): self.assertTrue(self.fixture.verify((rows, raw))['issues'])
            for field, value in [('portion', .99), ('nativeDuration', 464), ('progress', 1), ('menuDispatched', 1), ('dispatchRemaining', -.075)]:
                rows, raw = self.evidence(case);rows[1]['commands'][0][field] = value
                with self.subTest(case=case, field=field): self.assertTrue(self.fixture.verify((rows, raw))['issues'])
            for field in ('startOrder', 'completionOrder', 'order'):
                rows, raw = self.evidence(case);rows[1]['editEvidence'][field] = list(reversed(rows[1]['editEvidence'][field])) + [999]
                with self.subTest(case=case, field=field): self.assertTrue(self.fixture.verify((rows, raw))['issues'])
            rows, raw = self.evidence(case);rows[1]['commands'][-1]['progress'] = False
            self.assertTrue(self.fixture.verify((rows, raw))['issues'])
        rows, raw = self.evidence(food.FULL_QUARTER_CASE)
        rows[1]['editEvidence']['denialReason'] = 'edit_required_state'
        self.assertTrue(self.fixture.verify((rows, raw))['issues'])

    def test_preparation_receipts_water_and_authority_cannot_be_faked(self):
        for field, value in [('sourcePlain', False), ('sourceFood', False), ('foodWeight', 1), ('remaining', -.075),
                             ('baseHunger', -.4), ('foodType', 'Base.Cereal'), ('tailId', 102), ('panCount', True),
                             ('tailThirstChange', -.25), ('fixturePanId', 999)]:
            rows, raw = self.evidence();raw[0][1][field] = value
            with self.subTest(field=field): self.assertTrue(self.fixture.verify((rows, raw))['issues'])
        for field, value in [('tailAmount', .48), ('tailAmount', True), ('tailThirstChange', -.5), ('thirst', .55),
                             ('anchorAmount', 1), ('anchorThirstChange', -.5), ('hunger', .675)]:
            rows, raw = self.evidence()
            for endpoint in (rows[1], rows[1]['client'], raw[1][1]): endpoint[field] = value
            with self.subTest(field=field): self.assertTrue(self.fixture.verify((rows, raw))['issues'])
        rows, raw = self.evidence(kind='mp')
        self.assertTrue(self.fixture.verify((rows, raw), wrong_authority=True)['issues'])
        rows, raw = self.evidence();rows[1]['client']['pans'][-1]['id'] = 999
        self.assertTrue(self.fixture.verify((rows, raw))['issues'])

    def test_registered_scope_is_separate_from_partial_cases(self):
        suite = food.definitions()['food']
        for kind in ('sp', 'mp'):
            self.assertEqual(list(food.FULL_CASES), scenarios.select(suite, 'success-queued', 'eat-full-replacement', kind, 'toolkit')[0])
        action = suite['scenario_actions']['eat-full-replacement']
        self.assertEqual({'success-queued', 'move-independent', 'cancel-waiting', 'move-dependent', 'server-authority'}, set(action['checks']))
        for name, definition in suite['scenario_actions'].items():
            if name != 'eat-full-replacement':
                self.assertFalse(set(food.FULL_CASES) & {case for cases in definition['checks'].values() for case in cases})

    def test_native_original_disposal_guard_checks_exact_type_id_uses_and_detachment(self):
        from lupa import LuaRuntime
        lua = LuaRuntime()
        lua.globals().Full = lua.execute((ROOT / 'tests/native_queue/food/shared/QueueFoodFull.lua').read_text())
        lua.execute("""
package.preload.QueueTestSelection=function()return {mode='native'}end
local id,kind,uses,container,world,remaining=2,'Base.PanFriedVegetables2',0,nil,nil,0
local original={getID=function()return id end,getFullType=function()return kind end,
 getCurrentUses=function()return uses end,getContainer=function()return container end,
 getWorldItem=function()return world end,getHungChange=function()return remaining end}
local state={case='food-full-replacement-after-quarter',originalFood=original,
 ids={foodId=2,foodType=kind,foodTypeCount=1,panCount=1,pans={{id=4}},hunger=.8,baseHunger=-.1,
 anchorAmount=1,anchorThirstChange=-.5,tailAmount=1,tailThirstChange=-.5,thirst=.8}}
local value={deleted=true,foodCount=0,foodTypeCount=0,bagCount=1,anchorCount=1,panCount=2,
 tailAmount=.5,anchorAmount=.5,hunger=.7,thirst=.3,
 pans={{id=4,normal=true,fluid=false,root=true,weight=1.3},{id=5,normal=true,fluid=false,root=true,weight=1.3}}}
assert(Full.verify(state,value)==value and state.verified)
local function rejected()state.verified=nil;assert(Full.verify(state,value)==nil and not state.verified)end
id=3;rejected();id=2
kind='Base.Other';rejected();kind='Base.PanFriedVegetables2'
uses=1;rejected();uses=0
container={};rejected();container=nil
world={};rejected();world=nil
remaining=-.025;rejected();remaining=math.huge;rejected()
remaining=0/0;assert(Full.verify(state,value)==value)
remaining=0;value.pans[1].id=6;rejected();value.pans[1].id=4
value.pans[2].normal=false;rejected();value.pans[2].normal=true
value.pans[2].fluid=true;rejected();value.pans[2].fluid=false
value.pans[2].root=false;rejected();value.pans[2].root=true
assert(Full.verify(state,value)==value)
""")

    def test_completion_observer_delegates_then_restores_inherited_and_own_callback(self):
        from lupa import LuaRuntime
        lua = LuaRuntime()
        lua.execute("""
package.preload.QueueScenarioChecks=function()return {}end
package.preload['PZSurvivorToolkit/ActionQueue']=function()return {}end
package.preload['PZSurvivorToolkit/ActionQueuePolicy']=function()return {}end
""")
        lua.globals().Full = lua.execute((ROOT / 'tests/native_queue/food/client/QueueFoodFullClient.lua').read_text())
        lua.execute("""
for _,hasOwn in ipairs({false,true})do
 local anchor={action={}};local present={[anchor.action]=true}
 local root={getItemById=function()return {}end}
 local player={getInventory=function()return root end,getCharacterActions=function()return {contains=function(_,native)return present[native]==true end}end}
 local q={queue={anchor},current=anchor,character=player};local called=0
 local function native(self,action)
  assert(self.queue[1]==action);table.remove(self.queue,1);self.current=self.queue[1];called=called+1;return 'native'
 end
 setmetatable(q,{__index={onCompleted=native}})
 local own=function(self,action)return native(self,action)end
 if hasOwn then q.onCompleted=own end
 q.indexOf=function(self,action)for i,entry in ipairs(self.queue)do if entry==action then return i end end;return -1 end
 ISTimedActionQueue={add=function(action)q.queue[#q.queue+1]=action end}
 ISDrinkFluidAction={new=function()local handle={};present[handle]=true;return {action=handle,maxTime=460,percentage=.5,getDuration=function()return 460 end}end}
 local commands,observed,evidence={},{},{}
 local function eat(portion,menu)
  local action={action={}};present[action.action]=true;q.queue[#q.queue+1]=action
  commands[#commands+1]={};observed[#observed+1]={eat=action};return action
 end
 local observer=Full.dispatch(player,{tailId=3},'food-full-replacement-move-independent','native',q,anchor,eat,commands,observed,evidence)
 assert(q:onCompleted(anchor)=='native'and called==1 and #evidence.completionOrder==0)
 present[anchor.action]=nil;Full.poll(observer,evidence)
 assert(evidence.completionOrder[1]=='anchor')
 for _,label in ipairs({'full','tail'})do
  evidence.startOrder[#evidence.startOrder+1]=label
  local action=q.current;Full.started(observer,action);assert(q:onCompleted(action)=='native')
  local before=#evidence.completionOrder;assert(not observer.byAction[action].completed)
  present[action.action]=nil;Full.poll(observer,evidence);assert(#evidence.completionOrder==before+1)
 end
 Full.finish(observer,evidence)
 assert(called==3 and #q.queue==0 and q.onCompleted==(hasOwn and own or native))
 assert(rawget(q,'onCompleted')==(hasOwn and own or nil))
end
""")

    def test_actual_lifecycle_deferred_callback_waits_for_complete_and_native_removal(self):
        from lupa import LuaRuntime
        for host in (False, True):
            with self.subTest(host=host):
                lua = LuaRuntime()
                lua.globals().host = host
                lua.execute("""
package.preload.QueueScenarioChecks=function()return {}end
package.preload['PZSurvivorToolkit/ActionQueue']=function()return {}end
package.preload['PZSurvivorToolkit/ActionQueuePolicy']=function()return {}end
package.preload['TimedActions/ISQueueActionsAction']=function()return {}end
ISQueueActionsAction={start=function()end}
PZSurvivorToolkit={Settings={actionQueue=function()return true end}}
isClient=function()return host end
ISTimedActionQueue={queues={}}
""")
                lua.globals().Lifecycle = lua.execute((ROOT / 'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueLifecycle.lua').read_text())
                lua.globals().Full = lua.execute((ROOT / 'tests/native_queue/food/client/QueueFoodFullClient.lua').read_text())
                lua.execute("""
local present={};local root={getItemById=function()return {}end}
local player={getInventory=function()return root end,getCharacterActions=function()return {contains=function(_,native)return present[native]==true end}end}
local anchor={action={},character=player};present[anchor.action]=true
local q={queue={anchor},current=anchor,character=player};ISTimedActionQueue.queues[player]=q
q.indexOf=function(self,action)for i,entry in ipairs(self.queue)do if entry==action then return i end end;return -1 end
local nativeRemovals=0
local function prior(self,action)
 if Lifecycle.deferCompletion(self,action)then return 'deferred'end
 assert(self.queue[1]==action);table.remove(self.queue,1);self.current=self.queue[1];nativeRemovals=nativeRemovals+1
 return 'native'
end
q.onCompleted=prior
ISTimedActionQueue.add=function(action)q.queue[#q.queue+1]=action end
ISDrinkFluidAction={new=function()local handle={};present[handle]=true;return {character=player,action=handle,maxTime=460,percentage=.5,getDuration=function()return 460 end}end}
local commands,observed,evidence={},{},{}
local function eat()
 local action={character=player,action={}};present[action.action]=true;q.queue[#q.queue+1]=action
 commands[#commands+1]={};observed[#observed+1]={eat=action};return action
end
local observer=Full.dispatch(player,{tailId=3},'food-full-replacement-move-independent','native',q,anchor,eat,commands,observed,evidence)
for index,label in ipairs({'anchor','full','tail'})do
 local action=q.current;Full.started(observer,action)
 if index>1 then evidence.startOrder[#evidence.startOrder+1]=label end
 assert(Lifecycle.begin(action,'perform'))
 assert(q:onCompleted(action)=='deferred')
 assert(not observer.failed and #observer.requests==index and not observer.byAction[action].released)
 Lifecycle.finish(action,'perform',true)
 Full.poll(observer,evidence)
 assert(#evidence.completionOrder==index-1 and Lifecycle.flush(q)=='waiting')
 present[action.action]=nil
 if not host then
  -- Even Java removal is insufficient until the SP complete callback finishes.
  assert(Lifecycle.flush(q)=='waiting')
  assert(Lifecycle.begin(action,'complete'));Lifecycle.finish(action,'complete',true)
 end
 assert(Lifecycle.flush(q)=='completed')
 Full.poll(observer,evidence)
 assert(not observer.failed and #observer.requests==index and #evidence.completionOrder==index)
 assert(evidence.completionOrder[index]==label and observer.byAction[action].released)
end
Full.finish(observer,evidence)
assert(nativeRemovals==3 and q.onCompleted==prior)
""")

    def test_deferred_request_or_queue_disappearance_alone_never_counts_as_completion(self):
        from lupa import LuaRuntime
        lua = LuaRuntime()
        lua.execute("""
package.preload.QueueScenarioChecks=function()return {}end
package.preload['PZSurvivorToolkit/ActionQueue']=function()return {}end
package.preload['PZSurvivorToolkit/ActionQueuePolicy']=function()return {}end
local diagnostics={}
package.preload.QueueHealthEvents=function()return {encode=function(value)diagnostics[#diagnostics+1]=value;return 'diagnostic'end}end
print=function()end
Diagnostics=diagnostics
""")
        lua.globals().Full = lua.execute((ROOT / 'tests/native_queue/food/client/QueueFoodFullClient.lua').read_text())
        lua.execute("""
local present={};local root={getItemById=function()return {}end}
local player={getInventory=function()return root end,getCharacterActions=function()return {contains=function(_,native)return present[native]==true end}end}
for _,signal in ipairs({'deferred','absent','replaced','missing-native','swapped-native'})do
 local anchor={action=signal~='missing-native'and {}or nil}
 if anchor.action then present[anchor.action]=true end
 local q={queue={anchor},current=anchor,character=player,onCompleted=function()return 'deferred'end}
 q.indexOf=function(self,action)for i,entry in ipairs(self.queue)do if entry==action then return i end end;return -1 end
 ISTimedActionQueue={add=function(action)q.queue[#q.queue+1]=action end}
 ISDrinkFluidAction={new=function()return {maxTime=460,percentage=.5,getDuration=function()return 460 end}end}
 local commands,observed,evidence={},{},{}
 local function eat()local action={};q.queue[#q.queue+1]=action;commands[#commands+1]={};observed[#observed+1]={eat=action};return action end
 local observer=Full.dispatch(player,{tailId=3},'food-full-replacement-move-independent','native',q,anchor,eat,commands,observed,evidence)
 if signal=='swapped-native'then anchor.action={}end
 if signal~='absent'then assert(q:onCompleted(anchor)=='deferred')end
 if signal=='replaced'then q.onCompleted=function()end end
 -- A reset/cancel-like disappearance after a deferred request is not a completed callback.
 q.queue={};q.current=nil;if anchor.action then present[anchor.action]=nil end
 Full.poll(observer,evidence)
 assert(#evidence.completionOrder==0)
 local ok,problem=pcall(Full.finish,observer,evidence)
 assert(not ok)
 local diagnostic=Diagnostics[#Diagnostics]
 assert(diagnostic.callbackReplaced==(signal=='replaced'))
 if signal=='replaced'then assert(problem:find('callback replaced',1,true))
 elseif signal=='missing-native'or signal=='swapped-native'then assert(problem:find('observation failed',1,true)and diagnostic.observerFailure)
 else assert(problem:find('count differs',1,true)and not diagnostic.observerFailure)end
end
""")

    def test_all_food_lua_sources_compile(self):
        from lupa import LuaRuntime
        lua = LuaRuntime()
        for source in (ROOT / 'tests/native_queue/food').rglob('*.lua'):
            with self.subTest(source=source.name): self.assertIsNotNone(lua.eval('load')(source.read_text()))


if __name__ == '__main__':
    unittest.main()
