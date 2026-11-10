"""Bind centered health placement to owning clients, authority and native admission."""
import json
import re

from . import placement

PREFIX = '[HEALTH_PLACEMENT] '
MARKERS = {'LAYOUT', 'CLIENT_PLACEMENT', 'AUTHORITY_PLACEMENT', 'PREPARED', 'ADMITTED'}
RECEIPT = re.compile(r'HEALTH_AUTH_RECEIPT (\S*) phase=(\w+) ok=(true|false) patient=(\S*) error=([^\r\n]+)')


def _require(condition, detail):
    if not condition:
        raise ValueError('Health placement: ' + detail)


def _records(text):
    result = []
    for match in re.finditer(re.escape(PREFIX) + r'([^\r\n]*)', text):
        marker, separator, payload = match[1].partition(' ')
        _require(marker in MARKERS and separator, 'unknown or malformed record')
        value = json.loads(payload)
        _require(isinstance(value, dict), 'record must be an object')
        result.append((match.start(), marker, value))
    return result


def _events(text):
    result = []
    for match in re.finditer(re.escape('[QUEUE_CHECK] ') + r'([^\r\n]*)', text):
        value = json.loads(match[1])
        _require(isinstance(value, dict), 'invalid structured event')
        result.append((match.start(), value))
    return result


def _identity(row):
    _require(isinstance(row.get('phase'), str) and isinstance(row.get('doctor'), str), 'invalid round identity')
    return row['phase'], row['doctor']


def _same(left, right):
    # JSON equality must preserve numeric/boolean types in the transported proof.
    return json.dumps(left, sort_keys=True) == json.dumps(right, sort_keys=True)


