"""Disposable native VM observer; stages no gameplay implementation changes."""
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
from .. import preparation_process
import tempfile
import zipfile

MOD_ID = 'PZWarehouseWalkingProfile'
NATIVE_HASHES = {
    'se/krka/kahlua/vm/LuaCallFrame.class': '7d910d19d1008b2427f4e1409e6c0eb1f8c40e32132fce176b5123ae27192e30',
    'se/krka/kahlua/vm/Coroutine.class': 'b0ecb5f6f004ed43e356d5177403fee4b190e58f659709cc34b9bc89beb6dfa4',
    'se/krka/kahlua/vm/KahluaThread.class': '25f4c0dea91800dcb3fadd3d482ed5f7d5cf17908bf167afd308b85c99856bb6',
    'zombie/network/GameClient.class': '99d1778ab2c2627ddcbc04fdbb435461289c3c3075c96cf70eae5c216193352b',
    'zombie/network/GameServer.class': '308ee5247dc8bba4df2283d40d753c6839497767b9342a4adeea60e7c08cfacc',
    'zombie/network/PacketTypes$PacketType.class': 'aa6718ed4e2e33b199734c8cfa4b85a64c193ccc307b2cc4deafe18e0a43d5f5',
    'zombie/core/raknet/UdpConnection.class': '9c9bb471ff0c3dccdd0e52a3bb3c770327d02f0ad262187f950e660b2730e763',
    'zombie/core/network/ByteBufferWriter.class': 'b8f4a1aeace9d91b7b252965a52afe6dfaa32bd2569fbd875eaf5aeb89470b6a',
    'zombie/core/network/ByteBufferReader.class': '1c2731f2a49b57d2ad895069d499705f8492e3cb6ac275a8f1163b4940e370ff',
    'zombie/network/TableNetworkUtils.class': 'e25d6af0dfd36f6f08538463ee63d08f8d0990e64f61e52768c1506841bfe827',
    'zombie/network/packets/SyncClothingPacket.class': '09e83606c9de4555802b2171e26df4739a78c787afeb8b2907d46c19be311dff',
    'zombie/network/packets/INetworkPacket.class': '616a8d2e86a03952e16c45e756dae12910f637716568a74571defdc1884ce7e9',
    'zombie/network/packets/AddInventoryItemToContainerPacket.class': 'ebbd2e60b7430b6478498257cae19f21eb9d3e656bb1f03ac1dfa4422d2947f1',
    'zombie/network/packets/RemoveInventoryItemFromContainerPacket.class': '9eaceabf11a0fc4b2e0dc843fecfeada2417f76155de03aa059e7dae766fa983',
    'zombie/network/packets/AddItemToMapPacket.class': 'bd27fa5f01bb071122156d1b915cd8d75e9de62404b68175b83dd9614e58463d',
    'zombie/network/packets/ObjectModDataPacket.class': '1d6f806ee95bf6d22f5a69d0535b375a60085039311697eecd6b85dff8e9d9c2',
    'zombie/network/packets/RemoveItemFromSquarePacket.class': '13fc4649b4dadba1d03f3bc1cc211f98b96116c7179c33ba681127daf3affb0c',
}
JAVA_SOURCES = {'Main.java', 'Profile.java', 'ProfileChecks.java', 'OrderedCommands.java', 'OrderedCommandChecks.java'}
ORDERED_TRANSPORT = {'scope': 'warehouse-setup-and-owned-cleanup-only', 'reliability': 3,
                     'client_commands': {'Prepare': 0, 'Baseline': 0, 'Normalized': 0},
                     'server_commands': {'CaptureBaseline': 0, 'Normalize': 0, 'Prepared': 1, 'Abortd': 1, 'Done': 1},
                     'priority': 1, 'packet_type': 'ClientCommand', 'serializer': 'native-TableNetworkUtils',
                     'global_packet_settings_changed': False}
