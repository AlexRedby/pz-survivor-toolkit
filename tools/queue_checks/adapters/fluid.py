"""Native drink menus with exact bottle identities and bounded fluid effects."""
import json
import math
from pathlib import Path
import re
import shutil

from . import craft

EDIT_CASE = 'fluid-bag-edit-pickup-return-favorite'
EMPTY_MOVE_CASE = 'fluid-empty-move-independent'
EMPTY_CANCEL_CASE = 'fluid-empty-cancel-waiting'
EMPTY_DEPENDENCY_CASE = 'fluid-empty-drink-dependency'
EMPTY_CASES = (EMPTY_MOVE_CASE, EMPTY_CANCEL_CASE, EMPTY_DEPENDENCY_CASE)
CASES = ['fluid-bag', 'fluid-root', 'fluid-bag-favorite', 'fluid-root-favorite',
         'fluid-bag-all-favorite', 'fluid-bag-quarter-favorite', 'fluid-bag-smart-favorite',
         'fluid-bag-sip-favorite', 'fluid-bag-second-favorite', 'fluid-bag-pair-queued-favorite',
         'fluid-bag-pair-serial-favorite', 'fluid-bag-smart-low-favorite',
         'fluid-bag-full-favorite', 'fluid-root-full-favorite',
         'fluid-bag-same-serial-favorite', 'fluid-root-same-queued-favorite',
         'fluid-root-cancel-waiting-favorite', 'fluid-bag-cancel-waiting-favorite', EDIT_CASE, *EMPTY_CASES]
MODS = craft.MODS + ['Drink_Smart']
RECEIPT_KEYS = {'bagId', 'bagType', 'thirst', 'bottles', 'foodLevel'}
BAG_TYPE = 'Base.Bag_ALICEpack_Army'


def definitions():
    groups = {
        'drink-portions': ('Native portions from root or a worn military backpack; favorite bottles, queued halves and serial quarters with native SP/Host semantics and waiting cancellation.',
                           [case for case in CASES if '-smart-' not in case and '-sip-' not in case and case != EDIT_CASE and case not in EMPTY_CASES]),
        'drink-smart': ('Drink Smart from a worn military backpack with favorite bottles at normal and low thirst.',
                        [case for case in CASES if '-smart-' in case]),
        'drink-sip': ('Drink Smart sip from a worn military backpack with favorite bottles.',
                      ['fluid-bag-sip-favorite']),
    }
    actions = {}
    for name, (scope, cases) in groups.items():
        checks = {
            'success-empty': {case: {'emptyStartVerified': True, 'effectsVerified': True, 'wornBagVerified': True} for case in cases},
            'server-authority': {case: {'serverAuthorityVerified': True, 'effectsVerified': True} for case in cases},
        }
        if name == 'drink-portions':
            checks['repeat-independent'] = {'fluid-bag-pair-queued-favorite': {'independentRequestsQueued': True, 'effectsVerified': True}}
            checks['repeat-same'] = {case: {'sameBottleRequestsVerified': True, 'effectsVerified': True} for case in cases if '-same-' in case}
            checks['cancel-waiting'] = {case: {'waitingCancelVerified': True, 'effectsVerified': True} for case in cases if '-cancel-' in case}
            checks['move-independent'] = {'fluid-root-cancel-waiting-favorite': {'independentMoveVerified': True, 'effectsVerified': True}}
        actions[name] = {'scope': scope, 'mods': MODS, 'checks': checks}
    actions['drink-transfers'] = {
        'scope': 'A real running drink anchors a native manual grab and standalone drink/return actions for another favorite bottle. Toolkit moves an already-destination return before pickup, rejects removal/reordering of the required pickup, and preserves native costs; disabled controls retain the original order and finish in the bag.',
        'mods': MODS, 'toolkit_only': ['success-queued'], 'checks': {
            'success-empty': {EDIT_CASE: {'emptyStartVerified': True, 'effectsVerified': True, 'wornBagVerified': True}},
            'success-queued': {EDIT_CASE: {'pendingTransferEditVerified': True, 'effectsVerified': True}},
            'move-dependent': {EDIT_CASE: {'dependentPickupProtected': True, 'effectsVerified': True}},
            'server-authority': {EDIT_CASE: {'serverAuthorityVerified': True, 'effectsVerified': True}},
        }}
    actions['empty-water'] = {
        'scope': 'Raw native ISFluidEmptyAction on exact carried root Base.WaterBottle clean-water containers, queued behind a real native half-drink from separate bottle A. Move independent pending empty C before B, cancel waiting B while C finishes, or reject moving Empty B ahead of its required native half-drink. Disabled controls retain original order. Exact client/server IDs, counts, root sources, native weights, water amounts, captured amount, progress and unmodified constructor durations are checked. The dependency records B after drinking before emptying; discarded water does not reduce thirst. No physical/menu input, active cancellation, world endpoints or transfer-capacity coverage.',
        'mods': MODS, 'checks': {
            'success-queued': {case: {'pendingEmptyVerified': True, 'effectsVerified': True} for case in EMPTY_CASES},
            'move-independent': {EMPTY_MOVE_CASE: {'independentMoveVerified': True, 'effectsVerified': True}},
            'cancel-waiting': {EMPTY_CANCEL_CASE: {'waitingCancelVerified': True, 'effectsVerified': True}},
            'move-dependent': {EMPTY_DEPENDENCY_CASE: {'dependentEmptyProtected': True, 'effectsVerified': True}},
            'server-authority': {case: {'serverAuthorityVerified': True, 'effectsVerified': True} for case in EMPTY_CASES}}}
    return {'fluid': {'status': 'ready', 'clients': 1, 'default_mods': MODS, 'scenario_actions': actions,
                      'cases': [{'id': case, 'producer': 'fixture', 'capability': 'effect',
                                 'kinds': ['sp', 'mp'], 'languages': ['EN'], 'modes': ['native', 'toolkit']}
                                for case in CASES]}}


