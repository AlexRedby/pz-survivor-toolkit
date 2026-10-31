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
HOST_AUTHORITY = 'loot-resolved-runtime.host-authority'
DIAGNOSTIC = 'LOOT_RESOLVED_EXPECTED_ACCEPT_ERROR'
MODS = ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit', MOD]
ROOT = Path(__file__).resolve().parents[3]
CASE = 'bank'
BANKS = {'bank': ('base', 8), 'semantics': ('semantics', 12), 'reload': ('reload', 1)}
SCRIPT = '42/media/scripts/loot-runtime-probes.txt'
SEED = 'PZ-Loot-Resolved-42.21'
WORLD = 'PZDrivingBench-OptimizerTrial-LootResolved'
SANDBOX = {'Zombies': 3, 'StartYear': 1, 'StartMonth': 7, 'StartDay': 9, 'StartTime': 2}


def bank(selection):
    cases = selection.get('cases')
    if not isinstance(cases, list) or len(cases) != 1 or not isinstance(cases[0], str) or cases[0] not in BANKS:
        raise ValueError('Loot resolved requires exactly one explicit bank case')
    return cases[0], *BANKS[cases[0]]


def sandbox(selection):
    return dict(SANDBOX, **({} if bank(selection)[1] == 'base' else
                {'RollsMultiplier': 1, 'MementoLootNew': 0, 'MedicalLootNew': 1.0}))


def definitions():
    return {SUITE: {'status': 'ready', 'native_validation': 'not-run', 'clients': 1, 'default_mods': MODS,
        'cases': [{'id': case, 'producer': 'fixture', 'capability': 'capture', 'kinds': ['sp', 'mp'],
                   'languages': ['EN'], 'modes': ['toolkit']} for case in BANKS]}}


