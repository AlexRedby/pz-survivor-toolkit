"""Two native menu-Host clients exercise world-shared tag editors and assignment rules."""
from pathlib import Path
import re
import shutil
from .. import receipts

SUITE = 'custom-tags'
MARKER = '[CUSTOM_TAG_TEST] '
PROJECT = Path(__file__).resolve().parents[3]
MODS = re.search(r'^Mods=(.*)$', (PROJECT / 'SurvivorQoL-selected.ini').read_text(), re.M)[1].split(';')
PHASES = ('Create', 'Builtin', 'TypeAdd', 'ItemRemove', 'ItemDefault', 'ItemAdd', 'ItemReset',
          'TypeRemove', 'TypeReset', 'TypeFinal', 'ItemFinal', 'Cancel', 'Conflict',
          'RetiredCreate', 'RetiredAssign', 'RetiredDelete')


def definitions():
    return {SUITE: {'status': 'ready', 'clients': 2, 'default_mods': MODS,
                   'cases': [{'id': case, 'producer': 'fixture', 'capability': 'effect',
                              'kinds': ['mp'], 'languages': ['EN', 'RU'], 'modes': ['toolkit']}
                             for case in ('edit', 'reload')],
                   'limits': ['Native context/editor Save and Cancel callbacks; no physical mouse-input claim.']}}


def validate(selection):
    options = selection.get('options', {})
    if (selection.get('cases') not in (['edit'], ['reload']) or selection.get('kind') != 'mp'
            or selection.get('mode') != 'toolkit' or selection.get('clients') != 2
            or selection.get('languages') != ['EN', 'RU'] or options.get('mp_host') is not True
            or not set(MODS) <= set(selection.get('mods', []))
            or 'organizedCategories_core' in selection.get('mods', [])
            or any(options.get(key) for key in ('seed_run', 'startup_connection'))
            or bool(options.get('world_template')) != (selection['cases'] == ['reload'])):
        raise ValueError('Custom tags require selected pack without OC, two EN/RU menu-Host clients; reload needs sealed edit world')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / SUITE).rglob('*.lua')), *sorted((root / SUITE).rglob('*.json')), *sorted((root / 'startup').rglob('*.lua')),
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
                raise ValueError(role + ': missing/duplicate final tag evidence')
            row = rows[0]
            expected = {'role', 'tag', 'retired', 'revision', 'ids', 'truckId', 'shared', 'exact',
                        'tombstone', 'categoriesUnchanged', 'noOC'}
            if (set(row) != expected or row['role'] != role
                    or not all(row[key] is True for key in ('shared', 'exact', 'tombstone', 'categoriesUnchanged', 'noOC'))
                    or type(row['revision']) is not int or row['revision'] < 10
                    or type(row['truckId']) is not int or row['truckId'] < 0
                    or not isinstance(row['ids'], list) or len(row['ids']) != 4 or len(set(row['ids'])) != 4
                    or any(type(value) is not int for value in row['ids'])
                    or not all(isinstance(row[key], str) and re.fullmatch(r'custom:[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', row[key]) for key in ('tag', 'retired'))
                    or row['tag'] == row['retired']):
                raise ValueError(role + ': invalid identity/shared/exact/tombstone evidence')
            evidence[role] = row
            checks = receipts.records(text, MARKER, 'CHECK')
            phases = ['Reload'] if reload else list(PHASES)
            if ([entry.get('phase') for entry in checks] != phases
                    or any(entry.get('role') != role or entry.get('passed') is not True for entry in checks)):
                raise ValueError(role + ': missing or reordered phase assertions')
            if MARKER + 'FAIL ' in text or role != 'server' and not complete(selection, role, text):
                raise ValueError(role + ': failed or incomplete lifecycle')
            if not reload and role == 'client1':
                ui = receipts.records(text, MARKER, 'UI')
                if len(ui) != 1 or ui[0] != dict(catalog=True,assignment=True,cancel=True,conflict=True,color=True,icon=True):
                    raise ValueError('Missing actual editor callbacks and cancel/conflict evidence')
                for name in ('custom-tags-catalog.png', 'custom-tags-assignment.png', 'custom-tags-conflict.png',
                             'custom-tags-color.png', 'custom-tags-icon.png'):
                    if (root / role / 'Screenshots' / name).read_bytes()[:8] != b'\x89PNG\r\n\x1a\n':
                        raise ValueError('Missing editor screenshot ' + name)
            if reload and role == 'client2':
                for name in ('custom-tags-reload-ru-catalog.png', 'custom-tags-reload-ru-assignment.png'):
                    if (root / role / 'Screenshots' / name).read_bytes()[:8] != b'\x89PNG\r\n\x1a\n':
                        raise ValueError('Missing read-only RU reload editor screenshot ' + name)
            if role != 'server':
                consumers = receipts.records(text, MARKER, 'CONSUMERS')
                if consumers != [dict(role=role,filter=True,quartermaster=True,retiredInclude=False)]:
                    raise ValueError(role + ': missing actual filter/Quartermaster consumer evidence')
        for role in ('client1', 'client2'):
            if any(evidence[role][key] != evidence['server'][key] for key in ('tag', 'retired', 'revision', 'ids', 'truckId')):
                raise ValueError('Authority and owner/observer identities or revisions differ')
    except (OSError, ValueError, KeyError, TypeError) as error:
        issues.append(str(error))
    return {'issues': issues,
            'outcomes': [{'actor': role, 'case': selection['cases'][0], 'status': 'failed' if issues else 'passed',
                          'reason': '; '.join(issues)} for role in ('client1', 'client2')],
            'evidence': evidence}
