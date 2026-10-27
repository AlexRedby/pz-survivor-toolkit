"""Bounded native lot/animal-zone evidence; common runner owns launch, save/quit and templates."""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import zipfile
from .. import receipts
import optimizer_profile

SUITE, MARKER, WORLD = 'lot-streaming', '[LOT_STREAMING] ', 'PZDrivingBench-OptimizerTrial-LotStreaming'
SEED, PHASES, CELLS = 'PZ-Lot-Qualification-42.21', ['before', 'away', 'returned'], [(40, 34), (41, 34)]
START, AWAY, CHUNKS = (10323, 8752), (10595, 8752), [(1295, 1096), (1319, 1096)]
MODS = ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit']
LOT_HASH = 'c7dd6226fec81d27e761e661fcedc93164bf95fe07c59c3b2b0475c160d37b05'
POOL_HASH = '38c883df7d01b8d168510c0aaebf0fd02ad0ecd13630dd4adf2d35dcd6bd641e'


def definitions():
    return {SUITE: {'status': 'ready', 'native_validation': 'not-run', 'clients': 2, 'default_mods': MODS,
        'cases': [{'id': case, 'producer': 'fixture', 'capability': 'capture', 'kinds': ['sp', 'mp'],
                   'languages': ['EN', 'RU'], 'modes': ['toolkit']} for case in ('fresh', 'reload')]}}


def validate(s):
    o, kind = s.get('options', {}), s.get('kind')
    if (s.get('cases') not in (['fresh'], ['reload']) or kind not in ('sp', 'mp') or s.get('mode') != 'toolkit'
            or s.get('languages') not in ((['EN', 'RU'],) if kind == 'mp' else (['EN'], ['RU']))
            or type(s.get('clients')) is not int or s['clients'] != (2 if kind == 'mp' else 1)
            or not set(MODS) <= set(s.get('mods', [])) or kind == 'mp' and o.get('mp_host') is not True
            or kind == 'sp' and o.get('mp_host') or any(o.get(k) for k in ('seed_run', 'startup_connection'))
            or s.get('resources', {}).get('exclusive') is not True):
        raise ValueError('Lot streaming requires exclusive Toolkit SP or two-client EN/RU menu Host and Java Patches')
    if o.get('lot_locks_expect') not in ('control', 'patched'):
        raise ValueError('Explicit lot_locks_expect=control/patched required; it only validates loaded code')
    if bool(o.get('world_template')) != (s['cases'] == ['reload']):
        raise ValueError('Reload requires sealed world_template; fresh must create its own world')
    if 'optimizer_archive' in o and (type(o['optimizer_archive']) is not str
            or not Path(o['optimizer_archive']).is_absolute() or not Path(o['optimizer_archive']).is_file()):
        raise ValueError('optimizer_archive must be an explicit absolute official archive path')


def environment(selection, role, cache):
    return {'PZ_LOT_QUAL_CACHE': Path(cache)}


