"""Menu-Host diagnostics controls, correlated acknowledgements and real trace files."""
from pathlib import Path
import re
import shutil

MARKER = '[VEHICLE_DIAGNOSTICS] '
MODS = ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit']
CHECKS = ['initial-off', 'host-ack-active', 'native-driver-authority',
          'recording-survives-close', 'reopen-active', 'host-ack-off', 'reopen-off']
SHOTS = ['vehicle-diagnostics-active.png', 'vehicle-diagnostics-off.png']


def definitions():
    return {'vehicle-diagnostics': {'status': 'ready', 'clients': 1, 'default_mods': MODS,
        'cases': [{'id': 'controls', 'producer': 'fixture', 'capability': 'effect',
                   'kinds': ['mp'], 'languages': ['EN', 'RU'], 'modes': ['toolkit']}]}}


def validate(selection):
    if (selection['cases'] != ['controls'] or selection['kind'] != 'mp'
            or selection['mode'] != 'toolkit' or selection['clients'] != 1
            or selection['languages'] not in (['EN'], ['RU'])
            or not set(MODS) <= set(selection['mods'])
            or selection.get('options', {}).get('mp_host') is not True
            or selection.get('options', {}).get('world_template')):
        raise ValueError('Vehicle diagnostics requires fresh menu Host, one client and Toolkit Java patches')


def sources(project, selection):
    base = Path(project) / 'tests/native_queue'
    return sorted((base / 'vehicle-diagnostics').rglob('*.lua')) + sorted((base / 'startup').rglob('*.lua'))


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    for role in runtime['roles']:
        target = Path(output) / role / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            shutil.copy2(Path(project) / 'tests/native_queue/startup' / side / name, target / side / name)
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
                                            failure_markers=[MARKER + 'FAIL '])


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(re.escape(MARKER) + r'COMPLETE controls\s*$', text, re.M)) == 1


def verify(root, selection, catalog):
    root = Path(root)
    text = (root / 'client1-launch.log').read_text(errors='replace')
    server = (root / 'server-launch.log').read_text(errors='replace')
    issues = []
    checks = re.findall(re.escape(MARKER) + r'PASS (\S+)', text)
    if checks != CHECKS or not complete(selection, 'client1', text) or MARKER + 'FAIL ' in text + server:
        issues.append('Missing ordered diagnostics controls assertions')
    spawns = re.findall(re.escape(MARKER) + r'SPAWN id=(-?\d+)', server)
    authority = re.findall(re.escape(MARKER) + r'AUTHORITY state=(active|off) id=(-?\d+) driver=(\d+)', server)
    vehicle = spawns[0] if len(spawns) == 1 else None
    if (vehicle is None or [row[0] for row in authority] != ['active', 'off']
            or any(row[1] != vehicle for row in authority)
            or len({row[2] for row in authority}) != 1):
        issues.append('Missing authoritative occupied vehicle active/off observations')
    paths, counts = {}, {}
    for side in ('client', 'server'):
        # A menu-Host child intentionally shares client1 cachedir; role directories separate logs.
        expected = root / 'client1/Logs/PZToolkitVehicleTrace' / side / 'vehicle-sync.log'
        recorded = re.findall(re.escape(MARKER + 'PATH ' + side + '=') + r'([^\r\n]+)', text)
        if recorded != [str(expected)]:
            issues.append('Incorrect isolated ' + side + ' trace path')
        paths[side] = str(expected)
        if not expected.is_file() or expected.is_symlink():
            issues.append('Missing ' + side + ' trace file'); continue
        trace = expected.read_text(errors='replace')
        sessions = re.findall(r'\[VEHICLE_SYNC\] t=\d+ event=session state=(active|off)', trace)
        samples = re.findall(r'\[VEHICLE_SYNC\] t=\d+ side=' + side
                             + r' event=(\w+) vehicle=(-?\d+) local=-?\d+ driver=(\d+) ', trace)
        counts[side] = len(samples)
        if sessions != ['active', 'off'] or not trace.rstrip().endswith('event=session state=off'):
            issues.append('Missing explicit ' + side + ' recording start/stop')
        driver = authority[0][2] if authority else None
        if not samples or any(row[1] != vehicle or row[2] != driver for row in samples):
            issues.append('Missing real occupied ' + side + ' vehicle samples')
    for name in SHOTS:
        if not (root / 'client1/Screenshots' / name).is_file():
            issues.append('Missing diagnostics screenshot: ' + name)
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': 'controls',
        'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues)}],
        'evidence': {'checks': checks, 'trace_paths': paths, 'sample_counts': counts, 'screenshots': SHOTS,
            'limits': ['Native checkbox callbacks and seated Base.CarNormal on one macOS menu Host client; no physical mouse input or remote peer coverage.',
                       'Screenshots require visual inspection; rotation and guest authorization are covered separately by JVM/Lua checks.']}}
