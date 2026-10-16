"""Run isolated two-client tag checks using the shared native process guard."""
import argparse
import io
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
    parser.add_argument('--port', type=int, default=17493)
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    output = args.output.resolve()
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
    identifiers = INTEGRATION
    if args.selected:
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
    cases = BASELINE if args.baseline else CASES
    selection = dict(schema_version=1, suite='tags', kind='mp', mode='toolkit', cases=cases,
                     mods=identifiers, languages=['EN', 'RU'], ports=[args.port, args.port + 1],
                     timeout_seconds=600, expected_checks=len(cases) + 2,
                     tagRules=not args.baseline, textureNames=textures, placementBarrier=True, reconnectEvidence=True)
    prepared = prepare(source, output / 'run', args.game, args.jdk, selection)
    (output / 'candidate.json').write_text(json.dumps({'source_ref': args.source_ref or 'working-tree',
         'fixture': str(HERE), 'baseline': args.baseline, 'mods': len(identifiers)}, indent=2) + '\n')
    print('PREPARED ' + str(prepared), flush=True)
    if args.prepare_only:
        return
    execution = run(prepared)
    if execution['status'] != 'completed':
        raise RuntimeError(execution)
    verify(output)


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
        validate_receipts(receipts, role, phases)
        if selection.get('reconnectEvidence'):
            assert text.count('[QUEUE_TEST] NATIVE_CONNECTED ' + role) == 2, 'Not two actual client connections'
            for phase in ('disconnect', 'connected', 'verified'):
                assert '[TAG_RECONNECT] actor=' + role + ' phase=' + phase in text, (role, phase)
            validate_reconnect_receipts(receipts, role, phases[-1])
        screenshots = list((prepared / role / 'Screenshots').glob('tag-*.png'))
        assert len(screenshots) >= (1 if baseline else 6), (role, screenshots)
    provenance = verify_manifest(prepared, 'source-manifest.json', True) + verify_manifest(prepared, 'snapshot-hashes.json')
    assert not provenance, provenance
    audits = audit_logs(prepared, ['server', 'client1', 'client2'])
    assert not any(value['microphone'] for value in audits.values()), 'Microphone capture detected'
    result = dict(functional='passed', cases_per_client=len(cases), receipts=receipts,
                  runtime=audits, provenance_verified=True,
                  runtime_needs_review=any(value['error_count'] for value in audits.values()))
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print('FUNCTIONAL_PASS; see result.json for independent runtime audit', flush=True)


if __name__ == '__main__':
    main()