def validate(s):
    bank(s)
    o = s.get('options', {})
    if (s.get('kind') not in ('sp', 'mp') or s.get('mode') != 'toolkit'
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


def _sources(project, selection):
    base = Path(project) / 'tests/chunk_integration/loot_resolved_runtime'
    result = {p.name: _sha(p) for p in base.iterdir() if p.is_file() or p.is_symlink()}
    result['ResolvedCandidate.java'] = _sha(base.parent / 'loot_resolved/ResolvedCandidate.java')
    result['../loot_resolved/run.py'] = _sha(base.parent / 'loot_resolved/run.py')
    if selection['options'].get('optimizer_archive'):
        result['../../optimizer_trial/candidate-manifest.json'] = _sha(
            Path(project) / 'tests/optimizer_trial/candidate-manifest.json')
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


def _runtime_receipt(project, selection, native):
    archive = selection['options'].get('optimizer_archive')
    if archive is None:
        return dict(runtime_hashes=dict(native), optimizer_manifest_sha256=None,
                    optimizer_archive_sha256=None, optimizer_profile=None)
    path = Path(project) / 'tests/optimizer_trial/candidate-manifest.json'
    manifest_sha = _sha(path)
    manifest = receipts.decode_object(path.read_text())
    if _sha(Path(archive)) != manifest['release_sha256']:
        raise ValueError('Loot optimizer archive differs from current reviewed release')
    # A changed overlap requires explicit source review, even if a new manifest pins it.
    overlap = {name: digest for name, digest in manifest['selected_files'].items() if name in native}
    if overlap != {'zombie/Lua/LuaEventManager.class':
                   'd786c342e563fb735727beb268e39a9a40726c2e83a8ac15ec06c753580b524b',
                   'zombie/iso/IsoGridSquare.class':
                   '557646359c35a309c786c24c7d7fd522d2877f9ad64aea1315a29052d76920a6'}:
        raise ValueError('Loot optimizer guarded resource overlap changed')
    return dict(runtime_hashes={**native, **overlap}, optimizer_manifest_sha256=manifest_sha,
                optimizer_archive_sha256=manifest['release_sha256'],
                optimizer_profile={key: manifest['profile'][key] for key in ('id', 'properties')})


def bundle(cache, selection, project=ROOT):
    """Read-only early admission: no cache token is written here."""
    validate(selection)
    case, selected_bank, count = bank(selection)
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
                             'toolkit/lootresolved/bootstrap/mode.txt', 'toolkit/lootresolved/bootstrap/bank.txt']
            if any(jar.namelist().count(resource) != 1 for resource in required):
                raise ValueError('Missing/duplicate loot bootstrap resource')
            value = receipts.decode_object(jar.read(required[0]).decode('utf-8'))
            values.append(value)
            if name == BOOT:
                if not re.search(r'^ZB-Preload: true\r?$', jar.read('META-INF/MANIFEST.MF').decode('utf-8'), re.M):
                    raise ValueError('Loot bootstrap requires ZB-Preload manifest')
                token = jar.read('toolkit/lootresolved/bootstrap/token.txt').decode('ascii').strip()
                mode = jar.read('toolkit/lootresolved/bootstrap/mode.txt').decode('ascii').strip()
                selected = jar.read('toolkit/lootresolved/bootstrap/bank.txt').decode('ascii').strip()
                if selected != selected_bank:
                    raise ValueError('Loot bootstrap bank mismatch')
                if not re.fullmatch('[0-9a-f]{32}', token) or mode != selection['options']['loot_runtime_mode']:
                    raise ValueError('Loot bootstrap token/mode mismatch')
    value = values[0]
    if type(value.get('format')) is not int or value.get('test_only') is not True or value.get('success_path_checked') is not False:
        raise ValueError('Loot embedded receipt types differ')
    if values[1] != value or any(value.get(k) != v for k, v in {
            'format': 1, 'test_only': True, 'mode': selection['options']['loot_runtime_mode'],
            'success_path_checked': False, 'bank': selected_bank,
            'entry_point': 'lootResolvedRuntimeRun' if selected_bank == 'base' else 'lootResolvedRuntimeRunFor',
            'terminal_marker': '[LOOT_RESOLVED_RUNTIME] FINISH status=', 'required_preload': BOOT}.items()):
        raise ValueError('Loot runtime embedded receipt mismatch')
    if (value.get('sources') != _sources(project, selection) or value.get('native_hashes') != _guards(project)
            or value.get('headless_checks') != ['missing-token', 'already-loaded', 'initial-definition', 'preload']):
        raise ValueError('Foreign/stale loot runtime source or native receipt')
    expected_scripts = {} if selected_bank == 'base' else {SCRIPT: _sha(expected / 'loot-runtime-probes.txt')}
    if value.get('scripts') != expected_scripts:
        raise ValueError('Loot runtime script receipt differs')
    scripts = layer / '42/media/scripts'
    if scripts.is_symlink() or scripts.exists() and not scripts.is_dir():
        raise ValueError('Loot runtime scripts must be an owned regular directory')
    actual = {p.relative_to(layer).as_posix(): _sha(p) for p in scripts.rglob('*') if p.is_file() or p.is_symlink()} if scripts.exists() else {}
    if actual != expected_scripts:
        raise ValueError('Loot runtime owned script source changed')
    expected_runtime = _runtime_receipt(project, selection, _guards(project))
    if any(key not in value or value[key] != expected for key, expected in expected_runtime.items()):
        raise ValueError('Loot runtime effective optimizer receipt mismatch')
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
        host_marker = cache / HOST_AUTHORITY
        if target.exists() or target.is_symlink() or host_marker.exists() or host_marker.is_symlink():
            raise ValueError('Loot opt-in and Host authority must be fresh')
        staged.append((target, token))
        if selection['kind'] == 'mp':
            staged.append((host_marker, token))
        lua = cache / 'mods/ActionQueueTest/42/media/lua'
        for side in ('client', 'server', 'shared'):
            (lua / side).mkdir(parents=True, exist_ok=True)
        starter = (base / 'startup/client/ZZStartup.lua').read_text()
        world_anchor = "getWorld():setWorld('QueueStartup')"
        if starter.count(world_anchor) != 1:
            raise ValueError('Common startup world name changed')
        starter = starter.replace(world_anchor, "getWorld():setWorld('" + WORLD + "')")
        anchor = "getSandboxOptions():getOptionByName('Zombies'):setValue(6);getSandboxOptions():toLua()"
        if starter.count(anchor) != 1:
            raise ValueError('Common startup Zombies line changed')
        settings = ';'.join("getSandboxOptions():getOptionByName('" + key + "'):setValue(" + str(value) + ")" for key, value in sandbox(selection).items())
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
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY', sandbox=sandbox(selection),
        failure_markers=[MARKER + 'FAIL ', '[LOOT_RESOLVED_RUNTIME] FINISH status=failed',
                         '[LOOT_RESOLVED_RUNTIME] ACTIVATION disabled:'])
    optimizer_profile.stage(project, output, game, jdk, selection, runtime)


