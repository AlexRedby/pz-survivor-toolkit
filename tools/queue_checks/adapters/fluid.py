"""Native drink menus with exact bottle identities and bounded fluid effects."""
import json
import math
from pathlib import Path
import re

from . import craft

CASES = ['fluid-bag', 'fluid-root', 'fluid-bag-favorite', 'fluid-root-favorite',
         'fluid-bag-all-favorite', 'fluid-bag-quarter-favorite', 'fluid-bag-smart-favorite',
         'fluid-bag-sip-favorite', 'fluid-bag-second-favorite', 'fluid-bag-pair-queued-favorite',
         'fluid-bag-pair-serial-favorite', 'fluid-bag-smart-low-favorite',
         'fluid-bag-full-favorite', 'fluid-root-full-favorite']
MODS = craft.MODS + ['Drink_Smart']
RECEIPT_KEYS = {'bagId', 'bagType', 'thirst', 'bottles', 'foodLevel'}
BAG_TYPE = 'Base.Bag_ALICEpack_Army'


def definitions():
    return {'fluid': {'status': 'ready', 'clients': 1, 'default_mods': MODS,
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
            root / 'health/shared/QueueHealthEvents.lua',
            *sorted((root / 'startup').rglob('*.lua'))]


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    craft.stage_common(project, output, game, jdk, selection, locations, runtime)


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
    portion = {'half': .5, 'all': 1, 'quarter': .25, 'sip': .01}.get(menu)
    targets = [0, 1] if '-pair-' in case else [1] if '-second-' in case else [0]
    return menu, portion, targets


def _case(case, row, prep, receipt):
    issues = []
    bag, favorite = case.startswith('fluid-bag'), case.endswith('-favorite')
    full = '-full-' in case
    food_level = 3 if full else 0
    source = 'bag' if bag else 'root'
    initial_thirst = .04 if '-smart-low-' in case else .2 if '-smart-' in case else .8
    bottles = prep.get('bottles')
    if (set(prep) != RECEIPT_KEYS | {'case', 'foodTimer'}
            or not craft._matches(prep, dict(case=case, bagType=BAG_TYPE, foodTimer=4000 if full else 0, foodLevel=food_level))
            or not _close(prep.get('thirst'), initial_thirst, .00001)
            or type(bottles) is not list or len(bottles) != 2
            or any(type(bottle) is not dict or set(bottle) != {'id', 'amount', 'favorite', 'source', 'thirstChange'}
                   or not craft._matches(bottle, dict(source=source, favorite=favorite))
                   or not _close(bottle.get('amount'), 1) or not _number(bottle.get('thirstChange'))
                   or bottle['thirstChange'] >= 0 for bottle in bottles)
            or not craft._ids([prep.get('bagId')] + [bottle.get('id') for bottle in bottles], 3)):
        return ['Fluid preparation identity/state differs: ' + case]
    final = receipt.get('bottles')
    if (set(receipt) != RECEIPT_KEYS | {'case'} or not craft._matches(receipt, dict(case=case, bagId=prep['bagId'], bagType=BAG_TYPE, foodLevel=food_level))
            or not craft._matches(row, {key: receipt.get(key) for key in RECEIPT_KEYS})
            or type(final) is not list or len(final) != 2
            or any(type(bottle) is not dict or set(bottle) != {'id', 'amount', 'favorite', 'source', 'count'}
                   or not craft._matches(bottle, dict(id=original['id'], favorite=favorite, count=1))
                   or not _number(bottle.get('amount')) or bottle['amount'] < 0
                   for bottle, original in zip(final, bottles))):
        return ['Fluid authority/client identity or conservation differs: ' + case]
    thirst = receipt.get('thirst')
    if not _number(thirst) or not 0 <= thirst < prep['thirst'] - .00001:
        issues.append('Fluid thirst effect differs: ' + case)
    menu, portion, targets = _commands(case)
    commands, portions = row.get('commands'), {}
    if (not craft._matches(row, dict(status='passed', reason=None)) or type(commands) is not list
            or len(commands) != len(targets)):
        issues.append('Fluid native command count/status differs: ' + case)
    else:
        for command, target in zip(commands, targets):
            if (type(command) is not dict or set(command) != {'id', 'menu', 'portion', 'nativeDuration', 'pickupObserved', 'drinkProgress', 'menuDispatched', 'dispatchThirst', 'foodLevel'}
                    or not craft._matches(command, dict(id=bottles[target]['id'], menu=menu, nativeDuration=460,
                                                        pickupObserved=bag, drinkProgress=True, menuDispatched=True, foodLevel=food_level))
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
            portions[target] = command['portion']
    for index, (original, bottle) in enumerate(zip(bottles, final)):
        if index not in targets:
            if not _close(bottle['amount'], original['amount']) or bottle.get('source') != source:
                issues.append('Fluid unselected bottle changed: ' + case)
            continue
        if bottle.get('source') not in (('bag', 'root') if bag else ('root',)):
            issues.append('Fluid selected bottle endpoint differs: ' + case)
        if index not in portions:
            continue
        expected_amount = max(0, original['amount'] * (1 - portions[index]))
        # Native 100ms drinkFluid events can use progress >1 before complete; allow at most 10mL extra debit.
        if not max(0, expected_amount - .01) <= bottle['amount'] <= expected_amount + .0001:
            issues.append('Fluid bounded water debit/endpoint differs: ' + case)
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
        issues.extend(_case(case, row, prep, receipt))
        prepared_bottles = prep.get('bottles')
        identities += [prep.get('bagId')] + ([bottle.get('id') if type(bottle) is dict else None
                                             for bottle in prepared_bottles] if type(prepared_bottles) is list else [None, None])
        outcomes.append(dict(actor='client1', case=case, outcome={key: row.get(key) for key in RECEIPT_KEYS | {'commands'}}))
    if not craft._ids(identities):
        issues.append('Fluid fixture identities overlap between cases')
    if '[QUEUE_TEST] FAIL ' in client or '[QUEUE_TEST] FAIL ' in authority:
        issues.append('Native fluid fixture failed')
    for outcome in outcomes:
        outcome.update(status='failed' if issues else 'passed', reason='; '.join(issues))
    return {'issues': issues, 'outcomes': outcomes, 'evidence': {'limits': [
        'Fixture invokes real drink menu callbacks; physical mouse input is not covered.',
        'Requested portions allow at most 10mL native progress overshoot; raw remaining volumes are retained.',
        'Fresh one-client SP/Host with exact bottle receipts; no concurrent-client or WAN coverage.']}}
