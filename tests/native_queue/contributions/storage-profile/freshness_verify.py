"""Fail-closed functional native freshness receipts; no performance verdict."""
import json

VIEWS = ('grouped', 'hover', 'expanded', 'partial', 'offscreen', 'bar-only',
         'percentage-only', 'disabled', 'hidden')


def integer(value, minimum=0):
    if type(value) is not int or value < minimum:
        raise ValueError('Invalid native freshness count')
    return value


def require(row, **values):
    for key, value in values.items():
        if type(row.get(key)) is not type(value) or row[key] != value:
            raise ValueError('Native freshness guard differs: ' + key)


def strict_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate native freshness JSON key')
        result[key] = value
    return result


def reject_constant(value):
    raise ValueError('Non-finite native freshness JSON value')


def verify(root, text):
    if '[STORAGE_PROFILE] FAIL' in text or 'KahluaException' in text:
        raise ValueError('Native freshness fixture failed')
    events = []
    prefix = '[STORAGE_PROFILE] FRESH_'
    known = {'FRESH_SETUP', 'FRESH_PHASE', 'FRESH_RESTORED'}
    for line in text.splitlines():
        offset = line.find(prefix)
        if offset < 0:
            continue
        receipt = line[offset + len('[STORAGE_PROFILE] '):]
        if len(receipt) > 16384:
            raise ValueError('Oversized native freshness receipt')
        kind, separator, body = receipt.partition(' ')
        if kind not in known or not separator or not body:
            raise ValueError('Unknown or malformed native freshness marker')
        row = json.loads(body, object_pairs_hook=strict_object, parse_constant=reject_constant)
        if type(row) is not dict:
            raise ValueError('Native freshness receipt must be an object')
        events.append((kind, row))
    if [kind for kind, _ in events] != ['FRESH_SETUP'] + ['FRESH_PHASE'] * 19 + ['FRESH_RESTORED'] or text.count('[STORAGE_PROFILE] COMPLETE') != 1:
        raise ValueError('Missing, duplicate or reordered native freshness evidence')
    setup = events[0][1]
    require(setup, native=True, foodType='Base.Apple', food=6, spacers=45, phases=19,
            physicalInput=False, pixelCoverage=False, timing=False, naturalAgeing=False,
            ageControl='fixture-only-restored')
    active = setup.get('activeMode')
    if active not in ('clean', 'vanilla'):
        raise ValueError('Missing initial native freshness owner')
    other = 'vanilla' if active == 'clean' else 'clean'
    specs = [(mode, view) for mode in (active, other) for view in VIEWS] + [(active, 'hover')]
    phases = [row for kind, row in events if kind == 'FRESH_PHASE']
    for index, (row, (mode, view)) in enumerate(zip(phases, specs), 1):
        enabled = mode == active and view not in ('disabled', 'hidden')
        bar, percentage = view not in ('percentage-only', 'disabled'), view not in ('bar-only', 'disabled')
        require(row, index=index, mode=mode, view=view, native=True,
                paneClass='CleanUI_' + ('Clean' if mode == 'clean' else 'Vanilla') + '_ISInventoryPane',
                active=mode == active, fixtureChildren=6 if view in ('expanded', 'partial') else 0, pageVisible=view != 'hidden', paneVisible=True,
                exactOutput=True, currentRows=True, primaryPublished=True, items=True, options=True, tailWorst=True,
                fixtureAgeRestored=True, hiddenVisits=0, bar=bar, percentage=percentage,
                draggedNative=True, draggedPresenterCalls=0, primary=view != 'hidden', directHidden=view == 'hidden',
                layout=True, layoutReserved=mode == active and percentage)
        integer(row.get('rows'), 46)
        integer(row.get('separators'))
        for key in ('visibleRows', 'visibleSeparators', 'foodRows', 'visits', 'rects', 'texts'):
            integer(row.get(key))
        if not enabled and any(row[key] for key in ('visibleRows', 'foodRows', 'visits', 'rects', 'texts')):
            raise ValueError('Inactive/hidden/disabled freshness performed work')
        if enabled and view not in ('offscreen',):
            if row['foodRows'] < 1 or row['visits'] < 1:
                raise ValueError('Visible native food work absent')
            if bar and row['rects'] < 4:
                raise ValueError('Visible native freshness bar absent')
            if view in ('hover', 'expanded', 'partial', 'percentage-only') and row['texts'] < 1:
                raise ValueError('Visible native freshness percentage absent')
            if view in ('grouped', 'bar-only') and row['texts']:
                raise ValueError('Header percentage ignored live hover/flag')
    if not any(row['separators'] > 0 and row['visibleSeparators'] > 0 for row in phases if row['mode'] == 'clean'):
        raise ValueError('Actual native separator rows were not exercised')
    restored = events[-1][1]
    require(restored, ownedRemoved=51, foodRemoved=6, observers=True, items=True,
            options=True, mode=True, fixtureAges=True, phases=19)
    integer(restored.get('originalItems'))
    return {'freshness': phases, 'limits': [
        'Functional observations of actual native Food, selected pane classes and their current published row maps.',
        'Initial BC freshness class ownership is preserved across toggles; the other class remains inactive.',
        'Exact public presenter draw calls and Food eligibility visits are observed and delegated, then restored.',
        'Hidden-panel coverage calls the public presenter directly after native panel visibility changes.',
        'Dragged coverage invokes the actual native renderer programmatically; no physical input or pixel coverage.',
        'Fixture-only tail setAge is restored after each draw; natural ageing and regroup latency are not established.',
        'No timing, FPS, exclusive-run or performance claim.']}