def validate(selection):
    cases = selection.get('cases')
    if (type(cases) is not list or not cases or cases != [case for case in CASES if case in cases]
            or selection.get('kind') not in ('sp', 'mp') or selection.get('mode') not in ('native', 'toolkit')
            or selection.get('languages') != ['EN'] or type(selection.get('clients', 1)) is not int
            or selection.get('clients', 1) != 1 or not set(MODS) <= set(selection.get('mods', []))
            or selection.get('options', {}).get('world_template')):
        raise ValueError('Fluid requires ordered registered cases, fresh SP/Host, one EN client and Drink Smart')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / 'fluid').rglob('*.lua')), *sorted((root / 'craft/scripts').rglob('*.txt')),
            root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueScenarioChecks.lua',
            *sorted((root / 'startup').rglob('*.lua'))]


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    craft.stage_common(project, output, game, jdk, selection, locations, runtime)
    for role in runtime['roles'].values():
        shutil.copy2(Path(project) / 'tests/native_queue/support/QueueScenarioChecks.lua',
                     Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua/shared')


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(r'\[FLUID_TEST\] COMPLETE(?:\s|$)', text)) == 1


def _authority(text):
    result = []
    for match in re.finditer(r'\[FLUID_TEST\] (PREPARED|VERIFIED)(?:\s|$)([^\n]*)', text):
        marker, payload = match.groups()
        value = json.loads(payload)
        if type(value) is not dict:
            raise ValueError('Invalid fluid authoritative envelope')
        result.append((marker, value))
    return result


def _number(value):
    return type(value) in (int, float) and math.isfinite(value)


def _close(value, expected, tolerance=.0001):
    return _number(value) and abs(value - expected) <= tolerance


def _commands(case):
    menu = next((name for name in ('all', 'quarter', 'smart', 'sip') if name in case.split('-')), 'half')
    if '-same-serial-' in case: menu = 'quarter'
    portion = {'half': .5, 'all': 1, 'quarter': .25, 'sip': .01}.get(menu)
    targets = [0, 1] if case == EDIT_CASE else [0, 1, 2] if '-cancel-' in case else [0, 0] if '-same-' in case else [0, 1] if '-pair-' in case else [1] if '-second-' in case else [0]
    return menu, portion, targets


