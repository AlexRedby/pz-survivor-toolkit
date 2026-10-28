#!/usr/bin/env python3
"""Run pinned translucent-order correctness checks without launching or installing the game."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / 'JavaPatches/tests/net/alexredby/pztoolkitjavapatches'


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('game', 'jdk', 'optimizer-archive', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--patch-jar', type=Path, default=ROOT / 'JavaPatches/build/PZToolkitJavaPatches/42/media/java/PZToolkitJavaPatches.jar')
    args = parser.parse_args()
    game, jdk, archive, output, patch = [p.resolve() for p in
        (args.game, args.jdk, args.optimizer_archive, args.output, args.patch_jar)]
    if output.exists() or output == game or game in output.parents:
        parser.error('Output must be a new directory outside the game installation')
    for path in (game / 'projectzomboid.jar', game / 'ZombieBuddy.jar', jdk / 'bin/javac', jdk / 'bin/java', archive, patch):
        if not path.is_file():
            parser.error('Missing explicit input: ' + str(path))
    spec = importlib.util.spec_from_file_location('pz_java_build', ROOT / 'JavaPatches/build.py')
    build = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(build)
    build.require_current_patch_jar(patch, ROOT / 'JavaPatches')
    output.mkdir(parents=True)
    for name in ('classes', 'sources', 'home'):
        (output / name).mkdir()
    sources = []
    for name in ('TranslucentUnionChecks.java', 'TranslucentOrderChecks.java'):
        path = output / 'sources' / name
        path.write_bytes((TESTS / name).read_bytes())
        sources.append(path)
    receipt = {'format': 1, 'research_only': True, 'performance_measurement': False,
               'inputs': {name: digest(path) for name, path in (
                   ('game', game / 'projectzomboid.jar'), ('buddy', game / 'ZombieBuddy.jar'),
                   ('optimizer_archive', archive), ('patch', patch))},
               'sources': {path.name: digest(path) for path in sources},
               'runner_sha256': digest(Path(__file__))}
    (output / 'inputs.json').write_text(json.dumps(receipt, indent=2) + '\n')

    def run(command, log_name, marker=None):
        with (output / log_name).open('w') as log:
            result = subprocess.run(list(map(str, command)), cwd=output, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=180)
        text = (output / log_name).read_text(errors='replace')
        if result.returncode or marker and marker not in text:
            raise RuntimeError('Check failed; see ' + str(output / log_name))
        if marker:
            print(next(line for line in text.splitlines() if marker in line), flush=True)

    cp = os.pathsep.join(map(str, (game / 'projectzomboid.jar', game / 'ZombieBuddy.jar', patch)))
    run([jdk / 'bin/javac', '--release', '25', '-cp', cp, '-d', output / 'classes', *sources], 'compile.log')
    for name, marker in (('TranslucentOrderChecks', 'TRANSLUCENT_ORDER_CHECKS_PASS'),
                         ('TranslucentUnionChecks', 'TRANSLUCENT_UNION_CHECKS_PASS')):
        run([jdk / 'bin/java', '-Djava.awt.headless=true', '-Dzomboid.steam=0',
             '-Duser.home=' + str(output / 'home'), '-Dpz.test.optimizer.archive=' + str(archive),
             '-cp', os.pathsep.join((str(output / 'classes'), cp)),
             'net.alexredby.pztoolkitjavapatches.' + name], name + '.log', marker)
    print('Correctness and known limitations only; no cache activation or FPS measurement.')
    print(output)


if __name__ == '__main__':
    main()
