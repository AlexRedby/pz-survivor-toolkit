"""Exact native torch refill identities, retention and source returns in SP/menu Host."""
from pathlib import Path
import shutil
from .. import receipts

SUITE = 'torch-refill'
MARKER = '[TORCH_REFILL] '
CASES = ('trunk-retained', 'root-retained', 'trunk-unmarked')


def definitions():
    return {SUITE: {'status': 'ready', 'clients': 1,
                   'default_mods': ['PZSurvivorToolkit'],
                   'cases': [{'id': case, 'producer': 'fixture', 'capability': 'effect',
                              'kinds': ['sp', 'mp'], 'languages': ['EN'], 'modes': ['toolkit']}
                             for case in CASES],
                   'limits': ['Native context-menu callback; no physical input claim.']}}


def validate(selection):
    options = selection.get('options', {})
    if (len(selection.get('cases', [])) != 1 or selection['cases'][0] not in CASES
            or selection.get('kind') not in ('sp', 'mp') or selection.get('mode') != 'toolkit'
            or selection.get('clients', 1) != 1 or selection.get('languages') != ['EN']
            or 'PZSurvivorToolkit' not in selection.get('mods', [])
            or options.get('world_template') or options.get('seed_run')
            or (selection['kind'] == 'mp' and options.get('mp_host') is not True)):
        raise ValueError('Torch refill requires one EN client and one case in fresh SP/menu Host')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / SUITE).rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua', root / 'pinned-items/shared/PinnedItemsFixture.lua']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for source, side in [(root / 'startup/client/ZZStartup.lua', 'client'),
                             (root / 'startup/server/ZZStartupServer.lua', 'server'),
                             (root / 'health/shared/QueueHealthEvents.lua', 'shared'),
                             (root / 'pinned-items/shared/PinnedItemsFixture.lua', 'shared')]:
            (lua / side).mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, lua / side / source.name)
    runtime['fixture'] = {'server_ready': '[STARTUP_TEST] SERVER_READY',
                          'failure_markers': [MARKER + 'FAIL '], 'sandbox': {'Zombies': 6}}


def complete(selection, role, text):
    return receipts.records(text, MARKER, 'COMPLETE') == [{'case': selection['cases'][0], 'role': role}]


def verify(root, selection, catalog):
    root = Path(root)
    issues, evidence = [], {}
    try:
        client = (root / 'client1-launch.log').read_text(errors='replace')
        server = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else client
        for name, text in [('local', client), ('authority', server)]:
            rows = receipts.records(text, MARKER, name.upper())
            if len(rows) != 1:
                raise ValueError('Missing/duplicate torch ' + name + ' receipt')
            row = rows[0]
            if (row.get('case') != selection['cases'][0]
                    or type(row.get('sourceID')) is not int or type(row.get('outputID')) is not int
                    or row['sourceID'] == row['outputID'] or type(row.get('tankID')) is not int
                    or row.get('retained') is not (selection['cases'][0] != 'trunk-unmarked')
                    or any(row.get(key) is not True for key in
                           ('sourceRemoved', 'returned', 'tankReturned', 'fuelExact', 'conserved'))):
                raise ValueError('Invalid exact torch ' + name + ' evidence')
            evidence[name] = row
        if evidence['local'] != evidence['authority']:
            raise ValueError('Torch client/server effect identities differ')
        native = receipts.records(client, MARKER, 'NATIVE')
        if (len(native) != 1 or native[0].get('nativeDuration') is not True
                or native[0].get('selectedID') != evidence['local']['sourceID']
                or native[0].get('recipe') != 'Base.RefillBlowTorch'
                or native[0].get('queueDrained') is not True
                or native[0].get('craftObserved') is not True):
            raise ValueError('Missing native craft duration/identity/queue observation')
        if MARKER + 'FAIL ' in client + server or not complete(selection, 'client1', client):
            raise ValueError('Incomplete torch native lifecycle')
        evidence['native'] = native[0]
    except (OSError, KeyError, ValueError, TypeError) as error:
        issues.append(str(error))
    return {'issues': issues, 'evidence': evidence,
            'outcomes': [{'actor': 'client1', 'case': selection['cases'][0],
                          'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues)}]}
