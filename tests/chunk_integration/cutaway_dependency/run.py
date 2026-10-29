#!/usr/bin/env python3
"""Inventory actual cutaway dependency writers in the exact native and official bytecode."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import zipfile

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location('dependency_project_build', HERE.parents[2] / 'JavaPatches/build.py')
build = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(build)
NATIVE = 'e1a69eb743ede60b213a0fe7f8b83d4fcab773036d256cc4543a336f3b058a33'
OFFICIAL = '2bcd0e01a3ac66856fae137ff1dbda66c8397375da781e7a6ed67fe2b9d6590d'


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('game', 'jdk', 'official-overlay', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    game, jdk, official, out = (getattr(args, name).resolve() for name in ('game', 'jdk', 'official_overlay', 'output'))
    if out.exists() or out == game or game in out.parents:
        parser.error('Output must be new and outside the installed game')
    native, buddy = game / 'projectzomboid.jar', game / 'ZombieBuddy.jar'
    for path, expected in ((native, NATIVE), (official, OFFICIAL)):
        if sha(path) != expected:
            parser.error('Unsupported archive: ' + path.name)
    if build.JVM_TARGET != '25':
        parser.error('Requalify inventory on the new project JVM target')
    version = subprocess.run([str(jdk / 'bin/java'), '-version'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, timeout=15)
    major = re.search(r'version "(\d+)', version.stdout)
    if version.returncode or major is None or int(major[1]) < int(build.JVM_TARGET):
        parser.error('JDK 25+ is required')
    out.mkdir(parents=True)
    for name in ('classes', 'source', 'work'):
        (out / name).mkdir()
    sources = (HERE / 'WriterInventory.java', HERE / 'NativeMutationChecks.java', HERE.parent / 'cutaway_cache/DirtyDependencyChecks.java', Path(__file__))
    for source in sources:
        (out / 'source' / source.name).write_bytes(source.read_bytes())
    cp = os.pathsep.join(map(str, (out / 'classes', native, buddy)))

    def run(command, label):
        result = subprocess.run(list(map(str, command)), cwd=out / 'work', stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, timeout=60)
        (out / (label + '.log')).write_text(result.stdout)
        if result.returncode:
            raise RuntimeError(label + ': ' + result.stdout[-5000:])
        return result.stdout

    run([jdk / 'bin/javac', '--release', build.JVM_TARGET, '-cp', cp, '-d', out / 'classes',
         HERE / 'WriterInventory.java'], 'compile')
    inventories = {}
    for label, archive in (('native', native), ('official', official)):
        log = run([jdk / 'bin/java', '-Xmx256m', '-cp', cp, 'WriterInventory', archive], label)
        lines = log.splitlines()
        if not lines or not lines[-1].startswith('INVENTORY_CLASSES='):
            raise RuntimeError('Incomplete inventory: ' + label)
        rows = [dict(zip(('class', 'method', 'event', 'class_sha256'), line.split('\t'), strict=True))
                for line in lines[:-1]]
        inventories[label] = dict(summary=lines[-1], events=rows)
    for label, expected_count, expected_names in (
            ('native', 4, {'<init>', 'getNew', 'ReCalculateVisionBlocked'}),
            ('official', 6, {'<init>', 'getNew', 'ReCalculateVisionBlocked', 'pzoptHrRestore'})):
        writes = [row for row in inventories[label]['events']
                  if row['event'] == 'PUTFIELD zombie/iso/IsoGridSquare.visionMatrix I']
        if (len(writes) != expected_count or {row['method'].split('(')[0] for row in writes} != expected_names
                or any(row['class'] != 'zombie/iso/IsoGridSquare' for row in writes)):
            raise RuntimeError('Pinned direct vision writer inventory changed: ' + label)
    producer = HERE.parent / 'cutaway_cache/DirtyDependencyChecks.java'
    run([jdk / 'bin/javac', '--release', build.JVM_TARGET, '-cp', cp, '-d', out / 'classes',
         producer, HERE / 'NativeMutationChecks.java'], 'compile-producers')
    producer_log = run([jdk / 'bin/java', '-Xmx256m', '-Djava.awt.headless=true', '-cp', cp,
                        'NativeMutationChecks'], 'native-producers')
    if 'NATIVE_MUTATION_CHECKS_PASS cases=10' not in producer_log:
        raise RuntimeError('Incomplete native producer result')
    with zipfile.ZipFile(official) as archive:
        replaced = {name.removesuffix('.class') for name in archive.namelist() if name.endswith('.class')}
    effective = [row for row in inventories['native']['events'] if row['class'] not in replaced] + inventories['official']['events']
    receipt = dict(format=1, diagnostic_only=True, performance_measured=False, game_launched=False,
                   native_sha256=NATIVE, official_sha256=OFFICIAL, jvm_target=build.JVM_TARGET,
                   sources={source.name: sha(source) for source in sources}, inventories=inventories, effective_events=effective,
                   native_producer_result=producer_log.strip().splitlines(), persistent_generation_contract_admissible=False,
                   alias_closure_proved=False, selected_modpack_writers_audited=False)
    (out / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(producer_log, end='')
    print(*(label + ': ' + data['summary'] for label, data in inventories.items()), sep='\n')


if __name__ == '__main__':
    main()
