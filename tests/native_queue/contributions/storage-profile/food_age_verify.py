"""Strict native visibility, natural-expiry and independent Host authority proof."""
import math
from pathlib import Path

from queue_checks import receipts

MARKER = '[STORAGE_PROFILE] '
SPECS = [(size, mode, exposure) for mode in ('clean', 'vanilla') for size in (199, 200)
         for exposure in ('visible', 'hidden', 'clipped')]
EVENTS = ('AGE_SETUP', 'AGE_PHASE', 'AGE_RESTORED', 'AGE_COMPLETE')


def require(row, **values):
    ensure(type(row) is dict, 'Invalid native food-age object')
    for key, value in values.items():
        if type(row.get(key)) is not type(value) or row[key] != value:
            raise ValueError('Native food-age guard differs: ' + key)


def number(row, key, minimum=None, integer=False):
    ensure(type(row) is dict, 'Invalid native food-age object')
    value = row.get(key)
    if type(value) not in (int, float) or not math.isfinite(value) or integer and type(value) is not int:
        raise ValueError('Invalid native food-age number: ' + key)
    if minimum is not None and value < minimum:
        raise ValueError('Native food-age value below minimum: ' + key)
    return value


def ensure(condition, reason):
    if not condition:
        raise ValueError(reason)


def records(text):
    result = []
    for line in text.splitlines():
        prefix = MARKER + 'AGE_'
        if prefix not in line:
            continue
        event, separator, body = line.split(MARKER, 1)[1].partition(' ')
        ensure(event in EVENTS and separator and body and len(body) <= 32768,
               'Unknown or malformed native food-age receipt')
        result.append((event, receipts.decode_object(body)))
    return result


def envelope(selection, role):
    return dict(schema=2, suite='storage-profile', case='inventory-food-age', kind=selection['kind'],
                mode=selection['mode'], role='sp' if selection['kind'] == 'sp' else
                'server' if role == 'server' else 'client')


def complete(text, selection, role):
    try:
        found = [row for event, row in records(text) if event == 'AGE_COMPLETE']
        for row in found:
            require(row, phases=len(SPECS), restored=True)
        return found == [
            dict(envelope(selection, role), phases=len(SPECS), restored=True)]
    except (ValueError, TypeError):
        return False


def bounds(row):
    for key in ('world', 'age', 'primaryPasses', 'rowTop', 'rowBottom', 'header', 'height'):
        number(row, key)
    for key in ('pageVisible', 'paneVisible', 'rowVisible'):
        ensure(type(row.get(key)) is bool, 'Missing visibility state: ' + key)
    ensure(row['rowBottom'] > row['rowTop'] and row['height'] > row['header'], 'Invalid native row bounds')
    geometric = (row['pageVisible'] and row['paneVisible'] and row['rowBottom'] > row['header']
                 and row['rowTop'] < row['height'] - 1)
    ensure(row['rowVisible'] == geometric, 'Native row visibility contradicts its bounds')


def exposure_proof(row):
    proof = row['exposureProof']
    start, finish = proof['start'], proof['finish']
    bounds(start); bounds(finish)
    threshold = number(proof, 'potentialThresholdWorld')
    ensure(row['worldBefore'] <= start['world'] < finish['world'] <= row['worldAfter'],
           'Visibility observations are outside the phase interval')
    ensure(start['age'] < row['offAge'] and start['world'] < threshold <= finish['world'],
           'Concealment did not span the natural freshness boundary')
    number(proof, 'foodVisiblePasses', 0, integer=True)
    if row['exposure'] == 'visible':
        ensure(start['rowVisible'] and finish['rowVisible'] and proof['foodVisiblePasses'] > 0,
               'Visible control did not render the actual food row')
    else:
        ensure(not start['rowVisible'] and not finish['rowVisible'] and proof['foodVisiblePasses'] == 0,
               'Hidden expiry rendered food during concealment')
        duration = number(proof, 'concealedWorldHours', 0)
        ensure(duration > 0 and abs(duration - (finish['world'] - start['world'])) < .0001,
               'Concealment duration differs from measured world time')
        if row['exposure'] == 'hidden':
            ensure(not start['pageVisible'] and not finish['pageVisible'], 'Page never really hid')
        else:
            ensure(start['pageVisible'] and finish['pageVisible'] and start['paneVisible'] and finish['paneVisible'],
                   'Offscreen control substituted a hidden page')
            ensure(finish['primaryPasses'] > start['primaryPasses'], 'Clipped pane did not actually render')
            for state in (start, finish):
                scroll, minimum = number(state, 'scroll'), number(state, 'minScroll')
                ensure(minimum == min(0, number(state, 'scrollAreaHeight', 1)-number(state, 'scrollHeight', 1))
                       and minimum <= scroll <= 0, 'Offscreen control used an impossible scroll position')
                number(state, 'fillerVisibleRows', 1, integer=True)


