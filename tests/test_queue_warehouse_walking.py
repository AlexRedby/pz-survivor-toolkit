"""Synthetic authority/replica receipts validate rejection gates, not game speed."""
import copy
import json
import hashlib
import zipfile
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from queue_checks import adapters
from queue_checks.adapters import warehouse_walking as A, warehouse_walking_verify as V
from queue_checks.adapters.warehouse_walking_profile import SCOPE_DETAILS
from queue_checks.adapters import warehouse_walking_profile as observer
from tests.test_queue_warehouse_workload import fixture as peer_fixture


def selection(kind='mp'):
    return dict(suite=A.SUITE, cases=['walk'], kind=kind, mode='toolkit',
                clients=2 if kind == 'mp' else 1, languages=['EN', 'RU'] if kind == 'mp' else ['EN'],
                mods=A.MODS, resources={'exclusive': True},
                options=dict(pack_lock='/pack.json', **({'mp_host': True} if kind == 'mp' else {})))


def profile(index):
    names = ('page.refreshBackpacks', 'pane.refreshContainer', 'pane.restoreSelection', 'pane.itemSortFunc',
             'rows.captureAnchor', 'filter.active', 'categoryRules.get', 'categories.get',
             'tags.forItem', 'tags.automaticForItem', 'tags.signature', 'retention.isRetained',
             'categoryGroups.split', 'recipeCatalog.newContext')
    return dict(SCOPE_DETAILS, index=index, phase=index, elapsed_ms=13000, clock='nanoTime', scope='registered-native-lua-calls',
                identities_unchanged=True, observer_overhead_included=True, hooks=dict(init=100, shrink=100),
                allocation=dict(available=False, scope='owner-thread-whole-interval', includes_observer=True),
                metrics=[dict(name=name, aliases=[name], source=name+'.lua', first_line=1, calls=20,
                              inclusive_ms=20, exclusive_ms=10, max_ms=2) for name in names])


def lock_proof():
    def missing(): return dict(expected={'present': False}, actual={'present': False})
    return dict(restored=True, methodUnchanged=True,
                globals={name: missing() for name in ('isForceSelected', 'forceSelectedType', '_ForceSwitchIntent',
                                                      '_BrowseElapsedMs', '_HasNearbyCorpses')},
                pages=[{'tempForceSelectUnlock': missing()} for _ in range(2)])


