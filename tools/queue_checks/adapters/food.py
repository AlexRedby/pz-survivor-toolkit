"""Pending ordinary native food edits, exact item authority and queue-off controls."""
import json
from pathlib import Path
import re
import shutil

from . import craft, fluid

MOVE_CASE = 'food-root-move-same-portions'
CANCEL_CASE = 'food-root-cancel-first-portion'
BAG_CASE = 'food-bag-edit-pickup-return'
DEPLETION_CASE = 'food-root-depletion'
SMART_MOVE_CASE = 'food-smart-move-portions'
SMART_CANCEL_CASE = 'food-smart-cancel-first-portion'
SMART_CASES = (SMART_MOVE_CASE, SMART_CANCEL_CASE)
UTENSIL_MOVE_CASE = 'food-utensil-move-portions'
UTENSIL_CANCEL_CASE = 'food-utensil-cancel-first-portion'
UTENSIL_CASES = (UTENSIL_MOVE_CASE, UTENSIL_CANCEL_CASE)
COOKED_MOVE_CASE = 'food-cooked-move-portions'
COOKED_CANCEL_CASE = 'food-cooked-cancel-first-portion'
RAW_MOVE_CASE = 'food-raw-cookable-move-portions'
RAW_CANCEL_CASE = 'food-raw-cookable-cancel-first-portion'
COOKABLE_CASES = (COOKED_MOVE_CASE, COOKED_CANCEL_CASE, RAW_MOVE_CASE, RAW_CANCEL_CASE)
REPLACEMENT_MOVE_CASE = 'food-cooking-replacement-move-portions'
REPLACEMENT_CANCEL_CASE = 'food-cooking-replacement-cancel-first-portion'
REPLACEMENT_CASES = (REPLACEMENT_MOVE_CASE, REPLACEMENT_CANCEL_CASE)
CONSUMPTION_MOVE_CASE = 'food-consumption-replacement-move-portions'
CONSUMPTION_CANCEL_CASE = 'food-consumption-replacement-cancel-first-portion'
CONSUMPTION_CASES = (CONSUMPTION_MOVE_CASE, CONSUMPTION_CANCEL_CASE)
CASES = [MOVE_CASE, CANCEL_CASE, BAG_CASE, DEPLETION_CASE, *SMART_CASES, *UTENSIL_CASES, *COOKABLE_CASES, *REPLACEMENT_CASES, *CONSUMPTION_CASES]
# The full selected installation. Locked EatSmart debug logging leaves native completion unchanged.
MODS = next(line.split('=', 1)[1].split(';') for line in
            (Path(__file__).resolve().parents[3] / 'SurvivorQoL-selected.ini').read_text().splitlines()
            if line.startswith('Mods='))
RECEIPT_KEYS = {'case', 'bagId', 'bagType', 'bagCount', 'foodId', 'foodType', 'baseHunger', 'remaining',
                'source', 'foodCount', 'foodTypeCount', 'deleted', 'anchorId', 'anchorType', 'anchorAmount', 'anchorCount',
                'anchorThirstChange', 'hunger', 'thirst'}
UTENSIL_RECEIPT_KEYS = {'forkId', 'forkType', 'forkSource', 'forkCondition', 'forkCount',
                        'spoonId', 'spoonType', 'spoonSource', 'spoonCondition', 'spoonCount'}
UTENSIL_COMMAND_KEYS = {'useUtensil', 'utensilId', 'forkId', 'spoonId'}
COOKABLE_RECEIPT_KEYS = {'cookable', 'cooked', 'burnt', 'rotten', 'fertilized', 'heat', 'inventoryTemperature'}
COOKABLE_COMMAND_KEYS = {'cooked', 'dispatchHeat'}
REPLACEMENT_RECEIPT_KEYS = {'replacementType', 'replacementCount', 'cookingTime'}
CONSUMPTION_RECEIPT_KEYS = {'consumptionReplacementType', 'consumptionReplacementCount', 'foodWeight', 'customWeight', 'extraItems'}
FLAGS = {'emptyStart', 'anchorRunning', 'anchorProgress', 'anchorDuration', 'contractsVerified',
         'reordered', 'waitingCancel', 'moveRejected', 'cancelRejected', 'manualPickup',
         'untouchedBefore', 'nativeDurationsUnchanged', 'order'}
