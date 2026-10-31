"""Independent native endpoints, drag feedback and Host authority are all required."""
import math
from pathlib import Path

from queue_checks import receipts

MARKER = '[SMART_DEPOSIT_HOST] '
PNG = b'\x89PNG\r\n\x1a\n'
EVENTS = {'SETUP', 'SEED', 'PREVIEW', 'SHOT', 'QUEUED', 'TIMING', 'EFFECT', 'EXTRAS',
          'FULL', 'RELEASE', 'RESTORED', 'COMPLETE'}


def ensure(condition, message):
    if not condition:
        raise ValueError('Smart Deposit Host: ' + message)


def require(row, **expected):
    ensure(type(row) is dict, 'receipt must be an object')
    for key, value in expected.items():
        ensure(type(row.get(key)) is type(value) and row[key] == value, 'guard differs: ' + key)


def number(value, name, minimum=None):
    ensure(type(value) in (int, float) and math.isfinite(value), 'invalid number: ' + name)
    ensure(minimum is None or value >= minimum, 'number below minimum: ' + name)
    return value


def ids(value, count=None):
    ensure(type(value) is list and (count is None or len(value) == count), 'invalid identity cohort size')
    ensure(all(type(item) is int for item in value) and len(set(value)) == len(value), 'duplicate or invalid identities')
    return value


def records(text):
    result = []
    for line in text.splitlines():
        if MARKER not in line:
            continue
        event, separator, body = line.split(MARKER, 1)[1].partition(' ')
        if event == 'DIAGNOSTIC':
            continue
        ensure(event in EVENTS and separator and body and len(body) <= 65536, 'unknown, failed or malformed receipt')
        result.append((event, receipts.decode_object(body)))
    return result


def envelope(selection, role):
    return dict(suite='smart-deposit', case='partial', kind='mp', mode=selection['mode'],
                role='server' if role == 'server' else 'client')


def complete(text, selection, role):
    try:
        rows = [row for event, row in records(text) if event == 'COMPLETE']
        ensure(len(rows) == 1, 'completion count')
        require(rows[0], **envelope(selection, role), phases=2)
        return True
    except (ValueError, TypeError, KeyError):
        return False


def snapshot(row, original, expected, baseline=None):
    """Derive identity, capacity and preservation claims from raw endpoint contents."""
    ensure(type(row) is dict, 'missing endpoint snapshot')
    ensure(set(ids(row['originalRootIds'])) == set(original), 'original root cohort changed')
    root = ids(row['rootIds'])
    ensure(set(original) <= set(root), 'original item left root')
    items = row['items']
    ensure(type(items) is list, 'invalid owned item rows')
    ensure(set(ids([item['id'] for item in items])) == set(expected), 'owned cohort differs')
    item_map = {item['id']: item for item in items}
    containers = row['crates']
    ensure(type(containers) is list and len(containers) == 3, 'expected three owned crates')
    ensure(sorted(crate['slot'] for crate in containers) == [1, 2, 3], 'invalid crate slots')
    endpoint_ids = {'root': root}
    for crate in containers:
        slot = crate['slot']
        contents = ids(crate['itemIds'])
        endpoint_ids['crate' + str(slot)] = contents
        weight = number(crate['weight'], 'crate weight', 0)
        capacity = number(crate['effectiveCapacity'], 'effective capacity', 0)
        ensure(crate['capacity'] == 10, 'owned crate capacity changed')
        ensure(weight <= capacity + .0001, 'crate overfilled')
        ensure(set(contents) == {key for key, endpoint in expected.items() if endpoint == 'crate' + str(slot)},
               'crate contains missing or foreign item')
        ensure(abs(sum(number(item_map[key]['weight'], 'item weight', 0) for key in contents) - weight) < .001,
               'crate aggregate weight contradicts contents')
    ensure(set(root) == set(original) | {key for key, endpoint in expected.items() if endpoint == 'root'},
           'unexpected root contents')
    for key, endpoint in expected.items():
        item = item_map[key]
        require(item, count=1, endpoint=endpoint)
        ensure(sum(values.count(key) for values in endpoint_ids.values()) == 1, 'item is missing or duplicated across endpoints')
        ensure(key in endpoint_ids[endpoint], 'item row contradicts endpoint contents')
        ensure(type(item['type']) is str and item['type'].startswith('Base.'), 'invalid native fullType')
        number(item['weight'], 'item weight', 0)
        if baseline is not None and key in baseline:
            ensure(item['type'] == baseline[key]['type'] and abs(item['weight'] - baseline[key]['weight']) < .0001,
                   'owned item type/weight changed')
    return item_map


