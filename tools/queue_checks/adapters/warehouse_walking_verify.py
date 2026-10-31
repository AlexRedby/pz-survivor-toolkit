"""Reject incomplete or mismatched walking captures; timings are not acceptance."""
import itertools
import hashlib
import zipfile
import json
import math
from pathlib import Path

from .. import receipts
from .warehouse_workload_verify import restored_ui, position

MARKER = '[WAREHOUSE_WALKING] '
EVENTS = {'READY', 'BASELINE_SEEN', 'BASELINES', 'NORMALIZED', 'BASELINE', 'SETUP', 'SEED', 'ADMIT', 'MODE', 'GO', 'INTERVAL',
          'AUTHORITY', 'SEEN', 'RELEASE', 'RESTORED', 'COMPLETE'}
INITIAL_EVENTS={'READY','BASELINE_SEEN','BASELINES','NORMALIZED','BASELINE'}
PHASES = list(itertools.product(('sparse', 'dense'), ('clean', 'vanilla'),
                              ('own-only', 'both-hidden', 'loot-collapsed', 'both-open')))


def ensure(value, message):
    if not value:
        raise ValueError('Warehouse walking: ' + message)


def require(row, **expected):
    ensure(type(row) is dict, 'missing object')
    for key, value in expected.items():
        ensure(type(row.get(key)) is type(value) and row[key] == value, 'guard differs: ' + key)


def number(value, low=0, high=None, integer=False):
    ensure(type(value) in (int, float) and math.isfinite(value), 'invalid number')
    ensure(not integer or type(value) is int, 'noninteger evidence')
    ensure(value >= low and (high is None or value <= high), 'numeric bound differs')
    return value


def ids(value, count=None):
    ensure(type(value) is list and (count is None or len(value) == count), 'ID count differs')
    ensure(all(type(item) is int for item in value) and value == sorted(set(value)), 'unordered/duplicate IDs')
    return value


def one(rows, name):
    selected = [row for event, row in rows if event == name]
    ensure(len(selected) == 1, 'expected one ' + name)
    return selected[0]


def records(text, kind, allowed_roles):
    result = {role: [] for role in allowed_roles}
    for line in text.splitlines():
        if MARKER not in line:
            continue
        name, separator, body = line.split(MARKER, 1)[1].partition(' ')
        ensure(name in EVENTS and separator and 0 < len(body) <= 524288, 'failed/unknown/malformed event')
        row = receipts.decode_object(body)
        require(row, suite='warehouse-walking', case='walk', kind=kind, mode='toolkit')
        if name in INITIAL_EVENTS:
            require(row,initialTransport='native-reliable-ordered-channel0' if kind=='mp' else 'in-process-shared-authority')
        if name=='SETUP':
            require(row,materializationTransport='native-reliable-ordered-channel1' if kind=='mp' else 'in-process-shared-authority')
        ensure(row.get('role') in result, 'unexpected native role')
        result[row['role']].append((name, row))
    return result


def context(row, token, index):
    density, pane, state = PHASES[index-1]
    require(row, token=token, index=index, phaseToken=token+':'+str(index),
            density=density, paneMode=pane, paneState=state)


def original_equipment(row, original_ids=None):
    require(row, primaryEmpty=True, secondaryEmpty=True, attachedCount=0)
    ensure(type(row.get('worn')) is list, 'missing original worn equipment descriptors')
    seen=set()
    for entry in row['worn']:
        ensure(type(entry) is dict and type(entry.get('id')) is int, 'invalid original worn identity')
        ensure(type(entry.get('location')) is str and 0<len(entry['location'])<256, 'invalid original worn slot')
        ensure(type(entry.get('fullType')) is str and 0<len(entry['fullType'])<256, 'invalid original worn fullType')
        ensure(entry['id'] not in seen, 'duplicate original worn identity'); seen.add(entry['id'])
    if original_ids is not None:
        ensure(seen <= set(original_ids), 'original worn descriptor aliases nonoriginal item')


