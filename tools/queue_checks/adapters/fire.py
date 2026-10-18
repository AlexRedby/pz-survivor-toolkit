"""Native campfire fuel and disappearance after real borrowed-pickup expansion."""
import json
import math
from pathlib import Path
import re
import shutil

CASES = ['fuel', 'missing-target-after-expansion']
MODS = ['PZSurvivorToolkit', 'ZombieBuddy', 'PZToolkitJavaPatches']


def definitions():
    return {'fire': {'status': 'ready', 'clients': 1, 'default_mods': MODS,
                     'cases': [{'id': case, 'producer': 'fixture', 'capability': 'effect',
                                'kinds': ['sp', 'mp'], 'languages': ['EN'], 'modes': ['native', 'toolkit']}
                               for case in CASES]}}


def validate(selection):
    cases = selection.get('cases')
    if (not isinstance(cases, list) or not cases or cases != [case for case in CASES if case in cases]
            or selection.get('kind') not in ('sp', 'mp') or selection.get('mode') not in ('native', 'toolkit')
            or selection.get('languages') != ['EN'] or type(selection.get('clients', 1)) is not int
            or selection.get('clients', 1) != 1 or not set(MODS) <= set(selection.get('mods', []))
            or selection.get('options', {}).get('world_template')):
        raise ValueError('Fire requires ordered fuel/missing-target-after-expansion, fresh SP/MP, one EN client and Java patches')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / 'fire').rglob('*.lua')), root / 'health/shared/QueueHealthEvents.lua',
            *sorted((root / 'startup').rglob('*.lua'))]


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua'),
                           ('shared', 'QueueHealthEvents.lua')]:
            target = lua / side
            target.mkdir(parents=True, exist_ok=True)
            shutil.copy2(root / ('health' if side == 'shared' else 'startup') / side / name, target)
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
                                            sandbox={'Zombies': 6, 'MinutesPerPage': 2.0})


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(r'\[FIRE_TEST\] COMPLETE(?:\s|$)', text)) == 1


def _records(text, marker):
    result = []
    for line in text.splitlines():
        if marker in line:
            value = json.loads(line.split(marker, 1)[1])
            if not isinstance(value, dict):
                raise ValueError('Invalid Fire authority envelope')
            result.append(value)
    return result


def _number(value):
    return type(value) in (int, float) and math.isfinite(value)


