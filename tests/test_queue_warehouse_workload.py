"""Synthetic receipts exercise rejection paths; they never establish a game pass."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import adapters
from queue_checks.adapters import warehouse_workload as A
from queue_checks.adapters import warehouse_workload_verify as V


def selection():
    return dict(suite=A.SUITE, cases=['peer-edits'], kind='mp', mode='toolkit', clients=2,
                languages=['EN', 'RU'], mods=A.MODS, options={'mp_host': True})


def fixture():
    token = 'workload-session'
    originals = {'client1': [77], 'client2': [88]}
    crates = [dict(x=10+i, y=20, z=0, index=1, object=1, ci=0, key=f'{10+i},20,0',
                   id=f'{10+i},20,0/1/0', token=token+':'+str(i)) for i in range(1, 13)]
    descriptors = dict(token=token, crates=crates, originalRootIds=originals,
                       origin=dict(x=12,y=20,z=0), actorOrigin=dict(x=10,y=20,z=0), walkTarget=dict(x=9,y=20,z=0))
    rows = {role: [] for role in ('server', 'client1', 'client2')}
    def emit(role, event, row):
        rows[role].append((event, dict(suite=A.SUITE, case='peer-edits', kind='mp', mode='toolkit', role=role, token=token, **copy.deepcopy(row))))
    def position(x=10.5):
        point=dict(x=x,y=20.5,z=0,squareX=int(x),squareY=20,squareZ=0)
        return dict(target=point,actual=dict(point,currentSquareX=int(x),currentSquareY=20,currentSquareZ=0,
                     moving=False,hasPath=False,deferredX=0,deferredY=0),elapsedMs=200,lifecycleElapsedMs=800,
                     deadlineMs=15000,singlePlacement=True,quiescence=dict(stableMs=600,minimumStableMs=500,samples=10))
    def snapshot(phase, places, role):
        meta={item['id']:item for item in phase['items']} if phase else {}
        roots=('client1','client2') if role=='server' else (role,)
        visible={key:where for key,where in places.items() if role=='server' or where==role or where.startswith('crate')}
        return dict(token=token,index=phase['index'] if phase else 0,phaseToken=phase['phaseToken'] if phase else None,
                    visibility='both-roots' if role=='server' else role,
                    items=[dict(id=key,ft=meta[key]['ft'],endpoint=where,count=1,key=meta[key]['key'],cat=meta[key]['cat']) for key,where in visible.items()],
                    rootIds={actor:originals[actor]+[key for key,where in places.items() if where==actor] for actor in roots},
                    crates=[dict(slot=i,id=desc['id'],capacity=100,effectiveCapacity=100,
                                 weight=.05*sum(where=='crate'+str(i) for where in places.values()),
                                 itemIds=[key for key,where in places.items() if where=='crate'+str(i)]) for i,desc in enumerate(crates,1)])
    emit('server','SETUP',dict(ids=descriptors,onlineIds=dict(client1=0,client2=1)))
    baseline={role:dict(ids=originals[role],identity=True,payload=True,equipment=True) for role in ('client1','client2')}
    for role in ('client1','client2'):
        emit(role,'BASELINE',dict(original=baseline[role],position=position()['target'],stableSamples=3))
        emit(role,'SETUP',dict(ids=descriptors))
    for index,mode in enumerate(('clean','vanilla'),1):
        offset=index*100
        items=[]
        for i in range(1,15):
            ft='Base.Bandage' if i in (3,13) else 'Base.HotdogPack' if i==4 else 'Base.Nails'
            name='Warehouse old bandage' if i==3 else 'Warehouse new bandage' if i==13 else None
            items.append(dict(id=offset+i,ft=ft,name=name,key=ft+':'+str(name),cat='Material',
                              initialEndpoint='crate'+str(i) if i<=12 else 'client2' if i==13 else 'client1'))
        phase=dict(token=token,index=index,mode=mode,phaseToken=token+':'+str(index),items=items,outputIds=[],
                   recipe='OpenHotdogPack',outputType='Base.Hotdog_single',outputCount=4,transferId=offset+1,
                   replacementSourceId=offset+3,replacementId=offset+13,craftInputId=offset+4,quickId=offset+5,quickMatchId=offset+14)
        context=dict(index=index,paneMode=mode,phaseToken=phase['phaseToken'])
        places={item['id']:item['initialEndpoint'] for item in items}
        readiness={role:dict(requestedAt=1000,confirmedAt=1100,waitMs=100,deadlineMs=15000,onlineId=i,
                             x=10.5,y=20.5,z=0,squareX=10,squareY=20,squareZ=0) for i,role in enumerate(('client1','client2'))}
        emit('server','SEED',dict(context,phase=phase,snapshot=snapshot(phase,places,'server'),readiness=readiness))
        records={role:[] for role in ('client1','client2')}
        for role in ('client1','client2'):
            emit(role,'MODE',dict(context,placement=position()))
        for step in V.STEPS:
            current=dict(context,step=step)
            actor='client1' if step=='hidden-loot' else 'client2'
            transfers=[]
            if step=='peer-transfer':
                places[offset+1]='crate2'
                transfers=[(offset+1,'crate1','client2'),(offset+1,'client2','crate2')]
            elif step=='peer-replace':
                places[offset+3]='client2';places[offset+13]='crate3'
                transfers=[(offset+3,'crate3','client2'),(offset+13,'client2','crate3')]
            elif step=='peer-craft':
                del places[offset+4]
                for n in range(15,19):
                    phase['items'].append(dict(id=offset+n,ft='Base.Hotdog_single',name=None,key='Base.Hotdog_single:None',cat='Material',initialEndpoint='client2'))
                    phase['outputIds'].append(offset+n);places[offset+n]='client2'
                transfers=[(offset+4,'crate4','client2')]
            elif step=='hidden-loot':
                places[offset+5]='client1';transfers=[(offset+5,'crate5','client1')]
            authority=snapshot(phase,places,'server')
            if step!='initial':
                emit('server','GO',dict(current,actor=actor))
                emit('server','AUTHORITY',dict(current,phase=phase,snapshot=authority))
                records[actor]+=[dict(type='ISInventoryTransferAction',step=step,id=key,source=src,destination=dst,
                                      duration=-1,progressSamples=0,sourceMethodsUnchanged=True) for key,src,dst in transfers]
                extra={}
                if step=='peer-craft':
                    records[actor].append(dict(type='ISHandcraftAction',step=step,recipe='OpenHotdogPack',duration=75,
                                              started=True,progressSamples=5,sourceMethodsUnchanged=True))
                    extra['craftDispatch']=dict(recipe='OpenHotdogPack',inputId=offset+4,source='crate4',nativeMaterials=True,
                                                outputType='Base.Hotdog_single',outputCount=4,recipeTime=15,nativeDuration=75)
                if step=='hidden-loot':
                    extra['quick']=dict(installedButton=True,hiddenBefore=True,hiddenAfter=True,id=offset+5,source='crate5',destination='client1',
                                        callback='ISInventoryPage.onTransferByNameClick' if mode=='clean' else 'ISInventoryPage.lootAll')
                emit(actor,'ACTIONS',dict(current,records=records[actor],**extra))
            for role in ('client1','client2'):
                hidden=dict(visible=False,rowsPending=True,countPending=True,tooltipsPending=True,nativeBuilds=2)
                walker=dict(progress=True,returned=True,target=descriptors['walkTarget'],from_=None)
                walker['from']=position()['target'];walker['reached']=position(9.5)['actual'];del walker['from_']
                emit(role,'HIDDEN',dict(current,before=copy.deepcopy(hidden),after=hidden,samples=5,elapsedMs=100,walker=walker))
                aggregate_ids=[key for key,where in places.items() if where.startswith('crate')]
                displayed=[key for key,where in places.items() if where=='crate5'] if step=='hidden-loot' else aggregate_ids
                meta={item['id']:item for item in phase['items']}
                aggregate=dict(nativeAggregate=True,actualIds=aggregate_ids,expectedIds=aggregate_ids,discoveredSlots=list(range(1,13)),
                               identities=[dict(id=key,key=meta[key]['key'],cat=meta[key]['cat']) for key in aggregate_ids])
                reopen=dict(nativeRows=True,selectedBound=True,selectedKind='crate5' if step=='hidden-loot' else 'aggregate',
                            rowIds=displayed,containerIds=displayed,totalItems=len(displayed),expectedTotal=len(displayed),
                            groups=[dict(name=meta[key]['key'],category=meta[key]['cat'],ids=[key],count=1,nativeCount=2,
                                         groupCategory='BCMapped',expectedGroupCategory='BCMapped',
                                         itemCategories=[dict(id=key,rawCategory=meta[key]['cat'],modelCategory=meta[key]['cat'],resolvedCategory='BCMapped')]) for key in displayed],
                            before=hidden,after=dict(visible=True,rowsPending=False,countPending=False,tooltipsPending=False,nativeBuilds=3))
                emit(role,'SNAPSHOT',dict(current,native=snapshot(phase,places,role),authority=authority if step!='initial' else None,
                                        reopen=reopen,aggregateProof=aggregate))
                emit('server','SEEN',dict(current,observer=role))
        release=dict(token=token,index=index,phaseToken=phase['phaseToken'],removedIds=list(places),consumedIds=[offset+4],
                     ownedRemaining=0,originalRootIds=originals,snapshot=snapshot(None,{},'server'))
        # emit supplies the envelope token; raw nested receipts retain it.
        emit('server','RELEASE',{key:value for key,value in release.items() if key!='token'})
        release=copy.deepcopy(rows['server'][-1][1])
        for role in ('client1','client2'):
            emit(role,'RELEASE',dict(context,step='hidden-loot',receipt=release,absent=True,original=baseline[role]))
    cleanup=dict(token=token,index=2,removedCrates=12,ownedAbsent=True,ownedRemaining=0,originalRootIds=originals,
                 crates=[dict(desc,afterIndex=-1) for desc in crates],snapshot=snapshot(None,{},'server'))
    emit('server','RESTORED',{key:value for key,value in cleanup.items() if key!='token'})
    cleanup=copy.deepcopy(rows['server'][-1][1])
    emit('server','COMPLETE',dict(phases=2,restored=True))
    for role in ('client1','client2'):
        flags=dict(god=False,ghost=False,autoDrink=True);core=dict(autoDrink=True,focusLoss=True)
        page=dict(owner=dict(x=0,y=0,width=500,height=300,visible=False,pin=True,collapsed=False,maxDrawHeight=-1),
                  pane=dict(x=0,y=0,width=500,height=250,visible=True,mode='details',scroll=0,maxDrawHeight=-1))
        ui=dict(flags=dict(expected=copy.deepcopy(flags),actual=flags),core=dict(expected=copy.deepcopy(core),actual=core),cleanMode=dict(expected=True,actual=True),
                options={name:dict(expected=True,actual=True) for name in ('enableProximity','enableCorpseOnly','enableDualMode','enableNestedContainers_Loot','enableAutoLock')},
                pages=[dict(expected=copy.deepcopy(page),actual=copy.deepcopy(page),inventoryBound=True,selectionRestored=True) for _ in range(2)])
        emit(role,'RESTORED',dict(original=baseline[role],actual=baseline[role],uiProof=ui,positionProof=position(),ownedAbsent=True,authority=cleanup))
        emit(role,'COMPLETE',dict(phases=2,restored=True))
    return rows


def find(rows,role,event,step=None,index=None):
    return next(row for name,row in rows[role] if name==event and (step is None or row.get('step')==step) and (index is None or row.get('index')==index))


class WarehouseWorkloadTests(unittest.TestCase):
    def result(self,rows):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            for role,values in rows.items():
                (root/(role+'-launch.log')).write_text('\n'.join(A.MARKER+name+' '+json.dumps(row) for name,row in values))
            return A.verify(root,selection(),{})

    def test_registration_and_fresh_two_client_gate(self):
        self.assertIs(adapters.get(A.SUITE),A);A.validate(selection())
        for patch in ({'clients':True},{'clients':1},{'kind':'sp'},{'mode':'native'},{'languages':['EN']},
                      {'options':{}},{'options':{'mp_host':1}},{'options':{'mp_host':True,'seed_run':'/seed'}},
                      {'options':{'mp_host':True,'inventory_work_renderer':'clean'}},{'mods':A.MODS[:-1]}):
            with self.subTest(patch=patch),self.assertRaises(ValueError):A.validate(dict(selection(),**patch))

    def test_startup_dependencies_are_staged_for_all_real_roles(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);runtime={'roles':{role:{'cache':str(root/role)} for role in ('server','client1','client2')}}
            A.stage(ROOT,root,None,None,selection(),{},runtime)
            for role in runtime['roles']:
                lua=root/role/'mods/ActionQueueTest/42/media/lua'
                self.assertTrue((lua/'client/ZZStartup.lua').is_file());self.assertTrue((lua/'server/ZZStartupServer.lua').is_file())
                self.assertTrue((lua/'shared/QueueHealthEvents.lua').is_file())
            self.assertIn(Path(V.__file__),A.sources(ROOT,selection()))

    def test_complete_independent_two_mode_proof_passes(self):
        self.assertEqual(self.result(fixture())['issues'],[])

    def test_authority_and_projection_reject_wrong_or_foreign_items(self):
        mutations=[lambda r:find(r,'server','AUTHORITY','peer-transfer')['snapshot']['crates'][1]['itemIds'].pop(),
                   lambda r:find(r,'client1','SNAPSHOT','peer-replace')['native']['items'][0].update(endpoint='client2'),
                   lambda r:find(r,'client1','SNAPSHOT','peer-craft')['native']['rootIds'].update(client2=[]),
                   lambda r:find(r,'server','SEED')['phase'].update(phaseToken='foreign'),
                   lambda r:find(r,'server','SEED')['readiness']['client1'].update(x=20),
                   lambda r:find(r,'server','SEED')['readiness']['client2'].update(onlineId=0),
                   lambda r:find(r,'server','SEED')['readiness']['client1'].update(waitMs=16000,confirmedAt=17000),
                   lambda r:find(r,'server','AUTHORITY','peer-craft')['phase']['outputIds'].pop(),
                   lambda r:find(r,'server','AUTHORITY','hidden-loot')['phase']['items'][-1].update(id=999),
                   lambda r:find(r,'server','RELEASE')['removedIds'].pop(),
                   lambda r:find(r,'server','RESTORED')['crates'][0].update(afterIndex=1)]
        for mutation in mutations:
            rows=fixture();mutation(rows)
            with self.subTest(mutation=mutation):self.assertTrue(self.result(rows)['issues'])

    def test_hidden_refresh_reopen_recipe_and_quick_callbacks_are_required(self):
        mutations=[lambda r:find(r,'client1','HIDDEN','peer-transfer')['after'].update(nativeBuilds=4),
                   lambda r:find(r,'client1','SNAPSHOT','peer-replace')['reopen']['rowIds'].pop(),
                   lambda r:find(r,'client1','SNAPSHOT','peer-transfer')['reopen'].update(selectedBound=False),
                   lambda r:find(r,'client1','SNAPSHOT','hidden-loot')['reopen'].update(selectedKind='aggregate'),
                   lambda r:find(r,'client1','SNAPSHOT','peer-replace')['reopen']['groups'][0].update(nativeCount=1),
                   lambda r:find(r,'client1','SNAPSHOT','peer-replace')['reopen']['groups'][0].update(realCount=2),
                   lambda r:find(r,'client1','SNAPSHOT','peer-replace')['reopen']['groups'][0].update(groupCategory='WrongMapping'),
                   lambda r:find(r,'client1','SNAPSHOT','peer-replace')['reopen']['groups'][0]['itemCategories'][0].update(rawCategory='Stale'),
                   lambda r:find(r,'client1','SNAPSHOT','peer-replace')['reopen']['groups'][0]['itemCategories'][0].update(resolvedCategory='Stale'),
                   lambda r:find(r,'client1','SNAPSHOT','peer-replace')['reopen']['groups'][0]['itemCategories'].clear(),
                   lambda r:find(r,'client1','SNAPSHOT','peer-craft')['aggregateProof']['actualIds'].append(104),
                   lambda r:find(r,'client2','ACTIONS','peer-craft')['craftDispatch'].update(nativeDuration=15),
                   lambda r:find(r,'client1','ACTIONS','hidden-loot')['quick'].update(hiddenAfter=False),
                   lambda r:find(r,'client1','RESTORED')['positionProof']['actual'].update(x=10.7),
                   lambda r:find(r,'client2','RESTORED')['uiProof']['flags'].update(actual={'god':True})]
        for mutation in mutations:
            rows=fixture();mutation(rows)
            with self.subTest(mutation=mutation):self.assertTrue(self.result(rows)['issues'])

    def test_missing_duplicate_reordered_and_wrong_role_fail_closed(self):
        for mutate in (lambda r:r['client2'].pop(),lambda r:r['server'].reverse(),
                       lambda r:r['client1'].append(r['client1'][-1]),
                       lambda r:find(r,'server','SEEN').update(observer='client2'),
                       lambda r:find(r,'client2','ACTIONS','peer-transfer').update(role='client1')):
            rows=fixture();mutate(rows)
            with self.subTest(mutate=mutate):self.assertTrue(self.result(rows)['issues'])
        row=dict(suite=A.SUITE,case='peer-edits',kind='mp',mode='toolkit',role='client1',phases=2,restored=True)
        text=A.MARKER+'COMPLETE '+json.dumps(row)
        self.assertTrue(A.complete(selection(),'client1',text));self.assertFalse(A.complete(selection(),'client2',text))
        self.assertFalse(A.complete(selection(),'client1',text+'\n'+A.MARKER+'FAIL {}'))

    def test_peer_barriers_cannot_precede_authoritative_effects(self):
        rows=fixture()
        rows['server']=[row for row in rows['server'] if row[0]=='SEEN']+[row for row in rows['server'] if row[0]!='SEEN']
        self.assertTrue(self.result(rows)['issues'])

    def test_output_ids_cannot_change_after_crafting(self):
        rows=fixture()
        def rename(value):
            if type(value) is int and value in range(115,119):return value+800
            if type(value) is list:return [rename(item) for item in value]
            if type(value) is dict:return {key:rename(item) for key,item in value.items()}
            return value
        for role,events in rows.items():
            rows[role]=[(event,rename(row) if row.get('index')==1 and (row.get('step')=='hidden-loot' or event=='RELEASE') else row) for event,row in events]
        self.assertTrue(self.result(rows)['issues'])

    def test_empty_ui_restore_equality_is_not_evidence(self):
        for key in ('flags','core'):
            rows=fixture();find(rows,'client1','RESTORED')['uiProof'][key]=dict(expected={},actual={})
            self.assertTrue(self.result(rows)['issues'])


if __name__=='__main__':unittest.main()