def snapshot(row, phase, descriptors, originals, role):
    context(row, descriptors['token'], phase['index'])
    require(row, originals=True, identities=True, itemType='Base.Nails')
    ensure(type(row.get('crates')) is list and len(row['crates']) == 12, 'missing physical crates')
    all_ids = set()
    for slot, (crate, point, expected) in enumerate(zip(row['crates'], descriptors['crates'], phase['crateIds']), 1):
        require(crate, slot=slot, id=point['id'], capacity=100)
        ensure(ids(crate['itemIds'], phase['itemsPerCrate']) == expected, 'physical cohort changed')
        weight = number(crate['weight'], .001, 100)
        number(crate['effectiveCapacity'], weight, 100)
        ensure(not all_ids.intersection(expected), 'same item in two crates')
        all_ids.update(expected)
    loads = descriptors['actorLoads']
    visible = loads if role == 'server' else {role: loads[role]}
    ensure(row.get('rootIds') == {name: load['itemIds'] for name, load in visible.items()}, 'deterministic actor identities changed')
    ensure(set(row.get('actorLoads', {})) == set(visible), 'actor load projection differs')
    for name, load in visible.items():
        actual = row['actorLoads'][name]
        require(actual, itemType='Base.Nails', count=8, equipment='empty', originalsStashed=True)
        ensure(ids(actual['itemIds'], 8) == load['itemIds'] and actual['weight'] == load['weight'], 'actor composition/weight changed')
        ensure(not all_ids.intersection(actual['itemIds']), 'actor item aliases crate stock')
        all_ids.update(actual['itemIds'])
    for original in originals.values():
        ensure(not all_ids.intersection(original), 'owned item aliases original')


def readiness(proof, descriptors, roles, online_ids):
    ensure(type(proof) is dict and set(proof) == set(roles), 'missing authoritative position barrier')
    for role, row in proof.items():
        origin = descriptors['actorOrigins'][role]
        require(row, onlineId=online_ids[role], deadlineMs=15000)
        requested = number(row['requestedAt'])
        confirmed = number(row['confirmedAt'], requested)
        ensure(number(row['waitMs'], 0, 14999) == confirmed-requested, 'invalid readiness clock')
        for axis in ('x', 'y', 'z'):
            target = origin[axis] + (0 if axis == 'z' else .5)
            ensure(abs(number(row[axis], -100000) - target) <= .1, 'server actor not at route origin')
            ensure(row['square'+axis.upper()] == origin[axis], 'server actor square differs')


def view(rows, state):
    ensure(type(rows) is list and len(rows) == 2, 'missing actual window states')
    require(rows[0], visible=state != 'both-hidden', collapsed=False, paneVisible=True)
    require(rows[1], visible=state in ('both-open', 'loot-collapsed'),
            collapsed=state == 'loot-collapsed', paneVisible=True)
    for index, row in enumerate(rows):
        require(row, x=30 if index == 0 else 640, y=50, w=590, h=740)


def environment(row):
    require(row, width=1280, height=900, gameSpeed=1)
    for key in ('originX', 'originY', 'originZ'):
        number(row[key], -100000)
    number(row['actorRootItems'], integer=True)
    number(row['aggregateItems'], integer=True)


def restored_lock(proof):
    require(proof, restored=True, methodUnchanged=True)
    fields = {'isForceSelected': bool, 'forceSelectedType': str, '_ForceSwitchIntent': str,
              '_BrowseElapsedMs': (int, float), '_HasNearbyCorpses': bool}
    ensure(type(proof.get('globals')) is dict and set(proof['globals']) == set(fields), 'lock state fields differ')

    def value(row, expected_type):
        ensure(type(row) is dict and set(row) == {'expected', 'actual'}, 'lock restoration pair missing')
        for state in row.values():
            ensure(type(state) is dict and type(state.get('present')) is bool, 'lock state presence missing')
            ensure(set(state) == ({'present', 'value'} if state['present'] else {'present'}), 'lock state value differs')
            if state['present']:
                valid = type(state['value']) in expected_type if type(expected_type) is tuple else type(state['value']) is expected_type
                ensure(valid, 'lock state type differs')
                if type(expected_type) is tuple:
                    number(state['value'])
        ensure(row['expected'] == row['actual'], 'original lock state not restored')

    for field, expected_type in fields.items():
        value(proof['globals'][field], expected_type)
    ensure(type(proof.get('pages')) is list and len(proof['pages']) == 2, 'missing original page lock state')
    for page in proof['pages']:
        ensure(type(page) is dict and set(page) == {'tempForceSelectUnlock'}, 'page lock state fields differ')
        value(page['tempForceSelectUnlock'], bool)


