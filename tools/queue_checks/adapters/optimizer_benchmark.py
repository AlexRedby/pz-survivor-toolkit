"""Paired isolated SP driving cadence measurement, using one sealed seed world."""
from pathlib import Path
import csv
import hashlib
import json
import math
import re
import shutil
import subprocess
import tempfile
import zipfile
import optimizer_profile


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
    callbacks = options.get('callback_profile', False)
    if type(callbacks) is not bool or callbacks and not profile:
        raise ValueError('callback_profile must be an explicit boolean and requires stage_profile')
    details = options.get('callback_detail_profile', False)
    if type(details) is not bool or details and not callbacks:
        raise ValueError('callback_detail_profile must be an explicit boolean and requires callback_profile')
    chain = options.get('callback_chain_profile', False)
    if type(chain) is not bool or chain and not details:
        raise ValueError('callback_chain_profile must be an explicit boolean and requires callback_detail_profile')
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
            root / 'tests/native_queue/optimizer-benchmark/CallbackDetails.lua',
            root / 'tools/queue_checks/callback_chain.py',
            *sorted((root / 'tests/driving_benchmark/mods').rglob('*.lua')),
            root / 'tests/optimizer_trial/java/Main.java', root / 'tests/optimizer_trial/java/mod.info.template',
            root / 'tests/optimizer_trial/candidate-manifest.json', root / 'tools/prepare_optimizer_trial.py',
            root / 'tools/optimizer_profile.py', root / 'tools/check_optimizer_compatibility.py',
            root / 'tests/native_queue/support/viewport/Main.java',
            root / 'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/VehicleDashboardTextures.lua',
            Path(selection['options']['optimizer_archive'])]


def stage_callback_details(project, cache, mod):
    """Instrument only the owned snapshot; atomic replacement cannot write through a hard link."""
    project, cache, mod = map(Path, (project, cache, mod))
    target = cache / 'mods/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/VehicleLightDashboard.lua'
    if target.is_symlink() or not target.is_file() or not target.resolve().is_relative_to(cache.resolve()):
        raise ValueError('Callback details require the owned Toolkit dashboard snapshot')
    if not mod.resolve().is_relative_to(cache.resolve()):
        raise ValueError('Callback details require the owned probe mod')
    before = hashlib.sha256(target.read_bytes()).hexdigest()
    text = target.read_text()
    anchor = '        original(self, ...)\n        D.bind(self)'
    if text.count(anchor) != 1:
        raise ValueError('Callback details Toolkit dashboard boundary changed')
    replacement = '        PZDrivingCallbackCall(original, self, ...)\n        D.bind(self)'
    temporary = target.with_name(target.name + '.callback-details.tmp')
    if temporary.exists():
        raise ValueError('Callback details temporary file already exists')
    temporary.write_text(text.replace(anchor, replacement))
    temporary.replace(target)
    destination = mod / 'media/lua/client/ZZZDrivingCallbackDetails.lua'
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(project / 'tests/native_queue/optimizer-benchmark/CallbackDetails.lua', destination)
    receipt = dict(format=1, replacements=1, source=target.relative_to(cache).as_posix(),
                   before_sha256=before, after_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
                   helper=destination.relative_to(cache).as_posix(),
                   helper_sha256=hashlib.sha256(destination.read_bytes()).hexdigest())
    (cache / 'callback-details-staging.json').write_text(json.dumps(receipt, sort_keys=True) + '\n')
    return receipt


