"""Native seated door control and authoritative Host completion."""
from pathlib import Path
import os
import subprocess
import zipfile
import re
import shutil

MARKER = '[VEHICLE_DOORS] '


def definitions():
    return {'vehicle-doors': {'status': 'ready', 'clients': 1, 'default_mods': ['PZSurvivorToolkit'],
            'cases': [{'id': 'close', 'producer': 'fixture', 'capability': 'effect',
                       'kinds': ['sp', 'mp'], 'languages': ['EN', 'RU'], 'modes': ['toolkit']}]}}


def validate(selection):
    if (selection['cases'] != ['close'] or selection['kind'] not in ('sp', 'mp')
            or selection['mode'] != 'toolkit' or selection['clients'] != 1
            or selection['languages'] not in (['EN'], ['RU'])
            or 'PZSurvivorToolkit' not in selection['mods']
            or selection.get('options', {}).get('world_template')):
        raise ValueError('Vehicle doors requires fresh SP/Host, one client and Toolkit')


def sources(project, selection):
    base = Path(project) / 'tests/native_queue'
    return sorted(path for path in (base / 'vehicle-doors').rglob('*') if path.suffix in ('.lua', '.java')) + sorted((base / 'startup').rglob('*.lua'))


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    for role in runtime['roles']:
        target = Path(output) / role / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            shutil.copy2(Path(project) / 'tests/native_queue/startup' / side / name, target / side / name)
    classes = Path(output) / 'radial-capture-classes'
    classes.mkdir()
    source = Path(project) / 'tests/native_queue/vehicle-doors/support/VehicleDoorRadialCapture.java'
    javac = Path(jdk) / 'bin' / ('javac.exe' if os.name == 'nt' else 'javac')
    subprocess.run([str(javac), '--release', '25', '-cp', str(game / 'projectzomboid.jar'), '-d', str(classes), str(source)],
                   check=True, capture_output=True, text=True, timeout=60)
    jar = Path(output) / 'radial-capture.jar'
    with zipfile.ZipFile(jar, 'w') as archive:
        archive.writestr('META-INF/MANIFEST.MF', 'Manifest-Version: 1.0\nAgent-Class: zombie.ui.VehicleDoorRadialCapture\n\n')
        for path in classes.rglob('*.class'):
            archive.write(path, path.relative_to(classes).as_posix())
    runtime.setdefault('fixture', {})['attach'] = {'client1': [{
        'jar': str(jar), 'output': str(Path(output) / 'client1'),
        'classpath': str(classes) + os.pathsep + str(game / 'projectzomboid.jar'),
        'class': 'zombie.ui.VehicleDoorRadialCapture', 'ready': '[VEHICLE_DOORS] RADIAL_CAPTURE_READY'}]}
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
                                            failure_markers=[MARKER + 'FAIL '])


def complete(selection, role, text):
    return role == 'client1' and text.count(MARKER + 'COMPLETE close') == 1


def verify(root, selection, catalog):
    text = (Path(root) / 'client1-launch.log').read_text(errors='replace')
    checks = re.findall(re.escape(MARKER) + r'PASS (\S+)', text)
    expected = ['seated-open-door', 'native-radial', 'dashboard-button', 'native-action-once', 'closed-driver-only', 'authority']
    issues = [] if checks == expected and complete(selection, 'client1', text) and MARKER + 'FAIL ' not in text else ['Missing ordered vehicle door assertions']
    source = (Path(root) / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
    if len(re.findall(re.escape(MARKER) + r'AUTHORITY closed-driver-only id=(-?\d+)', source)) != 1 or MARKER + 'FAIL ' in source:
        issues.append('Missing authoritative seated driver door completion')
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': 'close',
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues)}],
            'evidence': {'checks': checks, 'limits': ['Programmatic radial builder and dashboard callback, stationary driver; no physical input, moving-car or remote peer coverage.']}}