def sources(project, selection):
    base = Path(project) / 'tests/native_queue'
    return [*sorted((base / SUITE).rglob('*.lua')), *sorted((base / SUITE / 'java').glob('*.java')),
        *sorted((base / 'startup').rglob('*.lua')), base / 'health/shared/QueueHealthEvents.lua',
        *optimizer_profile.sources(project, selection)]


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    project, output, game, jdk = map(Path, (project, output, game, jdk))
    base, classes = project / 'tests/native_queue', output / 'lot-streaming-probe-classes'
    classes.mkdir()
    subprocess.run([str(jdk / 'bin/javac'), '--release', '25', '-cp',
        os.pathsep.join(str(game / j) for j in ('projectzomboid.jar', 'ZombieBuddy.jar')), '-d', str(classes),
        str(base / SUITE / 'java/Main.java')], check=True, capture_output=True, text=True, timeout=60,
        env={k: v for k, v in os.environ.items() if k not in ('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS')})
    for role, settings in runtime['roles'].items():
        cache = Path(settings['cache']); helper = cache / 'mods/LotStreamingProbe'
        (helper / 'common').mkdir(parents=True)
        jar = helper / '42/media/java/LotStreamingProbe.jar'; jar.parent.mkdir(parents=True)
        with zipfile.ZipFile(jar, 'x', zipfile.ZIP_DEFLATED) as bundle:
            for source in sorted(classes.rglob('*.class')):
                bundle.write(source, source.relative_to(classes).as_posix())
        (helper / '42/mod.info').write_text('name=Disposable native lot streaming probe\nid=LotStreamingProbe\n'
            'versionMin=42.21\nrequire=\\ZombieBuddy\njavaPkgName=net.alexredby.lotstreamingfixture\n'
            'javaJarFile=media/java/LotStreamingProbe.jar\n')
        settings.setdefault('env', {}).update({k: str(v) for k, v in environment(selection, role, cache).items()})
        # A real menu Host shares client1's cache and inherits that exact environment.
        lua = cache / 'mods/ActionQueueTest/42/media/lua'
        shutil.copy2(base / 'health/shared/QueueHealthEvents.lua', lua / 'shared/QueueHealthEvents.lua')
        shutil.copy2(base / 'startup/server/ZZStartupServer.lua', lua / 'server/ZZStartupServer.lua')
        starter = (base / 'startup/client/ZZStartup.lua').read_text()
        spawn = 'MapSpawnSelect.instance.selectedRegion={points={unemployed={{posX=10835,posY=10144,posZ=0}}}}'
        if starter.count(spawn) != 1: raise ValueError('Common native selectedRegion changed')
        starter = starter.replace(spawn, 'MapSpawnSelect.instance.selectedRegion={points={unemployed={{posX='
            + str(START[0]) + ',posY=' + str(START[1]) + ',posZ=0}}}}')
        if selection['cases'] == ['reload'] and selection['kind'] == 'sp':
            anchor = "  getWorld():setGameMode('Sandbox');getWorld():setWorld('QueueStartup');getWorld():setMap('Muldraugh, KY')"
            if starter.count(anchor) != 1: raise ValueError('Common SP starter changed')
            starter = starter.replace(anchor, "  if config.cases[1]=='reload'then MainScreen.continueLatestSave('Sandbox','" + WORLD + "');return end")
        else:
            starter = starter.replace("getWorld():setWorld('QueueStartup')", "getWorld():setWorld('" + WORLD + "')")
            anchor = "\n  MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'})"
            if selection['kind'] == 'sp':
                if starter.count(anchor) != 1: raise ValueError('Common SP character starter changed')
                starter = starter.replace(anchor, "\n  assert(MapSpawnSelect.instance.seedTextBox,'Native seed UI unavailable')\n"
                    "  MapSpawnSelect.instance.seedTextBox:setText('" + SEED + "')\n"
                    "  WorldGenParams.INSTANCE:setSeedString('" + SEED + "')\n" + anchor)
        (lua / 'client/ZZStartup.lua').write_text(starter)
    if selection['kind'] == 'mp':
        path = output / 'server/Server/queue-smoke.ini'
        text = path.read_text()
        if len(re.findall(r'^SpawnPoint=.*$', text, flags=re.M)) != 1: raise ValueError('Common Host SpawnPoint changed')
        text = re.sub(r'^SpawnPoint=.*$', 'SpawnPoint=' + ','.join(map(str, (*START, 0))), text, flags=re.M)
        path.write_text(re.sub(r'^Seed=.*\n?', '', text, flags=re.M).rstrip('\n') + '\nSeed=' + SEED + '\n')
    runtime.setdefault('fixture', {}).update(mods=['LotStreamingProbe'], server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=[MARKER + 'FAIL '], client_launch_stagger_seconds=8)
    optimizer_profile.stage(project, output, game, jdk, selection, runtime)


def complete(selection, role, text):
    return receipts.records(text, MARKER, 'COMPLETE') == [{'case': selection['cases'][0], 'role': role}]


def _runtime(p, expected, server, client):
    if p.get('ok') is not True or p.get('format') != 1: raise ValueError('Native probe failed: ' + str(p.get('error')))
    if (p.get('server'), p.get('client')) != (server, client) or p.get('seedString') != SEED:
        raise ValueError('Native role or fixed worldgen seed differs')
    methods = p.get('getMethods', [])
    if ([r.get('overload') for r in methods] != ['primitive', 'boxed']
            or any(r.get('synchronized') is not (expected == 'control')
                   or r.get('modifiers') != (41 if expected == 'control' else 9) for r in methods)):
        raise ValueError('Actual loaded IsoLot.get modifiers differ')
    proof = p.get('bootstrap', {})
    if expected == 'patched':
        if (proof.get('available') is not True or proof.get('active') is not True or proof.get('state') != 'active'
                or proof.get('transformations') != 1 or proof.get('lotInputHash') != LOT_HASH or proof.get('poolInputHash') != POOL_HASH):
            raise ValueError('Missing exact guarded bootstrap transformation proof')
    elif proof.get('active') is True or proof.get('transformations', 0) != 0:
        raise ValueError('Control unexpectedly transformed IsoLot')
    maps = p.get('mapFiles', [])
    if not maps or any(r.get('index') != i or r.get('indexMatchesPriority') is not True for i, r in enumerate(maps)):
        raise ValueError('Native map priority registration differs')


