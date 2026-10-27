"""Bounded native lighting/movement evidence; screenshots need human visual review."""
from pathlib import Path
import math
import os
import subprocess
import zipfile
import struct
from .. import receipts
import optimizer_profile

SUITE = 'world-render'
MARKER = '[WORLD_RENDER] '
MODS = ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit']
CORE = ['first_arrival', 'torch_off', 'torch_on', 'torch_restored', 'walk_arrived']


def definitions():
    return {SUITE: {'status': 'ready', 'native_validation': 'not-run', 'clients': 2,
        'default_mods': MODS, 'cases': [{'id': 'lighting', 'producer': 'fixture',
        'capability': 'capture', 'kinds': ['sp', 'mp'], 'languages': ['EN', 'RU'], 'modes': ['toolkit']}],
        'limits': ['Discrete cached light/visibility observations are not pixel equivalence or a performance benchmark.']}}


def validate(selection):
    kind = selection.get('kind')
    clients = selection.get('clients', 2 if kind == 'mp' else 1)
    options = selection.get('options', {})
    if type(options.get('world_render_resources', False)) is not bool:
        raise ValueError('world_render_resources must be boolean')
    if options.get('world_render_resources') and 'ImmersiveSnow' not in selection.get('mods', []):
        raise ValueError('Resource scenario requires the selected ImmersiveSnow mod')
    if 'world_render_probe_expect' in options:
        raise ValueError('Obsolete clean-light probe option; use world_render_expect for cutaway snapshots')
    if options.get('world_render_expect', 'observe') not in ('observe', 'control', 'patched'):
        raise ValueError('world_render_expect must be observe/control/patched')
    if 'optimizer_archive' in options:
        archive = options['optimizer_archive']
        if type(archive) is not str or not Path(archive).is_absolute() or not Path(archive).is_file():
            raise ValueError('optimizer_archive must be an explicit absolute official archive path')
    if (selection.get('cases') != ['lighting'] or kind not in ('sp', 'mp')
            or selection.get('mode') != 'toolkit'
            or selection.get('languages') not in ((['EN', 'RU'],) if kind == 'mp' else (['EN'], ['RU']))
            or type(clients) is not int or clients != (2 if kind == 'mp' else 1)
            or not set(MODS) <= set(selection.get('mods', []))
            or any(options.get(key) for key in ('world_template', 'seed_run', 'startup_connection'))
            or kind == 'mp' and options.get('mp_host') is not True
            or kind == 'sp' and options.get('mp_host')):
        raise ValueError('World rendering requires fresh Toolkit SP or two-client menu Host, EN/RU and Java Patches')


def environment(selection, role, cache):
    return {'PZ_WORLD_RENDER_CACHE': Path(cache)} if role.startswith('client') else {}