def verify_callback_details(cache):
    cache = Path(cache)
    receipt = json.loads((cache / 'callback-details-staging.json').read_text())
    expected = {'format', 'replacements', 'source', 'before_sha256', 'after_sha256', 'helper', 'helper_sha256'}
    if (not isinstance(receipt, dict) or set(receipt) != expected or receipt['format'] != 1
            or receipt['replacements'] != 1 or any(not isinstance(receipt[key], str)
            or re.fullmatch('[0-9a-f]{64}', receipt[key]) is None
            for key in ('before_sha256', 'after_sha256', 'helper_sha256'))):
        raise ValueError('Invalid callback detail staging receipt')
    paths = dict(source='mods/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/VehicleLightDashboard.lua',
                 helper='mods/PZDrivingPerfProbe/42/media/lua/client/ZZZDrivingCallbackDetails.lua')
    for key, expected_path in paths.items():
        path = cache / expected_path
        if (receipt[key] != expected_path or path.is_symlink() or not path.is_file()
                or not path.resolve().is_relative_to(cache.resolve())
                or hashlib.sha256(path.read_bytes()).hexdigest() != receipt['after_sha256' if key == 'source' else 'helper_sha256']):
            raise ValueError('Callback detail staged source changed: ' + key)
    source = (cache / paths['source']).read_text()
    if source.count('        PZDrivingCallbackCall(original, self, ...)\n        D.bind(self)') != 1:
        raise ValueError('Callback detail staged source boundary changed')
    return receipt


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
    if selection['options'].get('callback_profile', False):
        guards['se/krka/kahlua/integration/LuaCaller.class'] = '0443930027e8f312ae9cb192c628f4b6c10743204597c508f8693cfd7bd79d0b'
    with zipfile.ZipFile(game / 'projectzomboid.jar') as z:
        for name, expected in guards.items():
            if hashlib.sha256(z.read(name)).hexdigest() != expected:
                raise ValueError('Unsupported native input: ' + name)
    optimizer_profile.stage_viewport(project, output / 'optimizer-benchmark-inputs', game, jdk, runtime,
                                     manifest['native_guards'])
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
    if selection['options'].get('callback_detail_profile', False):
        runtime['fixture']['callback_details'] = stage_callback_details(project, cache, mod)
    if selection['options'].get('callback_chain_profile', False):
        from queue_checks import callback_chain
        runtime['fixture']['callback_chain'] = callback_chain.stage(cache)
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
    if selection['options'].get('callback_profile', False):
        props['pz.drivingPerf.callbackProfile'] = 'true'
    if selection['options'].get('callback_detail_profile', False):
        props['pz.drivingPerf.callbackDetailProfile'] = 'true'
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



STAGES = ('logic', 'render', 'chunk', 'loot', 'lua', 'tiles', 'ui')
DETAILS = ('fog', 'translucent_total', 'translucent_merge', 'translucent_sort')
STAGE_COLUMNS = ('frame_id', 'phase', 'contacts', 'speed_kmh', 'nano_start', 'nano_end', 'wall_ns', 'cpu_ns') + tuple(
    stage + suffix for stage in STAGES for suffix in ('_inclusive_ns', '_exclusive_ns', '_calls')) + (
    'other_exclusive_ns',) + tuple(stage + suffix for stage in DETAILS
                                 for suffix in ('_inclusive_ns', '_exclusive_ns', '_calls'))
STAGE_CAPACITY = 120000


def _stage_integer(value, label, minimum=None, maximum=(1 << 63) - 1):
    if not isinstance(value, str) or not re.fullmatch(r'-?(?:0|[1-9][0-9]*)', value):
        raise ValueError('Invalid stage integer: ' + label)
    parsed = int(value)
    if parsed < (-(1 << 63) if minimum is None else minimum) or parsed > maximum:
        raise ValueError('Out-of-range stage integer: ' + label)
    return parsed


def _stage_jfr_chunks(path):
    # Validate complete JFR chunk bounds without loading the recording or depending on
    # a locally configured JDK CLI. Event payloads/counts are not decoded here.
    size = path.stat().st_size
    chunks, offset = 0, 0
    with path.open('rb') as stream:
        while offset < size:
            stream.seek(offset)
            header = stream.read(68)
            if len(header) != 68 or header[:4] != b'FLR\0' or int.from_bytes(header[4:6], 'big') != 2:
                raise ValueError('Invalid stage JFR chunk header')
            length = int.from_bytes(header[8:16], 'big')
            if length <= 68 or length > size - offset:
                raise ValueError('Incomplete stage JFR chunk')
            offset += length
            chunks += 1
    if not chunks:
        raise ValueError('Empty stage JFR recording')
    return chunks