def _cells(p, generated=False):
    if p.get('ok') is not True: raise ValueError('Native cell probe failed: ' + str(p.get('error')))
    cells = p.get('cells', [])
    if [(r.get('x'), r.get('y')) for r in cells] != CELLS: raise ValueError('Missing/reordered bounded meta cells')
    for c in cells:
        if generated and (c.get('loaded') is not True or c.get('generated') is not True):
            raise ValueError('Streamed cell did not naturally generate animal zones')
        if c.get('loaded'):
            rt = c.get('generatedBitRoundtrip', {})
            if (not re.fullmatch('[0-9a-f]{64}', str(c.get('geometrySha256', '')))
                    or type(c.get('animalZones')) is not int or c['animalZones'] < 0 or rt.get('savedBytes') != 1
                    or rt.get('consumedBytes') != 1 or rt.get('matches') is not True or rt.get('restored') != c.get('generated')):
                raise ValueError('Missing geometry/native generated-bit roundtrip evidence')
    return {(c['x'], c['y']): (c.get('generated'), c.get('animalZones'), c.get('geometrySha256')) for c in cells}


def _baseline(p, server):
    # Also reject manually edited/legacy full receipts; compact strings alone enter ModData.
    if len(json.dumps(p, ensure_ascii=False, separators=(',', ':')).encode('utf-8')) > 8192:
        raise ValueError('Compact baseline exceeds native-safe UTF-8 byte bound')
    if (set(p) != {'format', 'ok', 'kind', 'world', 'server', 'client', 'seedString', 'cells'}
            or type(p.get('format')) is not int or p['format'] != 1 or p.get('ok') is not True
            or p.get('kind') != 'lot-streaming-baseline' or p.get('seedString') != SEED
            or p.get('world') != ('queue-smoke' if server else WORLD)
            or p.get('server') is not server or p.get('client') is not False):
        raise ValueError('Compact baseline schema/world/authority identity differs')
    cells = p['cells']
    if type(cells) is not list or len(cells) != len(CELLS):
        raise ValueError('Compact baseline cell count differs')
    for c, position in zip(cells, CELLS):
        if (type(c) is not dict or set(c) != {'x', 'y', 'loaded', 'generated', 'animalZones', 'geometrySha256'}
                or type(c.get('x')) is not int or type(c.get('y')) is not int
                or (c['x'], c['y']) != position or type(c.get('loaded')) is not bool):
            raise ValueError('Compact baseline cell schema/identity differs')
        if c['loaded']:
            if (type(c['generated']) is not bool or type(c['animalZones']) is not int
                    or not 0 <= c['animalZones'] <= 8192
                    or not re.fullmatch('[0-9a-f]{64}', str(c['geometrySha256']))):
                raise ValueError('Compact baseline generated/count/digest differs')
        elif any(c[k] is not None for k in ('generated', 'animalZones', 'geometrySha256')):
            raise ValueError('Unloaded compact baseline contains generated state')
    return {(c['x'], c['y']): (c['generated'], c['animalZones'], c['geometrySha256']) for c in cells}


