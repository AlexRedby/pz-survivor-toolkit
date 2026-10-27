"""Fail-closed natural-age SP receipts from actual native inventory rows."""
import json
import math


def require(row, **values):
    for key, value in values.items():
        if type(row.get(key)) is not type(value) or row[key] != value:
            raise ValueError('Native food-age guard differs: ' + key)


def number(row, key, minimum=None, integer=False):
    value = row.get(key)
    if type(value) not in (int, float) or not math.isfinite(value) or integer and type(value) is not int:
        raise ValueError('Invalid native food-age number: ' + key)
    if minimum is not None and value < minimum:
        raise ValueError('Native food-age value below minimum: ' + key)
    return value


def strict_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate native food-age JSON key')
        result[key] = value
    return result


def reject_constant(value):
    raise ValueError('Non-finite native food-age JSON value')


def verify(root, text):
    if '[STORAGE_PROFILE] FAIL' in text or 'KahluaException' in text:
        raise ValueError('Native food-age fixture failed')
    events = []
    prefix = '[STORAGE_PROFILE] AGE_'
    for line in text.splitlines():
        offset = line.find(prefix)
        if offset < 0:
            continue
        receipt = line[offset + len('[STORAGE_PROFILE] '):]
        kind, separator, body = receipt.partition(' ')
        if len(receipt) > 16384 or kind not in ('AGE_SETUP', 'AGE_PHASE', 'AGE_RESTORED') or not separator or not body:
            raise ValueError('Unknown or malformed native food-age receipt')
        value = json.loads(body, object_pairs_hook=strict_object, parse_constant=reject_constant)
        if type(value) is not dict:
            raise ValueError('Native food-age receipt must be an object')
        events.append((kind, value))
    if [kind for kind, _ in events] != ['AGE_SETUP'] + ['AGE_PHASE'] * 4 + ['AGE_RESTORED'] or text.count('[STORAGE_PROFILE] COMPLETE') != 1:
        raise ValueError('Missing, duplicate or reordered native food-age evidence')
    require(events[0][1], native=True, foodType='Base.Apple', phases=4, kind='sp', naturalAgeing=True,
            ageControl='phase-setup-only', physicalInput=False, network=False, timing=False)
    phases = [row for kind, row in events if kind == 'AGE_PHASE']
    specs = [(size, mode) for mode in ('clean', 'vanilla') for size in (199, 200)]
    for index, (row, (size, mode)) in enumerate(zip(phases, specs), 1):
        require(row, index=index, size=size, mode=mode, native=True,
                paneClass='CleanUI_' + ('Clean' if mode == 'clean' else 'Vanilla') + '_ISInventoryPane',
                optimized=mode == 'clean' and size == 200, events=1, headFresh=True, tailFresh=False,
                headGroup=size-1, tailGroup=1, separatePublishedRows=True, identities=True,
                visibleObservation=True, hiddenReopen=True, naturalAgeing=True, observationAgeWrites=0)
        before, after = number(row, 'ageBefore', 0), number(row, 'ageAfter', 5)
        if not before < 5 <= after < 8:
            raise ValueError('Native food did not naturally cross its fresh threshold')
        world_before, world_after = number(row, 'worldBefore', 0), number(row, 'worldAfter', 0)
        event_world = number(row, 'eventWorld', 0)
        if not world_before < event_world <= world_after:
            raise ValueError('Native food-age event lacks forward world time')
        if number(row, 'headId', integer=True) == number(row, 'tailId', integer=True):
            raise ValueError('Native head and tail identities coincide')
        number(row, 'primaryPasses', 2, integer=True)
        if not 500 <= number(row, 'elapsedMs', 0) < 45000:
            raise ValueError('Native food-age observation deadline differs')
    restored = events[-1][1]
    require(restored, ownedRemoved=798, observers=True, items=True, mode=True, optimize=True, phases=4)
    number(restored, 'originalItems', 0, integer=True)
    return {'food_age': phases, 'limits': [
        'SP natural Food ageing, actual selected CleanUI pane renderers and published collapsed groups at 199/200 items.',
        'Only phase setup seeds Apple ages and last-aged time; observation forwards native render calls and never updates ages.',
        'Freshness event, separate native rows and exact item identities survive hiding and reopening the inventory page.',
        'Visible-row functional gate; no clipped-expiry, physical input, pixel, timing, freezer or live generator coverage.',
        'Host/server-owned ageing and replication remain a separate unimplemented gate.']}
