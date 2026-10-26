"""Bounded warehouse captures need real movement, native counts and exact effects."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from queue_checks import adapters
from queue_checks.adapters import auxiliary
INTAKE=ROOT/'tests/native_queue/contributions/storage-profile'
V=auxiliary._load(INTAKE/'verify.py')


def state(selected=False,builds=1,pending=False):
    return {'pending':pending,'pendingPane':pending,'rowsPending':pending,'countPending':pending,'tooltipsPending':False,
            'nativeBuildCount':builds,'builtWeightValues':False,'builtWeightField':'boolean','groups':1,'fastWeightGroups':0,
            'pageRefreshIdentityUnchanged':True,'paneRefreshIdentityUnchanged':True,
            'selection':{'count':1 if selected else 0,'signature':'item:123' if selected else '',
                         'anchorIndex':2 if selected else 0,'anchor':'item:123' if selected else ''}}


def environment():
    return {'year':1993,'month0':6,'day0':8,'timeOfDay':8.1,'rain':0,'fog':0,'wind':.1,'cloud':.2,
            'temperature':20,'light':.8,'width':1280,'height':900,'gameSpeed':1,'actorRootItems':1,
            'actorWeight':1,'originX':100,'originY':100,'originZ':0}


def rows():
    result=[]
    planned={'off-empty':(False,True,False),'normal-only':(True,False,False),'wishlist-only':(False,True,True),
             'both-enabled':(True,True,True),'off-repeat':(False,True,False)}
    for index,(density,mode,view,control) in enumerate(V.specifications(),1):
        hidden=view in ('own-only','both-hidden')
        initial=state();final=state(builds=1 if hidden else 31,pending=hidden)
        actual={'ownVisible':view!='both-hidden','lootVisible':view in ('both-open','loot-collapsed'),
                'ownReallyVisible':view!='both-hidden','lootReallyVisible':view in ('both-open','loot-collapsed'),
                'ownCollapsed':False,'lootCollapsed':view=='loot-collapsed','ownPaneVisible':True,'lootPaneVisible':True}
        features=(True,True,False) if control=='ordinary' else planned[control]
        enabled=control not in ('off-empty','off-repeat','ordinary')
        highlight={'sampleTicks':600,'maxTracked':100 if enabled else 0,'scanTicks':100 if enabled else 0,'clearTicks':0,
                   'outlineSamples':0 if control=='ordinary' else 12,'maxOwnedHighlighted':100 if enabled else 0,'maxOwnedOutlined':100 if enabled else 0}
        maximum=6 if density=='sparse' else 2400
        row={'index':index,'density':density,'mode':mode,'state':view,'control':control,'sourceCrates':12,
             'sourceItems':12 if density=='sparse' else 4800,'clockResolutionMs':1,'warmupMs':2000,
             'teleportsDuringMeasurement':0,'stateViolations':0,'discoveryPending':0,'pendingTicks':500 if hidden else 0,
             'initialState':actual,'finalState':dict(actual),'initialPresentation':initial,'finalPresentation':final,
             'environmentInitial':environment(),'environmentFinal':environment(),'nativeBuildDelta':0 if hidden else 30,
             'elapsedMs':13000,'distance':24,'movementTicks':500,'tileChanges':24,'reached':6,'nativeActions':6,
             'tickIntervalsMs':{'samples':600,'p50':17,'p95':20,'max':40},'uiDrawIntervalsMs':{'samples':600,'p50':17,'p95':21,'max':50},
             'observedNearbyMaxItems':maximum,'observedNearbyMaxContainers':7,'features':dict(zip(('normal','ground','wanted'),features),radius=15),
             'groundObjects':0 if control=='ordinary' else 200,'highlight':highlight,
             'callbacks':{key:{'calls':30,'items':maximum*30,'maxItems':maximum,'maxContainers':7,'ms':100,'maxMs':5} for key in V.CALLBACKS}}
        result.append(row)
    return result


def receipts(data=None):
    data=rows() if data is None else data
    result=[('SETUP',{'native':True,'crates':12,'itemType':'Base.Nails','clock':'getTimestampMs','resolutionMs':1,
                      'movement':'ISWalkToTimedAction','setupTeleport':True,'video':False,'proximity':True,'discoveryScope':'native-begin-end-events'}),
            ('STARTUP',{'untoggled':True,'mode':'clean','physical':{'raw':6,'rows':6,'exact':True},'presentation':state()})]
    for row in data:
        if row['index']==17:result.append(('GROUND',{'objects':200,'kind':'Base.Nails','native':True}))
        result.append(('PHASE',row))
        before=copy.deepcopy(row['finalPresentation']);after=state(builds=before['nativeBuildCount']+1)
        result.append(('REOPEN',{'index':row['index'],'replaced':True,'normalPostDraw':True,'sourceItems':row['sourceItems'],
            'oldId':'old'+str(row['index']),'newId':'new'+str(row['index']),'physical':{'raw':6,'rows':6,'exact':True},
            'pendingBefore':before['pending'],'pendingAfter':False,'before':before,'after':after}))
    for mode in ('clean','vanilla'):
        result.append(('SELECTION',{'mode':mode,'preserved':True,'before':state(True),'hidden':state(True),'after':state(True),
                                    'physical':{'raw':2400,'rows':2400,'exact':True}}))
    result.append(('RESTORED',{'wrappers':True,'cratesRemoved':12,'groundRemoved':200,'features':True,'phases':21}))
    result.append(('COMPLETE',None))
    return result


def text(receipts):
    return ''.join('[STORAGE_PROFILE] '+kind+(' '+json.dumps(value) if value is not None else '')+'\n' for kind,value in receipts)


class StorageProfileTests(unittest.TestCase):
    def test_registration_staging_and_verifier_preserve_capture_semantics(self):
        selection={'suite':'storage-profile','kind':'sp','mode':'toolkit','cases':['walk'],'languages':['EN'],
                   'mods':list(auxiliary.INVENTORY_MODS),'options':{}}
        self.assertIs(adapters.get('storage-profile'),auxiliary)
        self.assertEqual(auxiliary.definitions()['storage-profile']['cases'][0]['capability'],'capture')
        manifest=json.loads((INTAKE/'manifest.json').read_text())
        self.assertEqual(manifest['required_mods'],auxiliary.INVENTORY_MODS)
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);cache=root/'client1';cache.mkdir();runtime={'roles':{'client1':{'cache':str(cache)}}}
            auxiliary.stage(ROOT,root,root/'game',root/'jdk',selection,{'PZSurvivorToolkit':ROOT/'PZSurvivorToolkit'},runtime)
            helper=cache/'mods/StorageProfileNative/42/media/lua/client/ZZStorageProfileNative.lua'
            self.assertEqual(helper.read_bytes(),(INTAKE/helper.name).read_bytes())
            self.assertIn(INTAKE/'verify.py',auxiliary.sources(ROOT,selection))
            self.assertEqual(runtime['fixture']['failure_markers'],['[STORAGE_PROFILE] FAIL'])
            (cache/'console.txt').write_text(text(receipts()))
            result=auxiliary.verify(root,selection,{})
            self.assertFalse(result['issues']);self.assertEqual(result['outcomes'][0]['status'],'captured')
            self.assertEqual(len(result['evidence']['phases']),21)
            (cache/'console.txt').write_text(text(receipts())+'[STORAGE_PROFILE] FAIL test\n')
            self.assertEqual(auxiliary.verify(root,selection,{})['outcomes'][0]['status'],'failed')
        for key,value in [('kind','mp'),('languages',['RU']),('cases',['startup'])]:
            with self.subTest(key=key),self.assertRaises(ValueError):auxiliary.validate(dict(selection,**{key:value}))

    def test_capture_requires_actual_native_walk_complete_counts_and_unchanged_identity(self):
        self.assertEqual(len(V.verify(Path('/unused'),text(receipts()))['phases']),21)
        mutations=[('distance',0),('movementTicks',0),('tileChanges',0),('reached',0),('nativeActions',2),
                   ('teleportsDuringMeasurement',1),('elapsedMs',1000),('stateViolations',1),('discoveryPending',1),
                   ('sourceItems',400),('warmupMs',0),('nativeBuildDelta',999)]
        for key,value in mutations:
            data=rows();data[-1][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):V.verify(Path('/unused'),text(receipts(data)))
        data=rows();data[0]['finalPresentation']['paneRefreshIdentityUnchanged']=False
        with self.assertRaises(ValueError):V.verify(Path('/unused'),text(receipts(data)))
        for data in (rows()[:-1],list(reversed(rows())),rows()+[rows()[0]]):
            with self.assertRaises(ValueError):V.verify(Path('/unused'),text(receipts(data)))

    def test_baseline_work_is_valid_observation_not_failed_optimization(self):
        data=rows()
        for row in data:
            row['pendingTicks']=0;row['nativeBuildDelta']=30;row['finalPresentation']=state(builds=31)
        proof=V.verify(Path('/unused'),text(receipts(data)))
        self.assertEqual(proof['phases'][0]['nativeBuildDelta'],30)

    def test_same_count_stale_refs_and_selection_loss_cannot_pass(self):
        good=receipts()
        for mutate in (lambda r:r[1][1].update(untoggled=False),
                       lambda r:r[3][1].update(newId=r[3][1]['oldId']),
                       lambda r:r[3][1]['physical'].update(rows=5),
                       lambda r:r[-4][1]['hidden']['selection'].update(signature='lost'),
                       lambda r:r[-2][1].update(features=False)):
            broken=copy.deepcopy(good);mutate(broken)
            with self.assertRaises(ValueError):V.verify(Path('/unused'),text(broken))
        for missing in ('GROUND','STARTUP','REOPEN','SELECTION','RESTORED','COMPLETE'):
            broken=copy.deepcopy(good)
            index=next(i for i,row in enumerate(broken) if row[0]==missing);broken.pop(index)
            with self.subTest(missing=missing),self.assertRaises(ValueError):V.verify(Path('/unused'),text(broken))

    def test_real_feature_states_outlining_and_off_repeat_are_required(self):
        for mutate in (lambda r:r[16]['features'].update(normal=True),
                       lambda r:r[18]['features'].update(wanted=False),
                       lambda r:r[18]['highlight'].update(maxOwnedOutlined=0),
                       lambda r:r[20]['highlight'].update(scanTicks=1),
                       lambda r:r[17].update(groundObjects=4),
                       lambda r:r[18]['highlight'].update(maxOwnedOutlined=201),
                       lambda r:r[17]['uiDrawIntervalsMs'].update(samples=0),
                       lambda r:r[0]['environmentInitial'].update(width=1600)):
            data=rows();mutate(data)
            with self.assertRaises(ValueError):V.verify(Path('/unused'),text(receipts(data)))


if __name__=='__main__':unittest.main()