def validate(selection, texts, specs):
    """Only compare positions within one process; network clocks are unrelated."""
    roles = ['client1'] if selection['kind'] == 'sp' else ['client1', 'client2']
    authority_role = 'client1' if selection['kind'] == 'sp' else 'server'
    records = {role: _records(texts.get(role, '')) for role in [*roles, authority_role]}
    events = {role: _events(texts.get(role, '')) for role in roles}
    rounds, publications = [('setup', 'setup')], {}
    for role in roles:
        cases = [(position, value) for position, value in events[role] if value.get('event') == 'case']
        _require([value.get('id') for _, value in cases] == selection['cases'],
                 role + ' case events missing, duplicate or reordered')
        for position, value in cases:
            _require(value.get('status') in ('passed', 'failed', 'skipped'), 'invalid case status')
            if value['status'] != 'skipped':
                identity = value['id'], role
                rounds.append(identity)
                publications[identity] = position
    authority = records[authority_role]
    layouts = [(position, row) for position, marker, row in authority if marker == 'LAYOUT']
    prepared = [(position, row) for position, marker, row in authority if marker == 'PREPARED']
    _require([_identity(row) for _, row in layouts] == rounds
             and [_identity(row) for _, row in prepared] == rounds,
             'layouts/prepared missing, duplicate, foreign or reordered')
    _require(all(set(row) == {'phase', 'doctor', 'targets'} for _, row in layouts + prepared),
             'layout/prepared fields differ')
    origin = layouts[0][1]['targets']
    _require(isinstance(origin, dict) and 'client1' in origin, 'setup origin missing')
    origin = origin['client1']
    _require(isinstance(origin, dict) and set(origin) == {'x', 'y', 'z'}
             and all(type(value) is int and abs(value) < 1000000 for value in origin.values()), 'invalid origin')
    east = dict(origin, x=origin['x'] + 1)
    expected_targets = {}
    for phase, doctor in rounds:
        if phase == 'setup':
            targets = {'client1': origin}
            if selection['kind'] == 'mp':
                targets['client2'] = east
        else:
            _require(phase in specs, 'unknown case')
            targets = {doctor: origin}
            if selection['kind'] == 'mp' and specs[phase]['producer'] != 'inventory':
                targets['client2' if doctor == 'client1' else 'client1'] = east
        expected_targets[phase, doctor] = targets
    for (_, layout), (_, ready) in zip(layouts, prepared):
        targets = expected_targets[_identity(layout)]
        _require(_same(layout['targets'], targets) and _same(ready['targets'], targets),
                 'layout/prepared targets differ from fixed origin and east peer')
    local, remote, admissions = {}, {}, {}
    for role, stream in records.items():
        if selection['kind'] == 'mp':
            forbidden = {'CLIENT_PLACEMENT', 'ADMITTED'} if role == 'server' else {'LAYOUT', 'PREPARED', 'AUTHORITY_PLACEMENT'}
            _require(not any(marker in forbidden for _, marker, _ in stream), 'record published by wrong process')
        for position, marker, row in stream:
            identity = _identity(row)
            _require(identity in expected_targets, 'foreign or skipped round')
            if marker in ('CLIENT_PLACEMENT', 'AUTHORITY_PLACEMENT'):
                fields = {'phase', 'doctor', 'actor', 'target', 'proof'}
                if marker == 'AUTHORITY_PLACEMENT':
                    fields.add('clientProof')
                _require(set(row) == fields and isinstance(row['actor'], str) and row['actor'] in expected_targets[identity], 'placement fields/actor differ')
                actor, target = row['actor'], expected_targets[identity][row['actor']]
                _require(_same(row['target'], target), 'placement target differs')
                mode = 'replica' if marker == 'AUTHORITY_PLACEMENT' and selection['kind'] == 'mp' else 'local'
                placement.validate(row['proof'], target, mode, centered=True)
                bucket = local if marker == 'CLIENT_PLACEMENT' else remote
                key = (*identity, actor)
                _require(key not in bucket, 'duplicate placement')
                if marker == 'CLIENT_PLACEMENT':
                    _require(actor == role, 'client proof published by wrong owner')
                bucket[key] = position, row
            elif marker == 'ADMITTED':
                _require(set(row) == {'phase', 'doctor', 'actor', 'targets'}
                         and row['actor'] == role == row['doctor'] and identity != ('setup', 'setup')
                         and _same(row['targets'], expected_targets[identity]), 'admission fields/actor/targets differ')
                _require(identity not in admissions, 'duplicate admission')
                admissions[identity] = position
    expected = {(*identity, actor) for identity, targets in expected_targets.items() for actor in targets}
    _require(set(local) == expected and set(remote) == expected, 'missing or foreign placement proof')
    _require(set(admissions) == set(publications), 'missing or foreign native admission')
    receipts = []
    for match in RECEIPT.finditer(texts.get(authority_role, '')):
        doctor = match[1]
        if selection['kind'] == 'sp':
            _require(doctor == match[4], 'SP authority actor/patient differ')
            doctor = 'client1'
        receipts.append((match.start(), (match[2], doctor)))
    _require([identity for _, identity in receipts] == rounds[1:], 'authority receipts missing, duplicate, skipped or reordered')
    receipt_positions = {identity: position for position, identity in receipts}
    previous = -1
    for (lp, layout), (pp, _ready) in zip(layouts, prepared):
        identity = _identity(layout)
        _require(previous < lp < pp, 'authority round reordered')
        for actor in expected_targets[identity]:
            key = (*identity, actor)
            cp, owned = local[key]; rp, observed = remote[key]
            _require(lp < rp < pp, 'authority proof must precede prepared')
            _require(_same(observed['clientProof'], owned['proof']), 'authority client proof differs from owner')
            if selection['kind'] == 'sp':
                _require(lp < cp < rp and _same(observed['proof'], owned['proof']), 'SP proof/order differs')
        if identity != ('setup', 'setup'):
            previous = receipt_positions[identity]
            _require(pp < previous, 'authority receipt preceded prepared')
            doctor = identity[1]
            cp = local[(*identity, doctor)][0]
            ap, publication = admissions[identity], publications[identity]
            _require(cp < ap < publication, 'native admission must follow own proof and precede case')
            if selection['kind'] == 'sp':
                _require(pp < ap < previous < publication, 'SP native admission/setup/receipt reordered')
        else:
            previous = pp
    for role in roles:
        expected_rounds = [identity for identity, targets in expected_targets.items() if role in targets]
        actual_rounds = [_identity(row) for _, marker, row in records[role] if marker == 'CLIENT_PLACEMENT']
        _require(actual_rounds == expected_rounds, 'owning client placement rounds reordered')
        for before, after in zip(expected_rounds, expected_rounds[1:]):
            if before[1] == role:
                _require(publications[before] < local[(*after, role)][0],
                         'next local placement preceded previous native case completion')
