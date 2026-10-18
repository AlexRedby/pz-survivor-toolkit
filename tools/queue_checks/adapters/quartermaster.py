"""Native Quartermaster preset persistence and designated-container transfers."""
import os
from pathlib import Path
import re
import shutil

from .. import report


SUITE = 'quartermaster-presets'
TRANSFER_SUITE = 'quartermaster-transfers'
MODS = ['PZSurvivorToolkit', 'Quartermaster', 'organizedCategories_core']
STORES = ('PZSTQuartermasterPresets_a.txt', 'PZSTQuartermasterPresets_b.txt')
LEGACY_STORES = ('QuartermasterPresets.txt', 'PZSTQuartermasterTagRules.txt')
MARKER = '[QM_PRESET] '
TRANSFER_MARKER = '[QM_TRANSFER] '


def definitions():
    return {suite: {'status': 'ready', 'clients': 1, 'default_mods': MODS,
            'cases': [{'id': case, 'producer': 'fixture', 'capability': 'effect',
                       'kinds': ['sp'], 'languages': ['EN', 'RU'], 'modes': modes}
                      for case in cases]}
            for suite, cases, modes in ((SUITE, ('seed', 'reload'), ['toolkit']),
                                        (TRANSFER_SUITE, ('manifest',), ['toolkit', 'native']))}


def validate(selection):
    spec = definitions()[selection['suite']]
    if (len(selection.get('cases', [])) != 1 or selection['cases'][0] not in [case['id'] for case in spec['cases']]
            or selection.get('kind') != 'sp' or selection.get('mode') not in spec['cases'][0]['modes']
            or type(selection.get('clients', 1)) is not int or selection.get('clients', 1) != 1
            or selection.get('languages') not in (['EN'], ['RU'])
            or not set(MODS) <= set(selection.get('mods', []))):
        raise ValueError('Quartermaster requires one supported SP case and one EN/RU client')
    options = selection.get('options', {})
    if options.get('world_template') or bool(options.get('seed_run')) != (selection['cases'] == ['reload']):
        raise ValueError('Quartermaster reload requires seed_run; both cases create a fresh world')


def _stores(cache):
    lua = Path(cache) / 'Lua'
    paths = [lua / name for name in STORES + LEGACY_STORES]
    if (any(path.is_symlink() for path in (Path(cache), lua, *paths))
            or any(path.exists() and not path.is_file() for path in paths)):
        raise ValueError('Quartermaster stores must be regular global store files')
    if not any((lua / name).is_file() for name in STORES):
        raise ValueError('Quartermaster seed must contain at least one snapshot store')
    return [path for path in paths if path.is_file()]


def _seed(selection):
    value = selection['options']['seed_run']
    if not isinstance(value, str):
        raise ValueError('Quartermaster seed_run must be an absolute owned run directory')
    root = Path(value)
    if not root.is_absolute() or root.is_symlink():
        raise ValueError('Quartermaster seed_run must be an absolute owned run directory')
    root = root.resolve()
    initial = report.read_json(root / 'selection.json')
    runtime = report.read_json(root / 'runtime.json')
    if (initial.get('suite') != SUITE or initial.get('cases') != ['seed'] or initial.get('kind') != 'sp'
            or initial.get('mods') != selection['mods'] or initial.get('languages') != selection['languages']
            or Path(runtime['roles']['client1']['cache']) != root / 'client1'):
        raise ValueError('Quartermaster seed must have matching mods/language and its own SP cache')
    fresh = report.build_report(root, {'suites': definitions()})
    if fresh['status'] != 'passed' or fresh['runtime']['status'] != 'clean':
        raise ValueError('Quartermaster seed needs fresh successful assertions, provenance and clean logs')
    process = fresh['execution']['processes']['client1']
    if type(process.get('exit_code')) is not int or type(process.get('pid')) is not int or process['pid'] <= 0:
        raise ValueError('Quartermaster seed process was not stopped')
    try:
        os.kill(process['pid'], 0)
    except ProcessLookupError:
        pass
    else:
        raise ValueError('Quartermaster seed process is still alive')
    return root, _stores(root / 'client1')


def sources(project, selection):
    paths = sorted((Path(project) / 'tests/native_queue' / selection['suite']).rglob('*.lua'))
    paths.append(Path(project) / 'tests/native_queue/startup/client/ZZStartup.lua')
    if selection['cases'] == ['reload']:
        seed, stores = _seed(selection)
        paths += stores + [seed / name for name in ('selection.json', 'runtime.json', 'execution.json', 'manifest.json',
                            'source-manifest.json', 'snapshot-hashes.json', 'client1-launch.log')]
    return paths


