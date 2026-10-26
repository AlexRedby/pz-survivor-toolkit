"""Joining-client cooking: native portions, bread inheritance and independent world-container views."""
import json
import math
from pathlib import Path
import re

OBSERVER_MARKER = '[CRAFT_UI_OBSERVER] '

CASES = ('cook-sandwich-plain-joined', 'cook-sandwich-enriched-joined')
NUTRIENTS = ('calories', 'carbohydrates', 'lipids', 'proteins')
FOOD_NUMBERS = ('hunger', 'effectiveHunger', 'baseHunger', 'weight', *NUTRIENTS)
USES = {'Bread': {'Base.Cheese': 5, 'Base.ChocolateChips': 6},
        'Sandwich': {'Base.Cabbage': 6, 'Base.Tomato': 6}}
RECEIPT_KEYS = {'case', 'actorId', 'cookingLevel', 'nativeRecipeUses', 'source', 'base', 'breadInputs',
                'sandwichInputs', 'sandwiches', 'slices', 'checkpoints', 'bookId', 'tailRead', 'sourceSnapshot'}


def number(v):
    return type(v) in (int, float) and math.isfinite(v)


def same(a, b):
    if number(a) and number(b):
        return math.isclose(a, b, rel_tol=2e-5, abs_tol=2e-5)
    if type(a) is not type(b):
        return False
    if isinstance(a, dict):
        return set(a) == set(b) and all(same(a[k], b[k]) for k in a)
    if isinstance(a, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return a == b


def matches(a, b):
    return isinstance(a, dict) and all(k in a and same(a[k], v) for k, v in b.items())


def food(v):
    return (isinstance(v, dict) and type(v.get('id')) is int and isinstance(v.get('kind'), str)
            and type(v.get('uses')) is int and all(number(v.get(k)) for k in FOOD_NUMBERS)
            and all(type(v.get(k)) is bool for k in ('cooked', 'burnt', 'frozen'))
            and all(isinstance(v.get(k), list) and all(isinstance(x, str) for x in v[k]) for k in ('extras', 'spices')))


def ids(values):
    return isinstance(values, list) and all(type(v) is int for v in values) and len(set(values)) == len(values)


def source(v, case, kind='crate'):
    return (isinstance(v, dict) and all(type(v.get(k)) is int for k in ('x', 'y', 'z', 'objectIndex', 'containerIndex'))
            and v['objectIndex'] >= 0 and v['containerIndex'] >= 0 and v.get('containerType') == kind
            and v.get('sprite') == ('carpentry_01_16' if kind == 'crate' else 'appliances_cooking_01_0')
            and isinstance(v.get('ownerToken'), str) and v['ownerToken'].startswith(case + ':client2:'))


def generator(v, case):
    return (isinstance(v, dict) and all(type(v.get(k)) is int for k in ('x', 'y', 'z', 'objectIndex'))
            and v['objectIndex'] >= 0 and isinstance(v.get('ownerToken'), str)
            and v['ownerToken'].startswith(case + ':client2:') and v.get('active') is True
            and number(v.get('condition')) and v['condition'] > 0
            and number(v.get('fuel')) and v['fuel'] > 0)


def object_identity(v):
    return tuple(v[k] for k in ('x', 'y', 'z', 'objectIndex'))


def prepared(p, case):
    if not isinstance(p, dict) or p.get('case') != case or case not in CASES:
        return False
    enriched = case == CASES[1]
    foods = p.get('breadInputs', []) + p.get('sandwichInputs', []) if all(isinstance(p.get(k), list) for k in ('breadInputs', 'sandwichInputs')) else []
    expected = {'Base.Cheese', 'Base.ChocolateChips', 'Base.Cabbage', 'Base.Tomato'} if enriched else {'Base.Cabbage', 'Base.Tomato'}
    return (type(p.get('actorId')) is int and p['actorId'] > 0 and type(p.get('cookingLevel')) is int
            and 0 <= p['cookingLevel'] <= 10 and p.get('bags') == [] and type(p.get('book')) is int
            and food(p.get('base')) and p['base']['kind'] == ('Base.BreadDough' if enriched else 'Base.BreadSlices')
            and not any(p['base'][k] for k in ('cooked', 'burnt', 'frozen')) and source(p.get('source'), case)
            and (source(p.get('oven'), case, 'stove') and generator(p.get('generator'), case)
                 and p['generator']['condition'] == 100
                 and object_identity(p['generator']) not in (object_identity(p['source']), object_identity(p['oven']))
                 if enriched else 'oven' not in p and 'generator' not in p)
            and len(foods) == len(expected) and all(food(v) and not v['cooked'] and not v['burnt'] and not v['frozen']
                and v['hunger'] < 0 and not v['extras'] and not v['spices'] for v in foods)
            and {v['kind'] for v in foods} == expected
            and [v['kind'] for v in p['breadInputs']] == (list(USES['Bread']) if enriched else [])
            and [v['kind'] for v in p['sandwichInputs']] == list(USES['Sandwich'])
            and matches(p.get('knife'), dict(kind='Base.KitchenKnife')) and type(p['knife'].get('id')) is int
            and ids(p.get('baselineOutputIds'))
            and ids([p['base']['id'], p['book'], p['knife']['id']] + [v['id'] for v in foods] + p['baselineOutputIds'])
            and same(p.get('nativeRecipeUses'), USES if enriched else {'Sandwich': USES['Sandwich']}))


def raw_resource(value):
    return {k: v for k, v in value.items() if k not in ('sourceCount', 'rootCount', 'ovenCount', 'totalCount')}


def expected_cost(before, use, level):
    nominal = use / 100
    cost = nominal * (1 - .03 * level)
    fraction = min(1, abs(cost / before['hunger']))
    hunger = before['hunger'] + cost
    effective = before['effectiveHunger'] * hunger / before['hunger']
    after = dict(before, hunger=hunger, effectiveHunger=effective, baseHunger=before['baseHunger'] + cost)
    for key in NUTRIENTS:
        after[key] = before[key] * (1 - fraction)
    gain = {key: before[key] * fraction * (1 + level / 15) for key in NUTRIENTS}
    return after, gain, effective >= -.0200001


def checkpoint_stages(case):
    return (['BreadAdded', 'Baked', 'Sliced'] if case == CASES[1] else []) + ['FirstSandwich']


def check_case(selection, row, p, receipt, before_view, after_view, checkpoints):
    issues = []
    def fail(message):
        issues.append(message + ': ' + str(p.get('case')))
    if not isinstance(p, dict) or not prepared(p, p.get('case')):
        return ['Joining cooking preparation/identity/native mapping differs']
    if not isinstance(row, dict) or not isinstance(receipt, dict):
        return ['Joining cooking actor/server evidence is not an object']
    enriched, level = p['case'] == CASES[1], p['cookingLevel']
    expected_count = 4 if enriched else 2
    if not matches(row, dict(status='passed', requested=expected_count, actions=expected_count, actorId=p['actorId'],
            cookingLevel=level, sourceVerified=True, sourceMethodsUnchanged=True, callbackClass='PJCK_EvoPanel',
            dispatchMethod='PJCK_ItemSlot.onAddButton+PJCK_BaseItem.onCook', tailProgress=True,
            returnsBeforeRead=True, tailIndependent=True, tokensGrouped=selection['mode'] == 'toolkit')):
        fail('Native joining UI, paid continuation or source contract differs')
    if (not isinstance(receipt, dict) or set(receipt) != RECEIPT_KEYS
            or not matches(receipt, dict(case=p['case'], actorId=p['actorId'], cookingLevel=level,
                nativeRecipeUses=p['nativeRecipeUses'], source=p['source'], bookId=p['book'], tailRead=True))
            or not matches(row, {k: v for k, v in receipt.items() if k != 'case'})):
        fail('Server and actor authority receipts differ')
    seed_foods = p['breadInputs'] + p['sandwichInputs']
    seed_by_id = {v['id']: v for v in seed_foods}
    if not matches(before_view, dict(case=p['case'], source=p['source'], items=sorted(seed_foods, key=lambda v: v['id']))):
        fail('Host did not independently observe the complete initial source')
    if not all(isinstance(receipt.get(k), list) for k in ('breadInputs', 'sandwichInputs')):
        return issues + ['Authoritative ingredient lists missing']
    final_foods = receipt['breadInputs'] + receipt['sandwichInputs']
    if (not all(isinstance(v, dict) and type(v.get('id')) is int for v in final_foods)
            or len(final_foods) != len(seed_foods) or {v.get('id') for v in final_foods} != set(seed_by_id)
            or any([v.get('id') for v in receipt[k]] != [v['id'] for v in p[k]]
                   for k in ('breadInputs', 'sandwichInputs'))):
        return issues + ['Authoritative ingredient identities missing']
    gains = {'Bread': {key: 0 for key in NUTRIENTS}, 'Sandwich': {key: 0 for key in NUTRIENTS}}
    gain_by_id = {}
    for actual in final_foods:
        original = seed_by_id[actual['id']]
        stage = 'Bread' if original['kind'] in USES['Bread'] else 'Sandwich'
        expected, gain, consumed = expected_cost(original, USES[stage][original['kind']], level)
        gain_by_id[original['id']] = gain
        for key in NUTRIENTS:
            gains[stage][key] += gain[key]
        counts = dict(sourceCount=0 if consumed else 1, rootCount=0, ovenCount=0, totalCount=0 if consumed else 1)
        if not matches(actual, dict(id=original['id'], kind=original['kind'], **counts)):
            fail('Ingredient consumed, duplicated or restored to the wrong location')
        if consumed:
            if actual.get('missing') is not True:
                fail('Fully consumed ingredient remains')
        elif not food(actual) or not matches(actual, {k: expected[k] for k in ('hunger', 'effectiveHunger', 'baseHunger', *NUTRIENTS)}):
            fail('Actual ingredient hunger/nutrition deduction differs')
    terminal = dict(case=p['case'], source=p['source'], items=sorted(
        [raw_resource(v) for v in final_foods if v.get('totalCount') == 1], key=lambda v: v['id']))
    if any(not same(value, terminal) for value in (after_view, receipt.get('sourceSnapshot'), row.get('finalSourceSnapshot'), row.get('sourceAtTail'))):
        fail('Shared source views disagree between host, joining client and server')
    outputs, slices = receipt.get('sandwiches'), receipt.get('slices')
    if not isinstance(outputs, list) or len(outputs) != 1 or not food(outputs[0]):
        return issues + ['Exactly one native sandwich is required']
    sandwich = outputs[0]
    if sandwich['kind'] != 'Base.Sandwich' or sandwich['cooked'] or sandwich['burnt'] or sandwich['frozen'] or sandwich['extras'] != ['Base.Cabbage', 'Base.Tomato'] or sandwich['spices']:
        fail('New sandwich ingredients differ from inherited bread labels')
    if not same(sandwich['effectiveHunger'], sandwich['hunger']):
        fail('Native sandwich conversion retained the cooked bread hunger multiplier')
    dispatches = row.get('dispatches')
    stages = (['Bread'] if enriched else []) + ['Sandwich', 'Sandwich']
    if (not isinstance(dispatches, list) or not all(isinstance(d, dict) for d in dispatches)
            or [d.get('stage') for d in dispatches] != stages):
        return issues + ['Original plus/Cook dispatch stages missing']
    for index, d in enumerate(dispatches):
        first = index == len(dispatches) - 2
        expected_inputs = p['breadInputs'] if d['stage'] == 'Bread' else [p['sandwichInputs'][0 if first else 1]]
        first_only = d.get('firstOnly') is True if first else d.get('firstOnly') is None or d.get('firstOnly') is False
        if (d.get('cookStatus') != ('addOneFirst' if first else 'showNutrition')
                or not first_only):
            fail('Real rendered plus status or first-only conversion gate was bypassed')
        requests = d.get('requests', [])
        if not isinstance(requests, list) or len(requests) != len(expected_inputs) or any(not matches(r, dict(id=m['id'], kind=m['kind'],
                recipeUse=USES[d['stage']][m['kind']], before=m, displayedUsable=True, plusAllowed=True)) for r, m in zip(requests, expected_inputs)):
            fail('Original plus selected another physical ingredient or native portion')
    sandwich_base = dispatches[-2].get('baseBefore')
    if not food(sandwich_base) or sandwich_base['kind'] != 'Base.BreadSlices':
        return issues + ['Actual sandwich slice baseline missing']
    for key in NUTRIENTS:
        if not same(sandwich[key], sandwich_base[key] + gains['Sandwich'][key]):
            fail('Sandwich nutrition is not native base plus charged ingredients')
    for key in ('hunger', 'baseHunger'):
        if not same(sandwich[key], sandwich_base[key] - sum(USES['Sandwich'].values()) / 100):
            fail('Sandwich raw hunger is not native base plus nominal portions')
    if not matches(receipt.get('base'), dict(id=p['base']['id'], kind=p['base']['kind'], missing=True,
            sourceCount=0, rootCount=0, ovenCount=0, totalCount=0)):
        fail('Original bread base survives or was substituted')
    cp = receipt.get('checkpoints')
    if (not isinstance(cp, dict) or set(cp) != set(checkpoint_stages(p['case']))
            or not same(row.get('actorCheckpoints'), cp) or not same(checkpoints, cp)):
        return issues + ['Native bread and first sandwich checkpoints missing']
    if any(not matches(cp[stage], dict(case=p['case'], stage=stage)) for stage in checkpoint_stages(p['case'])):
        return issues + ['Native checkpoint stage identity differs']
    first_cp = cp['FirstSandwich']
    first_outputs = first_cp.get('sandwiches')
    if not isinstance(first_outputs, list) or len(first_outputs) != 1 or not food(first_outputs[0]):
        return issues + ['First native Cook did not produce exactly one sandwich']
    first_sandwich = first_outputs[0]
    if (not matches(first_sandwich, dict(id=sandwich['id'], kind='Base.Sandwich', cooked=False, burnt=False,
            frozen=False, extras=['Base.Cabbage'], spices=[]))
            or not same(first_sandwich['effectiveHunger'], first_sandwich['hunger'])
            or not same(row.get('firstSandwich'), first_sandwich)
            or not same(dispatches[-1].get('baseBefore'), first_sandwich)):
        fail('First native conversion identity, local view or following Cook base differs')
    first_input, second_input = p['sandwichInputs']
    for key in ('hunger', 'baseHunger'):
        if not same(first_sandwich[key], sandwich_base[key] - USES['Sandwich'][first_input['kind']] / 100):
            fail('First native Cook raw hunger is not one nominal portion')
    for key in NUTRIENTS:
        if (not same(first_sandwich[key], sandwich_base[key] + gain_by_id[first_input['id']][key])
                or not same(sandwich[key], first_sandwich[key] + gain_by_id[second_input['id']][key])):
            fail('Separate native Cook nutrition charges are missing or duplicated')
    untouched_second = dict(second_input, sourceCount=1, rootCount=0, ovenCount=0, totalCount=1)
    if (not same(first_cp.get('breadInputs'), receipt['breadInputs'])
            or not same(first_cp.get('sandwichInputs'), [receipt['sandwichInputs'][0], untouched_second])
            or not same(first_cp.get('slices'), slices) or first_cp.get('bread') is not None):
        fail('First native Cook charged another input or changed unused bread')
    if enriched:
        added, baked, sliced = (cp[k] for k in ('BreadAdded', 'Baked', 'Sliced'))
        if not all(isinstance(v, dict) for v in (added, baked, sliced)):
            return issues + ['Native bread checkpoints are not objects']
        if not food(added.get('bread')) or not food(baked.get('bread')) or not matches(baked['bread'], dict(cooked=True, burnt=False, frozen=False)):
            return issues + ['Native enriched bread was not genuinely baked']
        if not matches(added['bread'], dict(id=p['base']['id'], kind='Base.BreadDough', extras=['Base.Cheese', 'Base.ChocolateChips'])):
            fail('Bread inherited ingredient baseline differs')
        if (not matches(added['bread'], dict(cooked=False, burnt=False, frozen=False))
                or not same(added['bread']['effectiveHunger'], added['bread']['hunger'])
                or not same(baked['bread']['effectiveHunger'], baked['bread']['hunger'] * 1.3)):
            fail('Native fresh bread cooking hunger multiplier differs')
        untouched_inputs = [dict(v, sourceCount=1, rootCount=0, ovenCount=0, totalCount=1) for v in p['sandwichInputs']]
        for stage in ('BreadAdded', 'Baked', 'Sliced'):
            if (not same(cp[stage].get('breadInputs'), receipt['breadInputs'])
                    or not same(cp[stage].get('sandwichInputs'), untouched_inputs)
                    or cp[stage].get('sandwiches') != []):
                fail('Bread checkpoint charged sandwich ingredients or changed prior portions')
        for key in NUTRIENTS:
            if not same(added['bread'][key], p['base'][key] + gains['Bread'][key]):
                fail('Bread nutrition is not native base plus charged ingredients')
        if not matches(baked['bread'], {k: added['bread'][k] for k in ('id', 'kind', 'hunger', 'baseHunger', *NUTRIENTS, 'extras', 'spices')}):
            fail('Baking changed the bread identity or raw nutrition')
        for key in ('hunger', 'baseHunger'):
            if not same(added['bread'][key], p['base'][key] - sum(USES['Bread'].values()) / 100):
                fail('Bread raw hunger is not native base plus nominal portions')
        if not matches(baked.get('oven'), dict(active=True, maximum=200, powered=True)):
            fail('Read-only checkpoint does not show a live powered native oven')
        oven = baked.get('oven')
        actual_generator = oven.get('generator') if isinstance(oven, dict) else None
        if (not generator(actual_generator, p['case'])
                or not matches(actual_generator, {k: p['generator'][k] for k in ('x', 'y', 'z', 'objectIndex', 'ownerToken')})
                or actual_generator['fuel'] > p['generator']['fuel']
                or actual_generator['condition'] > p['generator']['condition']):
            fail('Baking generator identity, operation or native fuel differs')
        all_slices = sliced.get('slices')
        if not isinstance(all_slices, list) or len(all_slices) != 3 or not all(food(v) and v['kind'] == 'Base.BreadSlices' for v in all_slices) or not ids([v['id'] for v in all_slices]):
            return issues + ['Native SliceBread did not produce three distinct slices']
        for key in ('hunger', 'effectiveHunger', 'baseHunger', *NUTRIENTS):
            if any(not same(v[key], baked['bread'][key] / 3) for v in all_slices):
                fail('Native slices do not conserve the baked bread nutrition')
        if any(v['extras'] != baked['bread']['extras'] or v['spices'] != baked['bread']['spices'] or not v['cooked']
               or v['burnt'] or v['frozen'] or not same(v['effectiveHunger'], v['hunger'] * 1.3) for v in all_slices):
            fail('Native slice inheritance labels or cooked flags differ')
        chosen = next((v for v in all_slices if v['id'] == sandwich_base['id']), None)
        if not same(chosen, sandwich_base) or not same(slices, [v for v in all_slices if v['id'] != sandwich_base['id']]) or not same(row.get('sliceIds'), [v['id'] for v in all_slices]):
            fail('Sandwich used another slice or changed the two unused slices')
    elif not same(sandwich_base, p['base']) or slices != []:
        fail('Plain bread control was replaced by an enriched or fabricated base')
    if not same(row.get('actualSandwiches'), outputs) or not same(row.get('actualSlices'), slices):
        fail('Joining client food view disagrees with authoritative result')
    records = row.get('records', [])
    if not isinstance(records, list) or not all(isinstance(r, dict) for r in records):
        return issues + ['Native action observations are not objects']
    evolved = [r for r in records if r.get('kind') == 'evolved']
    transfers = [r for r in records if r.get('kind') == 'transfer']
    if len(evolved) != expected_count or [r.get('itemId') for r in evolved] != [m['id'] for m in seed_foods]:
        fail('Native ingredient applications are missing, duplicated or reordered')
    expected_dispatches = ([1, 1] if enriched else []) + [len(dispatches) - 1, len(dispatches)]
    expected_bases = ([p['base']['id']] * 2 if enriched else []) + [sandwich_base['id'], first_sandwich['id']]
    if any(not matches(r, dict(dispatch=dispatch, baseId=base, inputBefore=original))
           or type(r.get('dispatch')) is not int
           for r, dispatch, base, original in zip(evolved, expected_dispatches, expected_bases, seed_foods)):
        fail('Native applications do not match their original Cook dispatch and base')
    for r in records:
        if not matches(r, dict(progress=True, sourceMethodsUnchanged=True)):
            fail('Native action progress or unchanged callbacks missing')
        if type(r.get('dispatch')) is not int or not 1 <= r['dispatch'] <= len(dispatches):
            fail('Native action does not identify its original Cook dispatch')
        if r.get('kind') == 'evolved' and (not matches(r, dict(baseRoot=True, inputRoot=True, basePresent=True, inputPresent=True,
                cookingLevel=level)) or not number(r.get('duration')) or r['duration'] != 100 - level * 2.5):
            fail('Ingredient was applied without actual root ownership or native time')
    for original, dispatch in zip(seed_foods, expected_dispatches):
        related = [r for r in transfers if r.get('itemId') == original['id']]
        consumed = expected_cost(original, USES['Bread' if original['kind'] in USES['Bread'] else 'Sandwich'][original['kind']], level)[2]
        if len(related) != (1 if consumed else 2) or not related[0].get('pickup') or (not consumed and not related[1].get('returned')):
            fail('Original ingredient pickup or leftover return missing')
        if any(not number(r.get('transactionDuration')) or r['transactionDuration'] <= 1 for r in related):
            fail('Ingredient transfer was not paid natively')
        if any(r.get('dispatch') != dispatch for r in related):
            fail('Ingredient pickup or return crossed the original Cook dispatch')
    if enriched and len([r for r in records if r.get('kind') == 'slice' and r.get('duration') == 200]) != 1:
        fail('Native SliceBread cost/progress missing')
    owned = [p['base']['id'], p['book'], p['knife']['id'], *seed_by_id, *p['baselineOutputIds']]
    if not ids(owned + [sandwich['id']] + ([v['id'] for v in receipt.get('checkpoints', {}).get('Sliced', {}).get('slices', [])] if enriched else [])):
        fail('Input, baseline and output identities overlap')
    return issues


def verify(root, selection, catalog):
    from ..report import MARKER
    root, issues, outcomes = Path(root), [], []
    logs = {}
    for role in ('server', 'client1', 'client2'):
        try:
            logs[role] = (root / (role + '-launch.log')).read_text(errors='replace')
        except OSError as error:
            logs[role] = ''
            issues.append('Missing joined cooking log: ' + str(error))
    raw = []
    for match in re.finditer(r'\[CRAFT_UI_TEST\] (PREPARED|CHECKPOINT|VERIFIED|OBSERVED_BEFORE|OBSERVED) (.*)', logs['server']):
        try:
            value = json.loads(match.group(2))
            if not isinstance(value, dict):
                raise ValueError('receipt is not an object')
            raw.append((match.group(1), value))
        except (ValueError, TypeError) as error:
            issues.append('Invalid joining authority receipt: ' + str(error))
    records = {}
    for role in ('client1', 'client2'):
        records[role] = []
        for line in logs[role].splitlines():
            marker = OBSERVER_MARKER if OBSERVER_MARKER in line else MARKER
            if marker not in line:
                continue
            try:
                value = json.loads(line.split(marker, 1)[1])
                allowed = ('observer',) if marker == OBSERVER_MARKER else ('setup', 'case', 'complete', 'error')
                if not isinstance(value, dict) or value.get('event') not in allowed:
                    raise ValueError('invalid joining event envelope for ' + marker.strip())
                records[role].append(value)
            except (ValueError, TypeError) as error:
                issues.append('Invalid joining event in ' + role + ': ' + str(error))
    if any('[QUEUE_TEST] FAIL ' in text for text in logs.values()):
        issues.append('Native joining cooking fixture failed')
    cases = selection['cases']
    expected_raw = []
    for case in cases:
        expected_raw.extend([('PREPARED', case), ('OBSERVED_BEFORE', case)])
        expected_raw.extend([('CHECKPOINT', case)] * len(checkpoint_stages(case)))
        expected_raw.extend([('VERIFIED', case), ('OBSERVED', case)])
    if [(kind, value.get('case')) for kind, value in raw] != expected_raw:
        issues.append('Missing, duplicated or reordered joining authority/observer receipts')
    for role, rows in records.items():
        context = dict(suite='craft-ui', kind='mp', mode=selection['mode'], actor=role)
        if any(not matches(r, context) for r in rows):
            issues.append('Joining event context differs: ' + role)
        expected_events = ['setup'] + (['observer', 'observer', 'case'] * len(cases) if role == 'client1' else ['case'] * len(cases)) + ['complete']
        if [r.get('event') for r in rows] != expected_events:
            issues.append('Joining event sequence differs: ' + role)
        for event in ('setup', 'complete'):
            values = [r for r in rows if r.get('event') == event]
            expected = dict(cases=cases, expected=len(cases))
            if event == 'complete':
                expected.update(performed=0 if role == 'client1' else len(cases), failed=0, skipped=0)
                if role == 'client1':
                    expected['observed'] = len(cases)
            else:
                expected.update(queueEnabled=selection['mode'] == 'toolkit', nativeDurations=True)
            if len(values) != 1 or not matches(values[0], expected):
                issues.append('Joining ' + role + ' ' + event + ' evidence differs')
    case_issues = {}
    evidence = {}
    for case in cases:
        p = next((v for k, v in raw if k == 'PREPARED' and v.get('case') == case), {})
        receipt = next((v for k, v in raw if k == 'VERIFIED' and v.get('case') == case), {})
        actor = next((r for r in records['client2'] if r.get('event') == 'case' and r.get('id') == case), {})
        host = next((r for r in records['client1'] if r.get('event') == 'case' and r.get('id') == case), {})
        observations = [r for r in records['client1'] if r.get('event') == 'observer' and r.get('id') == case]
        before = next((r.get('snapshot') for r in observations if r.get('stage') == 'before'), {})
        after = next((r.get('snapshot') for r in observations if r.get('stage') == 'after'), {})
        cp_rows = [v for k, v in raw if k == 'CHECKPOINT' and v.get('case') == case]
        cps = {v.get('stage'): v.get('snapshot') for v in cp_rows}
        failures = check_case(selection, actor, p, receipt, before, after, cps)
        if [v.get('stage') for v in cp_rows] != checkpoint_stages(case):
            failures.append('Missing, duplicated or reordered native cooking checkpoint stages')
        if not matches(host, dict(status='observed', participation='observer', producerActor='client2', before=before, after=after)):
            failures.append('Host observer participation differs')
        for marker, stage in (('OBSERVED_BEFORE', before), ('OBSERVED', after)):
            rr = [v for k, v in raw if k == marker and v.get('case') == case]
            if len(rr) != 1 or not matches(rr[0], dict(actor='client1', snapshot=stage)):
                failures.append('Independent observer receipt disagrees with server transport log')
        case_issues[case] = failures
        issues.extend(failures)
        evidence[case] = dict(preparation=p, authority=receipt, actor=actor, host=host)
    for role in ('client1', 'client2'):
        for case in cases:
            reasons = issues if issues else case_issues[case]
            outcomes.append(dict(actor=role, case=case, status='failed' if reasons else 'passed',
                                 reason='; '.join(reasons), outcome=evidence[case][('host' if role == 'client1' else 'actor')]))
    return dict(issues=issues, outcomes=outcomes, evidence={'limits': [
        'Menu Host with a joining client2 producer and host client1 observing the real shared crate; private actor inventory is checked by actor2 and server, not independently exposed to the host.',
        'Plain bread and genuinely prepared/baked/sliced enriched bread; no fabricated food flags, shortened timed actions, dedicated-server or WAN coverage.',
        'Unchanged item count is permitted only when authoritative raw hunger and nutrition decrease by native partial-use rules.']})
