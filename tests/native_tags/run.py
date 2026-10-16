"""Run isolated two-client tag checks using the shared native process guard."""
import argparse
import io
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BASELINE = ['configure', 'reopen', 'sort', 'baseline-reconnect']
CASES = ['configure', 'reopen', 'icons', 'inventory-all', 'inventory-any', 'inventory-exclude',
         'preset-save', 'inventory-empty', 'preset-apply', 'rule-save', 'rule-reopen', 'rule-stale',
         'rule-peer', 'rule-toggle', 'sort', 'rule-reconnect']
INTEGRATION = ['NeatUI_Framework', 'CleanUI', 'PZSurvivorToolkit', 'EURY_CONTAINERS',
               'Quartermaster', 'BravoItemDetails', 'organizedCategories_core']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path, help='Fresh output directory; never reused')
    parser.add_argument('--game', type=Path, required=True, help='Directory containing projectzomboid.jar')
    parser.add_argument('--jdk', type=Path, required=True)
    parser.add_argument('--workshop', type=Path, action='append', required=True,
                        help='Explicit mod roots, in preference order (first matching root wins)')
    parser.add_argument('--source-ref', help='Use committed product bytes; fixture stays current')
    parser.add_argument('--baseline', action='store_true', help='Check old selection/sort and actual reconnect')
    parser.add_argument('--selected', action='store_true', help='Use all Mods from the selected INI')
    restart = parser.add_mutually_exclusive_group()
    restart.add_argument('--restart-seed', action='store_true', help='Retain and seal the completed 16-case world')
    restart.add_argument('--restart-from', type=Path, help='Reload a completed sealed restart seed')
    parser.add_argument('--port', type=int)
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    if args.baseline and (args.restart_seed or args.restart_from):
        parser.error('Restart checks require candidate tag rules')
    seed = validate_seed(args.restart_from) if args.restart_from else None
    port = args.port if args.port is not None else (seed['selection']['ports'][0] if seed else 17493)
    output = args.output.resolve()
    if seed:
        assert not output.is_relative_to(seed['output'].resolve()), 'Restart output must be outside seed'
    protected = [args.game, args.jdk, *args.workshop, ROOT / 'PZSurvivorToolkit',
                 ROOT / 'PZSurvivorWishlist', ROOT / 'tools', ROOT / 'tests']
    if any(output.is_relative_to(path.resolve()) for path in protected):
        raise ValueError('Output must be outside game, JDK, mod sources and test sources')
    output.mkdir(parents=True, exist_ok=False)
    source = output / 'source'
    source.mkdir()
    parts = ['PZSurvivorToolkit', 'PZSurvivorWishlist', 'tools', 'tests/native_queue']
    if args.source_ref:
        archive = subprocess.check_output(['git', 'archive', '--format=tar', args.source_ref, *parts,
                                           'SurvivorQoL-selected.ini'], cwd=ROOT)
        with tarfile.open(fileobj=io.BytesIO(archive)) as files:
            files.extractall(source, filter='data')
    else:
        for name in parts:
            shutil.copytree(ROOT / name, source / name, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        shutil.copy2(ROOT / 'SurvivorQoL-selected.ini', source)
    shutil.copytree(HERE, source / 'tests/native_queue/tags', ignore=shutil.ignore_patterns('__pycache__'))
    sys.path.insert(0, str(source / 'tools'))
    from queue_checks.native import prepare, _matching_roots
    from queue_checks.runner import run
    identifiers = seed['selection']['mods'] if seed else INTEGRATION
    if args.selected and not seed:
        line = next(line for line in (source / 'SurvivorQoL-selected.ini').read_text().splitlines()
                    if line.startswith('Mods='))
        identifiers = line[5:].split(';')
    for identifier in identifiers:
        if identifier in ('PZSurvivorToolkit', 'PZSurvivorWishlist'):
            continue
        if identifier == 'PZToolkitJavaPatches':
            candidate = ROOT / 'JavaPatches/build/PZToolkitJavaPatches'
            if not candidate.is_dir():
                raise ValueError('Build JavaPatches with tools/prepare_install.py before selected tests')
        else:
            found = set()
            for workshop in args.workshop:
                found = _matching_roots(workshop.rglob('mod.info'), identifier)
                if found:
                    break
            if len(found) != 1:
                raise ValueError('Expected one explicit mod source for ' + identifier + ': ' + str(found))
            candidate = next(iter(found))
        shutil.copytree(candidate, source / identifier)
    # B42 looks for these asset directories even in empty common layers.
    for identifier in identifiers:
        mod = source / identifier
        versions = [p for p in mod.iterdir() if p.is_dir() and re.fullmatch(r'42(?:[.][0-9]+)*', p.name)]
        # Common-only B42 mods still make the engine scan its 42.0 fallback.
        fallback = [mod / '42.0'] if (mod / 'common/mod.info').is_file() else []
        layers = [mod / 'common', *(versions or fallback)]
        for layer in layers:
            for name in ('AnimSets', 'actiongroups'):
                (layer / 'media' / name).mkdir(parents=True, exist_ok=True)
    visuals = (source / 'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/TagVisuals.lua').read_text()
    textures = sorted(set(re.findall(r'"((?:Item_|media/ui/)[^"]+)"', visuals)))
    cases = ['server-restart', 'restart-sort'] if seed else (BASELINE if args.baseline else CASES)
    selection = dict(schema_version=1, suite='tags', kind='mp', mode='toolkit', cases=cases,
                     mods=identifiers, languages=['EN', 'RU'], ports=[port, port + 1],
                     timeout_seconds=600, expected_checks=len(cases) + 2,
                     tagRules=not args.baseline, textureNames=textures, placementBarrier=True, reconnectEvidence=True)
    if args.restart_seed:
        selection['tagRestartSeed'] = True
    if seed:
        selection.update(tagRestart=seed['states'], placementBarrier=False, reconnectEvidence=False)
        assert selection['ports'] == seed['selection']['ports'], 'Restart endpoints changed'
    prepared = prepare(source, output / 'run', args.game, args.jdk, selection)
    if seed:
        restore_seed(seed, prepared)
    (output / 'candidate.json').write_text(json.dumps({'source_ref': args.source_ref or 'working-tree',
         'fixture': str(HERE), 'baseline': args.baseline, 'mods': len(identifiers)}, indent=2) + '\n')
    print('PREPARED ' + str(prepared), flush=True)
    if args.prepare_only:
        return
    execution = run(prepared)
    if execution['status'] != 'completed':
        raise RuntimeError(execution)
    verify(output)


ROLES = ('server', 'client1', 'client2')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def no_symlinks(root):
    root = Path(root)
    assert not any(path.is_symlink() for path in (root, *root.parents, *root.rglob('*'))), 'Symlink in restart seed'


def rows(text, marker):
    return [json.loads(line.split(marker, 1)[1]) for line in text.splitlines() if marker in line]


def persisted_files(run):
    files = {}
    for role in ROLES:
        for directory in ('Saves', 'db', 'Server'):
            path = run / role / directory
            if directory != 'Server' or role == 'server':
                assert path.is_dir() and any(p.is_file() for p in path.rglob('*')), 'Missing persisted ' + role + '/' + directory
            files.update({p.relative_to(run).as_posix(): digest(p) for p in path.rglob('*') if p.is_file()})
        presets = sorted((run / role / 'Lua').glob('PZSurvivorToolkit_TagFilters_*.txt'))
        if role != 'server':
            assert presets, 'Missing retained client tag filter preset'
        files.update({p.relative_to(run).as_posix(): digest(p) for p in presets})
    return files


def seed_states(text):
    snapshots = rows(text, '[TAG_RESTART_SEED] ')
    assert len(snapshots) == 2 and {row['actor'] for row in snapshots} == {'client1', 'client2'}, 'Missing or repeated actor seed'
    states = {row['actor']: row for row in snapshots}
    for actor, row in states.items():
        setup = row['setup']
        assert setup['owner'] == actor, 'Seed setup owner differs'
        assert all(key in setup for key in ('x', 'y', 'z', 'index', 'owner', 'battery', 'apple', 'beans', 'steak', 'source', 'revision', 'manualCategory'))
        assert len({str(setup[key]) for key in ('battery', 'apple', 'beans', 'steak')}) == 4
        assert all(key in row['start'] for key in ('x', 'y', 'z'))
        assert isinstance(row['original'], list) and all('id' in item and 'count' in item for item in row['original'])
        assert all(key in row['manual'] for key in ('priority', 'LSBox', 'LSBoxItems', 'LSBoxPresets'))
    return states


def validate_saved_endpoint(run, selection, runtime):
    name = runtime['server_name']
    assert re.fullmatch(r'[A-Za-z0-9_.-]+', name), 'Invalid saved server name'
    path = run / 'server/Server' / (name + '.ini')
    values = dict(line.split('=', 1) for line in path.read_text().splitlines() if '=' in line)
    assert [int(values['DefaultPort']), int(values['UDPPort'])] == selection['ports'], 'Saved server endpoints changed'
    assert values['Mods'].split(';') == [*selection['mods'], 'ActionQueueTest'], 'Saved server mod IDs changed'


def completed_execution(run):
    execution = json.loads((run / 'execution.json').read_text())
    assert execution['status'] == 'completed' and not execution.get('cleanup_errors'), 'Seed execution incomplete'
    assert set(execution['processes']) == set(ROLES)
    assert all(type(row.get('exit_code')) is int for row in execution['processes'].values()), 'Seed role still running'
    text = (run / 'server-launch.log').read_text(errors='replace')
    assert 'Saving finish' in text and re.search(r'Shutdown(?: handling)?\s+finished', text, re.I), 'Seed server did not save and shut down'
    return text


def seal_seed(output):
    run = output / 'run'
    no_symlinks(run)
    text = completed_execution(run)
    states = seed_states(text)
    evidence = {name: digest(run / name) for name in ('execution.json', 'server-launch.log', 'client1-launch.log', 'client2-launch.log')}
    record = dict(kind='seed', files=persisted_files(run), states=states, evidence=evidence, result_sha256=digest(output / 'result.json'))
    write_json(run / 'restart-inputs.json', record)
    frozen = json.loads((run / 'snapshot-hashes.json').read_text())
    frozen['restart-inputs.json'] = digest(run / 'restart-inputs.json')
    write_json(run / 'snapshot-hashes.json', frozen)


def validate_seed(output):
    output = Path(output).absolute()
    assert not output.is_symlink(), 'Symlink in restart seed'
    output = output.resolve()
    no_symlinks(output)
    run = output / 'run'
    selection = json.loads((run / 'selection.json').read_text())
    assert selection.get('tagRestartSeed') and selection['cases'] == CASES and selection['tagRules'], 'Not a completed candidate restart seed'
    result = json.loads((output / 'result.json').read_text())
    assert result.get('functional') == 'passed' and result.get('cases_per_client') == 16 and result.get('provenance_verified') is True
    text = completed_execution(run)
    runtime = json.loads((run / 'runtime.json').read_text())
    validate_saved_endpoint(run, selection, runtime)
    record = json.loads((run / 'restart-inputs.json').read_text())
    assert record['kind'] == 'seed' and record['files'] == persisted_files(run), 'Persisted seed inputs changed'
    assert record['states'] == seed_states(text) and record['result_sha256'] == digest(output / 'result.json')
    assert all(digest(run / name) == value for name, value in record['evidence'].items()), 'Seed execution evidence changed'
    sys.path.insert(0, str(output / 'source/tools'))
    from queue_checks.report import verify_manifest
    errors = verify_manifest(run, 'source-manifest.json', True) + verify_manifest(run, 'snapshot-hashes.json')
    assert not errors, errors
    return dict(output=output, selection=selection, states=record['states'], files=record['files'],
                runtime=runtime)


def restore_seed(seed, prepared):
    run = seed['output'] / 'run'
    assert json.loads((prepared / 'selection.json').read_text())['ports'] == seed['selection']['ports'], 'Restart endpoints changed'
    runtime = json.loads((prepared / 'runtime.json').read_text())
    assert runtime['server_name'] == seed['runtime']['server_name'], 'Restart server name changed'
    before = json.loads((run / 'manifest.json').read_text())
    after = json.loads((prepared / 'manifest.json').read_text())
    assert {row['id']: row['files'] for row in before} == {row['id']: row['files'] for row in after}, 'Restart product/mod bytes changed'
    no_symlinks(run)
    assert persisted_files(run) == seed['files'], 'Seed changed before copy'
    for name, expected in seed['files'].items():
        source, target = run / name, prepared / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        assert digest(target) == expected, 'Persisted input changed during copy'
    write_json(prepared / 'restart-inputs.json', dict(kind='restart', seed=str(seed['output']), files=seed['files'], states=seed['states']))
    # Only prepared immutable inputs are resealed. Saved worlds/databases remain mutable runtime inputs.
    initial = json.loads((prepared / 'initial-settings.json').read_text())
    for role in ROLES:
        for path in (prepared / role / 'Server').glob('*'):
            if path.is_file():
                initial[path.relative_to(prepared).as_posix()] = path.read_text()
    write_json(prepared / 'initial-settings.json', initial)
    fingerprint = json.loads((prepared / 'settings-fingerprint.json').read_text())
    fingerprint['inputs']['settings'] = initial
    fingerprint['sha256'] = hashlib.sha256(json.dumps(fingerprint['inputs'], sort_keys=True).replace(str(prepared), '<run>').encode()).hexdigest()
    write_json(prepared / 'settings-fingerprint.json', fingerprint)
    frozen = json.loads((prepared / 'snapshot-hashes.json').read_text())
    for name in seed['files']:
        if '/Lua/' in name:
            frozen[name] = digest(prepared / name)
    for name in ('restart-inputs.json', 'initial-settings.json', 'settings-fingerprint.json'):
        frozen[name] = digest(prepared / name)
    write_json(prepared / 'snapshot-hashes.json', frozen)


def consecutive_phases(records, expected):
    compact = []
    for row in records:
        if compact and row['phase'] == compact[-1]['phase']:
            assert row == compact[-1], 'Repeated restart phase evidence differs'
        else:
            compact.append(row)
    assert [row['phase'] for row in compact] == expected, 'Missing ordered restart evidence'
    return compact


def validate_restart_receipts(text, actor, state):
    receipts = rows(text, '[TAG_RECEIPT] ')
    selected = [row for row in receipts if row['actor'] == actor]
    selected = consecutive_phases(selected, ['enabled', 'disabled', 'enabled'])
    setup = state['setup']
    for row in selected:
        assert row['exact'] and row['originalInventoryUnchanged'] and row.get('reconnected') is True
        expected = {str(setup[key]): key for key in ('battery', 'apple', 'beans', 'steak')}
        assert set(row['ids']) == set(expected), 'Restart item IDs changed'
        for identity, key in expected.items():
            item = row['ids'][identity]
            destination = key == 'battery' or (key == 'apple' and row['phase'] == 'enabled')
            assert item['item'] == key and item['destination'] == int(destination) and item['source'] == int(not destination)
    rules = [row for row in rows(text, '[TAG_RESTART_VERIFIED] ') if row['actor'] == actor]
    rules = consecutive_phases(rules, ['restart-before', 'restart-after'])
    for row in rules:
        actual = row['setup']
        assert type(actual.get('index')) is int and actual['index'] >= 0, 'Invalid saved box object index'
        assert row['revision'] == setup['revision'] and {key: value for key, value in actual.items() if key != 'index'} == {key: value for key, value in setup.items() if key != 'index'}, 'Restart saved setup/revision changed'
        rule = row['rule']
        assert rule['mode'] == 'all' and sorted(rule['include']) == ['food', 'perishable'] and rule['exclude'] == ['meat'], 'Restart actual rule missing or changed'


def validate_receipts(receipts, actor, phases):
    for phase in phases:
        found = [row for row in receipts if row['actor'] == actor and row['phase'] == phase]
        assert found and all(row['exact'] and row['originalInventoryUnchanged'] for row in found)
        assert all(row['ids'] == found[0]['ids'] for row in found), 'Repeated authority receipts disagree'


def validate_placement_order(text):
    acknowledgements = {}
    created = set()
    for line in text.splitlines():
        if '[TAG_PLACEMENT_READY] ' in line:
            row = json.loads(line.split('[TAG_PLACEMENT_READY] ', 1)[1])
            acknowledgements[row['actor']] = row['signature']
        elif '[TAG_PLACEMENT] ' in line:
            assert set(acknowledgements) == {'client1', 'client2'}, 'Crate created before both client load acknowledgements'
            assert len(set(acknowledgements.values())) == 1, 'Client placement signatures disagree'
            row = json.loads(line.split('[TAG_PLACEMENT] ', 1)[1])
            assert row['actor'] not in created, 'Fixture crate created more than once'
            created.add(row['actor'])
    assert created == {'client1', 'client2'}, 'Missing native crate creation evidence'


def validate_reconnect_receipts(receipts, actor, phase):
    states = {row.get('reconnected') for row in receipts if row['actor'] == actor and row['phase'] == phase}
    assert states == {False, True}, 'Missing separate pre/post reconnect authority receipts'


def verify(output):
    output = Path(output)
    prepared = output / 'run'
    selection = json.loads((prepared / 'selection.json').read_text())
    baseline, cases = not selection['tagRules'], selection['cases']
    restart = selection.get('tagRestart')
    sys.path.insert(0, str(output / 'source/tools'))
    from queue_checks.report import audit_logs, events, verify_manifest
    receipts = []
    server_text = (prepared / 'server-launch.log').read_text(errors='replace')
    if selection.get('placementBarrier'):
        validate_placement_order(server_text)
    for line in server_text.splitlines():
        if '[TAG_RECEIPT] ' in line:
            receipts.append(json.loads(line.split('[TAG_RECEIPT] ', 1)[1]))
    for role in ('client1', 'client2'):
        text = (prepared / (role + '-launch.log')).read_text(errors='replace')
        records = events(text)
        assert [row['id'] for row in records if row['event'] == 'case'] == cases
        assert all(row.get('status') == 'passed' for row in records if row['event'] == 'case')
        assert len([row for row in records if row['event'] == 'setup']) == 1
        end = records[-1]
        assert end['event'] == 'complete' and end['performed'] == len(cases) and end['failed'] == 0
        for marker in ('VOICE_DISABLED', 'DISPLAY_READY', 'PREFLIGHT_COMPLETE', 'NATIVE_CONNECTED'):
            assert '[QUEUE_TEST] ' + marker in text, (role, marker)
        phases = ['baseline'] if baseline else ['disabled', 'enabled']
        if restart:
            assert text.count('[QUEUE_TEST] NATIVE_CONNECTED ' + role) == 1
            assert '[TAG_PLACEMENT' not in server_text
            for phase in ('verified', 'sorted'):
                assert '[TAG_RESTART] actor=' + role + ' phase=' + phase in text
            validate_restart_receipts(server_text, role, restart[role])
        else:
            validate_receipts(receipts, role, phases)
        if selection.get('reconnectEvidence'):
            assert text.count('[QUEUE_TEST] NATIVE_CONNECTED ' + role) == 2, 'Not two actual client connections'
            for phase in ('disconnect', 'connected', 'verified'):
                assert '[TAG_RECONNECT] actor=' + role + ' phase=' + phase in text, (role, phase)
            validate_reconnect_receipts(receipts, role, phases[-1])
        screenshots = list((prepared / role / 'Screenshots').glob('tag-*.png'))
        if not restart:
            assert len(screenshots) >= (1 if baseline else 6), (role, screenshots)
    provenance = verify_manifest(prepared, 'source-manifest.json', True) + verify_manifest(prepared, 'snapshot-hashes.json')
    assert not provenance, provenance
    audits = audit_logs(prepared, ['server', 'client1', 'client2'])
    assert not any(value['microphone'] for value in audits.values()), 'Microphone capture detected'
    result = dict(functional='passed', cases_per_client=len(cases), receipts=receipts,
                  runtime=audits, provenance_verified=True,
                  runtime_needs_review=any(value['error_count'] for value in audits.values()))
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    if selection.get('tagRestartSeed'):
        seal_seed(output)
    print('FUNCTIONAL_PASS; see result.json for independent runtime audit', flush=True)


if __name__ == '__main__':
    main()
