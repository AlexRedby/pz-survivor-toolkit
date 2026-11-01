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
        'cases': [dict(id='lifecycle', producer='fixture', capability='effect', kinds=['sp', 'mp'],
                       modes=['toolkit'], languages=['EN'])]}}


def validate(s):
    o = s.get('options', {})
    if (s.get('cases') != ['lifecycle'] or s.get('kind') not in ('sp', 'mp')
            or s.get('mode') != 'toolkit' or s.get('clients') != 1 or s.get('languages') != ['EN']
            or not REQUIRED <= set(s.get('mods', [])) or MOD in s['mods']
            or s.get('resources', {}).get('exclusive') is not True
            or o.get('loot_demand_experiment') is not True or o.get('preload_toolkit_fonts') is not True
            or (s['kind'] == 'mp') != (o.get('mp_host') is True)
            or any(o.get(k) for k in ('world_template', 'seed_run', 'startup_connection'))):
        raise ValueError('Loot demand requires explicit fresh exclusive SP/menu Host lifecycle with the selected pack')


def sources(project, selection):
    p = Path(project)
    return [*sorted(x for x in (p / 'tests/native_queue/loot-demand').rglob('*')
                    if x.is_file() and x.suffix in ('.java', '.lua', '.py')),
            *sorted((p / 'tests/native_queue/startup').rglob('*.lua')),
            *optimizer_profile.sources(project, selection)]


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
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
        lua = cache / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            (lua / side).mkdir(parents=True, exist_ok=True)
            shutil.copy2(project / 'tests/native_queue/startup' / side / name, lua / side / name)
        for side in ('client', 'server', 'shared'):
            (lua / side).mkdir(parents=True, exist_ok=True)
            for path in sorted((base / side).glob('*.lua')):
                shutil.copy2(path, lua / side / path.name)
        mod = cache / 'mods' / MOD
        (mod / 'common').mkdir(parents=True)
        version = mod / '42'
        (version / 'media/java').mkdir(parents=True)
        (version / 'mod.info').write_text('name=Disposable on-demand loot experiment\nid=' + MOD
            + '\nversion=0.0.1\nversionMin=42.21\nversionMax=42.21\nrequire=\\ZombieBuddy\n'
            + 'ZBVersionMin=2.3.4\njavaPkgName=toolkit.lootdemandruntime\njavaJarFile=media/java/' + MOD + '.jar\n')
        with zipfile.ZipFile(version / 'media/java' / (MOD + '.jar'), 'w', zipfile.ZIP_DEFLATED) as jar:
            for path in sorted(build.rglob('*.class')):
                jar.write(path, path.relative_to(build).as_posix())
            jar.writestr('loot-demand-token.txt', token)
            jar.writestr('META-INF/loot-demand-inputs.json', json.dumps(hashes, sort_keys=True))
    runtime.setdefault('fixture', {}).setdefault('mods', []).append(MOD)
    runtime['fixture'].update(server_ready='[STARTUP_TEST] SERVER_READY', failure_markers=[PREFIX + 'FAIL ', '[LOOT_DEMAND] FAILURE '])
    optimizer_profile.stage(project, output, game, jdk, selection, runtime)
    (output / 'loot-demand-inputs.json').write_text(json.dumps({'test_only': True, 'sources': hashes,
        'furniture_sources': furniture_inputs,
        'limits': ['Synthetic containers with native lifecycle methods, not driving or full save/restart.']}, indent=2) + '\n')


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(re.escape(PREFIX) + r'COMPLETE lifecycle(?:\s|$)', text)) == 1


def verify(root, selection, catalog):
    root = Path(root)
    issues = []
    client = (root / 'client1-launch.log').read_text(errors='replace')
    authority = client if selection['kind'] == 'sp' else (root / 'server-launch.log').read_text(errors='replace')
    for label, text in [('client', client), ('authority', authority)]:
        if '[LOOT_DEMAND] INSTALLED isolated=true' not in text or PREFIX + 'FAIL ' in text:
            issues.append(label + ': missing activation or fixture failed')
    for case in ('bin', 'dumpster', 'existing-items', 'destroy-fill', 'empty-trash'):
        if len(re.findall(re.escape(PREFIX + 'PASS ' + case) + r'(?:\s|$)', authority)) != 1:
            issues.append('Missing/duplicate authority case: ' + case)
    if selection['kind'] == 'mp' and len(re.findall(re.escape(PREFIX + 'PASS native-request') + r'(?:\s|$)', authority)) != 1:
        issues.append('Missing/duplicate native Host content exchange')
    if not complete(selection, 'client1', client):
        issues.append('Missing/duplicate completion')
    return {'issues': issues, 'outcomes': [dict(actor='client1', case='lifecycle',
        status='failed' if issues else 'passed', reason='; '.join(issues))],
        'evidence': {'limits': ['Synthetic native containers; no driving gain, full save restart, two-client race or FPP move acceptance.']}}