def verify(root, selection, catalog):
    from ..report import events
    root = Path(root)
    client = (root / 'client1-launch.log').read_text(errors='replace')
    authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else client
    rows = events(client)
    prepared = _records(authority, '[FIRE_TEST] PREPARED ')
    receipts = _records(authority, '[FIRE_TEST] AUTHORITY ')
    removals = _records(authority, '[FIRE_TEST] REMOVED ')
    cases = selection['cases']
    enabled = selection['mode'] == 'toolkit'
    issues, outcomes, case_failures = [], [], {}
    if [row['event'] for row in rows] != ['setup'] + ['case'] * len(cases) + ['complete']:
        issues.append('Missing, duplicate or reordered Fire events')
    for row in rows:
        if any(row.get(key) != value for key, value in dict(suite='fire', kind=selection['kind'],
                                                          mode=selection['mode'], actor='client1').items()):
            issues.append('Fire event context differs')
    results = [row for row in rows if row['event'] == 'case']
    for event, expected in [('setup', dict(cases=cases, expected=len(cases), queueEnabled=enabled, nativeDurations=True)),
                            ('complete', dict(cases=cases, expected=len(cases), performed=len(cases),
                                              failed=sum(row.get('status') == 'failed' for row in results), skipped=0))]:
        matches = [row for row in rows if row['event'] == event]
        if len(matches) != 1 or any(type(matches[0].get(key)) is not type(value) or matches[0].get(key) != value
                                    for key, value in expected.items()):
            issues.append('Fire ' + event + ' evidence differs')
    if [row.get('id') for row in results] != cases or [row.get('case') for row in prepared] != cases or [row.get('case') for row in receipts] != cases:
        issues.append('Fire case/authoritative receipt selection or order differs')
    expected_removed = [case for case in cases if case == 'missing-target-after-expansion']
    if [row.get('case') for row in removals] != expected_removed:
        issues.append('Missing or duplicate authoritative Fire removal')
    for case in cases:
        missing = case == 'missing-target-after-expansion'
        result = next((row for row in results if row.get('id') == case), {})
        prep = next((row for row in prepared if row.get('case') == case), {})
        receipt = next((row for row in receipts if row.get('case') == case), {})
        observed_native_mp_fuel = not missing and not enabled and selection['kind'] == 'mp'
        expected = dict(status='failed' if missing and not enabled else 'passed',
                        reason='native-missing-target' if missing and not enabled else None, consumed=0 if missing else 1,
                        sourceCount=1 if missing and enabled else 0, rootCount=1 if missing and not enabled else 0,
                        removed=missing, unspent=missing, tailRead=not missing or enabled, expanded=True,
                        pickupProgress=True, fuelProgress=not missing, tailProgress=not missing or enabled,
                        returnProgress=missing and enabled, removedDuringPickup=missing,
                        nativeDuration=100, authorityVerified=True)
        if observed_native_mp_fuel:
            for key in ('tailRead', 'fuelProgress', 'tailProgress'):
                if type(result.get(key)) is not bool:
                    issues.append('Fire observed native MP progress must be boolean: ' + key)
            expected.update(tailRead=receipt.get('tailRead'), fuelProgress=result.get('fuelProgress'),
                            tailProgress=result.get('tailProgress'),
                            status='failed' if receipt.get('tailRead') is False else 'passed',
                            reason='native-independent-tail-not-preserved' if receipt.get('tailRead') is False else None)
            if receipt.get('tailRead') is False:
                case_failures[case] = 'native-independent-tail-not-preserved'
        if missing and not enabled:
            case_failures[case] = 'native-missing-target'
        if any(type(result.get(key)) is not type(value) or result.get(key) != value for key, value in expected.items()):
            issues.append('Fire exact native effect/progress differs: ' + case)
        for key in ('logId', 'bookId', 'condition'):
            prep_key = {'logId': 'log', 'bookId': 'book'}.get(key, key)
            if type(result.get(key)) is not int or type(prep.get(prep_key)) is not int or result.get(key) != prep.get(prep_key):
                issues.append('Fire exact authoritative item identity/condition differs: ' + case)
        if result.get('logId') == result.get('bookId'):
            issues.append('Fire fuel and reader IDs overlap')
        for key in ('x', 'y', 'z', 'objectIndex', 'crateX', 'crateY', 'crateZ', 'crateIndex'):
            if type(prep.get(key)) is not int or key.endswith('Index') and prep[key] < 0:
                issues.append('Fire authoritative target/source identity missing: ' + case)
        if (any(prep.get('crate' + key.upper()) != prep.get(key) for key in ('x', 'y', 'z'))
                or type(prep.get('crateIndex')) is int and type(prep.get('objectIndex')) is int
                and prep['crateIndex'] >= prep['objectIndex']):
            issues.append('Fire source must precede the campfire on the same square: ' + case)
        amount = prep.get('fuelAmount')
        if (not _number(amount) or amount <= 0 or not _number(result.get('fuelAmount'))
                or result.get('fuelAmount') != amount or not _number(result.get('fuel'))
                or result.get('fuel') != (0 if missing else amount)
                or not _number(result.get('pickupDuration')) or result.get('pickupDuration') <= 1):
            issues.append('Fire native fuel amount/duration differs: ' + case)
        for key in ('logId', 'bookId', 'condition', 'fuelAmount', 'consumed', 'sourceCount', 'rootCount', 'fuel', 'removed', 'unspent', 'tailRead'):
            if type(receipt.get(key)) is not type(result.get(key)) or receipt.get(key) != result.get(key):
                issues.append('Fire authority differs from client evidence: ' + case)
                break
        if missing and (len(removals) != 1 or type(removals[0].get('logId')) is not int
                        or removals[0].get('logId') != result.get('logId') or type(removals[0].get('fuel')) is not int
                        or removals[0].get('fuel') != 0):
            issues.append('Fire removal identity/effect differs')
        outcomes.append({'actor': 'client1', 'case': case, 'outcome': {key: result.get(key) for key in
                         ('logId', 'consumed', 'sourceCount', 'rootCount', 'fuel', 'tailRead', 'returnProgress')}})
    if '[QUEUE_TEST] FAIL ' in client or '[QUEUE_TEST] FAIL ' in authority:
        issues.append('Native Fire fixture failed')
    for outcome in outcomes:
        case_issues = issues + ([case_failures[outcome['case']]] if outcome['case'] in case_failures else [])
        outcome.update(status='failed' if case_issues else 'passed', reason='; '.join(case_issues))
    issues.extend(case_failures.values())
    return {'issues': issues, 'outcomes': outcomes, 'evidence': {'limits': [
        'Fresh world, one actor, actual campfire/menu/world-crate/transfer/read actions and native durations.',
        'Missing-target native control intentionally remains red; common runtime log auditing is unchanged.',
        'SP/MP and Host results require real calibration; no physical menu input, WAN or peer contention coverage.']}}