def ui_setup_proof(setup):
    baseline, preflight = setup['uiBaseline'], setup['uiPreflight']
    require(baseline, stable=True, samples=3, intervalMs=120, deadlineMs=10000)
    times = baseline['sampleTimesMs']
    ensure(type(times) is list and len(times) == 3 and all(type(value) is int and value >= 0 for value in times),
           'Missing native UI baseline samples')
    ensure(all(b-a >= 120 for a, b in zip(times, times[1:])), 'Native UI samples did not span separate updates')
    span = number(baseline, 'stableSpanMs', 240)
    elapsed = number(baseline, 'elapsedMs', 240)
    ensure(span == times[-1]-times[0] and span <= elapsed < 10000,
           'Native UI baseline did not settle within its bounded interval')
    require(preflight, modeChanged=True, resized=True, relocated=True, restored=True, deadlineMs=10000)
    ensure(type(preflight['originalMode']) is bool and type(preflight['temporaryMode']) is bool
           and preflight['originalMode'] != preflight['temporaryMode'], 'Native UI preflight did not switch modes')
    ensure(number(preflight, 'elapsedMs', 0) < 10000, 'Native UI preflight exceeded its deadline')
    ensure(type(baseline['pages']) is list and len(baseline['pages']) == 2
           and type(preflight['pages']) is list and len(preflight['pages']) == 2, 'Missing native UI page proof')
    for index, (page, transition) in enumerate(zip(baseline['pages'], preflight['pages']), 1):
        require(page, page=index, inventoryBound=True)
        require(transition, page=index)
        owner, pane = page['owner'], page['pane']
        for geometry in (owner, pane):
            for key in ('x', 'y', 'width', 'height'):
                number(geometry, key)
            ensure(geometry['width'] > 0 and geometry['height'] > 0, 'Invalid native UI dimensions')
        ensure(pane['x'] >= 0 and pane['y'] >= 0 and pane['x']+pane['width'] <= owner['width']+.01
               and pane['y']+pane['height'] <= owner['height']+.01, 'Native UI baseline contains transient pane geometry')
        for dimension in ('x', 'y', 'width', 'height'):
            minimum = 1 if dimension in ('width', 'height') else 0
            ensure(number(transition['original'], dimension, minimum) == owner[dimension]
                   and number(transition['restored'], dimension, minimum) == owner[dimension]
                   and number(transition['temporary'], dimension, minimum) != owner[dimension],
                   'Native UI geometry roundtrip did not restore its baseline')


