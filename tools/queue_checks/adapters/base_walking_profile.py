"""Test-only full-frame and native-walking capture in one isolated menu Host client."""
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

PREFIX = '[BASE_WALK] '
MOD_ID = 'PZBaseWalkingProfile'
REQUIRED = {'ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit'}
STAGES = ('logic', 'render', 'chunk', 'loot', 'lua', 'tiles', 'ui')
NATIVE_HASHES = {
    'zombie/GameWindow.class': 'c3a3583923191b6aea23a74e6b05e2b53302bbcded7f89cae930e364a409dfb2',
    'zombie/iso/IsoChunk.class': '5048becc3f46f746686513d4dcadb137e6e11bfd44617075f41923b3db11650a',
    'zombie/inventory/ItemPickerJava.class': '5c8cf626e46a52cdbd9d73e9de10766dece3388ee3e4f4d8d071df5e44d68522',
    'se/krka/kahlua/vm/KahluaThread.class': '25f4c0dea91800dcb3fadd3d482ed5f7d5cf17908bf167afd308b85c99856bb6',
    'zombie/iso/fboRenderChunk/FBORenderCell.class': 'd5c46201d60cff36397ee46c56b53dbaee6e26e8733836f27bf56ad871eedf94',
    'zombie/ui/UIManager.class': 'fa9a2ec9388573f74082a22f3f357c08f3b0e662325ba4ea587b03a5de005704',
    'org/lwjglx/opengl/Display.class': '15a0c0a3646d4340cd96c47d143a5605bfbae7543410ddaa018e83f45ae1a578',
}
DISCOVERY_NATIVE_HASHES = {
    'zombie/inventory/ItemContainer.class': 'a2ac7dd6235f91255dc57b91419a2c8609bdb105214cddf7fb445b70507b6f96',
}


def definitions():
    return {'base-walking-profile': {'status': 'ready', 'clients': 1,
        'default_mods': ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit'],
        'cases': [dict(id='walk', producer='fixture', capability='capture', kinds=['mp'],
                       modes=['toolkit'], languages=['EN', 'RU'])]}}


def _sandbox(selection):
    value = selection.get('options', {}).get('external_sandbox_path')
    if not isinstance(value, str) or not Path(value).is_absolute():
        raise ValueError('base-walking-profile requires absolute options.external_sandbox_path')
    path = Path(value)
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= 1024 * 1024:
        raise ValueError('External sandbox must be a nonempty regular file <= 1 MiB')
    return path.resolve()


def validate(selection):
    options = selection.get('options', {})
    if (selection.get('cases') != ['walk'] or selection.get('kind') != 'mp'
            or selection.get('mode') != 'toolkit' or type(selection.get('clients')) is not int
            or selection['clients'] != 1 or selection.get('languages') not in (['EN'], ['RU'])
            or not REQUIRED <= set(selection.get('mods', [])) or MOD_ID in selection['mods']
            or options.get('mp_host') is not True):
        raise ValueError('Base walking requires Toolkit, one EN/RU menu Host client and case walk')
    if not options.get('world_template') or not options.get('pack_lock'):
        raise ValueError('Base walking requires an explicit sealed world_template and pack_lock')
    if options.get('optimizer_archive') or options.get('optimizer_enabled'):
        raise ValueError('Base walking profile does not stage gameplay optimizers')
    if not isinstance(options.get('base_walking', {}), dict):
        raise ValueError('options.base_walking must be an object')
    if options.get('base_walking', {}).get('ground_highlight_bridge') not in (None, 'lua', 'native'):
        raise ValueError('ground_highlight_bridge must be lua or native when supplied')
    if type(options.get('base_walking', {}).get('disable_newmusic_inventory_probe', False)) is not bool:
        raise ValueError('NewMusic probe control must be boolean')
    if type(options.get('base_walking', {}).get('verify_toolkit_newmusic_control', False)) is not bool:
        raise ValueError('Toolkit NewMusic verification must be boolean')
    if type(options.get('base_walking', {}).get('inventory_discovery_profile', False)) is not bool:
        raise ValueError('Inventory discovery profile must be boolean')
    if type(options.get('base_walking', {}).get('inventory_refresh_checks', False)) is not bool:
        raise ValueError('Inventory refresh checks must be boolean')
    if (options.get('base_walking', {}).get('inventory_refresh_checks')
            and not options.get('base_walking', {}).get('inventory_discovery_profile')):
        raise ValueError('Inventory refresh checks require discovery profiling')
    if type(options.get('base_walking', {}).get('inventory_button_checks', False)) is not bool:
        raise ValueError('Inventory button checks must be boolean')
    if (options.get('base_walking', {}).get('inventory_button_checks')
            and not options.get('base_walking', {}).get('inventory_discovery_profile')):
        raise ValueError('Inventory button checks require discovery profiling')
    if (options.get('base_walking', {}).get('verify_toolkit_newmusic_control')
            and options.get('base_walking', {}).get('disable_newmusic_inventory_probe')):
        raise ValueError('Toolkit verification must not remove callbacks through the fixture')
    _sandbox(selection)


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    fixture = root / 'contributions/base-walking-profile'
    return [*sorted((fixture / 'java').glob('*.java')), *sorted((fixture / 'client').rglob('*.lua')),
            *sorted((fixture / 'server').rglob('*.lua')),
            *sorted((root / 'startup').rglob('*.lua')), _sandbox(selection)]