# Absolute tolerance of one nanosecond after nanosecond-to-millisecond conversion
# and JSON/float summation; it does not scale with measured work or call count.
TIMING_EPSILON_MS = 1e-6
SCOPE_DETAILS = {'tail_calls': 'separate-frame-spans', 'exclusive_scope': 'registered-children',
                 'registration': 'public-roots-direct-upvalues-and-nested-prototypes', 'receiver_scope': 'shared-prototypes'}
PASS = 'WAREHOUSE_WALKING_PROFILE_NATIVE_PASS nested_lua_calls=true tail_calls=true exceptions=true native_returns=true thread_guard=true bounds=true'
ORDERED_PASS = 'WAREHOUSE_WALKING_ORDERED_COMMANDS_PASS native_payload=true reliability=3 channels=0,1 gated=true no_partial_send=true explicit_success=true'


def sources(project, selection=None):
    fixture = Path(project) / 'tests/native_queue/warehouse-walking'
    return [*sorted((fixture / 'java').glob('*.java')), fixture / 'client/WarehouseWalkingProfile.lua']


def _env():
    return {key: value for key, value in os.environ.items()
            if key not in ('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS')}


def _run(command):
    try:
        return preparation_process.run(list(map(str, command)), check=True, capture_output=True,
                              text=True, timeout=60, env=_env())
    except subprocess.CalledProcessError as error:
        raise ValueError('Warehouse observer native command failed: '
                         + (error.stdout + '\n' + error.stderr)[-6000:]) from error


def compile_check(project, game, jdk, build):
    project, game, jdk, build = map(Path, (project, game, jdk, build))
    with zipfile.ZipFile(game / 'projectzomboid.jar') as jar:
        for name, expected in NATIVE_HASHES.items():
            if hashlib.sha256(jar.read(name)).hexdigest() != expected:
                raise ValueError('Unsupported warehouse native observer input: ' + name)
    java = sorted((project / 'tests/native_queue/warehouse-walking/java').glob('*.java'))
    if {path.name for path in java} != JAVA_SOURCES:
        raise ValueError('Warehouse native observer/check source missing')
    classpath = os.pathsep.join(str(game / name) for name in ('projectzomboid.jar', 'ZombieBuddy.jar'))
    _run([jdk / 'bin/javac', '--release', '25', '-cp', classpath, '-d', build, *java])
    result = _run([jdk / 'bin/java', '-javaagent:' + str(game / 'ZombieBuddy.jar')
                   + '=config_dir=' + str(build / 'check-cache') + ',policy=deny-new,verbosity=0',
                   '-cp', str(build) + os.pathsep + str(game / '*'),
                   'toolkit.warehousewalking.ProfileChecks', project])
    if PASS not in result.stdout or ORDERED_PASS not in result.stdout or '[!] Failed' in result.stdout:
        raise ValueError('Native warehouse observer invocation check failed: ' + result.stdout[-4000:])
    return java


