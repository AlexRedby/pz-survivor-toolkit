"""Real generator completion/cancellation and independent native reading tails."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import zipfile

CASES = ['repair', 'cancel']
PEER_CASES = ['peer-cancel']
MODS = ['PZSurvivorToolkit', 'ZombieBuddy', 'PZToolkitJavaPatches']


def definitions():
    return {'engine': {'status': 'ready', 'clients': 1, 'default_mods': MODS,
                       'cases': [{'id': case, 'producer': 'fixture', 'capability': 'effect',
                                  'kinds': ['sp', 'mp'], 'languages': ['EN'], 'modes': ['toolkit']}
                                 for case in CASES]},
            'engine-peers': {'status': 'ready', 'clients': 2, 'default_mods': MODS,
                             'cases': [{'id': 'peer-cancel', 'producer': 'fixture', 'capability': 'effect',
                                        'kinds': ['mp'], 'languages': ['EN', 'RU'], 'modes': ['toolkit']}]}}


def validate(selection):
    peers = selection.get('suite') == 'engine-peers'
    if (selection.get('cases') != (PEER_CASES if peers else CASES)
            or selection.get('kind') not in (('mp',) if peers else ('sp', 'mp'))
            or selection.get('mode') != 'toolkit' or selection.get('languages') != (['EN', 'RU'] if peers else ['EN'])
            or type(selection.get('clients', 1)) is not int or selection.get('clients', 1) != (2 if peers else 1)):
        raise ValueError('Engine requires EN/SP or MP repair/cancel; engine-peers requires two EN/RU MP clients and peer-cancel')
    if not set(MODS) <= set(selection.get('mods', [])):
        raise ValueError('Engine requires toolkit, ZombieBuddy, and PZToolkitJavaPatches')
    if selection.get('options', {}).get('world_template'):
        raise ValueError('Engine requires a fresh native world')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return sorted(path for path in (root / 'engine').rglob('*') if path.suffix in ('.lua', '.java')) + sorted((root / 'startup').rglob('*.lua'))


def _peer_probe(project, output, game, jdk, locations):
    classes = Path(output) / 'engine-probe/classes'
    classes.mkdir(parents=True)
    classpath = os.pathsep.join(map(str, [Path(game) / 'projectzomboid.jar', Path(game) / 'ZombieBuddy.jar',
                                        Path(locations['PZToolkitJavaPatches']) / '42/media/java/PZToolkitJavaPatches.jar']))
    subprocess.run([str(Path(jdk) / 'bin/javac'), '--release', '17', '-cp', classpath, '-d', str(classes),
                    str(Path(project) / 'tests/native_queue/engine/java/Main.java')],
                   check=True, capture_output=True, text=True, timeout=60)
    compiled = sorted(classes.rglob('*.class'))
    if not compiled:
        raise ValueError('Engine peer probe compilation produced no classes')
    jar = classes.parent / 'EnginePeerProbe.jar'
    with zipfile.ZipFile(jar, 'x', zipfile.ZIP_DEFLATED) as archive:
        for path in compiled:
            archive.write(path, path.relative_to(classes).as_posix())
    return jar


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    startup = Path(project) / 'tests/native_queue/startup'
    probe = _peer_probe(project, output, game, jdk, locations) if selection['suite'] == 'engine-peers' else None
    if probe:
        runtime.setdefault('fixture', {})['mods'] = ['EnginePeerProbe']
    for role in runtime['roles'].values():
        cache = Path(role['cache'])
        lua = cache / 'mods/ActionQueueTest/42/media/lua'
        if selection['suite'] == 'engine-peers':
            for side in ('shared', 'client', 'server'):
                shutil.copytree(Path(project) / 'tests/native_queue/engine' / side, lua / side, dirs_exist_ok=True)
            layer = cache / 'mods/EnginePeerProbe/42'
            (layer / 'media/java').mkdir(parents=True)
            (layer / 'mod.info').write_text('name=Read-only queue peer probe\nid=EnginePeerProbe\nversionMin=42.21\n'
                                          'require=\\ZombieBuddy\njavaPkgName=net.alexredby.queueengineprobe\n'
                                          'javaJarFile=media/java/EnginePeerProbe.jar\n')
            shutil.copy2(probe, layer / 'media/java/EnginePeerProbe.jar')
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            target = lua / side / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(startup / side / name, target)
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
                                            sandbox={'Zombies': 6, 'MinutesPerPage': 2.0})


def complete(selection, role, text):
    return role.startswith('client') and len(re.findall(
        r'\[ENGINE_TEST\] COMPLETE cases=' + str(len(selection['cases'])) + r'(?:\s|$)', text)) == 1


def verify(root, selection, catalog):
    root = Path(root)
    issues, outcomes = [], []
    peers = selection.get('suite') == 'engine-peers'
    actors = ['client1', 'client2'] if peers else ['client1']
    first_captures, tokens, targets = {}, [], set()
    try:
        server = (root / ('server-launch.log' if selection['kind'] == 'mp' else 'client1-launch.log')).read_text(errors='replace')
        if selection['kind'] == 'mp' and server.count('[STARTUP_TEST] SERVER_READY') != 1:
            issues.append('Missing or duplicate real server readiness')
        for actor in actors:
            client = (root / (actor + '-launch.log')).read_text(errors='replace')
            authority = '\n'.join(line for line in server.splitlines() if line.endswith(' actor=' + actor)) if peers else server
            if peers:
                target = re.findall(r'\[ENGINE_TEST\] TARGET case=peer-cancel x=(-?\d+) y=(-?\d+) z=(-?\d+) index=(\d+) actor=' + actor + r'(?:\s|$)', authority)
                if len(target) != 1:
                    issues.append(actor + ': missing or duplicate exact target')
                else:
                    targets.add(target[0][:3])
            complete_marker = '[ENGINE_TEST] COMPLETE cases=' + str(len(selection['cases']))
            for marker in ['[QUEUE_TEST] PREFLIGHT_COMPLETE mods=' + str(len(selection['mods'])) + ' mode=toolkit',
                           '[QUEUE_TEST] ' + ('NATIVE_CONNECTED' if selection['kind'] == 'mp' else 'TRUE_SP'), complete_marker]:
                if len(re.findall(re.escape(marker) + r'(?:\s|$)', client)) != 1:
                    issues.append(actor + ': missing or duplicate native engine readiness: ' + marker)
            positions = []
            if peers:
                scenarios = [('peer-cancel', 94, 2)] if actor == 'client1' else [('peer-cancel', 100, 0)]
            else:
                scenarios = [('repair', 100, 0), ('cancel', 94, 2)]
            for case, condition, scraps in scenarios:
                receipts = (1 if scraps else 2) if selection['kind'] == 'mp' else 0
                marker = (f'[ENGINE_TEST] PASS case={case} condition={condition} scraps={scraps}'
                          f' tailRead=true boundary=true progress=true receipts={receipts}')
                matches = list(re.finditer(re.escape(marker) + r'(?:\s|$)', client))
                if len(matches) != 1:
                    issues.append(actor + ': missing or duplicate exact engine outcome: ' + case)
                else:
                    positions.append(matches[0].start())
                for pattern, source in [
                    (f'[ENGINE_TEST] PREPARED case={case} condition=94 scraps=2 electricity=0 nativeGenerator=true', authority),
                    (f'[ENGINE_TEST] AUTHORITY case={case} condition={condition} scraps={scraps} tailRead=true', authority),
                    (f'[ENGINE_TEST] ENQUEUED case={case} repairDuration=150 tailPages=1 nativeDurations=true', client),
                ]:
                    if len(re.findall(re.escape(pattern) + r'(?:\s|$)', source)) != 1:
                        issues.append(actor + ': missing or duplicate fixture evidence: ' + pattern)
                captures = re.findall(r'\[ENGINE_TEST\] CAPTURE case=' + case + r' kind=ISFixGenerator token=([0-9a-f-]{36})(?:\s|$)', client)
                if len(captures) != receipts or len(set(captures)) != receipts:
                    issues.append(actor + ': missing or duplicated native acknowledgement captures: ' + case)
                if peers:
                    correlated = re.findall(r'\[ENGINE_TEST\] CAPTURE case=peer-cancel kind=ISFixGenerator token=([0-9a-f-]{36}) transaction=(-?\d+) player=(\d+)(?:\s|$)', client)
                    if len(correlated) != receipts:
                        issues.append(actor + ': missing receipt identity')
                    if correlated:
                        first_captures[actor] = correlated[0]
                    tokens.extend(captures)
                cancel_marker = f'[ENGINE_TEST] CANCEL_REQUEST case={case} progress=true'
                if len(re.findall(re.escape(cancel_marker) + r'(?:\s|$)', client)) != (1 if scraps else 0):
                    issues.append(actor + ': unexpected or missing cancellation after native progress')
                outcomes.append({'actor': actor, 'case': case, 'outcome': {'condition': condition, 'scraps': scraps, 'tailRead': True}})
            if positions != sorted(positions) or positions and positions[-1] > client.find(complete_marker):
                issues.append(actor + ': engine cases completed out of order')
            if '[QUEUE_TEST] FAIL ' in client:
                issues.append(actor + ': native engine fixture failed')
        if peers:
            if len(targets) != 2:
                issues.append('Peer native repair targets overlap or are unverified')
            collision = re.findall(r'\[ENGINE_TEST\] COLLISION case=peer-cancel transaction=(-?\d+) firstPlayer=(\d+) secondPlayer=(\d+) firstToken=([0-9a-f-]{36}) secondToken=([0-9a-f-]{36})(?:\s|$)', server)
            if len(collision) != 1 or len(first_captures) != 2 or len(tokens) != 3 or len(set(tokens)) != 3:
                issues.append('Missing or duplicated peer collision identity')
            else:
                transaction, first, second, first_token, second_token = collision[0]
                if (not -128 <= int(transaction) <= 127 or int(transaction) == 0 or first == second
                        or first_captures['client1'] != (first_token, transaction, first)
                        or first_captures['client2'] != (second_token, transaction, second)):
                    issues.append('Peer collision differs from native owner/transaction/token captures')
                overlap = re.findall(r'\[ENGINE_TEST\] CANCEL_OVERLAP transaction=(-?\d+) firstPlayer=(\d+) secondPlayer=(\d+) firstToken=([0-9a-f-]{36}) secondToken=([0-9a-f-]{36}) otherPending=true(?:\s|$)', server)
                if overlap != collision:
                    issues.append('Cancellation lacked simultaneous pending native peers or removed the foreign action')
            if len(re.findall(r'\[ENGINE_TEST\] PROBE active=true(?:\s|$)', server)) != 1:
                issues.append('Read-only native overlap probe was not active')
        if '[QUEUE_TEST] FAIL ' in server:
            issues.append('Native engine fixture failed')
    except OSError as error:
        issues.append(str(error))
    if len(outcomes) != len(actors) * len(selection['cases']):
        outcomes = [{'actor': actor, 'case': case} for actor in actors for case in selection['cases']]
    for outcome in outcomes:
        outcome.update(status='failed' if issues else 'passed', reason='; '.join(issues))
    return {'issues': issues, 'outcomes': outcomes,
            'evidence': {'limits': ['Fresh world, native durations; no WAN, physical mouse input, reset/death/disconnect or long session coverage.']}}
