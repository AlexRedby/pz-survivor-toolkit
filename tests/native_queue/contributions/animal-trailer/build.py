#!/usr/bin/env python3
"""Prepare test-only mods offline; never install them or launch a game process."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

HERE = Path(__file__).resolve().parent


def build(game, jdk, patch_jar, output, scenario, cases=None):
    manifest = json.loads((HERE / 'manifest.json').read_text())
    for jar in [game / 'projectzomboid.jar', game / 'ZombieBuddy.jar', patch_jar]:
        if not jar.is_file():
            raise FileNotFoundError(jar)
    with zipfile.ZipFile(game / 'projectzomboid.jar') as engine:
        for name, expected in manifest['class_sha256'].items():
            if hashlib.sha256(engine.read(name)).hexdigest() != expected:
                raise ValueError('Unsupported game bytecode: ' + name)
    executable = '.exe' if os.name == 'nt' else ''
    javac = str(jdk / ('bin/javac' + executable))
    java = str(jdk / ('bin/java' + executable))
    version = subprocess.check_output([javac, '-version'], text=True, stderr=subprocess.STDOUT)
    compiler = re.search(r'javac (\d+)', version)
    if compiler is None or int(compiler[1]) < 25:
        raise ValueError('JDK 25+ is required to read the B42.21 classes')
    classpath = os.pathsep.join(map(str, [game / 'projectzomboid.jar', game / 'ZombieBuddy.jar', patch_jar]))
    # Refuse to merge into an existing cache, profile or mod installation.
    output.mkdir(parents=True, exist_ok=False)
    hashes = {}
    with tempfile.TemporaryDirectory(prefix='animal-trailer-compile-') as temporary:
        temporary = Path(temporary)
        keys = list(manifest['scenarios'][scenario])
        if cases:
            keys = list(dict.fromkeys(key for case in cases for key in manifest['scenarios'][case.split('-')[0]]))
        keys.append('session')
        for key in keys:
            probe = manifest['probes'][key]
            classes = temporary / key
            classes.mkdir()
            subprocess.run([javac, '--release', '17', '-cp', classpath, '-d', str(classes), str(HERE / probe['source'])], check=True)
            mod = output / 'mods' / probe['mod_id']
            jar = mod / ('42/media/java/' + probe['mod_id'] + '.jar')
            jar.parent.mkdir(parents=True)
            with zipfile.ZipFile(jar, 'w', zipfile.ZIP_DEFLATED) as archive:
                for file in sorted(classes.rglob('*.class')):
                    archive.write(file, file.relative_to(classes).as_posix())
            (mod / '42/mod.info').write_text(
                'name=Test-only ' + probe['mod_id'] + '\nid=' + probe['mod_id']
                + '\nversionMin=42.21\nversionMax=42.21\nrequire=\\ZombieBuddy'
                + '\njavaJarFile=media/java/' + jar.name + '\njavaPkgName=' + probe['package'] + '\n')
            hashes[probe['mod_id']] = hashlib.sha256(jar.read_bytes()).hexdigest()
        fixture = output / 'mods' / manifest['fixture_mod']
        shutil.copytree(HERE / 'lua', fixture / '42/media/lua')
        (fixture / '42/mod.info').write_text('name=Animal trailer native fixture\nid=' + manifest['fixture_mod'] + '\nversionMin=42.21\nversionMax=42.21\n')
        config = fixture / '42/media/lua/shared/ZAnimalTrailerConfig.lua'
        config.write_text('AnimalTrailerFixtureConfig = AnimalTrailerFixtureConfig or {\n' + ''.join(
            ' ' + key + '=' + str(value) + ',\n' for key, value in manifest['parameters'].items()) + '}\n')
        if cases:
            with config.open('a') as stream:
                stream.write('AnimalTrailerFixtureConfig.cases={' + ','.join(json.dumps(case) for case in cases) + '}\n')
            shutil.copy2(HERE.parents[1] / 'support/QueueFixtureSession.lua',
                         fixture / '42/media/lua/shared/QueueAnimalSession.lua')
        for mod in (output / 'mods').iterdir():
            for media in ['common/media', '42/media']:
                for directory in ['AnimSets', 'actiongroups']:
                    (mod / media / directory).mkdir(parents=True, exist_ok=True)
        check_classes = temporary / 'lua-parser'
        check_classes.mkdir()
        subprocess.run([javac, '--release', '17', '-cp', classpath, '-d', str(check_classes), str(HERE / 'checks/ParseLua.java')], check=True)
        subprocess.run([java, '-Djava.awt.headless=true', '-cp', str(check_classes) + os.pathsep + classpath, 'ParseLua', *map(str, sorted(fixture.rglob('*.lua')))], check=True)
        if cases and 'equipment' in keys and 'timer' in keys:
            checks_path = os.pathsep.join([classpath, *map(str, sorted((output / 'mods').rglob('*.jar')))])
            subprocess.run([javac, '--release', '17', '-cp', checks_path, '-d', str(check_classes), str(HERE / 'checks/SessionProbeChecks.java')], check=True)
            subprocess.run([java, '-Djava.awt.headless=true', '-cp', str(check_classes) + os.pathsep + checks_path, 'SessionProbeChecks'], check=True)
        if 'ghost' in keys:
            subprocess.run([javac, '--release', '17', '-cp', classpath, '-d', str(check_classes), str(HERE / 'checks/GhostDecoderChecks.java')], check=True)
            for mode in ('original', 'patched'):
                with tempfile.TemporaryDirectory(prefix='animal-ghost-decoder-') as config:
                    result = subprocess.run([java, '-javaagent:' + str(game / 'ZombieBuddy.jar') + '=config_dir=' + config + ',policy=deny-new,verbosity=0',
                        '-Djava.awt.headless=true', '-Dzomboid.steam=0', '-Djava.library.path=.', '-cp',
                        str(check_classes) + os.pathsep + classpath, 'zombie.characters.GhostDecoderChecks', mode],
                        cwd=game, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                (output / ('ghost-decoder-' + mode + '.log')).write_text(result.stdout)
                result.check_returncode()
                marker = 'GHOST_DECODER_CHECKS_PASS mode=' + ('woven' if mode == 'patched' else 'original')
                if marker not in result.stdout:
                    raise ValueError('Headless real decoder proof did not complete: ' + mode)
                print(next(line for line in result.stdout.splitlines() if marker in line))
    helpers = [manifest['probes'][key]['mod_id'] for key in keys] + [manifest['fixture_mod']]
    (output / 'runtime-manifest.json').write_text(json.dumps({'scenario': scenario, 'helper_mod_ids': helpers, 'jar_sha256': hashes, 'runtime': manifest['runtime'], 'installed': False, 'native_started': False}, indent=2) + '\n')
    print('Ready (not installed):', output)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', type=Path, required=True, help='Directory containing the two game/loader JARs')
    parser.add_argument('--jdk', type=Path, required=True, help='JDK 25+ home')
    parser.add_argument('--patch-jar', type=Path, required=True, help='Locally built PZToolkitJavaPatches.jar; compile dependency, not automatically enabled')
    parser.add_argument('--output', type=Path, required=True, help='New disposable directory outside a live game profile')
    parser.add_argument('--scenario', choices=['equipment', 'ghost', 'timer', 'combined'], default='combined')
    args = parser.parse_args()
    build(args.game.resolve(), args.jdk.resolve(), args.patch_jar.resolve(), args.output.resolve(), args.scenario)
