"""Exercise only the selective optimizer and its bridge in a disposable SP world."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import zipfile
from . import driving_benchmark as driving


def definitions():
    value = driving.definitions()['driving-benchmark']
    value = dict(value, clients=1, default_mods=['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit', 'PZDrivingBench'])
    value['cases'] = [dict(value['cases'][0], kinds=['sp'], languages=['EN'])]
    return {'optimizer-trial': value}


def validate(selection):
    driving.validate(selection)
    options = selection.get('options', {})
    if selection['kind'] != 'sp' or not {'ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit'} <= set(selection['mods']):
        raise ValueError('Optimizer trial requires single-player and both Toolkit components/ZombieBuddy')
    archive = options.get('optimizer_archive')
    if not isinstance(archive, str) or not Path(archive).is_absolute() or not Path(archive).is_file():
        raise ValueError('optimizer_archive must be an existing absolute official ZIP path')


def sources(project, selection):
    base = Path(project) / 'tests/optimizer_trial'
    return [*driving.sources(project, selection), *base.glob('java/*.java'), base / 'java/mod.info.template',
            base / 'candidate-manifest.json', Path(project) / 'tests/native_queue/optimizer-trial/client/ZZOptimizerTrialCheck.lua', Path(project) / 'tools/prepare_optimizer_trial.py',
            Path(project) / 'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/VehicleDashboardTextures.lua',
            Path(selection['options']['optimizer_archive'])]


def stage(project, output, game, jdk, selection, locations, runtime):
    from prepare_optimizer_trial import build_bridge
    project, output, game, jdk = map(Path, (project, output, game, jdk))
    driving.stage(project, output, game, jdk, selection, locations, runtime)
    cache = output / 'client1'
    fixture = cache / 'mods/ActionQueueTest/42/media/lua/client'
    shutil.copy2(project / 'tests/native_queue/driving-benchmark/client/ZZDrivingBenchCheck.lua', fixture)
    shutil.copy2(project / 'tests/native_queue/optimizer-trial/client/ZZOptimizerTrialCheck.lua', fixture)
    manifest = json.loads((project / 'tests/optimizer_trial/candidate-manifest.json').read_text())
    archive = Path(selection['options']['optimizer_archive'])
    if archive.is_symlink() or hashlib.sha256(archive.read_bytes()).hexdigest() != manifest['release_sha256']:
        raise ValueError('Optimizer archive differs from pinned release')
    with zipfile.ZipFile(game / 'projectzomboid.jar') as z:
        for name in manifest['native_absences']:
            if name in z.namelist():
                raise ValueError('Unexpected pre-existing optimizer class: ' + name)
        for name, expected in manifest['native_guards'].items():
            if hashlib.sha256(z.read(name)).hexdigest() != expected:
                raise ValueError('Unsupported native game class: ' + name)
    build_bridge(cache / 'mods', game, jdk, project)
    runtime['fixture']['mods'].append('PZDrivingOptimizerBridge')
    classes = cache / 'classes'
    with zipfile.ZipFile(archive) as z:
        for name, expected in manifest['selected_files'].items():
            data = z.read(name)
            if hashlib.sha256(data).hexdigest() != expected or '..' in Path(name).parts or Path(name).is_absolute():
                raise ValueError('Optimizer resource mismatch: ' + name)
            target = classes / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    # Add only explicit experiment properties to this fixture-owned launcher.
    # Retain the shared runner's GLFW/window/focus/VOIP/owned-process protections.
    launcher = classes / 'ToolkitSmokeLauncher.java'
    text = launcher.read_text()
    anchor = 'public static void main(String[] args) throws Exception {'
    if text.count(anchor) != 1:
        raise ValueError('Native launcher main changed')
    props = {'pz.optimizerTrial.prewarm': 'true', 'pz.optimizerTrial.sourceZip': str(archive),
             'pz.optimizerTrial.cachedir': str(cache), 'pz.optimizerTrial.profile': manifest['profile']['id'],
             **{'pzopt.' + key: value for key, value in manifest['profile']['properties'].items()}}
    assignments = '\n'.join('System.setProperty(' + json.dumps(k) + ', ' + json.dumps(v) + ');' for k, v in props.items())
    launcher.write_text(text.replace(anchor, anchor + '\n' + assignments))
    subprocess.run([str(jdk / 'bin/javac'), '--release', '25', '-cp', str(game / 'projectzomboid.jar'),
                    str(classes / 'ToolkitWindowBootstrap.java'), str(launcher)], check=True, capture_output=True)
    runtime['fixture']['failure_markers'] += ['[OptimizerTrial] prewarm disabled:', '[OptimizerTrial] FAIL',
                                             'animalPreload: java.', 'anim set preload zombie-crawler:', '[OPTIMIZER_TRIAL_TEST] FAIL ']


def complete(selection, role, text):
    return (driving.complete(selection, role, text) and '[OptimizerTrial] official cache and preload active' in text
            and '[OptimizerTrial] extended active profile=xd3i-b42.21-d1bbdcf-bounded-v1 ' in text
            and 'bakeScheduler=true occlusionRetain=true chunkHandoffDivisor=8' in text
            and '[OPTIMIZER_TRIAL_TEST] COMPLETE ' in text
            and '[OptimizerTrial] bake scheduler used frames=' in text
            and 'anim sets preloaded in ' in text
            and 'action groups handed to the game' in text and '[OptimizerTrial] OnGameBoot animation preload started' in text)


def verify(root, selection, catalog):
    result = driving.verify(root, selection, catalog)
    text = (Path(root) / 'client1-launch.log').read_text(errors='replace')
    if not complete(selection, 'client1', text):
        result['issues'].append('Missing real optimizer boot/animal preload completion and bridge lifecycle evidence')
    if '[OptimizerTrial] prewarm disabled:' in text or '[OptimizerTrial] FAIL' in text or '[OPTIMIZER_TRIAL_TEST] FAIL ' in text:
        result['issues'].append('Optimizer bridge disabled or failed')
    if result['issues']:
        for outcome in result['outcomes']:
            outcome.update(status='failed', reason='; '.join(result['issues']))
    result['evidence']['limits'] = ['macOS isolated SP functional smoke; no Windows, full-speed driving or FPS verdict.',
                                  'Check selected mod IDs in manifest; this does not prove other mods or Host compatibility.']
    result['evidence']['functional'] = re.findall(r'\[OPTIMIZER_TRIAL_TEST\] (?:COMPLETE|LIMIT)[^\r\n]*', text)
    result['evidence']['optimizer_activation'] = re.findall(r'\[OptimizerTrial\] extended active[^\r\n]*', text)
    return result
