"""Native chunk streaming/rejoin and sealed Host world persistence evidence."""
from pathlib import Path
import re

from . import warehouse_manifest as common
from .. import report, receipts

MARKER = '[WAREHOUSE_PERSIST] '
CASES = ('persist-seed', 'persist-reload')
SEED_STAGES = ('initial', 'unloaded', 'revisited', 'rejoined', 'saved')
RELOAD_STAGES = ('restored', 'revisited')


def _records(text, event):
    return receipts.records(text, MARKER, event)


def _one(text, event):
    rows = _records(text, event)
    if len(rows) != 1:
        raise ValueError('Missing/duplicate persistence ' + event)
    return rows[0]


def validate(selection):
    options = selection.get('options', {})
    case = selection.get('cases')
    if (case not in ([CASES[0]], [CASES[1]]) or selection.get('kind') != 'mp'
            or selection.get('mode') != 'toolkit' or type(selection.get('clients')) is not int or selection['clients'] != 2
            or selection.get('languages') != ['EN', 'RU'] or not set(common.MODS) <= set(selection.get('mods', []))
            or type(options) is not dict or options.get('mp_host') is not True
            or any(options.get(key) for key in ('seed_run', 'startup_connection'))
            or bool(options.get('world_template')) != (case == [CASES[1]])):
        raise ValueError('Warehouse persistence requires separate two-client EN/RU menu Host seed/reload and a sealed template only for reload')
    if case == [CASES[1]]:
        _seed(selection)


def _seed(selection):
    template = Path(selection['options']['world_template'])
    if not template.is_absolute() or template.is_symlink():
        raise ValueError('Warehouse reload requires an absolute sealed Host world template')
    world = report.read_json(template / 'world.json')
    if (world.get('source_suite') != common.SUITE or world.get('source_cases') != ['persist-seed']
            or world.get('kind') != 'mp' or world.get('mp_host') is not True
            or world.get('roles') != ['server', 'client1', 'client2']):
        raise ValueError('Warehouse reload template must come from its native Host persistence seed')
    seed = Path(world['source_run'])
    if not seed.is_absolute() or seed.is_symlink():
        raise ValueError('Warehouse persistence seed must be an absolute owned run')
    initial = report.read_json(seed / 'selection.json')
    value = report.read_json(seed / 'report.json')
    execution = report.read_json(seed / 'execution.json')
    if (initial.get('suite') != common.SUITE or initial.get('cases') != ['persist-seed']
            or initial.get('kind') != 'mp' or initial.get('options', {}).get('mp_host') is not True
            or value.get('status') != 'passed' or value.get('runtime', {}).get('status') not in ('clean', 'background-only')
            or value.get('functional', {}).get('status') != 'passed' or not value.get('provenance', {}).get('verified')
            or execution.get('status') != 'completed'):
        raise ValueError('Warehouse reload requires a completed clean verified native seed')
    if report.verify_manifest(seed, 'source-manifest.json', True) or report.verify_manifest(seed, 'snapshot-hashes.json'):
        raise ValueError('Warehouse seed source/snapshot evidence changed')
    audit = report.audit_logs(seed, ('server', 'client1', 'client2'), native_game_sha256=report.verified_game_sha256(seed, True))
    if any(not row['available'] or row['microphone'] or row['fatal_count'] or row['unclassified_count'] for row in audit.values()):
        raise ValueError('Warehouse seed live native log audit is unsafe or stale')
    result = verify(seed, initial, {})
    if result['issues']:
        raise ValueError('Warehouse seed native assertions incomplete: ' + '; '.join(result['issues']))
    return seed, result['evidence']['persisted']


def sources(selection):
    if selection['cases'] != ['persist-reload']:
        return []
    seed, _ = _seed(selection)
    return [seed / name for name in ('selection.json', 'runtime.json', 'report.json', 'execution.json',
                                     'source-manifest.json', 'snapshot-hashes.json',
                                     'server-launch.log', 'client1-launch.log', 'client2-launch.log')]


def complete(selection, role, text):
    try:
        return common._exact(_records(text, 'COMPLETE'), [{'case': selection['cases'][0], 'role': role}])
    except ValueError:
        return False


def _receipt(value, stage, loaded, actor=None, language=None):
    expected = {'stage', 'revision', 'loaded', 'samples', 'ages', 'observedAt', 'counts', 'worldAbsent', 'nativeIds'}
    if actor:
        expected |= {'role', 'language', 'windowCount'}
    if (type(value) is not dict or set(value) != expected or value['stage'] != stage or value['loaded'] is not loaded
            or value['worldAbsent'] is not (not loaded) or value['nativeIds'] is not loaded
            or type(value['revision']) is not int or value['revision'] < 1
            or not common._exact(value['counts'], [2, 1, 1, 0]) or not common._positive(value['observedAt'])
            or type(value['samples']) is not list or len(value['samples']) != 2
            or type(value['ages']) is not list or len(value['ages']) != 2
            or any(not common._positive(stamp) for stamp in value['samples'])
            or any(type(age) not in (int, float) or isinstance(age, bool) or age < 0 or not loaded and age < 500 for age in value['ages'])
            or any(value['observedAt'] - stamp != age for stamp, age in zip(value['samples'], value['ages']))
            or actor and (value['role'] != actor or value['language'] != language or type(value['windowCount']) is not int or value['windowCount'] != 4)):
        raise ValueError('Invalid exact persistence ' + stage + ' receipt' + (' for ' + actor if actor else ''))


