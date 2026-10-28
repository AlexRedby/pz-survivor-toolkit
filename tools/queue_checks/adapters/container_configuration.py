"""Unified Quartermaster container editing through native UI callbacks and Host authority."""
import math
from pathlib import Path
import re
import shutil
import struct

from .. import receipts

SUITE = 'container-configuration'
MARKER = '[CONTAINER_CONFIG] '
MODS = ['NeatUI_Framework', 'CleanUI', 'PZSurvivorToolkit', 'EURY_CONTAINERS']
PNG = b'\x89PNG\r\n\x1a\n'
CUSTOM_NAME = 'Fixture custom supplies'
CUSTOM_ID = re.compile(r'custom:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')


def definitions():
    return {SUITE: {'status': 'ready', 'native_validation': 'not-run', 'clients': 2,
                    'default_mods': MODS,
                    'cases': [{'id': 'edit', 'producer': 'fixture', 'capability': 'effect',
                               'kinds': ['sp', 'mp'], 'languages': ['EN', 'RU'], 'modes': ['toolkit']}],
                    'limits': ['Programmatic native callbacks; screenshots require separate visual review.']}}


def validate(selection):
    kind = selection.get('kind')
    clients = selection.get('clients', 2 if kind == 'mp' else 1)
    options = selection.get('options', {})
    if (selection.get('cases') != ['edit'] or kind not in ('sp', 'mp')
            or selection.get('mode') != 'toolkit' or type(clients) is not int
            or clients != (2 if kind == 'mp' else 1)
            or selection.get('languages') not in ((['EN', 'RU'],) if kind == 'mp' else (['EN'], ['RU']))
            or not set(MODS) <= set(selection.get('mods', [])) or not isinstance(options, dict)
            or any(options.get(key) for key in ('world_template', 'seed_run', 'startup_connection'))
            or kind == 'mp' and options.get('mp_host') is not True
            or kind == 'sp' and options.get('mp_host')):
        raise ValueError('Container configuration requires edit, fresh SP or two-client Host, Toolkit/BC/CleanUI and EN/RU')
    if options.get('profile_container_open') and (
            not isinstance(selection.get('resources'), dict)
            or selection['resources'].get('exclusive') is not True):
        raise ValueError('Container opening profiles require exclusive resource admission')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / SUITE).rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    support = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        target = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua'),
                           ('shared', 'QueueHealthEvents.lua')]:
            (target / side).mkdir(parents=True, exist_ok=True)
            shutil.copy2(support / ('health' if side == 'shared' else 'startup') / side / name, target / side)
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
                                            failure_markers=[MARKER + 'FAIL '],
                                            client_launch_stagger_seconds=8,
                                            sandbox={'Zombies': 6})


def _records(text, event):
    return receipts.records(text, MARKER, event)


def complete(selection, role, text):
    try:
        return _records(text, 'COMPLETE') == [{'case': 'edit', 'role': role}]
    except ValueError:
        return False


def _one(text, event):
    rows = _records(text, event)
    if len(rows) != 1:
        raise ValueError('Missing/duplicate ' + event + ' receipt')
    return rows[0]


def _expected(category, custom_id):
    return dict(name='QM supplies', iconKind='pzst-tag', iconValue='edible',
                customId=custom_id, customName=CUSTOM_NAME,
                r=.25, g=.5, b=.75, a=1, category=category, categorySelected=True,
                categoryCount=1, itemCount=0, presetCount=0, priority=6, ruleMode='',
                include=[], exclude=[], groups=[
                    {'include': ['edible', 'perishable'], 'exclude': ['meat']},
                    {'include': ['mechanics'], 'exclude': ['vehiclepart']},
                    {'include': [custom_id], 'exclude': []},
                ], revision=1)


def _exact(value, expected):
    return (type(value) is dict and set(value) == set(expected)
            and all(type(value[key]) is type(want) and value[key] == want
                    if type(want) not in (float, int) else type(value[key]) in (float, int)
                    and type(value[key]) is not bool and math.isfinite(value[key]) and value[key] == want
                    for key, want in expected.items()))