def _clean_env():
    return {key: value for key, value in os.environ.items()
            if key not in ('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS')}


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    project, output, game, jdk = map(Path, (project, output, game, jdk))
    root = project / 'tests/native_queue'
    fixture = root / 'contributions/base-walking-profile'
    java_sources = [fixture / 'java' / name for name in ('Main.java', 'StageProfiler.java')]
    if selection['options'].get('base_walking', {}).get('disable_newmusic_inventory_probe'):
        probe = Path(locations['NewMusic']) / '42/media/lua/client/runtime/NMClientVanillaDiscVisibleProbe.lua'
        if hashlib.sha256(probe.read_bytes()).hexdigest() != '9fe6ba4ff341a16d1f4ef3810835cba4e984a6c6e414574cbba7326406f6006c':
            raise ValueError('NewMusic probe control requires the reviewed exact source')
    clients = sorted((fixture / 'client').glob('*.lua'))
    if not clients or any(not path.is_file() for path in java_sources):
        raise ValueError('Base walking Java observer/client scenario is missing')
    discovery = selection['options'].get('base_walking', {}).get('inventory_discovery_profile', False)
    native_hashes = {**NATIVE_HASHES, **(DISCOVERY_NATIVE_HASHES if discovery else {})}
    with zipfile.ZipFile(game / 'projectzomboid.jar') as archive:
        for name, expected in native_hashes.items():
            if hashlib.sha256(archive.read(name)).hexdigest() != expected:
                raise ValueError('Unsupported base walking native input: ' + name)
    classpath = os.pathsep.join(str(game / name) for name in ('projectzomboid.jar', 'ZombieBuddy.jar'))
    with tempfile.TemporaryDirectory(prefix='pz-base-walking-observer-') as temporary:
        build = Path(temporary)
        subprocess.run([str(jdk / 'bin/javac'), '--release', '25', '-cp', classpath, '-d', str(build),
                        *map(str, java_sources)], check=True, capture_output=True, text=True, timeout=60,
                       env=_clean_env())
        for settings in runtime['roles'].values():
            cache = Path(settings['cache'])
            lua = cache / 'mods/ActionQueueTest/42/media/lua'
            for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
                shutil.copy2(root / 'startup' / side / name, lua / side / name)
            for path in clients:
                shutil.copy2(path, lua / 'client' / path.name)
            for path in sorted((fixture / 'server').glob('*.lua')):
                shutil.copy2(path, lua / 'server' / path.name)
            mod = cache / 'mods' / MOD_ID
            (mod / 'common').mkdir(parents=True)
            version = mod / '42'
            (version / 'media/java').mkdir(parents=True)
            (version / 'mod.info').write_text('name=Disposable base walking frame observer\n'
                'id=' + MOD_ID + '\nversion=0.0.1\nversionMin=42.21\nversionMax=42.21\n'
                'require=\\ZombieBuddy\nZBVersionMin=2.3.4\njavaPkgName=toolkit.basewalking\n'
                'javaJarFile=media/java/' + MOD_ID + '.jar\n')
            with zipfile.ZipFile(version / 'media/java' / (MOD_ID + '.jar'), 'w', zipfile.ZIP_DEFLATED) as jar:
                for path in sorted(build.rglob('*.class')):
                    if not discovery and path.name.startswith('Main$Floor'):
                        continue
                    jar.write(path, path.relative_to(build).as_posix())
    client = runtime['roles']['client1']
    cache, classes = Path(client['cache']), Path(client['classes'])
    launcher = classes / 'ToolkitSmokeLauncher.java'
    text = launcher.read_text()
    anchor = 'public static void main(String[] args) throws Exception {'
    if text.count(anchor) != 1 or 'pz.baseWalking.enabled' in text:
        raise ValueError('Private launcher main changed or observer already staged')
    props = {'pz.baseWalking.enabled': 'true', 'pz.baseWalking.cachedir': str(cache.resolve())}
    assignments = '\n'.join('System.setProperty(' + json.dumps(key) + ', ' + json.dumps(value) + ');'
                            for key, value in props.items())
    launcher.write_text(text.replace(anchor, anchor + '\n' + assignments))
    subprocess.run([str(jdk / 'bin/javac'), '--release', '25', '-cp', str(game / 'projectzomboid.jar'),
                    str(classes / 'ToolkitWindowBootstrap.java'), str(launcher)],
                   check=True, capture_output=True, text=True, timeout=60, env=_clean_env())
    server = output / 'server/Server'
    shutil.copy2(_sandbox(selection), server / 'queue-smoke_SandboxVars.lua')
    settings_path = server / 'queue-smoke.ini'
    text = settings_path.read_text()
    for key, value in {'Map': 'Muldraugh, KY', 'PVP': 'false', 'DoLuaChecksum': 'true',
                       'SleepAllowed': 'true', 'SleepNeeded': 'false'}.items():
        text = re.sub(r'^' + key + r'=.*\n?', '', text, flags=re.M).rstrip('\n') + '\n' + key + '=' + value + '\n'
    settings_path.write_text(text)
    runtime.setdefault('fixture', {}).setdefault('mods', []).append(MOD_ID)
    runtime['fixture'].update(server_ready='[STARTUP_TEST] SERVER_READY', failure_markers=[PREFIX + 'FAIL '])
    receipt = {'test_only': True, 'native_hashes': native_hashes,
               'java_sources': {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in java_sources},
               'sandbox_sha256': hashlib.sha256(_sandbox(selection).read_bytes()).hexdigest(),
               'client_properties': props, 'observer_mod': MOD_ID, 'optimizer_staged': False}
    (output / 'base-walking-observer-inputs.json').write_text(json.dumps(receipt, indent=2) + '\n')


