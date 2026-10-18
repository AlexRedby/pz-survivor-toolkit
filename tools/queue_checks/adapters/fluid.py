"""Native drinking callbacks, bounded bottle effects and independent queued reading."""
import json
import math
from pathlib import Path
import re

from . import craft

CASES = ['fluid-bag', 'fluid-root', 'fluid-bag-favorite', 'fluid-root-favorite']
MODS = craft.MODS + ['Drink_Smart']
IDENTITIES = {'bottleId', 'bagId', 'bookId'}
PREPARED_KEYS = IDENTITIES | {'case', 'amount', 'thirst', 'source', 'favorite'}
RECEIPT_KEYS = IDENTITIES | {'amount', 'thirst', 'source', 'favorite', 'bottleCount', 'tailRead'}


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


def _case(case, row, prep, receipt):
    issues = []
    bag, favorite = case.startswith('fluid-bag'), case.endswith('-favorite')
    if (set(prep) != PREPARED_KEYS or not craft._matches(prep, dict(case=case, source='bag' if bag else 'root', favorite=favorite))
            or not craft._ids([prep.get(key) for key in sorted(IDENTITIES)], 3)
            or not _number(prep.get('amount')) or prep['amount'] <= .24
            or not _number(prep.get('thirst')) or not 0 < prep['thirst'] <= 1):
        return ['Fluid preparation identity/state differs: ' + case]
    if (set(receipt) != RECEIPT_KEYS | {'case'} or not craft._matches(receipt, dict(case=case, bottleCount=1, tailRead=True, favorite=favorite))
            or not craft._matches(receipt, {key: prep[key] for key in IDENTITIES})
            or not craft._matches(row, {key: receipt.get(key) for key in RECEIPT_KEYS})
            or receipt.get('source') not in (('bag', 'root') if bag else ('root',))):
        issues.append('Fluid authority/client identity, conservation or reader effect differs: ' + case)
    amount, thirst = receipt.get('amount'), receipt.get('thirst')
    expected_amount = prep['amount'] * .5
    # Native 100ms drinkFluid events can use progress >1 before complete; allow at most 10mL extra debit.
    if (not _number(amount) or not expected_amount - .01 <= amount <= expected_amount + .0001
            or not _number(thirst) or not 0 <= thirst < prep['thirst'] - .00001):
        issues.append('Fluid bounded water debit/thirst effect differs: ' + case)
    if not craft._matches(row, dict(status='passed', reason=None, pickupObserved=bag, drinkProgress=True,
                                    menuDispatched=True, portion=.5,
                                    actionType='ISDrinkFluidAction', nativeDuration=460)):
        issues.append('Fluid native callback/progress/duration differs: ' + case)
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
        identities += [prep.get(key) for key in sorted(IDENTITIES)]
        outcomes.append(dict(actor='client1', case=case, outcome={key: row.get(key) for key in RECEIPT_KEYS | {
            'pickupObserved', 'drinkProgress', 'actionType', 'nativeDuration', 'menuDispatched', 'portion'}}))
    if not craft._ids(identities):
        issues.append('Fluid fixture identities overlap between cases')
    if '[QUEUE_TEST] FAIL ' in client or '[QUEUE_TEST] FAIL ' in authority:
        issues.append('Native fluid fixture failed')
    for outcome in outcomes:
        outcome.update(status='failed' if issues else 'passed', reason='; '.join(issues))
    return {'issues': issues, 'outcomes': outcomes, 'evidence': {'limits': [
        'Fixture invokes real drink menu callbacks; physical mouse input is not covered.',
        'Half portions allow at most 10mL native progress overshoot; raw remaining volume is retained.',
        'Fresh one-client SP/Host with exact bottle receipts; no concurrent-client or WAN coverage.']}}