def compiled_entries(path):
    try:
        with zipfile.ZipFile(path) as jar:
            names=jar.namelist(); ensure(len(names)==len(set(names)),'duplicate observer jar entry')
            return {name:hashlib.sha256(jar.read(name)).hexdigest() for name in names}
    except zipfile.BadZipFile as error:
        raise ValueError('Warehouse walking: malformed observer jar') from error


def verify(root, selection):
    root = Path(root)
    roles = ['client1'] if selection['kind'] == 'sp' else ['client1', 'client2']
    from . import warehouse_walking_profile as observer
    inputs = json.loads((root/'warehouse-walking-observer-inputs.json').read_text())
    require(inputs, test_only=True, observer_mod=observer.MOD_ID, callback_replacement=False,
            native_jvm_check=observer.PASS, ordered_jvm_check=observer.ORDERED_PASS, scope='registered-native-lua-calls', **observer.SCOPE_DETAILS)
    ensure(inputs.get('native_hashes') == observer.NATIVE_HASHES, 'observer native inputs differ')
    ensure(set(inputs.get('java_sources', {})) == observer.JAVA_SOURCES, 'observer sources missing')
    ensure(inputs.get('ordered_transport') == observer.ORDERED_TRANSPORT, 'native ordered transport differs')
    entries=inputs.get('java_entries', {})
    ensure(type(entries) is dict and {'toolkit/warehousewalking/Main.class','toolkit/warehousewalking/Profile.class','toolkit/warehousewalking/OrderedCommands.class'}<=set(entries),'compiled observer/ordered sender missing')
    ensure(all(type(key) is str and key.startswith('toolkit/warehousewalking/') and key.endswith('.class') and '/' not in key.removeprefix('toolkit/warehousewalking/') and 'Checks' not in key for key in entries),'compiled observer entry scope differs')
    native_roles=['server',*roles] if selection['kind']=='mp' else roles
    ensure(set(inputs.get('ordered_cache_markers', {}))==set(native_roles),'ordered sender owned cache cohort differs')
    for role in native_roles:
        marker=root/role/'Lua/warehouse-walking-ordered.txt'
        expected='PZWarehouseWalkingProfile/ordered-command-v1\n'+str((root/role).resolve())+'\n'+role+'\n'+entries['toolkit/warehousewalking/OrderedCommands.class']+'\n'
        ensure(marker.read_text()==expected and hashlib.sha256(marker.read_bytes()).hexdigest()==inputs['ordered_cache_markers'][role],'ordered sender owned cache marker differs')
        ensure(compiled_entries(root/role/('mods/'+observer.MOD_ID+'/42/media/java/'+observer.MOD_ID+'.jar'))==entries,'compiled observer jar entry fingerprints differ')
    for digest in [*inputs['java_sources'].values(), *entries.values(), *inputs['ordered_cache_markers'].values()]:
        ensure(type(digest) is str and len(digest) == 64 and set(digest) <= set('0123456789abcdef'), 'invalid observer source hash')
    ensure(set(inputs.get('client_properties', {})) == set(roles), 'observer client cohort differs')
    for role in roles:
        ensure(inputs['client_properties'][role] == {'pz.warehouseWalking.cache': str((root/role).resolve())},
               'observer not bound to owned client')
    grouped = {}
    for role in roles:
        allowed = [role, 'server'] if selection['kind'] == 'sp' else [role]
        grouped.update(records((root/(role+'-launch.log')).read_text(errors='replace'), selection['kind'], allowed))
    if selection['kind'] == 'mp':
        grouped.update(records((root/'server-launch.log').read_text(errors='replace'), 'mp', ['server']))
    server = grouped['server']
    setup = one(server, 'SETUP')
    descriptors = setup['ids']; token = descriptors['token']; originals = descriptors['originalRootIds']
    ensure(type(token) is str and 0 < len(token) < 256, 'invalid session token')
    ensure(set(originals) == set(roles) and set(setup['onlineIds']) == set(roles), 'wrong real-peer cohort')
    ensure(set(descriptors.get('originalEquipment', {})) == set(roles), 'missing correlated original equipment baselines')
    for equipment in descriptors['originalEquipment'].values():
        original_equipment(equipment)
    for role in roles:
        ids(originals[role]); number(setup['onlineIds'][role], -1, integer=True)
    ensure(set(descriptors.get('actorLoads', {})) == set(roles), 'missing deterministic actor descriptors')
    actor_ids = set()
    for role, load in descriptors['actorLoads'].items():
        require(load, token=token+':actor:'+role, itemType='Base.Nails', count=8, equipment='empty')
        cohort = ids(load['itemIds'], 8); number(load['weight'], .001)
        ensure(not actor_ids.intersection(cohort), 'actors share cohort IDs'); actor_ids.update(cohort)
        for original in originals.values():
            ensure(not set(cohort).intersection(original), 'actor cohort aliases originals')
    ensure(len({load['weight'] for load in descriptors['actorLoads'].values()}) == 1, 'actor weights differ')
    ensure(len(set(setup['onlineIds'].values())) == len(roles), 'peers share online ID')
    ensure(len(descriptors['crates']) == 12, 'wrong crate topology')
    origin = descriptors['origin']
    for axis in ('x', 'y', 'z'):
        number(origin[axis], -100000, integer=True)
    ensure(set(descriptors.get('actorOrigins', {})) == set(roles)
           and set(descriptors.get('routeOrigins', {})) == set(roles), 'missing distinct actor routes')
    for role in roles:
        lane_y = origin['y'] + (-2 if role == 'client1' else 2)
        ensure(descriptors['actorOrigins'][role] == dict(x=origin['x']-2, y=lane_y, z=origin['z']), 'different native route start')
        ensure(descriptors['routeOrigins'][role] == dict(x=origin['x'], y=lane_y, z=origin['z']), 'different native route origin')
    for slot, (point, (dx, dy)) in enumerate(zip(descriptors['crates'], itertools.product(range(-3, 3), (-1, 1))), 1):
        require(point, x=origin['x']+dx, y=origin['y']+dy, z=origin['z'], token=token+':'+str(slot), ci=0)
        number(point['index'], integer=True)
        require(point, object=point['index'], key=f"{point['x']},{point['y']},{point['z']}")
        require(point, id=point['key']+'/'+str(point['index'])+'/0')
    expected_server = ['READY'] + ['BASELINE_SEEN']*len(roles) + ['BASELINES'] + ['NORMALIZED']*len(roles) + ['SETUP']
    for _ in PHASES:
        expected_server += ['SEED', 'ADMIT'] + ['SEEN']*len(roles) + ['GO', 'AUTHORITY'] + ['SEEN']*len(roles) + ['RELEASE']
    expected_server += ['RESTORED', 'COMPLETE']
    ensure([name for name, _ in server] == expected_server, 'authority lifecycle/barrier order differs')
    for event,row in server:
        if event in ('READY','BASELINE_SEEN','BASELINES','NORMALIZED'):
            require(row,token=token,index=1)
    ready=one(server,'READY'); require(ready,token=token,index=1)
    ensure(ready['onlineIds']==setup['onlineIds'],'initial native peer readiness differs')
    baseline_seen=[row['observer'] for event,row in server if event=='BASELINE_SEEN']
    ensure(sorted(baseline_seen)==roles,'duplicate/missing initial baseline capture')
    captured=one(server,'BASELINES')
    ensure(captured['originalRootIds']==originals and captured['originalEquipment']==descriptors['originalEquipment'],'authority baseline capture differs')
    normalized={row['observer']:row for event,row in server if event=='NORMALIZED'}
    ensure(set(normalized)==set(roles),'missing native normalization acknowledgements')
    for row in normalized.values():
        require(row['proof'],rootEmpty=True,equipmentEmpty=True,originalsStashed=True)
    phases = {}
    for index in range(1, 17):
        rows = [(name, row) for name, row in server if name not in ('READY','BASELINE_SEEN','BASELINES','NORMALIZED','SETUP', 'RESTORED', 'COMPLETE') and row.get('index') == index]
        seed = one(rows, 'SEED'); phase = seed['phase']; context(phase, token, index)
        require(phase, itemType='Base.Nails', itemsPerCrate=1 if index <= 8 else 400)
        ensure(type(phase['crateIds']) is list and len(phase['crateIds']) == 12, 'seed lacks exact IDs')
        for expected in phase['crateIds']:
            ids(expected, phase['itemsPerCrate'])
        for _, row in rows:
            context(row, token, index)
        snapshot(seed['snapshot'], phase, descriptors, originals, 'server')
        readiness(seed['readiness'], descriptors, roles, setup['onlineIds'])
        admission = one(rows, 'ADMIT'); require(admission, stage='before')
        ensure(admission['snapshot'] == seed['snapshot'] and admission['readiness'] == seed['readiness'], 'authority admission changed')
        for stage in ('before', 'after'):
            observers = [row['observer'] for name, row in rows if name == 'SEEN' and row.get('stage') == stage]
            ensure(sorted(observers) == roles, 'missing/duplicate peer barrier')
        effect = one(rows, 'AUTHORITY')
        snapshot(effect['after'], phase, descriptors, originals, 'server')
        ensure(effect['before'] == seed['snapshot'] == effect['after'], 'authoritative static load changed')
        release = one(rows, 'RELEASE'); require(release, ownedRemaining=0)
        ensure(ids(release['removedIds'], 12*phase['itemsPerCrate']) == sorted(i for crate in phase['crateIds'] for i in crate), 'release removed wrong identities')
        ensure(release['originalRootIds'] == originals, 'release changed originals')
        phases[index] = (phase, seed['snapshot'], release)
    cleanup = one(server, 'RESTORED')
    require(cleanup, token=token, index=16, removedCrates=12, ownedAbsent=True, ownedRemaining=0,
            cleanupTransport='native-reliable-ordered-channel1' if selection['kind']=='mp' else 'in-process-shared-authority')
    ensure(cleanup['originalRootIds'] == originals and len(cleanup['crates']) == 12, 'cleanup cohort differs')
    ensure(cleanup.get('originalEquipment') == descriptors['originalEquipment'], 'authority original equipment slots/IDs not restored')
    ensure(set(cleanup.get('actorRestored', {})) == set(roles), 'missing authority actor restoration')
    for proof in cleanup['actorRestored'].values():
        require(proof, identity=True, payload=True, equipment=True)
    for before, after in zip(descriptors['crates'], cleanup['crates']):
        ensure(all(after.get(key) == value for key, value in before.items()), 'cleanup changed object identity')
        number(after['afterIndex'], -100000, -1, integer=True)
    require(one(server, 'COMPLETE'), token=token, phases=16, restored=True)
    evidence = {}
    for role in roles:
        rows = grouped[role]
        expected_client = ['BASELINE', 'NORMALIZED', 'SETUP'] + ['MODE', 'ADMIT', 'INTERVAL', 'ADMIT', 'RELEASE']*16 + ['RESTORED', 'COMPLETE']
        ensure([name for name, _ in rows] == expected_client, role+' incomplete client lifecycle')
        baseline = one(rows, 'BASELINE'); require(baseline,token=token,index=1); number(baseline['stableSamples'], 3, integer=True)
        require(baseline['original'], identity=True, payload=True, equipment=True)
        original_equipment(baseline['originalEquipment'], baseline['original']['ids'])
        ensure(baseline['originalEquipment'] == descriptors['originalEquipment'][role], 'authority baseline equipment differed before normalization')
        ensure(set(originals[role]) <= set(ids(baseline['original']['ids'])), 'baseline root missing')
        ensure(one(rows, 'SETUP')['ids'] == descriptors, 'client setup descriptors differ')
        require(one(rows,'NORMALIZED'),token=token,index=1)
        ensure(one(rows,'NORMALIZED')['proof']==normalized[role]['proof'],'native normalization proof/ack differs')
        intervals = []
        for index in range(1, 17):
            selected = [(name, row) for name, row in rows if name in ('MODE', 'ADMIT', 'INTERVAL', 'RELEASE') and row.get('index') == index]
            ensure([name for name, _ in selected] == ['MODE', 'ADMIT', 'INTERVAL', 'ADMIT', 'RELEASE'], 'client phase missing/out of order')
            phase, authority, release = phases[index]
            for _, row in selected:
                context(row, token, index)
            mode = selected[0][1]; position(mode['placement'])
            target = mode['placement']['target']
            ensure(all(target[axis] == descriptors['actorOrigins'][role][axis] + (0 if axis == 'z' else .5)
                       for axis in ('x', 'y', 'z')), 'client started another route')
            view(mode['paneStateProof'], phase['paneState'])
            before, interval, after = (selected[n][1] for n in (1, 2, 3))
            for stage, row in [('before', before), ('after', after)]:
                require(row, stage=stage)
                ensure(row['authority'] == authority, 'client authority projection changed')
                snapshot(row['snapshot'], phase, descriptors, originals, role)
            ensure(interval['before'] == before['snapshot'] == interval['after'] == after['snapshot'], 'client identities changed during interval')
            number(interval['warmupMs'], 2000)
            motion = interval['motion']; require(motion, sourceMethodsUnchanged=True, teleports=0,
                                                 uiIdentityUnchanged=True, actualPaneMode=phase['paneMode'],
                                                 manualAggregateLock=True, lockMethodUnchanged=True)
            number(motion['elapsedMs'], 12000, 60000)
            legs = number(motion['legs'], 4, integer=True)
            ensure(legs % 2 == 0 and motion['nativeActions'] == legs, 'route did not return through exact native actions')
            number(motion['distance'], 14); number(motion['tileChanges'], 12, integer=True)
            number(motion['movementTicks'], 30, integer=True)
            ticks = motion['tickIntervalsMs']
            samples = number(ticks['samples'], 30, 4096, integer=True)
            total = number(ticks['totalSamples'], samples, integer=True)
            ensure(samples == min(total, 4096) and total >= motion['movementTicks'], 'tick sampling cohort differs')
            p50, p95, maximum = (number(ticks[key], 0, motion['elapsedMs']) for key in ('p50', 'p95', 'max'))
            ensure(p50 <= p95 <= maximum, 'tick interval quantiles differ')
            view(interval['beforeState'], phase['paneState']); view(interval['afterState'], phase['paneState'])
            for key in ('environmentInitial', 'environmentFinal'):
                environment(interval[key])
                ensure(interval[key]['language'] == ('RU' if role == 'client2' else 'EN'), 'client locale differs')
                ensure(interval[key]['actorRootItems'] == 8, 'environment deterministic root count differs')
                require(interval[key], actorWornItems=0, actorPrimaryEmpty=True, actorSecondaryEmpty=True)
                ensure(abs(number(interval[key]['actorRootWeight'], .001)-descriptors['actorLoads'][role]['weight']) < .000001, 'environment actor weight differs')
                ensure(interval[key]['aggregateItems'] == 3*phase['itemsPerCrate'], 'nearby aggregate workload differs')
                ensure(all(interval[key]['origin'+axis.upper()] == descriptors['routeOrigins'][role][axis]
                           for axis in ('x', 'y', 'z')), 'environment route differs')
            observer.verify_profile(interval['profile'], index)
            ensure(abs(interval['profile']['elapsed_ms']-motion['elapsedMs']) <= 100,
                   'observer and walking intervals differ')
            client_release = selected[4][1]
            require(client_release, absent=True)
            ensure(client_release['receipt'] == release and client_release['originalStash'] == baseline['original'] and client_release['actorLoad'] == before['snapshot']['actorLoads'][role], 'client release differs')
            intervals.append(interval)
        restored = one(rows, 'RESTORED'); require(restored, ownedAbsent=True)
        ensure(restored['authority'] == cleanup and restored['original'] == baseline['original'], 'final client originals/cleanup differ')
        ensure(restored.get('originalEquipment') == baseline['originalEquipment'], 'final client worn slots/IDs not restored')
        ensure(cleanup['actorRestored'][role] == baseline['original'], 'authority originals differ from client baseline')
        restored_ui(restored['uiProof']); position(restored['positionProof'], baseline['position'])
        restored_lock(restored['lockProof'])
        require(one(rows, 'COMPLETE'), token=token, phases=16, restored=True)
        evidence[role] = intervals
    return {'phases': evidence, 'capture_only': True,
            'limits': ['Instrumented native Lua spans include observer overhead.',
                       'No FPS, WAN, user-save or optimization acceptance claim.']}
