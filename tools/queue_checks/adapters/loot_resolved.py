"""Opt-in, initial-load native loot bank. Capture is not control/candidate parity."""
import ast
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import zipfile
from .. import receipts
import optimizer_profile

SUITE = 'loot-resolved'
MARKER = '[LOOT_RESOLVED_TEST] '
MOD = 'PZLootResolvedRuntime'
BOOT = '42/media/bootstrap/PZLootResolvedBootstrap.jar'
RUNTIME = '42/media/java/PZLootResolvedRuntime.jar'
PACKAGE = 'toolkit.lootresolved.bootstrap'
TOKEN = 'loot-resolved-runtime.opt-in'
DIAGNOSTIC = 'LOOT_RESOLVED_EXPECTED_ACCEPT_ERROR'
MODS = ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit', MOD]
ROOT = Path(__file__).resolve().parents[3]
CASE = 'bank'
SEED = 'PZ-Loot-Resolved-42.21'
SANDBOX = {'Zombies': 3, 'StartYear': 1, 'StartMonth': 7, 'StartDay': 9, 'StartTime': 2}


def definitions():
    return {SUITE: {'status': 'ready', 'native_validation': 'not-run', 'clients': 1, 'default_mods': MODS,
        'cases': [{'id': CASE, 'producer': 'fixture', 'capability': 'capture', 'kinds': ['sp', 'mp'],
                   'languages': ['EN'], 'modes': ['toolkit']}]}}


def validate(s):
    o = s.get('options', {})
    if (s.get('cases') != [CASE] or s.get('kind') not in ('sp', 'mp') or s.get('mode') != 'toolkit'
            or type(s.get('clients')) is not int or s['clients'] != 1 or s.get('languages') != ['EN']
            or not set(MODS) <= set(s.get('mods', [])) or not isinstance(o, dict)
            or s.get('resources', {}).get('exclusive') is not True
            or o.get('loot_runtime_mode') not in ('control', 'candidate')
            or o.get('preload_toolkit_fonts') is not True
            or s['kind'] == 'mp' and o.get('mp_host') is not True
            or s['kind'] == 'sp' and o.get('mp_host')
            or any(o.get(k) for k in ('world_template', 'seed_run', 'startup_connection'))):
        raise ValueError('Loot resolved requires fresh exclusive toolkit SP/menu Host, one EN client, explicit mode and font preload')
    source = o.get('mod_sources', {}).get(MOD)
    if not isinstance(source, str) or not Path(source).is_absolute():
        raise ValueError('Loot resolved requires an explicit absolute PZLootResolvedRuntime mod source')
    archive = o.get('optimizer_archive')
    if archive is not None:
        if (not isinstance(archive, str) or not Path(archive).is_absolute() or not Path(archive).is_file()
                or o.get('optimizer_prewarm') is not True):
            raise ValueError('Loot optimizer archive requires explicit existing path and optimizer_prewarm=true')
    elif o.get('optimizer_prewarm'):
        raise ValueError('optimizer_prewarm requires optimizer_archive')


