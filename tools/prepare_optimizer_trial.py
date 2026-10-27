#!/usr/bin/env python3
"""Build a private, reversible Windows optimizer trial; never include upstream binaries."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import tarfile
import re
import zipfile
import sys

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'PZDrivingOptimizerTrial'
BRIDGE = 'PZDrivingOptimizerBridge'
LAUNCHERS = ('Launch-Trial.ps1', 'Start-optimized.cmd', 'Start-control.cmd', 'Check-setup.cmd',
             'candidate-manifest.json', 'README.txt', 'verification.txt', 'Pack.ps1',
             'TrialDiagnostics.ps1', 'TrialTelemetry.ps1', 'TrialReadiness.ps1', 'TrialWpr.ps1', 'TrialWprWorker.ps1', 'TrialWprTools.ps1', 'Test-WPR.ps1', 'Test-WPR.cmd', 'PZTrial.wprp', 'TrialDownload.ps1', 'TrialNvidia.ps1', 'TrialHotkey.ps1', 'TrialCapFrameX.ps1', 'Collect-TrialResults.ps1', 'Collect-results.cmd')


def regular(path: Path) -> None:
    if not path.is_file() or path.is_symlink() or any(p.is_symlink() for p in path.parents):
        raise ValueError(f'Required regular file: {path}')


def properties_resource(values: dict, *, hashes: bool = False) -> str:
    """Emit deterministic ASCII Java properties, without path or escape ambiguity."""
    if not isinstance(values, dict):
        raise ValueError('Expected a property map')
    rows = []
    for key, value in sorted(values.items()):
        if not isinstance(key, str) or not isinstance(value, str) or not key.isascii() or not value.isascii():
            raise ValueError('Bridge properties must contain ASCII string keys and values')
        if hashes:
            if not re.fullmatch(r'[A-Za-z0-9_/$.-]+', key) or '..' in Path(key).parts or key.startswith('/') or not re.fullmatch(r'[0-9a-f]{64}', value):
                raise ValueError('Invalid bridge resource/hash property')
        elif not re.fullmatch(r'[A-Za-z][A-Za-z0-9]*', key):
            raise ValueError('Invalid optimizer profile property name')
        escaped = value.replace('\\', '\\\\').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t').replace(' ', '\\ ')
        rows.append(key + '=' + escaped + '\n')
    return ''.join(rows)


def bridge_resources(manifest_path: Path) -> dict[str, str]:
    regular(manifest_path)
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    if not isinstance(manifest, dict) or manifest.get('format') not in (1, 2):
        raise ValueError('Unsupported optimizer candidate manifest')
    selected = manifest.get('selected_files')
    if not isinstance(selected, dict) or not selected:
        raise ValueError('Optimizer candidate manifest has no selected files')
    profile = manifest.get('profile', {})
    lifecycle = manifest.get('lifecycle_guards', {})
    if not isinstance(profile, dict):
        raise ValueError('Optimizer candidate profile must be an object')
    if manifest['format'] == 2 and (not isinstance(profile.get('properties'), dict) or not profile.get('id') or not lifecycle):
        raise ValueError('Extended optimizer manifest lacks its explicit profile/lifecycle guards')
    return {
        'optimizer-trial-selected.properties': properties_resource(selected, hashes=True),
        'optimizer-trial-profile.properties': properties_resource(profile.get('properties', {})),
        'optimizer-trial-native.properties': properties_resource(lifecycle, hashes=True),
        # Two lifecycle classes are reviewed official replacements. Control and
        # the native Host child must match stock bytes, never the optimized set.
        'optimizer-trial-native-lifecycle.properties': properties_resource({
            name: manifest.get('native_guards', {}).get(name, value)
            for name, value in lifecycle.items()}, hashes=True),
    }


def build_bridge(destination: Path, game: Path, jdk: Path, root: Path = ROOT,
                 manifest_path: Path | None = None) -> Path:
    source = root / 'tests/optimizer_trial/java'
    main = source / 'Main.java'
    for file in (main, source / 'mod.info.template', game / 'projectzomboid.jar', game / 'ZombieBuddy.jar'):
        regular(file)
    resources = bridge_resources(manifest_path or source.parent / 'candidate-manifest.json')
    mod = destination / BRIDGE
    if mod.exists():
        raise ValueError(f'Refusing to replace bridge: {mod}')
    (mod / 'common').mkdir(parents=True)
    (mod / '42/media/java').mkdir(parents=True)
    info = (source / 'mod.info.template').read_text()
    if f'id={BRIDGE}\n' not in info or f'javaJarFile=media/java/{BRIDGE}.jar\n' not in info:
        raise ValueError('Bridge metadata differs from agreed launcher ID/JAR')
    (mod / '42/mod.info').write_text(info)
    with tempfile.TemporaryDirectory(prefix='optimizer-bridge-') as temp:
        classes = Path(temp) / 'classes'
        classes.mkdir()
        subprocess.run([str(jdk / 'bin/javac'), '--release', '25', '-cp', str(game / 'ZombieBuddy.jar'),
                        '-d', str(classes), str(main)], check=True)
        target = mod / f'42/media/java/{BRIDGE}.jar'
        with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as z:
            z.writestr('META-INF/MANIFEST.MF', 'Manifest-Version: 1.0\n\n')
            for name, text in resources.items():
                z.writestr(name, text.encode('ascii'))
            for file in sorted(classes.rglob('*.class')):
                z.write(file, file.relative_to(classes).as_posix())
    return mod



def snapshot_pack(root: Path, destination: Path, reference: str) -> str:
    """Read one exact Git commit, never the possibly stale/dirty surrounding checkout."""
    revision = subprocess.check_output(['git', '-C', str(root), 'rev-parse', '--verify',
                                        '--end-of-options', reference + '^{commit}'], text=True).strip()
    if not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('Pack reference did not resolve to a SHA-1 Git commit')
    archive = destination.with_suffix('.tar')
    with archive.open('wb') as stream:
        subprocess.run(['git', '-C', str(root), 'archive', revision, 'PZSurvivorToolkit',
                        'JavaPatches', 'SurvivorQoL-selected.ini'], stdout=stream, check=True)
    destination.mkdir()
    with tarfile.open(archive) as bundle:
        for member in bundle:
            path = Path(member.name)
            if path.is_absolute() or '..' in path.parts or not (member.isdir() or member.isfile()):
                raise ValueError('Non-regular Git pack input: ' + member.name)
            target = destination / path
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with bundle.extractfile(member) as incoming, target.open('wb') as outgoing:
                    shutil.copyfileobj(incoming, outgoing)
    archive.unlink()
    return revision


def pack_provenance(root: Path, revision: str, base_ref: str = 'origin/main') -> dict:
    """Describe the local candidate without claiming that its commit is published main."""
    base = subprocess.check_output(['git', '-C', str(root), 'rev-parse', '--verify',
                                    '--end-of-options', base_ref + '^{commit}'], text=True).strip()
    ancestor = subprocess.check_output(['git', '-C', str(root), 'merge-base', revision, base], text=True).strip()
    if any(not re.fullmatch(r'[0-9a-f]{40}', value) for value in (revision, base, ancestor)):
        raise ValueError('Candidate provenance did not resolve to SHA-1 Git commits')
    return {'source_kind': 'local-candidate', 'source_revision': revision,
            'base_revision': ancestor, 'base_ref_revision': base,
            # Legacy PowerShell consumers use this as the pack identity, not a branch assertion.
            'main_revision': revision}


def snapshot_java_source(java_source: Path, destination: Path) -> dict:
    """Use working sources only after explicit selection; never copy build/cache output."""
    java_source = java_source.absolute()
    if java_source.is_symlink() or any(p.is_symlink() for p in java_source.parents):
        raise ValueError('Linked Java source is not supported')
    for path in (java_source / 'build.py', java_source / 'tools/RelocateKotlin.java'):
        regular(path)
    if not (java_source / 'src').is_dir():
        raise ValueError('Java source must be a JavaPatches directory with src/')
    base_revision = subprocess.check_output(['git', '-C', str(java_source), 'rev-parse', '--verify',
                                             'HEAD^{commit}'], text=True).strip()
    if not re.fullmatch(r'[0-9a-f]{40}', base_revision):
        raise ValueError('Java source base did not resolve to a Git commit')
    # These are the complete runtime/compiler inputs; tests/docs/build output are not build inputs.
    files = [java_source / 'build.py', java_source / 'tools/RelocateKotlin.java']
    runtime_paths = sorted((java_source / 'src').rglob('*'))
    if any(file.is_symlink() for file in runtime_paths):
        raise ValueError('Linked Java runtime source is not supported')
    files += [file for file in runtime_paths if '__pycache__' not in file.parts and not file.is_dir()]
    files = [file for file in files if not file.is_dir()]
    if any(file.suffix not in ('.java', '.kt', '.py') for file in files):
        raise ValueError('Java source contains unexpected generated or binary inputs')
    hashes = {}
    for file in files:
        regular(file)
        hashes[file.relative_to(java_source).as_posix()] = hashlib.sha256(file.read_bytes()).hexdigest()
    if not any(name.startswith('src/') for name in hashes):
        raise ValueError('Java source has no runtime source files')
    fingerprint = hashlib.sha256(json.dumps(hashes, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    if destination == java_source or destination in java_source.parents or java_source in destination.parents:
        raise ValueError('Java snapshot destination overlaps its source')
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    for file in files:
        relative = file.relative_to(java_source)
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(file, target)
        if hashlib.sha256(target.read_bytes()).hexdigest() != hashes[relative.as_posix()]:
            raise ValueError('Java working source changed while snapshotting: ' + relative.as_posix())
    current_files = [java_source / 'build.py', java_source / 'tools/RelocateKotlin.java'] + [
        file for file in (java_source / 'src').rglob('*') if '__pycache__' not in file.parts and not file.is_dir()]
    current = {}
    for file in current_files:
        regular(file)
        current[file.relative_to(java_source).as_posix()] = hashlib.sha256(file.read_bytes()).hexdigest()
    if current != hashes:
        raise ValueError('Java working-source inventory changed while snapshotting')
    return {'mode': 'explicit-working-source', 'base_revision': base_revision,
            'fingerprint_sha256': fingerprint, 'files': dict(sorted(hashes.items()))}


def record_java_source(jar: Path, identity: dict) -> None:
    """Extend the existing portable build proof, retaining the builder's source fingerprints."""
    resource = 'META-INF/pztoolkit-build-inputs.json'
    with zipfile.ZipFile(jar) as source:
        manifest = json.loads(source.read(resource))
        if not isinstance(manifest, dict) or manifest.get('format') != 1 or not isinstance(manifest.get('sources'), dict):
            raise ValueError('Java patch JAR lacks its source build manifest')
        manifest['optimizer_trial_source'] = identity
        temporary = jar.with_suffix('.trial-source.tmp')
        try:
            with zipfile.ZipFile(temporary, 'w') as target:
                for item in source.infolist():
                    target.writestr(item, (json.dumps(manifest, sort_keys=True, separators=(',', ':')) + '\n').encode('utf-8')
                                    if item.filename == resource else source.read(item))
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
    temporary.replace(jar)


