"""Verify native observations, without turning measured costs into an FPS verdict."""
import itertools
import json
import math
import re


def number(value, minimum=0, integer=False):
    if type(value) not in (int, float) or not math.isfinite(value) or value < minimum or integer and type(value) is not int:
        raise ValueError('Invalid inventory-work measurement')
    return value


def distribution(value, minimum=1):
    calls = number(value.get('calls'), minimum, True)
    total = number(value.get('totalMs'))
    points = [number(value.get(key)) for key in ('p50', 'p95', 'maxMs')]
    if points != sorted(points) or total > calls * points[-1] or number(value.get('zeroMsCalls'), integer=True) > calls:
        raise ValueError('Invalid render cost distribution')
    if not math.isclose(number(value.get('meanMs')), total/calls, rel_tol=1e-5, abs_tol=1e-6):
        raise ValueError('Render mean differs')
    age = number(value.get('updateAgeCalls'), integer=True)
    age_min = number(value.get('minUpdateAgeCalls'), integer=True)
    age_max = number(value.get('maxUpdateAgeCalls'), integer=True)
    if age_min > age_max or not calls*age_min <= age <= calls*age_max:
        raise ValueError('Native updateAge counter distribution differs')


def verify(root, text, selection=None):
    options = (selection or {}).get('options', {})
    renderer = options.get('inventory_work_renderer')
    if 'inventory_work_renderer' in options and (renderer not in ('clean', 'vanilla')
            or selection.get('suite') != 'storage-profile' or selection.get('cases') != ['inventory-work']
            or selection.get('kind') != 'sp' or type(selection.get('clients', 1)) is not int
            or selection.get('clients', 1) != 1
            or any(options.get(key) for key in ('seed_run', 'world_template', 'startup_connection', 'mp_host'))):
        raise ValueError('Invalid renderer-specific inventory-work selection')
    modes = (renderer,) if renderer else ('clean', 'vanilla')
    specs = [(*spec, True) for spec in itertools.product((100, 10000), modes,
             ('collapsed-visible', 'collapsed-clipped', 'expanded-visible', 'expanded-clipped'))]
    specs += [(10000, mode, view, False) for mode, view in itertools.product(modes, ('collapsed-visible', 'collapsed-clipped'))]
    if '[STORAGE_PROFILE] FAIL' in text:
        raise ValueError('Native inventory-work fixture failed')
    events = [(kind, json.loads(body)) for kind, body in re.findall(r'\[STORAGE_PROFILE\] (WORK_\w+) (\{[^\n]+\})', text)]
    expected = ['WORK_SETUP']+['WORK_LOOKUP']*4+['WORK_FOOD']*len(specs)+['WORK_FRESHNESS']*len(modes)+['WORK_RESTORED']
    if [kind for kind, _ in events] != expected or text.count('[STORAGE_PROFILE] COMPLETE') != 1:
        raise ValueError('Missing, duplicate or reordered inventory-work evidence')
    setup = events[0][1]
    expected_setup = dict(native=True, clock='getTimestampMs', resolutionMs=1, spacers=60, foodType='Base.Apple',
                     lookupType='Base.Nails', phases=len(specs), physicalInput=False, fpsMeasurement=False,
                     renderClock='System.nanoTime', renderResolutionMs=0.000001,
                     nativeAgeMethod='Food.updateAge()', observer='scoped-entry-counter')
    if renderer:
        expected_setup['renderer'] = renderer
    if setup != expected_setup:
        raise ValueError('Native workload setup differs')
    lookups = [value for kind, value in events if kind == 'WORK_LOOKUP']
    if [row.get('case') for row in lookups] != ['missing', 'first-present', 'last-nested', 'empty-control']:
        raise ValueError('Lookup controls differ')
    for row in lookups:
        for key, value in dict(native=True, clock='getTimestampMs', resolutionMs=1, nestedObjects=4800,
                               rootObjects=2, recursiveObjects=4802, emptyObjects=0, batchCalls=512,
                               warmupBatches=2, measuredBatches=9, measuredCalls=4608, matchedCalls=4608,
                               objectsPreserved=True, fpsMeasurement=False, receiptLatencyMeasurement=False,
                               missingId=-2147483648).items():
            if type(row.get(key)) is not type(value) or row[key] != value:
                raise ValueError('Native lookup workload/identity guard differs')
        values = row.get('elapsedMs')
        if not isinstance(values, list) or len(values) != 9:
            raise ValueError('Missing raw lookup batches')
        for value in values: number(value, integer=True)
        ordered = sorted(values)
        for key, value in dict(totalElapsedMs=sum(values), minBatchMs=ordered[0], medianBatchMs=ordered[4],
                               p95BatchMs=ordered[-1], maxBatchMs=ordered[-1], zeroMsBatches=values.count(0)).items():
            if row.get(key) != value: raise ValueError('Lookup summary differs from raw timing')
        if not math.isclose(number(row.get('meanMsPerCall')), sum(values)/4608, rel_tol=1e-5, abs_tol=1e-8):
            raise ValueError('Lookup mean differs')
        for key in ('firstId', 'lastId', 'requestedId'): number(row.get(key), -2147483648, True)
        expected_id = row['firstId'] if row['case']=='first-present' else row['lastId'] if row['case']=='last-nested' else -2147483648
        if row['requestedId'] != expected_id or len({row['firstId'],row['lastId'],-2147483648}) != 3:
            raise ValueError('Lookup requested item differs')
    food = [value for kind, value in events if kind == 'WORK_FOOD']
    for index,(row,spec) in enumerate(zip(food,specs),1):
        if (row.get('index'), row.get('size'), row.get('mode'), row.get('view')) != (index,*spec[:3]):
            raise ValueError('Native food workload differs')
        if row.get('freshnessBar') is not spec[3] or row.get('freshnessPercentage') is not spec[3]:
            raise ValueError('Native freshness feature control differs')
        if row.get('native') is not True or row.get('groupObjects') != spec[0] or row.get('clockResolutionMs') != 0.000001:
            raise ValueError('Native food cardinality/clock differs')
        if (row.get('clock'), row.get('nativeAgeMethod'), row.get('observer')) != ('System.nanoTime', 'Food.updateAge()', 'scoped-entry-counter'):
            raise ValueError('Native renderer observer differs')
        expected_class = 'CleanUI_Clean_ISInventoryPane' if spec[1] == 'clean' else 'CleanUI_Vanilla_ISInventoryPane'
        if row.get('paneClass') != expected_class or row.get('rendererMatchesClass') is not True:
            raise ValueError('Selected native pane class/renderer differs')
        if not 3000 <= number(row.get('elapsedMs')) < 30000 or row.get('warmupMs') != 1500:
            raise ValueError('Food observation window differs')
        if (number(row.get('foodIcons'),integer=True)>0) != (spec[2].endswith('-visible')):
            raise ValueError('Actual native food visibility differs')
        number(row.get('groups'),40,True);number(row.get('rawItems'),spec[0]+60,True)
        number(row.get('width'),1);number(row.get('height'),1);number(row.get('scrollY'),-1000000)
        distribution(row['primary'],60)
        if row['dragged'] != {'calls':0}: distribution(row['dragged'])
        refresh = row.get('refresh',{})
        refresh_calls = number(refresh.get('calls'),integer=True)
        refresh_total = number(refresh.get('totalMs'),integer=True)
        if not refresh_calls and refresh_total:
            raise ValueError('Refresh cost without observed refresh calls')
    freshness = [value for kind,value in events if kind=='WORK_FRESHNESS']
    if [row.get('mode') for row in freshness] != list(modes):
        raise ValueError('Selected native pane freshness checks differ')
    for row in freshness:
        expected_class = 'CleanUI_Clean_ISInventoryPane' if row['mode'] == 'clean' else 'CleanUI_Vanilla_ISInventoryPane'
        if row.get('paneClass') != expected_class or row.get('rendererMatchesClass') is not True:
            raise ValueError('Freshness pane class/renderer differs')
        if row.get('unique') is not True or row.get('objects') != 10000 or row.get('tailGroup') != 1:
            raise ValueError('Tail food did not regroup uniquely')
        if number(row.get('ageAfter')) <= number(row.get('ageBefore')):
            raise ValueError('Freshness control did not change age')
    restored = events[-1][1]
    if any(restored.get(key) != value for key,value in dict(ownedRemoved=10060,foodRemoved=10000,observers=True,
                                                           mode=True,freshnessOptions=True,phases=len(specs),lookupObjectsPreserved=True).items()):
        raise ValueError('Owned objects/observers not restored')
    number(restored.get('originalItems'),integer=True)
    return {'lookup':lookups,'food':food,'freshness':freshness,'limits':[
        'Observational SP timings around actual Java lookups and selected native pane renderers; not an FPS/performance pass.',
        '1ms clock; raw lookup batches use512calls, interleaved controls,2warmup and9measured rounds.',
        'Renderer timings use System.nanoTime (nominal1ns units, not measured precision), are inclusive and grouped by real icon visibility; setup and1500ms warmup are excluded.',
        'Native Food.updateAge() entry counts are scoped to delegated renderdetails, separate primary/drag; boolean overload and background updates are excluded.',
        'Counter advice adds observer overhead per native updateAge entry; renderer times include counter and Lua/Java scope-boundary overhead; individual updateAge calls are not timed.',
        f'First{len(modes)*8}phases force both BC freshness options on; final{len(modes)*2}dense phases cover the selected panes with both options off without persisting config.',
        'Refresh counts/times cover calls during measurement only, including calls outside rendering; nested times are inclusive.',
        'No physical input, Host receipt latency/event ordering or original-user-save stutter claim.',
        'Freshness checks change a tail item age and require native regrouping in every selected pane; they do not establish time-to-regroup after natural expiry.',
        'Renderer-specific runs retain one mode through dense phases/freshness; default runs retain the full two-renderer20phase matrix.']}
