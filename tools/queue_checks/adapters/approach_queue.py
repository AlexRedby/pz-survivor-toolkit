"""Stock cursor/direct routes, authoritative vegetation effects and independent tail."""
import json
from pathlib import Path
import re
import shutil

from .. import placement, report
from .tv_controls import MODS, _duration, _number

CASES = ('bush', 'manual-grass', 'direct-bush')
PREFIX = '[QUEUE_APPROACH] '
NATIVE_SPRITES = {'bush': ('f_bushes_1_0', 'canBeCut'),
                  'manual-grass': ('e_newgrass_1_0', 'canBeRemoved'),
                  'direct-bush': ('f_bushes_1_0', 'canBeCut')}
DIRECT_PRODUCER = 'native luautils.walkAdj -> ISWorldObjectContextMenu.doRemovePlant'


def definitions():
    checks = {name: {case: {'effectsVerified': True, 'tailCompleted': True,
                            'serverAuthorityVerified': True} for case in CASES}
              for name in ('success-queued', 'server-authority')}
    return {'approach-queue': {'status': 'ready', 'clients': 1, 'default_mods': list(MODS),
        'scenario_actions': {'native-cursor-approach': {'mods': list(MODS), 'checks': checks,
            'scope': 'Three ordered full-current-selected-pack fresh macOS SP/menu-Host cases: stock ISRemovePlantCursor.tryBuild for bush and manual grass, then direct native walkAdj and doRemovePlant for bush. Second initially adjacent target is submitted while a first distant native walk is active. Toolkit preserves first work and resolves both required walks from their future positions; queue-off native clear cancels the first and removes only the second. Exact marked stock object identities, authoritative removal order and stock loot conservation, naturally completed independent root reader in every mode; native Host additionally requires distinct exact started/completed removal and reader receipts, final pages and immediate native idle. Direct Toolkit execution requires its original walking, arrival and accepted-no-movement phase receipts. Unchanged native durations/lifecycle. Programmatic cursor and direct native entrypoints; no physical input or wall-vine/container coverage.'}},
        'cases': [dict(id=case, producer='fixture', capability='effect', kinds=['sp', 'mp'],
                       modes=['native', 'toolkit'], languages=['EN']) for case in CASES]}}