def stage(project, output, game, jdk, selection, locations, runtime):
    project, output, game, jdk = map(Path, (project, output, game, jdk))
    receipt = {**SCOPE_DETAILS, 'test_only': True, 'observer_mod': MOD_ID, 'native_hashes': NATIVE_HASHES,
               'scope': 'registered-native-lua-calls', 'callback_replacement': False,
               'native_jvm_check': PASS, 'ordered_jvm_check': ORDERED_PASS, 'client_properties': {}, 'ordered_transport': ORDERED_TRANSPORT,
               'ordered_cache_markers': {}, 'java_entries': {}}
    with tempfile.TemporaryDirectory(prefix='pz-warehouse-observer-') as temporary:
        build = Path(temporary)
        java = compile_check(project, game, jdk, build)
        receipt['java_sources'] = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in java}
        entries = [path for path in sorted((build / 'toolkit').rglob('*.class')) if 'Checks' not in path.name]
        receipt['java_entries'] = {path.relative_to(build).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for path in entries}
        for role, settings in runtime['roles'].items():
            cache = Path(settings['cache'])
            mod = cache / 'mods' / MOD_ID
            (mod / 'common').mkdir(parents=True)
            version = mod / '42'
            (version / 'media/java').mkdir(parents=True)
            (version / 'mod.info').write_text('name=Disposable warehouse native call observer\n'
                'id=' + MOD_ID + '\nversion=0.0.1\nversionMin=42.21\nversionMax=42.21\n'
                'require=\\ZombieBuddy\nZBVersionMin=2.3.4\njavaPkgName=toolkit.warehousewalking\n'
                'javaJarFile=media/java/' + MOD_ID + '.jar\n')
            with zipfile.ZipFile(version / 'media/java' / (MOD_ID + '.jar'), 'w', zipfile.ZIP_DEFLATED) as jar:
                for path in entries:
                    jar.write(path, path.relative_to(build).as_posix())
            marker = cache / 'Lua/warehouse-walking-ordered.txt'
            marker_text = ('PZWarehouseWalkingProfile/ordered-command-v1\n' + str(cache.resolve()) + '\n' + role + '\n'
                           + receipt['java_entries']['toolkit/warehousewalking/OrderedCommands.class'] + '\n')
            marker.write_text(marker_text)
            receipt['ordered_cache_markers'][role] = hashlib.sha256(marker_text.encode()).hexdigest()
            lua = cache / 'mods/ActionQueueTest/42/media/lua/client'
            lua.mkdir(parents=True, exist_ok=True)
            shutil.copy2(project / 'tests/native_queue/warehouse-walking/client/WarehouseWalkingProfile.lua', lua)
            if role == 'server':
                continue
            classes = Path(settings['classes'])
            launcher = classes / 'ToolkitSmokeLauncher.java'
            text = launcher.read_text()
            anchor = 'public static void main(String[] args) throws Exception {'
            if text.count(anchor) != 1 or 'pz.warehouseWalking.cache' in text:
                raise ValueError('Private client launcher changed or warehouse observer already staged')
            props = {'pz.warehouseWalking.cache': str(cache.resolve())}
            assignments = '\n'.join('System.setProperty(' + json.dumps(key) + ', ' + json.dumps(value) + ');'
                                    for key, value in props.items())
            launcher.write_text(text.replace(anchor, anchor + '\n' + assignments))
            _run([jdk / 'bin/javac', '--release', '25', '-cp', game / 'projectzomboid.jar',
                  classes / 'ToolkitWindowBootstrap.java', classes / 'ToolkitHostChildDiagnostics.java',
                  classes / 'ToolkitHostOutput.java', launcher])
            receipt['client_properties'][role] = props
    runtime.setdefault('fixture', {}).setdefault('mods', []).append(MOD_ID)
    (output / 'warehouse-walking-observer-inputs.json').write_text(json.dumps(receipt, indent=2) + '\n')