EMPTY_BOTTLE_KEYS = {'id', 'amount', 'favorite', 'source', 'count', 'weight', 'fullType', 'capacity',
                     'transferRate', 'cleanWater', 'emptyWeight'}
EMPTY_COMMAND_KEYS = {'kind', 'id', 'source', 'dispatchAmount', 'dispatchWeight', 'nativeDuration',
                      'progress', 'cancelled', 'rawDispatched'}
EMPTY_EDIT_KEYS = {'emptyStart', 'anchorRunning', 'contractsVerified', 'reordered', 'waitingCancel', 'moveRejected',
                   'denialReason', 'untouchedBefore', 'nativeDurationsUnchanged', 'order',
                   'drinkBCompleted', 'drinkBRemaining', 'drinkBBoundaryFailed'}


def _empty_case(case, row, prep, receipt, kind, mode):
    enabled = mode == 'toolkit'
    cancelled = enabled and case == EMPTY_CANCEL_CASE
    dependency = case == EMPTY_DEPENDENCY_CASE
    reordered = enabled and case == EMPTY_MOVE_CASE
    bottles = prep.get('bottles')
    if (set(prep) != RECEIPT_KEYS | {'case', 'foodTimer'}
            or not craft._matches(prep, dict(case=case, bagType=BAG_TYPE, foodTimer=0, foodLevel=0))
            or not _close(prep.get('thirst'), .8, .00001)
            or type(bottles) is not list or len(bottles) != 3
            or any(type(bottle) is not dict or set(bottle) != EMPTY_BOTTLE_KEYS | {'thirstChange'}
                   or not craft._matches(bottle, dict(fullType='Base.WaterBottle', source='root', count=1,
                                                       favorite=False, cleanWater=True))
                   or any(not _close(bottle.get(key), value, .00001) for key, value in
                          dict(amount=1, capacity=1, emptyWeight=.1, weight=1.1, thirstChange=-.5).items())
                   or not _number(bottle.get('transferRate')) or bottle['transferRate'] < 0 for bottle in bottles)
            or not craft._ids([prep.get('bagId')] + [bottle.get('id') for bottle in bottles], 4)):
        return ['Empty-fluid preparation identity/state differs: ' + case]
    final = receipt.get('bottles')
    if (set(receipt) != RECEIPT_KEYS | {'case'}
            or not craft._matches(receipt, dict(case=case, bagId=prep['bagId'], bagType=BAG_TYPE, foodLevel=0))
            or type(final) is not list or len(final) != 3
            or not craft._matches(row, {key: receipt[key] for key in RECEIPT_KEYS})
            or type(row.get('client')) is not dict or set(row['client']) != set(receipt)):
        return ['Empty-fluid authority/client schema differs: ' + case]
    for index, (bottle, original) in enumerate(zip(final, bottles)):
        if (type(bottle) is not dict or set(bottle) != EMPTY_BOTTLE_KEYS
                or not craft._matches(bottle, {key: original[key] for key in EMPTY_BOTTLE_KEYS - {'amount', 'weight'}})
                or not _number(bottle.get('amount')) or not 0 <= bottle['amount'] <= original['amount']
                or not _close(bottle.get('weight'), original['emptyWeight'] + bottle['amount'], .00001)):
            return ['Empty-fluid exact bottle identity/load differs: ' + case]
        expected_amount = None if index == 0 else 1 if index == 1 and cancelled or index == 2 and dependency else 0
        if expected_amount is not None and not _close(bottle['amount'], expected_amount, .000001):
            return ['Empty-fluid final empty/retained amount differs: ' + case]
    if not .49 <= final[0]['amount'] <= .5001:
        return ['Empty-fluid native anchor amount differs: ' + case]
    client = row['client']
    if not craft._matches(client, {key: receipt[key] for key in set(receipt) - {'thirst'}}) or not _close(client.get('thirst'), receipt.get('thirst'), .01):
        return ['Empty-fluid client authority disagreement: ' + case]
    evidence = row.get('editEvidence')
    expected_order = [1, 3, 2] if reordered else [1, 3] if cancelled else [1, 2, 3]
    if (type(evidence) is not dict or set(evidence) != EMPTY_EDIT_KEYS
            or not craft._matches(evidence, dict(emptyStart=True, anchorRunning=True, contractsVerified=enabled,
                reordered=reordered, waitingCancel=cancelled, moveRejected=enabled and dependency,
                denialReason='edit_resource_amount' if enabled and dependency else 'not-requested',
                untouchedBefore=True, nativeDurationsUnchanged=True, order=expected_order,
                drinkBCompleted=dependency, drinkBBoundaryFailed=False))
            or not _number(evidence.get('drinkBRemaining'))
            or (not .49 <= evidence['drinkBRemaining'] <= .5001 if dependency else evidence['drinkBRemaining'] != -1)):
        return ['Empty-fluid pending edit/native order evidence differs: ' + case]
    expected_thirst = prep['thirst'] + (1 - final[0]['amount']) * bottles[0]['thirstChange']
    if dependency:
        expected_thirst += (1 - evidence['drinkBRemaining']) * bottles[1]['thirstChange']
    if not _close(receipt.get('thirst'), expected_thirst, .01):
        return ['Empty-fluid discard changed thirst or native drink effect differs: ' + case]
    if not craft._matches(row, dict(status='passed', reason=None, waitingCancelVerified=cancelled,
                                    independentMoveVerified=reordered)):
        return ['Empty-fluid case status/control differs: ' + case]
    commands = row.get('commands')
    targets = [(0, 'drink'), (1, 'drink'), (1, 'empty')] if dependency else [(0, 'drink'), (1, 'empty'), (2, 'empty')]
    if type(commands) is not list or len(commands) != 3:
        return ['Empty-fluid native command count differs: ' + case]
    for position, (command, (target, action)) in enumerate(zip(commands, targets)):
        cancel = cancelled and position == 1
        extra_keys = {'portion'} if action == 'drink' else {'capturedAmount', 'transferRate', 'timePerLiter', 'minTime'}
        if (type(command) is not dict or set(command) != EMPTY_COMMAND_KEYS | extra_keys
                or not craft._matches(command, dict(kind=action, id=bottles[target]['id'], source='root',
                                                     progress=not cancel, cancelled=cancel, rawDispatched=True))
                or not _close(command.get('dispatchAmount'), 1, .00001)
                or not _close(command.get('dispatchWeight'), bottles[target]['weight'], .00001)):
            return ['Empty-fluid native target/dispatch/progress differs: ' + case]
        if action == 'drink':
            if not craft._matches(command, dict(nativeDuration=460)) or not _close(command.get('portion'), .5, .000001):
                return ['Empty-fluid native anchor/dependent drink duration differs: ' + case]
        else:
            if (not _close(command.get('capturedAmount'), command['dispatchAmount'], .000001)
                    or not _close(command.get('transferRate'), bottles[target]['transferRate'], .000001)
                    or any(not _number(command.get(key)) or command[key] <= 0 for key in ('timePerLiter', 'minTime', 'nativeDuration'))):
                return ['Empty-fluid captured amount/native timing differs: ' + case]
            duration = command['capturedAmount'] * command['timePerLiter']
            if command['transferRate'] > 0:
                duration /= command['transferRate']
            if not _close(command['nativeDuration'], max(command['minTime'], duration), .000001):
                return ['Empty-fluid native empty duration changed: ' + case]
    return []