def _sha(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError('Expected regular loot fixture input: ' + str(path))
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _sources(project):
    base = Path(project) / 'tests/chunk_integration/loot_resolved_runtime'
    result = {p.name: _sha(p) for p in base.iterdir() if p.is_file() or p.is_symlink()}
    result['ResolvedCandidate.java'] = _sha(base.parent / 'loot_resolved/ResolvedCandidate.java')
    result['../loot_resolved/run.py'] = _sha(base.parent / 'loot_resolved/run.py')
    return result


def _guards(project):
    base = Path(project) / 'tests/chunk_integration'
    tree = ast.parse((base / 'loot_resolved/run.py').read_text())
    matches = [node.value for node in tree.body if isinstance(node, ast.Assign)
               and any(isinstance(t, ast.Name) and t.id == 'GUARDS' for t in node.targets)]
    if len(matches) != 1:
        raise ValueError('Loot native guard declaration changed')
    result = ast.literal_eval(matches[0])
    result.update(json.loads((base / 'loot_resolved_runtime/success-native-hashes.json').read_text()))
    return result


def bundle(cache, selection, project=ROOT):
    """Read-only early admission: no cache token is written here."""
    validate(selection)
    layer = Path(cache) / 'mods' / MOD
    info = layer / '42/mod.info'
    expected = Path(project) / 'tests/chunk_integration/loot_resolved_runtime'
    if _sha(info) != _sha(expected / 'mod.info.template'):
        raise ValueError('Loot runtime metadata differs from current fixture')
    if _sha(layer / '42/media/lua/shared/ZZLootResolvedRuntime.lua') != _sha(expected / 'ZZLootResolvedRuntime.lua'):
        raise ValueError('Loot runtime Lua differs from current fixture')
    values = []
    token = None
    for name in (BOOT, RUNTIME):
        path = layer / name
        _sha(path)
        with zipfile.ZipFile(path) as jar:
            required = ['META-INF/loot-runtime-inputs.json']
            if name == BOOT:
                required += ['META-INF/MANIFEST.MF', 'toolkit/lootresolved/bootstrap/token.txt',
                             'toolkit/lootresolved/bootstrap/mode.txt']
            if any(jar.namelist().count(resource) != 1 for resource in required):
                raise ValueError('Missing/duplicate loot bootstrap resource')
            value = receipts.decode_object(jar.read(required[0]).decode('utf-8'))
            values.append(value)
            if name == BOOT:
                if not re.search(r'^ZB-Preload: true\r?$', jar.read('META-INF/MANIFEST.MF').decode('utf-8'), re.M):
                    raise ValueError('Loot bootstrap requires ZB-Preload manifest')
                token = jar.read('toolkit/lootresolved/bootstrap/token.txt').decode('ascii').strip()
                mode = jar.read('toolkit/lootresolved/bootstrap/mode.txt').decode('ascii').strip()
                if not re.fullmatch('[0-9a-f]{32}', token) or mode != selection['options']['loot_runtime_mode']:
                    raise ValueError('Loot bootstrap token/mode mismatch')
    value = values[0]
    if type(value.get('format')) is not int or value.get('test_only') is not True or value.get('success_path_checked') is not False:
        raise ValueError('Loot embedded receipt types differ')
    if values[1] != value or any(value.get(k) != v for k, v in {
            'format': 1, 'test_only': True, 'mode': selection['options']['loot_runtime_mode'],
            'success_path_checked': False, 'entry_point': 'lootResolvedRuntimeRun',
            'terminal_marker': '[LOOT_RESOLVED_RUNTIME] FINISH status=', 'required_preload': BOOT}.items()):
        raise ValueError('Loot runtime embedded receipt mismatch')
    if (value.get('sources') != _sources(project) or value.get('native_hashes') != _guards(project)
            or value.get('headless_checks') != ['missing-token', 'already-loaded', 'initial-definition', 'preload']):
        raise ValueError('Foreign/stale loot runtime source or native receipt')
    return token, value


def early_preload(cache, selection, game=None, project=ROOT):
    bundle(cache, selection, project)
    jar = Path(cache) / 'mods' / MOD / BOOT
    import os
    try:
        argument = os.path.relpath(jar, game) if game is not None else str(jar)
    except ValueError as error:
        raise ValueError('Loot preload requires the game and snapshot on the same drive') from error
    if any(char in argument for char in (',', ':', ';', '\n', '\r')):
        raise ValueError('Loot preload path contains loader separators')
    return argument + ':' + PACKAGE


def sources(project, selection):
    base = Path(project) / 'tests'
    return [*sorted((base / 'native_queue' / SUITE).rglob('*.lua')),
            *sorted((base / 'native_queue/startup').rglob('*.lua')),
            base / 'native_queue/health/shared/QueueHealthEvents.lua',
            *sorted(p for p in (base / 'chunk_integration/loot_resolved_runtime').iterdir() if p.is_file()),
            base / 'chunk_integration/loot_resolved/ResolvedCandidate.java',
            base / 'chunk_integration/loot_resolved/run.py', *optimizer_profile.sources(project, selection)]


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    output, project = Path(output).resolve(), Path(project)
    base = project / 'tests/native_queue'
    if set(runtime['roles']) != ({'client1', 'server'} if selection['kind'] == 'mp' else {'client1'}):
        raise ValueError('Loot fixture roles differ')
    staged = []
    for role, settings in runtime['roles'].items():
        cache = Path(settings['cache'])
        marker = cache / 'Lua/smoke-user.txt'
        if (cache.is_symlink() or cache.resolve() != output / role or marker.is_symlink()
                or not marker.is_file() or marker.read_text().strip() != role):
            raise ValueError('Loot token requires actual owned cache/Lua/smoke-user.txt')
        token, value = bundle(cache, selection, project)
        target = cache / TOKEN
        if target.exists() or target.is_symlink():
            raise ValueError('Loot opt-in must be fresh')
        staged.append((target, token))
        lua = cache / 'mods/ActionQueueTest/42/media/lua'
        for side in ('client', 'server', 'shared'):
            (lua / side).mkdir(parents=True, exist_ok=True)
        starter = (base / 'startup/client/ZZStartup.lua').read_text()
        anchor = "getSandboxOptions():getOptionByName('Zombies'):setValue(6);getSandboxOptions():toLua()"
        if starter.count(anchor) != 1:
            raise ValueError('Common startup Zombies line changed')
        settings = ';'.join("getSandboxOptions():getOptionByName('" + key + "'):setValue(" + str(value) + ")" for key, value in SANDBOX.items())
        starter = starter.replace(anchor, settings + ';getSandboxOptions():toLua()')
        seed_anchor = "\n  MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'})"
        if starter.count(seed_anchor) != 1:
            raise ValueError('Common startup SP seed anchor changed')
        starter = starter.replace(seed_anchor, "\n  assert(MapSpawnSelect.instance.seedTextBox,'Native seed UI unavailable')\n"
            "  MapSpawnSelect.instance.seedTextBox:setText('" + SEED + "')\n"
            "  WorldGenParams.INSTANCE:setSeedString('" + SEED + "')\n" + seed_anchor)
        (lua / 'client/ZZStartup.lua').write_text(starter)
        shutil.copy2(base / 'startup/server/ZZStartupServer.lua', lua / 'server/ZZStartupServer.lua')
        shutil.copy2(base / 'health/shared/QueueHealthEvents.lua', lua / 'shared/QueueHealthEvents.lua')
    if selection['kind'] == 'mp':
        path = output / 'server/Server/queue-smoke.ini'
        text = path.read_text()
        if len(re.findall(r'^SpawnPoint=.*$', text, re.M)) != 1:
            raise ValueError('Common Host startup settings changed')
        path.write_text(re.sub(r'^Seed=.*\n?', '', text, flags=re.M).rstrip('\n') + '\nSeed=' + SEED + '\n')
    for target, token in staged:
        with target.open('x', encoding='ascii') as stream:
            stream.write(token + '\n')
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY', sandbox=dict(SANDBOX),
        failure_markers=[MARKER + 'FAIL ', '[LOOT_RESOLVED_RUNTIME] FINISH status=failed',
                         '[LOOT_RESOLVED_RUNTIME] ACTIVATION disabled:'])
    optimizer_profile.stage(project, output, game, jdk, selection, runtime)


