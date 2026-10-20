"""Bulk dresser reading through native commands, with queue UI cost observations."""
import json
from pathlib import Path
import re
import shutil

MARKER = '[BULK_READING] '


def definitions():
    return {'bulk-reading': {'status': 'ready', 'clients': 1,
            'default_mods': ['PZSurvivorToolkit', 'ZombieBuddy', 'PZToolkitJavaPatches'],
            'cases': [{'id': 'dresser-15', 'producer': 'fixture', 'capability': 'effect',
                       'kinds': ['sp', 'mp'], 'languages': ['EN'], 'modes': ['toolkit', 'native']}]}}


def validate(selection):
    if (selection.get('cases') != ['dresser-15'] or selection.get('clients', 1) != 1
            or selection.get('kind') not in ('sp', 'mp') or selection.get('mode') not in ('toolkit', 'native')
            or selection.get('languages') != ['EN'] or selection.get('options', {}).get('world_template')
            or (selection['kind'] == 'mp' and not selection.get('options', {}).get('mp_host'))):
        raise ValueError('Bulk reading requires one EN client in fresh SP/menu Host')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / 'bulk-reading').rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua'),
                           ('shared', 'QueueHealthEvents.lua')]:
            (lua / side).mkdir(parents=True, exist_ok=True)
            shutil.copy2(root / ('health' if side == 'shared' else 'startup') / side / name, lua / side)
    runtime['fixture'] = {'server_ready': '[STARTUP_TEST] SERVER_READY', 'sandbox': {'Zombies': 6}}


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(re.escape(MARKER) + r'COMPLETE[ \t]*\r?$', text, re.M)) == 1


def one(text, event):
    values = re.findall(re.escape(MARKER + event + ' ') + r'([^\n]*)', text)
    if len(values) != 1:
        raise ValueError('Missing or duplicate reading ' + event)
    return json.loads(values[0])


def verify(root, selection, catalog):
    issues, evidence = [], None
    try:
        root = Path(root)
        client = (root / 'client1-launch.log').read_text(errors='replace')
        server = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else client
        prepared, local, authority = one(server, 'PREPARED'), one(client, 'LOCAL'), one(server, 'AUTHORITY')
        ids = prepared['ids']
        if len(ids) != 15 or len(set(ids)) != 15 or any(type(value) is not int for value in ids):
            raise ValueError('Invalid magazine identities')
        expected = {'count': 15, 'items': [{'id': value, 'read': True, 'returned': True} for value in ids]}
        if local != expected or authority != expected or not complete(selection, 'client1', client):
            raise ValueError('Reading or exact return effects differ from expected receipts')
        profile = one(client, 'PROFILE')
        if any(profile['frames'][stage]['samples'] < 50 for stage in ('idle', 'running')):
            raise ValueError('Insufficient idle/running frame samples')
        if [row['count'] for row in profile['enqueue']] != list(range(5, 16)):
            raise ValueError('Missing bulk or incremental enqueue observation')
        evidence = {'receipt': authority, 'profile': profile,
                    'limits': ['Native menu callbacks, not physical input; one client; intervals are not GPU FPS.']}
    except (OSError, KeyError, ValueError, TypeError) as error:
        issues.append(str(error))
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': 'dresser-15',
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues)}], 'evidence': evidence}
