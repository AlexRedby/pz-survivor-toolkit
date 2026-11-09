"""Real generator completion/cancellation and independent native reading tails."""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
from .. import placement, preparation_process
import zipfile

CASES = ['repair', 'cancel', 'missing-target', 'late-continuation']
PEER_CASES = ['peer-cancel']
MODS = ['PZSurvivorToolkit', 'ZombieBuddy', 'PZToolkitJavaPatches']


def definitions():
    return {'engine': {'status': 'ready', 'clients': 1, 'default_mods': MODS,
                       'cases': [{'id': case, 'producer': 'fixture', 'capability': 'effect',
                                  'kinds': ['sp', 'mp'], 'languages': ['EN'], 'modes': ['toolkit', 'native']}
                                 for case in CASES]},
            'engine-peers': {'status': 'ready', 'clients': 2, 'default_mods': MODS,
                             'cases': [{'id': 'peer-cancel', 'producer': 'fixture', 'capability': 'effect',
                                        'kinds': ['mp'], 'languages': ['EN', 'RU'], 'modes': ['toolkit']}]}}


def validate(selection):
    peers = selection.get('suite') == 'engine-peers'
    cases = selection.get('cases', [])
    if ((cases != PEER_CASES if peers else not cases or len(cases) != len(set(cases)) or any(case not in CASES for case in cases))
            or selection.get('kind') not in (('mp',) if peers else ('sp', 'mp'))
            or selection.get('mode') not in (('toolkit',) if peers else ('toolkit', 'native'))
            or selection.get('languages') != (['EN', 'RU'] if peers else ['EN'])
            or type(selection.get('clients', 1)) is not int or selection.get('clients', 1) != (2 if peers else 1)):
        raise ValueError('Engine requires selected EN SP/MP cases; engine-peers requires two EN/RU toolkit MP clients and peer-cancel')
    if not set(MODS) <= set(selection.get('mods', [])):
        raise ValueError('Engine requires toolkit, ZombieBuddy, and PZToolkitJavaPatches')
    if selection.get('options', {}).get('world_template'):
        raise ValueError('Engine requires a fresh native world')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return (sorted(path for path in (root / 'engine').rglob('*') if path.suffix in ('.lua', '.java'))
            + sorted((root / 'startup').rglob('*.lua'))
            + [root / 'support/QueueEnergyPlacement.lua', root / 'health/shared/QueueHealthEvents.lua', Path(placement.__file__)])


def _peer_probe(project, output, game, jdk, locations):
    classes = Path(output) / 'engine-probe/classes'
    classes.mkdir(parents=True)
    classpath = os.pathsep.join(map(str, [Path(game) / 'projectzomboid.jar', Path(game) / 'ZombieBuddy.jar',
                                        Path(locations['PZToolkitJavaPatches']) / '42/media/java/PZToolkitJavaPatches.jar']))
    preparation_process.run([str(Path(jdk) / 'bin/javac'), '--release', '25', '-cp', classpath, '-d', str(classes),
                    str(Path(project) / 'tests/native_queue/engine/java/Main.java'),
                    str(Path(project) / 'tests/native_queue/engine/java/EnginePeerProbeChecks.java')],
                   check=True, capture_output=True, text=True, timeout=60)
    # Exercise the real native stores before launching clients. A broken observer must
    # fail preparation, rather than leaving a game run without cancellation evidence.
    preparation_process.run([str(Path(jdk) / 'bin/java'), '-Djava.awt.headless=true',
                    '-Dzomboid.steam=0', '-Djava.library.path=.', '-cp', os.pathsep.join([str(classes), classpath]),
                    'zombie.core.EnginePeerProbeChecks'],
                   cwd=game, check=True, capture_output=True, text=True, timeout=60)
    compiled = sorted((classes / 'net/alexredby/queueengineprobe').glob('Main*.class'))
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
        (lua / 'shared').mkdir(parents=True, exist_ok=True)
        shutil.copy2(Path(project) / 'tests/native_queue/health/shared/QueueHealthEvents.lua', lua / 'shared/QueueHealthEvents.lua')
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
                                            sandbox={'Zombies': 6, 'MinutesPerPage': 2.0})


def complete(selection, role, text):
    return role.startswith('client') and len(re.findall(
        r'\[ENGINE_TEST\] COMPLETE cases=' + str(len(selection['cases'])) + r'(?:\s|$)', text)) == 1


def _placement_rows(text, marker):
    rows = []
    for match in re.finditer(re.escape('[ENGINE_TEST] ' + marker) + r'(?=\s|$)([^\r\n]*)', text):
        value = json.loads(match.group(1))
        if not isinstance(value, dict) or set(value) != {'case', 'actor', 'target', 'proof'}:
            raise ValueError('Malformed engine ' + marker)
        rows.append((match.start(), value))
    return rows