def _case(case, row, prep, receipt, kind='sp', mode='toolkit'):
    if case in EMPTY_CASES:
        return _empty_case(case, row, prep, receipt, kind, mode)
    issues = []
    bag, favorite = case.startswith('fluid-bag'), case.endswith('-favorite')
    editing = case == EDIT_CASE
    full = '-full-' in case
    food_level = 3 if full else 0
    source = 'bag' if bag else 'root'
    initial_thirst = .04 if '-smart-low-' in case else .2 if '-smart-' in case else .8
    bottles = prep.get('bottles')
    cancelling = '-cancel-' in case and mode == 'toolkit'
    count = 3 if '-cancel-' in case else 2
    if (set(prep) != RECEIPT_KEYS | {'case', 'foodTimer'}
            or not craft._matches(prep, dict(case=case, bagType=BAG_TYPE, foodTimer=4000 if full else 0, foodLevel=food_level))
            or not _close(prep.get('thirst'), initial_thirst, .00001)
            or type(bottles) is not list or len(bottles) != count
            or any(type(bottle) is not dict or set(bottle) != {'id', 'amount', 'favorite', 'source', 'thirstChange'} | ({'weight'} if editing else set())
                   or not craft._matches(bottle, dict(source='root' if editing and index == 0 else source, favorite=favorite))
                   or not _close(bottle.get('amount'), 1) or not _number(bottle.get('thirstChange'))
                   or bottle['thirstChange'] >= 0 or (editing and (not _number(bottle.get('weight')) or bottle['weight'] <= bottle['amount']))
                   for index, bottle in enumerate(bottles))
            or not craft._ids([prep.get('bagId')] + [bottle.get('id') for bottle in bottles], count + 1)):
        return ['Fluid preparation identity/state differs: ' + case]
    final = receipt.get('bottles')
    if (set(receipt) != RECEIPT_KEYS | {'case'} or not craft._matches(receipt, dict(case=case, bagId=prep['bagId'], bagType=BAG_TYPE, foodLevel=food_level))
            or not craft._matches(row, {key: receipt.get(key) for key in RECEIPT_KEYS})
            or type(final) is not list or len(final) != count
            or any(type(bottle) is not dict or set(bottle) != {'id', 'amount', 'favorite', 'source', 'count'} | ({'weight'} if editing else set())
                   or not craft._matches(bottle, dict(id=original['id'], favorite=favorite, count=1))
                   or not _number(bottle.get('amount')) or bottle['amount'] < 0
                   or (editing and not _close(bottle.get('weight'), original['weight'] - original['amount'] + bottle['amount']))
                   for bottle, original in zip(final, bottles))):
        return ['Fluid authority/client identity or conservation differs: ' + case]
    thirst = receipt.get('thirst')
    expected_thirst = max(0, prep['thirst'] + sum((original['amount'] - bottle['amount']) * original['thirstChange']
                                                for original, bottle in zip(bottles, final)))
    if not _number(thirst) or not 0 <= thirst < prep['thirst'] - .00001 or not _close(thirst, expected_thirst, .01):
        issues.append('Fluid thirst effect differs: ' + case)
    menu, portion, targets = _commands(case)
    commands, amounts, tolerances = row.get('commands'), {}, {}
    if (not craft._matches(row, dict(status='passed', reason=None, waitingCancelVerified=cancelling,
                                    independentMoveVerified=cancelling and not bag)) or type(commands) is not list
            or len(commands) != len(targets)):
        issues.append('Fluid native command count/status differs: ' + case)
    else:
        for position, (command, target) in enumerate(zip(commands, targets)):
            cancelled = cancelling and position == 1
            if (type(command) is not dict or set(command) != {'id', 'menu', 'portion', 'nativeDuration', 'pickupObserved', 'drinkProgress', 'menuDispatched', 'dispatchThirst', 'foodLevel', 'queueEmptyBefore', 'previousDrinkPending', 'backpackWorn', 'dispatchAmount', 'dispatchSource', 'cancelled'}
                    or not craft._matches(command, dict(id=bottles[target]['id'], menu=menu, nativeDuration=460,
                                                        pickupObserved=bag and not (editing and position == 0) and not cancelled, drinkProgress=not cancelled, menuDispatched=not (editing and position == 1), foodLevel=food_level,
                                                        dispatchSource='root' if editing and position == 0 else source, cancelled=cancelled,
                                                        queueEmptyBefore=position == 0 or '-serial-' in case,
                                                        previousDrinkPending=position > 0 and '-serial-' not in case, backpackWorn=True))
                    or not _number(command.get('dispatchThirst')) or not 0 <= command['dispatchThirst'] <= 1):
                issues.append('Fluid native target/menu/progress/duration differs: ' + case)
                continue
            expected_portion = portion
            if menu == 'smart':
                if not prep['thirst'] <= command['dispatchThirst'] <= prep['thirst'] + .01:
                    issues.append('Fluid smart dispatch thirst differs: ' + case)
                    continue
                expected_portion = min(1, command['dispatchThirst'] / abs(bottles[target]['thirstChange']))
            if not _close(command.get('portion'), expected_portion, .000001):
                issues.append('Fluid menu-defined portion differs: ' + case)
                continue
            initial = amounts.get(target, bottles[target]['amount']) if '-serial-' in case else bottles[target]['amount']
            tolerance = tolerances.get(target, .0001) if '-serial-' in case else .0001
            if not _number(command.get('dispatchAmount')) or not max(0, initial - tolerance) <= command['dispatchAmount'] <= initial + .0001:
                issues.append('Fluid dispatch volume differs: ' + case)
                continue
            if cancelled:
                continue
            # SP snapshots the ratio at enqueue; Host reconstructs the native action on the server.
            base = amounts.get(target, command['dispatchAmount']) if kind == 'mp' and '-queued-' in case else command['dispatchAmount']
            amounts[target] = base * (1 - command['portion'])
            tolerances[target] = tolerances.get(target, 0) * (1 - command['portion']) + .01
    for index, (original, bottle) in enumerate(zip(bottles, final)):
        if index not in targets or cancelling and index == 1:
            if not _close(bottle['amount'], original['amount']) or bottle.get('source') != source:
                issues.append('Fluid unselected bottle changed: ' + case)
            continue
        expected_endpoints = (('root',) if index == 0 or mode == 'toolkit' else ('bag',)) if editing else (('bag', 'root') if bag else ('root',))
        if bottle.get('source') not in expected_endpoints:
            issues.append('Fluid selected bottle endpoint differs: ' + case)
        if index not in amounts:
            continue
        expected_amount = max(0, amounts[index])
        # Native 100ms drinkFluid events can use progress >1 before complete; allow at most 10mL extra debit.
        if not max(0, expected_amount - tolerances[index]) <= bottle['amount'] <= expected_amount + .0001:
            issues.append('Fluid bounded water debit/endpoint differs: ' + case)
    if editing:
        evidence = row.get('editEvidence')
        enabled = mode == 'toolkit'
        expected_fields = {'anchorRunning', 'bottleId', 'fullWeight', 'standalone', 'manualPickupDispatched', 'pickupDuration', 'returnDuration',
                           'nativeDurationsUnchanged', 'contractsVerified', 'reordered', 'moveRejected', 'cancelRejected',
                           'untouchedBefore', 'returnNoopObserved', 'returnDontAdd', 'returnStarted', 'returnTransactionId',
                           'returnBoundaryObserved', 'returnCompleted', 'returnBefore', 'returnAfter', 'returnObservationFailed'}
        if (type(evidence) is not dict or set(evidence) != expected_fields
                or not craft._matches(evidence, dict(anchorRunning=True, bottleId=bottles[1]['id'], standalone=True, manualPickupDispatched=True,
                    nativeDurationsUnchanged=True, contractsVerified=enabled, reordered=enabled,
                    moveRejected=enabled, cancelRejected=enabled, untouchedBefore=True, returnNoopObserved=enabled, returnStarted=False, returnTransactionId=0,
                    returnBoundaryObserved=True, returnCompleted=True, returnObservationFailed=False,
                    returnBefore='bag' if enabled else 'root', returnAfter='bag'))
                or type(evidence.get('returnDontAdd')) is not bool
                or not _close(evidence.get('fullWeight'), bottles[1]['weight'])
                or any(not _number(evidence.get(field)) or
                       (evidence[field] != -1 if kind == 'mp' else evidence[field] <= 0)
                       for field in ('pickupDuration', 'returnDuration'))):
            issues.append('Fluid declarative pending transfer edit evidence differs: ' + case)
    return issues


