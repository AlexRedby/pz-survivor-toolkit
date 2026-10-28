"""Exact native torch refill identities, retention and source returns in SP/menu Host."""
from pathlib import Path
import shutil
from .. import receipts

SUITE = 'torch-refill'
MARKER = '[TORCH_REFILL] '
CASES = ('trunk-retained', 'root-retained', 'trunk-unmarked')


def definitions():
    return {SUITE: {'status': 'ready', 'clients': 1, 'shared_session': True,
                   'default_mods': ['PZSurvivorToolkit'],
                   'cases': [{'id': case, 'producer': 'fixture', 'capability': 'effect',
                              'kinds': ['sp', 'mp'], 'languages': ['EN'], 'modes': ['toolkit']}
                             for case in CASES],
                   'limits': ['Native context-menu callback; no physical input claim.',
                              'Only these torch cases share a qualified lifecycle: owned resources, equipment, position and inventory panes are restored.',
                              'Natural time and native craft history advance normally; history/timing-sensitive scenarios need their own lifecycle contract.']}}


def validate(selection):
    options = selection.get('options', {})
    selected = selection.get('cases', [])
    if (not selected or len(selected) != len(set(selected)) or any(case not in CASES for case in selected)
            or selection.get('kind') not in ('sp', 'mp') or selection.get('mode') != 'toolkit'
            or selection.get('clients', 1) != 1 or selection.get('languages') != ['EN']
            or 'PZSurvivorToolkit' not in selection.get('mods', [])
            or options.get('world_template') or options.get('seed_run')
            or (selection['kind'] == 'mp' and options.get('mp_host') is not True)):
        raise ValueError('Torch refill requires one EN client and unique cases in fresh SP/menu Host')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / SUITE).rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueFixtureSession.lua']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for source, side in [(root / 'startup/client/ZZStartup.lua', 'client'),
                             (root / 'startup/server/ZZStartupServer.lua', 'server'),
                             (root / 'health/shared/QueueHealthEvents.lua', 'shared'),
                             (root / 'support/QueueFixtureSession.lua', 'shared')]:
            (lua / side).mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, lua / side / source.name)
    runtime['fixture'] = {'server_ready': '[STARTUP_TEST] SERVER_READY',
                          'failure_markers': [MARKER + 'FAIL '], 'sandbox': {'Zombies': 6}}


def session_complete(selection, role, text):
    count = len(selection['cases'])
    marker = (f'[QUEUE_SESSION] COMPLETE case={selection["cases"][-1]} '
              f'epoch={count} actor={role} cases={count}')
    return sum(line.endswith(marker) for line in text.splitlines()) == 1


def complete(selection, role, text):
    expected = [{'case': case, 'epoch': epoch, 'role': role}
                for epoch, case in enumerate(selection['cases'], 1)]
    return receipts.records(text, MARKER, 'COMPLETE') == expected and session_complete(selection, role, text)


def verify(root, selection, catalog):
    root = Path(root)
    issues, evidence, outcomes = [], {}, []
    try:
        client = (root / 'client1-launch.log').read_text(errors='replace')
        server = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else client
        rows = {event: receipts.records(text, MARKER, event) for event, text in
                [('LOCAL', client), ('AUTHORITY', server), ('NATIVE', client),
                 ('REMOVED', server), ('CLEANUP', client)]}
        expected = [(case, epoch) for epoch, case in enumerate(selection['cases'], 1)]
        for event, values in rows.items():
            if [(row.get('case'), row.get('epoch')) for row in values] != expected:
                raise ValueError('Missing, duplicate or out-of-order torch ' + event + ' phases')
        if MARKER + 'FAIL ' in client + server or '[QUEUE_SESSION] QUARANTINE ' in client + server:
            raise ValueError('Torch session quarantined')
        if not complete(selection, 'client1', client) or not session_complete(selection, 'server', server):
            raise ValueError('Incomplete torch native lifecycle')
        # Cleanup must precede the following phase's native callback, not merely appear later in the log.
        lifecycle = []
        for line in client.splitlines():
            for event in ('LOCAL', 'NATIVE', 'CLEANUP', 'COMPLETE'):
                prefix = MARKER + event + ' '
                offset = line.find(prefix)
                if offset >= 0:
                    row = receipts.decode_object(line[offset + len(prefix):])
                    lifecycle.append((row.get('case'), row.get('epoch'), event))
        if lifecycle != [(case, epoch, event) for case, epoch in expected
                         for event in ('LOCAL', 'NATIVE', 'CLEANUP', 'COMPLETE')]:
            raise ValueError('Torch phase cleanup order differs')
        prior_ids = set()
        for index, (case, epoch) in enumerate(expected):
            local, authority = rows['LOCAL'][index], rows['AUTHORITY'][index]
            native, removed, cleanup = rows['NATIVE'][index], rows['REMOVED'][index], rows['CLEANUP'][index]
            problem = []
            for name, row in [('local', local), ('authority', authority)]:
                ids = [row.get(key) for key in ('sourceID', 'outputID', 'tankID')]
                if (any(type(value) is not int for value in ids) or len(set(ids)) != 3
                        or row.get('retained') is not (case != 'trunk-unmarked')
                        or any(row.get(key) is not True for key in
                               ('sourceRemoved', 'returned', 'tankReturned', 'fuelExact', 'conserved'))):
                    problem.append('Invalid exact torch ' + name + ' evidence')
            if local != authority:
                problem.append('Torch client/server effect identities differ')
            ids = {local.get(key) for key in ('sourceID', 'outputID', 'tankID')}
            if ids & prior_ids:
                problem.append('Torch identities reused between phases')
            prior_ids.update(ids)
            if (native.get('nativeDuration') is not True or native.get('selectedID') != local.get('sourceID')
                    or native.get('recipe') != 'Base.RefillBlowTorch'
                    or any(native.get(key) is not True for key in ('queueDrained', 'craftObserved'))
                    or type(native.get('duration')) not in (int, float) or native['duration'] <= 1):
                problem.append('Missing native craft duration/identity/queue observation')
            if (removed.get('items') != [local.get('sourceID'), local.get('tankID'), local.get('outputID')]
                    or removed.get('hasVehicle') is not (case != 'root-retained')
                    or type(removed.get('vehicle')) is not int or removed.get('baselineRestored') is not True
                    or any(cleanup.get(key) is not True for key in ('ownedRemoved', 'baselineRestored'))
                    or cleanup.get('role') != 'client1'):
                problem.append('Missing exact owned cleanup/baseline evidence')
            evidence[case] = dict(local=local, authority=authority, native=native, removed=removed, cleanup=cleanup)
            issues.extend(case + ': ' + reason for reason in problem)
            outcomes.append({'actor': 'client1', 'case': case, 'status': 'failed' if problem else 'passed',
                             'reason': '; '.join(problem)})
    except (OSError, KeyError, ValueError, TypeError) as error:
        issues.append(str(error))
        outcomes = [{'actor': 'client1', 'case': case, 'status': 'failed', 'reason': str(error)}
                    for case in selection['cases']]
    return {'issues': issues, 'evidence': evidence, 'outcomes': outcomes}
