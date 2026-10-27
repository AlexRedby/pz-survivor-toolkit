"""Capture original recipes and verify the fixed native battery paths in SP/Host."""
from pathlib import Path
import shutil
import struct

from .. import receipts

SUITE = 'plastic-battery'
MARKER = '[PLASTIC_BATTERY] '


def definitions():
    return {SUITE: {'status': 'ready', 'clients': 1,
                   'default_mods': ['damnlib', 'PZSurvivorToolkit'],
                   'cases': [{'id': 'charge-matrix', 'producer': 'fixture', 'capability': 'capture',
                              'kinds': ['sp'], 'languages': ['EN'], 'modes': ['native', 'toolkit']},
                             {'id': 'native-recipes', 'producer': 'fixture', 'capability': 'effect',
                              'kinds': ['sp', 'mp'], 'languages': ['EN'], 'modes': ['native', 'toolkit']}]}}


def validate(selection):
    fixed = selection.get('cases') == ['native-recipes']
    options = selection.get('options', {})
    if (selection.get('cases') not in (['charge-matrix'], ['native-recipes'])
            or selection.get('kind') not in (('sp', 'mp') if fixed else ('sp',))
            or selection.get('mode') not in ('native', 'toolkit')
            or selection.get('clients', 1) != 1 or selection.get('languages') != ['EN']
            or 'damnlib' not in selection.get('mods', [])
            or options.get('world_template') or options.get('seed_run')
            or (selection.get('kind') == 'mp' and options.get('mp_host') is not True)):
        raise ValueError('Plastic battery requires fresh one-client EN SP/menu Host with damnlib')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / SUITE).rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for source, side in [(root / 'startup/client/ZZStartup.lua', 'client'),
                             (root / 'health/shared/QueueHealthEvents.lua', 'shared'),
                             (root / 'startup/server/ZZStartupServer.lua', 'server')]:
            (lua / side).mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, lua / side / source.name)
    runtime['fixture'] = {'server_ready': '[STARTUP_TEST] SERVER_READY', 'failure_markers': [MARKER + 'FAIL '], 'sandbox': {'Zombies': 6}}


def complete(selection, role, text):
    if selection.get('cases') == ['native-recipes']:
        return receipts.records(text, MARKER, 'COMPLETE') == [{'case': 'native-recipes', 'role': role, 'phases': 6, 'restored': True}]
    return role == 'client1' and receipts.records(text, MARKER, 'COMPLETE') == [{'phases': 12, 'restored': True}]


def verify(root, selection, catalog):
    if selection.get('cases') == ['native-recipes']:
        return verify_native(root, selection)
    issues, rows = [], []
    try:
        text = (Path(root) / 'client1-launch.log').read_text(errors='replace')
        rows = receipts.records(text, MARKER, 'PHASE')
        expected = [(provider, operation, charge) for provider in ('base', 'damn')
                    for operation in ('insert', 'remove') for charge in (0, 0.37, 1)]
        if len(rows) != len(expected) or not complete(selection, 'client1', text):
            raise ValueError('Incomplete battery capture')
        for index, (row, values) in enumerate(zip(rows, expected), 1):
            if (row.get('index') != index
                    or tuple(row.get(key) for key in ('provider', 'operation', 'requestedCharge')) != values
                    or type(row.get('available')) is not bool
                    or row.get('queueDrained') is not True
                    or not isinstance(row.get('before'), list) or not isinstance(row.get('after'), list)):
                raise ValueError('Invalid battery phase provenance')
            if row['available'] and (row.get('actionObserved') is not True
                                     or row.get('nativeDuration') is not True
                                     or row.get('performCalls') != 1):
                raise ValueError('Available battery recipe did not reach native crafting exactly once')
            if row['available']:
                expected_ids = {row['gunID']}
                if row['operation'] == 'insert':
                    expected_ids.add(row['batteryID'])
                if set(row.get('inputIDs', [])) != expected_ids:
                    raise ValueError('Native recipe used different fixture inputs')
            if row['provider'] == 'base' and row['requestedCharge'] > 0 and not row['available']:
                raise ValueError('Required standard battery positive control unavailable')
        if MARKER + 'FAIL ' in text:
            raise ValueError('Battery fixture failed')
    except (OSError, ValueError, TypeError, KeyError) as error:
        issues.append(str(error))
    return {'issues': issues,
            'outcomes': [{'actor': 'client1', 'case': 'charge-matrix',
                          'status': 'failed' if issues else 'captured', 'reason': '; '.join(issues)}],
            'evidence': {'battery': rows, 'limits': [
                'SP recipe availability and native context callback; no physical input or Host transport.',
                'Capture records actual charges and identities; captured does not assert conservation.']}}