COMMAND_KEYS = {'id', 'portion', 'baseHunger', 'dispatchRemaining', 'dispatchSource', 'menuDispatched',
                'nativeDuration', 'progress', 'cancelled', 'pickupObserved'}


def definitions():
    common = {case: {'effectsVerified': True, 'pendingRequestsVerified': True} for case in CASES}
    edited = {case: {'effectsVerified': True, 'pendingEditsVerified': True} for case in CASES}
    actions = {'eat-portions': {
        'scope': 'Exact Base.Cereal half and quarter of original base hunger pending behind a real clean-water drink. Move the quarter before the half, or cancel the first portion; queue-off controls keep both in original order. A quarter followed by all must delete the original, and moving all before quarter is denied. No OnEat, replacements, utensils or smoking.',
        'mods': MODS, 'checks': {
            'success-queued': {case: common[case] for case in (MOVE_CASE, CANCEL_CASE, DEPLETION_CASE)},
            'repeat-same': {case: common[case] for case in (MOVE_CASE, DEPLETION_CASE)},
            'move-independent': {MOVE_CASE: edited[MOVE_CASE]},
            'move-dependent': {DEPLETION_CASE: edited[DEPLETION_CASE]},
            'cancel-waiting': {CANCEL_CASE: edited[CANCEL_CASE]},
            'server-authority': {case: {'effectsVerified': True, 'serverAuthorityVerified': True} for case in (MOVE_CASE, CANCEL_CASE, DEPLETION_CASE)}}},
        'eat-smart-portions': {
            'scope': 'Partly eaten Base.Cereal dispatched through public EatSmart ES_subMenuEat options with hunger goals 15 then 5. Both original-food fractions wait behind one clean-water drink; move the second first or cancel the first. Native controls execute both in original order. No physical menu input, OnEat, replacements, utensils or smoking.',
            'mods': MODS, 'checks': {
                'success-queued': {case: common[case] for case in SMART_CASES},
                'repeat-same': {case: common[case] for case in SMART_CASES},
                'move-independent': {SMART_MOVE_CASE: edited[SMART_MOVE_CASE]},
                'cancel-waiting': {SMART_CANCEL_CASE: edited[SMART_CANCEL_CASE]},
                'server-authority': {case: {'effectsVerified': True, 'serverAuthorityVerified': True} for case in SMART_CASES}}},
        'eat-utensils': {
            'scope': 'Base.OatsRaw original-food fractions .625 then .125 retain a captured native utensil from a worn army bag behind a clean-water drink. A valid bag fork wins over a root spoon; a broken root fork is excluded in favor of the bag spoon. Both native durations stay 232 with useUtensil. Move the second first or cancel the first; native controls retain both. No utensil transfers or active eating cancellation.',
            'mods': MODS, 'checks': {
                'success-queued': {case: common[case] for case in UTENSIL_CASES},
                'repeat-same': {case: common[case] for case in UTENSIL_CASES},
                'move-independent': {UTENSIL_MOVE_CASE: edited[UTENSIL_MOVE_CASE]},
                'cancel-waiting': {UTENSIL_CANCEL_CASE: edited[UTENSIL_CANCEL_CASE]},
                'server-authority': {case: {'effectsVerified': True, 'serverAuthorityVerified': True} for case in UTENSIL_CASES}}},
        'eat-cookable': {
            'scope': 'Fresh unburnt cooked Base.ChickenFillet and raw cookable Base.Cabbage original-food fractions .5 then .25 wait behind a clean-water drink at safe carried heat. Native durations stay 232. Move the second first or cancel the first; native controls retain both. Cooked hunger uses the native 1.3 multiplier while remaining food uses raw base hunger. No utensils, cooking transition, active eating cancellation or physical menu input.',
            'mods': MODS, 'checks': {
                'success-queued': {case: common[case] for case in COOKABLE_CASES},
                'repeat-same': {case: common[case] for case in COOKABLE_CASES},
                'move-independent': {case: edited[case] for case in (COOKED_MOVE_CASE, RAW_MOVE_CASE)},
                'cancel-waiting': {case: edited[case] for case in (COOKED_CANCEL_CASE, RAW_CANCEL_CASE)},
                'server-authority': {case: {'effectsVerified': True, 'serverAuthorityVerified': True} for case in COOKABLE_CASES}}},
        'eat-cooking-replacement': {
            'scope': 'Cold raw Base.BreadSlices with native ReplaceOnCooked=Base.Toast retains its exact original item and original-food fractions .5 then .25 behind a clean-water drink. Native durations stay 232. Move the second first or cancel the first; native controls retain both. Cooking time stays zero and no Toast is added. No active or hot cooking, cooking callbacks, utensils, active eating cancellation or physical menu input.',
            'mods': MODS, 'checks': {
                'success-queued': {case: common[case] for case in REPLACEMENT_CASES},
                'repeat-same': {case: common[case] for case in REPLACEMENT_CASES},
                'move-independent': {REPLACEMENT_MOVE_CASE: edited[REPLACEMENT_MOVE_CASE]},
                'cancel-waiting': {REPLACEMENT_CANCEL_CASE: edited[REPLACEMENT_CANCEL_CASE]},
                'server-authority': {case: {'effectsVerified': True, 'serverAuthorityVerified': True} for case in REPLACEMENT_CASES}}},
        'eat-consumption-replacement': {
            'scope': 'Base.CannedPeachesOpen with native ReplaceOnUse=Base.TinCanEmpty retains the exact original food through original-food fractions .5 then .25 behind a clean-water drink. Native durations stay 232. Move the second first or cancel the first; native controls retain both. Native partial weight keeps the .2 can and remaining .6 food; no empty can is added. No full depletion, custom weight, extra items, utensils, cooking, active eating cancellation or physical menu input.',
            'mods': MODS, 'checks': {
                'success-queued': {case: common[case] for case in CONSUMPTION_CASES},
                'repeat-same': {case: common[case] for case in CONSUMPTION_CASES},
                'move-independent': {CONSUMPTION_MOVE_CASE: edited[CONSUMPTION_MOVE_CASE]},
                'cancel-waiting': {CONSUMPTION_CANCEL_CASE: edited[CONSUMPTION_CANCEL_CASE]},
                'server-authority': {case: {'effectsVerified': True, 'serverAuthorityVerified': True} for case in CONSUMPTION_CASES}}},
        'eat-transfers': {
            'scope': 'A native manual cereal grab and standalone half-eat/return pending behind a real drink. Move an already-destination return before pickup; deny pickup removal and pickup-after-eat. Native controls retain pickup/eat/return and finish in the bag.',
            'mods': MODS, 'checks': {
                'success-queued': {BAG_CASE: common[BAG_CASE]},
                'move-dependent': {BAG_CASE: edited[BAG_CASE]},
                'server-authority': {BAG_CASE: {'effectsVerified': True, 'serverAuthorityVerified': True}}}}}
    return {'food': {'status': 'ready', 'clients': 1, 'default_mods': MODS, 'scenario_actions': actions,
                     'cases': [dict(id=case, producer='fixture', capability='effect', kinds=['sp', 'mp'],
                                    languages=['EN'], modes=['native', 'toolkit']) for case in CASES]}}


