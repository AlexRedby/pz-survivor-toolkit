#!/usr/bin/env python3
"""Verify the pinned optimizer classpath and Toolkit admission; never install or download it."""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def prepare_overlay(manifest: dict, archive: Path, game: Path, output: Path) -> Path:
    if archive.is_symlink() or sha(archive.read_bytes()) != manifest['release_sha256']:
        raise ValueError('Official archive differs from reviewed release')
    with zipfile.ZipFile(game / 'projectzomboid.jar') as native:
        for name in manifest['native_absences']:
            if name in native.namelist():
                raise ValueError('Unexpected native resource: ' + name)
        for name, digest in manifest['native_guards'].items():
            if sha(native.read(name)) != digest:
                raise ValueError('Changed native resource: ' + name)
    overlay = output / 'overlay'
    overlay.mkdir()
    with zipfile.ZipFile(archive) as bundle:
        for name, digest in manifest['selected_files'].items():
            relative = Path(name)
            if relative.is_absolute() or '..' in relative.parts:
                raise ValueError('Invalid resource path')
            data = bundle.read(name)
            if sha(data) != digest:
                raise ValueError('Changed official resource: ' + name)
            target = overlay / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    return overlay


def compile_ground_highlight_checks(jdk: Path, kotlin_home: Path | None,
                                    jar: Path, fonts: Path, game: Path,
                                    output: Path, classes: Path, parser) -> None:
    """Reuse the native parity suite; compile-only API classes never enter the JVM."""
    spec = importlib.util.spec_from_file_location('optimizer_patch_build', ROOT / 'JavaPatches/build.py')
    build = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(build)
    build.require_current_patch_jar(jar, ROOT / 'JavaPatches')
    home = build.kotlin_toolchain(kotlin_home, parser)
    api = output / 'ground-highlight-test-api'
    api.mkdir()
    dependencies = os.pathsep.join(map(str, [jar, fonts, game / 'projectzomboid.jar',
                                            game / 'ZombieBuddy.jar']))
    stdlib = str(home / 'lib/kotlin-stdlib.jar')
    # The shipped metadata is relocated. Compile only this bridge for original
    # Kotlin internals metadata, with the same module name as the actual artifact.
    build.compile_kotlin(jdk, home, os.pathsep.join([stdlib, dependencies]), api,
                         [ROOT / 'JavaPatches/src/net/alexredby/pztoolkitjavapatches/GroundHighlight.kt'])
    build.compile_kotlin(jdk, home, os.pathsep.join([stdlib, str(api), dependencies]), classes,
                         [ROOT / 'JavaPatches/tests/net/alexredby/pztoolkitjavapatches/GroundHighlightChecks.kt'],
                         module_name=build.KOTLIN_MODULE + '_tests',
                         options=['-Xfriend-paths=' + str(api)])
    relocation = output / 'ground-highlight-build-tools'
    relocation.mkdir()
    relocator = build.build_kotlin_relocator(jdk, home, relocation)
    subprocess.run([*relocator, str(classes), '--tests'], check=True)


