"""Reject invented native-food progress, wrong portions and client-only effects."""
import copy
import json
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
            cancel = case == food.CANCEL_CASE and enabled
            base = 100 + 10 * index
            prep = dict(case=case, bagId=base, bagType='Base.Bag_ALICEpack_Army', bagCount=1,
                        foodId=base + 1, foodType='Base.Cereal', baseHunger=-.4, remaining=-.4,
                        source='bag' if bag else 'root', foodCount=1, foodTypeCount=1, deleted=False,
                        anchorId=base + 2, anchorType='Base.WaterBottle', anchorAmount=1.0,
                        anchorCount=1, anchorThirstChange=-.5, hunger=.8, thirst=.8, foodTimer=0, foodLevel=0)
            fraction = 1 if depletion else .5 if bag else .25 if cancel else .75
            receipt = {key: value for key, value in prep.items() if key in food.RECEIPT_KEYS}
            receipt.update(remaining=-.4 * (1 - fraction), source='deleted' if depletion else 'root' if not bag or enabled else 'bag',
                           foodCount=0 if depletion else 1, foodTypeCount=0 if depletion else 1, deleted=depletion,
                           anchorAmount=.5, anchorThirstChange=-.25, hunger=.8 - .4 * fraction, thirst=.55)
            commands = [dict(id=base + 1, portion=portion, baseHunger=-.4, dispatchRemaining=-.4,
                             dispatchSource=prep['source'], menuDispatched=not bag, nativeDuration=464 if portion == 1 else 232,
                             progress=not (cancel and n == 0), cancelled=cancel and n == 0, pickupObserved=bag)
                        for n, portion in enumerate([.25, 1] if depletion else [.5] if bag else [.5, .25])]
            edit = dict(emptyStart=True, anchorRunning=True, anchorProgress=True, anchorDuration=460,
                        contractsVerified=enabled, reordered=enabled and case in (food.MOVE_CASE, food.BAG_CASE),
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


if __name__ == '__main__':
    unittest.main()
