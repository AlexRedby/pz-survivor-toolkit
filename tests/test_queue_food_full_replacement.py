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
    spec = food.FULL_SPECS[case]
    cancelled = enabled and case in (food.FULL_CANCEL_CASE, food.FLUID_FULL_CANCEL_CASE)
    quarter = case in (food.FULL_QUARTER_CASE, food.FLUID_FULL_QUARTER_CASE)
    base = 100 + index * 10
    has_fluid = spec['capacity'] > 0
    pan = dict(id=base + 4, type=spec['outputType'], weight=spec['outputWeight'], normal=True,
               fluid=has_fluid, root=True, scriptSafe=True, componentCount=int(has_fluid),
               fluidCount=int(has_fluid), initialFluidCount=0, fluidOwner=has_fluid,
               fluidOwnerId=base + 4 if has_fluid else -1, fluidAmount=0,
               fluidCapacity=spec['capacity'], fluidEmpty=True)
    prep = dict(case=case, bagId=base, bagType='Base.Bag_ALICEpack_Army', bagCount=1,
                foodId=base + 1, foodType=spec['foodType'], baseHunger=spec['baseHunger'], remaining=spec['baseHunger'],
                source='root', foodCount=1, foodTypeCount=1, deleted=False,
                anchorId=base + 2, anchorType='Base.WaterBottle', anchorAmount=1.0,
                anchorCount=1, anchorThirstChange=-.5, hunger=.8, thirst=.8, foodTimer=0, foodLevel=0,
                tailId=base + 3, tailType='Base.WaterBottle', tailAmount=1.0, tailThirstChange=-.5, tailCount=1,
                fixtureOutputId=base + 4, outputs=[pan], outputCount=1, foodWeight=spec['foodWeight'],
                sourceFood=True, sourcePlain=True, consumptionReplacementType=spec['outputType'])
    receipt = {key: copy.deepcopy(value) for key, value in prep.items() if key not in ('foodTimer', 'foodLevel')}
    receipt.update(remaining=spec['baseHunger'] if cancelled else 0, source='root' if cancelled else 'deleted',
                   foodCount=int(cancelled), foodTypeCount=int(cancelled), deleted=not cancelled,
                   anchorAmount=.5, anchorThirstChange=-.25, tailAmount=.5, tailThirstChange=-.25,
                   hunger=.8 if cancelled else .8 + spec['baseHunger'], thirst=.3, foodWeight=spec['foodWeight'] if cancelled else 0,
                   sourceFood=cancelled, sourcePlain=cancelled)
    if not cancelled:
        receipt['outputs'].append(dict(pan, id=base + 5, fluidOwnerId=base + 5 if has_fluid else -1))
        receipt['outputCount'] += 1
    portions = [.25, 1, .5] if quarter else [1, .5]
    commands = []
    for n, portion in enumerate(portions):
        tail = n == len(portions) - 1
        commands.append(dict(id=base + 3 if tail else base + 1, portion=portion,
                             baseHunger=0 if tail else spec['baseHunger'], dispatchRemaining=0 if tail else spec['baseHunger'],
                             dispatchSource='root', menuDispatched=not tail, nativeDuration=460 if tail else 232,
                             progress=not (cancelled and not tail), cancelled=cancelled and not tail, pickupObserved=False))
    order = [1, 2, 3] if quarter else [2] if cancelled else [2, 1] if enabled and case in (food.FULL_MOVE_CASE, food.FLUID_FULL_MOVE_CASE) else [1, 2]
    labels = ['anchor'] + [('quarter', 'full', 'tail')[n - 1] if quarter else ('full', 'tail')[n - 1] for n in order]
    edit = dict(emptyStart=True, anchorRunning=True, anchorProgress=True, anchorDuration=460,
                contractsVerified=enabled, reordered=enabled and case in (food.FULL_MOVE_CASE, food.FLUID_FULL_MOVE_CASE), waitingCancel=cancelled,
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

    def test_six_cases_have_matched_sp_host_and_queue_off_controls(self):
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
                  ('outputCount', 1), ('fixtureOutputId', 999), ('foodId', 999), ('consumptionReplacementType', 'Base.Bowl')]
        for field, value in faults:
            rows, raw = self.evidence()
            for endpoint in (rows[1], rows[1]['client'], raw[1][1]): endpoint[field] = value
            with self.subTest(field=field): self.assertTrue(self.fixture.verify((rows, raw))['issues'])
        for fault in ('lost-old', 'duplicate', 'source-id', 'nested', 'fluid', 'wrong-class', 'weight', 'extra-output', 'missing-output'):
            rows, raw = self.evidence()
            for endpoint in (rows[1], rows[1]['client'], raw[1][1]):
                outputs = endpoint['outputs']
                if fault == 'lost-old': outputs[0]['id'] = 999
                elif fault == 'duplicate': outputs[1]['id'] = outputs[0]['id']
                elif fault == 'source-id': outputs[1]['id'] = endpoint['foodId']
                elif fault == 'nested': outputs[1]['root'] = False
                elif fault == 'fluid': outputs[1]['fluid'] = True
                elif fault == 'wrong-class': outputs[1]['normal'] = False
                elif fault == 'weight': outputs[1]['weight'] = 2
                elif fault == 'extra-output': outputs.append(dict(outputs[-1], id=999));endpoint['outputCount'] += 1
                else: outputs.pop();endpoint['outputCount'] -= 1
            with self.subTest(fault=fault): self.assertTrue(self.fixture.verify((rows, raw))['issues'])

    def test_cancel_requires_original_untouched_and_no_new_output_while_tail_completes(self):
        for field, value in [('remaining', -.075), ('deleted', True), ('foodWeight', 1), ('sourcePlain', False),
                             ('outputCount', 2), ('tailAmount', 1), ('tailCount', 0), ('hunger', .7)]:
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
                             ('baseHunger', -.4), ('foodType', 'Base.Cereal'), ('tailId', 102), ('outputCount', True),
                             ('tailThirstChange', -.25), ('fixtureOutputId', 999)]:
            rows, raw = self.evidence();raw[0][1][field] = value
            with self.subTest(field=field): self.assertTrue(self.fixture.verify((rows, raw))['issues'])
        for field, value in [('tailAmount', .48), ('tailAmount', True), ('tailThirstChange', -.5), ('thirst', .55),
                             ('anchorAmount', 1), ('anchorThirstChange', -.5), ('hunger', .675)]:
            rows, raw = self.evidence()
            for endpoint in (rows[1], rows[1]['client'], raw[1][1]): endpoint[field] = value
            with self.subTest(field=field): self.assertTrue(self.fixture.verify((rows, raw))['issues'])
        rows, raw = self.evidence(kind='mp')
        self.assertTrue(self.fixture.verify((rows, raw), wrong_authority=True)['issues'])
        rows, raw = self.evidence();rows[1]['client']['outputs'][-1]['id'] = 999
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
 ids={foodId=2,foodType=kind,foodTypeCount=1,outputCount=1,outputs={{id=4}},hunger=.8,baseHunger=-.1,
 anchorAmount=1,anchorThirstChange=-.5,tailAmount=1,tailThirstChange=-.5,thirst=.8}}