def _placements(selection, clients, authority, actors):
    """Tie each settled actor tile to the exact generator before native work."""
    cases = selection['cases']
    expected = {(actor, case) for actor in actors for case in cases}
    authority_rows = _placement_rows(authority, 'AUTHORITY_PLACEMENT')
    if (len(authority_rows) != len(expected)
            or {(row['actor'], row['case']) for _, row in authority_rows} != expected):
        raise ValueError('Missing, duplicate or foreign engine authority placement')
    target_rows = []
    for match in re.finditer(r'\[ENGINE_TEST\] TARGET(?=\s|$)([^\r\n]*)', authority):
        target = re.fullmatch(r' case=(\S+) x=(-?\d+) y=(-?\d+) z=(-?\d+) index=(\d+) actor=(\S+)', match.group(1))
        if not target:
            raise ValueError('Malformed engine generator target')
        case, x, y, z, index, actor = target.groups()
        target_rows.append((match.start(), actor, case, dict(x=int(x), y=int(y), z=int(z)), int(index)))
    if (len(target_rows) != len(expected)
            or {(row[1], row[2]) for row in target_rows} != expected):
        raise ValueError('Missing, duplicate or foreign exact engine generator target')
    evidence, footprints = {}, {}
    for actor in actors:
        client = clients[actor]
        local_rows = _placement_rows(client, 'CLIENT_PLACEMENT')
        remote_rows = [(position, row) for position, row in authority_rows if row['actor'] == actor]
        if ([(row['actor'], row['case']) for _, row in local_rows] != [(actor, case) for case in cases]
                or [row['case'] for _, row in remote_rows] != cases):
            raise ValueError(actor + ': engine placements missing, duplicated, foreign or out of order')
        actor_footprint = set()
        for (local_position, local), (remote_position, remote) in zip(local_rows, remote_rows):
            case, target = local['case'], local['target']
            placement.validate(local['proof'], target, 'local')
            placement.validate(remote['proof'], remote['target'], 'replica' if selection['kind'] == 'mp' else 'local')
            if remote['target'] != target or selection['kind'] == 'sp' and remote != local:
                raise ValueError(actor + ': engine local and authority placement differ: ' + case)
            if target != local_rows[0][1]['target']:
                raise ValueError(actor + ': engine standing layout changed between cases')
            generator = next(row for row in target_rows if row[1:3] == (actor, case))
            if generator[3] != dict(x=target['x'] + 1, y=target['y'], z=target['z']):
                raise ValueError(actor + ': engine standing tile differs from exact generator: ' + case)
            prepared = list(re.finditer(re.escape(f'[ENGINE_TEST] PREPARED case={case} ')
                            + r'[^\r\n]*' + re.escape(' actor=' + actor) + r'\r?$', authority, re.MULTILINE))
            enqueued = list(re.finditer(re.escape(f'[ENGINE_TEST] ENQUEUED case={case} '), client))
            if (len(prepared) != 1 or len(enqueued) != 1
                    or not remote_position < prepared[0].start() < generator[0]
                    or local_position > enqueued[0].start()
                    or selection['kind'] == 'sp' and not local_position < remote_position < enqueued[0].start()):
                raise ValueError(actor + ': engine placement did not precede preparation and native work: ' + case)
            actor_footprint.update(tuple(point[key] for key in ('x', 'y', 'z')) for point in (target, generator[3]))
            evidence[(actor, case)] = dict(client=local['proof'], authority=remote['proof'], generator=dict(generator[3], index=generator[4]))
        if any(actor_footprint & other for other in footprints.values()):
            raise ValueError('Peer native generator/standing footprints overlap')
        footprints[actor] = actor_footprint
    return evidence