_CUSTOM = ('Base.damnCraftInsertBatteryIntoPlasticWeldingGun',
           'Base.damnCraftRemoveBatteryFromPlasticWeldingGun')
_GUN = 'damnCraft.PlasticWeldingGun'
_EFFECT_KEYS = ('index', 'operation', 'requestedCharge', 'recipe', 'gunID', 'batteryID', 'gunUseDelta', 'before', 'after')


def _items(rows):
    if not isinstance(rows, list):
        raise ValueError('Missing battery inventory snapshot')
    result = {}
    for item in rows:
        if (not isinstance(item, dict) or type(item.get('id')) is not int
                or item['id'] in result or type(item.get('uses')) is not int
                or type(item.get('maxUses')) is not int
                or item.get('type') not in (_GUN, 'Base.Battery')
                or item['maxUses'] != (1111 if item['type'] == _GUN else 142)
                or not 0 <= item['uses'] <= item['maxUses']):
            raise ValueError('Invalid bounded battery inventory snapshot')
        result[item['id']] = item
    return result


def _float32(value):
    return struct.unpack('!f', struct.pack('!f', value))[0]


def _stock_stats_uses(uses, use_delta, maximum):
    # B42.21 ItemStatsPacket: setData stores float(uses*useDelta); applyItemStats
    # calls setCurrentUses((int)(maxUses*usedDelta)), with a second float multiply.
    return int(_float32(_float32(maximum) * _float32(_float32(uses) * use_delta)))


def _effect(row, index, operation, charge, *, role='authority', mp=False):
    if not isinstance(row, dict):
        raise ValueError('Invalid fixed battery phase receipt')
    recipe = 'Base.InsertBattery' if operation == 'insert' else 'Base.RemoveBattery'
    if (row.get('index') != index or row.get('operation') != operation
            or row.get('requestedCharge') != charge or row.get('recipe') != recipe
            or type(row.get('gunID')) is not int or type(row.get('batteryID')) is not int
            or row.get('gunUseDelta') != _float32(.0009)):
        raise ValueError('Invalid fixed battery phase provenance')
    gun_id, battery_id = row['gunID'], row['batteryID']
    before, after = _items(row.get('before')), _items(row.get('after'))
    if before.get(gun_id, {}).get('type') != _GUN or after.get(gun_id, {}).get('type') != _GUN:
        raise ValueError('Native battery craft changed gun identity')
    expected_before = {gun_id, battery_id} if operation == 'insert' else {gun_id}
    if set(before) != expected_before:
        raise ValueError('Unexpected fixture source items')
    if operation == 'insert':
        if gun_id == battery_id or before[battery_id]['type'] != 'Base.Battery' or before[gun_id]['uses'] != 0:
            raise ValueError('Invalid insertion inputs')
        source, target_max = before[battery_id], 1111
    else:
        if battery_id != -1:
            raise ValueError('Removal was seeded with a battery')
        source, target_max = before[gun_id], 142
    # The game seeds bounded integer native uses and truncates the transfer.
    if source['uses'] != int(source['maxUses'] * charge + .5):
        raise ValueError('Unexpected battery source charge')
    transferred = source['uses'] * target_max // source['maxUses']
    codec = mp and role == 'local' and operation == 'insert' and charge > 0
    observed = _stock_stats_uses(transferred, row['gunUseDelta'], 1111) if codec else transferred
    if (row.get('effectRole') != role or row.get('nativeTransferUses') != transferred
            or row.get('expectedObservedUses') != observed
            or row.get('stockStatsCodec') != ('native-item-stats' if codec else 'none')):
        raise ValueError('Invalid explicit native transfer/stock packet receipt semantics')
    if operation == 'insert':
        if set(after) != {gun_id} or after[gun_id]['uses'] != observed:
            raise ValueError('Battery insertion did not consume input or transfer exact native uses')
    else:
        outputs = [item for item in after.values() if item['type'] == 'Base.Battery']
        if (after[gun_id]['uses'] != 0 or len(after) != (2 if charge else 1)
                or len(outputs) != (1 if charge else 0)
                or (outputs and (outputs[0]['id'] in before or outputs[0]['uses'] != transferred))):
            raise ValueError('Battery removal produced wrong charge, identities or output count')


