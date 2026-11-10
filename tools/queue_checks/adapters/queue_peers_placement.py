"""Independent centered setup/admission and terminal cleanup for peer cases."""
import math
import re

from .. import placement, receipts


PREFIX = '[QUEUE_PEERS] '
ROLES = ('client1', 'client2')
SERVER_EVENTS = ('LAYOUT', 'AUTHORITY_PLACEMENT', 'SEED', 'RELEASE', 'CAPACITY',
                 'APPLIED', 'PARTIAL', 'RESULT', 'AUTHORITY_CLEARED')
CLIENT_EVENTS = ('CLIENT_PLACEMENT', 'CLIENT_READY', 'ADMITTED', 'NATIVE_WALK', 'CASE', 'CLIENT_CLEARED')


def _stream(text, events):
    pattern = re.compile(re.escape(PREFIX) + '(' + '|'.join(events) + r')(?=\s|$)([^\r\n]*)')
    return [(match[1], receipts.decode_object(match[2])) for match in pattern.finditer(text)]


def _require(condition, detail):
    if not condition:
        raise ValueError('Queue peers placement: ' + detail)


def _target(value):
    return (isinstance(value, dict) and set(value) == {'x', 'y', 'z'}
            and all(type(number) is int and abs(number) < 1000000 for number in value.values()))


def _identity(row, case, index, token):
    return (row.get('case') == case and type(row.get('index')) is int and row['index'] == index
            and row.get('token') == token)


def _walk_actual(actual, target):
    return (isinstance(actual, dict) and set(actual) == {'x', 'y', 'z', 'square', 'currentSquare'}
            and all(type(actual[key]) in (int, float) and math.isfinite(actual[key]) for key in ('x', 'y', 'z'))
            and math.floor(actual['x']) == target['x'] and math.floor(actual['y']) == target['y']
            and abs(actual['z'] - target['z']) <= .01
            and all(_target(actual[key]) and actual[key] == target for key in ('square', 'currentSquare')))


