"""Paired isolated SP driving cadence measurement, using one sealed seed world."""
from pathlib import Path
import csv
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
import zipfile


# Reviewed native B42.21 inputs for disposable stage-timing hooks only.
STAGE_PROFILE_INPUTS = {'zombie/GameWindow.class': 'c3a3583923191b6aea23a74e6b05e2b53302bbcded7f89cae930e364a409dfb2',
 'zombie/iso/IsoChunk.class': '5048becc3f46f746686513d4dcadb137e6e11bfd44617075f41923b3db11650a',
 'zombie/inventory/ItemPickerJava.class': '5c8cf626e46a52cdbd9d73e9de10766dece3388ee3e4f4d8d071df5e44d68522',
 'se/krka/kahlua/vm/KahluaThread.class': '25f4c0dea91800dcb3fadd3d482ed5f7d5cf17908bf167afd308b85c99856bb6',
 'zombie/iso/fboRenderChunk/FBORenderCell.class': 'd5c46201d60cff36397ee46c56b53dbaee6e26e8733836f27bf56ad871eedf94',
 'zombie/ui/UIManager.class': 'fa9a2ec9388573f74082a22f3f357c08f3b0e662325ba4ea587b03a5de005704',
 'org/lwjglx/opengl/Display.class': '15a0c0a3646d4340cd96c47d143a5605bfbae7543410ddaa018e83f45ae1a578'}


def definitions():
    return {'optimizer-benchmark': {'status': 'ready', 'clients': 1,
        'default_mods': ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit', 'PZDrivingBench'],
        'cases': [dict(id=name, producer='fixture', capability='capture' if name == 'drive' else 'effect',
                       kinds=['sp'], languages=['EN'], modes=['native']) for name in ('seed', 'drive')]}}


def validate(selection):
    options = selection.get('options', {})
    if (selection['kind'] != 'sp' or selection['clients'] != 1 or selection['mode'] != 'native'
            or selection['languages'] != ['EN'] or selection['cases'] not in (['seed'], ['drive'])
            or not {'ZombieBuddy','PZToolkitJavaPatches','PZSurvivorToolkit','PZDrivingBench'} <= set(selection['mods'])
            or type(options.get('optimizer_enabled')) is not bool or options.get('mp_host')
            or not selection.get('resources', {}).get('exclusive')):
        raise ValueError('Requires exclusive native EN SP, one seed/drive case and explicit optimizer_enabled')
    if selection['cases'] == ['drive'] and not options.get('world_template'):
        raise ValueError('Measured drive requires a sealed seed world')
    if selection['cases'] == ['seed'] and (options.get('world_template') or options['optimizer_enabled']):
        raise ValueError('Seed must be fresh and unoptimized')
    profile = options.get('stage_profile', False)
    if type(profile) is not bool or profile and selection['cases'] != ['drive']:
        raise ValueError('stage_profile must be an explicit boolean and is only supported for a drive')
    perf = options.get('driving_perf', {})
    if perf.get('scenario', 'highway') not in ('highway', 'west-point-extinction', 'muldraugh-extinction'):
        raise ValueError('Unknown driving scenario')
    if perf.get('scenario') in ('west-point-extinction', 'muldraugh-extinction') and (
            perf.get('vehicle_script') != 'Base.SportsCar' or perf.get('full_throttle') is not True):
        raise ValueError('Urban stress requires the native sports car at full throttle')
    if perf.get('population_mode', 'scripted') not in ('native', 'scripted'):
        raise ValueError('Unknown population mode')
    if perf.get('scenario') == 'muldraugh-extinction' and perf.get('population_mode') != 'native':
        raise ValueError('Muldraugh scenario requires native population without corridor preloading')
    archive = Path(options.get('optimizer_archive', ''))
    if not archive.is_absolute() or not archive.is_file():
        raise ValueError('Explicit official optimizer_archive required')


def sources(project, selection):
    root = Path(project)
    return [*sorted((root / 'tests/native_queue/optimizer-benchmark/java').glob('*')),
            *sorted((root / 'tests/driving_benchmark/mods').rglob('*.lua')),
            root / 'tests/optimizer_trial/java/Main.java', root / 'tests/optimizer_trial/java/mod.info.template',
            root / 'tests/optimizer_trial/candidate-manifest.json', root / 'tools/prepare_optimizer_trial.py',
            root / 'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/VehicleDashboardTextures.lua',
            Path(selection['options']['optimizer_archive'])]