def _shot(root, role, stage):
    # Same bounded native PNG/header checks as the snapshot suite.
    path = root / role / 'Screenshots' / ('warehouse-persist-' + stage + '.png')
    data = path.read_bytes()
    import struct
    if len(data) < 33 or data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
        raise ValueError('Missing/invalid persistence screenshot ' + str(path))
    if any(size < minimum for size, minimum in zip(struct.unpack('>II', data[16:24]), (640, 480))):
        raise ValueError('Persistence screenshot too small')
    return str(path)


def verify(root, selection, catalog):
    root = Path(root)
    case = selection['cases'][0]
    stages = SEED_STAGES if case == 'persist-seed' else RELOAD_STAGES
    roles = ('client1', 'client2')
    issues, evidence = [], {}
    try:
        logs = {role: (root / (role + '-launch.log')).read_text(errors='replace') for role in ('server', *roles)}
        authority = logs['server']
        prepared = _one(authority, 'PREPARED')
        if set(prepared) != {'packet', 'home', 'away'}:
            raise ValueError('Persistence native descriptor absent')
        packet = prepared['packet']
        ids = packet['ids']
        if type(ids) is not list or len(ids) != 4 or len(set(ids)) != 4 or any(type(value) is not int for value in ids):
            raise ValueError('Persistence exact native item IDs absent')
        if (set(packet) != {'boxes', 'ids', 'category', 'identities'} or type(packet['category']) is not str or not packet['category']
                or type(packet['boxes']) is not list or len(packet['boxes']) != 2):
            raise ValueError('Persistence native container descriptors absent')
        common._item_identities(packet['identities'], packet['category'])
        for point in packet['boxes']:
            if (type(point) is not dict or set(point) != {'x', 'y', 'z', 'object', 'ci', 'key', 'id'}
                    or any(type(point[key]) is not int for key in ('x', 'y', 'z', 'object', 'ci'))
                    or point['object'] < 0 or point['ci'] != 0
                    or point['key'] != f"{point['x']},{point['y']},{point['z']}"
                    or point['id'] != f"{point['key']}/{point['object']}/0"):
                raise ValueError('Persistence native container descriptor invalid')
        if packet['boxes'][0]['key'] == packet['boxes'][1]['key']:
            raise ValueError('Persistence native locations must be distinct')
        for key in ('home', 'away'):
            point = prepared[key]
            if type(point) is not dict or set(point) != {'x', 'y', 'z'} or any(type(value) is not int for value in point.values()):
                raise ValueError('Persistence primitive travel point invalid')
        if abs(prepared['home']['x'] - prepared['away']['x']) < 300:
            raise ValueError('Persistence travel did not leave the native streaming range')
        authority_values = _records(authority, 'AUTHORITY')
        if len(authority_values) != len(stages):
            raise ValueError('Persistence authority stages incomplete')
        stage_values = {}
        for value, stage in zip(authority_values, stages):
            loaded = stage in ('initial', 'revisited', 'rejoined')
            _receipt(value, stage, loaded); stage_values[stage] = value
        if case == 'persist-seed':
            server_events = ['PREPARED', 'AUTHORITY', 'AUTHORITY', 'AUTHORITY', 'RECONNECT', 'DISCONNECTED', 'REJOIN', 'AUTHORITY', 'AUTHORITY', 'PERSISTED']
            old = _one(authority, 'RECONNECT')
            disconnect = _one(authority, 'DISCONNECTED')
            rejoin = _one(authority, 'REJOIN')
            if (set(old) != {'oldOnlineID'} or type(old['oldOnlineID']) is not int or old['oldOnlineID'] < 0
                    or not common._exact(disconnect, dict(old, oldPlayerAbsent=True))
                    or set(rejoin) != {'oldOnlineID', 'newOnlineID', 'newPlayer'} or rejoin['oldOnlineID'] != old['oldOnlineID']
                    or type(rejoin['newOnlineID']) is not int or rejoin['newOnlineID'] < 0 or rejoin['newPlayer'] is not True):
                raise ValueError('Persistence rejoin lacks native disconnect/new player proof')
            persisted = _one(authority, 'PERSISTED')
            saved_boxes = persisted.get('boxes')
            if type(saved_boxes) is not list or len(saved_boxes) != 2:
                raise ValueError('Persisted crate descriptors absent')
            for saved, original in zip(saved_boxes, packet['boxes']):
                if (type(saved) is not dict or set(saved) != set(original)
                        or any(saved[key] != original[key] for key in ('x', 'y', 'z', 'key', 'ci'))
                        or type(saved['object']) is not int or saved['object'] < 0
                        or saved['id'] != f"{saved['key']}/{saved['object']}/0"):
                    raise ValueError('Persisted stable crate location differs')
            expected = dict(schema=2, samples=stage_values['saved']['samples'], counts=[2, 1, 1, 0], ids=ids,
                            boxes=saved_boxes, identities=packet['identities'], category=packet['category'],
                            loaded=False, completedAt=persisted.get('completedAt'))
            if not common._exact(persisted, expected) or not common._positive(persisted['completedAt']):
                raise ValueError('Persisted world last-known receipt differs')
            evidence['persisted'] = persisted
            if any(new <= old for new, old in zip(stage_values['revisited']['samples'], stage_values['unloaded']['samples'])):
                raise ValueError('Revisit did not take a new native sample')
        else:
            server_events = ['COLD', 'PREPARED', 'AUTHORITY', 'AUTHORITY', 'CLEANUP']
            _, seed = _seed(selection)
            cold = _one(authority, 'COLD')
            cold_with_proof = dict(cold, worldAbsent=True, nativeIds=False)
            _receipt(cold_with_proof, 'cold', False)
            if ids != seed['ids'] or packet['boxes'] != seed['boxes']:
                raise ValueError('Reload replaced original persisted crate/item identities')
            if packet['category'] != seed['category'] or not common._exact(packet['identities'], seed['identities']):
                raise ValueError('Reload replaced original persisted native item states')
            if cold['samples'] != seed['samples'] or cold['counts'] != seed['counts']:
                raise ValueError('Cold authority did not restore exact persisted samples/counts')
            if stage_values['restored']['samples'] != seed['samples']:
                raise ValueError('Last-known samples changed before native revisit')
            if any(new <= old for new, old in zip(stage_values['revisited']['samples'], seed['samples'])):
                raise ValueError('Reload revisit did not advance sample timestamps')
            if not common._exact(_one(authority, 'CLEANUP'), {'ownedObjects': 2}):
                raise ValueError('Reload fixture cleanup missing')
            evidence['cold'] = cold
        if re.findall(re.escape(MARKER) + r'([A-Z_]+) ', authority) != server_events:
            raise ValueError('Persistence server lifecycle missing/duplicated/reordered')
        evidence['screenshots'], evidence['states'] = [], {}
        for role, language in zip(roles, ('EN', 'RU')):
            text = logs[role]
            setup = _one(text, 'SETUP')
            if (set(setup) != {'case', 'role', 'language', 'onlineID'} or setup['case'] != case
                    or setup['role'] != role or setup['language'] != language or type(setup['onlineID']) is not int or setup['onlineID'] < 0):
                raise ValueError('Persistence setup language/native identity differs')
            rows = _records(text, 'STATE')
            if len(rows) != len(stages):
                raise ValueError(role + ' persistence convergence stages incomplete')
            events = ['SETUP']
            for row, stage in zip(rows, stages):
                loaded = stage in ('initial', 'revisited', 'rejoined')
                _receipt(row, stage, loaded, role, language)
                if not loaded and row['samples'] != stage_values[stage]['samples']:
                    raise ValueError(role + ' last-known sample timestamp changed')
                if case == 'persist-seed' and role == 'client2' and stage == 'rejoined':
                    events += ['DISCONNECT', 'REJOIN']
                events += ['STATE', 'SHOT']
                evidence['screenshots'].append(_shot(root, role, stage))
            if case == 'persist-seed' and role == 'client2':
                dc, rj = _one(text, 'DISCONNECT'), _one(text, 'REJOIN')
                if not common._exact(dc, dict(role=role, onlineID=_one(authority, 'RECONNECT')['oldOnlineID'], nativeExitToMenu=True)):
                    raise ValueError('Observer did not exit through native menu')
                if not common._exact(rj, dict(role=role, onlineID=_one(authority, 'REJOIN')['newOnlineID'], nativeConnected=True)):
                    raise ValueError('Observer native reconnect not acknowledged')
            if not common._exact(_records(text, 'SHOT'), [dict(role=role, stage=stage) for stage in stages]):
                raise ValueError(role + ' persistence native screenshots absent/reordered')
            events += ['COMPLETE']
            if re.findall(re.escape(MARKER) + r'([A-Z_]+) ', text) != events or not complete(selection, role, text):
                raise ValueError(role + ' persistence lifecycle missing/duplicated/reordered')
            evidence['states'][role] = rows
        if len(re.findall(re.escape('[STARTUP_TEST] SERVER_READY') + r'(?:\s|$)', authority)) != 1:
            raise ValueError('Persistence menu Host readiness absent')
        if any(MARKER + 'FAIL ' in text or '[QUEUE_TEST] FAIL ' in text for text in logs.values()):
            raise ValueError('Persistence fixture failure marker present')
    except (OSError, ValueError, KeyError, TypeError) as error:
        issues.append(str(error))
    evidence['limits'] = ['Native chunk streaming, native observer menu rejoin, and a separate sealed server/client restart.',
                          'Programmatic window callbacks; screenshots require visual inspection.']
    return {'issues': issues, 'outcomes': [dict(actor=role, case=case, status='failed' if issues else 'passed', reason='; '.join(issues)) for role in roles],
            'evidence': evidence}
