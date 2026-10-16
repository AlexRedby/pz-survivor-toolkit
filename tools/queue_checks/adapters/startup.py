"""Native readiness and optional restored-world room persistence verification."""
from pathlib import Path
import re


def definitions():
    return {'startup': {'status': 'ready', 'clients': 1, 'default_mods': ['PZSurvivorToolkit'],
                        'cases': [{'id': 'loaded', 'producer': 'fixture', 'capability': 'effect',
                                   'kinds': ['sp', 'mp'], 'languages': ['EN', 'RU'],
                                   'modes': ['toolkit', 'native']}]}}


def validate(selection):
    options = selection.get('options', {})
    if not isinstance(options, dict):
        raise ValueError('Startup options must be an object')
    if (selection.get('cases') != ['loaded'] or selection.get('kind') not in ('sp', 'mp')
            or selection.get('mode') not in ('toolkit', 'native')
            or type(selection.get('clients', 1)) is not int or selection.get('clients', 1) != 1
            or selection.get('languages') not in (['EN'], ['RU'])):
        raise ValueError('Startup requires loaded, SP/MP, native/toolkit and one EN/RU client')
    if selection['kind'] == 'sp' and options.get('world_template'):
        raise ValueError('Startup SP creates a fresh world; restored SP worlds are unsupported')
    if 'room_state_roundtrip' in options:
        template, mods = options.get('world_template'), selection.get('mods')
        if (options['room_state_roundtrip'] not in ('migrate', 'reload') or selection['kind'] != 'mp'
                or not isinstance(template, str) or not template.strip() or not Path(template).is_absolute()
                or not isinstance(mods, list) or 'PZToolkitJavaPatches' not in mods):
            raise ValueError('room_state_roundtrip requires migrate|reload, MP, an absolute world_template and PZToolkitJavaPatches')
    if 'startup_connection' in options:
        connection = options['startup_connection']
        if (selection['kind'] != 'mp' or not isinstance(connection, dict)
                or set(connection) != {'username', 'password'}
                or not isinstance(connection['username'], str)
                or not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}', connection['username'])
                or not isinstance(connection['password'], str) or not 1 <= len(connection['password']) <= 256
                or not connection['password'].isprintable()):
            raise ValueError('startup_connection requires MP, a safe username and a printable password of 1..256 characters')


def sources(project, selection):
    return sorted((Path(project) / 'tests/native_queue/startup').rglob('*.lua'))


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    runtime.setdefault('fixture', {})['server_ready'] = '[STARTUP_TEST] SERVER_READY'


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(r'\[STARTUP_TEST\] COMPLETE case=loaded(?:\s|$)', text)) == 1


def verify(root, selection, catalog):
    issues, positions = [], []
    try:
        text = (Path(root) / 'client1-launch.log').read_text(errors='replace')
        patterns = [r'\[QUEUE_TEST\] ' + ('NATIVE_CONNECTED' if selection['kind'] == 'mp' else 'TRUE_SP') + r'(?:\s|$)',
                    r'\[QUEUE_TEST\] PREFLIGHT_COMPLETE mods=' + str(len(selection['mods'])) + ' mode=' + selection['mode'] + r'(?:\s|$)',
                    r'\[STARTUP_TEST\] GAME_START kind=' + selection['kind'] + ' mode=' + selection['mode'] + r'(?:\s|$)',
                    r'\[STARTUP_TEST\] PLAYER_READY square=-?\d+,-?\d+,-?\d+ tick=true(?:\s|$)',
                    r'\[STARTUP_TEST\] COMPLETE case=loaded(?:\s|$)']
        for pattern in patterns:
            matches = list(re.finditer(pattern, text))
            if len(matches) != 1:
                issues.append('Missing or duplicate startup readiness: ' + pattern)
            else:
                positions.append(matches[0].start())
        if positions != sorted(set(positions)):
            issues.append('Startup readiness preceded preflight or native game start')
        if '[QUEUE_TEST] FAIL ' in text:
            issues.append('Startup bootstrap/preflight failed')
        if selection['kind'] == 'mp':
            server = (Path(root) / 'server-launch.log').read_text(errors='replace')
            readiness = list(re.finditer(r'\[STARTUP_TEST\] SERVER_READY(?:\s|$)', server))
            if len(readiness) != 1:
                issues.append('Missing or duplicate native server readiness')
            if '[ROOM_STATE_TEST] FAIL' in server:
                issues.append('Room state roundtrip failed')
            roundtrip = selection.get('options', {}).get('room_state_roundtrip')
            if roundtrip:
                completions = list(re.finditer(r'\[ROOM_STATE_TEST\] COMPLETE(?:\s|$)', server))
                matching = list(re.finditer(r'\[ROOM_STATE_TEST\] COMPLETE mode=' + re.escape(roundtrip) + r'(?:\s|$)', server))
                if len(completions) != 1 or len(matching) != 1:
                    issues.append('Missing, duplicate or mismatched room state completion: ' + roundtrip)
                else:
                    if len(readiness) == 1 and matching[0].start() >= readiness[0].start():
                        issues.append('Server readiness preceded room state completion')
                    markers = ['[PZToolkitJavaPatches] Room state persistence loaded: validated provenance']
                    if roundtrip == 'migrate':
                        markers.append('[PZToolkitJavaPatches] Room state persistence serialized: bound owner provenance')
                    for marker in markers:
                        if not 0 <= server.find(marker) < matching[0].start():
                            issues.append('Missing native room provenance before completion: ' + marker)
    except OSError as error:
        issues.append(str(error))
    roundtrip = selection.get('options', {}).get('room_state_roundtrip')
    limits = (['Restored MP world room flags and IDs checked without player walking; no broader gameplay coverage.']
              if roundtrip else ['Load-only player/square readiness; no gameplay behavior is exercised.'])
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': 'loaded',
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues),
            'outcome': {'loaded': not issues}}],
            'evidence': {'limits': limits}}
