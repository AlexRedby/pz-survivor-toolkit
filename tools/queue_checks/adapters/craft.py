"""Native craft with exact borrowed tools and late return ordering; no UI substitution."""
from pathlib import Path
import re
import shutil

MODS = ['PZSurvivorToolkit', 'ZombieBuddy', 'PZToolkitJavaPatches']


def definitions():
    return {'craft': {'status': 'ready', 'clients': 1, 'default_mods': MODS,
                      'cases': [{'id': 'borrowed-tools', 'producer': 'fixture', 'capability': 'effect',
                                 'kinds': ['sp', 'mp'], 'languages': ['EN'], 'modes': ['native', 'toolkit']}]}}


def validate(selection):
    if (selection.get('cases') != ['borrowed-tools'] or selection.get('kind') not in ('sp', 'mp')
            or selection.get('mode') not in ('native', 'toolkit') or selection.get('languages') != ['EN']
            or type(selection.get('clients', 1)) is not int or selection.get('clients', 1) != 1
            or not set(MODS) <= set(selection.get('mods', []))
            or selection.get('options', {}).get('world_template')):
        raise ValueError('Craft requires borrowed-tools, fresh SP/MP, one EN client, Toolkit and Java patches')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted(path for path in (root / 'craft').rglob('*') if path.suffix in ('.lua', '.txt')),
            root / 'health/shared/QueueHealthEvents.lua', *sorted((root / 'startup').rglob('*.lua'))]


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        media = Path(role['cache']) / 'mods/ActionQueueTest/42/media'
        shutil.copytree(root / 'craft/scripts', media / 'scripts', dirs_exist_ok=True)
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua'),
                           ('shared', 'QueueHealthEvents.lua')]:
            target = media / 'lua' / side
            target.mkdir(parents=True, exist_ok=True)
            source = root / ('health' if side == 'shared' else 'startup') / side / name
            shutil.copy2(source, target)
    runtime['fixture'] = {'server_ready': '[STARTUP_TEST] SERVER_READY',
                          'sandbox': {'Zombies': 6, 'MinutesPerPage': 2.0}}


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(r'\[CRAFT_QUEUE_TEST\] COMPLETE(?:\s|$)', text)) == 1


def verify(root, selection, catalog):
    from ..report import events
    root = Path(root)
    text = (root / 'client1-launch.log').read_text(errors='replace')
    records = events(text)
    issues = []
    enabled = selection['mode'] == 'toolkit'
    if [row['event'] for row in records] != ['setup', 'case', 'complete']:
        issues.append('Missing, duplicated or reordered craft events')
    for row in records:
        if any(row.get(key) != value for key, value in {
                'suite': 'craft', 'kind': selection['kind'], 'mode': selection['mode'], 'actor': 'client1'}.items()):
            issues.append('Craft event context differs')
    expected = {'setup': {'cases': ['borrowed-tools'], 'expected': 1, 'queueEnabled': enabled, 'nativeDurations': True},
                'case': {'id': 'borrowed-tools', 'status': 'passed', 'consumed': 1, 'outputs': 1, 'toolsReturned': 2,
                         'tailRead': True, 'returnsBeforeRead': enabled, 'sharedPerform': enabled,
                         'sharedComplete': enabled and selection['kind'] == 'sp', 'localDeferrals': 0,
                         'nativeDuration': 150, 'authorityVerified': True},
                'complete': {'cases': ['borrowed-tools'], 'expected': 1, 'performed': 1, 'failed': 0, 'skipped': 0}}
    for row in records:
        if row['event'] not in expected or any(type(row.get(key)) is not type(value) or row.get(key) != value
                                              for key, value in expected[row['event']].items()):
            issues.append('Craft ' + row['event'] + ' evidence differs')
        if row['event'] == 'case':
            ids = row.get('toolIds')
            order = row.get('returnOrder')
            if (not isinstance(ids, list) or len(ids) != 2 or any(type(id) is not int for id in ids)
                    or len(set(ids)) != 2 or not isinstance(order, list)
                    or any(type(id) is not int for id in order) or order != ids):
                issues.append('Craft exact tool IDs or native return order differ')
    authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
    marker = '[CRAFT_QUEUE_TEST] AUTHORITY consumed=1 outputs=1 toolsReturned=2 tailRead=true'
    if len(re.findall(re.escape(marker) + r'(?:\s|$)', authority)) != 1:
        issues.append('Missing or duplicate authoritative craft receipt')
    if '[QUEUE_TEST] FAIL ' in text or '[QUEUE_TEST] FAIL ' in authority:
        issues.append('Native craft fixture failed')
    cases = [row for row in records if row['event'] == 'case']
    outcome = {key: cases[0].get(key) for key in ('consumed', 'outputs', 'toolsReturned', 'tailRead',
               'returnsBeforeRead', 'localDeferrals', 'nativeDuration', 'authorityVerified')} if len(cases) == 1 else {}
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': 'borrowed-tools',
             'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues), 'outcome': outcome}],
            'evidence': {'limits': ['Native recipe/transfer/read actions; late returns are injected at base.perform callback timing.',
                                    'No physical crafting UI, WAN or two-client contention coverage.']}}
