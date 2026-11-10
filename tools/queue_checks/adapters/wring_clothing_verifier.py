"""Read-only report checks over sealed native wring observation receipts."""
import json
import math
from pathlib import Path
import re

from .. import report
from ..placement import validate as validate_placement
from .wring_clothing import CASES, NAMES, PREFIX, PRODUCER, _raw, complete


def _number(value):
    return type(value) in (int, float) and math.isfinite(value)


def _counts(case, name, final):
    # Selected Tidy Up Meister restores the borrowed exact item after the operation.
    return dict(actor=0 if name == 'target' and case == 'world' else 1,
                root=0 if name == 'target' and case in ('worn-bag', 'world') else 1,
                source=1 if case in ('root', 'worn') or name == 'target' else 0)


def check_case(row, selection, prepared, verified, wear_baseline=None):
    issues = []
    try:
        ids = row['ids']; case = ids['case']; editing = selection['mode'] == 'toolkit' and case == 'root'
        native_wear = selection['kind'] == 'mp' and case in ('worn', 'worn-bag')
        if ids != prepared or case not in CASES or ids['mode'] != selection['mode'] or row['server'] != verified:
            raise ValueError('authority or selected identity')
        if ids.get('nativeWearSetup', False) is not native_wear:
            raise ValueError('native owner wear setup declaration')
        if native_wear:
            wear = row['wearSetup']
            item = ids['items']['target']['id'] if case == 'worn' else ids['source']['bag']
            if (wear['type'] != 'ISWearClothing' or wear['producer'] != 'native ISWearClothing constructor'
                or wear['item'] != item or wear['duration'] != 50 or wear['started'] is not True
                or wear['progress'] is not True or not _number(wear['startedAt'])):
                raise ValueError('real native owner wear setup')
            if wear_baseline is not None and row['authorityBaseline'] != wear_baseline:
                raise ValueError('native wear authority baseline receipt')
        elif row.get('wearSetup', False) is not False or row.get('authorityBaseline', False) is not False:
            raise ValueError('unexpected native wear setup')
        validate_placement(row['clientPlacement'], ids['origin'], 'local', centered=True)
        validate_placement(ids['placementProof'], ids['origin'], 'replica' if selection['kind'] == 'mp' else 'local', centered=True)
        source = ids['source']
        if set(source) != {'kind', 'bag', 'world'} or source['kind'] != case:
            raise ValueError('source identity')
        if (type(source['bag']) is not int if case == 'worn-bag' else source['bag'] is not False):
            raise ValueError('worn bag identity')
        if case == 'world':
            world = source['world']; origin = ids['origin']
            if (set(world) != {'x', 'y', 'z', 'index'} or any(type(v) is not int for v in world.values())
                or world['index'] < 0 or world['x'] != origin['x'] or world['y'] != origin['y'] - 1 or world['z'] != origin['z']):
                raise ValueError('furniture identity')
        elif source['world'] is not False:
            raise ValueError('unexpected world source')
        specs = ids['items']
        if set(specs) != set(NAMES) or len({v['id'] for v in specs.values()}) != len(NAMES):
            raise ValueError('fixture clothing identities')
        for name, spec in specs.items():
            shoes = name == 'tail' or name == 'target' and case in ('worn', 'world')
            if (type(spec['id']) is not int or spec['type'] != ('Base.Shoes_FlipFlop' if shoes else 'Base.Socks_Ankle')
                or spec['cap'] != 10 or spec['nativeShoe'] is not False or spec['bodyLocationClass'] != 'ItemBodyLocation'
                or spec['bodyLocation'] != ('base:shoes' if shoes else 'base:socks') or spec['initial'] != 100
                or not _number(spec['weight']) or spec['weight'] <= 0):
                raise ValueError('native clothing type/cap/initial state')
        for phase in (('input', 'authorityBaseline', 'client', 'server') if native_wear else ('input', 'client', 'server')):
            snapshot = row[phase]; final = phase not in ('input', 'authorityBaseline')
            if snapshot['case'] != case or snapshot['source'] != source or set(snapshot['items']) != set(NAMES):
                raise ValueError('snapshot identity')
            for name, item in snapshot['items'].items():
                spec = specs[name]
                expected_native = {key: spec[key] for key in ('bodyLocation', 'bodyLocationClass', 'nativeShoe', 'cap')}
                if (item['id'] != spec['id'] or item['type'] != spec['type'] or item['counts'] != _counts(case, name, final)
                    or item['native'] != expected_native
                    or item['worn'] is not (not final and case == 'worn' and name == 'target')
                    or not _number(item['weight']) or not 0 < item['weight'] <= spec['weight'] + .01
                    or not _number(item['wetness'])):
                    raise ValueError('clothing identity/source/weight/worn state')
                low, high = (80, 100) if not final or name == 'cancelled' else (spec['cap'] - 5, spec['cap'] + .01)
                if not low < item['wetness'] <= high:
                    raise ValueError('wetness effect or untouched cancelled garment')
        if (row['status'] != 'passed' or row['queueIdle'] is not True or not _number(row['settleMilliseconds'])
            or row['settleMilliseconds'] < 1000 or row['edit'] != dict(cancelled=editing, reordered=editing, repeatDenied=editing, untouched=True)):
            raise ValueError('pending edit/idle evidence')
        commands = row['commands']
        prelude = [('target', 'ISUnequipAction')] if case == 'worn' else [('target', 'ISInventoryTransferAction')] if case in ('worn-bag', 'world') else []
        expected = [('front', 'ISWringClothing')]
        if editing: expected += [('cancelled', 'ISWringClothing')]
        expected += prelude + [('target', 'ISWringClothing')]
        if editing: expected += [('repeat', 'ISWringClothing')]
        expected += [('tail', 'ISWringClothing')]
        if [(c['name'], c['type']) for c in commands] != expected:
            raise ValueError('complete native producer sequence')
        starts = []
        for command in commands:
            name = command['name']; cancelled = editing and name in ('cancelled', 'repeat')
            key = 'target' if name == 'repeat' else name
            # The native MP transfer wrapper waits for ItemTransactionPacket;
            # its constructor deliberately sets maxTime=-1, not a paid duration.
            transaction_wait = command['type'] == 'ISInventoryTransferAction' and selection['kind'] == 'mp'
            duration_valid = _number(command['duration']) and (command['duration'] == -1 if transaction_wait else command['duration'] > 0)
            if (command['producer'] != PRODUCER or command['item'] != specs[key]['id']
                or not duration_valid
                or bool(command.get('cancelled')) != cancelled):
                raise ValueError('native producer or cancellation identity')
            if cancelled:
                if command['started'] is not False or command['progress'] is not False or 'startedAt' in command:
                    raise ValueError('cancelled action started')
            elif command['type'] == 'ISWringClothing':
                if command['started'] is not True or command['progress'] is not True or not _number(command.get('startedAt')):
                    raise ValueError('native wring progress')
                starts.append(command['startedAt'])
            if command['type'] == 'ISWringClothing':
                wetness = command['constructorWetness']
                if (command['callbacksUntouched'] is not True or not _number(wetness) or not 80 < wetness <= 100
                    or command['duration'] != math.ceil(wetness * 5)):
                    raise ValueError('native wring callbacks/duration')
        if starts != sorted(starts):
            raise ValueError('native completion order')
        if native_wear and starts[0] <= row['wearSetup']['startedAt']:
            raise ValueError('wring started before native wear setup')
    except (KeyError, TypeError, ValueError, IndexError) as error:
        issues.append('Wring clothing evidence differs: ' + str(error))
    return issues


