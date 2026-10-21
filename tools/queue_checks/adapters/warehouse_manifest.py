"""Authoritative warehouse snapshots and native withdrawal in SP/two-client menu Host."""
import json
import math
from pathlib import Path
import re
import shutil
import struct

SUITE = 'warehouse-manifest'
MARKER = '[WAREHOUSE_MANIFEST] '
MODS = ['PZSurvivorToolkit', 'EURY_CONTAINERS', 'organizedCategories_core']
PHASES = ('initial', 'changed', 'transferred')
COUNTS = ([2, 1, 1, 0], [1, 3, 0, 1], [1, 3, 0, 0])
CUSTOM = 'Warehouse custom nails'


def definitions():
    return {SUITE: {'status': 'ready', 'native_validation': 'not-run', 'clients': 2,
                    'default_mods': MODS,
                    'cases': [{'id': 'snapshot', 'producer': 'fixture', 'capability': 'effect',
                               'kinds': ['sp', 'mp'], 'languages': ['EN', 'RU'], 'modes': ['toolkit']}]
                             + [{'id': case, 'producer': 'fixture', 'capability': 'effect',
                                 'kinds': ['mp'], 'languages': ['EN', 'RU'], 'modes': ['toolkit']}
                                for case in ('persist-seed', 'persist-reload')]
                             + [{'id': case, 'producer': 'fixture', 'capability': 'effect',
                                 'kinds': ['sp'], 'languages': ['EN', 'RU'], 'modes': ['toolkit']}
                                for case in ('legacy-seed', 'legacy-reload')],
                    'limits': ['Programmatic menu/native transfer callbacks; screenshots need visual review.']}}


def validate(selection):
    if selection.get('cases') in (['legacy-seed'], ['legacy-reload']):
        from . import warehouse_legacy
        return warehouse_legacy.validate(selection)
    if selection.get('cases') in (['persist-seed'], ['persist-reload']):
        from . import warehouse_persistence
        return warehouse_persistence.validate(selection)
    kind, options = selection.get('kind'), selection.get('options', {})
    clients = selection.get('clients', 2 if kind == 'mp' else 1)
    if (selection.get('cases') != ['snapshot'] or kind not in ('sp', 'mp')
            or selection.get('mode') != 'toolkit' or type(clients) is not int
            or clients != (2 if kind == 'mp' else 1)
            or selection.get('languages') not in ((['EN', 'RU'],) if kind == 'mp' else (['EN'], ['RU']))
            or not set(MODS) <= set(selection.get('mods', [])) or not isinstance(options, dict)
            or any(options.get(key) for key in ('world_template', 'seed_run', 'startup_connection'))
            or kind == 'mp' and options.get('mp_host') is not True
            or kind == 'sp' and options.get('mp_host')):
        raise ValueError('Warehouse Manifest requires fresh SP or two-client menu Host, snapshot, Toolkit/BC/OC and EN/RU')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    result = [*sorted((root / SUITE).rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
              root / 'health/shared/QueueHealthEvents.lua']
    if selection.get('cases') in (['persist-seed'], ['persist-reload']):
        from . import warehouse_persistence
        result += [Path(warehouse_persistence.__file__), *warehouse_persistence.sources(selection)]
    if selection.get('cases') in (['legacy-seed'], ['legacy-reload']):
        from . import warehouse_legacy
        result.append(Path(warehouse_legacy.__file__))
    return result


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        target = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua'),
                           ('shared', 'QueueHealthEvents.lua')]:
            (target / side).mkdir(parents=True, exist_ok=True)
            shutil.copy2(root / ('health' if side == 'shared' else 'startup') / side / name, target / side)
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
                                            failure_markers=[MARKER + 'FAIL ', '[WAREHOUSE_PERSIST] FAIL ', '[WAREHOUSE_LEGACY] FAIL '],
                                            client_launch_stagger_seconds=8, sandbox={'Zombies': 6})


