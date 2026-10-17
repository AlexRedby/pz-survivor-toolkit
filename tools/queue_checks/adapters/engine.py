"""Real generator completion/cancellation and independent native reading tails."""
from pathlib import Path
import re
import shutil

CASES = ['repair', 'cancel']
MODS = ['PZSurvivorToolkit', 'ZombieBuddy', 'PZToolkitJavaPatches']


def definitions():
    return {'engine': {'status': 'ready', 'clients': 1, 'default_mods': MODS,
                       'cases': [{'id': case, 'producer': 'fixture', 'capability': 'effect',
                                  'kinds': ['sp', 'mp'], 'languages': ['EN'], 'modes': ['toolkit']}
                                 for case in CASES]}}


def validate(selection):
    if (selection.get('cases') != CASES or selection.get('kind') not in ('sp', 'mp')
            or selection.get('mode') != 'toolkit' or selection.get('languages') != ['EN']
            or type(selection.get('clients', 1)) is not int or selection.get('clients', 1) != 1):
        raise ValueError('Engine requires repair/cancel, EN/SP or MP/toolkit, and one actual client')
    if not set(MODS) <= set(selection.get('mods', [])):
        raise ValueError('Engine requires toolkit, ZombieBuddy, and PZToolkitJavaPatches')
    if selection.get('options', {}).get('world_template'):
        raise ValueError('Engine requires a fresh native world')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return sorted((root / 'engine').rglob('*.lua')) + sorted((root / 'startup').rglob('*.lua'))


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    startup = Path(project) / 'tests/native_queue/startup'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            target = lua / side / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(startup / side / name, target)
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
                                            sandbox={'Zombies': 6, 'MinutesPerPage': 2.0})


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(r'\[ENGINE_TEST\] COMPLETE cases=2(?:\s|$)', text)) == 1


def verify(root, selection, catalog):
    root = Path(root)
    issues, outcomes = [], []
    try:
        client = (root / 'client1-launch.log').read_text(errors='replace')
        authority = (root / ('server-launch.log' if selection['kind'] == 'mp' else 'client1-launch.log')).read_text(errors='replace')
        for marker in ['[QUEUE_TEST] PREFLIGHT_COMPLETE mods=' + str(len(selection['mods'])) + ' mode=toolkit',
                       '[QUEUE_TEST] ' + ('NATIVE_CONNECTED' if selection['kind'] == 'mp' else 'TRUE_SP'),
                       '[ENGINE_TEST] COMPLETE cases=2']:
            if len(re.findall(re.escape(marker) + r'(?:\s|$)', client)) != 1:
                issues.append('Missing or duplicate native engine readiness: ' + marker)
        if selection['kind'] == 'mp' and authority.count('[STARTUP_TEST] SERVER_READY') != 1:
            issues.append('Missing or duplicate real server readiness')
        positions = []
        for case, condition, scraps in [('repair', 100, 0), ('cancel', 94, 2)]:
            receipts = (2 if case == 'repair' else 1) if selection['kind'] == 'mp' else 0
            marker = (f'[ENGINE_TEST] PASS case={case} condition={condition} scraps={scraps}'
                      f' tailRead=true boundary=true progress=true receipts={receipts}')
            matches = list(re.finditer(re.escape(marker) + r'(?:\s|$)', client))
            if len(matches) != 1:
                issues.append('Missing or duplicate exact engine outcome: ' + case)
            else:
                positions.append(matches[0].start())
            for pattern, source in [
                (f'[ENGINE_TEST] PREPARED case={case} condition=94 scraps=2 electricity=0 nativeGenerator=true', authority),
                (f'[ENGINE_TEST] AUTHORITY case={case} condition={condition} scraps={scraps} tailRead=true', authority),
                (f'[ENGINE_TEST] ENQUEUED case={case} repairDuration=150 tailPages=1 nativeDurations=true', client),
            ]:
                if len(re.findall(re.escape(pattern) + r'(?:\s|$)', source)) != 1:
                    issues.append('Missing or duplicate fixture evidence: ' + pattern)
            captures = re.findall(r'\[ENGINE_TEST\] CAPTURE case=' + case + r' kind=ISFixGenerator token=([0-9a-f-]{36})(?:\s|$)', client)
            if len(captures) != receipts or len(set(captures)) != receipts:
                issues.append('Missing or duplicated native acknowledgement captures: ' + case)
            outcomes.append({'actor': 'client1', 'case': case, 'outcome': {'condition': condition, 'scraps': scraps, 'tailRead': True}})
        if len(re.findall(r'\[ENGINE_TEST\] CANCEL_REQUEST case=cancel progress=true(?:\s|$)', client)) != 1:
            issues.append('Missing unique cancellation after native progress')
        if positions != sorted(positions) or positions and positions[-1] > client.find('[ENGINE_TEST] COMPLETE cases=2'):
            issues.append('Engine cases completed out of order')
        if '[QUEUE_TEST] FAIL ' in client + authority:
            issues.append('Native engine fixture failed')
    except OSError as error:
        issues.append(str(error))
    if not outcomes:
        outcomes = [{'actor': 'client1', 'case': case} for case in CASES]
    for outcome in outcomes:
        outcome.update(status='failed' if issues else 'passed', reason='; '.join(issues))
    return {'issues': issues, 'outcomes': outcomes,
            'evidence': {'limits': ['Fresh EN world, native durations, one actual player; no physical mouse input or long session coverage.']}}