def _shot(root, role, name):
    path = root / role / 'Screenshots' / ('container-config-' + name + '.png')
    data = path.read_bytes()
    if len(data) < 33 or data[:8] != PNG or data[12:16] != b'IHDR':
        raise ValueError('Missing/invalid native screenshot: ' + str(path))
    width, height = struct.unpack('>II', data[16:24])
    if width < 400 or height < 300:
        raise ValueError('Native screenshot is too small: ' + str(path))
    return str(path)


def _opening_profile(text):
    samples = _one(text, 'PERF').get('samples')
    names = ['idle', 'containerCold', 'ruleCold', 'chooserCold', 'chooserWarm', 'ruleWarm', 'containerWarm',
             'tagCatalogCold', 'tagCatalogWarm']
    if not isinstance(samples, list) or [row.get('name') for row in samples if isinstance(row, dict)] != names:
        raise ValueError('Opening profile stages missing, duplicated or reordered')

    def duration(value):
        return type(value) in (int, float) and math.isfinite(value) and value >= 0

    for row in samples:
        for key in ('callbackMs', 'firstUiPassMs', 'started'):
            if not duration(row.get(key)):
                raise ValueError('Invalid opening profile duration: ' + key)
        if row['name'] != 'idle' and not duration(row.get('firstTargetRenderMs')):
            raise ValueError('Opening profile lacks target window render')
        if row['name'] != 'idle' and (not duration(row.get('readyRenderMs'))
                                     or row['readyRenderMs'] < row['firstTargetRenderMs']):
            raise ValueError('Opening profile lacks completed catalogue render')
        for key in ('frameGaps', 'uiMs'):
            values = row.get(key)
            if not isinstance(values, list) or len(values) < 5 or not all(duration(value) for value in values):
                raise ValueError('Opening profile lacks valid frame samples')
        calls = row.get('functions')
        if calls == []:  # Lua encodes an empty map as an array.
            calls = {}
        if not isinstance(calls, dict):
            raise ValueError('Invalid opening profile function counters')
        for value in calls.values():
            if (not isinstance(value, dict) or type(value.get('calls')) is not int or value['calls'] < 1
                    or not duration(value.get('totalMs')) or not duration(value.get('maxMs'))):
                raise ValueError('Invalid opening profile function timing')
    return samples


