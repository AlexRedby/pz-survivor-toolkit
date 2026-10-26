"""Fixture-only staging of the exact reviewed optimizer renderer, without installing it."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import zipfile
from check_optimizer_compatibility import prepare_overlay


def sources(project, selection):
    archive = selection.get('options', {}).get('optimizer_archive')
    if not archive:
        return []
    root = Path(project)
    return [Path(archive), root / 'tests/optimizer_trial/candidate-manifest.json',
            root / 'tools/optimizer_profile.py', root / 'tools/check_optimizer_compatibility.py',
            root / 'tests/native_queue/support/viewport/Main.java']


def stage(project, output, game, jdk, selection, runtime):
    archive = selection.get('options', {}).get('optimizer_archive')
    if not archive:
        return
    archive = Path(archive)
    if not archive.is_absolute() or not archive.is_file():
        raise ValueError('optimizer_archive must name an explicit official archive')
    root, output, game, jdk = map(Path, (project, output, game, jdk))
    manifest = json.loads((root / 'tests/optimizer_trial/candidate-manifest.json').read_text())
    scratch = output / 'optimizer-inputs'
    scratch.mkdir()
    overlay = prepare_overlay(manifest, archive, game, scratch)
    probe = scratch / 'viewport-classes'
    probe.mkdir()
    subprocess.run([str(jdk / 'bin/javac'), '--release', '25', '-cp',
        os.pathsep.join(str(game / name) for name in ('projectzomboid.jar', 'ZombieBuddy.jar')),
        '-d', str(probe), str(root / 'tests/native_queue/support/viewport/Main.java')],
        check=True, capture_output=True, text=True, timeout=60)
    runtime.setdefault('fixture', {}).setdefault('mods', []).append('NativeViewportProbe')
    props = {'pz.optimizerTrial.profile': manifest['profile']['id'],
             **{'pzopt.' + key: value for key, value in manifest['profile']['properties'].items()}}
    assignments = '\n'.join('System.setProperty(' + json.dumps(key) + ', ' + json.dumps(value) + ');'
                            for key, value in props.items())
    for role, settings in runtime['roles'].items():
        helper = Path(settings['cache']) / 'mods/NativeViewportProbe'
        (helper / 'common').mkdir(parents=True)
        jar = helper / '42/media/java/NativeViewportProbe.jar'
        jar.parent.mkdir(parents=True)
        with zipfile.ZipFile(jar, 'x', zipfile.ZIP_DEFLATED) as bundle:
            for source in sorted(probe.rglob('*.class')):
                bundle.write(source, source.relative_to(probe).as_posix())
        (helper / '42/mod.info').write_text('name=Disposable native viewport observation\nid=NativeViewportProbe\n'
            'versionMin=42.21\nrequire=\\ZombieBuddy\njavaPkgName=net.alexredby.nativeviewport\n'
            'javaJarFile=media/java/NativeViewportProbe.jar\n')
        if not role.startswith('client'):
            continue
        classes = Path(settings['cache']) / 'classes'
        for name in manifest['selected_files']:
            destination = classes / name
            if destination.exists():
                raise ValueError('Optimizer would replace an existing fixture resource: ' + name)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(overlay / name, destination)
        launcher = classes / 'ToolkitSmokeLauncher.java'
        text = launcher.read_text()
        anchor = 'public static void main(String[] args) throws Exception {'
        if text.count(anchor) != 1:
            raise ValueError('Native launcher main changed')
        launcher.write_text(text.replace(anchor, anchor + '\n' + assignments))
        subprocess.run([str(jdk / 'bin/javac'), '--release', '25', '-cp',
                        str(game / 'projectzomboid.jar'), str(classes / 'ToolkitWindowBootstrap.java'),
                        str(launcher)], check=True, capture_output=True, text=True, timeout=60)
    (scratch / 'receipt.json').write_text(json.dumps({
        'archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
        'profile': manifest['profile']['id'], 'properties': len(props) - 1,
        'resources': len(manifest['selected_files']),
        'scope': 'Client renderer overlay. No preload bridge or Windows diagnostics; not a performance comparison.',
    }, indent=2) + '\n')