def one(rows, event):
    found = [row for key, row in rows if key == event]
    ensure(len(found) == 1, 'expected exactly one ' + event)
    return found[0]


def phase_expected(phase, moved=False, extras=()):
    order = ids(phase['order'], 3)
    ensure(sorted(order) == [1, 2, 3], 'routing order is not an owned-crate permutation')
    samples, stock, fillers = ids(phase['sampleIds'], 4), ids(phase['stockIds'], 2), ids(phase['fillerIds'], 3)
    ids(samples + stock + fillers + list(extras), 9 + len(extras))
    expected = {key: 'root' for key in samples + list(extras)}
    expected.update({stock[0]: 'crate' + str(order[1]), stock[1]: 'crate' + str(order[2])})
    expected.update({key: 'crate' + str(slot) for slot, key in enumerate(fillers, 1)})
    if moved:
        expected.update({key: 'crate' + str(slot) for key, slot in zip(samples[:3], reversed(order))})
    return expected


def _verify(root, text, selection):
    root = Path(root)
    all_rows = {'client': records(text), 'server': records((root / 'server-launch.log').read_text(errors='replace'))}
    proofs, shots = {}, []
    token = None
    original = None
    origin = None
    for role, rows in all_rows.items():
        setup = one(rows, 'SETUP')
        current_token = setup['ids']['token']
        ensure(type(current_token) is str and bool(current_token), 'missing session token')
        if token is None:
            token = current_token
        ensure(token == current_token, 'client/server session differs')
        current_origin = setup['ids']['origin']
        ensure(type(current_origin) is dict and all(type(current_origin.get(key)) is int for key in ('x', 'y', 'z')),
               'invalid fixture origin')
        if origin is None:
            origin = current_origin
        ensure(current_origin == origin, 'client/server fixture origin differs')
        current_original = ids(setup['snapshot']['originalRootIds'])
        if original is None:
            original = current_original
        ensure(set(original) == set(current_original), 'client/server original inventory differs')
        snapshot(setup['snapshot'], original, {})
        for event, row in rows:
            require(row, **envelope(selection, role), token=token)
        sequence = [event for event, _ in rows]
        per_phase = (['SEED', 'PREVIEW', 'SHOT', 'QUEUED', 'TIMING', 'TIMING', 'TIMING', 'EFFECT', 'EXTRAS', 'FULL', 'RELEASE']
                     if role == 'client' else ['SEED', 'EFFECT', 'EXTRAS', 'FULL', 'RELEASE'])
        ensure(sequence == ['SETUP'] + per_phase * 2 + ['RESTORED', 'COMPLETE'], 'receipt lifecycle order/duplicates differ')
        role_proofs = []
        for index, pane_mode in enumerate(('clean', 'vanilla'), 1):
            phase_rows = [(event, row) for event, row in rows if event not in ('SETUP', 'RESTORED', 'COMPLETE') and row.get('index') == index]
            ensure([event for event, _ in phase_rows] == per_phase, 'phase indices differ')
            for _, row in phase_rows:
                require(row, paneMode=pane_mode)
            seed = one(phase_rows, 'SEED')
            phase = seed['phase']
            require(phase, token=token, index=index, mode=pane_mode)
            baseline = snapshot(seed['snapshot'], original, phase_expected(phase))
            sample_weight = baseline[phase['sampleIds'][0]]['weight']
            ensure(sample_weight > 0, 'empty sample weight')
            for crate in seed['snapshot']['crates']:
                remaining = crate['effectiveCapacity'] - crate['weight']
                ensure(sample_weight <= remaining + .0001 and remaining < sample_weight * 2, 'one-item capacity precondition differs')
            for key in phase['sampleIds']:
                require(baseline[key], type='Base.Nails')
            require(baseline[phase['stockIds'][0]], type='Base.Screws')
            require(baseline[phase['stockIds'][1]], type='Base.Nails')
            for key in phase['fillerIds']:
                require(baseline[key], type='Base.Apple')
            effect = one(phase_rows, 'EFFECT')
            # The native client sort determines sample priority. Verify the same permutation on both roles.
            ordered = ids(effect['sampleIds'], 4)
            ensure(set(ordered) == set(phase['sampleIds']), 'effect uses foreign/missing sample')
            phase = dict(phase, sampleIds=ordered)
            moved = phase_expected(phase, True)
            snapshot(effect['snapshot'], original, moved, baseline)
            extras = one(phase_rows, 'EXTRAS')
            extra_ids = ids(extras['extraIds'], 3)
            full_expected = phase_expected(phase, True, extra_ids)
            full_baseline = snapshot(extras['snapshot'], original, full_expected, baseline)
            for key in extra_ids:
                require(full_baseline[key], type='Base.Nails')
            full = one(phase_rows, 'FULL')
            snapshot(full['snapshot'], original, full_expected, full_baseline)
            release = one(phase_rows, 'RELEASE')
            ensure(set(ids(release['removedIds'], 12)) == set(full_expected), 'release owned cohort differs')
            snapshot(release['snapshot'], original, {})
            if role == 'client':
                authority = seed['originAuthority']
                require(authority, token=token, index=index, ready=True)
                for axis in ('x', 'y', 'z'):
                    require(authority, **{'square' + axis.upper(): origin[axis]})
                    center = origin[axis] + (0 if axis == 'z' else .5)
                    ensure(abs(number(authority[axis], 'authority origin') - center) <= .02,
                           'server actor was outside fixture origin before seeding')
                preview = one(phase_rows, 'PREVIEW')
                require(preview, pane=True, page=True, cannotDropAny=False)
                validate_preview(preview['items'], ordered, moved, allowed=3)
                snapshot(preview['snapshot'], original, phase_expected(dict(phase, sampleIds=ordered)), baseline)
                queued = one(phase_rows, 'QUEUED')
                require(queued, nativeActions=3, rejectedQueued=False)
                ensure(type(queued['items']) is list and len(queued['items']) == 3, 'native queue count differs')
                for row, key in zip(queued['items'], ordered[:3]):
                    require(row, id=key, source='root', destination=moved[key], initialDuration=-1)
                    ensure(row['queueTime'] == -1, 'native Host queue timing changed')
                timing = [row for event, row in phase_rows if event == 'TIMING']
                for row, key in zip(timing, ordered[:3]):
                    require(row, id=key, source='root', destination=moved[key], initialDuration=-1,
                            started=True, completed=True, startCalls=1, performCalls=1, stopCalls=0)
                    number(row['updateCalls'], 'native update callbacks', 1)
                    number(row['duration'], 'native transaction duration', .000001)
                    require(row, durationSource='native-transaction-duration')
                    ensure(row['transactionDuration'] == row['duration'], 'transaction duration contradicts native API')
                    ensure(type(row['transactionId']) is int and row['transactionId'] > 0, 'missing native transaction identity')
                require(full, pane=False, page=False, cannotDropAny=True, nativeActions=0)
                validate_preview(full['items'], [ordered[3]] + extra_ids, {}, allowed=0, ordered=False)
                shot = one(phase_rows, 'SHOT')
                name = 'smart-deposit-' + pane_mode + '-partial.png'
                require(shot, name=name)
                path = root / 'client1/Screenshots' / name
                ensure(path.is_file() and path.read_bytes()[:8] == PNG, 'missing/invalid screenshot: ' + name)
                shots.append(str(path))
            role_proofs.append(dict(phase=phase, extraIds=extra_ids, seed=seed['snapshot'], effect=effect['snapshot'],
                                    full=full['snapshot'], release=release['snapshot']))
        restored = one(rows, 'RESTORED')
        require(restored, ownedAbsent=True)
        ensure(set(ids(restored['rootIds'])) == set(original), 'cleanup lost or added original root items')
        require(one(rows, 'COMPLETE'), phases=2, restored=True)
        if role == 'server':
            require(restored, removedCrates=3, ownedRemaining=0)
            ensure(len(restored['crates']) == 3, 'owned object cleanup count differs')
            for before, after in zip(setup['ids']['crates'], restored['crates']):
                ensure(all(before[key] == after[key] for key in ('x','y','z','index','token')), 'cleanup targets foreign world object')
                ensure(number(after['afterIndex'], 'removed object index') < 0, 'world object survived cleanup')
        else:
            require(one(rows, 'COMPLETE'), nativeActions=6)
            require(restored, ui=True, options=True, flags=True, positionRestored=True)
            ensure(restored['original'] == restored['actual'] == setup['original'], 'original inventory/equipment not restored')
            position_proof(restored['positionProof'])
            ui_proof(restored['uiProof'])
            baseline_ui = setup['uiBaseline']
            number(baseline_ui['samples'], 'stable UI samples', 3)
            number(baseline_ui['stableSpanMs'], 'stable UI span', 240)
        proofs[role] = role_proofs
    for client, server in zip(proofs['client'], proofs['server']):
        ensure(all(client['phase'][key] == server['phase'][key] for key in ('token', 'index', 'mode', 'order', 'sampleIds', 'stockIds', 'fillerIds')) and client['extraIds'] == server['extraIds'], 'client/server owned identities differ')
        for stage in ('seed', 'effect', 'full', 'release'):
            c, s = client[stage], server[stage]
            ensure({row['id']: row['endpoint'] for row in c['items']} == {row['id']: row['endpoint'] for row in s['items']},
                   'client/server native endpoints differ')
    return dict(screenshots=shots, smart_deposit_host=proofs,
                limits=['One actual menu-Host client; installed Lua drag/drop callbacks, not physical mouse input.',
                        'Screenshots require visual inspection; no contention, dedicated server or remote client claim.'])


