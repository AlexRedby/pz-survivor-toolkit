"""Falsify joined cooking evidence against native B42 portion/split rules."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import craft_ui_sandwich as cook
from queue_checks.report import events

# Current generated/evolvedrecipes.txt and generated/items/food.txt native mappings.
NATIVE_USES = {'Bread': {'Base.Cheese': 5, 'Base.ChocolateChips': 6},
               'Sandwich': {'Base.Cabbage': 6, 'Base.Tomato': 6}}


def food(ident, kind, hunger, calories, carbs, lipids, proteins, **kw):
    return dict(id=ident, kind='Base.' + kind, hunger=hunger, effectiveHunger=hunger,
                baseHunger=hunger, calories=calories, carbohydrates=carbs, lipids=lipids,
                proteins=proteins, weight=1, uses=1, cooked=False, burnt=False,
                frozen=False, extras=[], spices=[], **kw)


def evidence(enriched=False, level=0, mode='native'):
    case = cook.CASES[int(enriched)]
    source = dict(x=10, y=20, z=0, objectIndex=1, containerIndex=0,
                  containerType='crate', sprite='carpentry_01_16', ownerToken=case + ':client2:owned')
    inputs = [food(11, 'Cabbage', -.24, 180, 41, .7, 9), food(12, 'Tomato', -.12, 14, 3.5, .2, 1.3)]
    bread_inputs = [food(13, 'Cheese', -.15, 113, .87, 9.33, 6.4),
                    food(14, 'ChocolateChips', -.06, 50, 17, 8, 1)] if enriched else []
    base = food(10, 'BreadDough' if enriched else 'BreadSlices', -.24 if enriched else -.10,
                532 if enriched else 177, 99 if enriched else 33, 6.66 if enriched else 2.22, 17.7 if enriched else 5.9)
    p = dict(case=case, actorId=2, cookingLevel=level, bags=[], book=20,
             knife=dict(id=21, kind='Base.KitchenKnife'), source=source, base=base,
             breadInputs=bread_inputs, sandwichInputs=inputs, baselineOutputIds=[],
             nativeRecipeUses=copy.deepcopy(NATIVE_USES if enriched else {'Sandwich': NATIVE_USES['Sandwich']}))
    if enriched:
        p['oven'] = dict(source, sprite='appliances_cooking_01_0', containerType='stove', objectIndex=2)
        p['generator'] = dict(x=11, y=20, z=0, objectIndex=3, ownerToken=case + ':client2:generator',
                              condition=100, fuel=100, active=True)
    before = dict(case=case, source=source, items=sorted(copy.deepcopy(inputs + bread_inputs), key=lambda x: x['id']))
    final, gains, records = [], {'Bread': {}, 'Sandwich': {}}, []
    # Independent native addItem slots14/15/16: paid raw hunger, nutrient fraction, skill bonus.
    for stage, ingredients in [('Bread', bread_inputs), ('Sandwich', inputs)]:
        gains[stage] = dict.fromkeys(cook.NUTRIENTS, 0)
        for original in ingredients:
            use = p['nativeRecipeUses'][stage][original['kind']] / 100
            charged = use * (100 - 3 * level) / 100
            fraction = charged / -original['hunger']
            remaining = original['hunger'] + charged
            consumed = remaining >= -.02 - 1e-7
            value = dict(id=original['id'], kind=original['kind'], sourceCount=int(not consumed),
                         rootCount=0, ovenCount=0, totalCount=int(not consumed))
            if consumed:
                value['missing'] = True
            else:
                value.update(copy.deepcopy(original))
                value.update(hunger=remaining, effectiveHunger=remaining,
                             baseHunger=original['baseHunger'] + charged)
                for nutrient in cook.NUTRIENTS:
                    value[nutrient] = original[nutrient] * (1 - fraction)
            for nutrient in cook.NUTRIENTS:
                gains[stage][nutrient] += original[nutrient] * fraction * (1 + level / 15)
            final.append(value)
            records += [dict(kind='transfer', itemId=original['id'], pickup=True, returned=False,
                             progress=True, sourceMethodsUnchanged=True, transactionDuration=50),
                        dict(kind='evolved', itemId=original['id'], progress=True, sourceMethodsUnchanged=True,
                             baseRoot=True, inputRoot=True, basePresent=True, inputPresent=True,
                             cookingLevel=level, duration=100 - 2.5 * level)]
            if not consumed:
                records.append(dict(kind='transfer', itemId=original['id'], pickup=False, returned=True,
                                    progress=True, sourceMethodsUnchanged=True, transactionDuration=50))
    dispatches, checkpoints = [], {}
    by_id = {v['id']: v for v in final}
    untouched = [dict(copy.deepcopy(v), sourceCount=1, rootCount=0, ovenCount=0, totalCount=1) for v in inputs]
    def checkpoint(stage, **kw):
        return dict(case=case, stage=stage, breadInputs=copy.deepcopy(final[:len(bread_inputs)]),
                    sandwichInputs=copy.deepcopy(untouched), slices=[], sandwiches=[], **kw)
    def request(v, stage):
        return dict(id=v['id'], kind=v['kind'], recipeUse=p['nativeRecipeUses'][stage][v['kind']],
                    before=copy.deepcopy(v), displayedUsable=True, plusAllowed=True)
    sandwich_base, unused = copy.deepcopy(base), []
    if enriched:
        added = copy.deepcopy(base)
        added.update(extras=['Base.Cheese', 'Base.ChocolateChips'], hunger=base['hunger'] - .11,
                     baseHunger=base['baseHunger'] - .11, effectiveHunger=base['hunger'] - .11)
        for nutrient in cook.NUTRIENTS:
            added[nutrient] += gains['Bread'][nutrient]
        baked = dict(copy.deepcopy(added), cooked=True, effectiveHunger=added['hunger'] * 1.3)
        all_slices = []
        for ident in (30, 31, 32):
            item = dict(copy.deepcopy(baked), id=ident, kind='Base.BreadSlices')
            for key in ('hunger', 'effectiveHunger', 'baseHunger', *cook.NUTRIENTS):
                item[key] /= 3
            all_slices.append(item)
        sandwich_base, unused = all_slices[0], all_slices[1:]
        checkpoints = dict(BreadAdded=checkpoint('BreadAdded', bread=added),
                           Baked=checkpoint('Baked', bread=baked,
                                      oven=dict(active=True, maximum=200, powered=True, generator=dict(p['generator'], fuel=99.5))),
                           Sliced=checkpoint('Sliced'))
        checkpoints['Sliced']['slices'] = copy.deepcopy(all_slices)
        dispatches.append(dict(stage='Bread', baseBefore=base, cookStatus='showNutrition',
                               requests=[request(v, 'Bread') for v in bread_inputs]))
        records.append(dict(kind='slice', duration=200, progress=True, sourceMethodsUnchanged=True))
    first_sandwich = dict(copy.deepcopy(sandwich_base), id=40, kind='Base.Sandwich', cooked=False,
                         hunger=sandwich_base['hunger'] - .06, baseHunger=sandwich_base['baseHunger'] - .06,
                         effectiveHunger=sandwich_base['hunger'] - .06, extras=['Base.Cabbage'])
    sandwich = dict(copy.deepcopy(first_sandwich), hunger=first_sandwich['hunger'] - .06,
                    baseHunger=first_sandwich['baseHunger'] - .06, effectiveHunger=first_sandwich['hunger'] - .06,
                    extras=['Base.Cabbage', 'Base.Tomato'])
    for index, original in enumerate(inputs):
        fraction = (.06 * (1 - .03 * level)) / -original['hunger']
        for nutrient in cook.NUTRIENTS:
            gain = original[nutrient] * fraction * (1 + level / 15)
            if index == 0: first_sandwich[nutrient] += gain
            sandwich[nutrient] += gain
    dispatches += [dict(stage='Sandwich', baseBefore=copy.deepcopy(sandwich_base), cookStatus='addOneFirst', firstOnly=True,
                        requests=[request(inputs[0], 'Sandwich')]),
                   dict(stage='Sandwich', baseBefore=copy.deepcopy(first_sandwich), cookStatus='showNutrition',
                        requests=[request(inputs[1], 'Sandwich')])]
    checkpoints['FirstSandwich'] = checkpoint('FirstSandwich')
    checkpoints['FirstSandwich'].update(sandwiches=[copy.deepcopy(first_sandwich)], slices=copy.deepcopy(unused),
                                        sandwichInputs=[copy.deepcopy(by_id[inputs[0]['id']]), copy.deepcopy(untouched[1])])
    evolved = [r for r in records if r['kind'] == 'evolved']
    dispatch_ids = ([1, 1] if enriched else []) + [len(dispatches) - 1, len(dispatches)]
    base_ids = ([base['id']] * 2 if enriched else []) + [sandwich_base['id'], first_sandwich['id']]
    for record, dispatch_id, base_id, original in zip(evolved, dispatch_ids, base_ids, bread_inputs + inputs):
        record.update(dispatch=dispatch_id, baseId=base_id, inputBefore=copy.deepcopy(original))
    dispatch_by_id = dict(zip([v['id'] for v in bread_inputs + inputs], dispatch_ids))
    for record in records:
        if record['kind'] == 'transfer': record['dispatch'] = dispatch_by_id[record['itemId']]
        elif record['kind'] == 'slice': record['dispatch'] = 1
    terminal = dict(case=case, source=source, items=sorted([cook.raw_resource(v) for v in final if v['totalCount']], key=lambda v: v['id']))
    receipt = dict(case=case, actorId=2, cookingLevel=level, nativeRecipeUses=p['nativeRecipeUses'], source=source,
                   base=dict(id=10, kind=base['kind'], missing=True, sourceCount=0, rootCount=0, ovenCount=0, totalCount=0),
                   breadInputs=final[:len(bread_inputs)], sandwichInputs=final[len(bread_inputs):],
                   sandwiches=[sandwich], slices=unused, checkpoints=checkpoints, bookId=20, tailRead=True, sourceSnapshot=terminal)
    count = len(inputs + bread_inputs)
    row = dict(status='passed', requested=count, actions=count, actorId=2, cookingLevel=level,
               sourceVerified=True, sourceMethodsUnchanged=True, callbackClass='PJCK_EvoPanel',
               dispatchMethod='PJCK_ItemSlot.onAddButton+PJCK_BaseItem.onCook', tailProgress=True,
               returnsBeforeRead=True, tailIndependent=True, tokensGrouped=mode == 'toolkit',
               dispatches=dispatches, records=records, finalSourceSnapshot=terminal, sourceAtTail=terminal,
               actualSandwiches=[sandwich], actualSlices=unused, firstSandwich=copy.deepcopy(first_sandwich),
               actorCheckpoints=copy.deepcopy(checkpoints))
    if enriched:
        row.update(sliceIds=[30, 31, 32])
    row.update({k: copy.deepcopy(v) for k, v in receipt.items() if k != 'case'})
    return [dict(mode=mode), row, p, receipt, before, copy.deepcopy(terminal), copy.deepcopy(checkpoints)]


class SandwichVerifierTests(unittest.TestCase):
    def check(self, data):
        return cook.check_case(*data)

    def sync_actor(self, data):
        row, receipt = data[1], data[3]
        row.update({k: copy.deepcopy(v) for k, v in receipt.items() if k != 'case'})
        row['actualSandwiches'] = copy.deepcopy(receipt['sandwiches'])
        row['actualSlices'] = copy.deepcopy(receipt['slices'])

    def sync_checkpoints(self, data):
        self.sync_actor(data)
        data[1]['actorCheckpoints'] = copy.deepcopy(data[3]['checkpoints'])
        data[6] = copy.deepcopy(data[3]['checkpoints'])

    def sync_first(self, data):
        first = data[3]['checkpoints']['FirstSandwich']['sandwiches'][0]
        data[1]['firstSandwich'] = copy.deepcopy(first)
        data[1]['dispatches'][-1]['baseBefore'] = copy.deepcopy(first)
        self.sync_checkpoints(data)

    def test_real_partial_same_count_and_native_skill_bonus_pass(self):
        for enriched in (False, True):
            for level in (0, 5, 10):
                for mode in ('native', 'toolkit'):
                    with self.subTest(enriched=enriched, level=level, mode=mode):
                        data = evidence(enriched, level, mode)
                        self.assertEqual(self.check(data), [])
                        self.assertTrue(all(v['totalCount'] == 1 for v in data[3]['sandwichInputs']))
        ordinary = evidence()
        self.assertAlmostEqual(ordinary[3]['sandwiches'][0]['calories'], 229)
        self.assertAlmostEqual(ordinary[3]['sandwichInputs'][0]['hunger'], -.18)
        self.assertAlmostEqual(ordinary[3]['sandwichInputs'][1]['hunger'], -.06)
        self.assertAlmostEqual(evidence(True)[3]['checkpoints']['BreadAdded']['bread']['calories'], 619 + 2 / 3)
        # Native deletion can discard residual nutrition at high skill; output gain is not whole seed.
        data = evidence(True, 10)
        self.assertTrue(data[3]['breadInputs'][1]['missing'])
        self.assertAlmostEqual(data[3]['checkpoints']['BreadAdded']['bread']['calories'], 532 + 113 * (.035 / .15) * (1 + 10 / 15) + 50 * .7 * (1 + 10 / 15))

    def test_free_ingredients_and_independent_view_desync_fail(self):
        for mode in ('native', 'toolkit'):
            for change in ('hunger', 'baseHunger', 'calories', 'host', 'actor', 'server', 'tail'):
                with self.subTest(mode=mode, change=change):
                    d = evidence(mode=mode)
                    if change in ('hunger', 'baseHunger', 'calories'):
                        d[3]['sandwichInputs'][0][change] = d[2]['sandwichInputs'][0][change]
                        self.sync_actor(d)
                    elif change == 'host': d[5]['items'][0]['calories'] += 1
                    elif change == 'actor': d[1]['finalSourceSnapshot']['items'][0]['calories'] += 1
                    elif change == 'server': d[3]['sourceSnapshot']['items'][0]['calories'] += 1
                    else: d[1]['sourceAtTail']['items'][0]['calories'] += 1
                    self.assertTrue(self.check(d))

    def test_real_plus_render_status_and_first_conversion_allowance_are_required(self):
        for enriched in (False, True):
            for change in ('stale-first', 'stale-rest', 'displayed', 'plus-allowed', 'first-unbounded',
                           'rest-first-only', 'two-first-requests', 'old-combined-cook', 'wrong-dispatch', 'wrong-base'):
                with self.subTest(enriched=enriched, change=change):
                    d = evidence(enriched); first, rest = d[1]['dispatches'][-2:]
                    if change == 'stale-first': first['cookStatus'] = 'showNutrition'
                    elif change == 'stale-rest': rest['cookStatus'] = 'addOneFirst'
                    elif change == 'displayed': first['requests'][0]['displayedUsable'] = False
                    elif change == 'plus-allowed': first['requests'][0]['plusAllowed'] = False
                    elif change == 'first-unbounded': first.pop('firstOnly')
                    elif change == 'rest-first-only': rest['firstOnly'] = True
                    elif change == 'two-first-requests': first['requests'] += copy.deepcopy(rest['requests'])
                    elif change == 'old-combined-cook':
                        first['requests'] += rest['requests'];d[1]['dispatches'].pop()
                    else:
                        record = [r for r in d[1]['records'] if r['kind'] == 'evolved'][-1]
                        record['dispatch' if change == 'wrong-dispatch' else 'baseId'] -= 1
                    self.assertTrue(self.check(d))
        d = evidence(True);d[1]['dispatches'][0]['cookStatus'] = 'addOneFirst'
        self.assertTrue(self.check(d))

    def test_first_cook_conversion_and_each_partial_cost_have_independent_authority(self):
        for enriched in (False, True):
            for change in ('missing', 'cabbage-free', 'tomato-charged', 'double-charge', 'first-nutrition',
                           'first-identity', 'old-base-survives', 'local-first', 'next-base'):
                with self.subTest(enriched=enriched, change=change):
                    d = evidence(enriched);cp = d[3]['checkpoints']['FirstSandwich']
                    if change == 'missing': d[3]['checkpoints'].pop('FirstSandwich')
                    elif change == 'cabbage-free':
                        cp['sandwichInputs'][0] = dict(d[2]['sandwichInputs'][0], sourceCount=1, rootCount=0, ovenCount=0, totalCount=1)
                    elif change == 'tomato-charged': cp['sandwichInputs'][1] = copy.deepcopy(d[3]['sandwichInputs'][1])
                    elif change == 'double-charge': cp['sandwichInputs'][0]['hunger'] += .06
                    elif change == 'first-nutrition': cp['sandwiches'][0]['calories'] += 1
                    elif change == 'first-identity': cp['sandwiches'][0]['id'] += 1
                    elif change == 'old-base-survives': cp['bread'] = copy.deepcopy(d[2]['base'])
                    elif change == 'local-first': d[1]['firstSandwich']['calories'] += 1
                    else: d[1]['dispatches'][-1]['baseBefore']['calories'] += 1
                    if change not in ('missing', 'local-first', 'next-base'): self.sync_first(d)
                    else: self.sync_checkpoints(d)
                    self.assertTrue(self.check(d))

    def test_cooking_multiplier_and_conversion_reset_cannot_be_forged_consistently(self):
        for change in ('baked-effective', 'slice-effective', 'first-cooked', 'first-effective',
                       'final-cooked', 'final-effective'):
            with self.subTest(change=change):
                d = evidence(True);cp = d[3]['checkpoints']
                if change == 'baked-effective':
                    cp['Baked']['bread']['effectiveHunger'] = cp['Baked']['bread']['hunger']
                    for v in cp['Sliced']['slices']: v['effectiveHunger'] = v['hunger']
                    d[1]['dispatches'][-2]['baseBefore'] = copy.deepcopy(cp['Sliced']['slices'][0])
                    d[3]['slices'] = copy.deepcopy(cp['Sliced']['slices'][1:])
                    cp['FirstSandwich']['slices'] = copy.deepcopy(d[3]['slices'])
                elif change == 'slice-effective':
                    cp['Sliced']['slices'][0]['effectiveHunger'] += .01
                    d[1]['dispatches'][-2]['baseBefore'] = copy.deepcopy(cp['Sliced']['slices'][0])
                elif change.startswith('first-'):
                    v = cp['FirstSandwich']['sandwiches'][0]
                    if change == 'first-cooked': v['cooked'] = True
                    else: v['effectiveHunger'] = v['hunger'] * 1.3
                    self.sync_first(d)
                else:
                    v = d[3]['sandwiches'][0]
                    if change == 'final-cooked': v['cooked'] = True
                    else: v['effectiveHunger'] = v['hunger'] * 1.3
                self.sync_checkpoints(d)
                self.assertTrue(self.check(d))

    def test_missing_paid_progress_pickup_return_and_tail_fail(self):
        for change in ('progress', 'pickup', 'return', 'duration', 'root', 'callback', 'tail'):
            with self.subTest(change=change):
                d = evidence()
                if change == 'progress': d[1]['records'][1]['progress'] = False
                elif change == 'pickup': d[1]['records'].pop(0)
                elif change == 'return': d[1]['records'].pop(2)
                elif change == 'duration': d[1]['records'][0]['transactionDuration'] = 1
                elif change == 'root': d[1]['records'][1]['inputRoot'] = False
                elif change == 'callback': d[1]['records'][1]['sourceMethodsUnchanged'] = False
                else: d[1]['tailProgress'] = False
                self.assertTrue(self.check(d))

    def test_duplicate_identity_and_wrong_stage_partition_fail(self):
        d = evidence()
        d[3]['sandwichInputs'].append(copy.deepcopy(d[3]['sandwichInputs'][0]))
        # Keep forged totals mutually consistent so only repeated identity, not arithmetic, rejects it.
        for key in cook.NUTRIENTS:
            d[3]['sandwiches'][0][key] += d[2]['sandwichInputs'][0][key] / 4
        terminal = dict(case=d[2]['case'], source=d[2]['source'],
                        items=sorted([cook.raw_resource(v) for v in d[3]['sandwichInputs']], key=lambda v: v['id']))
        d[3]['sourceSnapshot'] = terminal
        self.sync_actor(d)
        d[1]['finalSourceSnapshot'] = copy.deepcopy(terminal)
        d[1]['sourceAtTail'] = copy.deepcopy(terminal)
        d[5] = copy.deepcopy(terminal)
        self.assertTrue(self.check(d))
        d = evidence(True)
        d[2]['breadInputs'][0], d[2]['sandwichInputs'][0] = d[2]['sandwichInputs'][0], d[2]['breadInputs'][0]
        self.assertTrue(self.check(d))

    def test_enriched_chain_requires_real_bake_and_equal_inherited_slices(self):
        for change in ('bake', 'slice', 'identity', 'labels', 'baseline', 'nutrition', 'free-bake', 'raw-hunger'):
            with self.subTest(change=change):
                d = evidence(True)
                cp = d[3]['checkpoints']
                if change == 'bake': cp['Baked']['bread']['cooked'] = False
                elif change == 'slice':
                    cp['Sliced']['slices'][0]['calories'] += 3
                    cp['Sliced']['slices'][1]['calories'] -= 3
                    d[1]['dispatches'][-1]['baseBefore'] = copy.deepcopy(cp['Sliced']['slices'][0])
                    d[3]['sandwiches'][0]['calories'] += 3
                    d[3]['slices'] = copy.deepcopy(cp['Sliced']['slices'][1:])
                elif change == 'identity': cp['Baked']['bread']['id'] = 900
                elif change == 'labels': cp['Sliced']['slices'][1]['extras'] = []
                elif change == 'baseline': d[1]['dispatches'][-1]['baseBefore']['calories'] = 177
                elif change == 'nutrition': cp['BreadAdded']['bread']['calories'] += 10
                elif change == 'free-bake':
                    cp['Baked']['bread']['calories'] += 9
                    for item in cp['Sliced']['slices']: item['calories'] += 3
                    d[1]['dispatches'][-1]['baseBefore'] = copy.deepcopy(cp['Sliced']['slices'][0])
                    d[3]['sandwiches'][0]['calories'] += 3
                    d[3]['slices'] = copy.deepcopy(cp['Sliced']['slices'][1:])
                else: d[3]['sandwiches'][0]['hunger'] = -.1
                self.sync_actor(d)
                d[1]['actorCheckpoints'] = copy.deepcopy(cp)
                d[6] = copy.deepcopy(cp)
                self.assertTrue(self.check(d))

    def test_enriched_generator_is_owned_distinct_and_actually_fuels_the_oven(self):
        worn = evidence(True)
        worn[3]['checkpoints']['Baked']['oven']['generator']['condition'] = 99.5
        self.sync_actor(worn)
        worn[1]['actorCheckpoints'] = copy.deepcopy(worn[3]['checkpoints'])
        worn[6] = copy.deepcopy(worn[3]['checkpoints'])
        self.assertEqual(self.check(worn), [])
        for change in ('missing-seed', 'inactive-seed', 'empty-seed', 'condition-seed', 'duplicate-object',
                       'plain-generator', 'missing-baked', 'wrong-id', 'wrong-owner', 'inactive-baked',
                       'empty-baked', 'increased-fuel', 'zero-condition-baked', 'healed-condition-baked'):
            with self.subTest(change=change):
                d = evidence(change != 'plain-generator')
                if change == 'missing-seed': d[2].pop('generator')
                elif change == 'inactive-seed': d[2]['generator']['active'] = False
                elif change == 'empty-seed': d[2]['generator']['fuel'] = 0
                elif change == 'condition-seed': d[2]['generator']['condition'] = 99
                elif change == 'duplicate-object':
                    d[2]['generator'].update({k: d[2]['oven'][k] for k in ('x', 'y', 'z', 'objectIndex')})
                elif change == 'plain-generator': d[2]['generator'] = {}
                else:
                    cp = d[3]['checkpoints']
                    oven = cp['Baked']['oven']
                    if change == 'missing-baked': oven.pop('generator')
                    elif change == 'wrong-id': oven['generator']['objectIndex'] += 1
                    elif change == 'wrong-owner': oven['generator']['ownerToken'] += ':foreign'
                    elif change == 'inactive-baked': oven['generator']['active'] = False
                    elif change == 'empty-baked': oven['generator']['fuel'] = 0
                    elif change == 'increased-fuel': oven['generator']['fuel'] = 101
                    elif change == 'zero-condition-baked': oven['generator']['condition'] = 0
                    else: oven['generator']['condition'] = 101
                    self.sync_actor(d)
                    d[1]['actorCheckpoints'] = copy.deepcopy(cp)
                    d[6] = copy.deepcopy(cp)
                self.assertTrue(self.check(d))

    def test_malformed_evidence_is_rejected_without_crash(self):
        for index, value in ((2, None), (3, None), (3, []), (1, None)):
            with self.subTest(index=index, value=value):
                d = evidence(); d[index] = value
                self.assertTrue(self.check(d))
        for target, key, value in ((3, 'breadInputs', None), (3, 'sandwichInputs', [None]),
                                   (1, 'dispatches', [None]), (1, 'records', [None])):
            with self.subTest(key=key):
                d = evidence(); d[target][key] = value
                self.assertTrue(self.check(d))
        d = evidence(); d[1]['dispatches'][0]['requests'] = None
        self.assertTrue(self.check(d))
        d = evidence(True); d[3]['checkpoints']['Baked'] = None
        self.assertTrue(self.check(d))

    def write_logs(self, root, mode='native', native_failure=False, enriched=False):
        d = evidence(enriched=enriched, mode=mode); _, row, p, receipt, before, after, _ = d
        case = p['case']; cases = [case]
        selection = dict(mode=mode, cases=cases)
        server = [('PREPARED', p), ('OBSERVED_BEFORE', dict(case=case, actor='client1', snapshot=before)),
                  *[('CHECKPOINT', dict(case=case, stage=stage, snapshot=receipt['checkpoints'][stage]))
                    for stage in cook.checkpoint_stages(case)],
                  ('VERIFIED', receipt), ('OBSERVED', dict(case=case, actor='client1', snapshot=after))]
        (root / 'server-launch.log').write_text('\n'.join('[CRAFT_UI_TEST] ' + k + ' ' + json.dumps(v) for k, v in server))
        for role in ('client1', 'client2'):
            context = dict(suite='craft-ui', kind='mp', mode=mode, actor=role)
            rows = [dict(event='setup', cases=cases, expected=1, queueEnabled=mode == 'toolkit', nativeDurations=True)]
            if role == 'client1':
                rows += [dict(event='observer', id=case, stage=stage, snapshot=v) for stage, v in [('before', before), ('after', after)]]
                rows += [dict(event='case', id=case, status='observed', participation='observer', producerActor='client2', before=before, after=after)]
            else:
                rows += [dict(row, event='case', id=case)]
            complete = dict(event='complete', cases=cases, expected=1, performed=int(role == 'client2'), failed=0, skipped=0)
            if role == 'client1': complete['observed'] = 1
            rows.append(complete)
            text = '\n'.join(('[CRAFT_UI_OBSERVER] ' if r['event'] == 'observer' else '[QUEUE_CHECK] ')
                             + json.dumps(dict(r, **context)) for r in rows)
            if native_failure: text += '\n[QUEUE_TEST] FAIL late native error\n'
            (root / (role + '-launch.log')).write_text(text)
        return selection

    def test_observer_log_acceptance_and_late_native_failure_propagation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for mode in ('native', 'toolkit'):
                selection = self.write_logs(root, mode)
                common_host = events((root / 'client1-launch.log').read_text())
                self.assertEqual([v['event'] for v in common_host], ['setup', 'case', 'complete'])
                result = cook.verify(root, selection, {})
                self.assertEqual(result['issues'], [])
                self.assertTrue(all(v['status'] == 'passed' for v in result['outcomes']))
                self.write_logs(root, mode, native_failure=True)
                result = cook.verify(root, selection, {})
                self.assertIn('Native joining cooking fixture failed', result['issues'])
                self.assertTrue(all(v['status'] == 'failed' for v in result['outcomes']))

    def test_native_checkpoint_transport_requires_each_stage_in_original_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for enriched in (False, True):
                selection = self.write_logs(root, enriched=enriched)
                self.assertEqual(cook.verify(root, selection, {})['issues'], [])
                for change in ('missing', 'duplicate', 'wrong-stage', 'wrong-inner-stage', 'reordered'):
                    if change == 'reordered' and not enriched: continue
                    with self.subTest(enriched=enriched, change=change):
                        self.write_logs(root, enriched=enriched)
                        path = root / 'server-launch.log';lines = path.read_text().splitlines()
                        positions = [i for i, line in enumerate(lines) if '] CHECKPOINT ' in line]
                        if change == 'missing': lines.pop(positions[-1])
                        elif change == 'duplicate': lines.insert(positions[-1], lines[positions[-1]])
                        elif change == 'reordered': lines[positions[0]], lines[positions[-1]] = lines[positions[-1]], lines[positions[0]]
                        else:
                            value = json.loads(lines[positions[-1]].split('CHECKPOINT ', 1)[1])
                            if change == 'wrong-stage': value['stage'] = 'Sliced'
                            else: value['snapshot']['stage'] = 'Sliced'
                            lines[positions[-1]] = '[CRAFT_UI_TEST] CHECKPOINT ' + json.dumps(value)
                        path.write_text('\n'.join(lines))
                        result = cook.verify(root, selection, {})
                        self.assertTrue(result['issues'])
                        self.assertTrue(all(v['status'] == 'failed' for v in result['outcomes']))

    def test_observer_custom_marker_is_required_and_strictly_checked(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for change in ('standard-observer', 'custom-case', 'missing-observer', 'custom-context', 'custom-json'):
                with self.subTest(change=change):
                    selection = self.write_logs(root)
                    path = root / 'client1-launch.log'
                    lines = path.read_text().splitlines()
                    if change == 'standard-observer':
                        lines[1] = lines[1].replace('[CRAFT_UI_OBSERVER] ', '[QUEUE_CHECK] ')
                    elif change == 'custom-case':
                        lines[3] = lines[3].replace('[QUEUE_CHECK] ', '[CRAFT_UI_OBSERVER] ')
                    elif change == 'missing-observer':
                        lines.pop(1)
                    elif change == 'custom-context':
                        lines[1] = lines[1].replace('"actor": "client1"', '"actor": "client2"')
                    else:
                        lines[1] = '[CRAFT_UI_OBSERVER] {broken'
                    path.write_text('\n'.join(lines))
                    result = cook.verify(root, selection, {})
                    self.assertTrue(result['issues'])
                    self.assertTrue(all(v['status'] == 'failed' for v in result['outcomes']))

    def test_malformed_log_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); selection = self.write_logs(root)
            for filename, text in [('server-launch.log', '[CRAFT_UI_TEST] PREPARED {broken'),
                                   ('client1-launch.log', '[QUEUE_CHECK] []')]:
                with self.subTest(filename=filename):
                    self.write_logs(root); (root / filename).write_text(text)
                    result = cook.verify(root, selection, {})
                    self.assertTrue(result['issues'])
                    self.assertTrue(all(v['status'] == 'failed' for v in result['outcomes']))

if __name__ == '__main__':
    unittest.main()
