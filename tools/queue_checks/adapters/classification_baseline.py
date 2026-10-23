"""Inventory-classification parity against a reviewed OC baseline, in one disposable SP client."""
from pathlib import Path
import shutil
import re
from .. import receipts

SUITE = 'classification-baseline'
MARKER = '[CLASSIFICATION_BASELINE] '
PROJECT = Path(__file__).resolve().parents[3]
MODS = re.search(r'^Mods=(.*)$', (PROJECT / 'SurvivorQoL-selected.ini').read_text(), re.M)[1].split(';')
if 'organizedCategories_core' not in MODS:
    MODS.append('organizedCategories_core')


def definitions():
    return {SUITE: {'status': 'ready', 'native_validation': 'not-run', 'clients': 1,
                    'default_mods': MODS,
                    'cases': [{'id': 'parity', 'producer': 'fixture', 'capability': 'effect',
                               'kinds': ['sp'], 'languages': ['EN'], 'modes': ['toolkit']}],
                    'limits': ['OC is loaded only as a reference in this baseline; candidate Host checks must exclude it.']}}


def validate(selection):
    options = selection.get('options', {})
    if (selection.get('cases') != ['parity'] or selection.get('kind') != 'sp'
            or selection.get('mode') != 'toolkit' or selection.get('clients') != 1
            or selection.get('languages') != ['EN']
            or not set(MODS) <= set(selection.get('mods', []))
            or any(options.get(key) for key in ('world_template', 'seed_run', 'startup_connection', 'mp_host'))):
        raise ValueError('Classification baseline requires fresh one-client EN SP Toolkit with selected pack plus reviewed OC')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / SUITE).rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        target = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for source, side in [(root / 'startup/client/ZZStartup.lua', 'client'),
                             (root / 'startup/server/ZZStartupServer.lua', 'server'),
                             (root / 'health/shared/QueueHealthEvents.lua', 'shared')]:
            (target / side).mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target / side / source.name)
    runtime.setdefault('fixture', {}).update(failure_markers=[MARKER + 'FAIL '], sandbox={'Zombies': 6})


def complete(selection, role, text):
    try:
        return receipts.records(text, MARKER, 'COMPLETE') == [{'case': 'parity', 'role': role}]
    except ValueError:
        return False


def verify(root, selection, catalog):
    issues, evidence = [], {}
    try:
        text = (Path(root) / 'client1-launch.log').read_text(errors='replace')
        rows = receipts.records(text, MARKER, 'VERIFIED')
        if len(rows) != 1:
            raise ValueError('Missing/duplicate classification parity receipt')
        row = rows[0]
        keys = {'scripts', 'instances', 'mediaKinds', 'differences', 'scriptCategoriesUnchanged', 'legacyOverride', 'role'}
        if (set(row) != keys or any(type(row[key]) is not int for key in ('scripts', 'instances', 'mediaKinds', 'differences'))
                or row['scripts'] < 5000 or row['instances'] < 9 or row['mediaKinds'] < 1
                or row['scriptCategoriesUnchanged'] is not True or row['legacyOverride'] is not True
                or row['role'] != 'client1'):
            raise ValueError('Incomplete native classification/catalog/fluid/media evidence')
        differences = receipts.records(text, MARKER, 'DIFF')
        evidence = {'summary': row, 'differences': differences}
        if row['differences'] != len(differences) or differences:
            raise ValueError('Classification differs from reviewed OC reference: ' + str(row['differences']) + ' items')
        if MARKER + 'FAIL ' in text or not complete(selection, 'client1', text):
            raise ValueError('Classification fixture failed or did not complete')
    except (OSError, ValueError, KeyError, TypeError) as error:
        issues.append(str(error))
    return {'issues': issues,
            'outcomes': [{'actor': 'client1', 'case': 'parity', 'status': 'failed' if issues else 'passed',
                          'reason': '; '.join(issues)}], 'evidence': evidence}