def validate(selection):
    cases = selection.get('cases')
    if (type(cases) is not list or not cases or cases != [case for case in CASES if case in cases]
            or selection.get('kind') not in ('sp', 'mp') or selection.get('mode') not in ('native', 'toolkit')
            or selection.get('languages') != ['EN'] or type(selection.get('clients', 1)) is not int
            or selection.get('clients', 1) != 1 or not set(MODS) <= set(selection.get('mods', []))
            or selection.get('options', {}).get('world_template')
            or selection['kind'] == 'mp' and selection.get('options', {}).get('mp_host') is not True):
        raise ValueError('Food requires ordered registered cases, fresh SP/Host, one EN client and the full selected mod set')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / 'food').rglob('*.lua')), *sorted((root / 'craft/scripts').rglob('*.txt')),
            root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueScenarioChecks.lua',
            Path(project) / 'SurvivorQoL-selected.ini',
            *sorted((root / 'startup').rglob('*.lua'))]


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    craft.stage_common(project, output, game, jdk, selection, locations, runtime)
    for role in runtime['roles'].values():
        shutil.copy2(Path(project) / 'tests/native_queue/support/QueueScenarioChecks.lua',
                     Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua/shared')


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(r'\[FOOD_TEST\] COMPLETE(?:\s|$)', text)) == 1