def verify(root, selection, catalog):
    issues = []; outcomes = []; setups = []; root = Path(root)
    try:
        text = (root / 'client1-launch.log').read_text(errors='replace')
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
        events = [e for e in report.events(text) if e.get('suite') == 'wring-clothing']
        rows = [e for e in events if e.get('event') == 'case']
        setups = [e for e in events if e.get('event') == 'setup']; ends = [e for e in events if e.get('event') == 'complete']
        prepared, verified = (_raw(authority, marker) for marker in ('PREPARED', 'VERIFIED'))
        wear_baselines = _raw(authority, 'WEAR_BASELINE')
        placements = _raw(text, 'CLIENT_PLACEMENT'); cases = list(CASES)
        if (len(setups) != 1 or len(ends) != 1 or [r.get('id') for r in rows] != cases
            or any([r.get('case') for r in values] != cases for values in (prepared, verified, placements))):
            raise ValueError('missing, duplicate or out-of-order authority/case evidence')
        wear_cases = ['worn', 'worn-bag'] if selection['kind'] == 'mp' else []
        if [baseline.get('case') for baseline in wear_baselines] != wear_cases:
            raise ValueError('missing, duplicate or out-of-order native wear baseline')
        ordered_authority = [(match.group(1), json.loads(match.group(2)).get('case')) for match in re.finditer(
            re.escape(PREFIX) + r'(PREPARED|WEAR_BASELINE|VERIFIED) ([^\n]+)', authority)]
        expected_authority = [(marker, case) for case in cases for marker in
                              (('PREPARED', 'WEAR_BASELINE', 'VERIFIED') if case in wear_cases else ('PREPARED', 'VERIFIED'))]
        if ordered_authority != expected_authority:
            raise ValueError('native preparation/baseline/effect authority order')
        if (setups[0].get('cases') != cases or setups[0].get('queueEnabled') is not (selection['mode'] == 'toolkit')
            or setups[0].get('nativeDurations') is not True or ends[0].get('cases') != cases
            or type(setups[0].get('adapterInstalled')) is not bool
            or selection['mode'] == 'toolkit' and setups[0].get('adapterInstalled') is not True
            or ends[0].get('performed') != len(cases) or ends[0].get('failed') != 0 or ends[0].get('skipped') != 0):
            raise ValueError('setup or completion evidence')
        for index, case in enumerate(cases):
            row = rows[index]
            if (row.get('actor') != 'client1' or row.get('kind') != selection['kind'] or row.get('mode') != selection['mode']
                or placements[index] != dict(case=case, proof=row.get('clientPlacement'))):
                raise ValueError('actor or placement receipt')
            baseline = next((value for value in wear_baselines if value['case'] == case), None)
            errors = check_case(row, selection, prepared[index], verified[index], baseline); issues += errors
            outcomes.append(dict(actor='client1', case=case, status='failed' if errors else 'passed', reason='; '.join(errors),
                outcome=dict(effectsVerified=not errors, serverAuthorityVerified=not errors, tailCompleted=not errors,
                             pendingEditsVerified=not errors and selection['mode'] == 'toolkit' and case == 'root')))
        if not complete(selection, 'client1', text): issues.append('Missing completion marker')
    except (OSError, ValueError, KeyError, TypeError) as error:
        issues.append(str(error))
    return dict(issues=issues, outcomes=outcomes, evidence={'adapterInstalled': setups[0].get('adapterInstalled') if len(setups) == 1 else None, 'limits': [
        'Programmatic native inventory UI callbacks; no physical input, active edits, recovery or capacity authority.',
        'Wetness caps allow bounded natural drying after native completion; rain disabled only in the disposable fixture world.']})