def validate(selection, texts):
    """Use order within each process; independent native clocks never get compared."""
    server = _stream(texts['server'], (*SERVER_EVENTS, *CLIENT_EVENTS, 'COMPLETE'))
    clients = {role: _stream(texts[role], (*SERVER_EVENTS, *CLIENT_EVENTS, 'COMPLETE')) for role in ROLES}
    _require(not any(event in CLIENT_EVENTS for event, _ in server), 'client evidence on authority')
    for role, stream in clients.items():
        _require(not any(event in SERVER_EVENTS for event, _ in stream), role + ': authority evidence on client')

    # Local streams bind every placement and admission to exactly one completed
    # case. No local placement may begin before that actor observed old IDs gone.
    local = {}
    for role, stream in clients.items():
        banks = [[event for event in CLIENT_EVENTS if event != 'NATIVE_WALK'
                  or case == 'partial-accepted' and role == 'client1'] for case in selection['cases']]
        expected = [event for bank in banks for event in bank] + ['COMPLETE']
        _require([event for event, _ in stream] == expected,
                 role + ': placement/readiness/admission/case/clear order differs')
        local[role] = []; start = 0
        for bank in banks:
            local[role].append(dict(stream[start:start + len(bank)])); start += len(bank)

    offset = 0; origin = None; tokens = set(); actors = None
    for index, case in enumerate(selection['cases'], 1):
        def take(event):
            nonlocal offset
            _require(offset < len(server) and server[offset][0] == event,
                     case + ': authority expected ' + event)
            row = server[offset][1]; offset += 1
            return row

        layout = take('LAYOUT'); token = layout.get('token')
        _require(set(layout) == {'case', 'index', 'token', 'origin', 'targets'}
                 and isinstance(token, str) and bool(token) and token not in tokens
                 and _identity(layout, case, index, token), case + ': invalid/reused layout epoch')
        tokens.add(token)
        current_origin = layout['origin']; targets = layout['targets']
        _require(_target(current_origin) and (origin is None or current_origin == origin),
                 case + ': missing or changed bank origin')
        origin = current_origin
        _require(isinstance(targets, dict) and set(targets) == set(ROLES)
                 and all(_target(targets[role]) for role in ROLES)
                 and targets['client1'] == origin
                 and targets['client2'] == dict(origin, x=origin['x'] + 1),
                 case + ': role placement differs from origin/east tile')

        observed = set()
        for _ in ROLES:
            row = take('AUTHORITY_PLACEMENT'); role = row.get('role')
            _require(set(row) == {'case', 'index', 'token', 'role', 'target', 'proof', 'clientProof'}
                     and _identity(row, case, index, token) and role in ROLES and role not in observed,
                     case + ': invalid/duplicate authority placement actor/epoch')
            observed.add(role)
            local_row = local[role][index - 1]['CLIENT_PLACEMENT']
            _require(set(local_row) == {'case', 'index', 'token', 'role', 'target', 'proof'}
                     and _identity(local_row, case, index, token) and local_row['role'] == role
                     and _target(local_row['target']) and _target(row['target'])
                     and local_row['target'] == row['target'] == targets[role]
                     and row['clientProof'] == local_row['proof'],
                     case + ': local/authority placement pairing differs for ' + role)
            placement.validate(local_row['proof'], targets[role], 'local', centered=True)
            placement.validate(row['clientProof'], targets[role], 'local', centered=True)
            placement.validate(row['proof'], targets[role], 'replica', centered=True)

        seed = take('SEED')
        standing = seed.get('placement')
        _require(_identity(seed, case, index, token) and _target(seed.get('origin')) and seed['origin'] == origin
                 and isinstance(standing, dict) and set(standing) == set(ROLES)
                 and all(_target(standing[role]) for role in ROLES) and standing == targets,
                 case + ': seed placement/layout differs')
        current_actors = seed.get('actors')
        _require(isinstance(current_actors, list) and len(current_actors) == len(ROLES)
                 and all(isinstance(actor, dict) for actor in current_actors)
                 and [actor.get('role') for actor in current_actors] == list(ROLES)
                 and all(type(actor.get('onlineId')) is int and actor['onlineId'] >= 0 for actor in current_actors)
                 and len({actor['onlineId'] for actor in current_actors}) == len(ROLES),
                 case + ': missing exact authoritative actors')
        current_actors = {actor['role']: actor['onlineId'] for actor in current_actors}
        _require(actors is None or actors == current_actors, case + ': native bank actors changed')
        actors = current_actors
        release = take('RELEASE')
        _require(_identity(release, case, index, token), case + ': release epoch differs')
        for intervention in {'shared-capacity': ['CAPACITY'], 'lost-done': ['APPLIED'],
                             'partial-accepted': ['PARTIAL']}.get(case, []):
            _require(_identity(take(intervention), case, index, token), case + ': intervention epoch differs')
        _require(_identity(take('RESULT'), case, index, token), case + ': result epoch differs')

        cleared = set()
        for _ in ROLES:
            row = take('AUTHORITY_CLEARED'); role = row.get('role')
            _require(set(row) == {'case', 'index', 'token', 'role'}
                     and _identity(row, case, index, token) and role in ROLES and role not in cleared,
                     case + ': invalid/duplicate authority cleared actor/epoch')
            cleared.add(role)
        for role in ROLES:
            for event, row in local[role][index - 1].items():
                _require(_identity(row, case, index, token) and row.get('role') == role,
                         case + ': ' + role + ' ' + event + ' actor/epoch differs')
                if event in ('CLIENT_READY', 'ADMITTED'):
                    _require(set(row) == {'case', 'index', 'token', 'role', 'target'}
                             and _target(row['target']) and row['target'] == targets[role],
                             case + ': ' + event + ' target differs')
                elif event == 'CLIENT_CLEARED':
                    _require(set(row) == {'case', 'index', 'token', 'role'}, case + ': client clear fields differ')
                elif event == 'NATIVE_WALK':
                    target = dict(origin, x=origin['x'] - 1)
                    _require(set(row) == {'case', 'index', 'token', 'role', 'target', 'actual', 'sourceBound'}
                             and row['sourceBound'] is True and _target(row['target']) and row['target'] == target
                             and _walk_actual(row['actual'], target), case + ': native walk completion differs')
                elif event == 'CASE':
                    _require(row.get('onlineId') == actors[role] and type(row.get('onlineId')) is int,
                             case + ': admitted actor differs from native case')
    _require([event for event, _ in server[offset:]] == ['COMPLETE'],
             'authority completed before final clear or published foreign lifecycle evidence')
    return True