def verify(root, selection, catalog):
    root = Path(root)
    issues, outcomes = [], []
    peers = selection.get('suite') == 'engine-peers'
    enabled = selection['mode'] == 'toolkit'
    actors = ['client1', 'client2'] if peers else ['client1']
    first_captures, tokens, placements = {}, [], {}
    try:
        server = (root / ('server-launch.log' if selection['kind'] == 'mp' else 'client1-launch.log')).read_text(errors='replace')
        if selection['kind'] == 'mp' and server.count('[STARTUP_TEST] SERVER_READY') != 1:
            issues.append('Missing or duplicate real server readiness')
        clients = {actor: (root / (actor + '-launch.log')).read_text(errors='replace') for actor in actors}
        try:
            placements = _placements(selection, clients, server, actors)
        except (ValueError, TypeError, KeyError) as error:
            issues.append('Invalid engine placement evidence: ' + str(error))
        for actor in actors:
            client = clients[actor]
            authority = '\n'.join(line for line in server.splitlines() if line.endswith(' actor=' + actor)) if peers else server
            complete_marker = '[ENGINE_TEST] COMPLETE cases=' + str(len(selection['cases']))
            for marker in ['[QUEUE_TEST] PREFLIGHT_COMPLETE mods=' + str(len(selection['mods'])) + ' mode=' + selection['mode'],
                           '[QUEUE_TEST] ' + ('NATIVE_CONNECTED' if selection['kind'] == 'mp' else 'TRUE_SP'), complete_marker]:
                if len(re.findall(re.escape(marker) + r'(?:\s|$)', client)) != 1:
                    issues.append(actor + ': missing or duplicate native engine readiness: ' + marker)
            positions = []
            if peers:
                scenarios = [('peer-cancel', 94, 2)] if actor == 'client1' else [('peer-cancel', 100, 0)]
            else:
                scenarios = [(case, 98 if not enabled and selection['kind'] == 'sp' else 100,
                              1 if not enabled and selection['kind'] == 'sp' else 0) if case == 'repair'
                             else (case, 94, 2) for case in selection['cases']]
            for case, condition, scraps in scenarios:
                receipts = (0 if case == 'missing-target' else 1 if scraps else 2) if enabled and selection['kind'] == 'mp' else 0
                read_pattern = 'true' if enabled or case == 'repair' and selection['kind'] == 'sp' else '(?:true|false)' if case == 'repair' else 'false'
                marker = (f'[ENGINE_TEST] PASS case={case} condition={condition} scraps={scraps}'
                          f' tailRead=')
                matches = list(re.finditer(re.escape(marker) + '(' + read_pattern + ')'
                               + re.escape(f' boundary={str(enabled).lower()} progress=true receipts={receipts}') + r'(?:\s|$)', client))
                read = matches[0].group(1) if len(matches) == 1 else 'unknown'
                if len(matches) != 1:
                    issues.append(actor + ': missing or duplicate exact engine outcome: ' + case)
                else:
                    positions.append(matches[0].start())
                phases = re.findall(r'\[ENGINE_TEST\] PHASES case=' + case
                                    + r' perform=(\d+) complete=(\d+) flush=(\d+)(?:\s|$)', client)
                allowed_perform = (1, 2) if enabled and selection['kind'] == 'mp' and scraps == 0 else (2,) if enabled and scraps == 0 else (0,)
                if len(phases) != 1:
                    issues.append(actor + ': missing or duplicate native completion phases: ' + case)
                else:
                    perform, completed, flushed = map(int, phases[0])
                    if (perform not in allowed_perform or completed != (perform if selection['kind'] == 'sp' else 0)
                            or flushed != perform):
                        issues.append(actor + ': native completion phases differ: ' + case)
                for pattern, source in [
                    (f'[ENGINE_TEST] PREPARED case={case} condition=94 scraps=2 electricity=0 nativeGenerator=true', authority),
                    (f'[ENGINE_TEST] AUTHORITY case={case} condition={condition} scraps={scraps} tailRead={read}', authority),
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
                if len(re.findall(re.escape(cancel_marker) + r'(?:\s|$)', client)) != (1 if case in ('cancel', 'late-continuation') or peers and actor == 'client1' else 0):
                    issues.append(actor + ': unexpected or missing cancellation after native progress')
                if case == 'missing-target':
                    for proof, text in [(f'[ENGINE_TEST] TARGET_REMOVED case={case} beforeRepair=true', authority),
                                        (f'[ENGINE_TEST] MISSING_TARGET case={case} beforeStart=true blockerProgress=true', client)]:
                        if len(re.findall(re.escape(proof) + r'(?:\s|$)', text)) != 1:
                            issues.append(actor + ': missing/duplicate disappearance before repair')
                if case == 'late-continuation':
                    proof = f'[ENGINE_TEST] LATE_CALLBACK case={case} parentRetired=true repeats=2 unchanged=true'
                    if len(re.findall(re.escape(proof) + r'(?:\s|$)', client)) != 1:
                        issues.append(actor + ': missing/duplicate retired-parent callback proof')
                outcomes.append({'actor': actor, 'case': case, 'outcome': {'condition': condition, 'scraps': scraps, 'tailRead': read == 'true',
                                 'placement': placements.get((actor, case)),
                                 'nativeCompletion': dict(zip(('perform', 'complete', 'flush'), map(int, phases[0]))) if len(phases) == 1 else None}})
            if positions != sorted(positions) or positions and positions[-1] > client.find(complete_marker):
                issues.append(actor + ': engine cases completed out of order')
            if '[QUEUE_TEST] FAIL ' in client:
                issues.append(actor + ': native engine fixture failed')
        if peers:
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
