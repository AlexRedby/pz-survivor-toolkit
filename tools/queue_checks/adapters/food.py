"""Pending ordinary native cereal edits, exact item authority and queue-off controls."""
import json
from pathlib import Path
import re
import shutil

from . import craft, fluid

MOVE_CASE = 'food-root-move-same-portions'
CANCEL_CASE = 'food-root-cancel-first-portion'
BAG_CASE = 'food-bag-edit-pickup-return'
DEPLETION_CASE = 'food-root-depletion'
CASES = [MOVE_CASE, CANCEL_CASE, BAG_CASE, DEPLETION_CASE]
# The full selected installation. Locked EatSmart debug logging leaves native completion unchanged.
MODS = next(line.split('=', 1)[1].split(';') for line in
            (Path(__file__).resolve().parents[3] / 'SurvivorQoL-selected.ini').read_text().splitlines()
            if line.startswith('Mods='))
RECEIPT_KEYS = {'case', 'bagId', 'bagType', 'bagCount', 'foodId', 'foodType', 'baseHunger', 'remaining',
                'source', 'foodCount', 'foodTypeCount', 'deleted', 'anchorId', 'anchorType', 'anchorAmount', 'anchorCount',
                'anchorThirstChange', 'hunger', 'thirst'}
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
    cancelled = case == CANCEL_CASE and enabled
    if (set(prep) != RECEIPT_KEYS | {'foodTimer', 'foodLevel'}
            or not craft._matches(prep, dict(case=case, bagType=fluid.BAG_TYPE, bagCount=1, foodType='Base.Cereal',
                source='bag' if bag else 'root', foodCount=1, deleted=False, anchorType='Base.WaterBottle', anchorCount=1,
                foodTimer=0, foodLevel=0))
            or not craft._ids([prep.get(key) for key in ('bagId', 'foodId', 'anchorId')], 3)
            or any(not fluid._close(prep.get(key), value) for key, value in
                   dict(baseHunger=-.4, remaining=-.4, anchorAmount=1, hunger=.8, thirst=.8).items())
            or type(prep.get('foodTypeCount')) is not int or prep['foodTypeCount'] < 1
            or not fluid._number(prep.get('anchorThirstChange')) or prep['anchorThirstChange'] >= 0):
        return ['Food preparation identity/state differs: ' + case]
    fixed = {key: prep[key] for key in RECEIPT_KEYS - {'remaining', 'source', 'hunger', 'thirst', 'anchorAmount', 'foodCount', 'foodTypeCount', 'deleted', 'anchorThirstChange'}}
    fixed.update(source='deleted' if depletion else 'root' if not bag or enabled else 'bag',
                 foodCount=0 if depletion else 1, foodTypeCount=prep['foodTypeCount'] - int(depletion), deleted=depletion)
    portion = 1 if depletion else .5 if bag else .25 if cancelled else .75
    expected_remaining = prep['baseHunger'] * (1 - portion)
    if (set(receipt) != RECEIPT_KEYS or not craft._matches(receipt, fixed)
            or not craft._matches(row, receipt) or type(row.get('client')) is not dict
            or set(row['client']) != RECEIPT_KEYS
            or not craft._matches(row['client'], {key: receipt[key] for key in RECEIPT_KEYS - {'hunger', 'thirst'}})
            or any(not fluid._close(row['client'].get(field), receipt.get(field), .01) for field in ('hunger', 'thirst'))
            or not fluid._close(receipt.get('remaining'), expected_remaining)
            or not fluid._number(receipt.get('anchorAmount')) or not .49 <= receipt['anchorAmount'] <= .5001
            or not fluid._close(receipt.get('anchorThirstChange'),
                                prep['anchorThirstChange'] * receipt['anchorAmount'] / prep['anchorAmount'])):
        return ['Food authority/client identity or consumption differs: ' + case]
    expected_hunger = prep['hunger'] + prep['baseHunger'] * portion
    expected_thirst = prep['thirst'] + (prep['anchorAmount'] - receipt['anchorAmount']) * prep['anchorThirstChange'] / prep['anchorAmount']
    if not fluid._close(receipt.get('hunger'), expected_hunger, .01) or not fluid._close(receipt.get('thirst'), expected_thirst, .01):
        issues.append('Food hunger or clean-water anchor effect differs: ' + case)
    if not craft._matches(row, dict(status='passed', reason=None)):
        issues.append('Food native status differs: ' + case)
    commands = row.get('commands')
    portions = [.25, 1] if depletion else [.5] if bag else [.5, .25]
    if type(commands) is not list or len(commands) != len(portions):
        issues.append('Food native command count differs: ' + case)
    else:
        for index, (command, fraction) in enumerate(zip(commands, portions)):
            cancel = cancelled and index == 0
            expected = dict(id=prep['foodId'], portion=fraction, baseHunger=prep['baseHunger'], dispatchRemaining=prep['remaining'],
                dispatchSource='bag' if bag else 'root', menuDispatched=not bag, nativeDuration=464 if fraction == 1 else 232,
                progress=not cancel, cancelled=cancel, pickupObserved=bag)
            if type(command) is not dict or set(command) != COMMAND_KEYS or not craft._matches(command, expected):
                issues.append('Food native target/original portion/progress/duration differs: ' + case)
    evidence = row.get('editEvidence')
    expected = dict(emptyStart=True, anchorRunning=True, anchorProgress=True, anchorDuration=460,
        contractsVerified=enabled, reordered=enabled and case in (MOVE_CASE, BAG_CASE), waitingCancel=cancelled,
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
        identities += [prep.get(field) for field in ('bagId', 'foodId', 'anchorId')]
        outcome = {key: row.get(key) for key in RECEIPT_KEYS | {'commands', 'editEvidence', 'client'}}
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
        'Ordinary Base.Cereal pending edits only; full selected mod set, real native actions and durations.',
        'Callback-driven menu dispatch does not establish physical input or visual correctness.',
        'No OnEat, replacement food, smoking, utensils, active eating cancellation or WAN coverage.']}}