def fixture(kind='mp'):
    roles = ['client1', 'client2'] if kind == 'mp' else ['client1']
    rows = {role: [] for role in ['server', *roles]}
    token = 'warehouse-walking-check'; originals = {role: [70+i] for i, role in enumerate(roles)}
    origin = dict(x=12, y=20, z=0)
    crates = [dict(x=12+dx, y=20+dy, z=0, index=1, object=1, ci=0, key=f'{12+dx},{20+dy},0',
                   id=f'{12+dx},{20+dy},0/1/0', token=f'{token}:{n}')
              for n, (dx, dy) in enumerate(V.itertools.product(range(-3, 3), (-1, 1)), 1)]
    actor_origins = {role: dict(x=10, y=18 if role == 'client1' else 22, z=0) for role in roles}
    route_origins = {role: dict(point, x=12) for role, point in actor_origins.items()}
    actor_loads = {role: dict(token=token+':actor:'+role, itemIds=list(range(200+i*8,208+i*8)),
                             itemType='Base.Nails',count=8,weight=.4,equipment='empty') for i,role in enumerate(roles)}
    measured_loads = {role: {**{k:v for k,v in load.items() if k != 'token'}, 'originalsStashed':True} for role,load in actor_loads.items()}
    equipment = {role: dict(primaryEmpty=True,secondaryEmpty=True,attachedCount=0,
                           worn=[dict(location='base:Shirt',id=originals[role][0],fullType='Base.Shirt_FormalWhite')]) for role in roles}
    descriptors = dict(originalEquipment=equipment,actorLoads=actor_loads, token=token, crates=crates, origin=origin, actorOrigins=actor_origins,
                       routeOrigins=route_origins, originalRootIds=originals)
    online = {role: i for i, role in enumerate(roles)}
    old = peer_fixture()
    restoration = {role: copy.deepcopy(next(row for event, row in old[role] if event == 'RESTORED')) for role in roles}
    baselines = {role: dict(ids=originals[role], identity=True, payload=True, equipment=True) for role in roles}
    def emit(role, event, row):
        value = dict(suite=A.SUITE, case='walk', kind=kind, mode='toolkit', role=role, token=token, **row)
        if event in V.INITIAL_EVENTS:value['initialTransport']='native-reliable-ordered-channel0' if kind=='mp' else 'in-process-shared-authority'
        if event=='SETUP':value['materializationTransport']='native-reliable-ordered-channel1' if kind=='mp' else 'in-process-shared-authority'
        rows[role].append((event, value)); return value
    emit('server','READY',dict(index=1,onlineIds=online))
    for role in roles:emit('server','BASELINE_SEEN',dict(index=1,observer=role))
    emit('server','BASELINES',dict(index=1,originalRootIds=originals,originalEquipment=equipment))
    proof=dict(rootEmpty=True,equipmentEmpty=True,originalsStashed=True)
    for role in roles:emit('server','NORMALIZED',dict(index=1,observer=role,proof=proof))
    emit('server', 'SETUP', dict(ids=descriptors, onlineIds=online))
    for role in roles:
        emit(role, 'BASELINE', dict(index=1,original=baselines[role], originalEquipment=equipment[role], position=restoration[role]['positionProof']['target'], stableSamples=3))
        emit(role,'NORMALIZED',dict(index=1,proof=proof))
        emit(role, 'SETUP', dict(ids=descriptors))
    for index, (density, pane, state) in enumerate(V.PHASES, 1):
        ctx = dict(index=index, phaseToken=f'{token}:{index}', density=density, paneMode=pane, paneState=state)
        count = 1 if density == 'sparse' else 400
        cohort = [list(range(index*10000+i*count, index*10000+(i+1)*count)) for i in range(12)]
        phase = dict(ctx, token=token, itemType='Base.Nails', itemsPerCrate=count, crateIds=cohort)
        def snapshot(role):
            return dict(ctx, token=token, originals=True, identities=True, itemType='Base.Nails',
                        rootIds={name:load['itemIds'] for name,load in actor_loads.items() if role=='server' or role==name},
                        actorLoads=measured_loads if role=='server' else {role:measured_loads[role]},
                        crates=[dict(slot=i, id=point['id'], capacity=100, effectiveCapacity=100,
                                     weight=.05*count, itemIds=cohort[i-1]) for i, point in enumerate(crates, 1)])
        authority = snapshot('server')
        ready = {role: dict(requestedAt=100, confirmedAt=200, waitMs=100, deadlineMs=15000, onlineId=online[role],
                            x=10.5, y=point['y']+.5, z=0, squareX=10, squareY=point['y'], squareZ=0)
                 for role, point in actor_origins.items()}
        emit('server', 'SEED', dict(ctx, phase=phase, snapshot=authority, readiness=ready))
        emit('server', 'ADMIT', dict(ctx, stage='before', snapshot=authority, readiness=ready))
        for role in roles: emit('server', 'SEEN', dict(ctx, observer=role, stage='before'))
        emit('server', 'GO', ctx)
        emit('server', 'AUTHORITY', dict(ctx, before=authority, after=authority))
        for role in roles: emit('server', 'SEEN', dict(ctx, observer=role, stage='after'))
        release = emit('server', 'RELEASE', dict(ctx, removedIds=sum(cohort, []), ownedRemaining=0, originalRootIds=originals))
        view = [dict(visible=state != 'both-hidden', collapsed=False, paneVisible=True, x=30, y=50, w=590, h=740),
                dict(visible=state in ('both-open', 'loot-collapsed'), collapsed=state == 'loot-collapsed', paneVisible=True,
                     x=640, y=50, w=590, h=740)]
        for role in roles:
            native = snapshot(role)
            placed = copy.deepcopy(restoration[role]['positionProof'])
            for part in ('target', 'actual'):
                placed[part].update(y=actor_origins[role]['y']+.5, squareY=actor_origins[role]['y'])
            placed['actual']['currentSquareY'] = actor_origins[role]['y']
            emit(role, 'MODE', dict(ctx, placement=placed, paneStateProof=view))
            emit(role, 'ADMIT', dict(ctx, stage='before', snapshot=native, authority=authority))
            env = dict(width=1280, height=900, gameSpeed=1, language='RU' if role == 'client2' else 'EN',
                       originX=12, originY=route_origins[role]['y'], originZ=0, actorRootItems=8, actorRootWeight=.4, actorWornItems=0, actorPrimaryEmpty=True, actorSecondaryEmpty=True, aggregateItems=3*count)
            motion = dict(elapsedMs=13000, legs=6, nativeActions=6, distance=24, tileChanges=24, movementTicks=700,
                          sourceMethodsUnchanged=True, uiIdentityUnchanged=True, actualPaneMode=pane, teleports=0,
                          manualAggregateLock=True, lockMethodUnchanged=True,
                          tickIntervalsMs=dict(samples=700, totalSamples=700,p50=17,p95=20,max=40))
            emit(role, 'INTERVAL', dict(ctx, before=native, after=native, beforeState=view, afterState=view,
                                       environmentInitial=env, environmentFinal=env, motion=motion, profile=profile(index), warmupMs=2000))
            emit(role, 'ADMIT', dict(ctx, stage='after', snapshot=native, authority=authority))
            emit(role, 'RELEASE', dict(ctx, receipt=release, absent=True, originalStash=baselines[role],actorLoad=measured_loads[role]))
    cleanup = emit('server', 'RESTORED', dict(cleanupTransport='native-reliable-ordered-channel1' if kind=='mp' else 'in-process-shared-authority',index=16, removedCrates=12, ownedAbsent=True, ownedRemaining=0,
                       originalRootIds=originals, originalEquipment=equipment, actorRestored=baselines, crates=[dict(point, afterIndex=-1) for point in crates]))
    emit('server', 'COMPLETE', dict(phases=16, restored=True))
    for role in roles:
        emit(role, 'RESTORED', dict(original=baselines[role], originalEquipment=equipment[role], uiProof=restoration[role]['uiProof'],
                                  positionProof=restoration[role]['positionProof'], ownedAbsent=True, authority=cleanup,
                                  lockProof=lock_proof()))
        emit(role, 'COMPLETE', dict(phases=16, restored=True))
    return rows