def stage(project, output, game, jdk, selection, locations, runtime):
    from prepare_optimizer_trial import build_bridge
    project, output, game, jdk = map(Path, (project, output, game, jdk))
    validate(selection)
    cache = output / 'client1'; classes = cache / 'classes'
    enabled = selection['options']['optimizer_enabled']
    archive = Path(selection['options']['optimizer_archive'])
    manifest = json.loads((project / 'tests/optimizer_trial/candidate-manifest.json').read_text())
    if archive.is_symlink() or hashlib.sha256(archive.read_bytes()).hexdigest() != manifest['release_sha256']:
        raise ValueError('Official archive differs from pinned input')
    guards = dict(manifest['native_guards'])
    if selection['options'].get('stage_profile', False): guards.update(STAGE_PROFILE_INPUTS)
    with zipfile.ZipFile(game / 'projectzomboid.jar') as z:
        for name, expected in guards.items():
            if hashlib.sha256(z.read(name)).hexdigest() != expected:
                raise ValueError('Unsupported native input: ' + name)
    build_bridge(cache / 'mods', game, jdk, project)
    runtime['fixture']['mods'].append('PZDrivingOptimizerBridge')
    if enabled:
        with zipfile.ZipFile(archive) as z:
            for name, expected in manifest['selected_files'].items():
                data = z.read(name)
                if hashlib.sha256(data).hexdigest() != expected or '..' in Path(name).parts or Path(name).is_absolute():
                    raise ValueError('Changed optimizer resource: ' + name)
                target = classes / name; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(data)
    # The same generated probe mod and input controller are in both arms and the seed.
    source = project / 'tests/native_queue/optimizer-benchmark/java'
    mod = cache / 'mods/PZDrivingPerfProbe/42'
    (mod / 'media/java').mkdir(parents=True)
    shutil.copy2(source / 'mod.info.template', mod / 'mod.info')
    with tempfile.TemporaryDirectory(prefix='pz-driving-probe-build-') as temporary:
        build = Path(temporary)
        subprocess.run([str(jdk / 'bin/javac'), '--release', '25', '-cp',
                        str(game / 'projectzomboid.jar') + ':' + str(game / 'ZombieBuddy.jar'),
                        '-d', str(build), *map(str, sorted(source.glob('*.java')))], check=True, capture_output=True)
        with zipfile.ZipFile(mod / 'media/java/PZDrivingPerfProbe.jar', 'w', zipfile.ZIP_DEFLATED) as jar:
            jar.writestr('META-INF/MANIFEST.MF', 'Manifest-Version: 1.0\n\n')
            for path in sorted(build.rglob('*.class')): jar.write(path, path.relative_to(build).as_posix())
    runtime['fixture']['mods'].append('PZDrivingPerfProbe')
    # Only the copied test starter changes: the fixture owns native create/load below.
    (cache / 'mods/PZDrivingBench/42/media/lua/client/DrivingBenchStart.lua').write_text('-- World lifecycle owned by isolated benchmark fixture.\n')
    client = cache / 'mods/PZDrivingBench/42/media/lua/client/DrivingBenchClient.lua'
    text = client.read_text()
    anchor = 'if C.ready or C.stage=="failed" or not isIngameState() or not F.allowed() then return end'
    if text.count(anchor) != 1: raise ValueError('Starter preparation guard changed')
    client.write_text(text.replace(anchor, 'if PZDrivingPerfSeeding then return end\n    ' + anchor))
    route = cache / 'mods/PZDrivingBench/42/media/lua/shared/DrivingBenchFixture.lua'
    route_text = route.read_text()
    original_route_text = route_text
    scenario = selection['options'].get('driving_perf', {}).get('scenario')
    urban = scenario in ('west-point-extinction', 'muldraugh-extinction')
    if urban:
        route_text = route_text.replace('START_X=10818, START_Y=10118', 'START_X=11050, START_Y=6902')
        start, end = route_text.index('local function spawnSquare(player)'), route_text.index('local function initialize(vehicle)')
        route_text = route_text[:start] + """local function spawnSquare(player)
    assert(math.abs(player:getX()-F.START_X)<3 and math.abs(player:getY()-F.START_Y)<3,
        "Urban seed did not restore its exact start")
    for ahead=-4,4 do for side=-1,1 do
        if not street(F.START_X+ahead,F.START_Y+side) then return end
    end end
    return street(F.START_X,F.START_Y), "E", 90
end

""" + route_text[end:]
        route_text = route_text.replace('Base.CarNormal', 'Base.SportsCar')
        if scenario == 'muldraugh-extinction':
            route_text = original_route_text.replace('START_X=10818, START_Y=10118', 'START_X=10594, START_Y=10650')
            route_text = route_text.replace('Base.CarNormal', 'Base.SportsCar')
            route_text = route_text.replace('{{0,1,"N",180},{1,0,"E",90}}', '{{0,1,"N",180}}')
    else:
        route_text = route_text.replace('START_X=10818, START_Y=10118', 'START_X=10590, START_Y=11680')
    route.write_text(route_text)
    (cache / 'Lua/DrivingBench-run.txt').write_text('PZDrivingBench-Perf\n')
    settings = cache / 'options.ini'
    settings.write_text(settings.read_text() + 'vsync=false\nframeRate=144\nautozoom=false,false,false,false\n')
    launcher = classes / 'ToolkitSmokeLauncher.java'
    text = launcher.read_text(); anchor = 'public static void main(String[] args) throws Exception {'
    if text.count(anchor) != 1: raise ValueError('Native launcher signature changed')
    props = {'pz.drivingPerf.cachedir': str(cache)}
    if selection['options'].get('stage_profile', False):
        props['pz.drivingPerf.stageProfile'] = 'true'
    if enabled:
        props.update({'pz.optimizerTrial.prewarm': 'true', 'pz.optimizerTrial.sourceZip': str(archive),
             'pz.optimizerTrial.cachedir': str(cache), 'pz.optimizerTrial.profile': manifest['profile']['id'],
             **{'pzopt.' + key: value for key, value in manifest['profile']['properties'].items()}})
    assignments = '\n'.join('System.setProperty(' + json.dumps(k) + ', ' + json.dumps(v) + ');' for k,v in props.items())
    launcher.write_text(text.replace(anchor, anchor + '\n' + assignments))
    subprocess.run([str(jdk / 'bin/javac'), '--release', '25', '-cp', str(game / 'projectzomboid.jar'),
                    str(classes / 'ToolkitWindowBootstrap.java'), str(launcher)], check=True, capture_output=True)
    runtime['fixture']['failure_markers'] = ['[DRIVING_PERF] FAIL ', '[PZDrivingBench] FAIL ', '[DRIVING_PERF_WORLD] FAIL ']
    if enabled: runtime['fixture']['failure_markers'] += ['[OptimizerTrial] prewarm disabled:', '[OptimizerTrial] FAIL']