def _records(text, event):
    def unique(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise ValueError('Duplicate receipt JSON key ' + key)
            value[key] = item
        return value
    rows = []
    for line in text.splitlines():
        offset = line.find(MARKER + event + ' ')
        if offset >= 0:
            row = json.loads(line[offset + len(MARKER + event + ' '):], object_pairs_hook=unique,
                             parse_constant=lambda value: (_ for _ in ()).throw(ValueError('Nonfinite receipt ' + value)))
            if type(row) is not dict:
                raise ValueError('Receipt must be an object: ' + event)
            rows.append(row)
    return rows


def _one(text, event):
    rows = _records(text, event)
    if len(rows) != 1:
        raise ValueError('Missing/duplicate ' + event + ' receipt')
    return rows[0]


def _positive(value):
    return type(value) in (int, float) and math.isfinite(value) and value > 0


def _exact(value, expected):
    # Booleans must never satisfy integer counters/identities.
    if type(value) is not type(expected):
        return False
    if type(expected) is dict:
        return set(value) == set(expected) and all(_exact(value[key], item) for key, item in expected.items())
    if type(expected) is list:
        return len(value) == len(expected) and all(_exact(a, b) for a, b in zip(value, expected))
    return value == expected


def complete(selection, role, text):
    if selection.get('cases') in (['legacy-seed'], ['legacy-reload']):
        from . import warehouse_legacy
        return warehouse_legacy.complete(selection, role, text)
    if selection.get('cases') in (['persist-seed'], ['persist-reload']):
        from . import warehouse_persistence
        return warehouse_persistence.complete(selection, role, text)
    try:
        return role in ('client1', 'client2') and _exact(_records(text, 'COMPLETE'), [{'case': 'snapshot', 'role': role}])
    except ValueError:
        return False


def _shot(root, role, phase):
    path = root / role / 'Screenshots' / ('warehouse-manifest-' + phase + '.png')
    data = path.read_bytes()
    if len(data) < 33 or data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
        raise ValueError('Missing/invalid warehouse screenshot: ' + str(path))
    width, height = struct.unpack('>II', data[16:24])
    if width < 640 or height < 480:
        raise ValueError('Warehouse screenshot is too small: ' + str(path))
    return str(path)


def verify(root, selection, catalog):
    if selection.get('cases') in (['legacy-seed'], ['legacy-reload']):
        from . import warehouse_legacy
        return warehouse_legacy.verify(root, selection, catalog)
    if selection.get('cases') in (['persist-seed'], ['persist-reload']):
        from . import warehouse_persistence
        return warehouse_persistence.verify(root, selection, catalog)
    root = Path(root)
    roles = ['client1', 'client2'] if selection['kind'] == 'mp' else ['client1']
    issues, receipts, screenshots = [], {}, []
    try:
        logs = {role: (root / (role + '-launch.log')).read_text(errors='replace') for role in roles}
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else logs['client1']
        prepared = _one(authority, 'PREPARED')
        if (set(prepared) != {'boxes', 'ids', 'category'} or type(prepared['boxes']) is not list
                or len(prepared['boxes']) != 2 or type(prepared['ids']) is not list
                or len(prepared['ids']) != 4 or any(type(value) is not int for value in prepared['ids'])
                or len(set(prepared['ids'])) != 4 or type(prepared['category']) is not str or not prepared['category']):
            raise ValueError('Invalid authoritative preparation identities')
        for point in prepared['boxes']:
            if (type(point) is not dict or set(point) != {'x', 'y', 'z', 'object', 'ci', 'key', 'id'}
                    or any(type(point[key]) is not int for key in ('x', 'y', 'z', 'object', 'ci'))
                    or point['object'] < 0 or point['ci'] != 0
                    or point['key'] != f"{point['x']},{point['y']},{point['z']}"
                    or point['id'] != f"{point['key']}/{point['object']}/0"):
                raise ValueError('Invalid native world container descriptor')
        if prepared['boxes'][0]['key'] == prepared['boxes'][1]['key']:
            raise ValueError('Warehouse locations must be distinct')
        mutation = _one(authority, 'MUTATED')
        if (set(mutation) != {'removedId', 'customId', 'addedIds', 'changedAt'}
                or type(mutation['removedId']) is not int or mutation['removedId'] != prepared['ids'][0]
                or type(mutation['customId']) is not int or mutation['customId'] != prepared['ids'][3]
                or type(mutation['addedIds']) is not list or len(mutation['addedIds']) != 2
                or any(type(value) is not int for value in mutation['addedIds'])
                or len(set(prepared['ids'] + mutation['addedIds'])) != 6 or not _positive(mutation['changedAt'])):
            raise ValueError('Invalid exact authority mutation receipt')
        expected_authority = [dict(phase=phase, counts=counts, ids=prepared['ids'],
                                   addedIds=[] if phase == 'initial' else mutation['addedIds'])
                              for phase, counts in zip(PHASES, COUNTS)]
        if not _exact(_records(authority, 'AUTHORITY'), expected_authority):
            raise ValueError('Authority native identities/counts/withdrawal endpoint receipts differ')
        expected_transfer = dict(id=prepared['ids'][3], source=prepared['boxes'][1]['id'], destination='client1')
        if not _exact(_one(logs['client1'], 'TRANSFER'), dict(expected_transfer, progress=True)):
            raise ValueError('Native client withdrawal progress/identity absent')
        if not _exact(_one(authority, 'TRANSFER_AUTHORITY'), dict(expected_transfer, unique=True)):
            raise ValueError('Authoritative native withdrawal identity/endpoint absent')
        if not _exact(_one(authority, 'CLEANUP'), {'ownedObjects': 2}):
            raise ValueError('Owned fixture cleanup missing')
        if selection['kind'] == 'mp':
            if len(re.findall(re.escape('[STARTUP_TEST] SERVER_READY') + r'(?:\s|$)', authority)) != 1:
                raise ValueError('Missing/duplicate menu Host readiness')
            sequences = {'server': ['PREPARED', 'AUTHORITY', 'MUTATED', 'AUTHORITY', 'TRANSFER_AUTHORITY', 'AUTHORITY', 'CLEANUP'],
                         'client1': ['SETUP', 'MENU', 'SNAPSHOT', 'SHOT', 'SNAPSHOT', 'SHOT', 'TRANSFER', 'SNAPSHOT', 'SHOT', 'COMPLETE'],
                         'client2': ['SETUP', 'MENU', 'SNAPSHOT', 'SHOT', 'SNAPSHOT', 'SHOT', 'SNAPSHOT', 'SHOT', 'COMPLETE']}
        else:
            sequences = {'client1': ['SETUP', 'PREPARED', 'MENU', 'SNAPSHOT', 'SHOT', 'AUTHORITY', 'MUTATED',
                                     'SNAPSHOT', 'SHOT', 'AUTHORITY', 'TRANSFER', 'TRANSFER_AUTHORITY',
                                     'SNAPSHOT', 'SHOT', 'AUTHORITY', 'CLEANUP', 'COMPLETE']}
        for role, events in sequences.items():
            text = authority if role == 'server' else logs[role]
            if re.findall(re.escape(MARKER) + r'([A-Z_]+) ', text) != events:
                raise ValueError(role + ' lifecycle missing, duplicated or reordered')
        names = []
        for role, text in logs.items():
            language = selection['languages'][0 if role == 'client1' else 1]
            if not _exact(_one(text, 'SETUP'), dict(role=role, language=language, kind=selection['kind'], queueEnabled=True)):
                raise ValueError(role + ' native language/feature setup differs')
            if not _exact(_one(text, 'MENU'), {'role': role, 'nativeCallback': True}):
                raise ValueError(role + ' native Manifest menu callback absent')
            values = _records(text, 'SNAPSHOT')
            if len(values) != 3:
                raise ValueError(role + ' snapshot phases missing or duplicated')
            previous = 0
            for value, phase, counts in zip(values, PHASES, COUNTS):
                keys = {'phase', 'revision', 'samples', 'counts', 'role', 'language', 'defaultName', 'customName',
                        'appearance', 'locations', 'nativeItems', 'rendered', 'searchLocal'}
                if (set(value) != keys or value['phase'] != phase or value['role'] != role or value['language'] != language
                        or not _exact(value['counts'], counts) or type(value['revision']) is not int or value['revision'] <= previous
                        or type(value['samples']) is not list or len(value['samples']) != 2
                        or any(not _positive(stamp) for stamp in value['samples'])
                        or phase != 'initial' and any(stamp < mutation['changedAt'] for stamp in value['samples'])
                        or type(value['defaultName']) is not str or not value['defaultName'] or value['defaultName'] == CUSTOM
                        or value['customName'] != CUSTOM
                        or any(value[key] is not True for key in ('appearance', 'locations', 'nativeItems', 'rendered', 'searchLocal'))):
                    raise ValueError(role + ' exact ' + phase + ' snapshot/UI/render/search receipt differs')
                previous = value['revision']
            if len({value['defaultName'] for value in values}) != 1:
                raise ValueError(role + ' localized default label changed within one client')
            names.append(values[0]['defaultName'])
            receipts[role] = values
            if not _exact(_records(text, 'SHOT'), [dict(role=role, phase=phase) for phase in PHASES]):
                raise ValueError(role + ' screenshot lifecycle differs')
            screenshots += [_shot(root, role, phase) for phase in PHASES]
            if not complete(selection, role, text):
                raise ValueError(role + ' completion missing or duplicated')
        if selection['kind'] == 'mp' and names[0] == names[1]:
            raise ValueError('EN/RU clients did not localize the default item independently')
        if any(MARKER + 'FAIL ' in text or '[QUEUE_TEST] FAIL ' in text for text in [authority, *logs.values()]):
            raise ValueError('Native fixture failure marker present')
    except (OSError, ValueError, KeyError, TypeError) as error:
        issues.append(str(error))
    return {'issues': issues,
            'outcomes': [dict(actor=role, case='snapshot', status='failed' if issues else 'passed', reason='; '.join(issues)) for role in roles],
            'evidence': {'snapshots': receipts, 'screenshots': screenshots,
                         'limits': ['Programmatic native menu/transfer, no physical input or WAN claim.',
                                    'Search instrumentation covers synchronous UI world/RPC entrypoints.',
                                    'Screenshots require visual inspection; existence does not certify layout.']}}