def stage_metrics(cache):
    """Validate bounded completed-frame diagnostics; these are wall attribution, not an A/B result."""
    cache = Path(cache)
    paths = {name: cache / ('driving-stages.' + name) for name in ('csv', 'jfr')}
    status_path = cache / 'driving-stages-status.txt'
    for path in (*paths.values(), status_path):
        if not path.is_file():
            raise ValueError('Missing stage profile artifact: ' + path.name)
    status_text = status_path.read_text()
    status = {}
    if len(status_text.splitlines()) != 1:
        raise ValueError('Invalid stage status record')
    for token in status_text.split():
        if token.count('=') != 1:
            raise ValueError('Invalid stage status field')
        key, value = token.split('=')
        if not key or not value or key in status:
            raise ValueError('Duplicate/empty stage status field')
        status[key] = value
    required_status = {
        'diagnostic': 'none', 'phase_contacts_speed': 'snapshot-at-frame-begin',
        'exclusive_plus_other': 'wall', 'inclusive': 'category-union-nonadditive',
        'detail': 'independent-nonadditive', 'fog': 'renderFog-whole',
        'translucent_total': 'whole-method',
        'translucent_merge': 'after-tempSquares-clear-to-doSort-including-profiler-and-sort-arguments',
        'translucent_sort': 'TimSort.doSort-call', 'partial-details-on-throwable': 'included'}
    if any(status.get(key) != value for key, value in required_status.items()):
        raise ValueError('Incomplete/invalid stage profile status or detail boundaries')
    if status.get('cpu_supported_and_enabled') not in ('true', 'false'):
        raise ValueError('Invalid stage CPU availability status')
    completed = _stage_integer(status.get('complete_frames'), 'complete_frames', 1, STAGE_CAPACITY)
    omitted = _stage_integer(status.get('omitted_incomplete_frames'), 'omitted_incomplete_frames', 0)
    jfr_chunks = _stage_jfr_chunks(paths['jfr'])

    def empty_group():
        return {'frames': 0, 'frame_wall_ms': 0, 'detail_wall': {
            stage: {'inclusive_ms': 0, 'exclusive_ms': 0, 'calls': 0, 'max_frame_inclusive_ms': 0}
            for stage in DETAILS}}

    groups = {name: empty_group() for name in ('overall', 'phase1', 'phase2', 'phase3')}
    previous = None
    with paths['csv'].open(newline='') as source:
        reader = csv.DictReader(source, strict=True)
        if reader.fieldnames != list(STAGE_COLUMNS):
            raise ValueError('Invalid stage CSV columns/order')
        for index, raw in enumerate(reader, 1):
            if index > STAGE_CAPACITY or set(raw) != set(STAGE_COLUMNS) or any(value is None for value in raw.values()):
                raise ValueError('Stage CSV row shape/capacity mismatch')
            row = {key: _stage_integer(value, key) for key, value in raw.items() if key != 'speed_kmh'}
            try:
                speed = float(raw['speed_kmh'])
            except (ValueError, TypeError) as error:
                raise ValueError('Invalid stage speed') from error
            if not math.isfinite(speed) or speed < 0:
                raise ValueError('Nonfinite/negative stage speed')
            if not 1 <= row['frame_id'] <= STAGE_CAPACITY or row['phase'] not in (1, 2, 3) or not 0 <= row['contacts'] <= (1 << 31) - 1:
                raise ValueError('Invalid stage frame identity/phase/contacts')
            if row['wall_ns'] <= 0 or row['nano_end'] - row['nano_start'] != row['wall_ns'] or row['cpu_ns'] < -1:
                raise ValueError('Invalid stage frame wall/CPU timing')
            if status['cpu_supported_and_enabled'] == 'false' and row['cpu_ns'] != -1:
                raise ValueError('Stage CPU timing contradicts unavailable status')
            if previous and (row['frame_id'] <= previous['frame_id'] or row['nano_start'] < previous['nano_end']
                             or row['phase'] < previous['phase'] or row['contacts'] < previous['contacts']):
                raise ValueError('Unordered stage frames/timestamps/phase/contacts')
            for stage in (*STAGES, *DETAILS):
                inclusive, exclusive, calls = (row[stage + suffix] for suffix in ('_inclusive_ns', '_exclusive_ns', '_calls'))
                if not 0 <= exclusive <= inclusive <= row['wall_ns'] or not 0 <= calls <= (1 << 31) - 1:
                    raise ValueError('Invalid stage timing/call bounds: ' + stage)
                if calls == 0 and (inclusive or exclusive):
                    raise ValueError('Stage timing without a call: ' + stage)
            if row['other_exclusive_ns'] < 0 or sum(row[stage + '_exclusive_ns'] for stage in STAGES) + row['other_exclusive_ns'] != row['wall_ns']:
                raise ValueError('Stage exclusive partition does not equal frame wall')
            total = row['translucent_total_inclusive_ns']
            if (total != row['translucent_total_exclusive_ns'] + row['translucent_merge_inclusive_ns'] + row['translucent_sort_inclusive_ns']
                    or row['translucent_merge_exclusive_ns'] != row['translucent_merge_inclusive_ns']
                    or row['translucent_sort_exclusive_ns'] != row['translucent_sort_inclusive_ns']
                    or row['translucent_sort_calls'] > row['translucent_merge_calls']
                    or row['translucent_merge_calls'] > row['translucent_total_calls']):
                raise ValueError('Invalid translucent detail nesting/counts')
            for name in ('overall', 'phase' + str(row['phase'])):
                group = groups[name]
                group['frames'] += 1
                group['frame_wall_ms'] += row['wall_ns'] / 1e6
                for stage, values in group['detail_wall'].items():
                    values['inclusive_ms'] += row[stage + '_inclusive_ns'] / 1e6
                    values['exclusive_ms'] += row[stage + '_exclusive_ns'] / 1e6
                    values['calls'] += row[stage + '_calls']
                    values['max_frame_inclusive_ms'] = max(values['max_frame_inclusive_ms'], row[stage + '_inclusive_ns'] / 1e6)
            previous = row
    if groups['overall']['frames'] != completed:
        raise ValueError('Stage CSV/status complete frame count mismatch')
    for group in groups.values():
        for values in group['detail_wall'].values():
            values['mean_per_frame_inclusive_ms'] = values['inclusive_ms'] / group['frames'] if group['frames'] else None
    return {'complete_frames': completed, 'omitted_incomplete_frames': omitted, 'jfr_chunks': jfr_chunks,
            'attribution': 'Owner-thread elapsed wall time. Detail timers use an independent stack; inclusive totals are nonadditive.',
            'groups': groups,
            'limits': ['Fog is the whole renderFog method, including its early exits; timing does not establish visible fog.',
                       'Translucent total includes preparation and drawing. Merge includes native profiler and sort argument preparation; sort is the exact doSort call.',
                       'Instrumentation/JFR add overhead. These timings do not establish per-stage CPU cost or optimization gain.',
                       'JFR chunk bounds are validated; JFR event payloads/counts are not decoded. CSV counts agree with the completed-frame status.']}