def _records(text, event):
    return receipts.records(text, MARKER, event)


def complete(selection, role, text):
    try:
        case, selected_bank, count = bank(selection)
        mode = selection['options']['loot_runtime_mode']
        source = 'server-response' if selection['kind'] == 'mp' else 'sp-main-tick'
        authority = dict(role='client1', case=case, runtimeMode=mode, status='complete', cases=count, source=source)
        final = dict(role='client1', case=case, runtimeMode=mode, status='complete', authority=True)
        return (role == 'client1' and _records(text, 'AUTHORITY') == [authority]
                and _records(text, 'COMPLETE') == [final] and not _records(text, 'FAIL')
                and text.index(MARKER + 'AUTHORITY ') < text.index(MARKER + 'COMPLETE ')
                and '[LOOT_RESOLVED_RUNTIME] FINISH status=failed' not in text
                and (selection['kind'] == 'mp' or text.index('[LOOT_RESOLVED_RUNTIME] FINISH status=complete cases=' + str(count) + ' reason=') < text.index(MARKER + 'AUTHORITY ') and len(re.findall(r'\[LOOT_RESOLVED_RUNTIME\] FINISH status=complete cases=' + str(count) + r' reason=\s*(?:\n|$)', text)) == 1))
    except (KeyError, ValueError):
        return False


