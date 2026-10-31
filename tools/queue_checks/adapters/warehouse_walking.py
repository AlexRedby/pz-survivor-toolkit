"""Matched SP and two-client Host captures, separate from sparse peer actions."""
from pathlib import Path
import shutil

from .. import receipts

SUITE = 'warehouse-walking'
MARKER = '[WAREHOUSE_WALKING] '
MODS = ['ZombieBuddy', 'PZToolkitJavaPatches', 'NeatUI_Framework', 'CleanUI',
        'PZSurvivorToolkit', 'EURY_CONTAINERS']


def definitions():
    return {SUITE: {'status': 'ready', 'clients': 2, 'default_mods': MODS,
                   'window_size': [1280, 900],
                   'cases': [{'id': 'walk', 'producer': 'fixture', 'capability': 'capture',
                              'kinds': ['sp', 'mp'], 'languages': ['EN', 'RU'], 'modes': ['toolkit']}],
                   'limits': ['Exclusive fresh-world timing captures with the complete locked pack.',
                              'Instrumented Lua timings include observer overhead; no FPS, WAN or user-save claim.']}}


def validate(selection):
    options = selection.get('options', {})
    kind = selection.get('kind')
    clients = 1 if kind == 'sp' else 2
    languages = ['EN'] if kind == 'sp' else ['EN', 'RU']
    if (selection.get('cases') != ['walk'] or kind not in ('sp', 'mp')
            or selection.get('mode') != 'toolkit' or type(selection.get('clients')) is not int
            or selection['clients'] != clients or selection.get('languages') != languages
            or not isinstance(options, dict)
            or (kind == 'mp' and options.get('mp_host') is not True)
            or (kind == 'sp' and options.get('mp_host'))
            or not set(MODS) <= set(selection.get('mods', []))
            or any(options.get(key) for key in ('world_template', 'seed_run', 'startup_connection',
                                               'inventory_work_renderer', 'video'))):
        raise ValueError('Warehouse walking requires fresh EN SP or two-client EN/RU menu Host with Toolkit/CleanUI/BC')
    if selection.get('resources', {}).get('exclusive') is not True or not options.get('pack_lock'):
        raise ValueError('Warehouse walking requires exclusive admission and a complete source pack lock')
    forbidden = {'ContainerCapacityIndicator', 'BravoItemDetails', 'Quartermaster', 'HasResearch', 'SeedSeasonIndicator'}
    if forbidden & set(selection['mods']):
        raise ValueError('External inventory owners are unsupported by warehouse walking')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / SUITE).rglob('*.lua')), *sorted((root / SUITE / 'java').glob('*.java')),
            *sorted((root / 'startup').rglob('*.lua')),
            root / 'warehouse-workload/client/WarehouseWorkloadUI.lua',
            root / 'health/shared/QueueHealthEvents.lua',
            Path(__file__).with_name('warehouse_workload_verify.py'),
            Path(__file__).with_name('warehouse_walking_verify.py'),
            Path(__file__).with_name('warehouse_walking_profile.py')]


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for source, side in [(root / 'startup/client/ZZStartup.lua', 'client'),
                             (root / 'startup/server/ZZStartupServer.lua', 'server'),
                             (root / 'warehouse-workload/client/WarehouseWorkloadUI.lua', 'client'),
                             (root / 'health/shared/QueueHealthEvents.lua', 'shared')]:
            if selection['kind'] == 'sp' and source.name == 'ZZStartup.lua':
                continue
            (lua / side).mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, lua / side / source.name)
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=[MARKER + 'FAIL '], client_launch_stagger_seconds=8,
        sandbox={'Zombies': 6, 'EnableVehicles': False, 'StartMonth': 7, 'StartDay': 9, 'StartTime': 2})
    from . import warehouse_walking_profile
    warehouse_walking_profile.stage(project, output, game, jdk, selection, locations, runtime)


def complete(selection, role, text):
    try:
        rows = [row for row in receipts.records(text, MARKER, 'COMPLETE') if row.get('role') == role]
        return (role in ('client1', 'client2') and len(rows) == 1
                and all(type(rows[0].get(key)) is type(value) and rows[0][key] == value
                        for key, value in dict(suite=SUITE, case='walk', kind=selection['kind'], mode='toolkit',
                                               role=role, phases=16, restored=True).items())
                and MARKER + 'FAIL ' not in text)
    except (ValueError, TypeError):
        return False


def verify(root, selection, catalog):
    from . import warehouse_walking_verify
    try:
        validate(selection)
        evidence = warehouse_walking_verify.verify(root, selection)
        issues = []
    except (ValueError, KeyError, TypeError, IndexError, OSError) as error:
        issues, evidence = [str(error)], {}
    roles = ['client1'] if selection['kind'] == 'sp' else ['client1', 'client2']
    return {'issues': issues, 'evidence': evidence,
            'outcomes': [{'actor': role, 'case': 'walk', 'status': 'failed' if issues else 'captured'}
                         for role in roles]}