def validate(selection):
    if (selection.get('cases') != list(CASES) or selection.get('kind') not in ('sp', 'mp')
            or selection.get('mode') not in ('native', 'toolkit') or selection.get('languages') != ['EN']
            or type(selection.get('clients')) is not int or selection['clients'] != 1
            or selection.get('mods') != MODS or selection.get('options', {}).get('world_template')
            or selection['kind'] == 'mp' and selection.get('options', {}).get('mp_host') is not True):
        raise ValueError('Approach requires all three ordered cases, current full selected EN pack, fresh SP/menu Host and one client')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [Path(__file__).with_name('tv_controls.py'), Path(placement.__file__),
            *sorted((root / 'approach-queue').rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueEnergyPlacement.lua']


def native_sprite_proof(game):
    """Fail preparation if either exact stock tile lacks its declared native flag."""
    source = Path(game) / 'media/tiledefinitions_erosion.tiles.txt'
    text = source.read_text()
    proof = []
    for case, (name, flag) in NATIVE_SPRITES.items():
        matches = list(re.finditer(r'^\s*// ' + re.escape(name) + r'\s+tile\s*\{([^}]+)\}', text, re.MULTILINE))
        if len(matches) != 1 or not re.search(r'^\s*' + re.escape(flag) + r'\s*=\s*$', matches[0][1], re.MULTILINE):
            raise ValueError('Missing exact native vegetation definition: ' + name + '/' + flag)
        match = matches[0]
        proof.append(dict(case=case, sprite=name, flag=flag, source=str(source.resolve()),
                          line=text.count('\n', 0, match.start()) + 1))
    return proof


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    proof = native_sprite_proof(game)
    if output is not None:
        (Path(output) / 'native-sprite-proof.json').write_text(json.dumps(proof, indent=2) + '\n')
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            shutil.copy2(root / 'startup' / side / name, lua / side / name)
        shutil.copy2(root / 'health/shared/QueueHealthEvents.lua', lua / 'shared')
        # This suite alone authorizes pre-baseline scene clearing in its owned profiles.
        config_path = lua / 'shared/QueueTestSelection.lua'
        config = config_path.read_text()
        marker = 'return QueueTestSelection'
        if not config.startswith('QueueTestSelection=') or config.count(marker) != 1:
            raise ValueError('Missing generated approach fixture selection')
        config_path.write_text(config.replace(marker, 'QueueTestSelection.disposable=true\n' + marker))
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL approach-queue'], sandbox={'Zombies': 6, 'MinutesPerPage': 2.0})


def _raw(text, marker):
    values = [json.loads(m.group(1)) for m in re.finditer(re.escape(PREFIX + marker + ' ') + r'([^\n]+)', text)]
    if any(not isinstance(v, dict) for v in values):
        raise ValueError('Malformed approach raw ' + marker)
    return values


def _records(text, marker):
    records = []
    for match in re.finditer(re.escape(PREFIX + marker) + r'(?=\s|$)([^\r\n]*)', text):
        value = json.loads(match[1])
        if not isinstance(value, dict):
            raise ValueError('Malformed approach raw ' + marker)
        records.append((match.start(), value))
    return records


def _placements(selection, client, authority, rows):
    """Bind each settled center to its own setup and admission in publication order."""
    layouts, local, remote, admitted, prepared, baselines, verified = (
        _records(text, marker) for text, marker in (
            (authority, 'LAYOUT'), (client, 'CLIENT_PLACEMENT'), (authority, 'AUTHORITY_PLACEMENT'),
            (client, 'ADMITTED'), (authority, 'PREPARED'),
            (authority, 'BASELINE'), (authority, 'VERIFIED')))
    publications = []
    for match in re.finditer(re.escape('[QUEUE_CHECK] ') + r'([^\r\n]*)', client):
        value = json.loads(match[1])
        if isinstance(value, dict) and value.get('suite') == 'approach-queue' and value.get('event') == 'case':
            publications.append((match.start(), value))
    if (any([value.get('case') for _, value in stream] != list(CASES)
            for stream in (layouts, local, remote, admitted, prepared, baselines, verified))
            or [value.get('id') for _, value in publications] != list(CASES)
            or [row.get('id') for row in rows] != list(CASES)):
        raise ValueError('Approach placement/setup/admission missing, duplicate, foreign or reordered')
    if selection['kind'] == 'mp' and (_records(client, 'LAYOUT') or _records(client, 'AUTHORITY_PLACEMENT')
            or _records(authority, 'CLIENT_PLACEMENT') or _records(authority, 'ADMITTED')):
        raise ValueError('Approach placement published by wrong process')
    witnesses = [record for marker in ('NATIVE_STATE', 'SPATIAL_OUTCOME', 'CLIENT_IDLE', 'SERVER_SNAPSHOT')
                 for record in _records(client, marker)]
    for i, case in enumerate(CASES):
        dp, layout = layouts[i]; lp, local_row = local[i]; rp, remote_row = remote[i]
        ap, admission = admitted[i]; pp, ids = prepared[i]
        bp, _ = baselines[i]; vp, _ = verified[i]; cp, _ = publications[i]
        for receipt in (local_row, remote_row):
            if set(receipt) != {'case', 'actor', 'target', 'proof'} or receipt['actor'] != 'client1':
                raise ValueError('Malformed approach placement identity')
        target = local_row['target']
        if (layout != dict(case=case, actor='client1', target=target)
                or not all(type(v) is int for v in layout['target'].values())):
            raise ValueError('Approach layout differs from final placement')
        placement.validate(local_row['proof'], target, 'local', centered=True)
        placement.validate(remote_row['proof'], remote_row['target'],
                           'replica' if selection['kind'] == 'mp' else 'local', centered=True)
        if remote_row['target'] != target or selection['kind'] == 'sp' and remote_row != local_row:
            raise ValueError('Approach placement target or SP proof differs')
        if any(spec.get('origin') != target or spec.get('placement') != target
               for spec in (ids, rows[i].get('ids', {}))):
            raise ValueError('Approach placement differs from prepared identities')
        if admission != dict(case=case, actor='client1'):
            raise ValueError('Malformed approach native admission identity')
        if (not lp < ap < cp or not dp < rp < pp < bp < vp
                or selection['kind'] == 'sp' and not dp < lp < rp < bp < ap < vp < cp
                or any(position <= ap for position, value in witnesses if value.get('case') == case)
                or i and (publications[i - 1][0] >= lp or verified[i - 1][0] >= dp)):
            raise ValueError('Approach placement did not precede setup and native admission')


def complete(selection, role, text):
    try:
        values = _raw(text, 'COMPLETE')
        return role == 'client1' and len(values) == 1 and values[0].get('cases') == selection['cases']
    except (ValueError, TypeError):
        return False


def _near(position, target):
    return (isinstance(position, dict) and set(position) == {'x', 'y', 'z'}
            and all(_number(v) for v in position.values()) and position['z'] == target['z']
            and abs(position['x'] - target['x'] - .5) <= 1.6 and abs(position['y'] - target['y'] - .5) <= 1.6)


def _items(values):
    return (isinstance(values, list) and all(isinstance(v, dict) and set(v) == {'id', 'type'}
            and type(v['id']) is int and isinstance(v['type'], str) and v['type'] for v in values)
            and [v['id'] for v in values] == sorted({v['id'] for v in values}))


def _spatial_outcomes(row, spec, enabled):
    values = row.get('spatialOutcomes')
    if not isinstance(values, list):
        return ['Missing transparent native spatial outcomes']
    if not enabled:
        return ['Native control acquired qualified spatial outcomes'] if values else []
    commands = {v.get('name'): v for v in row.get('commands', [])}
    tokens = {commands.get(name, {}).get('token'): name for name in ('first', 'second')}
    errors = []
    previous = None
    for value in values:
        if not isinstance(value, dict):
            errors.append('Malformed spatial outcome'); continue
        name = tokens.get(value.get('token'))
        outcome = value.get('result')
        target = spec['targets'].get(name)
        if (set(value) != {'case', 'result', 'type', 'token', 'observedAt', 'position', 'target'}
                or value.get('case') != spec['case'] or target is None or type(value.get('token')) is not int
                or outcome not in ('walking', 'native-arrival', 'native-no-movement')
                or value.get('type') != ('ISWalkToTimedAction' if outcome == 'native-arrival' else 'ISQueueActionsAction')
                or not _number(value.get('observedAt')) or previous is not None and value['observedAt'] < previous
                or not _near(value.get('target'), target)
                or outcome != 'walking' and not _near(value.get('position'), target)
                or outcome != 'native-arrival' and value.get('target') != {k: target[k] for k in ('x', 'y', 'z')}):
            errors.append('Unproven or unsuccessful native spatial outcome')
        previous = value.get('observedAt') if _number(value.get('observedAt')) else previous
    if spec['case'] == 'direct-bush':
        expected = [(name, result) for name in ('first', 'second')
                    for result in ('walking', 'native-arrival', 'native-no-movement')]
        if [(tokens.get(v.get('token')), v.get('result')) for v in values if isinstance(v, dict)] != expected:
            errors.append('Direct native spatial execution lacks its exact two movement/arrival/no-movement episodes')
        elif (not _near(values[0].get('position'), spec['origin'])
              or not _near(values[3].get('position'), spec['targets']['first'])
              or values[3].get('observedAt', 0) < row.get('secondIssue', {}).get('issuedAt', float('inf'))):
            errors.append('Direct spatial execution did not resolve from the actual future position')
    return errors


def _snapshot(value, spec, final):
    if (not isinstance(value, dict) or value.get('case') != spec['case'] or not _items(value.get('root'))
            or set(value.get('targets', {})) != {'first', 'second'}
            or set(value.get('ground', {})) != {'first', 'second'}):
        return False
    enabled = spec['mode'] == 'toolkit'
    for name in ('first', 'second'):
        target = value['targets'][name]
        removed = final and (enabled or name == 'second')
        if target != dict(identity=spec['targets'][name], objects=[] if removed else [
                {k: spec['targets'][name][k] for k in ('marker', 'index', 'sprite')}]):
            return False
        if not _items(value['ground'][name]):
            return False
    book = spec['book']
    expected = dict(id=book['id'], type=book['type'], pages=book['pages'] if final else book['initial'],
                    characterPages=book['pages'] if final else book['initial'], root=True)
    if value.get('book') != expected or value.get('order') != (['first', 'second'] if enabled else ['second']) * bool(final):
        return False
    effects = value.get('effects')
    expected_effects = (['first', 'second'] if enabled else ['second']) if final else []
    if (not isinstance(effects, list) or [e.get('name') for e in effects] != expected_effects
            or any(set(e) != {'name', 'root', 'ground'} or not _items(e['root'])
                   or set(e['ground']) != {'first', 'second'} or any(not _items(v) for v in e['ground'].values()) for e in effects)):
        return False
    return all(dict(id=spec[k]['id'], type=spec[k]['type']) in value['root'] for k in ('book', 'tool'))


def _conservation(before, after, spec, paid_names=None):
    paid_names = paid_names if paid_names is not None else (['first', 'second'] if spec['mode'] == 'toolkit' else ['second'])
    old = {r['id']: r['type'] for r in before['root']}
    new = {r['id']: r['type'] for r in after['root']}
    if any(new.get(k) != v for k, v in old.items()):
        return False
    extra = [v for k, v in new.items() if k not in old]
    removed = len(paid_names)
    if spec['case'] == 'manual-grass':
        if not 2 * removed <= len(extra) <= 3 * removed or any(v != 'Base.GrassTuft' for v in extra):
            return False
    elif extra:
        return False
    ground_ids = set()
    for name in ('first', 'second'):
        old = {r['id']: r['type'] for r in before['ground'][name]}
        new = {r['id']: r['type'] for r in after['ground'][name]}
        if ground_ids.intersection(new) or any(new.get(k) != v for k, v in old.items()):
            return False
        ground_ids.update(new)
        extra = [v for k, v in new.items() if k not in old]
        paid = name in paid_names
        if spec['case'] in ('bush', 'direct-bush') and paid:
            if extra.count('Base.Twigs') != 1 or extra.count('Base.TreeBranch2') not in (0, 1) or len(extra) != 1 + extra.count('Base.TreeBranch2'):
                return False
        elif extra:
            return False
    return not ground_ids.intersection(r['id'] for r in after['root'])


def _native_host_control(row, spec, native_states, idle, authority_idle):
    """Exact paid removal and naturally completed independent reader on native Host."""
    errors = []
    commands = {r.get('name'): r for r in row.get('commands', [])}
    second, tail = commands.get('second', {}), commands.get('tail', {})
    expected_states = []
    pairs = {}
    for name, command, kind in (('second', second, 'ISRemoveBush' if spec['case'] in ('bush', 'direct-bush') else 'ISRemoveGrass'),
                                ('tail', tail, 'ISReadABook')):
        states = command.get('nativeStates', [])
        if (not isinstance(states, list) or len(states) != 2
                or [r.get('state') for r in states] != ['started', 'completed']):
            errors.append('Host native control lacks exact started/completed receipts: ' + name)
            continue
        expected_states.extend(states)
        first, completed = states; pairs[name] = (first, completed)
        for receipt in states:
            if (receipt.get('case') != spec['case'] or receipt.get('name') != name or receipt.get('type') != kind
                    or receipt.get('kind') != kind or receipt.get('matched') is not True or receipt.get('referenceStable') is not True
                    or type(receipt.get('player')) is not int or type(receipt.get('transaction')) is not int
                    or not -128 <= receipt['transaction'] <= 127 or receipt['transaction'] == 0
                    or not re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', str(receipt.get('token')))
                    or not isinstance(receipt.get('actionRef'), str) or not receipt['actionRef']
                    or not isinstance(receipt.get('nativeRef'), str) or not receipt['nativeRef']
                    or receipt.get('currentActionRef') != receipt.get('actionRef') or not _number(receipt.get('observedAt'))):
                errors.append('Host native receipt identity/current action differs: ' + name)
        if any(first.get(k) != completed.get(k) for k in ('player', 'transaction', 'kind', 'token', 'actionRef', 'nativeRef')):
            errors.append('Host native receipt binding changed across completion: ' + name)
        if (not _number(command.get('admittedAt')) or not _number(command.get('endedAt'))
                or not _number(first.get('observedAt')) or not _number(completed.get('observedAt'))
                or not command['admittedAt'] <= first['observedAt'] <= completed['observedAt'] <= command['endedAt']):
            errors.append('Host native receipt/admission/completion order differs: ' + name)
    if list(native_states) != expected_states:
        errors.append('Host native raw receipt stream differs from exact removal then reader completion')
    if set(pairs) == {'second', 'tail'}:
        removal, reader = pairs['second'], pairs['tail']
        if (removal[0].get('player') != reader[0].get('player')
                or any(removal[0].get(k) == reader[0].get(k) for k in ('transaction', 'token', 'actionRef', 'nativeRef'))):
            errors.append('Host native removal and reader do not have distinct exact identities')
        if (not _number(second.get('admittedAt')) or not _number(tail.get('admittedAt'))
                or not _number(removal[1].get('observedAt')) or not _number(reader[0].get('observedAt'))
                or not second['admittedAt'] <= tail['admittedAt'] <= removal[1]['observedAt'] <= reader[0]['observedAt']):
            errors.append('Host native reader did not follow the paid removal')
    if (commands.get('first', {}).get('nativeStates')
            or type(tail.get('token')) is not int or tail.get('token') in [commands.get(n, {}).get('token') for n in ('first', 'second')]
            or row.get('manualInputSeen') is not False):
        errors.append('Host native control shared reader, acknowledged first removal or manual interruption')
    if (not isinstance(idle, dict) or row.get('clientIdle') != idle or idle.get('case') != spec['case']
            or idle.get('phase') != 'running' or not _snapshot(idle.get('client'), spec, True)
            or row.get('serverIdle') != authority_idle or not _snapshot(authority_idle, spec, True)):
        errors.append('Host native idle requires independent exact paid-effect/completed-reader snapshots')
    else:
        q = idle.get('queue', {})
        if (q.get('current') is not False or q.get('currentType') is not False or q.get('pending') != []
                or q.get('hasTimedActions') is not False or q.get('nativeCount') != 0
                or q.get('pressedMovement') is not False or q.get('pressedCancel') is not False
                or q.get('manualInputSeen') is not False or not _near(q.get('position'), spec['targets']['second'])):
            errors.append('Host native idle has pending Java/Lua work or external movement/cancel input')
        for key in ('targets', 'book', 'root', 'ground', 'order'):
            if idle['client'][key] != row.get('client', {}).get(key) or authority_idle[key] != row.get('server', {}).get(key):
                errors.append('Host native effects/pages changed after first idle')
        completed = pairs.get('tail', ({}, {}))[1]
        if (not _number(idle.get('observedAt')) or not _number(tail.get('endedAt'))
                or not tail['endedAt'] <= idle['observedAt'] <= tail['endedAt'] + 1000
                or not _number(completed.get('observedAt')) or not 0 <= idle['observedAt'] - completed['observedAt'] <= 1000):
            errors.append('Host native idle was not the immediate completed-reader boundary')
    return errors


def check_case(row, case, selection, prepared, authority_baseline, verified, native_states=(), idle=None, authority_idle=None):
    spec = row.get('ids')
    try:
        if (not isinstance(spec, dict) or spec != prepared or spec['case'] != case or spec['mode'] != selection['mode']
                or set(spec['origin']) != {'x', 'y', 'z'} or any(type(v) is not int for v in spec['origin'].values())
                or spec.get('placement') != spec['origin']
                or any(type(v) is not int for v in spec['placement'].values())
                or set(spec['targets']) != {'first', 'second'}):
            raise ValueError()
        for name, dx in (('first', 7), ('second', -1)):
            target = spec['targets'][name]
            if (set(target) != {'x', 'y', 'z', 'index', 'sprite', 'marker'}
                    or any(type(target[k]) is not int for k in ('x', 'y', 'z', 'index')) or target['index'] < 1
                    or not isinstance(target['sprite'], str) or not target['sprite'] or target['marker'] != case + '-' + name
                    or any(target[k] != spec['origin'][k] + (dx if k == 'x' else 0) for k in ('x', 'y', 'z'))):
                raise ValueError()
        if (spec['tool']['type'] != 'Base.HuntingKnife' or spec['book']['type'] != 'Base.BookCarpentry1'
                or any(type(spec['book'][k]) is not int for k in ('id', 'pages', 'initial'))
                or type(spec['tool']['id']) is not int or spec['book']['id'] == spec['tool']['id']
                or spec['book']['pages'] <= 1 or spec['book']['initial'] != spec['book']['pages'] - 1):
            raise ValueError()
    except (KeyError, TypeError, ValueError):
        return ['Missing exact authoritative approach identities']
    errors = []; enabled = selection['mode'] == 'toolkit'
    errors.extend(_spatial_outcomes(row, spec, enabled))
    native_host = selection['kind'] == 'mp' and not enabled
    if (row.get('status') != 'passed' or row.get('queueIdle') is not True or row.get('lifecycleUnchanged') is not True
            or not _number(row.get('settleMilliseconds')) or row['settleMilliseconds'] < 1000):
        errors.append('Missing native idle or unchanged lifecycle gate')
    for key, final in (('input', False), ('authorityBaseline', False), ('client', True), ('server', True)):
        if not _snapshot(row.get(key), spec, final):
            errors.append('Wrong exact approach snapshot: ' + key)
    if row.get('authorityBaseline') != authority_baseline or row.get('server') != verified:
        errors.append('Independent raw authority readbacks differ')
    if not errors:
        if row['input'] != row['authorityBaseline']:
            errors.append('Client/authority baseline differs')
        for side in ('client', 'server'):
            if not _conservation(row['authorityBaseline'], row[side], spec):
                errors.append('Exact native loot/item conservation differs: ' + side)
        for side in ('server',):
            previous = row['authorityBaseline']
            for effect in row[side]['effects']:
                if not _conservation(previous, effect, spec, [effect['name']]):
                    errors.append('Per-target stock loot conservation differs: ' + side + '/' + effect['name'])
                previous = effect
            if any(previous[key] != row[side][key] for key in ('root', 'ground')):
                errors.append('Items changed after final exact removal receipt')
        if any(row['client'][key] != row['server'][key] for key in ('case', 'targets', 'root', 'ground', 'book', 'order')):
            errors.append('Exact client/authority final effects differ')
    issue = row.get('secondIssue', {})
    if (issue.get('firstWalking') is not True or not _near(issue.get('position'), spec['targets']['second'])
            or _near(issue.get('position'), spec['targets']['first'])
            or not _number(issue.get('firstStartedAt')) or not _number(issue.get('issuedAt'))
            or issue['firstStartedAt'] > issue['issuedAt'] or issue.get('firstRetainedAfterIssue') is not enabled
            or issue.get('firstJavaRetainedAfterIssue') is not enabled):
        errors.append('Second entrypoint did not preserve/cancel the active first native walk as required')
    expected = ['first', 'second', 'tail'] if enabled else ['second', 'tail']
    if row.get('order') != expected:
        errors.append('Native removals/tail started in the wrong order')
    commands = row.get('commands', [])
    if [r.get('name') for r in commands] != ['first', 'second', 'tail']:
        errors.append('Missing, duplicate or foreign native operation')
    tokens = []
    for command in commands:
        name = command.get('name'); tail = name == 'tail'; did_start = name in expected
        if (command.get('type') != ('ISReadABook' if tail else 'ISRemoveBush' if case in ('bush', 'direct-bush') else 'ISRemoveGrass')
                or command.get('producer') != ('native ISReadABook constructor' if tail else DIRECT_PRODUCER if case == 'direct-bush' else 'native ISRemovePlantCursor.tryBuild')
                or command.get('started') is not did_start or command.get('progress') is not did_start
                or not _number(command.get('duration')) or command['duration'] <= 1
                or not tail and command['duration'] != (100 if case in ('bush', 'direct-bush') else 50)
                or command.get('itemId') != (spec['book']['id'] if tail else False)
                or command.get('target') != (False if tail else spec['targets'].get(name))
                or command.get('cancelled') is not (not enabled and name == 'first')):
            errors.append('Native producer/duration/start/cancellation differs: ' + str(name))
        if did_start and (not _duration(command) or not _number(command.get('endedAt')) or command['endedAt'] <= command.get('startedAt', float('inf'))):
            errors.append('Native duration/completion observation differs: ' + str(name))
        if did_start and not tail and not _near(command.get('startPosition'), spec['targets'].get(name, {})):
            errors.append('Native removal started beyond target reach')
        if enabled:
            if type(command.get('token')) is not int:
                errors.append('Missing operation token identity')
            tokens.append(command.get('token'))
    if enabled and len(set(tokens)) != 3:
        errors.append('Distinct native operations/independent reader share tokens')
    walks = row.get('walks', [])
    if any(w.get('type') != 'ISWalkToTimedAction' or w.get('duration') != -1
           or not isinstance(w.get('destination'), dict) or not _number(w.get('admittedAt')) for w in walks):
        errors.append('Native walk identity/duration differs')
    active = [w for w in walks if w.get('started') is True]
    if enabled:
        completed = [w for w in active if w.get('progress') is True and w.get('cancelled') is False
                     and _number(w.get('endedAt')) and w.get('endedAt') > w.get('startedAt', float('inf'))]
        if len(completed) != 2 or len(active) != 2:
            errors.append('Expected two actual native approach walks')
        else:
            first, second = completed
            if (not _near(first.get('destination'), spec['targets']['first']) or not _near(second.get('destination'), spec['targets']['second'])
                    or not _near(first.get('startPosition'), spec['origin']) or not _near(first.get('endPosition'), spec['targets']['first'])
                    or not _near(second.get('startPosition'), spec['targets']['first']) or not _near(second.get('endPosition'), spec['targets']['second'])
                    or first['endedAt'] > second.get('startedAt', 0) or second.get('admittedAt', 0) < issue.get('issuedAt', float('inf'))
                    or len(tokens) != 3 or [first.get('token'), second.get('token')] != tokens[:2]):
                errors.append('Native routes were not resolved at each operation head from the future position')
    elif len(active) != 1 or active[0].get('cancelled') is not True:
        errors.append('Native control did not cancel exactly its first active walk')
    if case == 'direct-bush':
        if enabled and len(walks) != 2:
            errors.append('Deferred direct inner phases added redundant native walks')
        if not enabled:
            unstarted = [w for w in walks if w.get('started') is False]
            if (len(walks) != 2 or len(unstarted) != 1
                    or unstarted[0].get('cancelled') is not True or unstarted[0].get('progress') is not False
                    or any(k in unstarted[0] for k in ('startedAt', 'endedAt', 'startPosition', 'endPosition'))
                    or not _near(unstarted[0].get('destination'), spec['targets']['first'])
                    or unstarted[0].get('admittedAt', float('inf')) > issue.get('issuedAt', 0)):
                errors.append('Native direct control lacks its exact cancelled unstarted redundant inner walk')
    if native_host:
        errors.extend(_native_host_control(row, spec, native_states, idle, authority_idle))
    return errors


def verify(root, selection, catalog):
    root = Path(root); issues, outcomes = [], []
    try:
        text = (root / 'client1-launch.log').read_text(errors='replace')
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
        events = [r for r in report.events(text) if r.get('suite') == 'approach-queue']
        setups = [r for r in events if r.get('event') == 'setup']; rows = [r for r in events if r.get('event') == 'case']
        completed = [r for r in events if r.get('event') == 'complete']
        if (len(setups) != 1 or setups[0].get('cases') != list(CASES) or setups[0].get('nativeDurations') is not True
                or setups[0].get('queueEnabled') is not (selection['mode'] == 'toolkit')
                or len(completed) != 1 or completed[0].get('cases') != list(CASES) or completed[0].get('performed') != len(CASES)
                or completed[0].get('failed') != 0 or completed[0].get('skipped') != 0):
            issues.append('Missing exact approach setup/completion gate')
        prepared, baseline, verified = (_raw(authority, marker) for marker in ('PREPARED', 'BASELINE', 'VERIFIED'))
        native_states, idle, authority_idle = _raw(text, 'NATIVE_STATE'), _raw(text, 'CLIENT_IDLE'), _raw(authority, 'SNAPSHOT')
        server_idle = _raw(text, 'SERVER_SNAPSHOT')
        spatial = _raw(text, 'SPATIAL_OUTCOME')
        if any(value.get('case') not in CASES for value in spatial):
            issues.append('Unknown-case native spatial outcome')
        native_host = selection['kind'] == 'mp' and selection['mode'] == 'native'
        if native_host and any(r.get('case') not in CASES for r in native_states):
            issues.append('Unknown-case native Host receipt')
        if native_host and (any([r.get('case') for r in values] != list(CASES) for values in (idle, authority_idle, server_idle)) or server_idle != authority_idle):
            issues.append('Host native raw idle/authority snapshots missing, duplicated, changed or out of order')
        if ([r.get('id') for r in rows] != list(CASES)
                or any([r.get('case') for r in values] != list(CASES) for values in (prepared, baseline, verified))):
            issues.append('Case/authority evidence missing, duplicated or out of order')
        _placements(selection, text, authority, rows)
        for i, case in enumerate(CASES):
            row = rows[i] if i < len(rows) else {}
            if row.get('spatialOutcomes') != [value for value in spatial if value.get('case') == case]:
                issues.append(case + ': transparent raw spatial outcomes differ from case evidence')
            errors = check_case(row, case, selection, prepared[i] if i < len(prepared) else None,
                                baseline[i] if i < len(baseline) else None, verified[i] if i < len(verified) else None,
                                [r for r in native_states if r.get('case') == case],
                                idle[i] if i < len(idle) else None, authority_idle[i] if i < len(authority_idle) else None)
            if row.get('actor') != 'client1' or row.get('kind') != selection['kind'] or row.get('mode') != selection['mode']:
                errors.append('Approach actor/kind/mode differs')
            issues += [case + ': ' + error for error in errors]
            outcomes.append(dict(actor='client1', case=case, status='failed' if errors else 'passed', reason='; '.join(errors),
                                 outcome=dict(effectsVerified=not errors, serverAuthorityVerified=not errors, tailCompleted=not errors)))
        if not complete(selection, 'client1', text): issues.append('Missing unique approach completion marker')
    except (OSError, ValueError, KeyError, TypeError, AttributeError, IndexError) as error:
        issues.append('Approach verifier ' + type(error).__name__ + ': ' + str(error))
    return dict(issues=issues, outcomes=outcomes, evidence={'limits': [
        'Programmatic stock cursor/direct native entrypoints; no physical keyboard/mouse or rendering claim.',
        'Fresh one-client current selected-pack macOS SP/menu Host; bush/manual grass/direct-bush corridor only.']})