def stage(project, output, game, jdk, selection, locations, runtime):
    from ..native import hashes
    validate(selection)
    cache = Path(runtime['roles']['client1']['cache'])
    client = cache / 'mods/ActionQueueTest/42/media/lua/client'
    shutil.copy2(Path(project) / 'tests/native_queue/startup/client/ZZStartup.lua', client / 'ZZStartup.lua')
    marker = TRANSFER_MARKER if selection['suite'] == TRANSFER_SUITE else MARKER
    runtime.setdefault('fixture', {})['failure_markers'] = [marker + 'FAIL ']
    if selection['cases'] == ['reload']:
        seed, stores = _seed(selection)
        if Path(report.read_json(seed / 'runtime.json')['game']) != Path(game):
            raise ValueError('Quartermaster seed uses a different game')
        before = {row['id']: row['files'] for row in report.read_json(seed / 'manifest.json')}
        if before != {identifier: hashes(Path(path)) for identifier, path in locations.items()}:
            raise ValueError('Quartermaster seed uses different mod contents')
        for source in stores:
            shutil.copyfile(source, cache / 'Lua' / source.name)


def complete(selection, role, text):
    marker = TRANSFER_MARKER if selection['suite'] == TRANSFER_SUITE else MARKER
    return role == 'client1' and len(re.findall(re.escape(marker) + 'COMPLETE case='
            + selection['cases'][0] + r'(?:\s|$)', text)) == 1


def verify(root, selection, catalog):
    if selection['suite'] == TRANSFER_SUITE:
        return _verify_transfers(Path(root), selection)
    root = Path(root)
    issues, generations, revisions, creators, stores = [], [], [], [], []
    try:
        text = (root / 'client1-launch.log').read_text(errors='replace')
        case = selection['cases'][0]
        if not complete(selection, 'client1', text) or MARKER + 'FAIL ' in text:
            raise ValueError('Missing successful Quartermaster preset completion')
        pattern = (re.escape(MARKER) + r'RULE index=([12]) gen=(\S+) rev=(\d+) '
                   r'creator=(nil|s(?:[0-9a-f]{4})*) mode=(all|any) resolved=true')
        matches = re.findall(pattern, text)
        if (len(matches) != 2 or [(index, mode) for index, _, _, _, mode in matches] != [('1', 'all'), ('2', 'any')]
                or any(revision != '2' for _, _, revision, _, _ in matches)):
            raise ValueError('Missing ordered native preset generation/rule/resolver assertions')
        generations = [generation for _, generation, _, _, _ in matches]
        revisions = [revision for _, _, revision, _, _ in matches]
        creators = [creator for _, _, _, creator, _ in matches]
        stores = _stores(root / 'client1')
        if case == 'reload':
            seed, previous_stores = _seed(selection)
            previous = (seed / 'client1-launch.log').read_text(errors='replace')
            if re.findall(pattern, previous) != matches:
                raise ValueError('Reload changed preset generations, revisions or creators')
            if ([path.name for path in previous_stores] != [path.name for path in stores]
                    or any(source.read_bytes() != (root / 'client1/Lua' / source.name).read_bytes()
                           for source in previous_stores)):
                raise ValueError('Reload changed the persisted global store files')
    except (OSError, ValueError, KeyError) as error:
        issues.append(str(error))
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': selection['cases'][0],
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues)}],
            'evidence': {'generations': generations, 'revisions': revisions, 'creators': creators,
                         'stores': [path.name for path in stores],
                         'limits': ['SP global stores in a fresh world; no Host or physical UI input coverage.']}}


def _verify_transfers(root, selection):
    issues = []
    try:
        text = (root / 'client1-launch.log').read_text(errors='replace')
        expected = ['PHASE success moved=2 remaining=0 tailRead=true dirty=true',
                    'PHASE partial moved=1 remaining=1 tailRead=true dirty=true',
                    'PHASE rejected moved=0 remaining=2 tailRead=false dirty=false',
                    'PHASE withdraw moved=1 remaining=1 tailRead=true dirty=true',
                    'CUSTOM protected=3 queueUnchanged=true', 'COMPLETE case=manifest']
        if re.findall(re.escape(TRANSFER_MARKER) + r'([^\r\n]+)', text) != expected:
            raise ValueError('Missing, duplicate, reordered or incorrect native transfer outcomes')
    except (OSError, ValueError) as error:
        issues.append(str(error))
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': 'manifest',
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues)}],
            'evidence': {'limits': ['SP only; programmatic UI callbacks and native actions, no physical input or Host.']}}