def sources(project, selection):
    base = Path(project) / 'tests/native_queue'
    return [*sorted((base / SUITE).rglob('*.lua')), *sorted((base / SUITE / 'java').glob('*.java')), *sorted((base / 'startup').rglob('*.lua')),
            base / 'health/shared/QueueHealthEvents.lua', *optimizer_profile.sources(project, selection)]


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    base = Path(project) / 'tests/native_queue'
    classes = Path(output) / 'world-render-probe-classes'; classes.mkdir()
    subprocess.run([str(Path(jdk) / 'bin/javac'), '--release', '25', '-cp',
        os.pathsep.join(str(Path(game) / jar) for jar in ('projectzomboid.jar', 'ZombieBuddy.jar')),
        '-d', str(classes), str(base / SUITE / 'java/Main.java')],
        check=True, capture_output=True, text=True, timeout=60)
    for role, settings in runtime['roles'].items():
        cache = Path(settings['cache'])
        lua = cache / 'mods/ActionQueueTest/42/media/lua'
        helper = cache / 'mods/WorldRenderProbe'
        (helper / 'common').mkdir(parents=True)
        jar = helper / '42/media/java/WorldRenderProbe.jar'; jar.parent.mkdir(parents=True)
        with zipfile.ZipFile(jar, 'x', zipfile.ZIP_DEFLATED) as archive:
            for source in sorted(classes.rglob('*.class')):
                archive.write(source, source.relative_to(classes).as_posix())
        (helper / '42/mod.info').write_text('name=Disposable native cutaway snapshot probe\nid=WorldRenderProbe\n'
            'versionMin=42.21\nrequire=\\ZombieBuddy\njavaPkgName=net.alexredby.worldrenderfixture\n'
            'javaJarFile=media/java/WorldRenderProbe.jar\n')
        if role.startswith('client'):
            settings.setdefault('env', {})['PZ_WORLD_RENDER_CACHE'] = str(cache)
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua'),
                           ('shared', 'QueueHealthEvents.lua')]:
            source = base / ('health' if side == 'shared' else 'startup') / side / name
            text = source.read_text()
            if side == 'client':
                text = text.replace("getSandboxOptions():getOptionByName('Zombies'):setValue(6);",
                    "getSandboxOptions():getOptionByName('StartTime'):setValue(8);"
                    "getSandboxOptions():getOptionByName('ElecShutModifier'):setValue(365);"
                    "getSandboxOptions():getOptionByName('Zombies'):setValue(6);")
                text = text.replace("getWorld():setWorld('QueueStartup')", "getWorld():setWorld('QueueWorldRender')")
            (lua / side / name).write_text(text)
    runtime.setdefault('fixture', {}).update(mods=['WorldRenderProbe'], server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=[MARKER + 'FAIL '], client_launch_stagger_seconds=8,
        sandbox={'Zombies': 6, 'StartTime': 8, 'ElecShutModifier': 365})
    optimizer_profile.stage(project, output, game, jdk, selection, runtime)


def complete(selection, role, text):
    complete = receipts.records(text, MARKER, 'COMPLETE') == [{'case': 'lighting', 'role': role}]
    options = selection.get('options', {})
    if options.get('optimizer_prewarm') and role.startswith('client'):
        complete = complete and all(marker in text for marker in (
            '[OptimizerTrial] animation preload joined; animal preload started',
            '[OptimizerTrial] bake scheduler used frames=',
            'anim sets preloaded in ', 'action groups handed to the game'))
        if selection['kind'] == 'mp':
            complete = complete and all(marker in text for marker in (
                '[OptimizerTrial] bridge ready mode=multiplayer client=true server=false session=1',
                '[OptimizerTrial] animal drain invoked mode=multiplayer client=true server=false'))
    return complete


