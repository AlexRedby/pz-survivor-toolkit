#!/usr/bin/env python3
"""Reproduce pinned tile/stage profiling checks without launching or installing the game.

Use explicit game Java-directory, JDK-home, current patch-jar and official archive
inputs. Generated overlays, classes, recordings and logs stay in a new --output.
These correctness checks do not measure gameplay performance.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from zipfile import ZipFile

from check_driving_callbacks import BAD_OUTPUT, digest, load_build
from check_optimizer_compatibility import prepare_overlay

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'net.alexredby.drivingperf.'


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('game', 'jdk', 'patch-jar', 'optimizer-archive', 'output'):
        parser.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args(argv)
    game, jdk, patch, archive = (getattr(args, name).expanduser().resolve()
                                for name in ('game', 'jdk', 'patch_jar', 'optimizer_archive'))
    requested_output = args.output.expanduser()
    if os.path.lexists(requested_output):
        parser.error('--output must be a new directory')
    output = requested_output.resolve()
    if output == game or game in output.parents:
        parser.error('--output cannot be inside the game installation')
    if ',' in str(output):
        parser.error('--output cannot contain a comma (ZombieBuddy agent-option delimiter)')
    if args.optimizer_archive.expanduser().is_symlink():
        parser.error('--optimizer-archive must be the explicit regular release archive')
    game_jar, buddy = game / 'projectzomboid.jar', game / 'ZombieBuddy.jar'
    java, javac = jdk / 'bin/java', jdk / 'bin/javac'
    for path in (game_jar, buddy, java, javac, patch, archive):
        if not path.is_file():
            parser.error('Required input missing: ' + str(path))
    output.mkdir(parents=True)
    logs = output / 'logs'
    logs.mkdir()
    state = {'format': 1, 'status': 'incomplete', 'checks': [], 'game_launched': False,
             'game_installed': False, 'performance_measurement': False}

    def save():
        (output / 'result.json').write_text(json.dumps(state, indent=2, sort_keys=True) + '\n', encoding='utf-8')

    def run(label, command, markers=()):
        log = logs / (label + '.log')
        command = list(map(str, command))
        (logs / (label + '.command.json')).write_text(json.dumps(command, indent=2) + '\n', encoding='utf-8')
        save()
        try:
            with log.open('w', encoding='utf-8') as target:
                completed = subprocess.run(command, cwd=output, stdout=target, stderr=subprocess.STDOUT,
                                           timeout=180, check=False)
        except subprocess.TimeoutExpired as failure:
            state['checks'].append({'label': label, 'status': 'timeout'})
            save()
            raise RuntimeError('Timed out: ' + label + '; see ' + log.name) from failure
        text = log.read_text(encoding='utf-8', errors='replace')
        passed = completed.returncode == 0 and not any(bad in text for bad in BAD_OUTPUT)
        passed = passed and all(marker in text for marker in markers)
        state['checks'].append({'label': label, 'exit': completed.returncode, 'passed': passed})
        save()
        if not passed:
            raise RuntimeError('Failed: ' + label + '; see ' + log.name)
        print(label + ': PASS', flush=True)

    try:
        save()
        load_build().require_current_patch_jar(patch, ROOT / 'JavaPatches')
        source = ROOT / 'tests/native_queue/optimizer-benchmark'
        manifest_path = ROOT / 'tests/optimizer_trial/candidate-manifest.json'
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        runtime_sources = sorted((source / 'java').glob('*.java'))
        check_sources = [source / 'checks' / (name + '.java') for name in ('StageProfilerChecks', 'TileProfilerChecks')]
        source_paths = [*runtime_sources, *check_sources, Path(__file__).resolve(), manifest_path,
                        ROOT / 'JavaPatches/build.py', ROOT / 'tools/check_driving_callbacks.py',
                        ROOT / 'tools/check_optimizer_compatibility.py', ROOT / 'tools/queue_checks/tile_metrics.py',
                        ROOT / 'tools/queue_checks/adapters/optimizer_benchmark.py']
        fingerprints = {path.relative_to(ROOT).as_posix(): digest(path) for path in source_paths}
        overlay = prepare_overlay(manifest, archive, game, output)
        resources = ('zombie/iso/fboRenderChunk/FBORenderCell.class',
                     'zombie/iso/fboRenderChunk/FBORenderChunkManager.class')
        with ZipFile(game_jar) as bundle:
            native = {name: hashlib.sha256(bundle.read(name)).hexdigest() for name in resources}
        (output / 'inputs.json').write_text(json.dumps({
            'format': 1, 'sources': fingerprints, 'native_resources': native,
            'game_jar_sha256': digest(game_jar), 'buddy_sha256': digest(buddy),
            'patch_jar_sha256': digest(patch), 'optimizer_archive_sha256': digest(archive),
            'patch_source_manifest_verified': True, 'optimizer_overlay_verified': True,
            'profile': manifest['profile']['id'], 'profile_properties': manifest['profile']['properties'],
            'overlay_resources': manifest['selected_files']}, indent=2, sort_keys=True) + '\n', encoding='utf-8')
        classes, checks = output / 'runtime-classes', output / 'check-classes'
        classes.mkdir()
        checks.mkdir()
        native_cp = os.pathsep.join(map(str, (game_jar, buddy)))
        run('java-version', [java, '-version'])
        run('compile-runtime', [javac, '--release', '25', '-cp', native_cp, '-d', classes, *runtime_sources])
        run('compile-checks', [javac, '--release', '25', '-cp', str(classes) + os.pathsep + native_cp,
                               '-d', checks, *check_sources])
        properties = {'pz.optimizerTrial.profile': manifest['profile']['id'],
                      **{'pzopt.' + key: value for key, value in manifest['profile']['properties'].items()}}
        profile_args = output / 'official-profile.args'
        profile_args.write_text('\n'.join('"' + ('-D' + key + '=' + value).replace('\\', '\\\\').replace('"', '\\"') + '"'
                                           for key, value in sorted(properties.items())) + '\n', encoding='utf-8')

        def command(label, main_class, arguments=(), official=False):
            temporary = output / ('tmp-' + label)
            temporary.mkdir()
            cp = ([overlay] if official else []) + [checks, classes, patch, game_jar, buddy]
            result = [java, '-Xmx1536m']
            if official:
                result.append('@' + str(profile_args))
            result += ['-javaagent:' + str(buddy) + '=config_dir=' + str(output / ('agent-' + label))
                       + ',policy=deny-new,verbosity=0', '-Djava.awt.headless=true',
                       '-Duser.home=' + str(output / ('home-' + label)), '-Djava.io.tmpdir=' + str(temporary),
                       '-Dzomboid.steam=0', '-cp', os.pathsep.join(map(str, cp)), main_class, *arguments]
            return result

        # Every case runs in a fresh JVM, with its own classpath, home and agent configuration.
        captures = []
        for official in (False, True):
            for union in (False, True):
                label = ('official' if official else 'native') + ('-union' if union else '')
                cache = output / (label + '-capture')
                arguments = [cache] + (['--union'] if union else [])
                run(label, command(label, PACKAGE + 'TileProfilerChecks', arguments, official),
                    ('TILE_PROFILER_CHECKS_PASS',))
                captures.append(cache)
        sys.path.insert(0, str(ROOT / 'tools'))
        from queue_checks.adapters.optimizer_benchmark import stage_metrics
        evidence = {}
        for cache in captures:
            label = cache.name.removesuffix('-capture') + '-join'
            try:
                evidence[cache.name] = stage_metrics(cache)
            except Exception as failure:
                state['checks'].append({'label': label, 'passed': False, 'error': str(failure)})
                save()
                raise
            (logs / (label + '.json')).write_text(json.dumps(evidence[cache.name], indent=2, sort_keys=True) + '\n', encoding='utf-8')
            state['checks'].append({'label': label, 'passed': True})
            save()
            print(label + ': PASS', flush=True)
        for label, official, union in (('stage-native', False, False), ('stage-official-union', True, True)):
            run(label, command(label, PACKAGE + 'StageProfilerChecks', ['--weave'] + (['--union'] if union else []), official),
                ('STAGE_PROFILER_NATIVE_WEAVING_PASS', 'STAGE_PROFILER_CHECKS_PASS'))
        label = 'export-failure'
        run(label, command(label, PACKAGE + 'TileProfilerChecks', [output / 'export-failure-capture', '--export-failure']),
            ('TILE_EXPORT_FAILURE_CHECKS_PASS',))
        if any(digest(ROOT / name) != expected for name, expected in fingerprints.items()):
            raise RuntimeError('Project sources changed during checks; rerun against stable inputs')
        (output / 'artifact-evidence.json').write_text(json.dumps(evidence, indent=2, sort_keys=True) + '\n', encoding='utf-8')
        state['status'] = 'complete'
        save()
        print('DRIVING_TILE_CHECKS_PASS output=' + str(output))
        return 0
    except Exception as failure:
        state['error'] = str(failure)
        save()
        print('DRIVING_TILE_CHECKS_FAILED ' + str(failure), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