def verify(root, selection, catalog):
    root = Path(root)
    roles = ['client1', 'client2'] if selection['kind'] == 'mp' else ['client1']
    issues, receipts, screenshots, opening, parity = [], {}, [], [], {}
    try:
        logs = {role: (root / (role + '-launch.log')).read_text(errors='replace') for role in roles}
        authority_role = 'server' if selection['kind'] == 'mp' else 'client1'
        authority = (root / (authority_role + '-launch.log')).read_text(errors='replace')
        prepared = _one(authority, 'PREPARED')
        if (set(prepared) != {'x', 'y', 'z', 'index', 'category', 'customId', 'customName'}
                or any(type(prepared[key]) is not int for key in ('x', 'y', 'z', 'index'))
                or prepared['index'] < 0 or type(prepared['category']) is not str or not prepared['category']
                or type(prepared['customId']) is not str or not CUSTOM_ID.fullmatch(prepared['customId'])
                or prepared['customName'] != CUSTOM_NAME):
            raise ValueError('Invalid owned crate descriptor')
        category = prepared['category']
        if selection['kind'] == 'mp' and len(re.findall(re.escape('[STARTUP_TEST] SERVER_READY') + r'(?:\s|$)', authority)) != 1:
            raise ValueError('Missing/duplicate Host server readiness')
        owner_events = ['SHOT'] * 11 + ['TAGUI', 'SHOT', 'SHOT', 'SHOT', 'SHOT', 'DEFAULTS', 'SHOT', 'SHOT', 'SAVE', 'LOCAL']
        sequences = {'client1': owner_events + ['COMPLETE']}
        if selection['kind'] == 'sp':
            sequences['client1'] = ['PREPARED', *owner_events, 'AUTHORITY', 'COMPLETE']
        else:
            sequences['client2'] = ['SHOT', 'OBSERVER', 'COMPLETE']
            sequences['server'] = ['PREPARED', 'AUTHORITY']
        if selection.get('options', {}).get('profile_container_open'):
            sequences['client1'].insert(1 if selection['kind'] == 'sp' else 0, 'PERF')
            opening = _opening_profile(logs['client1'])
        if selection.get('options', {}).get('check_script_choice_parity'):
            position = (1 if selection['kind'] == 'sp' else 0) + bool(opening)
            sequences['client1'].insert(position, 'CHOICEPARITY')
            parity = _one(logs['client1'], 'CHOICEPARITY')
            if set(parity) != {'scripts'} or type(parity['scripts']) is not int or parity['scripts'] <= 0:
                raise ValueError('Script choice parity requires a positive native script count')
        for role, expected_events in sequences.items():
            text = authority if role == 'server' else logs[role]
            events = re.findall(re.escape(MARKER) + r'([A-Z]+) ', text)
            if events != expected_events:
                raise ValueError(role + ' native lifecycle missing, duplicated or reordered')
        if _one(logs['client1'], 'TAGUI') != dict(oneClick=True, checked=True, advancedApplied=True, foreground=True):
            raise ValueError('Direct tag selection, Apply or foreground evidence absent')
        expected = _expected(category, prepared['customId'])
        defaults = _one(logs['client1'], 'DEFAULTS')
        if (set(defaults) != {'tag', 'item', 'role', 'menuClasses'} or defaults['tag'] != 'edible'
                or defaults['item'] != 'Base.Hammer' or defaults['role'] != 'client1'
                or type(defaults['menuClasses']) is not int or defaults['menuClasses'] < 2):
            raise ValueError('Tag/item defaults or native/CleanUI menu routes absent')
        if _records(logs['client1'], 'SAVE') != [{'count': 1, 'role': 'client1'}]:
            raise ValueError('Expected exactly one unified Save callback')
        for actor, event, text in [('client1', 'LOCAL', logs['client1']), ('authority', 'AUTHORITY', authority)]:
            receipts[actor] = _one(text, event)
            if not _exact(receipts[actor], expected):
                raise ValueError(actor + ' complete config/rule/appearance/revision differs')
        if selection['kind'] == 'mp':
            receipts['client2'] = _one(logs['client2'], 'OBSERVER')
            if not _exact(receipts['client2'], expected):
                raise ValueError('Observer global BC appearance or routing differs')
        for role, text in logs.items():
            names = (['empty', 'search', 'no-results', 'checked', 'items', 'presets', 'rule', 'color', 'tag-checked', 'tag-scroll', 'tag-dropdown',
                      'icon', 'tags', 'custom-tags', 'rules', 'edit', 'minimum'] if role == 'client1' else ['observer'])
            dimensions = {'empty': (480, 700), 'search': (480, 700), 'no-results': (480, 700),
                          'checked': (480, 700), 'items': (480, 700), 'presets': (480, 700),
                          'rule': (480, 700), 'color': (480, 700),
                          'tag-checked': (480, 700), 'tag-scroll': (480, 700), 'tag-dropdown': (480, 700),
                          'icon': (480, 700), 'tags': (480, 700), 'custom-tags': (480, 700), 'rules': (480, 700),
                          'edit': (480, 700), 'minimum': (420, 600), 'observer': (480, 700)}
            expected_shots = [{'name': name, 'role': role, 'width': dimensions[name][0],
                               'height': dimensions[name][1]} for name in names]
            if _records(text, 'SHOT') != expected_shots:
                raise ValueError(role + ' screenshots missing, duplicated or reordered')
            screenshots += [_shot(root, role, name) for name in names]
            if not complete(selection, role, text):
                raise ValueError(role + ' completion missing or duplicated')
        if any(MARKER + 'FAIL ' in text or '[QUEUE_TEST] FAIL ' in text for text in [authority, *logs.values()]):
            raise ValueError('Fixture failure marker present')
    except (OSError, ValueError, KeyError, TypeError) as error:
        issues.append(str(error))
    return {'issues': issues,
            'outcomes': [{'actor': role, 'case': 'edit', 'status': 'failed' if issues else 'passed',
                          'reason': '; '.join(issues)} for role in roles],
            'evidence': {'receipts': receipts, 'screenshots': screenshots, 'openingProfile': opening,
                         'scriptChoiceParity': parity,
                         'limits': ['Native callback-driven checks; no physical input claims.',
                                    'Screenshots require visual inspection; presence does not certify layout.',
                                    'Opening profiles measure Lua callbacks and UI frame intervals, not GPU presentation timestamps.']}}
