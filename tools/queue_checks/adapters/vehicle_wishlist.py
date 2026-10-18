"""Compatible vehicle wishes through real mechanics windows in a disposable SP/Host."""
from pathlib import Path
import re
import shutil

MARKER = '[VEHICLE_WISHLIST] '


def definitions():
    return {'vehicle-wishlist': {'status': 'ready', 'clients': 1, 'default_mods': ['PZSurvivorToolkit'],
            'cases': [{'id': 'mechanics', 'producer': 'fixture', 'capability': 'effect',
                       'kinds': ['sp', 'mp'], 'languages': ['EN', 'RU'], 'modes': ['toolkit']}]}}


def validate(selection):
    if (selection['cases'] != ['mechanics'] or selection['kind'] not in ('sp', 'mp')
            or selection['mode'] != 'toolkit' or selection['clients'] != 1
            or selection['languages'] not in (['EN'], ['RU'])
            or 'PZSurvivorToolkit' not in selection['mods']
            or selection.get('options', {}).get('world_template')):
        raise ValueError('Vehicle wishlist requires fresh SP/MP, one client and Toolkit')


def sources(project, selection):
    base = Path(project) / 'tests/native_queue'
    return sorted((base / 'vehicle-wishlist').rglob('*.lua')) + sorted((base / 'startup').rglob('*.lua'))


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    for role in runtime['roles']:
        target = Path(output) / role / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            shutil.copy2(Path(project) / 'tests/native_queue/startup' / side / name, target / side / name)
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
                                            failure_markers=[MARKER + 'FAIL '])


def complete(selection, role, text):
    return role == 'client1' and text.count(MARKER + 'COMPLETE mechanics') == 1


def verify(root, selection, catalog):
    text = (Path(root) / 'client1-launch.log').read_text(errors='replace')
    checks = re.findall(re.escape(MARKER) + r'PASS (\S+)', text)
    expected = ['native-menu', 'variants-and-classes', 'inventory-and-counts', 'mechanics-row', 'wishlist-label', 'done', 'mechanics-remove', 'inventory-remove']
    issues = [] if checks == expected and complete(selection, 'client1', text) and MARKER + 'FAIL ' not in text else ['Missing ordered vehicle Wishlist assertions']
    if selection['kind'] == 'mp':
        server = (Path(root) / 'server-launch.log').read_text(errors='replace')
        if re.findall(re.escape(MARKER) + r'AUTHORITY (open|done|removed-mechanics|removed-inventory)', server) != ['open', 'done', 'removed-mechanics', 'removed-inventory']:
            issues.append('Missing authoritative Host/server wishes')
    spawn_text = (Path(root) / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
    spawns = re.findall(re.escape(MARKER) + r'SPAWN (\S+) id=(-?\d+) square=(-?\d+,-?\d+)', spawn_text)
    if len(spawns) != 4 or len({row[1] for row in spawns}) != 4 or len({row[2] for row in spawns}) != 4:
        issues.append('Expected four distinct vehicles and spawn positions')
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': 'mechanics',
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues)}],
            'evidence': {'checks': checks, 'limits': ['Programmatic UI callbacks; screenshots require visual inspection; no physical input or remote peer coverage.']}}