def verify(root, selection, catalog):
    root, expected = Path(root), selection['options']['lot_locks_expect']
    roles = ['client1', 'client2'] if selection['kind'] == 'mp' else ['client1']
    issues, evidence = [], {}
    try:
        for role in roles + (['server'] if selection['kind'] == 'mp' else []):
            text = (root / (role + '-launch.log')).read_text(errors='replace')
            if MARKER + 'FAIL ' in text or '[QUEUE_TEST] FAIL ' in text: raise ValueError(role + ': fixture/bootstrap failure')
            server, authority = role == 'server', role == 'server' or selection['kind'] == 'sp'
            snapshots = receipts.records(text, MARKER, 'SNAPSHOT')
            if server:
                if sorted({r.get('role') for r in snapshots}) != roles: raise ValueError('Missing server actor snapshots')
                grouped = {a: [r for r in snapshots if r.get('role') == a] for a in roles}
            else:
                if not complete(selection, role, text): raise ValueError(role + ': missing/duplicate completion')
                grouped = {role: snapshots}
            if authority:
                persisted = receipts.records(text, MARKER, 'PERSIST_BASELINE')
                baselines = receipts.records(text, MARKER, 'BASELINE')
                if sorted(r.get('role') for r in persisted) != sorted(grouped):
                    raise ValueError('Missing/duplicate authoritative compact persistence receipts')
                if sorted(r.get('role') for r in baselines) != (sorted(grouped) if selection['cases'] == ['reload'] else []):
                    raise ValueError('Missing/duplicate saved compact baseline receipts')
            for actor, rows in grouped.items():
                if [r.get('phase') for r in rows] != PHASES or any(r.get('role') != actor for r in rows):
                    raise ValueError(role + ': missing, duplicate or reordered phases')
                for row in rows:
                    _runtime(row['probe']['runtime'], expected, server, selection['kind'] == 'mp' and not server)
                    _cells(row['probe'], authority and row['phase'] != 'before')
                if authority:
                    compact = [r for r in persisted if r['role'] == actor][0]
                    if compact.get('phase') != 'returned' or _baseline(compact['probe'], server) != _cells(rows[-1]['probe']):
                        raise ValueError('Compact persisted baseline differs from final native snapshot')
                    if sum(c.get('animalZones', 0) for c in rows[-1]['probe']['cells']) == 0:
                        raise ValueError('No actual animal-zone geometry was exercised')
                    if selection['cases'] == ['fresh'] and rows[0]['probe']['cells'][1].get('generated') is True:
                        raise ValueError('Fresh destination was already generated before streaming')
                    if selection['cases'] == ['reload']:
                        prior = [r for r in baselines if r.get('role') == actor]
                        if (len(prior) != 1 or prior[0].get('phase') != 'saved'
                                or _baseline(prior[0]['probe'], server) != _cells(rows[0]['probe'])):
                            raise ValueError('Saved geometry/generated bits did not survive reload')
            if not server:
                moves = receipts.records(text, MARKER, 'TRANSITION')
                if ([r.get('phase') for r in moves] != ['away', 'returned'] or any(r.get('role') != role
                        or not 1 <= r.get('steps', 0) <= 40 or r.get('distance', 0) < 250 or r.get('maxStep', 100) > 16 for r in moves)):
                    raise ValueError(role + ': missing bounded actual streaming transition')
                for row, target in zip(moves, (AWAY, START)):
                    if any(type(row.get(k)) not in (int, float) or abs(row[k] - v) > 4 for k, v in zip(('x', 'y'), target)) or row.get('z') != 0:
                        raise ValueError('Native transition did not reach the selected authored site')
                trees = receipts.records(text, MARKER, 'TREES')
                if [r.get('phase') for r in trees] != PHASES: raise ValueError('Missing authored tree phases')
                for row in trees:
                    p = row['probe']; _runtime(p['runtime'], expected, False, selection['kind'] == 'mp')
                    if p.get('ok') is not True or len(p.get('chunks', [])) != 2: raise ValueError('Native tree probe failed')
                    if [(c.get('wx'), c.get('wy')) for c in p['chunks']] != CHUNKS:
                        raise ValueError('Native authored tree chunk identities differ')
                    for c in p['chunks']:
                        if type(c.get('trees')) is not int or not 0 <= c['trees'] <= 64 or not c.get('authoredLayers'):
                            raise ValueError('Missing native tree/map layer data')
                        if any(not re.fullmatch('[0-9a-f]{64}', str(layer.get('payloadSha256', ''))) for layer in c['authoredLayers']):
                            raise ValueError('Missing native parsed payload digest')
                if receipts.records(text, MARKER, 'SAVE_READY') != [{'case': selection['cases'][0], 'role': role, 'nativeSave': selection['kind'] == 'sp'}]:
                    raise ValueError('Missing native save or Host save readiness')
            evidence[role] = {'snapshots': snapshots, 'baselines': receipts.records(text, MARKER, 'BASELINE'),
                'persisted_baselines': receipts.records(text, MARKER, 'PERSIST_BASELINE'), 'trees': receipts.records(text, MARKER, 'TREES')}
        if selection['kind'] == 'mp':
            text = (root / 'server-launch.log').read_text(errors='replace'); ready = receipts.records(text, MARKER, 'READY')
            if (sorted(r.get('role') for r in ready) != roles or len({r.get('onlineID') for r in ready}) != 2
                    or any(type(r.get('onlineID')) is not int or r['onlineID'] < 0 for r in ready)):
                raise ValueError('Missing distinct Host/joining-peer authority readiness')
            if selection.get('options', {}).get('optimizer_archive') and ('[OptimizerTrialProbe] native server resources=' not in text or 'overlayAbsent=true' not in text):
                raise ValueError('Host optimizer-overlay isolation not proved')
    except (OSError, ValueError, KeyError, TypeError) as error:
        issues.append(str(error))
    return {'issues': issues, 'outcomes': [{'actor': r, 'case': selection['cases'][0], 'status': 'failed' if issues else 'captured',
        'reason': '; '.join(issues)} for r in roles], 'evidence': {'actors': evidence, 'limits': [
        'No frame-time, speedup or RNG-equivalence claim. Native reads use private generator cache and native lot pool.',
        'Selected cells contain authored wildlife geometry; natural generated-bit transitions do not prove creation of random wildlife paths.',
        'Detached generated-bit roundtrip and separate saved authoritative geometry/bit reload evidence.',
        'UUID/dynamic spawn state excluded from geometry comparisons. Common Host save/quit and world-template guards remain required.']}}
