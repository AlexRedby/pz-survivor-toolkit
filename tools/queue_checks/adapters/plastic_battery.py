"""Capture DAMN and native battery recipe effects through normal SP crafting."""
from pathlib import Path
import shutil

from .. import receipts

SUITE = 'plastic-battery'
MARKER = '[PLASTIC_BATTERY] '


def definitions():
    return {SUITE: {'status': 'ready', 'clients': 1,
                   'default_mods': ['damnlib', 'PZSurvivorToolkit'],
                   'cases': [{'id': 'charge-matrix', 'producer': 'fixture', 'capability': 'capture',
                              'kinds': ['sp'], 'languages': ['EN'], 'modes': ['native', 'toolkit']}]}}


def validate(selection):
    if (selection.get('cases') != ['charge-matrix'] or selection.get('kind') != 'sp'
            or selection.get('mode') not in ('native', 'toolkit')
            or selection.get('clients', 1) != 1 or selection.get('languages') != ['EN']
            or 'damnlib' not in selection.get('mods', [])
            or selection.get('options', {}).get('world_template')):
        raise ValueError('Plastic battery capture requires fresh one-client EN SP with damnlib')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / SUITE).rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for source, side in [(root / 'startup/client/ZZStartup.lua', 'client'),
                             (root / 'health/shared/QueueHealthEvents.lua', 'shared')]:
            (lua / side).mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, lua / side / source.name)
    runtime['fixture'] = {'failure_markers': [MARKER + 'FAIL '], 'sandbox': {'Zombies': 6}}


def complete(selection, role, text):
    return role == 'client1' and receipts.records(text, MARKER, 'COMPLETE') == [{'phases': 12, 'restored': True}]


def verify(root, selection, catalog):
    issues, rows = [], []
    try:
        text = (Path(root) / 'client1-launch.log').read_text(errors='replace')
        rows = receipts.records(text, MARKER, 'PHASE')
        expected = [(provider, operation, charge) for provider in ('base', 'damn')
                    for operation in ('insert', 'remove') for charge in (0, 0.37, 1)]
        if len(rows) != len(expected) or not complete(selection, 'client1', text):
            raise ValueError('Incomplete battery capture')
        for index, (row, values) in enumerate(zip(rows, expected), 1):
            if (row.get('index') != index
                    or tuple(row.get(key) for key in ('provider', 'operation', 'requestedCharge')) != values
                    or type(row.get('available')) is not bool
                    or row.get('queueDrained') is not True
                    or not isinstance(row.get('before'), list) or not isinstance(row.get('after'), list)):
                raise ValueError('Invalid battery phase provenance')
            if row['available'] and (row.get('actionObserved') is not True
                                     or row.get('nativeDuration') is not True
                                     or row.get('performCalls') != 1):
                raise ValueError('Available battery recipe did not reach native crafting exactly once')
            if row['available']:
                expected_ids = {row['gunID']}
                if row['operation'] == 'insert':
                    expected_ids.add(row['batteryID'])
                if set(row.get('inputIDs', [])) != expected_ids:
                    raise ValueError('Native recipe used different fixture inputs')
            if row['provider'] == 'base' and row['requestedCharge'] > 0 and not row['available']:
                raise ValueError('Required standard battery positive control unavailable')
        if MARKER + 'FAIL ' in text:
            raise ValueError('Battery fixture failed')
    except (OSError, ValueError, TypeError, KeyError) as error:
        issues.append(str(error))
    return {'issues': issues,
            'outcomes': [{'actor': 'client1', 'case': 'charge-matrix',
                          'status': 'failed' if issues else 'captured', 'reason': '; '.join(issues)}],
            'evidence': {'battery': rows, 'limits': [
                'SP recipe availability and native context callback; no physical input or Host transport.',
                'Capture records actual charges and identities; captured does not assert conservation.']}}
