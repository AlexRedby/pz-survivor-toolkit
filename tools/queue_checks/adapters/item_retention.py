"""Exact retained-item effects through two native menu-Host clients."""
from pathlib import Path
import shutil
from .. import receipts

SUITE = 'item-retention'
MARKER = '[ITEM_RETENTION_TEST] '


def definitions():
    return {SUITE: {'status': 'ready', 'clients': 2,
                   'default_mods': ['PZSurvivorToolkit', 'EURY_CONTAINERS', 'CleanUI'],
                   'cases': [{'id': case, 'producer': 'fixture', 'capability': 'effect',
                              'kinds': ['mp'], 'languages': ['EN', 'RU'], 'modes': ['toolkit']}
                             for case in ('trunk', 'reload')],
                   'limits': ['Real native menu callbacks; no physical mouse-input claim.']}}


def validate(selection):
    options = selection.get('options', {})
    if (selection.get('cases') not in (['trunk'], ['reload']) or selection.get('kind') != 'mp'
            or selection.get('mode') != 'toolkit' or selection.get('clients') != 2
            or selection.get('languages') != ['EN', 'RU'] or options.get('mp_host') is not True
            or not {'PZSurvivorToolkit', 'EURY_CONTAINERS', 'CleanUI'} <= set(selection.get('mods', []))
            or 'organizedCategories_core' in selection.get('mods', [])
            or any(options.get(key) for key in ('seed_run', 'startup_connection'))
            or bool(options.get('world_template')) != (selection['cases'] == ['reload'])):
        raise ValueError('Retention requires two-client EN/RU menu Host without OC; reload needs a sealed trunk world')


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
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
                                            failure_markers=[MARKER + 'FAIL '],
                                            client_launch_stagger_seconds=8, sandbox={'Zombies': 6})


def complete(selection, role, text):
    try:
        return receipts.records(text, MARKER, 'COMPLETE') == [{'case': selection['cases'][0], 'role': role}]
    except ValueError:
        return False


def verify(root, selection, catalog):
    root = Path(root)
    issues, evidence = [], {}
    reload = selection['cases'] == ['reload']
    try:
        for role in ('server', 'client1', 'client2'):
            text = (root / (role + '-launch.log')).read_text(errors='replace')
            rows = receipts.records(text, MARKER, 'PERSISTED' if reload else 'VERIFIED')
            if len(rows) != 1:
                raise ValueError(role + ': missing/duplicate verified receipt')
            row = rows[0]
            expected = (dict(role=role, retained=True, legacy=True, released=True, noOC=True) if reload
                        else dict(role=role, retained=True, legacy=True, observer=True,
                                  distributed=True, manual=True, released=True, conserved=True, noOC=True))
            if (set(row) != set(expected) | {'truckId', 'ids'}
                    or any(type(row[k]) is not type(v) or row[k] != v for k, v in expected.items())
                    or type(row['truckId']) is not int or row['truckId'] < 0
                    or not isinstance(row['ids'], list) or len(row['ids']) != 4
                    or any(type(value) is not int for value in row['ids']) or len(set(row['ids'])) != 4):
                raise ValueError(role + ': missing or invalid retention/transfer evidence')
            evidence[role] = row
            if MARKER + 'FAIL ' in text:
                raise ValueError(role + ': failure marker')
            if role != 'server' and not complete(selection, role, text):
                raise ValueError(role + ': incomplete native lifecycle')
        for role in ('client1', 'client2'):
            if any(evidence[role][key] != evidence['server'][key] for key in ('ids', 'truckId')):
                raise ValueError('Owner/observer/server native identities differ')
            if not reload:
                text = (root / (role + '-launch.log')).read_text(errors='replace')
                markers = receipts.records(text, MARKER, 'MARKERS')
                if (len(markers) != 1 or set(markers[0]) != {'role', 'markedRows', 'retainedIds'}
                        or markers[0]['role'] != role or markers[0]['retainedIds'] != 3
                        or type(markers[0]['markedRows']) is not int or markers[0]['markedRows'] < 3):
                    raise ValueError('Missing exact retained-item marker evidence: ' + role)
                orders = receipts.records(text, MARKER, 'ORDER')
                expected_modes = ['clean', 'vanilla'] if role == 'client1' else ['vanilla', 'clean']
                if len(orders) != 2:
                    raise ValueError('Missing native/CleanUI retained ordering evidence: ' + role)
                for index, order in enumerate(orders):
                    if (set(order) != {'role', 'mode', 'hostUpdate', 'physicalOrder', 'selectedId',
                                       'retainedBeforePinned', 'mixedCopiesSplit', 'exactSelection',
                                       'repeatedRefresh'}
                            or order['role'] != role or order['mode'] != expected_modes[index]
                            or order['hostUpdate'] is not (index == 0)
                            or any(order[key] is not True for key in ('retainedBeforePinned',
                                      'mixedCopiesSplit', 'exactSelection', 'repeatedRefresh'))
                            or type(order['selectedId']) is not int
                            or order['selectedId'] != evidence[role]['ids'][1]
                            or not isinstance(order['physicalOrder'], list)
                            or len(order['physicalOrder']) != 4
                            or any(type(value) is not int for value in order['physicalOrder'])
                            or set(order['physicalOrder']) != set(evidence[role]['ids'])
                            or order['physicalOrder'][-1] != evidence[role]['ids'][1]):
                        raise ValueError('Invalid physical retained ordering/selection evidence: ' + role)
                for name in ('item-retention-menu.png', 'item-retention-markers.png'):
                    shot = root / role / 'Screenshots' / name
                    if shot.read_bytes()[:8] != b'\x89PNG\r\n\x1a\n':
                        raise ValueError('Missing real inventory screenshot: ' + role + '/' + name)
    except (OSError, ValueError, KeyError, TypeError) as error:
        issues.append(str(error))
    return {'issues': issues,
            'outcomes': [{'actor': role, 'case': selection['cases'][0], 'status': 'failed' if issues else 'passed',
                          'reason': '; '.join(issues)} for role in ('client1', 'client2')],
            'evidence': evidence}
