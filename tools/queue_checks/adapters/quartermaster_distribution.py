"""Basic owned Quartermaster world-container distribution, in SP and Host."""
import json
from pathlib import Path
import re
import shutil

SUITE = 'quartermaster-distribution'
MODS = ['PZSurvivorToolkit', 'PZToolkitJavaPatches', 'organizedCategories_core']


def definitions():
    return {SUITE: {'status': 'ready', 'clients': 1, 'default_mods': MODS,
                   'cases': [{'id': 'sort', 'producer': 'fixture', 'capability': 'effect',
                              'kinds': ['sp', 'mp'], 'languages': ['EN'], 'modes': ['toolkit']}]}}


def validate(selection):
    if (selection.get('cases') != ['sort'] or selection.get('kind') not in ('sp', 'mp')
            or selection.get('mode') != 'toolkit' or selection.get('clients', 1) != 1
            or selection.get('languages') != ['EN'] or not set(MODS) <= set(selection.get('mods', []))
            or selection.get('options', {}).get('world_template')):
        raise ValueError('Distribution requires sort, fresh SP/Host, one EN client and Toolkit')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / SUITE).rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
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
    return role == 'client1' and len(re.findall(r'\[QM_DISTRIBUTION\] COMPLETE(?:\s|$)', text)) == 1


def _one(text, event):
    values = re.findall(r'\[QM_DISTRIBUTION\] ' + event + r' (\{[^\r\n]+\})', text)
    if len(values) != 1:
        raise ValueError('Missing/duplicate distribution ' + event)
    return json.loads(values[0])


def verify(root, selection, catalog):
    issues, receipt = [], None
    try:
        root = Path(root)
        text = (root / 'client1-launch.log').read_text(errors='replace')
        packet = _one(text, 'PREPARED')
        ids = packet['ids']
        if len(ids) != 4 or any(type(value) is not int for value in ids) or len(set(ids)) != 4:
            raise ValueError('Distribution item identities are not unique integers')
        expected = {'items': [{'id': value, 'container': dest} for value, dest in zip(ids, [2, 3, 1, 1])],
                    'moved': 2, 'retained': 2, 'favorite': True}
        receipt = _one(text, 'LOCAL')
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
        if receipt != expected or _one(authority, 'AUTHORITY') != expected:
            raise ValueError('Client/server distribution effects differ from exact designated destinations')
        marker = '[QM_DISTRIBUTION] COMPLETE moved=2 retained=2 walking=true pickup=true destinations=2 favorite=true'
        if not complete(selection, 'client1', text) or text.count(marker) != 1:
            raise ValueError('Distribution movement/transfer/cleanup gate missing')
    except (OSError, ValueError, KeyError, TypeError) as error:
        issues.append(str(error))
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': 'sort',
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues)}],
            'evidence': {'receipt': receipt, 'limits': ['Programmatic native button callback; no physical input or second client.']}}