def verify_native(root, selection):
    issues, evidence = [], {}
    try:
        root = Path(root)
        client = (root / 'client1-launch.log').read_text(errors='replace')
        mp = selection['kind'] == 'mp'
        server = (root / 'server-launch.log').read_text(errors='replace') if mp else client
        for role, text in [('client1', client), *([('server', server)] if mp else [])]:
            if receipts.records(text, MARKER, 'RECIPES') != [dict(role=role, customAbsent=True, basePresent=True)]:
                raise ValueError('Missing exact fixed recipe registry evidence for ' + role)
            if not complete(selection, role, text) or MARKER + 'FAIL ' in text:
                raise ValueError('Incomplete fixed battery lifecycle for ' + role)
        local = receipts.records(client, MARKER, 'LOCAL')
        authority = receipts.records(server, MARKER, 'AUTHORITY')
        native = receipts.records(client, MARKER, 'NATIVE')
        if any(len(rows) != 6 for rows in (local, authority, native)):
            raise ValueError('Missing/duplicate fixed battery phase receipts')
        plans = [(operation, charge) for operation in ('insert', 'remove') for charge in (0, .37, 1)]
        fixture_ids = set()
        for index, ((operation, charge), effect, actual, action) in enumerate(zip(plans, local, authority, native), 1):
            _effect(effect, index, operation, charge, role='local', mp=mp)
            _effect(actual, index, operation, charge, role='authority', mp=mp)
            if (any(effect.get(key) != actual.get(key) for key in _EFFECT_KEYS if key != 'after')
                    or [{k: v for k, v in item.items() if k != 'uses'} for item in effect['after']]
                    != [{k: v for k, v in item.items() if k != 'uses'} for item in actual['after']]):
                raise ValueError('Battery client/server effect identities or charges differ')
            ids = {item['id'] for item in effect['before'] + effect['after']}
            if fixture_ids & ids:
                raise ValueError('Battery phases reused fixture identities')
            fixture_ids.update(ids)
            positive = charge > 0
            inputs = [effect['gunID']]
            if operation == 'insert':
                inputs.append(effect['batteryID'])
            if (type(actual.get('performCalls')) is not int or actual['performCalls'] != int(positive)
                    or actual.get('nativeDuration') is not positive
                    or actual.get('observerIntact') is not True
                    or not isinstance(actual.get('inputIDs'), list)
                    or sorted(actual['inputIDs']) != sorted(inputs if positive else [])):
                raise ValueError('Missing exact authoritative native craft/input observation')
            expected_menu = [dict(recipe=effect['recipe'], enabled=True)] if positive else []
            if not isinstance(action, dict):
                raise ValueError('Invalid native battery observation')
            if (action.get('index') != index or action.get('recipe') != effect['recipe']
                    or action.get('gunID') != effect['gunID'] or action.get('available') is not positive
                    or action.get('menu') != expected_menu or action.get('queueDrained') is not True
                    or action.get('craftObserved') is not positive or action.get('nativeDuration') is not positive
                    or type(action.get('duration')) not in (int, float)
                    or (action['duration'] <= 1 if positive else action['duration'] != 0)):
                raise ValueError('Invalid standard battery menu/native duration/queue evidence')
        replication = [dict(index=l['index'], gunID=l['gunID'], authorityUses=a['after'][0]['uses'],
                            clientUses=l['after'][0]['uses'], nativeTransferUses=a['nativeTransferUses'],
                            expectedClientUses=l['expectedObservedUses'], codec=l['stockStatsCodec'],
                            chargeMismatch=l['after'][0]['uses'] != a['after'][0]['uses'])
                       for l, a in zip(local, authority) if l['operation'] == 'insert' and l['requestedCharge'] > 0]
        evidence = dict(local=local, authority=authority, native=native, stockStatsReplication=replication, limits=[
            'Native context-menu callback with ordinary durations; no physical input claim.',
            'Authority uses exact native integer transfer. MP kept-gun insertion uses exact stock IEEE754 float stats normalization, which loses charge (414 -> 413 and 1111 -> 1110); no idealized charge or client/server equality claim.'])
    except (OSError, KeyError, ValueError, TypeError) as error:
        issues.append(str(error))
    return {'issues': issues, 'evidence': evidence,
            'outcomes': [{'actor': 'client1', 'case': 'native-recipes',
                          'status': 'failed' if issues else 'passed', 'reason': '; '.join(issues)}]}