def verify(root, selection, catalog):
    from ..report import events
    root = Path(root)
    client = (root / 'client1-launch.log').read_text(errors='replace')
    authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else client
    rows, raw, cases = events(client), _authority(authority), selection['cases']
    results, issues, identities = [row for row in rows if row['event'] == 'case'], [], []
    if not complete(selection, 'client1', client):
        issues.append('Missing or duplicate fluid completion marker')
    if [row['event'] for row in rows] != ['setup'] + ['case'] * len(cases) + ['complete']:
        issues.append('Missing, duplicate or reordered fluid events')
    if any(not craft._matches(row, dict(suite='fluid', kind=selection['kind'], mode=selection['mode'], actor='client1'))
           for row in rows):
        issues.append('Fluid event context differs')
    if [row.get('id') for row in results] != cases:
        issues.append('Fluid case selection/order differs')
    for event, expected in [('setup', dict(cases=cases, expected=len(cases), queueEnabled=selection['mode'] == 'toolkit', nativeDurations=True)),
                            ('complete', dict(cases=cases, expected=len(cases), performed=len(cases), failed=0, skipped=0))]:
        records = [row for row in rows if row['event'] == event]
        if len(records) != 1 or not craft._matches(records[0], expected):
            issues.append('Fluid ' + event + ' evidence differs')
    if [(marker, value.get('case')) for marker, value in raw] != [
            (marker, case) for case in cases for marker in ('PREPARED', 'VERIFIED')]:
        issues.append('Missing, duplicate or reordered fluid authority')
    outcomes = []
    for case in cases:
        row = next((row for row in results if row.get('id') == case), {})
        prep = next((value for marker, value in raw if marker == 'PREPARED' and value.get('case') == case), {})
        receipt = next((value for marker, value in raw if marker == 'VERIFIED' and value.get('case') == case), {})
        case_issues = _case(case, row, prep, receipt, selection['kind'], selection['mode'])
        issues.extend(case_issues)
        prepared_bottles = prep.get('bottles')
        identities += [prep.get('bagId')] + ([bottle.get('id') if type(bottle) is dict else None
                                             for bottle in prepared_bottles] if type(prepared_bottles) is list else [None, None])
        outcome = {key: row.get(key) for key in RECEIPT_KEYS | {'commands', 'editEvidence'} | ({'client'} if case in EMPTY_CASES else set())}
        outcome.update(emptyStartVerified=not case_issues, effectsVerified=not case_issues, wornBagVerified=not case_issues,
                       independentRequestsQueued=not case_issues and case == 'fluid-bag-pair-queued-favorite',
                       sameBottleRequestsVerified=not case_issues and '-same-' in case,
                       waitingCancelVerified=not case_issues and ('-cancel-' in case or case == EMPTY_CANCEL_CASE) and selection['mode']=='toolkit',
                       independentMoveVerified=not case_issues and case in ('fluid-root-cancel-waiting-favorite', EMPTY_MOVE_CASE) and selection['mode']=='toolkit',
                       serverAuthorityVerified=not case_issues and selection['kind'] == 'mp',
                       pendingTransferEditVerified=not case_issues and case==EDIT_CASE and selection['mode']=='toolkit',
                       pendingEmptyVerified=not case_issues and case in EMPTY_CASES,
                       dependentEmptyProtected=not case_issues and case==EMPTY_DEPENDENCY_CASE and selection['mode']=='toolkit',
                       dependentPickupProtected=not case_issues and case==EDIT_CASE and selection['mode']=='toolkit')
        outcomes.append(dict(actor='client1', case=case, outcome=outcome))
    if not craft._ids(identities):
        issues.append('Fluid fixture identities overlap between cases')
    if '[QUEUE_TEST] FAIL ' in client or '[QUEUE_TEST] FAIL ' in authority:
        issues.append('Native fluid fixture failed')
    for outcome in outcomes:
        outcome.update(status='failed' if issues else 'passed', reason='; '.join(issues))
    return {'issues': issues, 'outcomes': outcomes, 'evidence': {'limits': [
        'Fixture invokes real drink menu callbacks; physical mouse input is not covered.',
        'Requested portions allow at most 10mL native progress overshoot; raw remaining volumes are retained.',
        'The pending transfer case uses a native manual grab and standalone drink/return behind a running menu drink; Toolkit and disabled controls intentionally end in different containers.',
        'Raw pending empty cases use exact root clean-water bottles and native fluid wrappers/durations; no menu, physical input, active cancellation, world endpoint or capacity claims.',
        'Fresh one-client SP/Host with exact bottle receipts; no concurrent-client or WAN coverage.']}}