def _compare(project):
    spec = importlib.util.spec_from_file_location('_loot_native_receipts', Path(project) / 'tests/chunk_integration/loot_resolved_runtime/compare.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _activation(compare, cache, pid, mode, native_hash, resource_profile, manifest_sha, checked, selected_bank):
    value = compare.values(cache / ('loot-resolved-runtime-activation-' + str(pid) + '.txt'))
    if (any(value.get(k) != v for k, v in dict(state='active', mode=mode, bank=selected_bank, pid=str(pid), definitions='1', input=native_hash, resource_profile=resource_profile, optimizer_manifest_sha256=manifest_sha,
                                                    runtime_profile_checked=str(checked).lower(), **compare.RNG_ACTIVATION).items())
            or not re.fullmatch('[0-9a-f]{64}', value.get('output', ''))
            or (value['input'] == value['output']) != (mode == 'control')):
        raise ValueError('Missing/failed/PID/profile-mismatched loot activation')
    return value


def verify(root, selection, catalog):
    root = Path(root); issues, evidence = [], {}
    try:
        validate(selection)
        case, selected_bank, count = bank(selection)
        runtime = json.loads((root / 'runtime.json').read_text())
        execution = json.loads((root / 'execution.json').read_text())
        cache = root / 'client1'
        project = Path(runtime['project'])
        token, inputs = bundle(cache, selection, project)
        host_marker = cache / HOST_AUTHORITY
        if selection['kind'] == 'mp':
            if host_marker.is_symlink() or not host_marker.is_file() or host_marker.read_text() != token + '\n':
                raise ValueError('Missing/foreign owned Host authority marker')
        elif host_marker.exists() or host_marker.is_symlink():
            raise ValueError('SP must not arm Host authority')
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
        optimized = bool(selection['options'].get('optimizer_archive'))
        client_profile = 'optimized-client' if optimized else 'native'
        authority_profile = 'native-host' if optimized and selection['kind'] == 'mp' else client_profile
        manifest_sha = inputs['optimizer_manifest_sha256'] or 'none'
        activation = _activation(compare, cache, pid, mode, native_hash, authority_profile, manifest_sha, True, selected_bank)
        client_activation = _activation(compare, cache, client_pid, mode, native_hash, client_profile,
                                        manifest_sha, selection['kind'] == 'sp', selected_bank)
        status, _, rows = compare.read(cache, mode)
        if any(status.get(key) != value for key, value in dict(resource_profile=authority_profile,
                optimizer_manifest_sha256=manifest_sha, runtime_profile_checked='true').items()):
            raise ValueError('Loot authority runtime profile/status mismatch')
        if status['pid'] != str(pid) or status.get('reason') or status.get('bank') != selected_bank:
            raise ValueError('Loot bank PID/status/selection mismatch')
        text = (root / 'client1-launch.log').read_text(errors='replace')
        auth = (root / (authority + '-launch.log')).read_text(errors='replace')
        finishes = re.findall(r'\[LOOT_RESOLVED_RUNTIME\] FINISH status=(\S+) cases=(\d+) reason=([^\r\n]*)', auth)
        if finishes != [('complete', str(count), '')] or auth.count(DIAGNOSTIC) != (0 if selected_bank == 'reload' else 1):
            raise ValueError('Missing/failed bank terminal or expected protected Lua diagnostic count differs')
        if not complete(selection, 'client1', text):
            raise ValueError('Loot completion missing authority handshake')
        if selection['kind'] == 'mp':
            requests, server_requests = _records(text, 'REQUEST'), _records(auth, 'REQUEST')
            if (len(requests) != 1 or len(server_requests) != 1
                    or type(requests[0].get('onlineID')) is not int or requests[0]['onlineID'] < 0
                    or requests[0] != dict(role='client1', case=case, runtimeMode=mode, onlineID=requests[0]['onlineID'])
                    or server_requests[0] != dict(role='server', case=case, runtimeMode=mode, onlineID=requests[0]['onlineID'])
                    or text.index(MARKER + 'REQUEST ') > text.index(MARKER + 'AUTHORITY ')
                    or auth.index(MARKER + 'REQUEST ') > auth.index('[LOOT_RESOLVED_RUNTIME] FINISH ')):
                raise ValueError('Missing/mismatched explicit owned client1 request')
            expected = dict(role='server', case=case, runtimeMode=mode, status='complete', cases=count, source='server-main-tick')
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
        evidence = dict(authority_pid=pid, runtime_mode=mode, status=status, activation=activation, client_activation=client_activation,
                        ordered_rows=len(rows)-1, rng_scope=compare.rng(cache,pid), clock_proofs=compare.clock_rows(rows, selected_bank != 'reload')[1],
                        bank=selected_bank, semantic_proofs=compare.semantic_rows(rows, selected_bank),
                        expected_protected_diagnostic=None if selected_bank == 'reload' else DIAGNOSTIC, requires_review=True,
                        limits=['Captured actual bank; matching control/candidate comparator and full log audit still required.',
                                *compare.limits(selected_bank)])
    except (OSError, ValueError, KeyError, TypeError, AttributeError, zipfile.BadZipFile) as error:
        issues.append(str(error))
    return dict(issues=issues, outcomes=[dict(actor='client1', case=selection.get('cases', [CASE])[0], status='failed' if issues else 'captured',
                reason='; '.join(issues))], evidence=evidence)