def verify_role(text, selection, role):
    ensure(MARKER + 'FAIL' not in text and 'KahluaException' not in text, 'Native food-age fixture failed')
    rows = records(text)
    ensure([event for event, _ in rows] == ['AGE_SETUP'] + ['AGE_PHASE'] * len(SPECS)
           + ['AGE_RESTORED', 'AGE_COMPLETE'], 'Missing, duplicate or reordered food-age lifecycle')
    for _, row in rows:
        require(row, **envelope(selection, role))
    ensure(complete(text, selection, role), 'Incomplete native food-age lifecycle')
    setup, restored = rows[0][1], rows[-2][1]
    food_type, off_age, off_max = ('Base.Apple', 5, 8) if selection['kind'] == 'sp' else ('Base.Cabbage', 2, 4)
    endpoint = 'root' if selection['kind'] == 'sp' else 'ambient'
    require(setup, phases=len(SPECS), foodType=food_type, naturalAgeing=True, ageControl='phase-setup-only',
            physicalInput=False, clockUnchanged=True, forcedAgeUpdates=0, fillersPerPhase=60)
    clock = number(setup, 'minutesPerDay', 1)
    require(setup, observationAgeWrites=0, periodicAgeReplication=False,
            initialStateReplication=selection['kind'] == 'mp')
    if role != 'server':
        ui_setup_proof(setup)
    ensure(setup['clock']['minutesPerDay'] == clock and setup['clock']['foodRemoval'] == -1
           and setup['clock']['foodRotSpeed'] in (1, 2, 3, 4, 5), 'Invalid native ageing clock/settings')
    phases = [row for event, row in rows if event == 'AGE_PHASE']
    previous_world = None
    for index, (row, (size, mode, exposure)) in enumerate(zip(phases, SPECS), 1):
        require(row, index=index, size=size, paneMode=mode, exposure=exposure, foodType=food_type,
                offAge=off_age, offAgeMax=off_max, events=0 if role == 'server' else 1,
                headFresh=True, tailFresh=False, identities=True, endpoint=endpoint,
                naturalAgeing=True, observationAgeWrites=0, forcedAgeUpdates=0)
        ensure(row['minutesPerDay'] == clock and row['clock'] == setup['clock'],
               'World-clock or sandbox settings changed during natural ageing')
        if role == 'server':
            require(row, serverOwned=True, clientPhaseComplete=True)
        ids = row['foodIds']
        # Native factory IDs are random. The fixture releases the previous
        # phase before preparing another; only live members must be unique.
        # Phase ordering, native reference conservation and Host replica
        # agreement still bind each ID to its own phase and container.
        ensure(type(ids) is list and len(ids) == size and all(type(value) is int for value in ids)
               and len(set(ids)) == size, 'Owned food identities differ or alias within a phase')
        head, tail = number(row, 'headId', integer=True), number(row, 'tailId', integer=True)
        ensure(head != tail and head in ids and tail in ids, 'Invalid native head/tail identity')
        before, after = number(row, 'ageBefore', 0), number(row, 'ageAfter', off_age)
        ensure(before < off_age <= after < off_max, 'Native food did not cross its freshness threshold')
        start, finish = number(row, 'worldBefore', 0), number(row, 'worldAfter', 0)
        ensure(start < finish and (previous_world is None or previous_world <= start), 'Phase time did not advance')
        previous_world = finish
        if role != 'server':
            require(row, paneClass='CleanUI_' + ('Clean' if mode == 'clean' else 'Vanilla') + '_ISInventoryPane',
                    optimized=mode == 'clean' and size == 200, headGroup=size-1, tailGroup=1,
                    separatePublishedRows=True, tailBeyond50=True)
            number(row, 'primaryPasses', 2, integer=True)
            ensure(start < number(row, 'eventWorld') <= finish, 'Native event lacks forward phase time')
            exposure_proof(row)
            cycles = row['cycles']
            ensure(type(cycles) is list and len(cycles) == 3, 'Missing repeated regrouping observations')
            for cycle, state in enumerate(cycles, 1):
                require(state, cycle=cycle, expandedActualCount=size, collapsedActualCount=size,
                        headGroup=size-1, tailGroup=1, identities=True)
                number(state, 'expandedPublishedRows', 3, integer=True)
    require(restored, ownedRemoved=sum(spec[0] for spec in SPECS), fillerRemoved=60*len(SPECS),
            objectsRemoved=len(SPECS) if selection['kind'] == 'mp' else 0,
            items=True, settings=True, phases=len(SPECS))
    number(restored, 'originalItems', 0, integer=True)
    ensure(restored['minutesPerDay'] == clock and restored['clock'] == setup['clock'],
           'Original world-clock or sandbox settings not preserved')
    if role != 'server':
        require(restored, observers=True, ui=True)
        if selection['kind'] == 'mp':
            require(restored, positionRestored=True)
            proof = restored['positionProof']
            require(proof, deadlineMs=10000, minimumWaitMs=100)
            ensure(100 <= number(proof, 'elapsedMs') < 10000, 'Host position return was not bounded and settled')
            original, actual = proof['original'], proof['actual']
            require(actual, moving=False, hasPath=False)
            for axis in ('x', 'y', 'z'):
                target = number(original, axis)
                ensure(abs(number(actual, axis)-target) <= .01, 'Host position lost original coordinates')
                cell = 'square' + axis.upper()
                ensure(number(original, cell, integer=True) == math.floor(target)
                       and number(actual, cell, integer=True) == original[cell]
                       and number(actual, 'currentSquare' + axis.upper(), integer=True) == original[cell],
                       'Host square did not settle before UI restoration')
    return {'phases': phases, 'setup': setup, 'restored': restored}


def _verify(root, text, selection):
    roles = {'sp' if selection['kind'] == 'sp' else 'client': text}
    if selection['kind'] == 'mp':
        roles['server'] = (Path(root) / 'server-launch.log').read_text(errors='replace')
    result = {role: verify_role(body, selection, role) for role, body in roles.items()}
    if selection['kind'] == 'mp':
        for client, server in zip(result['client']['phases'], result['server']['phases']):
            ensure(sorted(client['foodIds']) == sorted(server['foodIds']), 'Client/server item replicas differ')
            ensure(all(client[key] == server[key] for key in ('index', 'foodType', 'headId', 'tailId', 'exposure', 'paneMode')),
                   'Client/server phase ownership differs')
            proof = client['authority']
            require(proof, index=client['index'], headId=client['headId'], tailId=client['tailId'],
                    foodType=client['foodType'], endpoint='ambient', count=client['size'], identities=True,
                    headFresh=True, tailFresh=False)
            ensure(proof['tailAge'] == server['ageAfter'] and proof['world'] == server['worldAfter']
                   and proof['clock'] == server['clock'], 'Client authority acknowledgement differs from server receipt')
    return {'food_age': result, 'limits': [
        'SP Apple root inventory and one-client menu-Host active Cabbage in an owned ambient world container.',
        'Initial exact-item replication and independent native ageing; no periodic age/lastAged replication claim.',
        'Native visible/hidden/offscreen expiry, actual rows and repeated expansion/regrouping at 199/200 items in both renderers.',
        'Setup alone seeds food age; no observer age updates, clock acceleration, physical-input, pixel, WAN or second-player claim.']}


def verify(root, text, selection):
    try:
        return _verify(root, text, selection)
    except (KeyError, TypeError, IndexError) as error:
        raise ValueError('Missing or malformed food-age evidence: ' + str(error)) from error