def verify_profile(value, phase=None):
    """Reject malformed/incompatible captures, retaining source-separated consumer rows."""
    if (not isinstance(value, dict) or (phase is not None and value.get('phase') != phase) or value.get('clock') != 'nanoTime'
            or value.get('scope') != 'registered-native-lua-calls' or value.get('identities_unchanged') is not True
            or value.get('observer_overhead_included') is not True
            or any(value.get(key) != expected for key, expected in SCOPE_DETAILS.items())):
        raise ValueError('Missing warehouse native observer ownership/scope receipt')
    if (type(value.get('phase')) is not int or type(value.get('index')) is not int or not 1 <= value['index'] <= 16
            or value['index'] != value.get('phase')
            or type(value.get('elapsed_ms')) not in (int, float)
            or not math.isfinite(value['elapsed_ms']) or value['elapsed_ms'] <= 0):
        raise ValueError('Invalid warehouse native observer interval')
    hooks = value.get('hooks', {})
    if not isinstance(hooks, dict) or any(type(hooks.get(key)) is not int or hooks[key] <= 0 for key in ('init', 'shrink')):
        raise ValueError('Warehouse native observer hooks were not invoked')
    allocation = value.get('allocation')
    if (not isinstance(allocation, dict) or type(allocation.get('available')) is not bool
            or allocation.get('scope') != 'owner-thread-whole-interval' or allocation.get('includes_observer') is not True
            or (allocation['available'] and (type(allocation.get('bytes')) is not int or allocation['bytes'] < 0))
            or (not allocation['available'] and 'bytes' in allocation)):
        raise ValueError('Invalid whole-interval native allocation receipt')
    metrics = value.get('metrics')
    if not isinstance(metrics, list) or not 1 <= len(metrics) <= 2048:
        raise ValueError('Warehouse native observer metrics missing or unbounded')
    identities = set()
    exclusive_total = 0.0
    for row in metrics:
        if (not isinstance(row, dict) or not isinstance(row.get('name'), str) or not row['name']
                or not isinstance(row.get('source'), str) or not row['source']
                or type(row.get('first_line')) is not int or row['first_line'] < 0
                or type(row.get('calls')) is not int or row['calls'] < 0):
            raise ValueError('Invalid warehouse native observer identity/counter')
        key = row['name'], row['source'], row['first_line']
        if key in identities:
            raise ValueError('Duplicate warehouse native observer identity')
        identities.add(key)
        aliases = row.get('aliases')
        if (not isinstance(aliases, list) or not 1 <= len(aliases) <= 128
                or any(not isinstance(alias, str) or not alias for alias in aliases)
                or len(set(aliases)) != len(aliases) or row['name'] not in aliases):
            raise ValueError('Invalid warehouse native observer aliases')
        if any(type(row.get(key)) not in (int, float) or not math.isfinite(row[key]) or row[key] < 0
               for key in ('inclusive_ms', 'exclusive_ms', 'max_ms')):
            raise ValueError('Nonfinite warehouse native observer duration')
        if row['exclusive_ms'] > row['inclusive_ms'] or row['max_ms'] > row['inclusive_ms']:
            raise ValueError('Invalid warehouse native observer nesting')
        if row['max_ms'] > value['elapsed_ms'] + TIMING_EPSILON_MS:
            raise ValueError('Native invocation exceeds observer wall interval')
        try:
            inclusive_bound = row['calls'] * row['max_ms']
        except OverflowError as error:
            raise ValueError('Invalid native invocation count/duration product') from error
        if row['inclusive_ms'] > inclusive_bound + TIMING_EPSILON_MS:
            raise ValueError('Inclusive duration exceeds native calls times maximum')
        exclusive_total += row['exclusive_ms']
        if not math.isfinite(exclusive_total) or exclusive_total > value['elapsed_ms'] + TIMING_EPSILON_MS:
            raise ValueError('Registered exclusive durations exceed observer wall interval')
        if row['calls'] == 0 and any(row[key] != 0 for key in ('inclusive_ms', 'exclusive_ms', 'max_ms')):
            raise ValueError('Timing without native invocation')
    for prefix in ('page.refreshBackpacks', 'pane.refreshContainer', 'pane.restoreSelection', 'pane.itemSortFunc',
                   'rows.', 'filter.', 'categoryRules.', 'categories.', 'categoryGroups.split',
                   'tags.forItem', 'tags.automaticForItem', 'tags.signature', 'retention.isRetained', 'recipeCatalog.newContext'):
        if not any(any(alias.startswith(prefix) for alias in row['aliases']) for row in metrics):
            raise ValueError('Warehouse native observer consumer missing: ' + prefix)
    if not any(row['name'].startswith('page.refreshBackpacks') and row['calls'] > 0 for row in metrics):
        raise ValueError('Warehouse discovery was never invoked during the interval')
    return value