def ground_highlight_parity(jdk: Path, game: Path, jar: Path, fonts: Path,
                           classes: Path, overlay: Path, properties: dict,
                           output: Path) -> list[dict]:
    results = []
    for name, pins, paths in [('ground-highlight-native', {}, [classes, jar, fonts]),
                              ('ground-highlight-optimized', properties, [classes, overlay, jar, fonts])]:
        cache = output / name
        cache.mkdir()
        options = [f'-D{k}={v}' for k, v in sorted(pins.items())]
        argfile = cache / 'profile.args'
        argfile.write_text('\n'.join('"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"' for s in options) + '\n')
        cp = os.pathsep.join(map(str, [*paths, game / 'projectzomboid.jar', game / 'ZombieBuddy.jar']))
        command = [str(jdk / 'bin/java'), '@' + str(argfile),
                   '-javaagent:' + str(game / 'ZombieBuddy.jar') + '=config_dir=' + str(cache) + ',policy=deny-new,verbosity=1',
                   '-Djava.awt.headless=true', '-Dzomboid.steam=0', '-Djava.library.path=.',
                   '-Dpz.test.patch.jar=' + str(jar), '-cp', cp,
                   'net.alexredby.pztoolkitjavapatches.GroundHighlightChecks']
        result = subprocess.run(command, cwd=game, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=120)
        (cache / 'check.log').write_text(result.stdout)
        passed = (result.returncode == 0 and 'GROUND_HIGHLIGHT_CHECKS_PASS' in result.stdout
                  and 'ERROR transforming' not in result.stdout)
        results.append({'case': name, 'passed': passed, 'exit': result.returncode})
        print(name, 'PASS' if passed else 'FAIL', flush=True)
        if not passed:
            print(result.stdout[-4000:])
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--game', type=Path, required=True)
    parser.add_argument('--jdk', type=Path, required=True)
    parser.add_argument('--kotlin-home', type=Path, help='Pinned compiler for the existing Kotlin parity suite')
    parser.add_argument('--output', type=Path, required=True, help='New directory for isolated inputs and reports')
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    manifest = json.loads((ROOT / 'tests/optimizer_trial/candidate-manifest.json').read_text())
    if len(manifest['profile']['properties']) != 770 or len(manifest['selected_files']) != 888:
        raise ValueError('Review the changed complete profile before running')
    overlay = prepare_overlay(manifest, args.archive, args.game, args.output)
    mod = ROOT / 'JavaPatches/build/PZToolkitJavaPatches/42/media'
    jar = mod / 'java/PZToolkitJavaPatches.jar'
    fonts = mod / 'bootstrap/PZToolkitFonts.jar'
    if not jar.is_file() or not fonts.is_file():
        raise ValueError('Build Java Patches first')
    classes = args.output / 'classes'
    classes.mkdir()
    compile_ground_highlight_checks(args.jdk, args.kotlin_home, jar, fonts, args.game, args.output, classes, parser)
    cp = os.pathsep.join(map(str, [classes, overlay, jar, fonts, args.game / 'projectzomboid.jar', args.game / 'ZombieBuddy.jar']))
    subprocess.run([str(args.jdk / 'bin/javac'), '--release', '25', '-cp', cp, '-d', str(classes),
                    str(ROOT / 'tests/optimizer_trial/java/OptimizerAdmissionChecks.java')], check=True)
    properties = {'pz.optimizerTrial.profile': manifest['profile']['id'],
                  **{'pzopt.' + key: value for key, value in manifest['profile']['properties'].items()}}
    cases = [('exact', properties, True),
             ('missing-profile', {k: v for k, v in properties.items() if k != 'pz.optimizerTrial.profile'}, False),
             ('missing-pin', {k: v for k, v in properties.items() if k != 'pzopt.entityUpdateParallel'}, False),
             ('unsafe-pin', {**properties, 'pzopt.entityUpdateParallel': 'true'}, False),
             ('extra-pin', {**properties, 'pzopt.unreviewedOption': 'false'}, False),
             ('changed-resource', properties, False)]
    # Run both parity JVMs before the final negative case mutates the overlay.
    results = ground_highlight_parity(args.jdk, args.game, jar, fonts, classes, overlay, properties, args.output)
    for name, pins, expected in cases:
        cache = args.output / name
        cache.mkdir()
        # Each verdict uses a fresh JVM; no previous positive resource cache can mask mutation.
        if name == 'changed-resource':
            target = overlay / 'pzopt/build-info.properties'
            target.write_bytes(target.read_bytes() + b'\nchanged=true\n')
        options = [f'-D{k}={v}' for k, v in sorted(pins.items())]
        argfile = cache / 'profile.args'
        argfile.write_text('\n'.join('"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"' for s in options) + '\n')
        command = [str(args.jdk / 'bin/java'), '@' + str(argfile),
                   '-javaagent:' + str(args.game / 'ZombieBuddy.jar') + '=config_dir=' + str(cache) + ',policy=deny-new,verbosity=1',
                   '-Djava.awt.headless=true', '-Dzomboid.steam=0', '-cp', cp,
                   'OptimizerAdmissionChecks', str(expected).lower()]
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
        (cache / 'check.log').write_text(result.stdout)
        marker = f'OPTIMIZER_ADMISSION_PASS accepted={str(expected).lower()} pairs=20'
        passed = result.returncode == 0 and marker in result.stdout
        results.append({'case': name, 'passed': passed, 'exit': result.returncode})
        print(name, 'PASS' if passed else 'FAIL', flush=True)
        if not passed:
            print(result.stdout[-4000:])
    report = {'archive_sha256': manifest['release_sha256'], 'jar_sha256': sha(jar.read_bytes()),
              'profile': manifest['profile']['id'], 'properties': 770, 'resources': 888,
              'checks': results, 'limits': ['Headless macOS classpath/admission/weaving checks; no visual or FPS verdict.']}
    (args.output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    if not all(row['passed'] for row in results):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
