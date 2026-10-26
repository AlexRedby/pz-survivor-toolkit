"""Exercise only the selective optimizer and its bridge in a disposable SP world."""
from pathlib import Path
import re
import shutil
import optimizer_profile
from . import driving_benchmark as driving

SP_WORLD = 'PZDrivingBench-OptimizerTrial-native-SP'
LIFECYCLE_FAILURES = ('[OptimizerTrial] prewarm disabled:', '[OptimizerTrial] FAIL',
            '[OptimizerTrialProbe] FAIL ', '[OptimizerTrial] telemetry flush failed',
            '[OptimizerTrial] drive telemetry disabled', 'animalPreload: java.',
            'anim set preload zombie-crawler:')
FUNCTIONAL_FAILURE = '[OPTIMIZER_TRIAL_TEST] FAIL '
FAILURES = (*LIFECYCLE_FAILURES, FUNCTIONAL_FAILURE)


def definitions():
    value = driving.definitions()['driving-benchmark']
    value = dict(value, clients=1, default_mods=['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit'])
    value['cases'] = [dict(value['cases'][0], kinds=['sp'], languages=['EN'])]
    return {'optimizer-trial': value}


def driving_selection(selection):
    # A locked gameplay pack remains exact; the starter is a separately sealed fixture.
    mods = list(selection['mods'])
    if 'PZDrivingBench' not in mods:
        mods.append('PZDrivingBench')
    return dict(selection, mods=mods)


def validate(selection):
    driving.validate(driving_selection(selection))
    options = selection.get('options', {})
    if selection['kind'] != 'sp' or not {'ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit'} <= set(selection['mods']):
        raise ValueError('Optimizer trial requires single-player and both Toolkit components/ZombieBuddy')
    archive = options.get('optimizer_archive')
    if not isinstance(archive, str) or not Path(archive).is_absolute() or not Path(archive).is_file():
        raise ValueError('optimizer_archive must be an existing absolute official ZIP path')
    if options.get('optimizer_prewarm', True) is not True:
        raise ValueError('Optimizer trial requires the production preload bridge')


def sources(project, selection):
    return [*driving.sources(project, selection), *optimizer_profile.sources(project, selection),
            Path(project) / 'tests/driving_benchmark/mods/PZDrivingBench/42/mod.info',
            Path(project) / 'tests/native_queue/optimizer-trial/client/ZZOptimizerTrialCheck.lua',
            Path(project) / 'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/VehicleDashboardTextures.lua']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    project, output, game, jdk = map(Path, (project, output, game, jdk))
    driving.stage(project, output, game, jdk, driving_selection(selection), locations, runtime)
    cache = Path(runtime['roles']['client1']['cache'])
    if 'PZDrivingBench' not in selection['mods']:
        shutil.copytree(project / 'tests/driving_benchmark/mods/PZDrivingBench', cache / 'mods/PZDrivingBench')
        runtime['fixture'].setdefault('mods', []).append('PZDrivingBench')
    (cache / 'Lua/DrivingBench-run.txt').write_text(SP_WORLD + '\n')
    fixture = cache / 'mods/ActionQueueTest/42/media/lua/client'
    shutil.copy2(project / 'tests/native_queue/driving-benchmark/client/ZZDrivingBenchCheck.lua', fixture)
    shutil.copy2(project / 'tests/native_queue/optimizer-trial/client/ZZOptimizerTrialCheck.lua', fixture)
    profile_selection = dict(selection, options={**selection.get('options', {}), 'optimizer_prewarm': True})
    # The shared stager authenticates the archive/native bytes, builds the actual
    # bridge and viewport observer, and keeps the overlay outside runner classes.
    optimizer_profile.stage(project, output, game, jdk, profile_selection, runtime)
    runtime['fixture']['failure_markers'] += [marker for marker in FAILURES
        if marker not in runtime['fixture']['failure_markers']]


def lifecycle_complete(text):
    if any(marker in text for marker in LIFECYCLE_FAILURES):
        return False
    markers = ('[OptimizerTrial] prewarm armed; awaiting OnGameBoot; mode=singleplayer',
        '[OptimizerTrial] official cache and preload active',
        '[OptimizerTrial] OnGameBoot animation preload started mode=singleplayer postClientReset=false',
        '[OptimizerTrial] animation preload joined; animal preload started mode=singleplayer',
        '[OptimizerTrial] bridge ready mode=singleplayer client=false server=false session=1',
        '[OptimizerTrial] animal drain invoked mode=singleplayer client=false server=false')
    if not all(marker in text for marker in markers):
        return False
    profile = re.search(r'\[OptimizerTrial\] extended active profile=xd3i-b42\.21-d1bbdcf-bounded-v1 tileBatch=(true|false) '
                        r'bakeScheduler=true occlusionRetain=true chunkHandoffDivisor=8(?:\s|$)', text)
    if (profile is None or not re.search(r'\[OptimizerTrial\] bake scheduler used frames=[1-9]\d* grants=[1-9]\d*', text)
            or not re.search(r'anim sets preloaded in \d+(?:[.,]\d+)? s', text)):
        return False
    if profile[1] == 'true' and not re.search(r'\[OptimizerTrial\] tile batch used starts=[1-9]\d* merged=[1-9]\d* stamped=[1-9]\d*', text):
        return False
    parsed = re.findall(r'animalPreload: (\d+) animation sets, (\d+) action groups parsed', text)
    handed = re.findall(r'animalPreload: (\d+) action groups handed to the game, (\d+) it had loaded first', text)
    return bool(parsed and handed and int(parsed[-1][1]) > 0
                and sum(map(int, handed[-1])) >= int(parsed[-1][1]))


def complete(selection, role, text):
    return (driving.complete(selection, role, text) and lifecycle_complete(text)
            and '[OPTIMIZER_TRIAL_TEST] COMPLETE ' in text
            and not any(marker in text for marker in FAILURES))


def verify(root, selection, catalog):
    result = driving.verify(root, selection, catalog)
    text = (Path(root) / 'client1-launch.log').read_text(errors='replace')
    if not lifecycle_complete(text):
        result['issues'].append('Missing real optimizer boot/animal preload completion and bridge lifecycle evidence')
    if any(marker in text for marker in LIFECYCLE_FAILURES):
        result['issues'].append('Optimizer lifecycle/preload or observer failed')
    if FUNCTIONAL_FAILURE in text:
        result['issues'].append('Functional optimizer walking/observation fixture failed')
    elif '[OPTIMIZER_TRIAL_TEST] COMPLETE ' not in text:
        result['issues'].append('Functional optimizer walking/observation completion missing')
    if result['issues']:
        for outcome in result['outcomes']:
            outcome.update(status='failed', reason='; '.join(result['issues']))
    result['evidence']['limits'] = ['macOS isolated SP functional smoke; no Windows, full-speed driving or FPS verdict.',
                                  'Check selected mod IDs in manifest; this does not prove other mods or Host compatibility.']
    result['evidence']['functional'] = re.findall(r'\[OPTIMIZER_TRIAL_TEST\] (?:COMPLETE|LIMIT)[^\r\n]*', text)
    result['evidence']['optimizer_activation'] = re.findall(r'\[OptimizerTrial\] extended active[^\r\n]*', text)
    return result