def include_pack(stage: Path, source: Path, revision: str, game: Path, jdk: Path,
                 kotlin_home: Path | None, root: Path, java_source_identity: dict | None = None,
                 provenance: dict | None = None) -> dict:
    from tools.queue_checks.mod_selection import metadata, mod_ids
    from tools.prepare_driving_benchmark import _regular_tree
    settings = metadata(source / 'SurvivorQoL-selected.ini')
    ordered = mod_ids(settings['Mods'])
    workshop = settings['WorkshopItems'].split(';')
    if not workshop or len(workshop) != len(set(workshop)) or any(not item.isascii() or not item.isdigit() for item in workshop):
        raise ValueError('Invalid pinned Workshop list')
    command = [sys.executable, str(source / 'JavaPatches/build.py'), '--game', str(game), '--jdk', str(jdk)]
    if kotlin_home is not None:
        command += ['--kotlin-home', str(kotlin_home)]
    subprocess.run(command, check=True, cwd=source)
    if java_source_identity is not None:
        record_java_source(source / 'JavaPatches/build/PZToolkitJavaPatches/42/media/java/PZToolkitJavaPatches.jar', java_source_identity)
    own = {}
    for identifier, folder in [('PZSurvivorToolkit', source / 'PZSurvivorToolkit'),
                               ('PZToolkitJavaPatches', source / 'JavaPatches/build/PZToolkitJavaPatches')]:
        if identifier not in ordered:
            raise ValueError('Pinned set lacks repository mod: ' + identifier)
        _regular_tree(folder)
        info = metadata(folder / '42/mod.info')
        if info['id'] != identifier:
            raise ValueError('Wrong repository mod ID: ' + identifier)
        own[identifier] = {'version': info.get('modversion', info.get('version')),
            'files': {p.relative_to(folder).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in sorted(folder.rglob('*')) if p.is_file()}}
        shutil.copytree(folder, stage / 'mods' / identifier)
    manifest = {'format': 1, **(provenance or pack_provenance(root, revision)), 'mod_ids': ordered,
                'workshop_ids': workshop, 'repository_mods': own}
    if java_source_identity is not None:
        manifest['java_source'] = java_source_identity
    (stage / 'pack-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    shutil.copy2(source / 'SurvivorQoL-selected.ini', stage / 'SurvivorQoL-selected.ini')
    # Separate native menu Host preset. The SP driving starter is not active in MP.
    host = dict(settings)
    host.update(Mods=';'.join(ordered + [BRIDGE]), Public='false', UPnP='false')
    (stage / 'Server').mkdir(exist_ok=True)
    (stage / 'Server/PZOptimizerHost.ini').write_text(
        '# Isolated optimizer diagnostics: select PZOptimizerHost in the Host menu.\n'
        + ''.join(key + '=' + value + '\n' for key, value in host.items()))
    lua = stage / 'mods' / BRIDGE / '42/media/lua/client'
    lua.mkdir(parents=True, exist_ok=True)
    for name in ('PZOptimizerTrialPack.lua', 'PZOptimizerTrialTelemetry.lua'):
        regular(root / 'tests/optimizer_trial' / name)
        shutil.copy2(root / 'tests/optimizer_trial' / name, lua)
    # Identifiers and SHA were validated above; JSON quoting is valid for these ASCII Lua strings.
    text = 'return {revision=' + json.dumps(revision) + ',ids={' + ','.join(
        json.dumps(id) for id in ordered + ['PZDrivingBench', BRIDGE]) + '}}\n'
    (lua / 'PZOptimizerTrialExpectedMods.lua').write_text(text)
    return manifest


def prepare(output: Path, game: Path, jdk: Path, root: Path = ROOT,
            pack_ref: str = 'HEAD', kotlin_home: Path | None = None,
            java_source: Path | None = None, base_ref: str = 'origin/main') -> tuple[Path, Path]:
    root, output, game, jdk = (p.absolute() for p in (root, output, game, jdk))
    archive = output.with_suffix('.zip')
    if output.exists() or archive.exists():
        raise ValueError('Output or archive exists; choose a fresh output to preserve profiles/recordings')
    if any(p.is_symlink() for p in (output, archive, *output.parents)):
        raise ValueError('Linked output is not supported')
    source = root / 'tests/optimizer_trial'
    base = root / 'tests/driving_benchmark'
    for name in LAUNCHERS:
        regular(source / name)
    for name in ('Launch.ps1', 'Record-JFR.ps1', 'Record-JFR.cmd'):
        regular(base / name)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.optimizer-trial-', dir=output.parent) as temp:
        stage = Path(temp) / PACKAGE
        stage.mkdir()
        for name in LAUNCHERS:
            shutil.copy2(source / name, stage / name)
        for name in ('Launch.ps1', 'Record-JFR.ps1', 'Record-JFR.cmd'):
            shutil.copy2(base / name, stage / name)
        from tools.prepare_driving_benchmark import _regular_tree, HOST_INI
        starter = base / 'mods/PZDrivingBench'
        _regular_tree(starter)
        shutil.copytree(starter, stage / 'mods/PZDrivingBench')
        (stage / 'Server').mkdir()
        (stage / 'Server/PZDrivingBench.ini').write_text(HOST_INI)
        bridge = build_bridge(stage / 'mods', game, jdk, root, stage / 'candidate-manifest.json')
        pack_source = Path(temp) / 'candidate-source'
        revision = snapshot_pack(root, pack_source, pack_ref)
        provenance = pack_provenance(root, revision, base_ref)
        java_identity = snapshot_java_source(java_source, pack_source / 'JavaPatches') if java_source is not None else None
        pack = include_pack(stage, pack_source, revision, game, jdk, kotlin_home, root, java_identity, provenance)
        receipt = {'format': 1, 'scope': 'experimental one-PC sequential single-player comparison with shared multiplayer-compatible optimizations; explicit multiplayer mode; one world session per process',
                   'default_session': 'SinglePlayer',
                   'diagnostics_format': 3, 'diagnostics_revision': '3.3',
                   'source_only_upstream': True, **provenance, 'selected_mod_count': len(pack['mod_ids']),
                   'repository_versions': {id: row['version'] for id, row in pack['repository_mods'].items()},
                   'bridge_jar_sha256': hashlib.sha256(
                       (bridge / f'42/media/java/{BRIDGE}.jar').read_bytes()).hexdigest(),
                   'dashboard_sha256': hashlib.sha256((stage / 'mods/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/VehicleDashboardTextures.lua').read_bytes()).hexdigest()}
        receipt['diagnostics_files_sha256'] = {name: hashlib.sha256((stage / name).read_bytes()).hexdigest() for name in LAUNCHERS}
        receipt['wpr_profile'] = {'file': 'PZTrial.wprp', 'selector': 'PZTrial.light',
            'sha256': hashlib.sha256((stage / 'PZTrial.wprp').read_bytes()).hexdigest()}
        candidate = stage / 'candidate-manifest.json'
        receipt['candidate_manifest_sha256'] = hashlib.sha256(candidate.read_bytes()).hexdigest()
        candidate_data = json.loads(candidate.read_text(encoding='utf-8'))
        receipt['optimizer_candidate'] = {'format': candidate_data['format'],
            'release_sha256': candidate_data.get('release_sha256'),
            'profile_id': candidate_data.get('profile', {}).get('id'),
            'profile_source_revision': candidate_data.get('toolkit_source_revision')}
        if java_identity is not None:
            receipt['java_source'] = java_identity
        (stage / 'build-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        packed = Path(temp) / archive.name
        with zipfile.ZipFile(packed, 'w', zipfile.ZIP_DEFLATED) as z:
            for p in sorted(stage.rglob('*')):
                z.write(p, (Path(PACKAGE) / p.relative_to(stage)).as_posix())
        stage.rename(output)
        try:
            packed.rename(archive)
        except OSError:
            shutil.rmtree(output)
            raise
    return output, archive


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--game', type=Path, required=True, help='Directory containing projectzomboid.jar and ZombieBuddy.jar')
    p.add_argument('--jdk', type=Path, required=True)
    p.add_argument('--output', type=Path, default=ROOT / 'dist' / PACKAGE)
    p.add_argument('--pack-ref', default='HEAD', help='Exact local candidate commit/ref to snapshot once; uncommitted runtime changes are excluded')
    p.add_argument('--base-ref', default='origin/main', help='Fetched main ref used to record the candidate merge base')
    p.add_argument('--kotlin-home', type=Path, help='Pinned Kotlin compiler required by the snapshotted candidate builder')
    p.add_argument('--java-source', type=Path, help='Explicit reviewed JavaPatches working-source directory; Toolkit and mod selection stay pinned to --pack-ref')
    a = p.parse_args()
    for value in prepare(a.output, a.game, a.jdk, pack_ref=a.pack_ref, kotlin_home=a.kotlin_home, java_source=a.java_source, base_ref=a.base_ref):
        print(value)


if __name__ == '__main__':
    # Support both python tools/foo.py and importing tools.foo in checks.
    import sys
    sys.path.insert(0, str(ROOT))
    main()
