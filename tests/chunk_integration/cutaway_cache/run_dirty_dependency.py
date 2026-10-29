#!/usr/bin/env python3
"""Prove the native API dirty-dependency gap; do not claim gameplay reachability."""
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
_spec = importlib.util.spec_from_file_location('cutaway_cache_fixture', HERE / 'run.py')
fixture = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fixture)
GUARDS = {**fixture.GUARDS,
    'zombie/core/properties/PropertyContainer.class': 'bc236f8e9e4e0da8a86b0d1fd19ad8d44a040fe4f67d1baac77401b3b148bd77',
    'zombie/iso/SpriteDetails/IsoFlagType.class': '0c11206e0b8366e286d4d7e2aaa802d40f106463163397a59bc5d761f40a8bf9',
}
sha = lambda b: hashlib.sha256(b).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('game', 'jdk', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    game, jdk, out = (getattr(args, name).resolve() for name in ('game', 'jdk', 'output'))
    if out.exists() or out == game or game in out.parents:
        parser.error('Output must be new and outside the installed game')
    if fixture.operation.JVM_TARGET != '25':
        parser.error('Requalify this pinned B42.21 producer check before changing JVM target')
    version = subprocess.run([str(jdk / 'bin/java'), '-version'], text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15)
    major = re.search(r'version "(\d+)', version.stdout)
    if version.returncode or major is None or int(major[1]) < int(fixture.operation.JVM_TARGET):
        parser.error('JDK 25+ is required')
    native, buddy = game / 'projectzomboid.jar', game / 'ZombieBuddy.jar'
    with zipfile.ZipFile(native) as archive:
        for name, digest in GUARDS.items():
            if sha(archive.read(name)) != digest:
                parser.error('Native resource changed: ' + name)
    out.mkdir(parents=True)
    for name in ('classes', 'source', 'work', 'home'):
        (out / name).mkdir()
    cp = os.pathsep.join(map(str, (out / 'classes', native, buddy)))
    source = HERE / 'DirtyDependencyChecks.java'
    for path in (source, Path(__file__)):
        (out / 'source' / path.name).write_bytes(path.read_bytes())
    (out / 'java-version.log').write_text(version.stdout)

    def run(command, label):
        try:
            result = subprocess.run(list(map(str, command)), cwd=out / 'work', text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
        except subprocess.TimeoutExpired as error:
            output = error.stdout or ''
            (out / (label + '.log')).write_text(output.decode() if isinstance(output, bytes) else output)
            raise
        (out / (label + '.log')).write_text(result.stdout)
        if result.returncode:
            raise RuntimeError(label + ': ' + result.stdout[-5000:])
        return result.stdout

    run([jdk / 'bin/javac', '--release', fixture.operation.JVM_TARGET, '-cp', cp,
         '-d', out / 'classes', source], 'compile')
    log = run([jdk / 'bin/java', '-Xmx256m', '-Djava.awt.headless=true',
               '-Duser.home=' + str(out / 'home'), '-cp', cp, 'DirtyDependencyChecks'], 'correctness')
    if 'DIRTY_DEPENDENCY_CHECKS_PASS gameplay_reachability_proved=false' not in log:
        raise RuntimeError('Missing complete native producer result')
    receipt = dict(format=1, diagnostic_only=True, api_dependency_gap_proved=True,
                   gameplay_reachability_proved=False, performance_measured=False, game_launched=False,
                   jvm_target=fixture.operation.JVM_TARGET, native_guards=GUARDS,
                   sources={path.name: sha(path.read_bytes()) for path in (source, Path(__file__))},
                   result=log.strip().splitlines())
    (out / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(log, end='')


if __name__ == '__main__':
    main()
