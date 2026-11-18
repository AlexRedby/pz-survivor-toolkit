"""Opt-in native bin/dumpster lifecycle fixture; no driving-performance claim."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import zipfile
import optimizer_profile

MOD = 'PZLootDemandExperiment'
PREFIX = '[LOOT_DEMAND_TEST] '
REQUIRED = {'ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit', 'FurniturePushPull'}


def definitions():
    return {'loot-demand': {'status': 'ready', 'clients': 1, 'default_mods': sorted(REQUIRED),
        'cases': [dict(id=case, producer='fixture', capability='effect', kinds=['sp', 'mp'],
                       modes=['toolkit'], languages=['EN']) for case in ('lifecycle', 'persist-seed', 'persist-reload', 'furniture')]
        + [dict(id='natural',producer='fixture',capability='effect',kinds=['mp'],modes=['toolkit'],languages=['EN'])]}}


def validate(s):
    o = s.get('options', {})
    if (s.get('cases') not in (['lifecycle'], ['persist-seed'], ['persist-reload'], ['natural'], ['furniture']) or s.get('kind') not in ('sp', 'mp')
            or s.get('mode') != 'toolkit' or s.get('clients') != 1 or s.get('languages') != ['EN']
            or not REQUIRED <= set(s.get('mods', [])) or MOD in s['mods']
            or s.get('resources', {}).get('exclusive') is not True
            or o.get('loot_demand_experiment') is not True or o.get('preload_toolkit_fonts') is not True
            or (s['kind'] == 'mp') != (o.get('mp_host') is True)
            or any(o.get(k) for k in ('seed_run', 'startup_connection'))):
        raise ValueError('Loot demand requires explicit exclusive SP/menu Host with the selected pack')
    if s['cases'] == ['natural']:
        if s['kind'] != 'mp' or o.get('loot_demand_arm') not in ('defer', 'observe') or o.get('optimizer_archive'):
            raise ValueError('Natural access requires a current menu Host and explicit loot arm')
    elif 'loot_demand_arm' in o:
        raise ValueError('Lifecycle fixtures use the ordinary on-demand experiment')
    if bool(o.get('world_template')) != (s['cases'] == ['persist-reload']):
        raise ValueError('Only persist-reload requires a sealed world_template')


def sources(project, selection):
    p = Path(project)
    return [*sorted(x for x in (p / 'tests/native_queue/loot-demand').rglob('*')
                    if x.is_file() and x.suffix in ('.java', '.lua', '.py')),
            *sorted((p / 'tests/native_queue/startup').rglob('*.lua')),
            *optimizer_profile.sources(project, selection)]


def stage_probe(project, output, game, jdk, selection, locations, runtime, arm):
    if arm not in (None, 'observe', 'defer') or not selection['resources'].get('exclusive'):
        raise ValueError('A disposable exclusive loot experiment is required')
    project, output, game, jdk = map(Path, (project, output, game, jdk))
    base = project / 'tests/native_queue/loot-demand'
    spec = importlib.util.spec_from_file_location('loot_demand_furniture_checks', base / 'furniture_checks.py')
    furniture = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(furniture)
    furniture_inputs = furniture.source_receipt(locations['FurniturePushPull'])
    java = [*sorted((base / 'java').glob('*.java')), *sorted((base / 'runtime').glob('*.java'))]
    build = output / 'loot-demand-classes'
    build.mkdir()
    env = {k: v for k, v in os.environ.items() if k not in ('JAVA_TOOL_OPTIONS', '_JAVA_OPTIONS', 'JDK_JAVA_OPTIONS')}
    result = subprocess.run([str(jdk / 'bin/javac'), '--release', '25', '-cp',
        os.pathsep.join(str(game / x) for x in ('projectzomboid.jar', 'ZombieBuddy.jar')),
        '-d', str(build), *map(str, java)], capture_output=True, text=True, timeout=60, env=env)
    (output / 'loot-demand-compile.log').write_text(result.stdout + result.stderr)
    result.check_returncode()
    token = secrets.token_hex(16)
    hashes = {str(p.relative_to(project)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources(project, selection) if p.is_relative_to(project)}
    for role, settings in runtime['roles'].items():
        cache = Path(settings['cache'])
        marker = cache / 'Lua/smoke-user.txt'
        if cache.resolve() != output.resolve() / role or not marker.is_file() or marker.read_text().strip() != role:
            raise ValueError('Demand token requires actual owned profile marker')
        (cache / 'loot-demand.opt-in').write_text(token + '\n')
        mod = cache / 'mods' / MOD
        (mod / 'common').mkdir(parents=True)
        version = mod / '42'
        (version / 'media/java').mkdir(parents=True)
        (version / 'mod.info').write_text('name=Disposable on-demand loot experiment\nid=' + MOD
            + '\nversion=0.0.1\nversionMin=42.22\nversionMax=42.22\nrequire=\\ZombieBuddy\n'
            + 'ZBVersionMin=2.3.4\njavaPkgName=toolkit.lootdemandruntime\njavaJarFile=media/java/' + MOD + '.jar\n')
        with zipfile.ZipFile(version / 'media/java' / (MOD + '.jar'), 'w', zipfile.ZIP_DEFLATED) as jar:
            for path in sorted(build.rglob('*.class')):
                jar.write(path, path.relative_to(build).as_posix())
            if arm is not None:
                jar.writestr('loot-demand-arm.txt', arm.encode('ascii'))
            jar.writestr('loot-demand-token.txt', token)
            jar.writestr('META-INF/loot-demand-inputs.json', json.dumps(hashes, sort_keys=True))
    runtime.setdefault('fixture', {}).setdefault('mods', []).append(MOD)
    (output / 'loot-demand-inputs.json').write_text(json.dumps(
        {'test_only': True, 'arm': arm, 'sources': hashes, 'furniture_sources': furniture_inputs}, indent=2) + '\n')
    if arm == 'defer' and selection['suite'] != 'loot-demand':
        for settings in runtime['roles'].values():
            target = Path(settings['cache']) / 'mods/ActionQueueTest/42/media/lua/shared'
            target.mkdir(parents=True, exist_ok=True)
            shutil.copy2(base / 'shared/LootDemandFurniture.lua', target)


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    project, output = Path(project), Path(output)
    options = selection['options']
    stage_probe(project, output, game, jdk, selection, locations, runtime, options.get('loot_demand_arm'))
    for settings in runtime['roles'].values():
        cache = Path(settings['cache'])
        lua = cache / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            (lua / side).mkdir(parents=True, exist_ok=True)
            shutil.copy2(project / 'tests/native_queue/startup' / side / name, lua / side / name)
        if selection['kind'] == 'sp':
            starter = lua / 'client/ZZStartup.lua'
            text = starter.read_text()
            world = 'PZDrivingBench-OptimizerTrial-LootDemand'
            anchor = "  getWorld():setGameMode('Sandbox');getWorld():setWorld('QueueStartup');getWorld():setMap('Muldraugh, KY')"
            if text.count(anchor) != 1:
                raise ValueError('Common SP starter changed')
            replacement = anchor.replace('QueueStartup', world)
            if selection['cases'] == ['persist-reload']:
                replacement = f"  MainScreen.continueLatestSave('Sandbox','{world}');return"
                replacement = f"  if config.cases[1]=='persist-reload' then {replacement} end"
            starter.write_text(text.replace(anchor, replacement))
    fixture = runtime['fixture']
    fixture.update(server_ready='[STARTUP_TEST] SERVER_READY',
                   failure_markers=[PREFIX + 'FAIL ', '[LOOT_DEMAND] FAILURE ', '[LOOT_NATURAL] FAIL '])
    if selection['cases'] == ['natural']:
        ini = output / 'server/Server/queue-smoke.ini'
        text = re.sub(r'^Seed=.*\n?', '', ini.read_text(), flags=re.M)
        text, changed = re.subn(r'^SpawnPoint=.*$', 'SpawnPoint=10849,10147,0', text, flags=re.M)
        if changed != 1:
            raise ValueError('Natural Host requires one isolated spawn point')
        ini.write_text(text.rstrip() + '\nSeed=PZLootNatural4222\n')
    optimizer_profile.stage(project, output, game, jdk, selection, runtime)


def complete(selection, role, text):
    if selection['cases'] == ['natural']:
        return role == 'client1' and text.count('[LOOT_NATURAL] COMPLETE ') == 1
    return role == 'client1' and len(re.findall(re.escape(PREFIX) + 'COMPLETE ' + re.escape(selection['cases'][0]) + r'(?:\s|$)', text)) == 1


def verify(root, selection, catalog):
    root = Path(root)
    issues = []
    client = (root / 'client1-launch.log').read_text(errors='replace')
    authority = client if selection['kind'] == 'sp' else (root / 'server-launch.log').read_text(errors='replace')
    for label, text in [('client', client), ('authority', authority)]:
        if '[LOOT_DEMAND] INSTALLED isolated=true' not in text or PREFIX + 'FAIL ' in text:
            issues.append(label + ': missing activation or fixture failed')
    case = selection['cases'][0]
    if case == 'natural':
        if not complete(selection, 'client1', client) or '[LOOT_NATURAL] RESULT ' not in authority:
            issues.append('Missing completed approach and authoritative result')
        if '[LOOT_NATURAL] FAIL ' in client + authority:
            issues.append('Natural approach fixture reported failure')
        return {'issues': issues, 'outcomes': [dict(actor='client1', case=case,
            status='failed' if issues else 'passed', reason='; '.join(issues))],
            'evidence': {'first_fill_timed': bool(re.search(r'\[LOOT_NATURAL\] RESULT role=server [^\n]* fill_kind=(?:demand|automatic) fill_ns=\d+', authority)),
                         'limits': ['Natural menu Host map load and on-foot approach. A missing fill duration is unavailable; inventory delivery is checked independently. No driving FPS inference.']}}
    if case == 'furniture':
        for empty in ('false', 'true'):
            if len(re.findall(r'\[LOOT_FURNITURE\] PASS mode=(?:sp|host-authority) empty=' + empty + r'\s', authority)) != 1:
                issues.append('Missing/duplicate actual furniture empty=' + empty)
        if authority.count('[LOOT_FURNITURE] OWNED_PENDING_PRESERVED bothMembers=true') != 1:
            issues.append('Missing owned pending member preservation')
        if selection['kind'] == 'mp':
            if authority.count('[LOOT_FURNITURE] PASS host-native-client-content-overlay ') != 1:
                issues.append('Missing independent native client contents/overlay confirmation')
            if authority.count(PREFIX + 'PASS native-request') != 1:
                issues.append('Missing separate native request exchange')
        if not complete(selection, 'client1', client):
            issues.append('Missing/duplicate completion')
        return {'issues': issues, 'outcomes': [dict(actor='client1', case=case,
            status='failed' if issues else 'passed', reason='; '.join(issues))],
            'evidence': {'limits': ['Actual selected mod complete() called directly on native authority; no client UI/timed-action dispatch.',
                'Native pickup/place and exact item references checked; controlled empty callback result.',
                'Host observes native multipart contents/overlay equality; nil overlays are allowed. No client UI/timed-action dispatch or two-client race.']}}
    expected = [] if case == 'persist-reload' else ['bin', 'dumpster', 'existing-items', 'destroy-fill', 'empty-trash']
    if case != 'lifecycle':
        expected.append(case)
    if case == 'persist-reload':
        expected.append('native-moveable-roundtrip')
    for case in expected:
        if len(re.findall(re.escape(PREFIX + 'PASS ' + case) + r'(?:\s|$)', authority)) != 1:
            issues.append('Missing/duplicate authority case: ' + case)
    if selection['kind'] == 'mp' and selection['cases'] != ['persist-reload'] and len(re.findall(re.escape(PREFIX + 'PASS native-request') + r'(?:\s|$)', authority)) != 1:
        issues.append('Missing/duplicate native Host content exchange')
    if not complete(selection, 'client1', client):
        issues.append('Missing/duplicate completion')
    return {'issues': issues, 'outcomes': [dict(actor='client1', case=selection['cases'][0],
        status='failed' if issues else 'passed', reason='; '.join(issues))],
        'evidence': {'limits': ['Synthetic native containers; persist-reload alone covers stopped-world contents. No driving gain, two-client race or FPP move acceptance.']}}