local value={deleted=true,foodCount=0,foodTypeCount=0,bagCount=1,anchorCount=1,outputCount=2,
 tailAmount=.5,anchorAmount=.5,tailCount=1,hunger=.7,thirst=.3,
 outputs={}}
for _,id in ipairs({4,5})do value.outputs[#value.outputs+1]={id=id,type='Base.RoastingPan',normal=true,fluid=false,root=true,
 weight=1.3,scriptSafe=true,componentCount=0,fluidCount=0,initialFluidCount=0,fluidOwner=false,
 fluidOwnerId=-1,fluidAmount=0,fluidCapacity=0,fluidEmpty=true}end
assert(Full.verify(state,value)==value and state.verified)
local function rejected()state.verified=nil;assert(Full.verify(state,value)==nil and not state.verified)end
id=3;rejected();id=2
kind='Base.Other';rejected();kind='Base.PanFriedVegetables2'
uses=1;rejected();uses=0
container={};rejected();container=nil
world={};rejected();world=nil
remaining=-.025;rejected();remaining=math.huge;rejected()
remaining=0/0;assert(Full.verify(state,value)==value)
remaining=0;value.outputs[1].id=6;rejected();value.outputs[1].id=4
value.outputs[2].normal=false;rejected();value.outputs[2].normal=true
value.outputs[2].fluid=true;rejected();value.outputs[2].fluid=false
value.outputs[2].root=false;rejected();value.outputs[2].root=true
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
        lua.globals().FullFixture = lua.execute((ROOT / 'tests/native_queue/food/shared/QueueFoodFull.lua').read_text())
        lua.execute("package.preload.QueueFoodFull=function()return FullFixture end")
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
                lua.globals().FullFixture = lua.execute((ROOT / 'tests/native_queue/food/shared/QueueFoodFull.lua').read_text())
                lua.execute("package.preload.QueueFoodFull=function()return FullFixture end")
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
        lua.globals().FullFixture = lua.execute((ROOT / 'tests/native_queue/food/shared/QueueFoodFull.lua').read_text())
        lua.execute("package.preload.QueueFoodFull=function()return FullFixture end")
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

    def test_empty_fluid_outputs_require_exact_schema_on_both_endpoints_and_preparation(self):
        faults = [('type', 'Base.RoastingPan'), ('normal', False), ('weight', .3), ('root', False),
                  ('fluid', False), ('scriptSafe', False), ('componentCount', 0), ('componentCount', 2),
                  ('componentCount', True), ('fluidCount', 0), ('fluidCount', 2), ('initialFluidCount', 1),
                  ('fluidOwner', False), ('fluidOwnerId', 999), ('fluidAmount', .01), ('fluidAmount', .000001), ('fluidAmount', True),
                  ('fluidCapacity', .4), ('fluidEmpty', False), ('fluidEmpty', 1)]
        for field, value in faults:
            for prepared in (False, True):
                rows, raw = self.evidence(food.FLUID_FULL_MOVE_CASE)
                endpoints = (raw[0][1],) if prepared else (rows[1], rows[1]['client'], raw[1][1])
                for endpoint in endpoints: endpoint['outputs'][-1][field] = value
                with self.subTest(field=field, value=value, prepared=prepared):
                    self.assertTrue(self.fixture.verify((rows, raw))['issues'])
        rows, raw = self.evidence(food.FLUID_FULL_MOVE_CASE)
        fields = list(raw[1][1]['outputs'][-1])
        for field in fields + ['unexpected']:
            rows, raw = self.evidence(food.FLUID_FULL_MOVE_CASE)
            for endpoint in (rows[1], rows[1]['client'], raw[1][1]):
                if field == 'unexpected': endpoint['outputs'][-1][field] = 1
                else: del endpoint['outputs'][-1][field]
            with self.subTest(schema=field): self.assertTrue(self.fixture.verify((rows, raw))['issues'])
        for fault in ('lost-old', 'duplicate', 'source-id', 'missing', 'extra', 'changed-old'):
            rows, raw = self.evidence(food.FLUID_FULL_MOVE_CASE)
            for endpoint in (rows[1], rows[1]['client'], raw[1][1]):
                outputs = endpoint['outputs']
                if fault == 'lost-old': outputs[0].update(id=999, fluidOwnerId=999)
                elif fault == 'duplicate': outputs[1].update(id=outputs[0]['id'], fluidOwnerId=outputs[0]['id'])
                elif fault == 'source-id': outputs[1].update(id=endpoint['foodId'], fluidOwnerId=endpoint['foodId'])
                elif fault == 'missing': outputs.pop(); endpoint['outputCount'] -= 1
                elif fault == 'extra': outputs.append(dict(outputs[-1], id=999, fluidOwnerId=999)); endpoint['outputCount'] += 1
                else: outputs[0]['fluidAmount'] = .01
            with self.subTest(identity=fault): self.assertTrue(self.fixture.verify((rows, raw))['issues'])
        rows, raw = self.evidence(food.FLUID_FULL_MOVE_CASE)
        rows[1]['client']['outputs'][-1]['fluidOwnerId'] = 999
        self.assertTrue(self.fixture.verify((rows, raw))['issues'])

    def test_native_empty_fluid_receipt_rejects_wrong_type_component_owner_and_nonempty_output(self):
        from lupa import LuaRuntime
        lua = LuaRuntime()
        lua.globals().Full = lua.execute((ROOT / 'tests/native_queue/food/shared/QueueFoodFull.lua').read_text())
        row, raw = family_evidence(food.FLUID_FULL_MOVE_CASE, 0, 'native')
        lua.globals().ids = lua.table_from(raw[0][1], recursive=True)
        lua.globals().value = lua.table_from(raw[1][1], recursive=True)
        lua.execute("""
package.preload.QueueTestSelection=function()return {mode='native'}end
local original={getID=function()return ids.foodId end,getFullType=function()return ids.foodType end,
 getCurrentUses=function()return 0 end,getContainer=function()end,getWorldItem=function()end,getHungChange=function()return 0 end}
local state={case=ids.case,ids=ids,originalFood=original}
assert(Full.verify(state,value)==value)
local output=value.outputs[2]
local function reject(field,bad)
 local old=output[field];output[field]=bad;state.verified=nil
 assert(Full.verify(state,value)==nil and not state.verified,field);output[field]=old
end
reject('type','Base.Other');reject('normal',false);reject('fluid',false);reject('root',false)
reject('scriptSafe',false);reject('componentCount',0);reject('componentCount',2)
reject('fluidCount',0);reject('fluidCount',2);reject('initialFluidCount',1)
reject('fluidOwner',false);reject('fluidOwnerId',999);reject('fluidAmount',.01);reject('fluidAmount',.000001)
reject('fluidCapacity',.4);reject('fluidEmpty',false);reject('weight',.3)
reject('id',ids.foodId);reject('id',value.outputs[1].id)
value.outputs[1].fluidAmount=.01;assert(Full.verify(state,value)==nil)
value.outputs[1].fluidAmount=0;assert(Full.verify(state,value)==value)
""")

    def test_native_cancel_keeps_exact_original_can_and_all_preexisting_outputs(self):
        from lupa import LuaRuntime
        lua = LuaRuntime()
        lua.globals().Full = lua.execute((ROOT / 'tests/native_queue/food/shared/QueueFoodFull.lua').read_text())
        row, raw = family_evidence(food.FLUID_FULL_CANCEL_CASE, 0, 'toolkit')
        lua.globals().ids = lua.table_from(raw[0][1], recursive=True)
        lua.globals().value = lua.table_from(raw[1][1], recursive=True)
        lua.execute("""
package.preload.QueueTestSelection=function()return {mode='toolkit'}end
local root={};local id,kind,container,world,remaining,weight=ids.foodId,ids.foodType,root,nil,ids.remaining,ids.foodWeight
local original={getID=function()return id end,getFullType=function()return kind end,
 getContainer=function()return container end,getWorldItem=function()return world end,
 getHungChange=function()return remaining end,getActualWeight=function()return weight end}
local state={case=ids.case,ids=ids,originalFood=original,player={getInventory=function()return root end}}
assert(Full.verify(state,value)==value)
local function reject()state.verified=nil;assert(Full.verify(state,value)==nil and not state.verified)end
id=999;reject();id=ids.foodId;kind='Base.Other';reject();kind=ids.foodType
container={};reject();container=root;world={};reject();world=nil
remaining=0;reject();remaining=ids.remaining;weight=.2;reject();weight=ids.foodWeight
value.outputs[1].fluidAmount=.01;reject();value.outputs[1].fluidAmount=0
assert(Full.verify(state,value)==value)
""")

    def test_native_factory_default_and_authored_script_are_checked_without_repair_or_rng(self):
        from lupa import LuaRuntime
        lua = LuaRuntime()
        lua.globals().Full = lua.execute((ROOT / 'tests/native_queue/food/shared/QueueFoodFull.lua').read_text())
        lua.execute("""
local bad=nil;local published=0;local outputEmptied=0
local function list(values)return {size=function()return #values end,get=function(_,i)return values[i+1]end}end
ComponentType={FluidContainer='fluid'};ItemTag={FORK='fork',SPOON='spoon'};Fluid={Water='water'}
instanceof=function(item,kind)return item.class==kind end
getClassSimpleName=function(item)return item.class end
isServer=function()return true end
sendAddItemToContainer=function()published=published+1 end
local component={class='FluidContainerScript',getCapacity=function()return bad=='script-capacity'and .4 or .3 end,
 getInitialFluids=function()return bad=='initial-fluid'and list({{}})or nil end,
 getInitialAmount=function()error('RNG must never run')end}
local outputScript={getItemType=function()return bad=='item-type'and 'base:food'or 'base:normal'end,
 getLuaCreate=function()return bad=='callback'and 'callback'or nil end,
 getItemConfig=function()return bad=='config'and 'config'or nil end,
 getItemConfigKey=function()return bad=='config-key'and 'key'or nil end,
 getActualWeight=function()return .2 end,hasComponents=function()return true end,
 getComponentScripts=function()return bad=='extra-component'and list({component,{class='Other'}})
  or bad=='missing-component'and list({})or list({component})end,
 getComponentScriptFor=function()return bad=='component-identity'and {}or component end}
local source={hasComponents=function()return false end,getItemType=function()return 'base:food'end,
 getLuaCreate=function()end,getItemConfig=function()end,getItemConfigKey=function()end}
local root={getFirstTagRecurse=function()end,getFirstTypeRecurse=function()end}
local food={class='Food',getScriptItem=function()return source end,getBaseHunger=function()return -.15 end,
 getHungChange=function()return -.15 end,getActualWeight=function()return .8 end,
 isCookable=function()return false end,isCooked=function()return false end,isCustomWeight=function()return false end,
 haveExtraItems=function()return false end,getOnEat=function()end,getOnCooked=function()end,
 getReplaceOnUseFullType=function()return 'Base.TinCanEmpty'end}
ScriptManager={instance={getItem=function()return outputScript end}}
root.AddItem=function(_,kind)
 if kind=='Base.WaterBottle'then return {getID=function()return 2 end,getFluidContainer=function()return {Empty=function()end,addFluid=function()end}end}end
 local item={class=bad=='class'and 'Other'or 'ComboItem',getID=function()return 3 end,getFullType=function()return kind end,
  getScriptItem=function()return outputScript end,getActualWeight=function()return .2 end,getContainer=function()return root end}
 local fluid={getOwner=function()return bad=='owner'and {getID=function()return 3 end}or item end,
  getAmount=function()return bad=='nonempty'and .1 or 0 end,getCapacity=function()return .3 end,
  isEmpty=function()return bad~='nonempty'end,Empty=function()outputEmptied=outputEmptied+1 end}
 item.getFluidContainer=function()return bad~='missing-fluid'and fluid or nil end
 return item
end
local player={getInventory=function()return root end}
local function prepare()return Full.prepare(player,food,{case='food-full-fluid-replacement-move-independent'})end
prepare();assert(published==2 and outputEmptied==0)
for _,fault in ipairs({'script-capacity','initial-fluid','item-type','callback','config','config-key',
 'extra-component','missing-component','component-identity','class','owner','nonempty','missing-fluid'})do
 bad=fault;published=0;assert(not pcall(prepare),fault);assert(published==0 and outputEmptied==0,fault)
end
""")

    def test_all_food_lua_sources_compile(self):
        from lupa import LuaRuntime
        lua = LuaRuntime()
        for source in (ROOT / 'tests/native_queue/food').rglob('*.lua'):
            with self.subTest(source=source.name): self.assertIsNotNone(lua.eval('load')(source.read_text()))


if __name__ == '__main__':
    unittest.main()