def verify(root, selection, catalog):
    root = Path(root)
    roles = ['client1', 'client2'] if selection['kind'] == 'mp' else ['client1']
    issues, evidence = [], {}
    for role in roles:
        try:
            text = (root / (role + '-launch.log')).read_text(errors='replace')
            phases = receipts.records(text, MARKER, 'PHASE')
            names = [row['name'] for row in phases]
            if names[:len(CORE)] != CORE or len(names) != len(set(names)) or not complete(selection, role, text):
                raise ValueError('Missing, duplicate or reordered native lighting phases')
            if MARKER + 'FAIL ' in text or '[QUEUE_TEST] FAIL ' in text:
                raise ValueError('Fixture/bootstrap failure marker')
            for row in phases:
                if row['role'] != role or not row['samples']:
                    raise ValueError('Wrong actor or empty native samples')
                for sample in row['samples']:
                    if not all(type(sample[key]) in (int, float) and math.isfinite(sample[key])
                               and 0 <= sample[key] <= 1.01 for key in ('r', 'g', 'b')):
                        raise ValueError('Invalid cached native light sample')
                path = root / role / 'Screenshots' / ('world-render-' + row['name'] + '.png')
                data = path.read_bytes()
                if (len(data) < 33 or data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR'
                        or min(struct.unpack('>II', data[16:24])) < 300):
                    raise ValueError('Missing/invalid native screenshot ' + row['name'])
            checks = receipts.records(text, MARKER, 'CHECK')
            if [row['name'] for row in checks[:2]] != ['torch-response', 'native-walk']:
                raise ValueError('Missing torch response or actual native walking assertion')
            if checks[0]['delta'] <= .02 or checks[0]['returnDelta'] <= .02 or checks[1]['distance'] < 2:
                raise ValueError('Lighting response or movement too small')
            probes = receipts.records(text, MARKER, 'CUTAWAY')
            if len(probes) != 1:
                raise ValueError('Missing/duplicate final native cutaway observation')
            probe = probes[0]
            for name in ('snapshots', 'observations', 'mismatches', 'asymmetric'):
                if type(probe.get(name)) is not int or not 0 <= probe[name] <= 64:
                    raise ValueError('Invalid bounded cutaway observation count: ' + name)
            if (probe.get('error') != '' or probe['mismatches'] > probe['observations']
                    or probe['asymmetric'] > probe['observations']):
                raise ValueError('Native cutaway observation failed')
            expectation = selection.get('options', {}).get('world_render_expect', 'observe')
            if expectation == 'patched' and (probe['observations'] == 0 or probe['mismatches'] != 0):
                raise ValueError('Patched south-edge cache must have observed edges and no mismatch')
            evidence[role] = {'phases': phases, 'checks': checks, 'cutaway': probe,
                              'limits': receipts.records(text, MARKER, 'LIMIT')}
            if selection.get('options', {}).get('world_render_resources'):
                resources = receipts.records(text, MARKER, 'RESOURCE')
                expected = [dict(role=role, stage='pending', draws=6, dimensionsUnchanged=True),
                            dict(role=role, stage='ready', draws=6, width=64, height=64,
                                 outlinePrograms=3, outlineIdentityStable=True)]
                if resources != expected or not all(name in names for name in ('decal_control', 'decal_ready', 'decal_restored')):
                    raise ValueError('Resource lifecycle scenario incomplete')
                if text.count('[PZToolkitJavaPatches] Outline composite shaders prepared on render context: 3') != 1:
                    raise ValueError('Expected exactly one successful outline preparation')
                evidence[role]['resources'] = resources
        except (OSError, ValueError, KeyError, TypeError) as error:
            issues.append(role + ': ' + str(error))
    if selection['kind'] == 'mp':
        try:
            server = (root / 'server-launch.log').read_text(errors='replace')
            ready = receipts.records(server, MARKER, 'READY')
            if sorted(row['role'] for row in ready) != roles or MARKER + 'FAIL ' in server:
                issues.append('Missing distinct Host/joining-client authority readiness')
            if selection.get('options', {}).get('optimizer_archive'):
                if ('[OptimizerTrialProbe] native server resources=' not in server
                        or 'overlayAbsent=true' not in server or '[OptimizerTrialProbe] FAIL ' in server):
                    issues.append('Native Host resource isolation was not proved')
            evidence['authority'] = receipts.records(server, MARKER, 'AUTHORITY')
            for role in roles:
                values = [row['active'] for row in evidence['authority']
                          if row.get('role') == role and row.get('kind') == 'torch']
                expected_torch = [False, True, False]
                if selection.get('options', {}).get('world_render_resources'):
                    expected_torch += [True, False]
                if values != expected_torch:
                    issues.append(role + ': authoritative torch off/on/off absent')
        except (OSError, ValueError, KeyError, TypeError) as error:
            issues.append('authority: ' + str(error))
    return {'issues': issues, 'outcomes': [{'actor': role, 'case': 'lighting',
        'status': 'failed' if issues else 'captured', 'reason': '; '.join(issues)} for role in roles],
        'evidence': {'actors': evidence, 'limits': [
            'Screenshots require separate visual review; RGB/visibility counters cannot prove visual equivalence.',
            'Bounded walking and local scene relocation; no actual high-speed vehicle or distant streaming acceptance.',
            'Natural window/tree/switch coverage is conditional and explicitly reported when unavailable.',
            'Discrete visibility getters may refresh native lighting; no direct dirty-byte/cacheLightInfo calls or CPU benchmark.',
            'Control records naturally observed south-cache mismatches; absent asymmetric geometry is not a control failure.']}}