def _raw(text, marker):
    values = [json.loads(match.group(1)) for match in re.finditer(re.escape(PREFIX + marker + ' ') + r'([^\r\n]+)', text)]
    if any(not isinstance(value, dict) for value in values):
        raise ValueError('Invalid base walking ' + marker + ' JSON record')
    return values


def complete(selection, role, text):
    try:
        records = _raw(text, 'COMPLETE')
        return role == 'client1' and len(records) == 1 and records[0].get('case') == 'walk'
    except (TypeError, ValueError):
        return False


def _number(value):
    return type(value) in (int, float) and math.isfinite(value)


def _phases(text, options):
    phases, movement, done = _raw(text, 'PHASE'), _raw(text, 'MOVEMENT'), _raw(text, 'COMPLETE')
    if [row.get('phase') for row in phases] != [1, 2, 3] or [row.get('name') for row in phases] != ['stationary', 'walking', 'post-stationary']:
        raise ValueError('Missing ordered stationary/walking/post-stationary phase records')
    for row in phases:
        if (any(not _number(row.get(key)) or row[key] < 0 for key in ('elapsedMs', 'distance'))
                or any(type(row.get(key)) is not int or row[key] < 0 for key in ('samples', 'tileChanges', 'movementTicks'))
                or row['samples'] == 0):
            raise ValueError('Invalid base walking phase counters')
    if any(row['elapsedMs'] < 20000 or row['distance'] >= 1 for row in (phases[0], phases[2])):
        raise ValueError('Stationary baseline/post interval missing or actor moved')
    walk = phases[1]
    if (walk['elapsedMs'] < 60000 or walk['tileChanges'] < options.get('minimum_tile_changes', 12)
            or walk['distance'] < options.get('minimum_distance', 15)
            or walk['movementTicks'] < 10 or len(movement) < options.get('minimum_legs', 4)):
        raise ValueError('Insufficient actual walking evidence')
    for index, row in enumerate(movement, 1):
        if (row.get('leg') != index or row.get('action') != 'ISWalkToTimedAction' or row.get('reached') is not True
                or not _number(row.get('distance')) or row['distance'] <= 0):
            raise ValueError('Invalid native completed walking leg')
        for endpoint in ('start', 'finish'):
            position = row.get(endpoint)
            if not isinstance(position, dict) or any(not _number(position.get(key)) for key in ('x', 'y', 'z')):
                raise ValueError('Missing actual leg endpoint coordinates')
        if math.dist([row['start'][key] for key in ('x', 'y', 'z')], [row['finish'][key] for key in ('x', 'y', 'z')]) < .5:
            raise ValueError('Completed walking leg lacks displacement')
    if len(done) != 1 or done[0].get('phases') != 3 or done[0].get('legs') != len(movement):
        raise ValueError('Completion counters differ from captured phases/legs')
    return phases, movement, done[0]


