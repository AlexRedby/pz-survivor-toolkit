"""Native one-shot vehicle entry/exit poses and cancellation in disposable SP/Host."""
from pathlib import Path
import re
import os
import subprocess
import zipfile
import shutil

MARKER = '[VEHICLE_POSE] '
CHECKS = ['enter-driver', 'cancel-exit', 'exit-driver', 'cancel-enter', 'enter-passenger', 'exit-passenger']


def definitions():
    return {'vehicle-pose': {'status': 'ready', 'clients': 1, 'default_mods': ['ZombieBuddy', 'PZSurvivorToolkit'],
            'cases': [{'id': 'transitions', 'producer': 'fixture', 'capability': 'effect',
                       'kinds': ['sp', 'mp'], 'languages': ['EN'], 'modes': ['toolkit']}]}}


def validate(selection):
    if (selection['cases'] != ['transitions'] or selection['kind'] not in ('sp', 'mp')
            or selection['mode'] != 'toolkit' or selection['clients'] != 1
            or selection['languages'] != ['EN'] or 'PZSurvivorToolkit' not in selection['mods']
            or 'ZombieBuddy' not in selection['mods']
            or selection.get('options', {}).get('world_template')
            or selection['kind'] == 'mp' and selection.get('options', {}).get('mp_host') is not True):
        raise ValueError('Vehicle poses require fresh SP/menu Host, one EN client and Toolkit')


def environment(selection, role, cache):
    return {'PZ_POSE_TEST_CACHE': Path(cache)} if role == 'client1' else {}


def sources(project, selection):
    base = Path(project) / 'tests/native_queue'
    return (sorted((base / 'vehicle-pose').rglob('*.lua'))
            + sorted((base / 'startup').rglob('*.lua'))
            + [base / 'vehicle-doors/shared/VehicleDoorsFixture.lua', base / 'vehicle-pose/Main.java'])


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    base = Path(project) / 'tests/native_queue'
    classes = Path(output) / 'pose-probe-classes'; classes.mkdir()
    subprocess.run([str(Path(jdk) / 'bin/javac'), '--release', '25', '-cp',
        os.pathsep.join(str(Path(game) / jar) for jar in ('projectzomboid.jar', 'ZombieBuddy.jar')),
        '-d', str(classes), str(base / 'vehicle-pose/Main.java')],
        check=True, capture_output=True, text=True, timeout=60)
    for role, settings in runtime['roles'].items():
        target = Path(output) / role / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            text = (base / 'startup' / side / name).read_text().replace('posX=10835,posY=10144', 'posX=10640,posY=10144')
            (target / side / name).write_text(text)
        shutil.copy2(base / 'vehicle-doors/shared/VehicleDoorsFixture.lua', target / 'shared/VehicleDoorsFixture.lua')
        helper = Path(settings['cache']) / 'mods/VehiclePoseProbe'
        jar = helper / '42/media/java/VehiclePoseProbe.jar'; jar.parent.mkdir(parents=True)
        with zipfile.ZipFile(jar, 'x') as archive:
            for source in sorted(classes.rglob('*.class')):
                archive.write(source, source.relative_to(classes).as_posix())
        (helper / '42/mod.info').write_text('name=Disposable vehicle pose probe\nid=VehiclePoseProbe\n'
            'versionMin=42.21\nrequire=\\ZombieBuddy\njavaPkgName=net.alexredby.vehicleposefixture\n'
            'javaJarFile=media/java/VehiclePoseProbe.jar\n')
        if role == 'client1':
            settings.setdefault('env', {})['PZ_POSE_TEST_CACHE'] = str(settings['cache'])
    if selection['kind'] == 'mp':
        ini = Path(output) / 'server/Server/queue-smoke.ini'
        ini.write_text(ini.read_text().replace('SpawnPoint=10835,10144,0', 'SpawnPoint=10640,10144,0'))
    runtime.setdefault('fixture', {}).update(mods=['VehiclePoseProbe'], server_ready='[STARTUP_TEST] SERVER_READY',
                                            failure_markers=[MARKER + 'FAIL '])


def complete(selection, role, text):
    return role == 'client1' and text.count(MARKER + 'COMPLETE transitions') == 1


def verify(root, selection, catalog):
    text = (Path(root) / 'client1-launch.log').read_text(errors='replace')
    checks = re.findall(re.escape(MARKER) + r'PASS (\S+)', text)
    issues = [] if checks == CHECKS and complete(selection, 'client1', text) and MARKER + 'FAIL ' not in text else ['Missing ordered vehicle transition assertions']
    authority = (Path(root) / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
    if re.findall(re.escape(MARKER) + r'AUTHORITY (\S+)', authority) != CHECKS:
        issues.append('Missing authoritative passenger occupancy checks')
    if re.findall(re.escape(MARKER) + r'POSE (\S+) ', text) != CHECKS:
        issues.append('Missing active native seated track probes')
    shots = [f'vehicle-pose-{name}.png' for name in CHECKS]
    for name in shots:
        if not (Path(root) / 'client1/Screenshots' / name).is_file():
            issues.append('Missing transition screenshot: ' + name)
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': 'transitions',
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues)}],
            'evidence': {'checks': checks, 'screenshots': shots,
                'limits': ['Programmatically queued native actions; screenshots require visual inspection. One client, stationary Base.CarNormal; no remote observer, moving vehicle or custom vehicle library coverage.']}}