def validate_preview(items, sample_ids, destinations, allowed, ordered=True):
    ensure(type(items) is list and len(items) == 4, 'invalid per-item drag feedback')
    keys = ids([item['id'] for item in items], 4)
    ensure(keys == sample_ids if ordered else set(keys) == set(sample_ids), 'drag feedback identities/order differ')
    for index, row in enumerate(items):
        accepted = index < allowed
        require(row, allowed=accepted, cannotDrop=not accepted)
        if accepted:
            require(row, destination=destinations[row['id']])
        else:
            ensure(row.get('destination') in (None, False, ''), 'rejected preview has a destination')


def verify(root, text, selection):
    try:
        return _verify(root, text, selection)
    except (KeyError, IndexError, TypeError) as error:
        raise ValueError('Smart Deposit Host: malformed native proof: ' + str(error)) from error


def position_proof(proof):
    require(proof, minimumWaitMs=100, deadlineMs=10000)
    ensure(100 <= number(proof['elapsedMs'], 'position settle') < 10000, 'position restoration outside bound')
    ensure(proof['elapsedMs'] <= number(proof['lifecycleElapsedMs'], 'position lifecycle') < 10000,
           'position lifecycle outside bound')
    quiet = proof['quiescence']
    require(quiet, minimumStableMs=500)
    number(quiet['stableMs'], 'native motion quiet span', 500)
    number(quiet['samples'], 'native motion samples', 2)
    for sample in (quiet['first'], quiet['last']):
        require(sample, moving=False, hasPath=False)
        ensure(number(sample['deferredX'], 'native deferred motion') == number(sample['deferredY'], 'native deferred motion') == 0,
               'native animation motion still pending before placement')
    ensure(all(quiet['first'][key] == quiet['last'][key] for key in ('x', 'y', 'z')),
           'native position was still moving before placement')
    original, actual = proof['original'], proof['actual']
    require(actual, moving=False, hasPath=False)
    ensure(number(actual['deferredX'], 'restored native motion') == number(actual['deferredY'], 'restored native motion') == 0,
           'native animation motion still pending after return')
    for key in ('x', 'y', 'z'):
        ensure(abs(number(original[key], 'original position') - number(actual[key], 'actual position')) <= .01, 'fractional position not restored')
        axis = key.upper()
        ensure(actual['square'+axis] == actual['currentSquare'+axis] == original['square'+axis], 'native square not restored')


def ui_proof(proof):
    ensure(type(proof) is dict and len(proof['pages']) == 2, 'missing live UI restoration proof')
    for key in ('flags', 'core', 'cleanMode'):
        ensure(proof[key]['expected'] == proof[key]['actual'], 'original UI/core/player state changed: ' + key)
    ensure(set(proof['options']) == {'enableProximity','enableCorpseOnly','enableDualMode','enableNestedContainers_Loot','enableAutoLock'}, 'missing original Better Containers settings')
    for row in proof['options'].values():
        ensure(row['expected'] == row['actual'], 'Better Containers setting changed')
    for page in proof['pages']:
        require(page, inventoryBound=True, selectionRestored=True)
        ensure(page['expected'] == page['actual'], 'native UI geometry/state not restored')
        for key in ('owner','pane'):
            row=page['actual'][key]
            for field in ('x','y','width','height'): number(row[field], 'restored geometry')
            ensure(row['width'] > 0 and row['height'] > 0, 'invalid restored UI dimensions')
