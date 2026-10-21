"""Reject invented native-food progress, wrong portions and client-only effects."""
import copy
import json
import os
import shutil
import subprocess
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import adapters
from queue_checks.adapters import food


class FoodAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.selection = dict(suite='food', cases=list(food.CASES), kind='sp', mode='toolkit',
                              languages=['EN'], mods=list(food.MODS), clients=1, options={})

    def evidence(self):
        cases = self.selection['cases']
        rows = [dict(event='setup', cases=cases, expected=len(cases),
                     queueEnabled=self.selection['mode'] == 'toolkit', nativeDurations=True)]
        raw = []
        for index, case in enumerate(cases):
            bag, enabled, depletion = case == food.BAG_CASE, self.selection['mode'] == 'toolkit', case == food.DEPLETION_CASE
            smart, utensil, cookable = case in food.SMART_CASES, case in food.UTENSIL_CASES, case in food.COOKABLE_CASES
            replacement = case in food.REPLACEMENT_CASES
            custom_weight = case in food.CUSTOM_WEIGHT_CASES
            consumption = custom_weight or case in food.CONSUMPTION_CASES
            thermal = cookable or replacement
            cooked = case in (food.COOKED_MOVE_CASE, food.COOKED_CANCEL_CASE)
            base_hunger = -.15 if consumption else -.1 if replacement else -.3 if cooked else -.24 if cookable else -.5 if utensil else -.4
            cancel = case in (food.CANCEL_CASE, food.SMART_CANCEL_CASE, food.UTENSIL_CANCEL_CASE, food.COOKED_CANCEL_CASE, food.RAW_CANCEL_CASE, food.REPLACEMENT_CANCEL_CASE, food.CONSUMPTION_CANCEL_CASE, food.CUSTOM_WEIGHT_CANCEL_CASE) and enabled
            base = 100 + 10 * index
            prep = dict(case=case, bagId=base, bagType='Base.Bag_ALICEpack_Army', bagCount=1,
                        foodId=base + 1, foodType='Base.CannedPeachesOpen' if consumption else 'Base.BreadSlices' if replacement else 'Base.ChickenFillet' if cooked else 'Base.Cabbage' if cookable else 'Base.OatsRaw' if utensil else 'Base.Cereal',
                        baseHunger=base_hunger, remaining=-.3 if smart else base_hunger,
                        source='bag' if bag else 'root', foodCount=1, foodTypeCount=1, deleted=False,
                        anchorId=base + 2, anchorType='Base.WaterBottle', anchorAmount=1.0,
                        anchorCount=1, anchorThirstChange=-.5, hunger=.2 if smart else .8, thirst=.8, foodTimer=0, foodLevel=0)
            if thermal:
                prep.update(cookable=True, cooked=cooked, burnt=False, rotten=False, fertilized=False,
                            heat=1, inventoryTemperature=1)
            if replacement:
                prep.update(replacementType='Base.Toast', replacementCount=0, cookingTime=0)
            if consumption:
                prep.update(consumptionReplacementType='Base.TinCanEmpty', consumptionReplacementCount=0,
                            foodWeight=1.1 if custom_weight else .8, customWeight=custom_weight, extraItems=False)
            if utensil:
                prep.update(forkId=base + 3, forkType='Base.Fork', forkCount=1,
                            forkSource='bag' if case == food.UTENSIL_MOVE_CASE else 'root',
                            forkCondition=5 if case == food.UTENSIL_MOVE_CASE else 0,
                            spoonId=base + 4, spoonType='Base.Spoon', spoonCount=1,
                            spoonSource='root' if case == food.UTENSIL_MOVE_CASE else 'bag', spoonCondition=5)
            fraction = (.125 if cancel else .75) if utensil else (.375 if cancel else .5) if smart else 1 if depletion else .5 if bag else .25 if cancel else .75
            receipt = {key: value for key, value in prep.items() if key in food.RECEIPT_KEYS | (food.UTENSIL_RECEIPT_KEYS if utensil else set()) | (food.COOKABLE_RECEIPT_KEYS if thermal else set()) | (food.REPLACEMENT_RECEIPT_KEYS if replacement else set()) | (food.CONSUMPTION_RECEIPT_KEYS if consumption else set())}
            receipt.update(remaining=prep['remaining'] - prep['baseHunger'] * fraction if smart else prep['baseHunger'] * (1 - fraction), source='deleted' if depletion else 'root' if not bag or enabled else 'bag',
                           foodCount=0 if depletion else 1, foodTypeCount=0 if depletion else 1, deleted=depletion,
                           anchorAmount=.5, anchorThirstChange=-.25, hunger=prep['hunger'] + prep['baseHunger'] * fraction * (1.3 if cooked else 1),
                           thirst=.55 - (.1 * fraction if cookable and not cooked else 0))
            if consumption:
                receipt['foodWeight'] = prep['foodWeight'] if custom_weight else .2 + .6 * (1 - fraction)
            commands = [dict(id=base + 1, portion=portion, baseHunger=prep['baseHunger'], dispatchRemaining=prep['remaining'],
                             dispatchSource=prep['source'], menuDispatched=not bag, nativeDuration=464 if portion == 1 else 232,
                             progress=not (cancel and n == 0), cancelled=cancel and n == 0, pickupObserved=bag)
                        for n, portion in enumerate([.625, .125] if utensil else [.125, .375] if smart else [.25, 1] if depletion else [.5] if bag else [.5, .25])]
            if thermal:
                for command in commands:
                    command.update(cooked=cooked, dispatchHeat=1)
            if utensil:
                for command in commands:
                    command.update(useUtensil=True,
                                   utensilId=prep['forkId' if case == food.UTENSIL_MOVE_CASE else 'spoonId'],
                                   forkId=prep['forkId'] if case == food.UTENSIL_MOVE_CASE else -1, spoonId=prep['spoonId'])
            if smart:
                for command, goal in zip(commands, (15, 5)):
                    command.update(smartGoal=goal, dispatchHunger=prep['hunger'])
            edit = dict(emptyStart=True, anchorRunning=True, anchorProgress=True, anchorDuration=460,
                        contractsVerified=enabled, reordered=enabled and case in (food.MOVE_CASE, food.BAG_CASE, food.SMART_MOVE_CASE, food.UTENSIL_MOVE_CASE, food.COOKED_MOVE_CASE, food.RAW_MOVE_CASE, food.REPLACEMENT_MOVE_CASE, food.CONSUMPTION_MOVE_CASE, food.CUSTOM_WEIGHT_MOVE_CASE),
                        waitingCancel=cancel, moveRejected=enabled and (bag or depletion), cancelRejected=enabled and bag,
                        manualPickup=bag, untouchedBefore=True, nativeDurationsUnchanged=True,
                        order=[1] if bag else [1, 2] if depletion else [2] if cancel else [2, 1] if enabled else [1, 2])
            if depletion: edit['denialReason'] = 'edit_resource_amount' if enabled else 'not-requested'
            if bag:
                edit.update(pickupDuration=-1 if self.selection['kind'] == 'mp' else 50,
                            returnDuration=-1 if self.selection['kind'] == 'mp' else 50,
                            returning=dict(boundary=True, completed=True, observationFailed=False,
                                           before='bag' if enabled else 'root', after='bag',
                                           started=False, transactionId=0, dontAdd=enabled))
            rows.append(dict(event='case', id=case, status='passed', commands=commands,
                             editEvidence=edit, client=copy.deepcopy(receipt), **receipt))
            raw.extend([('PREPARED', prep), ('VERIFIED', receipt)])
        rows.append(dict(event='complete', cases=cases, expected=len(cases), performed=len(cases), failed=0, skipped=0))
        for row in rows:
            row.update(suite='food', kind=self.selection['kind'], mode=self.selection['mode'], actor='client1')
        return rows, raw

    def single(self, case=food.MOVE_CASE):
        self.selection['cases'] = [case]
        return self.evidence()

    def verify(self, data=None, wrong_authority=False):
        rows, raw = data or self.evidence()
        client = '\n'.join('[QUEUE_CHECK] ' + json.dumps(row) for row in rows) + '\n[FOOD_TEST] COMPLETE\n'
        authority = '\n'.join('[FOOD_TEST] ' + marker + ' ' + json.dumps(value) for marker, value in raw) + '\n'
        (self.root / 'client1-launch.log').write_text(client + (authority if self.selection['kind'] == 'sp' or wrong_authority else ''))
        (self.root / 'server-launch.log').write_text('' if wrong_authority else authority)
        return food.verify(self.root, self.selection, {})

    def test_progress_observer_handles_idle_optional_pickup_and_queue_end(self):
        lua = shutil.which('luajit')
        if not lua:
            self.skipTest('LuaJIT is required to execute the fixture observer')
        helper = ROOT / 'tests/native_queue/food/shared/QueueFoodProgress.lua'
        script = r"""
local Progress=assert(loadfile(arg[1]))()
local started,delta,calls=true,.2,0
local action={isStarted=function()calls=calls+1;return started end,
 getJobDelta=function()calls=calls+1;return delta end}
-- Root food has no pickup; an idle queue must not match that absent action.
assert(Progress.running(nil,nil)==false)
assert(Progress.running(nil,action)==false)
assert(Progress.running(action,nil)==false)
assert(Progress.running(action,{})==false and calls==0)
assert(Progress.running(action,action)==true and calls==2)
started=false;delta=1
assert(Progress.running(action,action)==false and calls==3)
started=true;delta=0
assert(Progress.running(action,action)==false)
delta=.5;assert(Progress.running(action,action)==true)
-- Completion empties the queue while retained eat/pickup handles still exist.
local pending={eat=action};local command={progress=true,pickupObserved=false}
for _,head in ipairs({action,action})do
 if Progress.running(head,pending.pickup)then command.pickupObserved=true end
end
local head=nil
assert(Progress.running(head,pending.pickup)==false)
assert(Progress.running(head,pending.eat)==false)
assert(command.progress and not command.pickupObserved)
"""
        result = subprocess.run([lua, '-', str(helper)], input=script, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_preparation_disables_process_auto_drink_before_exposing_water(self):
        lua = shutil.which('luajit')
        if not lua:
            self.skipTest('LuaJIT is required to execute food preparation')
        script = r"""
local Fixture=assert(loadfile(arg[1]))()
for _,coreBefore in ipairs({false,true})do
 for _,playerBefore in ipairs({false,true})do
  local coreEnabled,playerEnabled=coreBefore,playerBefore
  local stop,reads={},0
  getCore=function()return {setOptionAutoDrink=function(_,value)coreEnabled=value end}end
  local player={setAutoDrink=function(_,value)playerEnabled=value end,
   getInventory=function()
    reads=reads+1
    assert(not coreEnabled and not playerEnabled,'water exposed with auto-drink enabled')
    error(stop)
   end}
  -- Execute the real preparation prologue and stop before allocating native items.
  local ok,problem=pcall(Fixture.prepare,player,'food-root-move-same-portions')
  assert(not ok and problem==stop and reads==1)
 end
end
"""
        result = subprocess.run(
            [lua, '-', str(ROOT / 'tests/native_queue/food/shared/QueueFoodFixture.lua')],
            input=script, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_installed_engine_auto_drink_guard(self):
        game, jdk = os.environ.get('PZ_NATIVE_GAME'), os.environ.get('PZ_NATIVE_JDK')
        if not game or not jdk:
            self.skipTest('Set PZ_NATIVE_GAME and PZ_NATIVE_JDK to run native auto-drink checks headlessly')
        jar = Path(game) / 'projectzomboid.jar'
        with tempfile.TemporaryDirectory() as directory:
            source = ROOT / 'tests/native_queue/support/FoodAutoDrinkChecks.java'
            compiled = subprocess.run(
                [str(Path(jdk) / 'bin/javac'), '-d', directory, '-cp', str(jar), str(source)],
                text=True, capture_output=True, timeout=60)
            self.assertEqual(0, compiled.returncode, compiled.stdout + compiled.stderr)
            result = subprocess.run(
                [str(Path(jdk) / 'bin/java'), '-Djava.awt.headless=true',
                 '-cp', directory + os.pathsep + str(jar), 'zombie.characters.FoodAutoDrinkChecks'],
                text=True, capture_output=True, timeout=60)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertIn('FOOD_AUTO_DRINK_CHECKS_PASS', result.stdout)

    def test_deletion_guard_rejects_moved_stale_or_unconsumed_original_with_precise_proof(self):
        lua = shutil.which('luajit')
        if not lua:
            self.skipTest('LuaJIT is required to execute the fixture deletion guard')
        fixture = ROOT / 'tests/native_queue/food/shared/QueueFoodFixture.lua'
        script = r"""
local Fixture=assert(loadfile(arg[1]))()
local id,kind,hunger,container,world,uses=10,'Base.Cereal',0,nil,nil,0
local original={getID=function()return id end,getFullType=function()return kind end,
 getHungChange=function()return hunger end,getContainer=function()return container end,
 getWorldItem=function()return world end,getCurrentUses=function()return uses end}
local state={case='food-root-depletion',ids={foodId=10,foodType='Base.Cereal',foodTypeCount=1,hunger=.8,baseHunger=-.4},originalFood=original}
local value={deleted=true,foodCount=0,foodTypeCount=0,hunger=.4}
local reason,proof=Fixture.checkDeletion(state,value)
assert(not reason and proof.id==10 and proof.remaining==0 and not proof.hasContainer and not proof.hasWorldItem)
id=11;assert(Fixture.checkDeletion(state,value)=='original-id');id=10
kind='Base.Other';assert(Fixture.checkDeletion(state,value)=='original-type');kind='Base.Cereal'
hunger=-.3;assert(Fixture.checkDeletion(state,value)=='original-hunger');hunger=0
container={getItemById=function()return original end}
reason,proof=Fixture.checkDeletion(state,value)
assert(reason=='original-container' and proof.containerContainsId);container=nil
world={getSquare=function()return {} end}
reason,proof=Fixture.checkDeletion(state,value)
assert(reason=='original-world-item' and proof.worldOnSquare);world=nil
-- Native Food.setCurrentUses after Eat zeroes hunger divides 0/0 on disposal.
hunger=0/0
reason,proof=Fixture.checkDeletion(state,value)
assert(not reason and proof.remaining=='NaN' and proof.uses==0)
uses=1;assert(Fixture.checkDeletion(state,value)=='original-uses');uses=0
id=11;assert(Fixture.checkDeletion(state,value)=='original-id');id=10
container={getItemById=function()return original end}
assert(Fixture.checkDeletion(state,value)=='original-container');container=nil
world={getSquare=function()return {} end}
assert(Fixture.checkDeletion(state,value)=='original-world-item');world=nil
value.foodCount=1;assert(Fixture.checkDeletion(state,value)=='inventory-count');value.foodCount=0
value.foodTypeCount=1;assert(Fixture.checkDeletion(state,value)=='inventory-count');value.foodTypeCount=0
value.hunger=.8;assert(Fixture.checkDeletion(state,value)=='actor-hunger');value.hunger=.4
state.case='food-root-move-same-portions'
assert(Fixture.checkDeletion(state,value)=='not-depletion-case');state.case='food-root-depletion'
for _,invalid in ipairs({-.3,-.001,.001,math.huge,-math.huge})do
 hunger=invalid;assert(Fixture.checkDeletion(state,value)=='original-hunger')
end
hunger=0;value.deleted=false;assert(Fixture.checkDeletion(state,value)=='still-present')
-- The disposal exception never permits NaN/infinity on food still present in inventory.
original.getBaseHunger=function()return -.4 end
Fixture.items=function()return {food=original,anchor={},bag={}}end
local player={getInventory=function()return {}end}
for _,invalid in ipairs({0/0,math.huge,-math.huge})do
 hunger=invalid;assert(Fixture.snapshot(player,state.ids)==nil)
end

"""
        result = subprocess.run([lua, '-', str(fixture)], input=script, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_registered_sources_selected_mods_and_scope(self):
        self.assertIs(adapters.get('food'), food)
        self.assertIn('EatSmartInt', food.MODS)
        self.assertGreater(len(food.MODS), 30)
        self.assertEqual(food.CASES, [case['id'] for case in food.definitions()['food']['cases']])
        self.assertTrue(all(path.is_file() for path in food.sources(ROOT, self.selection)))
        food.validate(self.selection)
        self.selection.update(kind='mp', options={'mp_host': True})
        food.validate(self.selection)
        for key, value in [('mods', ['PZSurvivorToolkit', 'EatSmartInt']), ('cases', list(reversed(food.CASES))),
                           ('languages', ['RU']), ('clients', True), ('options', {}),
                           ('options', {'mp_host': True, 'world_template': '/tmp/stale'})]:
            wrong = copy.deepcopy(self.selection);wrong[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError): food.validate(wrong)

    def test_each_kind_and_control_has_exact_original_portion_results(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode, cases=list(food.CASES))
                result = self.verify()
                self.assertEqual([], result['issues'])
                for outcome in result['outcomes']:
                    self.assertIs(outcome['outcome']['effectsVerified'], True)
                    self.assertIs(outcome['outcome']['pendingEditsVerified'], mode == 'toolkit')
                    self.assertIs(outcome['outcome']['serverAuthorityVerified'], kind == 'mp')

    def test_server_receipts_not_client_claims_and_ordered_fresh_identities(self):
        self.selection['kind'] = 'mp'
        self.assertTrue(self.verify(wrong_authority=True)['issues'])
        for fault in ('duplicate-prep', 'duplicate-final', 'missing-final', 'case-order', 'overlap', 'complete', 'failure'):
            self.selection['cases'] = list(food.CASES)
            rows, raw = self.evidence()
            if fault == 'duplicate-prep': raw.insert(1, raw[0])
            elif fault == 'duplicate-final': raw.insert(2, raw[1])
            elif fault == 'missing-final': raw.pop()
            elif fault == 'case-order': rows[1], rows[2] = rows[2], rows[1]
            elif fault == 'overlap': raw[2][1]['foodId'] = raw[0][1]['foodId']
            elif fault == 'complete': rows[-1]['performed'] = 0
            else: rows[1]['status'] = 'failed'
            with self.subTest(fault=fault): self.assertTrue(self.verify((rows, raw))['issues'])

    def test_wrong_effects_cannot_be_hidden_by_matching_client_or_claimed_flags(self):
        for case in food.CASES:
            for field, value in [('remaining', -.23), ('remaining', -.4), ('foodCount', 2), ('deleted', True),
                                 ('foodType', 'Base.CerealBowl'), ('foodId', 999), ('baseHunger', -.2),
                                 ('hunger', .8), ('thirst', .8), ('source', 'floor'),
                                 ('anchorAmount', .48), ('anchorCount', 0)]:
                rows, raw = self.single(case)
                if field=='deleted' and case==food.DEPLETION_CASE: value=False
                for record in (rows[1], rows[1]['client'], raw[1][1]): record[field] = value
                rows[1].update(effectsVerified=True, pendingEditsVerified=True)
                with self.subTest(case=case, field=field, value=value):
                    self.assertTrue(self.verify((rows, raw))['issues'])
            rows, raw = self.single(case)
            rows[1]['client']['remaining'] += .01
            self.assertTrue(self.verify((rows, raw))['issues'])

    def test_water_property_is_remaining_aggregate_while_prepared_coefficient_sets_cost(self):
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for amount in (.5, .4971739, .49, .5001):
                rows, raw = self.single()
                prep = raw[0][1]
                for record in (rows[1], rows[1]['client'], raw[1][1]):
                    record.update(anchorAmount=amount, anchorThirstChange=prep['anchorThirstChange'] * amount,
                                  thirst=prep['thirst'] + (1 - amount) * prep['anchorThirstChange'])
                with self.subTest(kind=kind, amount=amount): self.assertEqual([], self.verify((rows, raw))['issues'])
            for value in (-.5, -.125, .25, 0, True, float('nan'), None):
                rows, raw = self.single()
                for record in (rows[1], rows[1]['client'], raw[1][1]): record['anchorThirstChange'] = value
                with self.subTest(kind=kind, value=value): self.assertTrue(self.verify((rows, raw))['issues'])
            rows, raw = self.single();raw[1][1].pop('anchorThirstChange')
            self.assertTrue(self.verify((rows, raw))['issues'])
            rows, raw = self.single()
            for record in (rows[1], rows[1]['client'], raw[1][1]): record['thirst'] = .675
            self.assertTrue(self.verify((rows, raw))['issues'], 'current aggregate must not become the initial debit coefficient')

    def test_every_native_command_field_and_boolean_type_is_required(self):
        for case in food.CASES:
            for field in food.COMMAND_KEYS:
                rows, raw = self.single(case)
                del rows[1]['commands'][0][field]
                with self.subTest(case=case, field=field): self.assertTrue(self.verify((rows, raw))['issues'])
            for field in ('progress', 'cancelled', 'pickupObserved', 'menuDispatched'):
                for wrong in (None, 'true', 1):
                    rows, raw = self.single(case);rows[1]['commands'][0][field] = wrong
                    with self.subTest(case=case, field=field, wrong=wrong): self.assertTrue(self.verify((rows, raw))['issues'])
        for field, value in [('portion', .75), ('nativeDuration', 1), ('id', 105), ('dispatchRemaining', -.2),
                             ('baseHunger', -.2), ('dispatchSource', 'bag'), ('progress', False)]:
            rows, raw = self.single();rows[1]['commands'][0][field] = value
            with self.subTest(field=field): self.assertTrue(self.verify((rows, raw))['issues'])

    def test_pending_edit_flags_order_and_transfer_boundaries_are_decisive(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                for case in food.CASES:
                    for field in food.FLAGS:
                        rows, raw = self.single(case);del rows[1]['editEvidence'][field]
                        with self.subTest(kind=kind, mode=mode, case=case, field=field): self.assertTrue(self.verify((rows, raw))['issues'])
                    rows, raw = self.single(case);rows[1]['editEvidence']['anchorRunning'] = 1
                    self.assertTrue(self.verify((rows, raw))['issues'])
                for field, value in [('boundary', False), ('completed', False), ('observationFailed', True),
                                     ('before', 'unknown'), ('after', 'root'), ('started', True),
                                     ('transactionId', True), ('dontAdd', 1)]:
                    rows, raw = self.single(food.BAG_CASE);rows[1]['editEvidence']['returning'][field] = value
                    with self.subTest(kind=kind, mode=mode, field=field): self.assertTrue(self.verify((rows, raw))['issues'])
                for field in ('pickupDuration', 'returnDuration'):
                    rows, raw = self.single(food.BAG_CASE);rows[1]['editEvidence'][field] = 0
                    self.assertTrue(self.verify((rows, raw))['issues'])
                rows, raw = self.single(food.BAG_CASE);rows[1]['client']['source'] = 'bag' if mode == 'toolkit' else 'root'
                self.assertTrue(self.verify((rows, raw))['issues'])

    def test_full_after_quarter_deletes_only_the_exact_original_and_denies_reorder(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                rows, raw = self.single(food.DEPLETION_CASE)
                self.assertEqual([], self.verify((rows, raw))['issues'])
                self.assertEqual([.25, 1], [value['portion'] for value in rows[1]['commands']])
                self.assertEqual([232, 464], [value['nativeDuration'] for value in rows[1]['commands']])
                self.assertEqual([1, 2], rows[1]['editEvidence']['order'])
                self.assertIs(rows[1]['editEvidence']['moveRejected'], mode == 'toolkit')
                self.assertEqual((0, 0, True, 'deleted'), tuple(raw[1][1][key] for key in
                                 ('remaining', 'foodCount', 'deleted', 'source')))
                for field, value in [('foodCount', 1), ('foodTypeCount', 1), ('deleted', False),
                                     ('foodId', 999), ('foodType', 'Base.CerealBowl'), ('remaining', -.3),
                                     ('source', 'root'), ('hunger', .3)]:
                    rows, raw = self.single(food.DEPLETION_CASE)
                    for record in (rows[1], rows[1]['client'], raw[1][1]): record[field] = value
                    with self.subTest(kind=kind, mode=mode, field=field):
                        self.assertTrue(self.verify((rows, raw))['issues'])
                for fault in ('wrong-reason', 'missing-reason', 'full-first', 'wrong-full-duration',
                              'wrong-id', 'not-started', 'missing-command', 'accepted-reorder', 'client-food-present'):
                    rows, raw = self.single(food.DEPLETION_CASE)
                    if fault == 'wrong-reason': rows[1]['editEvidence']['denialReason'] = 'edit_required_state'
                    elif fault == 'missing-reason': rows[1]['editEvidence'].pop('denialReason')
                    elif fault == 'full-first': rows[1]['editEvidence']['order'] = [2, 1]
                    elif fault == 'wrong-full-duration': rows[1]['commands'][1]['nativeDuration'] = 232
                    elif fault == 'wrong-id': rows[1]['commands'][1]['id'] = raw[0][1]['anchorId']
                    elif fault == 'not-started': rows[1]['commands'][1]['progress'] = False
                    elif fault == 'missing-command': rows[1]['commands'].pop()
                    elif fault == 'accepted-reorder': rows[1]['editEvidence']['reordered'] = True
                    else: rows[1]['client']['foodCount'] = 1
                    with self.subTest(kind=kind, mode=mode, fault=fault):
                        self.assertTrue(self.verify((rows, raw))['issues'])

    def test_smart_portions_use_public_goals_and_original_food_not_remaining(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                for case in food.SMART_CASES:
                    rows, raw = self.single(case)
                    self.assertEqual([], self.verify((rows, raw))['issues'])
                    self.assertEqual([.125, .375], [c['portion'] for c in rows[1]['commands']])
                    self.assertEqual([15, 5], [c['smartGoal'] for c in rows[1]['commands']])
                    expected = -.15 if mode == 'toolkit' and case == food.SMART_CANCEL_CASE else -.1
                    self.assertAlmostEqual(expected, raw[1][1]['remaining'])
                    for fault in ('missing-goal', 'wrong-goal', 'boolean-goal', 'string-goal',
                                  'missing-hunger', 'boolean-hunger', 'unrelated-hunger', 'wrong-formula',
                                  'remainder-fraction', 'double-fraction', 'fake-menu', 'fake-action',
                                  'not-started', 'wrong-order', 'wrong-effect'):
                        rows, raw = self.single(case)
                        command = rows[1]['commands'][1]
                        if fault == 'missing-goal': command.pop('smartGoal')
                        elif fault == 'wrong-goal': command['smartGoal'] = 15
                        elif fault == 'boolean-goal': command['smartGoal'] = True
                        elif fault == 'string-goal': command['smartGoal'] = '5'
                        elif fault == 'missing-hunger': command.pop('dispatchHunger')
                        elif fault == 'boolean-hunger': command['dispatchHunger'] = True
                        elif fault == 'unrelated-hunger': command['dispatchHunger'] = .7
                        elif fault == 'wrong-formula': command['portion'] += .00001
                        elif fault == 'remainder-fraction': command['portion'] = .5
                        elif fault == 'double-fraction':
                            for record in (rows[1], rows[1]['client'], raw[1][1]):
                                record['remaining'] = -.3 + .3 * (.375 if mode == 'toolkit' and case == food.SMART_CANCEL_CASE else .5)
                        elif fault == 'fake-menu': command['menuDispatched'] = False
                        elif fault == 'fake-action': command['nativeDuration'] = 1
                        elif fault == 'not-started': command['progress'] = False
                        elif fault == 'wrong-order': rows[1]['editEvidence']['order'] = [1]
                        else:
                            for record in (rows[1], rows[1]['client'], raw[1][1]): record['hunger'] += .1
                        with self.subTest(kind=kind, mode=mode, case=case, fault=fault):
                            self.assertTrue(self.verify((rows, raw))['issues'])

    def test_smart_native_float_and_hunger_drift_keep_measured_original_fractions(self):
        for mode in ('native', 'toolkit'):
            self.selection['mode'] = mode
            for case in food.SMART_CASES:
                rows, raw = self.single(case)
                for command in rows[1]['commands']:
                    command['dispatchHunger'] += .0002
                    command['portion'] = (command['dispatchHunger'] - command['smartGoal'] / 100) / .4 + .00000001
                portions = sum(command['portion'] for index, command in enumerate(rows[1]['commands'])
                               if not (mode == 'toolkit' and case == food.SMART_CANCEL_CASE and index == 0))
                for record in (rows[1], rows[1]['client'], raw[1][1]):
                    record.update(remaining=-.3 + .4 * portions, hunger=.2 - .4 * portions)
                self.assertEqual([], self.verify((rows, raw))['issues'])

    def test_utensil_contract_keeps_captured_bag_tool_and_native_duration(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                for case in food.UTENSIL_CASES:
                    rows, raw = self.single(case)
                    self.assertEqual([], self.verify((rows, raw))['issues'])
                    prep, receipt = raw[0][1], raw[1][1]
                    self.assertEqual([.625, .125], [c['portion'] for c in rows[1]['commands']])
                    self.assertEqual([232, 232], [c['nativeDuration'] for c in rows[1]['commands']])
                    selected = 'forkId' if case == food.UTENSIL_MOVE_CASE else 'spoonId'
                    self.assertEqual('bag', prep[selected.replace('Id', 'Source')])
                    self.assertEqual([prep[selected]] * 2, [c['utensilId'] for c in rows[1]['commands']])
                    cancelled = mode == 'toolkit' and case == food.UTENSIL_CANCEL_CASE
                    self.assertAlmostEqual(-.4375 if cancelled else -.125, receipt['remaining'])
                    self.assertAlmostEqual(.7375 if cancelled else .425, receipt['hunger'])
                    self.assertEqual([2] if cancelled else [2, 1] if mode == 'toolkit' else [1, 2],
                                     rows[1]['editEvidence']['order'])
                    for field in food.UTENSIL_RECEIPT_KEYS:
                        self.assertEqual(prep[field], receipt[field])
                        rows, raw = self.single(case)
                        raw[1][1].pop(field)
                        with self.subTest(kind=kind, mode=mode, case=case, missing=field):
                            self.assertTrue(self.verify((rows, raw))['issues'])
                    for field in food.UTENSIL_COMMAND_KEYS:
                        rows, raw = self.single(case)
                        rows[1]['commands'][0].pop(field)
                        with self.subTest(kind=kind, mode=mode, case=case, missing=field):
                            self.assertTrue(self.verify((rows, raw))['issues'])

    def test_utensil_identity_selection_condition_and_conservation_tampering_is_rejected(self):
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for case in food.UTENSIL_CASES:
                for field, wrong in [('forkType', 'Base.Spoon'), ('spoonType', 'Base.Fork'),
                                     ('forkSource', 'floor'), ('spoonSource', 'floor'),
                                     ('forkCondition', 0 if case == food.UTENSIL_MOVE_CASE else 1),
                                     ('spoonCondition', 0), ('forkCount', 2), ('spoonCount', 0),
                                     ('forkId', 999), ('spoonId', 999),
                                     ('remaining', -.4), ('hunger', .8), ('foodCount', 0)]:
                    rows, raw = self.single(case)
                    for record in (rows[1], rows[1]['client'], raw[1][1]): record[field] = wrong
                    with self.subTest(kind=kind, case=case, field=field):
                        self.assertTrue(self.verify((rows, raw))['issues'])
                for field, wrong in [('useUtensil', False), ('useUtensil', 1), ('useUtensil', 'true'),
                                     ('utensilId', 999), ('forkId', 999), ('spoonId', -1),
                                     ('nativeDuration', 464), ('pickupObserved', True), ('portion', .5)]:
                    rows, raw = self.single(case)
                    rows[1]['commands'][0][field] = wrong
                    with self.subTest(kind=kind, case=case, field=field, wrong=wrong):
                        self.assertTrue(self.verify((rows, raw))['issues'])
                rows, raw = self.single(case)
                command = rows[1]['commands'][0]
                command['utensilId'] = raw[0][1]['spoonId' if case == food.UTENSIL_MOVE_CASE else 'forkId']
                self.assertTrue(self.verify((rows, raw))['issues'], 'native selector must retain the captured valid bag tool')
                rows, raw = self.single(case)
                rows[1]['commands'][0]['forkId'] = -1 if case == food.UTENSIL_MOVE_CASE else raw[0][1]['forkId']
                self.assertTrue(self.verify((rows, raw))['issues'], 'constructor fork ref must exclude the broken fork')
                for field in ('forkId', 'spoonId', 'forkCondition', 'spoonCondition', 'forkSource', 'spoonSource'):
                    rows, raw = self.single(case)
                    rows[1]['client'][field] = 999
                    with self.subTest(kind=kind, case=case, client_only=field):
                        self.assertTrue(self.verify((rows, raw))['issues'])
                for field, wrong in [('forkCondition', True), ('spoonCondition', 0),
                                     ('forkSource', 'root' if case == food.UTENSIL_MOVE_CASE else 'bag'),
                                     ('spoonSource', 'bag' if case == food.UTENSIL_MOVE_CASE else 'root'),
                                     ('forkCount', True), ('spoonId', 100)]:
                    rows, raw = self.single(case)
                    for record in (raw[0][1], rows[1], rows[1]['client'], raw[1][1]): record[field] = wrong
                    with self.subTest(kind=kind, case=case, prepared=field):
                        self.assertTrue(self.verify((rows, raw))['issues'])

    def test_utensil_fields_are_only_accepted_for_registered_utensil_cases(self):
        for case in (food.MOVE_CASE, food.SMART_MOVE_CASE):
            for field in food.UTENSIL_RECEIPT_KEYS:
                rows, raw = self.single(case)
                for record in (raw[0][1], rows[1], rows[1]['client'], raw[1][1]): record[field] = 1
                with self.subTest(case=case, receipt=field): self.assertTrue(self.verify((rows, raw))['issues'])
                rows, raw = self.single(case); rows[1][field] = 1
                with self.subTest(case=case, row_only=field): self.assertTrue(self.verify((rows, raw))['issues'])
            for field in food.UTENSIL_COMMAND_KEYS:
                rows, raw = self.single(case); rows[1]['commands'][0][field] = 1
                with self.subTest(case=case, command=field): self.assertTrue(self.verify((rows, raw))['issues'])

    def test_cancelled_first_portion_never_started_or_consumed(self):
        for mode in ('native', 'toolkit'):
            self.selection['mode'] = mode
            for field in ('cancelled', 'progress'):
                rows, raw = self.single(food.CANCEL_CASE)
                rows[1]['commands'][0][field] = not rows[1]['commands'][0][field]
                self.assertTrue(self.verify((rows, raw))['issues'])
            rows, raw = self.single(food.CANCEL_CASE)
            rows[1]['editEvidence']['order'] = [1, 2] if mode == 'toolkit' else [2]
            self.assertTrue(self.verify((rows, raw))['issues'])

    def test_cookable_food_preserves_raw_remaining_and_native_cooked_hunger(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                for case in food.COOKABLE_CASES:
                    rows, raw = self.single(case)
                    prep, receipt = raw[0][1], raw[1][1]
                    cooked = case in (food.COOKED_MOVE_CASE, food.COOKED_CANCEL_CASE)
                    cancelled = mode == 'toolkit' and case in (food.COOKED_CANCEL_CASE, food.RAW_CANCEL_CASE)
                    portion = .25 if cancelled else .75
                    with self.subTest(kind=kind, mode=mode, case=case):
                        self.assertEqual([], self.verify((rows, raw))['issues'])
                        self.assertEqual('Base.ChickenFillet' if cooked else 'Base.Cabbage', prep['foodType'])
                        self.assertAlmostEqual(-.3 if cooked else -.24, prep['baseHunger'])
                        self.assertAlmostEqual(prep['baseHunger'] * (1 - portion), receipt['remaining'])
                        self.assertAlmostEqual(.8 + prep['baseHunger'] * portion * (1.3 if cooked else 1), receipt['hunger'])
                        self.assertAlmostEqual(.55 - (.1 * portion if not cooked else 0), receipt['thirst'])
                        self.assertEqual([.5, .25], [c['portion'] for c in rows[1]['commands']])
                        self.assertEqual([232, 232], [c['nativeDuration'] for c in rows[1]['commands']])
                        self.assertEqual([2] if cancelled else [2, 1] if mode == 'toolkit' else [1, 2], rows[1]['editEvidence']['order'])
                    for heat in (0, .2, .7, 1.6):
                        rows, raw = self.single(case)
                        for record in (rows[1], rows[1]['client'], raw[1][1]): record['heat'] = heat
                        for command in rows[1]['commands']: command['dispatchHeat'] = heat
                        with self.subTest(kind=kind, mode=mode, case=case, heat=heat):
                            self.assertEqual([], self.verify((rows, raw))['issues'])

    def test_native_cabbage_thirst_requires_exact_consumed_original_fraction(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                for case in (food.RAW_MOVE_CASE, food.RAW_CANCEL_CASE):
                    portion = .25 if mode == 'toolkit' and case == food.RAW_CANCEL_CASE else .75
                    for debit in (0, .1 * portion * 2):
                        rows, raw = self.single(case)
                        for record in (rows[1], rows[1]['client'], raw[1][1]): record['thirst'] = .55 - debit
                        with self.subTest(kind=kind, mode=mode, case=case, debit=debit):
                            self.assertTrue(self.verify((rows, raw))['issues'])

    def test_cookable_state_flags_and_temperature_cannot_be_forged(self):
        for case in (*food.COOKABLE_CASES, *food.REPLACEMENT_CASES):
            cooked = case in (food.COOKED_MOVE_CASE, food.COOKED_CANCEL_CASE)
            for field, wrong in [('cookable', False), ('cooked', not cooked), ('burnt', True),
                                 ('rotten', True), ('fertilized', True), ('inventoryTemperature', 1.01),
                                 ('inventoryTemperature', True), ('heat', -1), ('heat', 1.6001),
                                 ('heat', True), ('heat', float('nan')), ('heat', float('inf'))]:
                rows, raw = self.single(case)
                for record in (rows[1], rows[1]['client'], raw[1][1]): record[field] = wrong
                with self.subTest(case=case, field=field, wrong=wrong):
                    self.assertTrue(self.verify((rows, raw))['issues'])
            for field in food.COOKABLE_RECEIPT_KEYS:
                for location in ('prepared', 'receipt', 'row', 'client'):
                    rows, raw = self.single(case)
                    record = {'prepared': raw[0][1], 'receipt': raw[1][1], 'row': rows[1], 'client': rows[1]['client']}[location]
                    record.pop(field)
                    with self.subTest(case=case, missing=field, location=location):
                        self.assertTrue(self.verify((rows, raw))['issues'])
                if field in ('cookable', 'cooked', 'burnt', 'rotten', 'fertilized'):
                    for wrong in (0, 1, 'true', None):
                        rows, raw = self.single(case)
                        for record in (raw[0][1], rows[1], rows[1]['client'], raw[1][1]): record[field] = wrong
                        with self.subTest(case=case, field=field, wrong=wrong):
                            self.assertTrue(self.verify((rows, raw))['issues'])
            for field, wrong in [('heat', .9), ('inventoryTemperature', .9), ('cooked', not cooked),
                                 ('cookable', False), ('burnt', True), ('rotten', True), ('fertilized', True),
                                 ('foodType', 'Base.Cereal'), ('baseHunger', -.4)]:
                rows, raw = self.single(case)
                raw[0][1][field] = wrong
                with self.subTest(case=case, prepared=field):
                    self.assertTrue(self.verify((rows, raw))['issues'])
            rows, raw = self.single(case)
            rows[1]['client']['heat'] = .5
            self.assertTrue(self.verify((rows, raw))['issues'])

    def test_cookable_hunger_portion_duration_and_command_state_are_strict(self):
        for mode in ('native', 'toolkit'):
            self.selection['mode'] = mode
            for case in (*food.COOKABLE_CASES, *food.REPLACEMENT_CASES):
                cooked = case in (food.COOKED_MOVE_CASE, food.COOKED_CANCEL_CASE)
                for field, wrong in [('cooked', not cooked), ('cooked', 1), ('cooked', 'true'),
                                     ('dispatchHeat', -.001), ('dispatchHeat', 1.6001), ('dispatchHeat', True),
                                     ('dispatchHeat', float('nan')), ('dispatchHeat', float('inf')),
                                     ('portion', .25), ('nativeDuration', 464), ('menuDispatched', False),
                                     ('pickupObserved', True)]:
                    rows, raw = self.single(case)
                    rows[1]['commands'][0][field] = wrong
                    with self.subTest(mode=mode, case=case, field=field, wrong=wrong):
                        self.assertTrue(self.verify((rows, raw))['issues'])
                for field in food.COOKABLE_COMMAND_KEYS:
                    rows, raw = self.single(case)
                    rows[1]['commands'][0].pop(field)
                    with self.subTest(mode=mode, case=case, missing=field):
                        self.assertTrue(self.verify((rows, raw))['issues'])
                for fault in ('wrong-hunger-multiplier', 'cooked-multiplier-on-remaining', 'remaining-fraction'):
                    rows, raw = self.single(case)
                    prep = raw[0][1]
                    portion = .25 if mode == 'toolkit' and case in (food.COOKED_CANCEL_CASE, food.RAW_CANCEL_CASE, food.REPLACEMENT_CANCEL_CASE) else .75
                    for record in (rows[1], rows[1]['client'], raw[1][1]):
                        if fault == 'wrong-hunger-multiplier':
                            # Bread's quarter portion needs a larger wrong debit to exceed native actor drift tolerance.
                            multiplier = 2 if case in food.REPLACEMENT_CASES else 1 if cooked else 1.3
                            record['hunger'] = .8 + prep['baseHunger'] * portion * multiplier
                        elif fault == 'cooked-multiplier-on-remaining':
                            record['remaining'] = prep['baseHunger'] * (1 - portion) * 1.3
                        else:
                            record['remaining'] = prep['baseHunger'] * .5 * .75
                    with self.subTest(mode=mode, case=case, fault=fault):
                        self.assertTrue(self.verify((rows, raw))['issues'])

    def test_cold_cooking_replacement_preserves_original_bread_and_existing_toast_count(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                for case in food.REPLACEMENT_CASES:
                    rows, raw = self.single(case)
                    prep, receipt = raw[0][1], raw[1][1]
                    cancelled = mode == 'toolkit' and case == food.REPLACEMENT_CANCEL_CASE
                    with self.subTest(kind=kind, mode=mode, case=case):
                        self.assertEqual([], self.verify((rows, raw))['issues'])
                        self.assertEqual('Base.BreadSlices', prep['foodType'])
                        self.assertEqual(prep['foodId'], receipt['foodId'])
                        self.assertEqual((1, 1, False), (receipt['foodCount'], receipt['foodTypeCount'], receipt['deleted']))
                        self.assertAlmostEqual(-.075 if cancelled else -.025, receipt['remaining'])
                        self.assertAlmostEqual(.775 if cancelled else .725, receipt['hunger'])
                        self.assertAlmostEqual(.55, receipt['thirst'])
                        self.assertEqual([.5, .25], [c['portion'] for c in rows[1]['commands']])
                        self.assertEqual([232, 232], [c['nativeDuration'] for c in rows[1]['commands']])
                        self.assertEqual([2] if cancelled else [2, 1] if mode == 'toolkit' else [1, 2], rows[1]['editEvidence']['order'])
                        self.assertEqual(('Base.Toast', 0, 0), tuple(receipt[key] for key in ('replacementType', 'replacementCount', 'cookingTime')))
                    for record in (prep, rows[1], rows[1]['client'], receipt): record['replacementCount'] = 3
                    self.assertEqual([], self.verify((rows, raw))['issues'], 'preexisting Toast must be conserved')

    def test_cooking_replacement_evidence_cannot_hide_replacement_or_cooking(self):
        for case in food.REPLACEMENT_CASES:
            for field, wrong in [('replacementType', 'Base.BreadSlices'), ('replacementType', False),
                                 ('replacementCount', -1), ('replacementCount', True), ('replacementCount', 0.0),
                                 ('replacementCount', '0'), ('cookingTime', .00001), ('cookingTime', True),
                                 ('cookingTime', '0'), ('cookingTime', float('nan'))]:
                rows, raw = self.single(case)
                for record in (raw[0][1], rows[1], rows[1]['client'], raw[1][1]): record[field] = wrong
                with self.subTest(case=case, field=field, wrong=wrong):
                    self.assertTrue(self.verify((rows, raw))['issues'])
            for field, wrong in [('foodId', 999), ('foodType', 'Base.Toast'), ('foodCount', 0),
                                 ('foodTypeCount', 0), ('deleted', True), ('replacementCount', 1),
                                 ('replacementType', 'Base.Cereal'), ('cookingTime', 1),
                                 ('hunger', .7025), ('remaining', -.0325), ('thirst', .475)]:
                rows, raw = self.single(case)
                for record in (rows[1], rows[1]['client'], raw[1][1]): record[field] = wrong
                with self.subTest(case=case, effect=field):
                    self.assertTrue(self.verify((rows, raw))['issues'])
            for field in food.REPLACEMENT_RECEIPT_KEYS:
                for location in ('prepared', 'receipt', 'row', 'client'):
                    rows, raw = self.single(case)
                    record = {'prepared': raw[0][1], 'receipt': raw[1][1], 'row': rows[1], 'client': rows[1]['client']}[location]
                    record.pop(field)
                    with self.subTest(case=case, location=location, missing=field):
                        self.assertTrue(self.verify((rows, raw))['issues'])
            for field in ('replacementType', 'replacementCount', 'cookingTime'):
                rows, raw = self.single(case)
                rows[1]['commands'][0][field] = 0
                with self.subTest(case=case, extra_command=field): self.assertTrue(self.verify((rows, raw))['issues'])

    def test_cooking_replacement_receipt_fields_are_only_accepted_for_replacement_cases(self):
        for case in (food.MOVE_CASE, food.SMART_MOVE_CASE, food.UTENSIL_MOVE_CASE, food.RAW_MOVE_CASE):
            for field in food.REPLACEMENT_RECEIPT_KEYS:
                for location in ('prepared', 'receipt', 'row', 'client'):
                    rows, raw = self.single(case)
                    record = {'prepared': raw[0][1], 'receipt': raw[1][1], 'row': rows[1], 'client': rows[1]['client']}[location]
                    record[field] = 0
                    with self.subTest(case=case, extra=field, location=location):
                        self.assertTrue(self.verify((rows, raw))['issues'])

    def test_consumption_replacement_retains_exact_food_partial_weight_and_empty_can_count(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                for case in food.CONSUMPTION_CASES:
                    rows, raw = self.single(case)
                    prep, receipt = raw[0][1], raw[1][1]
                    cancelled = mode == 'toolkit' and case == food.CONSUMPTION_CANCEL_CASE
                    with self.subTest(kind=kind, mode=mode, case=case):
                        self.assertEqual([], self.verify((rows, raw))['issues'])
                        self.assertEqual('Base.CannedPeachesOpen', prep['foodType'])
                        self.assertAlmostEqual(-.15, prep['baseHunger'])
                        self.assertAlmostEqual(.8, prep['foodWeight'])
                        self.assertEqual(prep['foodId'], receipt['foodId'])
                        self.assertEqual((1, 1, False), (receipt['foodCount'], receipt['foodTypeCount'], receipt['deleted']))
                        self.assertAlmostEqual(.65 if cancelled else .35, receipt['foodWeight'])
                        self.assertAlmostEqual(-.1125 if cancelled else -.0375, receipt['remaining'])
                        self.assertAlmostEqual(.7625 if cancelled else .6875, receipt['hunger'])
                        self.assertAlmostEqual(.55, receipt['thirst'])
                        self.assertEqual([.5, .25], [c['portion'] for c in rows[1]['commands']])
                        self.assertEqual([232, 232], [c['nativeDuration'] for c in rows[1]['commands']])
                        self.assertTrue(all(set(c) == food.COMMAND_KEYS for c in rows[1]['commands']))
                        self.assertEqual([2] if cancelled else [2, 1] if mode == 'toolkit' else [1, 2], rows[1]['editEvidence']['order'])
                        self.assertEqual(('Base.TinCanEmpty', 0, False, False), tuple(receipt[key] for key in
                                         ('consumptionReplacementType', 'consumptionReplacementCount', 'customWeight', 'extraItems')))
                    for record in (prep, rows[1], rows[1]['client'], receipt): record['consumptionReplacementCount'] = 3
                    self.assertEqual([], self.verify((rows, raw))['issues'], 'preexisting empty cans must be conserved')
                    for delta in (-.000009, .000009):
                        rows, raw = self.single(case)
                        for record in (rows[1], rows[1]['client'], raw[1][1]): record['foodWeight'] += delta
                        self.assertEqual([], self.verify((rows, raw))['issues'], 'native float drift within 1e-5 is allowed')

    def test_consumption_replacement_rejects_wrong_weight_flags_output_and_count(self):
        for mode in ('native', 'toolkit'):
            self.selection['mode'] = mode
            for case in food.CONSUMPTION_CASES:
                for field, wrong in [('consumptionReplacementType', 'Base.Toast'), ('consumptionReplacementType', False),
                                     ('consumptionReplacementCount', -1), ('consumptionReplacementCount', True),
                                     ('consumptionReplacementCount', 0.0), ('consumptionReplacementCount', '0'),
                                     ('customWeight', True), ('customWeight', 0), ('customWeight', 'false'),
                                     ('extraItems', True), ('extraItems', 0), ('extraItems', 'false'),
                                     ('foodWeight', .79), ('foodWeight', True), ('foodWeight', '.8'),
                                     ('foodWeight', float('nan')), ('foodWeight', float('inf'))]:
                    rows, raw = self.single(case)
                    for record in (raw[0][1], rows[1], rows[1]['client'], raw[1][1]): record[field] = wrong
                    with self.subTest(mode=mode, case=case, field=field, wrong=wrong):
                        self.assertTrue(self.verify((rows, raw))['issues'])
                cancelled = mode == 'toolkit' and case == food.CONSUMPTION_CANCEL_CASE
                weight = .65 if cancelled else .35
                for field, wrong in [('consumptionReplacementCount', 1), ('consumptionReplacementCount', True),
                                     ('consumptionReplacementCount', 0.0), ('foodWeight', weight + .00002),
                                     ('foodWeight', weight - .00002), ('foodWeight', .8),
                                     ('foodWeight', .8 * (.75 if cancelled else .25)),
                                     ('foodType', 'Base.TinCanEmpty'), ('foodId', 999), ('foodCount', 0),
                                     ('foodTypeCount', 0), ('deleted', True), ('hunger', .8), ('thirst', .475)]:
                    rows, raw = self.single(case)
                    for record in (rows[1], rows[1]['client'], raw[1][1]): record[field] = wrong
                    with self.subTest(mode=mode, case=case, effect=field, wrong=wrong):
                        self.assertTrue(self.verify((rows, raw))['issues'])
                for field in food.CONSUMPTION_RECEIPT_KEYS:
                    for location in ('prepared', 'receipt', 'row', 'client'):
                        rows, raw = self.single(case)
                        record = {'prepared': raw[0][1], 'receipt': raw[1][1], 'row': rows[1], 'client': rows[1]['client']}[location]
                        record.pop(field)
                        with self.subTest(mode=mode, case=case, location=location, missing=field):
                            self.assertTrue(self.verify((rows, raw))['issues'])
                for index in (0, 1):
                    for field, wrong in [('portion', .75), ('nativeDuration', 464), ('id', 999),
                                         ('menuDispatched', False), ('pickupObserved', True)]:
                        rows, raw = self.single(case)
                        rows[1]['commands'][index][field] = wrong
                        with self.subTest(mode=mode, case=case, index=index, field=field):
                            self.assertTrue(self.verify((rows, raw))['issues'])
                rows, raw = self.single(case)
                rows[1]['client']['foodWeight'] = weight + .00002
                self.assertTrue(self.verify((rows, raw))['issues'])
                for commands in ([], [0], [0, 1, 0]):
                    rows, raw = self.single(case)
                    originals = rows[1]['commands']
                    rows[1]['commands'] = [copy.deepcopy(originals[index]) for index in commands]
                    with self.subTest(mode=mode, case=case, command_count=len(commands)):
                        self.assertTrue(self.verify((rows, raw))['issues'])

    def test_consumption_replacement_schema_stays_separate_from_other_food_contracts(self):
        for case in (food.MOVE_CASE, food.SMART_MOVE_CASE, food.UTENSIL_MOVE_CASE, food.RAW_MOVE_CASE, food.REPLACEMENT_MOVE_CASE):
            for field in food.CONSUMPTION_RECEIPT_KEYS:
                for location in ('prepared', 'receipt', 'row', 'client'):
                    rows, raw = self.single(case)
                    record = {'prepared': raw[0][1], 'receipt': raw[1][1], 'row': rows[1], 'client': rows[1]['client']}[location]
                    record[field] = 0
                    with self.subTest(case=case, extra=field, location=location):
                        self.assertTrue(self.verify((rows, raw))['issues'])
        for case in food.CONSUMPTION_CASES:
            for field in food.COOKABLE_RECEIPT_KEYS | food.REPLACEMENT_RECEIPT_KEYS | food.UTENSIL_RECEIPT_KEYS:
                rows, raw = self.single(case)
                for record in (raw[0][1], rows[1], rows[1]['client'], raw[1][1]): record[field] = 0
                with self.subTest(case=case, extra_receipt=field): self.assertTrue(self.verify((rows, raw))['issues'])
            for field in food.CONSUMPTION_RECEIPT_KEYS | food.COOKABLE_COMMAND_KEYS | food.UTENSIL_COMMAND_KEYS:
                rows, raw = self.single(case)
                rows[1]['commands'][0][field] = 0
                with self.subTest(case=case, extra_command=field): self.assertTrue(self.verify((rows, raw))['issues'])

    def test_custom_weight_portions_keep_native_actual_weight_and_output_count(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                for case in food.CUSTOM_WEIGHT_CASES:
                    self.selection.update(kind=kind, mode=mode)
                    rows, raw = self.single(case)
                    with self.subTest(kind=kind, mode=mode, case=case):
                        self.assertEqual([], self.verify((rows, raw))['issues'])
                        self.assertTrue(raw[0][1]['customWeight'])
                        self.assertEqual(1.1, raw[1][1]['foodWeight'])
                        self.assertEqual(0, raw[1][1]['consumptionReplacementCount'])
                        cancelled = mode == 'toolkit' and case == food.CUSTOM_WEIGHT_CANCEL_CASE
                        self.assertEqual([2] if cancelled else [2, 1] if mode == 'toolkit' else [1, 2],
                                         rows[1]['editEvidence']['order'])
                    # A nominal script weight or a proportionally reduced weight
                    # would conceal the actual native custom-weight branch.
                    for field, wrong in (('foodWeight', .35), ('foodWeight', .8), ('foodWeight', float('nan')),
                                         ('customWeight', False), ('extraItems', True),
                                         ('consumptionReplacementCount', 1), ('foodId', 999)):
                        rows, raw = self.single(case)
                        for record in (rows[1], rows[1]['client'], raw[1][1]):
                            record[field] = wrong
                        with self.subTest(kind=kind, mode=mode, case=case, field=field, wrong=wrong):
                            self.assertTrue(self.verify((rows, raw))['issues'])
                    rows, raw = self.single(case)
                    rows[1]['client']['foodWeight'] = .8
                    self.assertTrue(self.verify((rows, raw))['issues'])
                    if kind == 'mp':
                        rows, raw = self.single(case)
                        self.assertTrue(self.verify((rows, raw), wrong_authority=True)['issues'])

    def test_cookable_fields_are_only_accepted_for_registered_cookable_cases(self):
        for case in (food.MOVE_CASE, food.SMART_MOVE_CASE, food.UTENSIL_MOVE_CASE):
            for field in food.COOKABLE_RECEIPT_KEYS:
                rows, raw = self.single(case)
                for record in (raw[0][1], rows[1], rows[1]['client'], raw[1][1]): record[field] = 1
                with self.subTest(case=case, receipt=field): self.assertTrue(self.verify((rows, raw))['issues'])
                rows, raw = self.single(case); rows[1][field] = 1
                with self.subTest(case=case, row_only=field): self.assertTrue(self.verify((rows, raw))['issues'])
            for field in food.COOKABLE_COMMAND_KEYS:
                rows, raw = self.single(case); rows[1]['commands'][0][field] = 1
                with self.subTest(case=case, command=field): self.assertTrue(self.verify((rows, raw))['issues'])


if __name__ == '__main__':
    unittest.main()