def _authority(text):
    result = []
    for match in re.finditer(r'\[FOOD_TEST\] (PREPARED|VERIFIED)(?:\s|$)([^\n]*)', text):
        marker, payload = match.groups()
        value = json.loads(payload)
        if type(value) is not dict:
            raise ValueError('Invalid food authoritative envelope')
        result.append((marker, value))
    return result


def _case(case, row, prep, receipt, kind='sp', mode='toolkit'):
    issues = []
    bag, enabled, depletion = case == BAG_CASE, mode == 'toolkit', case == DEPLETION_CASE
    smart, utensil, cookable = case in SMART_CASES, case in UTENSIL_CASES, case in COOKABLE_CASES
    replacement = case in REPLACEMENT_CASES
    consumption = case in CONSUMPTION_CASES
    thermal = cookable or replacement
    cooked = case in (COOKED_MOVE_CASE, COOKED_CANCEL_CASE)
    base_hunger = -.15 if consumption else -.1 if replacement else -.3 if cooked else -.24 if cookable else -.5 if utensil else -.4
    food_type = 'Base.CannedPeachesOpen' if consumption else 'Base.BreadSlices' if replacement else 'Base.ChickenFillet' if cooked else 'Base.Cabbage' if cookable else 'Base.OatsRaw' if utensil else 'Base.Cereal'
    receipt_keys = RECEIPT_KEYS | (UTENSIL_RECEIPT_KEYS if utensil else set()) | (COOKABLE_RECEIPT_KEYS if thermal else set()) | (REPLACEMENT_RECEIPT_KEYS if replacement else set()) | (CONSUMPTION_RECEIPT_KEYS if consumption else set())
    identity_keys = ('bagId', 'foodId', 'anchorId') + (('forkId', 'spoonId') if utensil else ())
    if not utensil and UTENSIL_RECEIPT_KEYS & set(row):
        return ['Food unexpected utensil evidence: ' + case]
    if not thermal and COOKABLE_RECEIPT_KEYS & set(row):
        return ['Food unexpected cookable evidence: ' + case]
    if not replacement and REPLACEMENT_RECEIPT_KEYS & set(row):
        return ['Food unexpected cooking replacement evidence: ' + case]
    if not consumption and CONSUMPTION_RECEIPT_KEYS & set(row):
        return ['Food unexpected consumption replacement evidence: ' + case]
    cancelled = case in (CANCEL_CASE, SMART_CANCEL_CASE, UTENSIL_CANCEL_CASE, COOKED_CANCEL_CASE, RAW_CANCEL_CASE, REPLACEMENT_CANCEL_CASE, CONSUMPTION_CANCEL_CASE) and enabled
    if (set(prep) != receipt_keys | {'foodTimer', 'foodLevel'}
            or not craft._matches(prep, dict(case=case, bagType=fluid.BAG_TYPE, bagCount=1, foodType=food_type,
                source='bag' if bag else 'root', foodCount=1, deleted=False, anchorType='Base.WaterBottle', anchorCount=1,
                foodTimer=0, foodLevel=0))
            or not craft._ids([prep.get(key) for key in identity_keys], len(identity_keys))
            or any(not fluid._close(prep.get(key), value) for key, value in
                   dict(baseHunger=base_hunger, remaining=-.3 if smart else base_hunger, anchorAmount=1,
                        hunger=.2 if smart else .8, thirst=.8).items())
            or type(prep.get('foodTypeCount')) is not int or prep['foodTypeCount'] < 1
            or not fluid._number(prep.get('anchorThirstChange')) or prep['anchorThirstChange'] >= 0):
        return ['Food preparation identity/state differs: ' + case]
    if thermal and (not craft._matches(prep, dict(cookable=True, cooked=cooked, burnt=False, rotten=False,
                                                fertilized=False, inventoryTemperature=1))
                     or not fluid._close(prep.get('heat'), 1)):
        return ['Food preparation cookable state differs: ' + case]
    if replacement and (prep.get('replacementType') != 'Base.Toast'
                        or type(prep.get('replacementCount')) is not int or prep['replacementCount'] < 0
                        or not fluid._number(prep.get('cookingTime')) or prep['cookingTime'] != 0):
        return ['Food preparation cooking replacement state differs: ' + case]
    if consumption and (not craft._matches(prep, dict(consumptionReplacementType='Base.TinCanEmpty', customWeight=False, extraItems=False))
                        or type(prep.get('consumptionReplacementCount')) is not int or prep['consumptionReplacementCount'] < 0
                        or not fluid._close(prep.get('foodWeight'), .8, 1e-5)):
        return ['Food preparation consumption replacement state differs: ' + case]
    if utensil and (not craft._matches(prep, dict(forkType='Base.Fork', spoonType='Base.Spoon',
            forkSource='bag' if case == UTENSIL_MOVE_CASE else 'root',
            spoonSource='root' if case == UTENSIL_MOVE_CASE else 'bag', forkCount=1, spoonCount=1))
            or type(prep.get('forkCondition')) is not int
            or (prep['forkCondition'] <= 0 if case == UTENSIL_MOVE_CASE else prep['forkCondition'] != 0)
            or type(prep.get('spoonCondition')) is not int or prep['spoonCondition'] <= 0):
        return ['Food preparation utensil identity/state differs: ' + case]
    fixed = {key: prep[key] for key in receipt_keys - {'remaining', 'source', 'hunger', 'thirst', 'anchorAmount', 'foodCount', 'foodTypeCount', 'deleted', 'anchorThirstChange', 'heat', 'foodWeight'}}
    fixed.update(source='deleted' if depletion else 'root' if not bag or enabled else 'bag',
                 foodCount=0 if depletion else 1, foodTypeCount=prep['foodTypeCount'] - int(depletion), deleted=depletion)
    portion = (.125 if cancelled else .75) if utensil else (.375 if cancelled else .5) if smart else 1 if depletion else .5 if bag else .25 if cancelled else .75
    commands = row.get('commands')
    if (smart and type(commands) is list and len(commands) == 2
            and all(type(command) is dict and fluid._number(command.get('portion')) for command in commands)):
        portion = sum(command['portion'] for index, command in enumerate(commands) if not (cancelled and index == 0))
    expected_remaining = prep['remaining'] - prep['baseHunger'] * portion if smart else prep['baseHunger'] * (1 - portion)
    if (set(receipt) != receipt_keys or not craft._matches(receipt, fixed)
            or not craft._matches(row, receipt) or type(row.get('client')) is not dict
            or set(row['client']) != receipt_keys
            or not craft._matches(row['client'], {key: receipt[key] for key in receipt_keys - {'hunger', 'thirst'}})
            or thermal and (not fluid._number(receipt.get('heat')) or not 0 <= receipt['heat'] <= 1.6)
            or consumption and not fluid._close(receipt.get('foodWeight'), .2 + .6 * (1 - portion), 1e-5)
            or any(not fluid._close(row['client'].get(field), receipt.get(field), .01) for field in ('hunger', 'thirst'))
            or not fluid._close(receipt.get('remaining'), expected_remaining)
            or not fluid._number(receipt.get('anchorAmount')) or not .49 <= receipt['anchorAmount'] <= .5001
            or not fluid._close(receipt.get('anchorThirstChange'),
                                prep['anchorThirstChange'] * receipt['anchorAmount'] / prep['anchorAmount'])):
        return ['Food authority/client identity or consumption differs: ' + case]
    expected_hunger = prep['hunger'] + prep['baseHunger'] * portion * (1.3 if cooked else 1)
    expected_thirst = prep['thirst'] + (prep['anchorAmount'] - receipt['anchorAmount']) * prep['anchorThirstChange'] / prep['anchorAmount']
    if cookable and not cooked:
        # Native Base.Cabbage ThirstChange=-10 applies to each original-food fraction.
        expected_thirst -= .1 * portion
    if not fluid._close(receipt.get('hunger'), expected_hunger, .01) or not fluid._close(receipt.get('thirst'), expected_thirst, .01):
        issues.append('Food hunger or clean-water anchor effect differs: ' + case)
    if not craft._matches(row, dict(status='passed', reason=None)):
        issues.append('Food native status differs: ' + case)
    portions = [.625, .125] if utensil else [.125, .375] if smart else [.25, 1] if depletion else [.5] if bag else [.5, .25]
    if type(commands) is not list or len(commands) != len(portions):
        issues.append('Food native command count differs: ' + case)
    else:
        for index, (command, fraction) in enumerate(zip(commands, portions)):
            cancel = cancelled and index == 0
            expected = dict(id=prep['foodId'], portion=fraction, baseHunger=prep['baseHunger'], dispatchRemaining=prep['remaining'],
                dispatchSource='bag' if bag else 'root', menuDispatched=not bag, nativeDuration=464 if fraction == 1 else 232,
                progress=not cancel, cancelled=cancel, pickupObserved=bag)
            if utensil:
                expected.update(useUtensil=True, utensilId=prep['forkId' if case == UTENSIL_MOVE_CASE else 'spoonId'],
                                forkId=prep['forkId'] if case == UTENSIL_MOVE_CASE else -1, spoonId=prep['spoonId'])
            if thermal:
                expected['cooked'] = cooked
            if smart:
                expected.pop('portion')
                expected['smartGoal'] = 15 if index == 0 else 5
            if (type(command) is not dict or set(command) != COMMAND_KEYS | ({'smartGoal', 'dispatchHunger'} if smart else set()) | (UTENSIL_COMMAND_KEYS if utensil else set()) | (COOKABLE_COMMAND_KEYS if thermal else set())
                    or not craft._matches(command, {key: value for key, value in expected.items() if key != 'smartGoal'})
                    or thermal and (not fluid._number(command.get('dispatchHeat')) or not 0 <= command['dispatchHeat'] <= 1.6)
                    or smart and (not fluid._number(command.get('smartGoal'))
                                  or command['smartGoal'] != expected['smartGoal']
                                  or not fluid._close(command.get('dispatchHunger'), prep['hunger'], .01)
                                  or not fluid._close(command.get('portion'),
                                      (command['dispatchHunger'] - expected['smartGoal'] / 100) / -prep['baseHunger'], 1e-6))):
                issues.append('Food native target/original portion/progress/duration differs: ' + case)
    evidence = row.get('editEvidence')
    expected = dict(emptyStart=True, anchorRunning=True, anchorProgress=True, anchorDuration=460,
        contractsVerified=enabled, reordered=enabled and case in (MOVE_CASE, BAG_CASE, SMART_MOVE_CASE, UTENSIL_MOVE_CASE, COOKED_MOVE_CASE, RAW_MOVE_CASE, REPLACEMENT_MOVE_CASE, CONSUMPTION_MOVE_CASE), waitingCancel=cancelled,
        moveRejected=enabled and (bag or depletion), cancelRejected=enabled and bag, manualPickup=bag,
        untouchedBefore=True, nativeDurationsUnchanged=True,
        order=[1] if bag else [1, 2] if depletion else [2] if cancelled else [2, 1] if enabled else [1, 2])
    if type(evidence) is not dict or set(evidence) != FLAGS | ({'pickupDuration', 'returnDuration', 'returning'} if bag else set()) | ({'denialReason'} if depletion else set()) or not craft._matches(evidence, expected):
        issues.append('Food pending native edit/order evidence differs: ' + case)
    elif depletion and not craft._matches(evidence, dict(denialReason='edit_resource_amount' if enabled else 'not-requested')):
        issues.append('Food depletion dependency denial differs: ' + case)
    elif bag:
        returning = evidence.get('returning')
        if (any(not fluid._number(evidence[field]) or (evidence[field] != -1 if kind == 'mp' else evidence[field] <= 0)
                for field in ('pickupDuration', 'returnDuration'))
                or type(returning) is not dict or set(returning) != {'boundary', 'completed', 'observationFailed', 'before', 'after', 'started', 'transactionId', 'dontAdd'}
                or not craft._matches(returning, dict(boundary=True, completed=True, observationFailed=False,
                    before='bag' if enabled else 'root', after='bag', started=False, transactionId=0))
                or type(returning.get('dontAdd')) is not bool):
            issues.append('Food native transfer duration/return boundary differs: ' + case)
    return issues