def _profile(cache, text, jdk):
    csv_path = cache / 'base-walking-stages.csv'
    jfr_path = cache / 'base-walking-stages.jfr'
    status_path = cache / 'base-walking-stages-status.txt'
    for path in (csv_path, jfr_path, status_path):
        if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
            raise ValueError('Missing regular profile artifact: ' + path.name)
    status = status_path.read_text()
    if not re.search(r'\bdiagnostic=none(?:\s|$)', status):
        raise ValueError('Native frame profiler has an instrumentation diagnostic')
    raw = list(csv.DictReader(csv_path.open()))
    if not raw:
        raise ValueError('No complete native frame samples')
    rows = [{key: float(value) if key == 'speed_kmh' else int(value) for key, value in row.items()} for row in raw]
    for row in rows:
        if (row['phase'] not in (1, 2, 3) or row['wall_ns'] != row['nano_end'] - row['nano_start'] or row['wall_ns'] <= 0
                or sum(row[stage + '_exclusive_ns'] for stage in STAGES) + row['other_exclusive_ns'] != row['wall_ns']
                or any(not 0 <= row[stage + '_exclusive_ns'] <= row[stage + '_inclusive_ns'] <= row['wall_ns'] for stage in STAGES)
                or row['cpu_ns'] < -1):
            raise ValueError('Native stage timing/partition invariant failed')
    if any(a['frame_id'] >= b['frame_id'] or a['nano_end'] > b['nano_start'] for a, b in zip(rows, rows[1:])):
        raise ValueError('Native frame identity/timestamps are unordered')
    if set(row['phase'] for row in rows) != {1, 2, 3}:
        raise ValueError('Native profile does not contain all three phases')
    count = re.search(r'\bcomplete_frames=(\d+)\b', status)
    omitted = re.search(r'\bomitted_incomplete_frames=(\d+)\b', status)
    if not count or int(count[1]) != len(rows) or not omitted or int(omitted[1]) not in (0, 1):
        raise ValueError('Native frame status counters differ')
    hooks = re.findall(r'\[BASE_WALKING_PROFILE\] HOOK_COUNTS stage=(\w+) advice_observed=(true|false) calls=(\d+)', text)
    if [stage for stage, _, _ in hooks] != list(STAGES):
        raise ValueError('Missing native stage hook counters')
    for stage, observed, calls in hooks:
        if int(calls) != sum(row[stage + '_calls'] for row in rows) or int(calls) > 0 and observed != 'true':
            raise ValueError('Native stage hook counters differ: ' + stage)
    for stage in ('logic', 'render', 'lua', 'ui'):
        if not any(name == stage and int(calls) > 0 for name, _, calls in hooks):
            raise ValueError('Active frame stage hook was not observed: ' + stage)
    if ('[BASE_WALKING_PROFILE] HOOK_ACTIVE method=GameWindow.frameStep' not in text
            or '[BASE_WALKING_PROFILE] HOOK_ACTIVE method=Display.swapBuffers' not in text
            or not re.search(r'\[BASE_WALKING_PROFILE\] COMPLETE frame_hook=true swap_hook=true ', text)):
        raise ValueError('Actual frame/swap hook activation evidence missing')
    if jfr_path.read_bytes()[:4] != b'FLR\x00':
        raise ValueError('Native JFR artifact has an invalid header')
    result = subprocess.run([str(jdk / 'bin/jfr'), 'summary', str(jfr_path)], check=True,
                            capture_output=True, text=True, timeout=30, env=_clean_env())
    frame_event = re.search(r'^\s*pz\.baseWalking\.Frame\s+(\d+)\s+\d+\s*$', result.stdout, re.M)
    swap_event = re.search(r'^\s*pz\.baseWalking\.Swap\s+(\d+)\s+\d+\s*$', result.stdout, re.M)
    if not frame_event or int(frame_event[1]) != len(rows) or not swap_event or int(swap_event[1]) == 0:
        raise ValueError('Readable JFR frame/swap event counts differ from capture')
    return rows, {'complete_frames': len(rows), 'omitted_incomplete_frames': int(omitted[1]),
                  'swap_events': int(swap_event[1]), 'status': status.strip(),
                  'artifacts': {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                                for path in (csv_path, jfr_path, status_path)}}


