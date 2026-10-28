"""Authoritative warehouse snapshots and native withdrawal in SP/two-client menu Host."""
import math
from pathlib import Path
import re
import shutil
import struct

from .. import receipts

SUITE = 'warehouse-manifest'
MARKER = '[WAREHOUSE_MANIFEST] '
MODS = ['PZSurvivorToolkit', 'EURY_CONTAINERS']
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


def window_start_counts(selection):
    """The seed's native guest rejoin creates exactly one additional game start."""
    options = selection.get('options', {})
    if (selection.get('suite') == SUITE and selection.get('cases') == ['persist-seed']
            and selection.get('kind') == 'mp' and selection.get('mode') == 'toolkit'
            and type(selection.get('clients')) is int and selection['clients'] == 2
            and selection.get('languages') == ['EN', 'RU']
            and isinstance(options, dict) and options.get('mp_host') is True):
        return {'client2': 2}
    return {}


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
        raise ValueError('Warehouse Manifest requires fresh SP or two-client menu Host, snapshot, Toolkit/BC and EN/RU')


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
    return receipts.records(text, MARKER, event)


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


def _item_identities(value, category):
    """Validate frozen native Model.item descriptors, including known false states."""
    if type(value) is not dict or set(value) != {'default', 'custom'}:
        raise ValueError('Missing authoritative warehouse item identities')
    required = {'key', 'ft', 'cat', 'n'}
    optional = {'name', 'ingredient', 'cookingState', 'fluidState', 'usageState',
                'tagDelta', 'tagKey', 'mediaId', 'mediaIndex'}
    def units(text):
        # Native Kahlua Model.identity counts UTF-16 code units.
        return len(text.encode('utf-16-le')) // 2
    for kind, row in value.items():
        if (type(row) is not dict or not required <= set(row) or set(row) - required - optional
                or row.get('ft') != 'Base.Nails' or row.get('cat') != category
                or type(row.get('n')) is not int or row['n'] != 1
                or type(row.get('key')) is not str or not row['key']
                or kind == 'default' and 'name' in row
                or kind == 'custom' and row.get('name') != CUSTOM):
            raise ValueError('Invalid authoritative warehouse ' + kind + ' item identity')
        if ('ingredient' in row and type(row['ingredient']) is not bool
                or 'cookingState' in row and row['cookingState'] is not False and row['cookingState'] not in ('raw', 'cooked', 'burnt')
                or 'fluidState' in row and row['fluidState'] not in ('none', 'beverage', 'alcoholic')
                or 'usageState' in row and (type(row['usageState']) is not str
                    or not re.fullmatch(r'(?:[01?]{4}|[01?]{10,14})', row['usageState']) or not re.search('[01]', row['usageState']))
                or 'mediaIndex' in row and (type(row['mediaIndex']) is not int or row['mediaIndex'] < 0)
                or 'mediaId' in row and (type(row['mediaId']) is not str or not row['mediaId'] or 'mediaIndex' not in row)):
            raise ValueError('Invalid authoritative warehouse native state')
        tag_key = ''
        if 'tagDelta' in row or 'tagKey' in row:
            delta = row.get('tagDelta')
            if (type(delta) is not dict or not delta or type(row.get('tagKey')) is not str
                    or any(type(key) is not str or not key or operation not in ('add', 'remove') for key, operation in delta.items())):
                raise ValueError('Invalid authoritative warehouse tag delta')
            tag_key = ''.join(str(units(key)) + ':' + key + ':' + delta[key]
                              for key in sorted(delta, key=lambda text: text.encode('utf-16-be')))
            if row['tagKey'] != tag_key:
                raise ValueError('Authoritative warehouse tag key differs')
        media = row.get('mediaId', '#' + str(row['mediaIndex']) if 'mediaIndex' in row else '')
        expected = ''.join(str(units(part)) + ':' + part for part in (row['ft'], row.get('name', ''), category, media))
        for field in ('ingredient', 'cookingState', 'fluidState', 'usageState'):
            if field in row:
                text = str(row[field]).lower() if type(row[field]) is bool else row[field]
                expected += ':' + field + ':' + text
        if tag_key:
            expected += str(units(tag_key)) + ':' + tag_key
        if row['key'] != expected:
            raise ValueError('Authoritative warehouse item key omits/differs from native state')
    if value['default']['key'] == value['custom']['key']:
        raise ValueError('Default/custom warehouse identities overlap')


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
    issues, receipts, idle_receipts, screenshots = [], {}, {}, []
    try:
        logs = {role: (root / (role + '-launch.log')).read_text(errors='replace') for role in roles}
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else logs['client1']
        prepared = _one(authority, 'PREPARED')
        if (set(prepared) != {'boxes', 'ids', 'category', 'identities'} or type(prepared['boxes']) is not list
                or len(prepared['boxes']) != 2 or type(prepared['ids']) is not list
                or len(prepared['ids']) != 4 or any(type(value) is not int for value in prepared['ids'])
                or len(set(prepared['ids'])) != 4 or type(prepared['category']) is not str or not prepared['category']):
            raise ValueError('Invalid authoritative preparation identities')
        _item_identities(prepared['identities'], prepared['category'])
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
                         'client1': ['SETUP', 'MENU', 'SNAPSHOT', 'SHOT', 'IDLE', 'SNAPSHOT', 'SHOT', 'TRANSFER', 'SNAPSHOT', 'SHOT', 'COMPLETE'],
                         'client2': ['SETUP', 'MENU', 'SNAPSHOT', 'SHOT', 'IDLE', 'SNAPSHOT', 'SHOT', 'SNAPSHOT', 'SHOT', 'COMPLETE']}
        else:
            sequences = {'client1': ['SETUP', 'PREPARED', 'MENU', 'SNAPSHOT', 'SHOT', 'IDLE', 'AUTHORITY', 'MUTATED',
                                     'SNAPSHOT', 'SHOT', 'AUTHORITY', 'TRANSFER', 'TRANSFER_AUTHORITY',
                                     'SNAPSHOT', 'SHOT', 'AUTHORITY', 'CLEANUP', 'COMPLETE']}
        for role in roles:
            events = sequences[role]
            sequences[role] = [part for event in events for part in (['LAYOUT', event] if event == 'SNAPSHOT' else [event])]
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
            layouts = _records(text, 'LAYOUT')
            if len(layouts) != 3:
                raise ValueError(role + ' default/minimum/enlarged layout evidence missing')
            for layout, (width, height) in zip(layouts, ((640, 600), (480, 440), (800, 700))):
                if (set(layout) != {'width', 'height', 'fontHeight', 'footerY', 'footerHeight', 'glyphBottom', 'resizeTop', 'lines'}
                        or any(not _positive(value) for value in layout.values())
                        or layout['width'] != width or layout['height'] != height or layout['lines'] < 2
                        or layout['glyphBottom'] > layout['footerHeight']
                        or layout['footerY'] + layout['footerHeight'] > layout['resizeTop'] - 8
                        or layout['resizeTop'] >= layout['height']):
                    raise ValueError(role + ' native footer is clipped or overlaps the resize strip')
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
            idle = _one(text, 'IDLE')
            identity_keys = ('payloadSame', 'containersSame', 'viewSame', 'rowsSame',
                             'listItemsSame', 'locationItemsSame', 'sortsSame')
            if (set(idle) != {'role', 'revision', 'polls', 'pages', 'itemEntries', 'initialSamples', 'samples', *identity_keys}
                    or idle['role'] != role or type(idle['revision']) is not int or idle['revision'] != values[0]['revision']
                    or not _exact(idle['polls'], 2) or type(idle['pages']) is not int or idle['pages'] < idle['polls']
                    or not _exact(idle['itemEntries'], 0) or not _exact(idle['initialSamples'], values[0]['samples'])
                    or type(idle['samples']) is not list or len(idle['samples']) != 2
                    or any(idle[key] is not True for key in identity_keys)):
                raise ValueError(role + ' exact idle revision/pagination/cache evidence differs')
            previous_samples = idle['initialSamples']
            for samples in idle['samples']:
                if (type(samples) is not list or len(samples) != 2
                        or any(not _positive(stamp) or stamp <= previous_samples[i] or stamp > mutation['changedAt']
                               for i, stamp in enumerate(samples))):
                    raise ValueError(role + ' idle samples did not advance before mutation')
                previous_samples = samples
            names.append(values[0]['defaultName'])
            receipts[role] = values
            idle_receipts[role] = idle
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
            'evidence': {'snapshots': receipts, 'idle': idle_receipts, 'screenshots': screenshots,
                         'limits': ['Programmatic native menu/transfer, no physical input or WAN claim.',
                                    'Search instrumentation covers synchronous UI world/RPC entrypoints.',
                                    'Screenshots require visual inspection; existence does not certify layout.']}}
