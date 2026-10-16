"""Load-only native readiness; the shared runner owns launch, audit and cleanup."""
from pathlib import Path
import re


def definitions():
    return {'startup': {'status': 'ready', 'clients': 1, 'default_mods': ['PZSurvivorToolkit'],
                        'cases': [{'id': 'loaded', 'producer': 'fixture', 'capability': 'effect',
                                   'kinds': ['sp', 'mp'], 'languages': ['EN', 'RU'],
                                   'modes': ['toolkit', 'native']}]}}


def validate(selection):
    if (selection.get('cases') != ['loaded'] or selection.get('kind') not in ('sp', 'mp')
            or selection.get('mode') not in ('toolkit', 'native')
            or type(selection.get('clients', 1)) is not int or selection.get('clients', 1) != 1
            or selection.get('languages') not in (['EN'], ['RU'])):
        raise ValueError('Startup requires loaded, SP/MP, native/toolkit and one EN/RU client')
    if selection['kind'] == 'sp' and selection.get('options', {}).get('world_template'):
        raise ValueError('Startup SP creates a fresh world; restored SP worlds are unsupported')


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
            if len(re.findall(r'\[STARTUP_TEST\] SERVER_READY(?:\s|$)', server)) != 1:
                issues.append('Missing or duplicate native server readiness')
    except OSError as error:
        issues.append(str(error))
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': 'loaded',
            'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues),
            'outcome': {'loaded': not issues}}],
            'evidence': {'limits': ['Load-only player/square readiness; no gameplay behavior is exercised.']}}