def verify(root, selection, catalog):
    from ..report import events
    root = Path(root)
    client = (root / 'client1-launch.log').read_text(errors='replace')
    authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else client
    rows, raw, cases = events(client), _authority(authority), selection['cases']
    results = [row for row in rows if row['event'] == 'case']
    issues, identities, outcomes = [], [], []
    if not complete(selection, 'client1', client):
        issues.append('Missing or duplicate food completion marker')
    if [row['event'] for row in rows] != ['setup'] + ['case'] * len(cases) + ['complete']:
        issues.append('Missing, duplicate or reordered food events')
    if any(not craft._matches(row, dict(suite='food', kind=selection['kind'], mode=selection['mode'], actor='client1')) for row in rows):
        issues.append('Food event context differs')
    if [row.get('id') for row in results] != cases:
        issues.append('Food case selection/order differs')
    for event, expected in [('setup', dict(cases=cases, expected=len(cases), queueEnabled=selection['mode'] == 'toolkit', nativeDurations=True)),
                            ('complete', dict(cases=cases, expected=len(cases), performed=len(cases), failed=0, skipped=0))]:
        records = [row for row in rows if row['event'] == event]
        if len(records) != 1 or not craft._matches(records[0], expected):
            issues.append('Food ' + event + ' evidence differs')
    if [(marker, value.get('case')) for marker, value in raw] != [(marker, case) for case in cases for marker in ('PREPARED', 'VERIFIED')]:
        issues.append('Missing, duplicate or reordered food authority')
    for case in cases:
        row = next((row for row in results if row.get('id') == case), {})
        prep = next((value for marker, value in raw if marker == 'PREPARED' and value.get('case') == case), {})
        receipt = next((value for marker, value in raw if marker == 'VERIFIED' and value.get('case') == case), {})
        case_issues = _case(case, row, prep, receipt, selection['kind'], selection['mode'])
        issues.extend(case_issues)
        identities += [prep.get(field) for field in ('bagId', 'foodId', 'anchorId', 'forkId', 'spoonId')
                       if case in UTENSIL_CASES or field not in ('forkId', 'spoonId')]
        outcome = {key: row.get(key) for key in RECEIPT_KEYS | (UTENSIL_RECEIPT_KEYS if case in UTENSIL_CASES else set()) | (COOKABLE_RECEIPT_KEYS if case in (*COOKABLE_CASES, *REPLACEMENT_CASES) else set()) | (REPLACEMENT_RECEIPT_KEYS if case in REPLACEMENT_CASES else set()) | (CONSUMPTION_RECEIPT_KEYS if case in CONSUMPTION_CASES else set()) | {'commands', 'editEvidence', 'client'}}
        outcome.update(effectsVerified=not case_issues, pendingRequestsVerified=not case_issues, pendingEditsVerified=not case_issues and selection['mode'] == 'toolkit',
                       serverAuthorityVerified=not case_issues and selection['kind'] == 'mp')
        outcomes.append(dict(actor='client1', case=case, outcome=outcome))
    if not craft._ids(identities):
        issues.append('Food fixture identities overlap between cases')
    if '[QUEUE_TEST] FAIL ' in client or '[QUEUE_TEST] FAIL ' in authority:
        issues.append('Native food fixture failed')
    for outcome in outcomes:
        outcome.update(status='failed' if issues else 'passed', reason='; '.join(issues))
    return {'issues': issues, 'outcomes': outcomes, 'evidence': {'limits': [
        'Base.Cereal native/public EatSmart, Base.OatsRaw native utensils, cooked Base.ChickenFillet and raw cookable Base.Cabbage pending edits only; full selected mod set, real native actions and durations.',
        'Callback-driven menu dispatch does not establish physical input or visual correctness.',
        'Cold Base.BreadSlices keeps ReplaceOnCooked dormant with zero cooking time and unchanged Base.Toast count; no active or hot cooking or callback coverage.',
        'Partial Base.CannedPeachesOpen keeps its original identity, native can-plus-food weight and unchanged Base.TinCanEmpty count; no full depletion coverage.',
        'No OnEat, smoking, utensil transfers, active eating cancellation or WAN coverage.']}}