def verify(root, selection, catalog):
    root = Path(root); text = (root / 'client1-launch.log').read_text(errors='replace'); issues=[]; evidence={}
    if not complete(selection, 'client1', text): issues.append('Missing seed or measured-route completion')
    if re.search(r'\[(?:DRIVING_PERF(?:_WORLD)?|PZDrivingBench)\] FAIL ', text): issues.append('Fixture failed')
    if '[PZToolkitJavaPatches] Experimental B42.21 patch:' not in text: issues.append('Toolkit Java patches did not activate')
    if selection['options'].get('callback_detail_profile') is True:
        functions = 17 if selection['options'].get('callback_chain_profile') is True else 6
        if text.count('[DRIVING_PERF] CALLBACK_DETAILS_INSTALLED functions=' + str(functions)) != 1:
            issues.append('Missing/duplicate diagnostic callback detail installation')
        try: evidence['callback_detail_staging'] = verify_callback_details(root / 'client1')
        except (OSError, ValueError, KeyError): issues.append('Missing/invalid callback detail staging receipt')
    if selection['options'].get('callback_chain_profile') is True:
        from queue_checks import callback_chain
        try: evidence['callback_chain_staging'] = callback_chain.verify(root / 'client1')
        except (OSError, ValueError, KeyError): issues.append('Missing/invalid callback chain staging receipt')
    if selection['options']['optimizer_enabled']:
        for marker in ('[OptimizerTrial] official cache and preload active', 'anim sets preloaded in ', 'action groups handed to the game'):
            if marker not in text: issues.append('Missing optimizer activation: ' + marker)
    elif '[OptimizerTrial] official cache and preload active' in text:
        issues.append('Control unexpectedly enabled optimizer')
    if selection['cases'] == ['drive']:
        try: evidence['timings'] = metrics(root / 'client1/driving-perf.csv')
        except (OSError,ValueError,KeyError) as error: issues.append(str(error))
        if selection['options'].get('stage_profile') is True:
            try: evidence['stage_timings'] = stage_metrics(root / 'client1')
            except (OSError, ValueError, KeyError, csv.Error) as error: issues.append('Stage profile: ' + str(error))
        if selection['options'].get('callback_profile') is True:
            from queue_checks.callback_metrics import callback_metrics
            try:
                evidence['callback_timings'] = callback_metrics(root / 'client1')
                expected_details = 'enabled' if selection['options'].get('callback_detail_profile') is True else 'disabled'
                if evidence['callback_timings']['detail_spans'] != expected_details:
                    raise ValueError('Callback detail status differs from requested profile')
            except (OSError, ValueError, KeyError, csv.Error) as error: issues.append('Callback profile: ' + str(error))
        for marker in ('[DRIVING_PERF] BEGIN ', '[DRIVING_PERF] MEASURE ', '[DRIVING_PERF] END ', '[DRIVING_PERF] COMPLETE '):
            if text.count(marker) != 1: issues.append('Missing/duplicate actual route marker: ' + marker)
    evidence['limits']=['macOS swap-completion cadence, not compositor presentation or Windows FPS.',
        'Same saved starting world; distant new chunks and stochastic NPC simulation may diverge. Inspect manifest for available mod subset.']
    return dict(issues=issues, outcomes=[dict(actor='client1',case=selection['cases'][0],
        status='failed' if issues else 'captured' if selection['cases']==['drive'] else 'passed', reason='; '.join(issues))],evidence=evidence)