def complete(selection, role, text):
    marker = '[DRIVING_PERF_WORLD] SEED_SAVED' if selection['cases'] == ['seed'] else '[DRIVING_PERF] LUA_COMPLETE'
    return role == 'client1' and text.count(marker) == 1


def metrics(path):
    buckets = {}
    with path.open() as f:
        for row in csv.DictReader(f):
            key = row['channel'] + '-phase' + row['phase']
            sample = (int(row['nano_time']), int(row['cpu_work_ns']))
            buckets.setdefault(key, []).append(sample)
            if row['phase'] in ('2', '3'):
                buckets.setdefault(row['channel'] + '-moving', []).append(sample)
    result = {}
    for key, samples in buckets.items():
        values = [(b[0]-a[0])/1e6 for a,b in zip(samples, samples[1:])]
        minimum = 1 if key.endswith('-phase2') else 100
        if len(values) < minimum or min(values) <= 0: raise ValueError('Missing or unordered timing samples: ' + key)
        sorted_values = sorted(values)
        def percentile(p): return sorted_values[round((len(sorted_values)-1)*p)]
        result[key] = dict(intervals=len(values), seconds=sum(values)/1000, mean_ms=sum(values)/len(values),
            cadence_hz=1000*len(values)/sum(values), p50_ms=percentile(.5), p95_ms=percentile(.95),
            p99_ms=percentile(.99), max_ms=max(values), over33_ms=sum(v>33.333 for v in values),
            over50_ms=sum(v>50 for v in values), over100_ms=sum(v>100 for v in values))
    if set(result) != {channel + '-' + phase for channel in ('swap', 'game')
                       for phase in ('phase1', 'phase2', 'phase3', 'moving')}:
        raise ValueError('Missing stationary/approach/driving swap/game channels')
    return result


def verify(root, selection, catalog):
    root = Path(root); text = (root / 'client1-launch.log').read_text(errors='replace'); issues=[]; evidence={}
    if not complete(selection, 'client1', text): issues.append('Missing seed or measured-route completion')
    if re.search(r'\[(?:DRIVING_PERF(?:_WORLD)?|PZDrivingBench)\] FAIL ', text): issues.append('Fixture failed')
    if '[PZToolkitJavaPatches] Experimental B42.21 patch:' not in text: issues.append('Toolkit Java patches did not activate')
    if selection['options']['optimizer_enabled']:
        for marker in ('[OptimizerTrial] official cache and preload active', 'anim sets preloaded in ', 'action groups handed to the game'):
            if marker not in text: issues.append('Missing optimizer activation: ' + marker)
    elif '[OptimizerTrial] official cache and preload active' in text:
        issues.append('Control unexpectedly enabled optimizer')
    if selection['cases'] == ['drive']:
        try: evidence['timings'] = metrics(root / 'client1/driving-perf.csv')
        except (OSError,ValueError,KeyError) as error: issues.append(str(error))
        for marker in ('[DRIVING_PERF] BEGIN ', '[DRIVING_PERF] MEASURE ', '[DRIVING_PERF] END ', '[DRIVING_PERF] COMPLETE '):
            if text.count(marker) != 1: issues.append('Missing/duplicate actual route marker: ' + marker)
    evidence['limits']=['macOS swap-completion cadence, not compositor presentation or Windows FPS.',
        'Same saved starting world; distant new chunks and stochastic NPC simulation may diverge. Inspect manifest for available mod subset.']
    return dict(issues=issues, outcomes=[dict(actor='client1',case=selection['cases'][0],
        status='failed' if issues else 'captured' if selection['cases']==['drive'] else 'passed', reason='; '.join(issues))],evidence=evidence)