def _motion(cache, frames):
    path = cache / 'Lua/base-walking-motion.jsonl.txt'
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size < 64 * 1024 * 1024:
        raise ValueError('Missing bounded native motion JSONL')
    rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    if not rows or len(rows) > 120000:
        raise ValueError('Native motion sample count outside bounds')
    ids = {row['frame_id'] for row in frames}
    for row in rows:
        if (not isinstance(row, dict) or any(not _number(row.get(key)) for key in ('t', 'x', 'y'))
                or type(row.get('frame')) is not int or row['frame'] <= 0
                or type(row.get('tileChanged')) is not bool or type(row.get('moving')) is not bool):
            raise ValueError('Invalid native motion sample')
    if any(a['t'] > b['t'] or a['frame'] > b['frame'] for a, b in zip(rows, rows[1:])):
        raise ValueError('Native motion timeline is unordered')
    unmatched = {row['frame'] for row in rows} - ids
    if unmatched - {max(ids) + 1}:
        raise ValueError('Motion references an unrecorded interior frame')
    return {'samples': len(rows), 'tile_changes': sum(row['tileChanged'] for row in rows),
            'moving_samples': sum(row['moving'] for row in rows),
            'unmatched_closing_frames': sorted(unmatched), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def _callbacks(cache, frames):
    path = cache / 'base-walking-lua-callbacks.csv'
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size < 16 * 1024 * 1024:
        raise ValueError('Missing bounded Lua callback timing CSV')
    with path.open() as source:
        rows = list(csv.DictReader(source))
    counts = {phase: 0 for phase in (1, 2, 3)}
    for row in rows:
        phase = int(row['phase'])
        calls, inclusive, exclusive, maximum = (int(row[key]) for key in
            ('calls', 'inclusive_ns', 'exclusive_ns', 'max_inclusive_ns'))
        if (phase not in counts or not row['source'] or not row['function'] or calls <= 0
                or not 0 <= exclusive <= inclusive or not 0 <= maximum <= inclusive):
            raise ValueError('Invalid Lua callback timing row')
        counts[phase] += calls
    expected = {phase: sum(row['lua_calls'] for row in frames if row['phase'] == phase)
                for phase in counts}
    if counts != expected or not all(counts.values()):
        raise ValueError('Lua callback counts differ from native stage hooks')
    status = (cache / 'base-walking-stages-status.txt').read_text()
    if not re.search(r'\blua_callback_overflow_calls=0\b', status):
        raise ValueError('Lua callback label attribution overflowed')
    return {'rows': len(rows), 'calls_by_phase': counts,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def _discovery(root, text):
    records = _raw(text, 'INVENTORY_DISCOVERY')
    path = Path(root) / 'client1/Lua/base-walking-inventory-discovery.jsonl.txt'
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size < 512 * 1024:
        raise ValueError('Missing bounded regular inventory discovery artifact')
    saved = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    if records != saved:
        raise ValueError('Inventory discovery log/file receipts differ')
    begins = [row for row in records if row.get('kind') == 'begin']
    ends = [row for row in records if row.get('kind') == 'end']
    if [row.get('phase') for row in begins] != [1, 2, 3] or [row.get('phase') for row in ends] != [1, 2, 3]:
        raise ValueError('Missing ordered inventory discovery phases')
    for begin, end in zip(begins, ends):
        if (end.get('aborted') is not False or end.get('restore_conflicts') != 0
                or end.get('samples', {}).get('observer_errors') != 0
                or end.get('settings') != begin.get('settings')):
            raise ValueError('Inventory discovery observer failed or settings changed')
    timings, names = [], set()
    for row in records:
        if row.get('kind') != 'timing':
            continue
        key = (row.get('phase'), row.get('name'))
        if key in names or key[0] not in (1, 2, 3) or not isinstance(key[1], str):
            raise ValueError('Invalid or duplicate inventory discovery timing')
        names.add(key)
        if type(row.get('calls')) is not int or row['calls'] < 0 or row.get('errors') != 0:
            raise ValueError('Invalid inventory discovery call/error counts')
        values = [row.get(name) for name in ('inclusive_ms', 'exclusive_ms', 'max_ms')]
        if any(type(value) not in (int, float) or not math.isfinite(value) or value < 0 for value in values):
            raise ValueError('Invalid inventory discovery durations')
        if values[1] > values[0] + 0.001 or values[2] > values[0] + 0.001:
            raise ValueError('Inconsistent inventory discovery durations')
        if row['calls'] == 0 and any(values):
            raise ValueError('Uncalled inventory method has measured duration')
        timings.append(row)
    walking = next((row for row in timings if row['phase'] == 2 and row['name'] == 'page.refreshBackpacks.loot'), None)
    if walking is None or walking['calls'] <= 0 or ends[1].get('samples', {}).get('loot', {}).get('refreshes') != walking['calls']:
        raise ValueError('Missing measured walking loot refreshes')
    floor_path = Path(root) / 'client1/base-walking-inventory-floor.csv'
    if floor_path.is_symlink() or not floor_path.is_file() or not 0 < floor_path.stat().st_size < 64 * 1024:
        raise ValueError('Missing bounded regular native floor artifact')
    with floor_path.open() as source:
        floor = [{key: value if key == 'method' else int(value) for key, value in row.items()}
                 for row in csv.DictReader(source)]
    methods = ['AddItem(InventoryItem)', 'clear()', 'removeItemsFromProcessItems()']
    if [(row['phase'], row['method']) for row in floor] != [(phase, method) for phase in (1, 2, 3) for method in methods]:
        raise ValueError('Missing native floor method/phase counters')
    if any(row['calls'] < 0 or not 0 <= row['max_inclusive_ns'] <= row['inclusive_ns']
           or row['calls'] == 0 and row['inclusive_ns'] != 0 for row in floor):
        raise ValueError('Invalid native floor counters')
    if any(row['calls'] != walking['calls'] for row in floor if row['phase'] == 2 and row['method'] != methods[0]):
        raise ValueError('Native floor reset counts differ from walking loot refreshes')
    counts = ends[1]['samples']['loot']
    cardinalities = [counts.get('floor_items_' + suffix) for suffix in ('min', 'last', 'max')]
    if (any(type(value) is not int or value < 0 for value in cardinalities)
            or not cardinalities[0] <= cardinalities[1] <= cardinalities[2]):
        raise ValueError('Missing or invalid walking floor cardinalities')
    additions = next(row for row in floor if row['phase'] == 2 and row['method'] == methods[0])
    if cardinalities[2] > 0 and additions['calls'] == 0:
        raise ValueError('Nonempty walking floor lacks native AddItem observations')
    receipt = '[BASE_WALKING_PROFILE] INVENTORY_FLOOR csv=' + str(floor_path) + ' unclosed_scopes=0'
    if text.count(receipt) != 1:
        raise ValueError('Native floor observation scope did not close')
    return {'phases': ends, 'timings': timings, 'floor': floor, 'path': path.relative_to(root).as_posix(),
            'limits': ['Opt-in method observers add overhead; use component attribution, not absolute frame-time comparisons.']}


def _refresh_checks(text):
    records = _raw(text, 'INVENTORY_REFRESH_CHECKS')
    if len(records) != 1:
        raise ValueError('Missing unique native player inventory refresh checks')
    row = records[0]
    expected = dict(kind='inventory-refresh-checks', playerNum=0, clock='getTimestampMs',
                    warmupPerMode=8, callsPerBatch=64, rounds=3, totalCalls=384,
                    candidateCalls=192, controlCalls=192, counterModulus=10001)
    if any(type(row.get(key)) is not type(value) or row[key] != value for key, value in expected.items()):
        raise ValueError('Native player refresh workload differs')
    checks = ('hiddenPlayerDeferred', 'directPaneImmediate', 'reopenFresh',
              'visibleCollapsedPlayerLive', 'restored')
    if any(row.get('checks', {}).get(key) is not True for key in checks):
        raise ValueError('Native player refresh behavior or restoration failed')
    limits = row.get('limits', {})
    if (any(limits.get(key) is not False for key in
            ('inventoryMutation', 'worldMutation', 'movement', 'categoryMutation', 'classHooks', 'paneHooks'))
            or any(limits.get(key) is not True for key in ('timingIncludesAssertions', 'identityChecksOutsideTiming'))):
        raise ValueError('Native player refresh observer scope differs')
    workload = row.get('workload', {})
    if (any(type(workload.get(key)) is not int or workload[key] <= 0 for key in ('rawItems', 'buttons'))
            or workload.get('settings', {}).get('mode') != 'details'
            or workload.get('settings', {}).get('onCharacter') is not True):
        raise ValueError('Native player inventory workload is missing')
    projection = row.get('rowProjection', {})
    if (projection.get('matchesForcedControl') is not True
            or any(type(projection.get(key)) is not int or projection[key] <= 0 for key in ('groups', 'actualItems'))):
        raise ValueError('Native player row projection does not match forced control')
    cleanup = row.get('cleanup', {})
    if (any(cleanup.get(key) is not True for key in ('selectionRestored', 'inventoryRestored', 'forceRestored'))
            or cleanup.get('visible') is not False or type(cleanup.get('collapsed')) is not bool):
        raise ValueError('Native player UI state was not restored')
    batches = row.get('batches', {})
    if not isinstance(batches, dict) or set(batches) != {str(i) for i in range(1, 7)}:
        raise ValueError('Native player refresh batches are missing')
    times = {'candidate': [], 'control': []}
    order = ['candidate', 'control', 'control', 'candidate', 'candidate', 'control']
    for index, mode in enumerate(order, 1):
        batch = batches[str(index)]
        if (batch.get('mode') != mode or type(batch.get('round')) is not int
                or batch['round'] != (index + 1) // 2 or batch.get('calls') != 64
                or type(batch.get('elapsedMs')) is not int or batch['elapsedMs'] < 0
                or batch.get('allRowsPending') is not (mode == 'candidate')
                or batch.get('identityUnchanged') is not True):
            raise ValueError('Native player refresh batch workload or timing differs')
        before, after, builds = (batch.get(key) for key in ('rowCounterBefore', 'rowCounterAfter', 'rowCounterDelta'))
        if (any(type(value) is not int or not 0 <= value < 10001 for value in (before, after, builds))
                or (after - before) % 10001 != builds or builds != (64 if mode == 'control' else 0)):
            raise ValueError('Native player row counters do not prove the batch behavior')
        times[mode].append(batch['elapsedMs'])
    return {'receipt': row, 'median_batch_ms': {key: sorted(value)[1] for key, value in times.items()},
            'limits': ['Alternating synchronous batches compare complete refresh callbacks, not FPS or remote-client stutter.',
                       'UI correctness checks do not simulate physical input or remote inventory mutation.']}


def _button_checks(text):
    records = _raw(text, 'INVENTORY_BUTTON_CHECKS')
    if len(records) != 1:
        raise ValueError('Missing unique inventory button experiment')
    row = records[0]
    expected = dict(kind='inventory-button-checks', playerNum=0, clock='baseWalkingExperimentClockMs',
                    callsPerBatch=256, rounds=5, warmupPerMode=8, totalCalls=2560, restoreConflicts=0, sourceLimit=128)
    if any(type(row.get(key)) is not type(value) or row[key] != value for key, value in expected.items()):
        raise ValueError('Inventory button experiment workload differs')
    if (row.get('timingMethod') != 'sum of complete refreshBackpacks callback intervals; guard branch/counters included; assertions outside timing'
            or row.get('itemIdentityCheck') != 'before probe, after each warmup/mode batch, and cleanup; geometry/UI identities before and after every callback'):
        raise ValueError('Inventory button timing boundary differs')
    if any(row.get('checks', {}).get(key) is not True for key in
           ('orderedIdentities', 'geometry', 'parentsAndChildren', 'selection', 'restored')):
        raise ValueError('Inventory button model or restoration failed')
    limits = row.get('limits', {})
    if (any(limits.get(key) is not True for key in
            ('testOnly', 'assumesGeometryMirror', 'discoveryAndEventsUnchanged'))
            or any(limits.get(key) is not False for key in
                   ('movement', 'resize', 'nestedReentry', 'remoteMutation', 'classHooks', 'paneHooks',
                    'inventoryMutation', 'worldMutation'))):
        raise ValueError('Inventory button experiment scope differs')
    workload = row.get('workload', {})
    buttons, pooled, guarded = (workload.get('buttons'), workload.get('pooledButtons'), row.get('guardedButtons'))
    if (any(type(value) is not int for value in (buttons, pooled, guarded))
            or buttons <= 0 or pooled < 0 or not 0 < guarded <= buttons + pooled <= 128):
        raise ValueError('Inventory button sources missing')
    for name in ('setX', 'setY', 'getKeepOnScreen', 'onResize'):
        source = row.get('defaultSources', {}).get(name)
        if (not isinstance(source, str) or not source.endswith('/media/lua/client/ISUI/ISUIElement.lua')
                or '/mods/' in source.lower()):
            raise ValueError('Inventory button default source differs')
    sources = workload.get('sources', {})
    if not isinstance(sources, dict) or set(sources) != {str(i) for i in range(1, buttons + pooled + 1)}:
        raise ValueError('Inventory button source identities missing')
    for source in sources.values():
        if (any(not isinstance(source.get(key), str) or not source[key] for key in
                ('button', 'container', 'kind', 'luaParent', 'nativeParent'))
                or type(source.get('items')) is not int or source['items'] < 0
                or any(not _number(source.get('geometry', {}).get(key)) for key in ('x', 'y', 'width', 'height'))):
            raise ValueError('Invalid inventory button source witness')
    batches = row.get('batches', {})
    if not isinstance(batches, dict) or set(batches) != {str(i) for i in range(1, 11)}:
        raise ValueError('Inventory button batches missing')
    times = {'candidate': [], 'control': []}
    totals = {}
    for index, mode in enumerate(('candidate', 'control', 'control', 'candidate', 'candidate',
                                 'control', 'control', 'candidate', 'candidate', 'control'), 1):
        batch = batches[str(index)]
        called, skipped = (batch.get('calledSetters'), batch.get('skippedSetters'))
        if (batch.get('mode') != mode or type(batch.get('round')) is not int
                or batch['round'] != (index + 1) // 2 or batch.get('calls') != 256
                or not _number(batch.get('elapsedMs')) or batch['elapsedMs'] < 0
                or batch.get('modelUnchanged') is not True or batch.get('geometryMatched') is not True
                or any(type(value) is not int or value < 0 for value in (called, skipped))
                or called + skipped <= 0 or (skipped <= 0 if mode == 'candidate' else skipped != 0)):
            raise ValueError('Inventory button batch timing, behavior or counters differ')
        totals.setdefault(batch['round'], []).append(called + skipped)
        times[mode].append(batch['elapsedMs'])
    if any(pair[0] != pair[1] for pair in totals.values()):
        raise ValueError('Inventory button setter workloads differ')
    return {'receipt': row, 'median_batch_ms': {key: sorted(value)[2] for key, value in times.items()},
            'limits': ['Test-only geometry-mirror ablation; passing is not approval of a production cache.',
                       'Complete callback timings include identical guard/counter overhead in both modes.',
                       'No movement, resize, reentrant refresh, remote mutation or FPS qualification.']}


def verify(root, selection, catalog):
    root = Path(root)
    text = (root / 'client1-launch.log').read_text(errors='replace')
    issues, evidence = [], {}
    if not complete(selection, 'client1', text) or PREFIX + 'FAIL ' in text:
        issues.append('Missing or failed base walking completion')
    try:
        phases, legs, done = _phases(text, selection.get('options', {}).get('base_walking', {}))
        expected = str(root / 'client1/base-walking-stages.csv')
        if done.get('profile') != expected:
            raise ValueError('Profile completion path escapes the owned client cache')
        evidence.update(phases=phases, legs=legs)
        runtime = json.loads((root / 'runtime.json').read_text())
        frames, profile = _profile(root / 'client1', text, Path(runtime['jdk']))
        evidence.update(profile=profile, motion=_motion(root / 'client1', frames),
                        callbacks=_callbacks(root / 'client1', frames))
        if selection['options'].get('base_walking', {}).get('inventory_discovery_profile'):
            evidence['inventory_discovery'] = _discovery(root, text)
        if selection['options'].get('base_walking', {}).get('inventory_refresh_checks'):
            evidence['inventory_refresh_checks'] = _refresh_checks(text)
        if selection['options'].get('base_walking', {}).get('inventory_button_checks'):
            evidence['inventory_button_checks'] = _button_checks(text)
        highlight_bridge = selection['options'].get('base_walking', {}).get('ground_highlight_bridge')
        if highlight_bridge:
            proofs = _raw(text, 'HIGHLIGHT_BRIDGE')
            if (len(proofs) != 1 or proofs[0].get('mode') != highlight_bridge
                    or proofs[0].get('highlightedObjects', 0) <= 0):
                raise ValueError('Missing active ground-highlight bridge control witness')
            for key in ('distanceCalls', 'matchesCalls'):
                calls = proofs[0].get(key)
                if type(calls) is not int or (calls <= 0 if highlight_bridge == 'native' else calls != 0):
                    raise ValueError('Ground-highlight bridge control counts differ')
            phase_proofs = _raw(text, 'HIGHLIGHT_BRIDGE_PHASE')
            if ([proof.get('phase') for proof in phase_proofs] != [1, 2, 3]
                    or any(proof.get('mode') != highlight_bridge or proof.get('unchanged') is not True
                           or proof.get('highlightedObjects', 0) <= 0 for proof in phase_proofs)):
                raise ValueError('Ground-highlight mode or workload was not preserved across phases')
            evidence['ground_highlight_bridge'] = proofs[0]
            evidence['ground_highlight_bridge_phases'] = phase_proofs
        if selection['options'].get('base_walking', {}).get('disable_newmusic_inventory_probe'):
            ready = _raw(text, 'READY')
            if len(ready) != 1 or ready[0].get('newMusicInventoryProbeRemoved') is not True:
                raise ValueError('NewMusic control removal witness missing')
            with (root / 'client1/base-walking-lua-callbacks.csv').open() as source:
                callbacks = list(csv.DictReader(source))
            if any('NMClientVanillaDiscVisibleProbe.lua' in row['source'] and
                   row['function'] == 'onRefreshInventoryWindowContainers' for row in callbacks):
                raise ValueError('Removed NewMusic inventory probe was still invoked')
            if not any('NMClientVanillaDiscVisibleProbe.lua' in row['source'] and
                       row['function'] == 'onTick' for row in callbacks):
                raise ValueError('NewMusic periodic observer unexpectedly disappeared')
        if selection['options'].get('base_walking', {}).get('verify_toolkit_newmusic_control'):
            proofs = _raw(text, 'TOOLKIT_NEWMUSIC')
            if (len(proofs) != 1 or proofs[0].get('clientDisabled') is not True
                    or proofs[0].get('serverDisabled') is not True
                    or proofs[0].get('savedSettingEnabled') is not True):
                raise ValueError('Missing client/server Toolkit NewMusic proof with saved setting enabled')
            with (root / 'client1/base-walking-lua-callbacks.csv').open() as source:
                if any('NMClientVanillaDiscVisibleProbe.lua' in row['source'] for row in csv.DictReader(source)):
                    raise ValueError('Toolkit left a NewMusic conversion scan callback active')
            evidence['toolkit_newmusic'] = proofs[0]
    except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError) as error:
        issues.append(str(error))
    evidence['limits'] = ['One rendered macOS menu-Host client in an isolated copy of the imported world; no remote-peer or Windows qualification.',
        'FrameStep durations and JFR are instrumented diagnostic work, not compositor FPS or a gameplay optimization comparison.',
        'Exclusive buckets partition frame work; inclusive nested stages are not additive. One closing partial frame may be omitted.',
        'First hook activation logs can affect initial frames; exclude capture warmup when interpreting latency tails.']
    return {'issues': issues, 'outcomes': [dict(actor='client1', case='walk', status='failed' if issues else 'captured',
                                               reason='; '.join(issues))], 'evidence': evidence}
