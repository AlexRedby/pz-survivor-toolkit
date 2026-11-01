"""Two real Host peers exercise shared storage with hidden inventory presentation."""
from pathlib import Path
import shutil

from .. import receipts

SUITE = 'warehouse-workload'
MARKER = '[WAREHOUSE_WORKLOAD] '
MODS = ['NeatUI_Framework', 'CleanUI', 'PZSurvivorToolkit', 'EURY_CONTAINERS']


def definitions():
    return {SUITE: {'status': 'ready', 'clients': 2, 'default_mods': MODS,
                   'window_size': [1280, 900],
                   'cases': [{'id': name, 'producer': 'fixture', 'capability': 'effect',
                              'kinds': ['mp'], 'languages': ['EN', 'RU'], 'modes': ['toolkit']}
                             for name in ('peer-edits', 'hidden-affinity', 'physical-affinity')],
                   'limits': ['Sparse functional checks with two actual menu-Host clients.',
                              'Installed UI callbacks; no physical-input, dense walking, performance or WAN claim.']}}


def validate(selection):
    options = selection.get('options', {})
    if (selection.get('cases') not in (['peer-edits'], ['hidden-affinity'], ['physical-affinity']) or selection.get('kind') != 'mp'
            or selection.get('mode') != 'toolkit' or type(selection.get('clients')) is not int
            or selection['clients'] != 2 or selection.get('languages') != ['EN', 'RU']
            or not isinstance(options, dict) or options.get('mp_host') is not True
            or any(options.get(key) for key in ('world_template', 'seed_run', 'startup_connection', 'inventory_work_renderer'))
            or not set(MODS) <= set(selection.get('mods', []))):
        raise ValueError('Warehouse workload requires fresh two-client EN/RU menu Host, one declared case and installed Toolkit/CleanUI/BC')
    forbidden = {'ContainerCapacityIndicator', 'BravoItemDetails', 'Quartermaster', 'HasResearch', 'SeedSeasonIndicator'}
    if forbidden & set(selection['mods']):
        raise ValueError('External inventory owners are unsupported by warehouse workload')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    paths = [*sorted((root / SUITE).rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
             root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueFixtureItemCleanup.lua', Path(__file__).with_name('warehouse_workload_verify.py')]
    if selection['cases'] in (['hidden-affinity'], ['physical-affinity']):
        paths.append(Path(__file__).with_name('warehouse_affinity_verify.py'))
    return paths


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for source, side in [(root / 'startup/client/ZZStartup.lua', 'client'),
                             (root / 'startup/server/ZZStartupServer.lua', 'server'),
                             (root / 'health/shared/QueueHealthEvents.lua', 'shared'),
                             (root / 'support/QueueFixtureItemCleanup.lua', 'shared')]:
            (lua / side).mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, lua / side / source.name)
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=[MARKER + 'FAIL '], client_launch_stagger_seconds=8, sandbox={'Zombies': 6})


def complete(selection, role, text):
    try:
        rows = receipts.records(text, MARKER, 'COMPLETE')
        return (role in ('client1', 'client2') and len(rows) == 1
                and all(type(rows[0].get(key)) is type(value) and rows[0][key] == value
                        for key, value in dict(suite=SUITE, case=selection['cases'][0], kind='mp', mode='toolkit',
                                               role=role, phases=4 if selection['cases'] == ['physical-affinity'] else 2, restored=True).items())
                and MARKER + 'FAIL ' not in text)
    except (ValueError, TypeError):
        return False


def verify(root, selection, catalog):
    if selection.get('cases') in (['hidden-affinity'], ['physical-affinity']):
        from . import warehouse_affinity_verify as verifier
    else:
        from . import warehouse_workload_verify as verifier
    try:
        validate(selection)
        evidence = (verifier.verify(root, case=selection['cases'][0])
                    if selection['cases'] in (['hidden-affinity'], ['physical-affinity']) else verifier.verify(root))
        issues = []
    except (ValueError, KeyError, TypeError, IndexError, OSError) as error:
        issues, evidence = [str(error)], {}
    return {'issues': issues, 'evidence': evidence,
            'outcomes': [{'actor': role, 'case': selection['cases'][0], 'status': 'failed' if issues else 'passed'}
                         for role in ('client1', 'client2')]}