def _records(text, event):
    return receipts.records(text, MARKER, event)


def complete(selection, role, text):
    try:
        mode = selection['options']['loot_runtime_mode']
        source = 'server-response' if selection['kind'] == 'mp' else 'sp-main-tick'
        authority = dict(role='client1', case=CASE, runtimeMode=mode, status='complete', cases=8, source=source)
        final = dict(role='client1', case=CASE, runtimeMode=mode, status='complete', authority=True)
        return (role == 'client1' and _records(text, 'AUTHORITY') == [authority]
                and _records(text, 'COMPLETE') == [final] and not _records(text, 'FAIL')
                and text.index(MARKER + 'AUTHORITY ') < text.index(MARKER + 'COMPLETE ')
                and '[LOOT_RESOLVED_RUNTIME] FINISH status=failed' not in text
                and (selection['kind'] == 'mp' or text.index('[LOOT_RESOLVED_RUNTIME] FINISH status=complete cases=8 reason=') < text.index(MARKER + 'AUTHORITY ') and len(re.findall(r'\[LOOT_RESOLVED_RUNTIME\] FINISH status=complete cases=8 reason=\s*(?:\n|$)', text)) == 1))
    except (KeyError, ValueError):
        return False


def _compare(project):
    spec = importlib.util.spec_from_file_location('_loot_native_receipts', Path(project) / 'tests/chunk_integration/loot_resolved_runtime/compare.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _activation(compare, cache, pid, mode, native_hash):
    value = compare.values(cache / ('loot-resolved-runtime-activation-' + str(pid) + '.txt'))
    if (any(value.get(k) != v for k, v in dict(state='active', mode=mode, pid=str(pid), definitions='1', rng_audit_definitions='1', input=native_hash).items())
            or not re.fullmatch('[0-9a-f]{64}', value.get('output', ''))
            or (value['input'] == value['output']) != (mode == 'control')):
        raise ValueError('Missing/failed/PID-mismatched loot activation')
    return value


def verify(root, selection, catalog):
    root = Path(root); issues, evidence = [], {}
    try:
        validate(selection)
        runtime = json.loads((root / 'runtime.json').read_text())
        execution = json.loads((root / 'execution.json').read_text())
        cache = root / 'client1'
        project = Path(runtime['project'])
        _, inputs = bundle(cache, selection, project)
        compare = _compare(project)
        mode = selection['options']['loot_runtime_mode']
        authority = 'server' if selection['kind'] == 'mp' else 'client1'
        pid = execution['processes'][authority]['pid']
        client_pid = execution['processes']['client1']['pid']
        if type(pid) is not int or pid <= 0 or type(client_pid) is not int or client_pid <= 0:
            raise ValueError('Missing owned loot authority/client PID')
        if selection['kind'] == 'mp' and (pid == client_pid or execution['processes']['server'].get('parent_role') != 'client1'
                or Path(execution['processes']['server'].get('cache', '')).resolve() != cache.resolve()
                or Path(runtime.get('host_cache', '')).resolve() != cache.resolve()):
            raise ValueError('Loot Host authority must be the owned child sharing client1 cache')
        native_hash = inputs['native_hashes']['zombie/inventory/ItemPickerJava.class']
        activation = _activation(compare, cache, pid, mode, native_hash)
        _activation(compare, cache, client_pid, mode, native_hash)
        status, _, rows = compare.read(cache, mode)
        if status['pid'] != str(pid) or status.get('reason') or any(status.get(k) != 'uncovered' for k in ('source_square', 'live_script_reload', 'module_item_replacement')):
            raise ValueError('Loot bank PID/status/uncovered gates mismatch')
        text = (root / 'client1-launch.log').read_text(errors='replace')
        auth = (root / (authority + '-launch.log')).read_text(errors='replace')
        finishes = re.findall(r'\[LOOT_RESOLVED_RUNTIME\] FINISH status=(\S+) cases=(\d+) reason=([^\r\n]*)', auth)
        if finishes != [('complete', '8', '')] or auth.count(DIAGNOSTIC) != 1:
            raise ValueError('Missing/failed bank terminal or expected protected Lua diagnostic count differs')
        if not complete(selection, 'client1', text):
            raise ValueError('Loot completion missing authority handshake')
        if selection['kind'] == 'mp':
            requests, server_requests = _records(text, 'REQUEST'), _records(auth, 'REQUEST')
            if (len(requests) != 1 or len(server_requests) != 1
                    or type(requests[0].get('onlineID')) is not int or requests[0]['onlineID'] < 0
                    or requests[0] != dict(role='client1', case=CASE, runtimeMode=mode, onlineID=requests[0]['onlineID'])
                    or server_requests[0] != dict(role='server', case=CASE, runtimeMode=mode, onlineID=requests[0]['onlineID'])
                    or text.index(MARKER + 'REQUEST ') > text.index(MARKER + 'AUTHORITY ')
                    or auth.index(MARKER + 'REQUEST ') > auth.index('[LOOT_RESOLVED_RUNTIME] FINISH ')):
                raise ValueError('Missing/mismatched explicit owned client1 request')
            expected = dict(role='server', case=CASE, runtimeMode=mode, status='complete', cases=8, source='server-main-tick')
            if _records(auth, 'AUTHORITY') != [expected] or auth.index('[LOOT_RESOLVED_RUNTIME] FINISH ') > auth.index(MARKER + 'AUTHORITY '):
                raise ValueError('Missing/invalid server main-thread authority response')
            if '[LOOT_RESOLVED_RUNTIME] FINISH ' in text:
                raise ValueError('Menu Host client must not run authoritative loot bank')
        if selection['options'].get('optimizer_archive'):
            profile = 'multiplayer client=true' if selection['kind'] == 'mp' else 'singleplayer client=false'
            ready = '[OptimizerTrial] bridge ready mode=' + profile + ' server=false session=1'
            if len(re.findall(re.escape(ready) + r'(?:\s|$)', text)) != 1:
                raise ValueError('Selected Optimized client profile kind/session did not become ready')
            if selection['kind'] == 'mp' and ('[OptimizerTrialProbe] native server resources=' not in auth or 'overlayAbsent=true' not in auth):
                raise ValueError('Optimizer Host child isolation not proved')
        evidence = dict(authority_pid=pid, runtime_mode=mode, status=status, activation=activation,
                        ordered_rows=len(rows)-1, expected_protected_diagnostic=DIAGNOSTIC, requires_review=True,
                        limits=['Captured actual bank; matching control/candidate comparator and full log audit still required.',
                                'Source-square, live reload, module replacement and later Java transformations remain uncovered.'])
    except (OSError, ValueError, KeyError, TypeError, AttributeError, zipfile.BadZipFile) as error:
        issues.append(str(error))
    return dict(issues=issues, outcomes=[dict(actor='client1', case=CASE, status='failed' if issues else 'captured',
                reason='; '.join(issues))], evidence=evidence)
