"""Native inventory Grab / Grab One from a real adjacent microwave."""
import json
from pathlib import Path
import re
from . import craft

CASES = ['root-grab', 'root-one', 'bag-grab', 'bag-one']
MODS = craft.MODS + ['P4TidyUpMeister']


def definitions():
    return {'inventory-grab': {'status': 'ready', 'clients': 1, 'default_mods': MODS,
        'cases': [dict(id=case, producer='fixture', capability='effect', kinds=['sp', 'mp'],
                       languages=['EN'], modes=['native', 'toolkit']) for case in CASES]}}


def validate(selection):
    cases = selection.get('cases')
    if (type(cases) is not list or not cases or cases != [case for case in CASES if case in cases]
            or selection.get('kind') not in ('sp', 'mp') or selection.get('mode') not in ('native', 'toolkit')
            or selection.get('languages') != ['EN'] or type(selection.get('clients', 1)) is not int
            or selection.get('clients', 1) != 1 or not set(MODS) <= set(selection.get('mods', []))
            or selection.get('options', {}).get('world_template')):
        raise ValueError('Inventory Grab requires ordered cases, fresh one-client SP/Host, EN, Toolkit, Java patches and P4')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / 'inventory-grab').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua', *sorted((root / 'startup').rglob('*.lua')),
            *sorted((root / 'craft/scripts').rglob('*.txt'))]


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    craft.stage_common(project, output, game, jdk, selection, locations, runtime)


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(r'\[INVENTORY_GRAB_TEST\] COMPLETE(?:\s|$)', text)) == 1


def _authority(text):
    return [(match[1], json.loads(match[2])) for match in re.finditer(
        r'\[INVENTORY_GRAB_TEST\] (PREPARED|VERIFIED)\s+([^\n]*)', text)]


def _case(case, row, prep, receipt, kind='sp'):
    issues = []
    bag, one = case.startswith('bag-'), case.endswith('-one')
    original = prep.get('bottles', [])
    final = receipt.get('bottles', [])
    identities = [item.get('id') for item in original if type(item) is dict]
    if (not craft._matches(prep, dict(case=case, bagType='Base.Bag_ALICEpack_Army',
                                     sprite='appliances_cooking_01_28', sourceType='microwave', nativeMicrowave=True))
            or not craft._ids([prep.get('bagId')] + identities, 3)
            or len(original) != 2 or any(not craft._matches(item, dict(kind='Base.WaterBottle', amount=1)) for item in original)):
        return ['Inventory Grab preparation differs: ' + case]
    target = receipt.get('targetId')
    if target not in identities or not craft._matches(receipt, dict(case=case, bagId=prep['bagId'],
            bagType=prep['bagType'], sourceType='microwave', nativeMicrowave=True)):
        issues.append('Inventory Grab authoritative identity differs: ' + case)
    if (len(final) != 2 or any(not craft._matches(item, dict(id=identity, kind='Base.WaterBottle', amount=1,
            count=1, endpoint=('bag' if bag else 'root') if identity == target else 'microwave'))
            for item, identity in zip(final, identities))):
        issues.append('Inventory Grab exact endpoint/volume differs: ' + case)
    if not craft._matches(row, dict(status='passed', reason=None, queueIdle=True, clientIdentityVerified=True,
                                    **{key: value for key, value in receipt.items()})):
        issues.append('Inventory Grab client/authority result differs: ' + case)
    command = row.get('command', {})
    if (type(command) is not dict or not craft._matches(command, dict(targetId=target, selectedRows=1,
            rowKind='collapsed-group' if one else 'expanded-child', destination='bag' if bag else 'root',
            menuDispatched=True, transferCount=1, transferProgress=True, backpackWorn=True, queueEmptyBefore=True,
            adjacent=True, capacityAvailable=True, nativeDurations=True, menuBuilds=2, targetType='table', callbackType='function'))
            or type(command.get('nativeDuration')) not in (int, float)
            or (command['nativeDuration'] != -1 if kind == 'mp' else command['nativeDuration'] <= 0)
            or type(command.get('progressDuration')) not in (int, float) or command['progressDuration'] <= 0
            or type(row.get('settleMilliseconds')) not in (int, float) or row['settleMilliseconds'] < 6000):
        issues.append('Inventory Grab native dispatch/transfer/settle evidence differs: ' + case)
    return issues


def verify(root, selection, catalog):
    from ..report import events
    root = Path(root)
    client = (root / 'client1-launch.log').read_text(errors='replace')
    authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else client
    rows, raw, cases = events(client), _authority(authority), selection['cases']
    results = [row for row in rows if row['event'] == 'case']
    issues = []
    if not complete(selection, 'client1', client):
        issues.append('Missing or duplicate inventory Grab completion')
    if ([row['event'] for row in rows] != ['setup'] + ['case'] * len(cases) + ['complete']
            or [row.get('id') for row in results] != cases
            or any(not craft._matches(row, dict(suite='inventory-grab', actor='client1', kind=selection['kind'], mode=selection['mode'])) for row in rows)):
        issues.append('Inventory Grab event order/context differs')
    for event, expected in [('setup', dict(cases=cases, expected=len(cases), queueEnabled=selection['mode']=='toolkit', nativeDurations=True)),
                            ('complete', dict(cases=cases, expected=len(cases), performed=len(cases), failed=0, skipped=0))]:
        records = [row for row in rows if row['event'] == event]
        if len(records) != 1 or not craft._matches(records[0], expected):
            issues.append('Inventory Grab ' + event + ' differs')
    if [(marker, value.get('case')) for marker, value in raw] != [(marker, case) for case in cases for marker in ('PREPARED', 'VERIFIED')]:
        issues.append('Inventory Grab authority order differs')
    outcomes, identities = [], []
    for case in cases:
        row = next((item for item in results if item.get('id') == case), {})
        prep = next((item for marker, item in raw if marker == 'PREPARED' and item.get('case') == case), {})
        receipt = next((item for marker, item in raw if marker == 'VERIFIED' and item.get('case') == case), {})
        problems = _case(case, row, prep, receipt, selection['kind'])
        issues.extend(problems)
        identities += [prep.get('bagId')] + [item.get('id') for item in prep.get('bottles', [])]
        outcomes.append(dict(actor='client1', case=case, outcome=dict(row, effectsVerified=not problems,
                             serverAuthorityVerified=not problems and selection['kind']=='mp')))
    if not craft._ids(identities):
        issues.append('Inventory Grab fixture identities overlap')
    if '[QUEUE_TEST] FAIL ' in client or '[QUEUE_TEST] FAIL ' in authority:
        issues.append('Native inventory Grab fixture failed')
    for outcome in outcomes:
        outcome.update(status='failed' if issues else 'passed', reason='; '.join(issues))
    return dict(issues=issues, outcomes=outcomes, evidence={'limits': [
        'Actual inventory menu onMouseUp dispatch with native timing; physical mouse input is not covered.',
        'One-client SP/Host, two pure-water bottles, one native microwave and worn military backpack.',
        'Exact authoritative endpoints remain observed for six seconds after queue idle; no concurrent-client coverage.']})