class WarehouseWalkingTests(unittest.TestCase):
    def result(self, rows, kind='mp'):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            roles = ['client1'] if kind == 'sp' else ['client1', 'client2']
            inputs = dict(SCOPE_DETAILS, test_only=True, observer_mod=observer.MOD_ID, callback_replacement=False,
                          native_jvm_check=observer.PASS, ordered_jvm_check=observer.ORDERED_PASS, scope='registered-native-lua-calls', native_hashes=observer.NATIVE_HASHES,
                          java_sources={name:'a'*64 for name in observer.JAVA_SOURCES},
                          ordered_transport=observer.ORDERED_TRANSPORT,ordered_cache_markers={},java_entries={},
                          client_properties={role:{'pz.warehouseWalking.cache':str((root/role).resolve())} for role in roles})
            classes={name:b'fixture-class-bytes:'+name.encode() for name in ('Main','Profile','OrderedCommands')}
            inputs['java_entries']={'toolkit/warehousewalking/'+name+'.class':hashlib.sha256(content).hexdigest() for name,content in classes.items()}
            for role in (['server',*roles] if kind=='mp' else roles):
                marker=root/role/'Lua/warehouse-walking-ordered.txt';marker.parent.mkdir(parents=True)
                text='PZWarehouseWalkingProfile/ordered-command-v1\n'+str((root/role).resolve())+'\n'+role+'\n'+inputs['java_entries']['toolkit/warehousewalking/OrderedCommands.class']+'\n'
                marker.write_text(text);inputs['ordered_cache_markers'][role]=hashlib.sha256(marker.read_bytes()).hexdigest()
                jar=root/role/('mods/'+observer.MOD_ID+'/42/media/java/'+observer.MOD_ID+'.jar');jar.parent.mkdir(parents=True)
                with zipfile.ZipFile(jar,'w') as output:
                    for name,content in classes.items():output.writestr('toolkit/warehousewalking/'+name+'.class',content)
            (root/'warehouse-walking-observer-inputs.json').write_text(json.dumps(inputs))
            for role, values in rows.items():
                if kind == 'sp' and role == 'server': continue
                if kind == 'sp': values = [*rows['server'], *values]
                (root/(role+'-launch.log')).write_text('\n'.join(A.MARKER+event+' '+json.dumps(row) for event,row in values))
            return A.verify(root, selection(kind), {})

    def test_matched_sp_host_are_captures_not_performance_passes(self):
        for kind in ('sp', 'mp'):
            with self.subTest(kind=kind):
                result = self.result(fixture(kind), kind)
                self.assertEqual(result['issues'], [])
                self.assertTrue(all(row['status'] == 'captured' for row in result['outcomes']))

    def test_runner_completion_uses_restored_client_not_local_sp_authority(self):
        for kind in ('sp', 'mp'):
            rows = fixture(kind)
            for role in ('client1',) if kind == 'sp' else ('client1', 'client2'):
                def log(values):
                    return '\n'.join(A.MARKER + event + ' ' + json.dumps(row) for event, row in values)
                authority = rows['server'] if kind == 'sp' else []
                completed = [*authority, *rows[role]]
                with self.subTest(kind=kind, role=role):
                    self.assertTrue(A.complete(selection(kind), role, log(completed)))
                    self.assertFalse(A.complete(selection(kind), role, log(completed[:-1])))
                    self.assertFalse(A.complete(selection(kind), role, log([*completed, completed[-1]])))
                    self.assertFalse(A.complete(selection(kind), role, log(completed) + '\n' + A.MARKER + 'FAIL {}'))
                    self.assertFalse(A.complete(selection(kind), 'server', log(completed)))

    def test_exclusive_source_locked_topology_is_required(self):
        self.assertIs(adapters.get(A.SUITE), A)
        for change in ({'resources': {}}, {'clients': True}, {'clients': 1}, {'languages': ['EN']},
                       {'options': {'mp_host': True}}, {'options': {'mp_host': True, 'pack_lock': 'p', 'seed_run': 's'}},
                       {'mode': 'native'}, {'mods': A.MODS[:-1]}):
            with self.subTest(change=change), self.assertRaises(ValueError): A.validate(dict(selection(), **change))

    def test_startup_has_one_owner_and_all_observer_sources_are_tracked(self):
        for kind in ('sp', 'mp'):
            with tempfile.TemporaryDirectory() as folder, patch('queue_checks.adapters.warehouse_walking_profile.stage') as observer:
                runtime = {'roles': {role: {'cache': str(Path(folder)/role)} for role in (['client1'] if kind == 'sp' else ['server','client1','client2'])}}
                A.stage(ROOT, Path(folder), None, None, selection(kind), {}, runtime)
                observer.assert_called_once()
                for value in runtime['roles'].values():
                    lua = Path(value['cache'])/'mods/ActionQueueTest/42/media/lua'
                    self.assertEqual((lua/'client/ZZStartup.lua').exists(), kind == 'mp')
                    self.assertTrue((lua/'client/WarehouseWorkloadUI.lua').is_file())
                self.assertIn(Path(V.__file__), A.sources(ROOT, selection(kind)))

    def test_missing_peer_and_replayed_barrier_fail(self):
        for mutate in (lambda rows: rows['client2'].clear(),
                       lambda rows: rows['server'].insert(4, copy.deepcopy(rows['server'][4])),
                       lambda rows: rows['client1'].pop(4)):
            rows = fixture(); mutate(rows)
            self.assertTrue(self.result(rows)['issues'])

    def test_shared_lane_and_different_nearby_load_are_rejected(self):
        rows = fixture()
        descriptors = V.one(rows['server'], 'SETUP')['ids']
        descriptors['actorOrigins']['client2'] = descriptors['actorOrigins']['client1']
        self.assertTrue(self.result(rows)['issues'])
        rows = fixture()
        interval = next(row for event, row in rows['client1'] if event == 'INTERVAL')
        interval['environmentFinal']['aggregateItems'] = 6
        self.assertTrue(self.result(rows)['issues'])

    def test_static_membership_and_capacity_cannot_be_relaxed(self):
        rows = fixture(); setup=V.one(rows['server'],'SETUP'); seed=next(row for event,row in rows['server'] if event=='SEED')
        for mutate in (lambda row: row['crates'][0]['itemIds'].clear(),
                       lambda row: row['crates'][0].update(capacity=10000),
                       lambda row: row['crates'][0].update(weight=101),
                       lambda row: row.update(rootIds={}),
                       lambda row: row.update(identities=False)):
            bad=copy.deepcopy(seed['snapshot']);mutate(bad)
            with self.assertRaises(ValueError): V.snapshot(bad,seed['phase'],setup['ids'],setup['ids']['originalRootIds'],'server')

    def test_actor_composition_weight_equipment_and_restore_are_required(self):
        for mutate in (lambda load: load.update(count=7),
                       lambda load: load.update(itemType='Base.Bandage'),
                       lambda load: load.update(weight=.5),
                       lambda load: load.update(equipment='worn'),
                       lambda load: load.update(originalsStashed=False),
                       lambda load: load['itemIds'].pop()):
            rows = fixture(); seed = next(row for event,row in rows['server'] if event=='SEED')
            changed = copy.deepcopy(seed['snapshot']); mutate(changed['actorLoads']['client1'])
            with self.assertRaises(ValueError):
                V.snapshot(changed, seed['phase'], V.one(rows['server'],'SETUP')['ids'],
                           V.one(rows['server'],'SETUP')['ids']['originalRootIds'], 'server')
        rows=fixture(); V.one(rows['server'],'RESTORED')['actorRestored']={}
        self.assertTrue(self.result(rows)['issues'])
        rows=fixture(); interval=next(row for event,row in rows['client1'] if event=='INTERVAL')
        interval['environmentFinal']['actorWornItems']=1
        self.assertTrue(self.result(rows)['issues'])

    def test_original_equipment_requires_correlated_slots_and_ids(self):
        for mutate in (lambda rows: V.one(rows['server'],'SETUP')['ids'].pop('originalEquipment'),
                       lambda rows: V.one(rows['client1'],'BASELINE').update(originalEquipment=dict(primaryEmpty=True,secondaryEmpty=True,attachedCount=0,worn=[])),
                       lambda rows: V.one(rows['client1'],'RESTORED').update(originalEquipment=dict(primaryEmpty=True,secondaryEmpty=True,attachedCount=0,worn=[])),
                       lambda rows: V.one(rows['server'],'RESTORED').update(originalEquipment={})):
            rows=fixture();mutate(rows);self.assertTrue(self.result(rows)['issues'])
        original_equipment = dict(primaryEmpty=True,secondaryEmpty=True,attachedCount=0,
                                  worn=[dict(location='base:Shirt',id=1,fullType='Base.Shirt_FormalWhite')])
        V.original_equipment(original_equipment, [1])
        for key,value in [('primaryEmpty',False),('secondaryEmpty',False),('attachedCount',1)]:
            bad=copy.deepcopy(original_equipment);bad[key]=value
            with self.assertRaises(ValueError):V.original_equipment(bad,[1])
        with self.assertRaises(ValueError):V.original_equipment(original_equipment,[2])

    def test_initial_native_barriers_are_complete_and_token_bound(self):
        for mutate in (lambda rows: rows['server'].pop(0),
                       lambda rows: rows['server'].insert(2,copy.deepcopy(rows['server'][1])),
                       lambda rows: V.one(rows['server'],'BASELINES').update(token='foreign'),
                       lambda rows: V.one(rows['client1'],'NORMALIZED')['proof'].update(rootEmpty=False),
                       lambda rows: V.one(rows['client1'],'BASELINE').update(token='foreign'),
                       lambda rows: V.one(rows['server'],'READY').update(initialTransport='unordered'),
                       lambda rows: V.one(rows['client1'],'NORMALIZED').pop('initialTransport'),
                       lambda rows: V.one(rows['server'],'RESTORED').pop('cleanupTransport'),
                       lambda rows: V.one(rows['client1'],'SETUP').update(materializationTransport='native-reliable-ordered-channel0'),
                       lambda rows: V.one(rows['server'],'RESTORED').update(cleanupTransport='native-reliable-ordered-channel0')):
            rows=fixture();mutate(rows);self.assertTrue(self.result(rows)['issues'])

    def test_motion_and_ui_drift_cannot_pass(self):
        for mutate in (lambda row: row['motion'].update(teleports=1),
                       lambda row: row['motion'].update(legs=0),
                       lambda row: row['motion'].update(sourceMethodsUnchanged=False),
                       lambda row: row['motion'].update(manualAggregateLock=False),
                       lambda row: row['motion'].update(lockMethodUnchanged=False),
                       lambda row: row['afterState'][1].update(visible=True)):
            rows=fixture();interval=next(row for event,row in rows['client1'] if event=='INTERVAL')
            # Avoid changing shared synthetic baselines along with the observation.
            replacement=copy.deepcopy(interval);mutate(replacement)
            rows['client1']=[(event,replacement if row is interval else row) for event,row in rows['client1']]
            self.assertTrue(self.result(rows)['issues'])

    def test_original_lock_slots_require_exact_presence_value_and_method(self):
        V.restored_lock(lock_proof())
        for mutate in (lambda p: p.update(methodUnchanged=False),
                       lambda p: p['globals'].pop('_HasNearbyCorpses'),
                       lambda p: p['globals']['isForceSelected'].update(actual={'present': True, 'value': True}),
                       lambda p: p['pages'][1]['tempForceSelectUnlock'].update(actual={'present': True, 'value': False}),
                       lambda p: p['globals']['_BrowseElapsedMs'].update(expected={'present': True, 'value': True}, actual={'present': True, 'value': True})):
            proof = lock_proof(); mutate(proof)
            with self.assertRaises(ValueError): V.restored_lock(proof)
        proof = lock_proof()
        proof['globals']['_BrowseElapsedMs'] = dict(expected={'present': True, 'value': 123.5}, actual={'present': True, 'value': 123.5})
        V.restored_lock(proof)


if __name__ == '__main__': unittest.main()
