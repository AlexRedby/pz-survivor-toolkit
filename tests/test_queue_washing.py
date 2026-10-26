"""Native washing receipts prove costs, same-ID endpoints and post-reset isolation."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import washing


def evidence(cancel=False, kind='sp', mode='toolkit', single=False):
    case = 'cancel-after-pickup' if cancel else 'borrowed-single-soap' if single else 'borrowed-batch'
    no_soap = not cancel and not single
    selection = dict(suite='washing', cases=[case], kind=kind, mode=mode, clients=1, languages=['EN'],
                     mods=list(washing.MODS), options={'mp_host': True} if kind == 'mp' else {})
    sink = dict(x=1, y=2, z=0, objectIndex=1, sprite='location_business_office_generic_01_49', entity='Base.WaterDispenser', ownerToken=case + ':client1:1', amount=15, capacity=15,
                moved=True, usesExternalWaterSource=False, canBeWaterPiped=True,inputLocked=True)
    garments = [dict(id=100 + i, kind=kind, blood=7.5, dirt=5, wetness=0, transforming=False,
                     parts=[dict(index=0, blood=.15, dirt=.1), dict(index=1, blood=0, dirt=0)],
                     requiredWater=5, requiredSoap=1) for i, kind in enumerate(washing.GARMENTS[:1 if cancel or single else 2])]
    prep = dict(case=case, actorId=1, bagId=10, bagType='Base.Bag_ALICEpack_Army', book=20,
                soap=dict(id=30, kind='Base.Soap2', uses=20), sink=sink, garments=garments,
                allIds=sorted([10, 20, 30, 999] + [v['id'] for v in garments]))
    actual, records = [], []
    for before in garments:
        value = {k: copy.deepcopy(v) for k, v in before.items() if k not in ('requiredWater', 'requiredSoap')}
        value.update(rootCount=int(cancel), sourceCount=int(not cancel), totalCount=1)
        if not cancel:
            value.update(blood=0, dirt=0, wetness=95, parts=[dict(v, blood=0, dirt=0) for v in before['parts']])
        actual.append(value)
        boundary = dict(perform=0, complete=0, stop=0)
        common = dict(id=before['id'], behavior=washing.BEHAVIOR if mode == 'toolkit' else None, sourceProof=mode == 'toolkit', methodsUnchanged=True,
                      begin=boundary, finish=boundary)
        records += [dict(copy.deepcopy(common), kind='ISInventoryTransferAction', progress=True, pickup=True, returned=False, transactionDuration=50),
                    dict(copy.deepcopy(common), kind='ISWashClothing', progress=True, inputRoot=True, noSoap=no_soap,
                         bloodAmount=before['blood'], dirtAmount=before['dirt'], duration=800 if no_soap else 187.5),
                    dict(copy.deepcopy(common), kind='ISInventoryTransferAction', progress=not cancel,
                         pickup=False, returned=True, transactionDuration=50 if not cancel else None)]
        wash = records[-2]
        if mode == 'native': records[-1].update(behavior='native.ISInventoryTransferAction',sourceProof=True)
        if not cancel and mode == 'toolkit':
            wash['begin'] = dict(perform=1, complete=int(kind == 'sp'), stop=0)
            wash['finish'] = copy.deepcopy(wash['begin'])
    receipt = dict(case=case, actorId=1, bagId=10, bagType=prep['bagType'], bagRootCount=1, soap=dict(prep['soap'],
                   uses=20 - (0 if cancel or no_soap else len(garments)), rootCount=1, totalCount=1),
                   sink=dict(source=sink, amount=15 - (0 if cancel else len(garments) * 5), fluidAmount=15 - (0 if cancel else len(garments) * 5), pureWater=True,
                             moved=True, usesExternalWaterSource=False, canBeWaterPiped=True,inputLocked=True),
                   garments=actual, bookId=20, tailRead=True, allIds=prep['allIds'])
    row = dict(status='passed', sourceMethodsUnchanged=True, localDeferrals=0, tailProgress=True, tailIndependent=True, lateSourceActions=0,
               reset=cancel, originalTailStarted=not cancel, returnsBeforeRead=not cancel, records=records,
               menu=dict(method='WS.WMI_BuildWashMenu+ISContextMenu.onMouseUp', callback='function: native',
                         exactArguments=True, noSoap=no_soap, requested=len(garments), bagWorn=True,inputIds=[v['id'] for v in garments],soapId=30,soapUses=20,
                         soapList=dict(shape='lua-table',count=1,ownOnly=True,items=[copy.deepcopy(prep['soap'])]),
                         choice='bag-aggregate' if no_soap else 'bag-individual'),
               actualResources=copy.deepcopy(receipt), lateObservedMs=3200 if cancel else 0, waitsObserved=0)
    if cancel:
        row['resetProof'] = dict(method='ISTimedActionQueue.clear', id=100, rootObserved=True, progress=.1,
                                 beforeGeneration=1, afterGeneration=2, freshGeneration=2,
                                 oldTailRemoved=True, freshIndependent=True)
    row.update({k: copy.deepcopy(v) for k, v in receipt.items() if k != 'case'})
    return selection, row, prep, receipt


def body_evidence(case='body-full', kind='sp', mode='toolkit'):
    cancel = case == 'body-cancel'
    selection = dict(suite='washing', cases=[case], kind=kind, mode=mode, clients=1, languages=['EN'],
                     mods=list(washing.MODS), options={'mp_host': True} if kind == 'mp' else {})
    sink = dict(x=1, y=2, z=0, objectIndex=1, sprite='location_business_office_generic_01_49', entity='Base.WaterDispenser',
                ownerToken=case + ':client1:1', amount=1 if case == 'body-water-limited' else 15, capacity=15,
                moved=True, usesExternalWaterSource=False, canBeWaterPiped=True, inputLocked=True)
    parts = [dict(index=i, blood=.1490196 if i == 0 else 0, dirt=.0980392 if i < 2 else 0) for i in range(18)]
    prep = dict(case=case, actorId=0, sink=sink, soap=dict(id=30, kind='Base.Soap2', uses=20),
                weather=dict(precipitation=0,rain=0,snow=0,rainAlwaysClean=False),
                makeup=dict(id=40, kind='Base.MakeUp_Crow', slot='base:makeup_eyes'), body=dict(parts=parts, makeupIds=[40]),
                book=20, requiredWater=2, requiredSoap=1, expectedDuration=70 if case == 'body-water-limited' else 140, allIds=[20, 30, 40, 999])
    washed = 0 if cancel else 1 if case == 'body-water-limited' else 2
    water = sink['amount'] - washed
    receipt = dict(weather=copy.deepcopy(prep['weather']),case=case, actorId=0, bookId=20, tailRead=True, allIds=copy.deepcopy(prep['allIds']) if cancel else [20, 30, 999],
                   body=dict(parts=[dict(p, blood=0, dirt=0) if p['index'] < washed else copy.deepcopy(p) for p in parts], makeupIds=[40] if cancel else []),
                   soap=dict(prep['soap'], uses=20 - int(not cancel), rootCount=1, totalCount=1),
                   makeup=dict(prep['makeup'], rootCount=int(cancel), totalCount=int(cancel), worn=cancel),
                   sink=dict(source=sink, amount=water, fluidAmount=water, pureWater=water > 0, moved=True,
                             usesExternalWaterSource=False, canBeWaterPiped=True, inputLocked=True))
    phases = dict(perform=int(not cancel), complete=int(not cancel and kind == 'sp'), stop=0)
    soap_list = dict(shape='java-list', count=1, ownOnly=True, items=[prep['soap']])
    row = dict(status='passed', sourceMethodsUnchanged=True, nativeSourceVerified=True, localDeferrals=0, tailProgress=True,
               tailIndependent=True, originalTailStarted=not cancel, reset=cancel, lateSourceActions=0, lateObservedMs=3500 if cancel else 0,
               menu=dict(method='WS.WMI_BuildWashMenu+ISContextMenu.onMouseUp', choice='yourself', exactArguments=True,
                         actorMatches=True, sinkMatches=True, closeContextMatches=True, soapList=soap_list, callback='closure native'),
               records=[dict(kind='ISWashYourself', actorId=0, duration=prep['expectedDuration'], progress=True,
                             behavior='native.ISWashYourself', sourceProof=True, methodsUnchanged=True, sinkMatches=True,
                             soaps=soap_list, requiredWater=2, requiredSoap=1, begin=phases, finish=copy.deepcopy(phases),
                             sharedFinish={k: v * int(mode == 'toolkit') for k, v in phases.items()})], actualResources=copy.deepcopy(receipt))
    if cancel: row['resetProof'] = dict(method='ISTimedActionQueue.clear', progress=.1, beforeGeneration=0, afterGeneration=2,
                                      freshGeneration=2, oldTailRemoved=True, freshIndependent=True)
    row.update({k: copy.deepcopy(v) for k, v in receipt.items() if k != 'case'})
    return selection, row, prep, receipt


def mixed_evidence(case='mixed-all', kind='sp', mode='toolkit'):
    selection,row,p,receipt=evidence(False,kind,mode)
    reset=case=='mixed-reset-after-body'
    _,body,bp,br=body_evidence('body-full',kind,mode)
    p.update(case=case,weather=bp['weather'],makeup=bp['makeup'],body=bp['body'],requiredWater=2,requiredSoap=1,expectedDuration=140)
    p['sink']['ownerToken']=case+':client1:1';p['allIds']=sorted(p['allIds']+[40])
    body['records'][0]['actorId']=p['actorId'];body['originalTailStarted']=not reset
    row.update(mixed=True,reset=reset,originalTailStarted=not reset,bodyEvidence=body,ownedCleanupActions=0,creationOverflow=False)
    row['menu'].update(choice='mixed-all',noSoap=False,washYourself=True,cleanBandages=False)
    row['menu']['soapList']['shape']='java-list'
    for value in row['records']:
        if value['kind']=='ISWashClothing':value.update(noSoap=False,duration=187.5)
    if reset:
        row['records']=[dict(v,progress=False)for v in row['records']if v['kind']=='ISInventoryTransferAction'and v.get('pickup')]
        row.update(returnsBeforeRead=True,lateObservedMs=3500,
            resetProof=dict(method='ISTimedActionQueue.clear',afterPaidBody=True,beforeClothesWash=True,beforeGeneration=1,afterGeneration=2,freshGeneration=2,
                oldTailRemoved=True,freshIndependent=True,paid=dict(body=br['body'],soapUses=19,waterAmount=13,makeupRootAbsent=True,
                    garments=[dict(v,rootCount=0,sourceCount=1)for v in p['garments']])))
        receipt['garments']=[dict(v,rootCount=0,sourceCount=1,totalCount=1)for v in p['garments']]
    receipt.update(case=case,weather=p['weather'],body=br['body'],makeup=br['makeup'],allIds=[v for v in p['allIds']if v!=40])
    receipt['soap']['uses']=19 if reset else 17
    receipt['sink'].update(amount=13 if reset else 3,fluidAmount=13 if reset else 3)
    row.update({k:copy.deepcopy(v)for k,v in receipt.items()if k!='case'});row['actualResources']=copy.deepcopy(receipt)
    selection['cases']=[case]
    return selection,row,p,receipt


class WashingTests(unittest.TestCase):
    def test_mixed_native_body_and_shared_clothes_success_reset_both_modes(self):
        for case in washing.MIXED_CASES:
            for kind in ('sp','mp'):
                for mode in ('native','toolkit'):
                    with self.subTest(case=case,kind=kind,mode=mode):
                        d=mixed_evidence(case,kind,mode);washing.validate(d[0]);self.assertEqual([],washing.check_case(*d))

    def test_mixed_oracle_rejects_unpaid_body_extra_cost_late_wash_desync_and_wrong_menu(self):
        for case in washing.MIXED_CASES:
            for change in ('body','makeup','soap','water','body-boundary','body-duration','missing-body','unsealed-clothes','no-reader','menu','duplicate',
                           'dirty-clothes','late-source','client','missing-paid','old-tail','same-generation','unpaid-wash','extra-output'):
                with self.subTest(case=case,change=change):
                    d=mixed_evidence(case);row,p,r=d[1:]
                    if change=='body':r['body']['parts'][0]['blood']=.15;self.sync(d)
                    elif change=='makeup':r['makeup']['rootCount']=1;self.sync(d)
                    elif change=='soap':r['soap']['uses']+=1;self.sync(d)
                    elif change=='water':r['sink']['amount']+=1;self.sync(d)
                    elif change=='body-boundary':row['bodyEvidence']['records'][0]['sharedFinish']['perform']=0
                    elif change=='body-duration':row['bodyEvidence']['records'][0]['duration']=1
                    elif change=='missing-body':row['bodyEvidence']['records']=[]
                    elif change=='unsealed-clothes':row['records'][0]['behavior']='compat.selected-chains'
                    elif change=='no-reader':row['tailProgress']=False
                    elif change=='menu':row['menu']['cleanBandages']=True
                    elif change=='duplicate':row['menu']['inputIds'][1]=100
                    elif change=='dirty-clothes':r['garments'][0]['blood']=7.5 if case=='mixed-all'else 0;self.sync(d)
                    elif change=='late-source':row['lateSourceActions']=1
                    elif change=='client':row['actualResources']['soap']['uses']+=1
                    elif change=='extra-output':r['allIds'].append(9999);self.sync(d)
                    elif case!='mixed-reset-after-body':continue
                    elif change=='missing-paid':row['resetProof']['paid']=None
                    elif change=='old-tail':row['originalTailStarted']=True
                    elif change=='same-generation':row['resetProof']['afterGeneration']=1
                    else:row['records'].append(dict(kind='ISWashClothing',id=100,progress=True))
                    self.assertTrue(washing.check_case(*d))

    @unittest.skipUnless(shutil.which('luajit'),'LuaJIT is required for actual mixed selector')
    def test_actual_mixed_menu_rejects_changed_body_bandages_foreign_ids_and_args(self):
        script=r'''
package.loaded.QueueWashingBodyFixture={};package.loaded.QueueWashingFixture={}
local M=assert(loadfile(arg[1]))()
assert(not pcall(M.assertBodyQueued,{records={}}),'mixed All body loss did not fail before effects')
assert(not pcall(M.assertBodyQueued,{records={{kind='ISWashClothing'}}}),'wrong native action counted as body')
assert(M.assertBodyQueued({records={{kind='ISWashYourself'}}}))
function instanceof(item,kind)return item.class==kind end
local player,sink,soap,source={},{},{},{}
local function item(id)return{class='Clothing',getID=function()return id end,getFullType=function()return 'Base.Shirt'end,getContainer=function()return source end,getItemAfterCleaning=function()return nil end}end
local first,second=item(1),item(2);local ids={garments={{id=1,kind='Base.Shirt'},{id=2,kind='Base.Shirt'}}}
local root={options={}};local data={washYourself=true,cleanBandages=false,regularItems={first,second}}
local option={target=player,param1=sink,param2={size=function()return 1 end,get=function()return soap end},param3=data,param4=false,param5=root,onSelect=function()end}
root.options={option};local state={sink=sink,soap=soap,source=source}
assert(M.selectMenu(root,player,state,ids)==root)
for _,field in ipairs({'target','param1','param4','param5','param6','notAvailable'})do
 local old=option[field];option[field]={};assert(M.selectMenu(root,player,state,ids)==nil,'foreign option '..field);option[field]=old
end
data.cleanBandages=true;assert(not M.selectMenu(root,player,state,ids));data.cleanBandages=false
data.washYourself=false;assert(not M.selectMenu(root,player,state,ids));data.washYourself=true
data.extra=true;assert(not M.selectMenu(root,player,state,ids));data.extra=nil
data.regularItems={first,first};assert(not M.selectMenu(root,player,state,ids));data.regularItems={first,second}
first.getItemAfterCleaning=function()return 'Base.Bandage'end;assert(not M.selectMenu(root,player,state,ids))
'''
        result=subprocess.run([shutil.which('luajit'),'-',str(ROOT/'tests/native_queue/washing/client/QueueWashingMixed.lua')],input=script,text=True,capture_output=True)
        self.assertEqual(0,result.returncode,result.stdout+result.stderr)

    def test_body_native_full_partial_and_reset_in_sp_host_both_modes(self):
        for case in washing.BODY_CASES:
            for kind in ('sp', 'mp'):
                for mode in ('native', 'toolkit'):
                    with self.subTest(case=case, kind=kind, mode=mode):
                        d = body_evidence(case, kind, mode)
                        washing.validate(d[0])
                        self.assertEqual([], washing.check_case(*d))

    def test_body_cost_makeup_partial_and_authority_falsifications_fail(self):
        for case in washing.BODY_CASES:
            for change in ('water', 'soap', 'makeup-root', 'makeup-slot', 'body', 'ids', 'client', 'duration', 'progress',
                           'legacy', 'behavior', 'proof', 'repeated', 'shared', 'all-menu', 'other-context', 'weather', 'late-body'):
                with self.subTest(case=case, change=change):
                    d = body_evidence(case);row, prep, receipt = d[1:]
                    if change == 'water': receipt['sink']['amount'] += 1
                    elif change == 'soap': receipt['soap']['uses'] += 1
                    elif change == 'makeup-root': receipt['makeup']['totalCount'] = 1 - receipt['makeup']['totalCount']
                    elif change == 'makeup-slot': receipt['body']['makeupIds'] = [] if case == 'body-cancel' else [40]
                    elif change == 'body': receipt['body']['parts'][1]['dirt'] = 0 if case != 'body-full' else .0980392
                    elif change == 'ids': receipt['allIds'].append(12345)
                    elif change == 'client': row['actualResources']['soap']['uses'] += 1
                    elif change == 'duration': row['records'][0]['duration'] = 1
                    elif change == 'progress': row['records'][0]['progress'] = False
                    elif change == 'legacy': row['localDeferrals'] = 1
                    elif change == 'behavior': row['records'][0]['behavior'] = 'compat.selected-chains'
                    elif change == 'proof': row['records'][0]['sourceProof'] = False
                    elif change == 'repeated': row['records'][0]['begin']['perform'] = 2
                    elif change == 'shared': row['records'][0]['sharedFinish']['perform'] = int(case == 'body-cancel')
                    elif change == 'all-menu': row['menu']['choice'] = 'all'
                    elif change == 'other-context': row['menu']['closeContextMatches'] = False
                    elif change == 'weather': receipt['weather']['rain'] = .3;self.sync(d)
                    else: row['lateSourceActions'] = 1
                    if change in ('water', 'soap', 'makeup-root', 'makeup-slot', 'body', 'ids'):
                        self.sync(d)
                    self.assertTrue(washing.check_case(*d))
        for change in ('no-reset', 'old-tail', 'late-progress', 'same-generation', 'short-watch'):
            d = body_evidence('body-cancel');r=d[1]
            if change == 'no-reset': r['reset'] = False
            elif change == 'old-tail': r['originalTailStarted'] = True
            elif change == 'late-progress': r['resetProof']['progress'] = .5
            elif change == 'same-generation': r['resetProof']['afterGeneration'] = 0
            else: r['lateObservedMs'] = 0
            with self.subTest(change=change): self.assertTrue(washing.check_case(*d))

    def test_body_logs_require_own_server_authority_without_clothing_replay(self):
        for kind in ('sp', 'mp'):
            with tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp);cases = list(washing.BODY_CASES)
                context=dict(suite='washing',kind=kind,mode='toolkit',actor='client1')
                rows=[dict(event='setup',cases=cases,expected=3,queueEnabled=True,nativeDurations=True)];raw=[]
                for case in cases:
                    _,row,prep,receipt=body_evidence(case,kind)
                    rows.append(dict(row,event='case',id=case));raw += [('PREPARED',prep),('VERIFIED',receipt)]
                rows.append(dict(event='complete',cases=cases,expected=3,performed=3,failed=0,skipped=0))
                text='\n'.join('[QUEUE_CHECK] '+json.dumps(dict(v,**context))for v in rows)+'\n[WASHING_TEST] COMPLETE\n'
                authority='\n'.join('[WASHING_TEST] '+k+' '+json.dumps(v)for k,v in raw)
                actor=root/'client1-launch.log';actor.write_text(text+('\n'+authority if kind=='sp'else''))
                if kind=='mp':(root/'server-launch.log').write_text(authority)
                selection=dict(body_evidence(kind=kind)[0],cases=cases)
                self.assertEqual([],washing.verify(root,selection,{})['issues'])
                actor.write_text(actor.read_text()+'\n[QUEUE_TEST] FAIL late body error')
                result=washing.verify(root,selection,{})
                self.assertTrue(result['issues']);self.assertTrue(all(v['status']=='failed'for v in result['outcomes']))

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT is required for actual body selector')
    def test_actual_body_menu_selector_rejects_all_foreign_disabled_and_ambiguous_options(self):
        script = r'''
package.loaded['TimedActions/ISWashYourself']={}
package.loaded.QueueWashingBodyFixture={};package.loaded.QueueHealthEvents={}
PZSurvivorToolkit={ActionQueueLifecycle={registerObserver=function()return true end},ActionQueueOperations={deferCompletion=function()return false end}}
local M=assert(loadfile(arg[1]))()
local player,sink,soap={},{},{}
local list={size=function()return 1 end,get=function(_,i)assert(i==0);return soap end}
local root={options={}};local menu={options={}}
function root:getSubMenu()return menu end
local body={target=player,param1=sink,param2=list,param3=root,onSelect=function()end}
local all={target=player,param1=sink,param2=list,param3={washYourself=true},param4=false,onSelect=function()end}
menu.options={all,body};root.options={{subOption=1}}
local selected,index,option=M.selectMenu(root,player,sink,soap)
assert(selected==menu and index==2 and option==body)
for _,key in ipairs({'target','param1','param2','param3','param4','param5','param6','onSelect','notAvailable','isDisabled'})do
 local old=body[key]
 if key=='notAvailable'or key=='isDisabled'then body[key]=true
 elseif key=='onSelect'then body[key]=nil else body[key]={}end
 assert(M.selectMenu(root,player,sink,soap)==nil,'accepted foreign body option '..key)
 body[key]=old
end
menu.options={body,body};assert(not pcall(M.selectMenu,root,player,sink,soap),'accepted duplicate body selection')
print('actual body selector passed')
'''
        result=subprocess.run([shutil.which('luajit'),'-',str(ROOT/'tests/native_queue/washing/client/QueueWashingBody.lua')],input=script,text=True,capture_output=True)
        self.assertEqual(0,result.returncode,result.stdout+result.stderr)

    def test_mixed_selection_checks_all_six_cases_in_one_log(self):
        for kind in ('sp', 'mp'):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp); cases=list(washing.CLOTHING_CASES+washing.BODY_CASES)
                context=dict(suite='washing',kind=kind,mode='toolkit',actor='client1')
                rows=[dict(event='setup',cases=cases,expected=6,queueEnabled=True,nativeDurations=True)]; raw=[]
                proof=self.sealed_replay(root) if kind=='mp' else None
                if proof: proof=dict(proof,verified=True)
                for case in cases:
                    d=body_evidence(case,kind) if case in washing.BODY_CASES else evidence(case=='cancel-after-pickup',kind,single=case=='borrowed-single-soap')
                    _,row,prep,receipt=d
                    if proof and case in washing.CLOTHING_CASES: row['replayProof']=copy.deepcopy(proof)
                    rows.append(dict(row,event='case',id=case));raw += [('PREPARED',prep),('VERIFIED',receipt)]
                rows.append(dict(event='complete',cases=cases,expected=6,performed=6,failed=0,skipped=0))
                text='\n'.join('[QUEUE_CHECK] '+json.dumps(dict(v,**context))for v in rows)+'\n[WASHING_TEST] COMPLETE\n'
                authority='\n'.join('[WASHING_TEST] '+k+' '+json.dumps(v)for k,v in raw)
                (root/'client1-launch.log').write_text(text+('\n'+authority if kind=='sp'else''))
                if kind=='mp':(root/'server-launch.log').write_text(authority)
                selection=dict(body_evidence(kind=kind)[0],cases=cases)
                runtime={'roles':{'client1':{'cache':str(root/'client1')},'server':{'cache':str(root/'server')}}} if kind=='mp' else {}
                washing.validate(selection)
                self.assertEqual([],washing.verify(root,selection,runtime)['issues'])

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT is required for actual body lifecycle bridge')
    def test_body_observer_requests_native_scope_off_without_granting_shared_ownership(self):
        script = r'''
for _,name in ipairs({'TimedActions/ISQueueActionsAction','PZSurvivorToolkit/ActionQueueOperations','TimedActions/ISWashYourself','QueueWashingBodyFixture','QueueHealthEvents'})do package.loaded[name]={}end
ISQueueActionsAction={start=function()end}
PZSurvivorToolkit={Settings={actionQueue=function()return false end},ActionQueueOperations={deferCompletion=function()return false end,adoptCommandLifecycle=function()end}}
ISTimedActionQueue={queues={}}
local L=assert(loadfile(arg[1]))();assert(loadfile(arg[2]))()
local function up(fn,key,value)
 for i=1,100 do local name,current=debug.getupvalue(fn,i);if not name then break end
  if name==key then if value~=nil then debug.setupvalue(fn,i,value)end;return current end
 end;error('missing upvalue '..key)
end
local observers=up(up(L.begin,'observe'),'observers');assert(#observers==1)
local actor={};local action={Type='ISWashYourself',character=actor,action={}}
local q={character=actor,current=action,queue={action}};ISTimedActionQueue.queues[actor]=q
local phases={perform=0,complete=0,stop=0}
local entry={row={begin=phases}}
up(observers[1].begin,'active',{player=actor,seen={[action]=entry}})
assert(L.begin(action,'perform')==true,'queue-off observer did not request native bridge scope')
assert(phases.perform==1 and L.current(actor)==nil,'observation granted queue-off shared ownership')
assert(L.begin({Type='ISWashClothing',character=actor},'perform')==false,'foreign action requested body scope')
assert(L.begin({Type='ISWashYourself',character={}},'perform')==false,'foreign actor requested body scope')
assert(L.begin(action,'unknown')==false,'unknown phase requested body scope')
print('actual body bridge scope passed')
'''
        result=subprocess.run([shutil.which('luajit'),'-',
            str(ROOT/'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueLifecycle.lua'),
            str(ROOT/'tests/native_queue/washing/client/QueueWashingBody.lua')],input=script,text=True,capture_output=True)
        self.assertEqual(0,result.returncode,result.stdout+result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT is required for actual fixture cleanup')
    def test_actual_cleanup_requires_verified_same_id_endpoint_after_native_cancel(self):
        script = r'''
package.loaded['TimedActions/ISWashClothing']={};package.loaded.QueueHealthEvents={}
local F=assert(loadfile(arg[1]))()
local cleanup
for i=1,30 do local name,value=debug.getupvalue(F.prepare,i);if not name then break end;if name=='cleanup'then cleanup=value end end
assert(cleanup,'actual cleanup missing')
local function list(values)return{size=function()return #values end,get=function(_,i)return values[i+1]end}end
function instanceof(item,name)return name=='InventoryContainer'and item.bag==true end
function isServer()return false end
Fluid={Water={}}
local part={index=function()return 0 end}
BloodClothingType={getCoveredParts=function()return list({part})end}
local function container()
 local c={values={}}
 function c:getItems()return list(self.values)end
 function c:getItemById(id)
  for _,v in ipairs(self.values)do if v:getID()==id then return v end;if v.bag then local found=v:getItemContainer():getItemById(id);if found then return found end end end
 end
 function c:Remove(item)for i,v in ipairs(self.values)do if v==item then table.remove(self.values,i);item.container=nil;return end end;error('removing absent item')end
 return c
end
local function item(c,id,kind)
 local v={container=c,id=id,kind=kind}
 function v:getID()return self.id end;function v:getFullType()return self.kind end;function v:getContainer()return self.container end
 c.values[#c.values+1]=v;return v
end
local function fixture(endpoint)
 local root,source=container(),container()
 local bag=item(root,10,'Base.Bag_ALICEpack_Army');bag.bag=true;function bag:getItemContainer()return source end
 local garment=item(endpoint=='root'and root or source,100,'Base.Tshirt_DefaultTEXTURE_TINT')
 function garment:getBloodClothingType()return{}end;function garment:getBloodLevel()return 7.5 end;function garment:getDirtiness()return 5 end
 function garment:getWetness()return 0 end;function garment:getItemAfterCleaning()return nil end
 function garment:getBlood()return .15 end;function garment:getDirt()return .10 end
 local soap=item(root,30,'Base.Soap2');function soap:getCurrentUses()return 20 end
 local book=item(root,20,'Base.BookCarpentry1');function book:getAlreadyReadPages()return 220 end;function book:getNumberOfPages()return 220 end
 local actor={getInventory=function()return root end,getOnlineID=function()return 1 end,isEquipped=function()return false end}
 local fluid={getAmount=function()return 15 end,isPureFluid=function()return true end,isInputLocked=function()return true end}
 local square={transmitRemoveItemFromSquare=function(self,obj)self.removed=obj end}
 local sink={getFluidAmount=function()return 15 end,getFluidContainer=function()return fluid end,isMovedThumpable=function()return true end,
  getUsesExternalWaterSource=function()return false end,getModData=function()return{canBeWaterPiped=true}end,
  getSquare=function()return square end,getObjectIndex=function()return -1 end}
 F.resolveSink=function(spec)assert(spec=='owned-source');return sink end
 local state={player=actor,root=root,sink=sink,case='cancel-after-pickup',ids={bagId=10,bagType=bag:getFullType(),soap={id=30},book=20,sink='owned-source',
  garments={{id=100,kind=garment:getFullType()}}}}
 return state,garment,root,source,square,sink
end
for _,endpoint in ipairs({'bag','root'})do
 local state,garment,root,source,square,sink=fixture(endpoint)
 local receipt=assert(F.verify(state))
 assert(receipt.garments[1].rootCount==(endpoint=='root'and 1 or 0))
 cleanup(state);assert(state.verifiedReceipt==receipt)
 assert(#root.values==0 and square.removed==sink,'verified endpoint cleanup failed '..endpoint)
end
for _,mutation in ipairs({'endpoint','type','duplicate','missing-receipt','invalid-receipt','foreign-bag-item'})do
 local state,garment,root,source=fixture('bag');assert(F.verify(state))
 if mutation=='endpoint'then source:Remove(garment);root.values[#root.values+1]=garment;garment.container=root
 elseif mutation=='type'then garment.kind='Base.Shirt_FormalWhite'
 elseif mutation=='duplicate'then source.values[#source.values+1]=garment
 elseif mutation=='missing-receipt'then state.verifiedReceipt=nil
 elseif mutation=='invalid-receipt'then state.verifiedReceipt.garments[1].rootCount=1
 else item(source,777,'Base.Soap2')end
 assert(not pcall(cleanup,state),'cleanup accepted changed/unverified endpoint '..mutation)
 assert(root:getItemById(10),'failed endpoint preflight already removed bag')
end
print('actual verified receipt cleanup passed')
'''
        result=subprocess.run([shutil.which('luajit'),'-',str(ROOT/'tests/native_queue/washing/shared/QueueWashingFixture.lua')],input=script,text=True,capture_output=True)
        self.assertEqual(0,result.returncode,result.stdout+result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT is required for actual readiness predicates')
    def test_actual_body_readiness_names_alias_parts_weather_and_bounds_diagnostics(self):
        script = r'''
package.loaded['TimedActions/ISWashYourself']={}
local logged,last={},nil;package.loaded.QueueHealthEvents={encode=function(value)last=value;return 'json'end};print=function()logged[#logged+1]=last end
local B=assert(loadfile(arg[1]))()
ItemBodyLocation={MAKE_UP_FULL_FACE='full',MAKE_UP_EYES='eyes',MAKE_UP_EYES_SHADOW='shadow',MAKE_UP_LIPS='lips'}
BloodBodyPartType={MAX={index=function()return 18 end},FromIndex=function(i)return i end}
SandboxVars={RainCleansBlood={AlwaysClean=false}};local rain=0
getClimateManager=function()return{getPrecipitationIntensity=function()return rain end,getRainIntensity=function()return rain end,getSnowIntensity=function()return 0 end}end
function instanceof()return false end
local client,server=false,false;function isClient()return client end;function isServer()return server end
local values={};local root={}
function root:getItems()return{size=function()return #values end,get=function(_,i)return values[i+1]end}end
function root:getItemById(id)for _,v in ipairs(values)do if v:getID()==id then return v end end end
local function item(id,kind)
 return{getID=function()return id end,getFullType=function()return kind end,getContainer=function()return root end,getCurrentUses=function()return 20 end}
end
local soap,book,makeup=item(30,'Base.Soap2'),item(20,'Base.BookCarpentry1'),item(40,'Base.MakeUp_Crow');values={soap,book,makeup}
local worn=makeup;local dirty=true;local visual={getBlood=function(_,i)return dirty and i==0 and .15 or 0 end,getDirt=function(_,i)return i<2 and .10 or 0 end}
local player={getInventory=function()return root end,getOnlineID=function()return 0 end,getHumanVisual=function()return visual end,
 getWornItem=function(_,slot)if slot=='eyes'then return worn end end}
local amount=15;local sink={getFluidAmount=function()return amount end}
local F={resolveSink=function()return sink end}
local meta={case='body-full',actorId=0,soap={id=30,kind='Base.Soap2',uses=20},book=20,makeup={id=40,kind='Base.MakeUp_Crow',slot='eyes'},sink={amount=15},body=B.snapshot(player),weather=B.weather()}
assert(B.preparationStatus(player,meta,F).ready)
worn=item(40,'Base.MakeUp_Crow')
local status=B.preparationStatus(player,meta,F)
assert(not status.ready and not status.predicates.makeupIdentity and not status.actual.makeupSameReference and status.predicates.wornIds and status.predicates.parts)
assert(status.actual.makeup.id==status.actual.wornMakeup.id and status.actual.makeupCount==1)
local alias=worn;alias.getContainer=function()return nil end
assert(not B.makeupIdentity(player,meta),'SP accepted visual alias')
client=true;assert(B.makeupIdentity(player,meta),'client rejected native unattached visual')
assert(B.preparationStatus(player,meta,F).ready,'client alias blocked readiness')
book.getAlreadyReadPages=function()return 220 end;book.getNumberOfPages=function()return 220 end
Fluid={Water={}};sink.getFluidContainer=function()return{getAmount=function()return amount end,isPureFluid=function()return true end,isInputLocked=function()return true end}end
sink.isMovedThumpable=function()return true end;sink.getUsesExternalWaterSource=function()return false end;sink.getModData=function()return{canBeWaterPiped=true}end
local receipt=assert(B.verify({player=player,root=root,ids=meta,case=meta.case,sink=sink},F))
assert(receipt.makeup.worn and receipt.makeup.rootCount==1 and receipt.makeup.totalCount==1,'client receipt lost native visual identity')
server=true;assert(not B.makeupIdentity(player,meta),'server accepted visual alias');server=false
for _,bad in ipairs({item(41,'Base.MakeUp_Crow'),item(40,'Base.MakeUp_Skull'),item(40,'Base.MakeUp_Crow')})do
 worn=bad;assert(not B.makeupIdentity(player,meta),'accepted wrong/attached worn identity')
end
local attached=item(40,'Base.MakeUp_Crow');attached.getContainer=function()return{}end;worn=attached;assert(not B.makeupIdentity(player,meta),'accepted foreign attached visual')
worn=alias;values[#values+1]=makeup;assert(not B.makeupIdentity(player,meta),'accepted duplicate root ID');values[#values]=nil
values[#values]=nil;assert(not B.makeupIdentity(player,meta),'accepted missing root');values[#values+1]=makeup
local oldSlot=meta.makeup.slot;meta.makeup.slot='lips';assert(not B.makeupIdentity(player,meta),'accepted wrong slot');meta.makeup.slot=oldSlot
assert(player:getWornItem('eyes')==alias and root:getItemById(40)==makeup,'identity observation rebound native objects')
client=false;worn=item(40,'Base.MakeUp_Crow')
dirty=false;assert(not B.preparationStatus(player,meta,F).predicates.parts);dirty=true
rain=.5;assert(not B.preparationStatus(player,meta,F).predicates.dry);rain=0
amount=0;assert(not B.preparationStatus(player,meta,F).predicates.sinkAmount);amount=15
local now=0;function getTimestampMs()return now end
for _,time in ipairs({0,200,1000,5000,15000,16000})do now=time;assert(not B.resolve(player,meta,F))end
assert(#logged==4,'readiness diagnostics were not bounded')
worn=makeup;assert(B.resolve(player,meta,F));assert(#logged==5 and logged[5].ready)
assert(B.resolve(player,meta,F));assert(#logged==5,'repeated ready diagnostics')
'''
        result=subprocess.run([shutil.which('luajit'),'-',str(ROOT/'tests/native_queue/washing/shared/QueueWashingBodyFixture.lua')],input=script,text=True,capture_output=True)
        self.assertEqual(0,result.returncode,result.stdout+result.stderr)

    def test_flat_then_two_mixed_cases_share_one_sp_host_log(self):
        for kind in ('sp','mp'):
            with self.subTest(kind=kind),tempfile.TemporaryDirectory()as tmp:
                root=Path(tmp);cases=['borrowed-single-soap',*washing.MIXED_CASES]
                context=dict(suite='washing',kind=kind,mode='toolkit',actor='client1')
                rows=[dict(event='setup',cases=cases,expected=3,queueEnabled=True,nativeDurations=True)];raw=[]
                proof=dict(self.sealed_replay(root),verified=True)if kind=='mp'else None
                for case in cases:
                    _,row,p,r=mixed_evidence(case,kind)if case in washing.MIXED_CASES else evidence(False,kind,single=True)
                    if proof:row['replayProof']=copy.deepcopy(proof)
                    rows.append(dict(row,event='case',id=case));raw.extend([('PREPARED',p),('VERIFIED',r)])
                rows.append(dict(event='complete',cases=cases,expected=3,performed=3,failed=0,skipped=0))
                text='\n'.join('[QUEUE_CHECK] '+json.dumps(dict(v,**context))for v in rows)+'\n[WASHING_TEST] COMPLETE\n'
                authority='\n'.join('[WASHING_TEST] '+k+' '+json.dumps(v)for k,v in raw)
                (root/'client1-launch.log').write_text(text+('\n'+authority if kind=='sp'else''))
                if kind=='mp':(root/'server-launch.log').write_text(authority)
                selection=dict(mixed_evidence(kind=kind)[0],cases=cases)
                self.assertEqual([],washing.verify(root,selection,{})['issues'])

    def test_mixed_reset_endpoint_requires_paid_pickup_or_proven_p4_return(self):
        d=mixed_evidence('mixed-reset-after-body');row,p,r=d[1:]
        r['garments'][0].update(rootCount=1,sourceCount=0);self.sync(d)
        self.assertTrue(washing.check_case(*d),'unpaid root retention was accepted')
        row['records'][0]['progress']=True
        row['resetProof']['paid']['garments'][0].update(rootCount=1,sourceCount=0)
        self.assertEqual([],washing.check_case(*d))
        r['garments'][0].update(rootCount=0,sourceCount=1);self.sync(d)
        self.assertTrue(washing.check_case(*d),'unproven post-reset return was accepted')

    def sealed_replay(self, root, source=None):
        if source is None:
            source = (ROOT / 'PZSurvivorToolkit/42' / washing.REPLAY_PATH).read_text()
        for role in ('client1', 'server'):
            target = root / role / 'mods/PZSurvivorToolkit/42' / washing.REPLAY_PATH
            target.parent.mkdir(parents=True, exist_ok=True);target.write_text(source)
        return washing.replay_source(root / 'client1')

    def sync(self, data):
        _, row, _, receipt = data
        row.update({k: copy.deepcopy(v) for k, v in receipt.items() if k != 'case'})
        row['actualResources'] = copy.deepcopy(receipt)

    def test_native_effects_and_explicit_reset_pass_in_sp_host_both_modes(self):
        for cancel, single in ((False, False), (False, True), (True, False)):
            for kind in ('sp', 'mp'):
                for mode in ('toolkit', 'native'):
                    with self.subTest(cancel=cancel, kind=kind, mode=mode):
                        data = evidence(cancel, kind, mode, single=single)
                        washing.validate(data[0])
                        self.assertEqual([], washing.check_case(*data))
        data = evidence();data[1]['actualResources']['garments'][0]['wetness'] = 94.5
        self.assertEqual([], washing.check_case(*data))
        data = evidence();data[3]['garments'][0]['wetness'] = 0;self.sync(data)
        self.assertEqual([], washing.check_case(*data))

    def test_sink_must_remain_an_own_finite_unplumbed_fluid_source(self):
        for change in ('moved', 'external', 'plumbed', 'infinite', 'component-free', 'generic-sink', 'wrong-entity', 'capacity', 'unlocked-prepare', 'unlocked-live'):
            with self.subTest(change=change):
                d = evidence()
                if change == 'moved': d[2]['sink']['moved'] = False
                elif change == 'external': d[2]['sink']['usesExternalWaterSource'] = True
                elif change == 'plumbed': d[2]['sink']['canBeWaterPiped'] = False
                elif change == 'infinite': d[2]['sink'].update(amount=10000,capacity=10000)
                elif change == 'component-free': d[3]['sink']['fluidAmount'] = 20
                elif change == 'generic-sink': d[2]['sink']['sprite'] = 'fixtures_sinks_01_0'
                elif change == 'wrong-entity': d[2]['sink']['entity'] = 'Base.WaterDispenserNoBottle'
                elif change == 'capacity': d[2]['sink'].update(capacity=20,amount=20)
                elif change == 'unlocked-prepare': d[2]['sink']['inputLocked'] = False
                else: d[3]['sink']['inputLocked'] = False
                self.sync(d)
                self.assertTrue(washing.check_case(*d))

    def test_definition_and_stage_use_common_native_bootstrap_without_runner_changes(self):
        definition = washing.definitions()['washing']
        self.assertEqual(1, definition['clients'])
        self.assertEqual(washing.CASES, [v['id'] for v in definition['cases']])
        selection = evidence()[0];runtime = {}
        with patch.object(washing.craft, 'stage_common') as common:
            washing.stage(ROOT, None, None, None, selection, {}, runtime)
            common.assert_called_once_with(ROOT, None, None, None, selection, {}, runtime)
        self.assertTrue(all(p.is_file() for p in washing.sources(ROOT, selection)))
        for change in ({'clients': 2}, {'clients': True}, {'languages': ['EN', 'RU']}, {'actor': 'client2'},
                       {'cases': list(reversed(washing.CASES))}, {'options': {'world_template': '/tmp/save'}},
                       {'mods': list(washing.craft.MODS)}, {'kind': 'mp', 'options': {}}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                washing.validate(dict(selection, **change))

    def test_mp_replay_metadata_pins_reviewed_body_but_derives_line_from_sealed_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp);proof = self.sealed_replay(root)
            selection = evidence(kind='mp')[0]
            runtime = {'roles': {name: {'cache': str(root / name)} for name in ('client1', 'server')}}
            with patch.object(washing.craft, 'stage_common'):
                washing.stage(ROOT, root, None, None, selection, {}, runtime)
            helper = root / 'client1/mods/ActionQueueTest/42/media/lua/shared/QueueWashingReplayProof.lua'
            self.assertEqual(helper.read_text(), (root / 'server/mods/ActionQueueTest/42/media/lua/shared/QueueWashingReplayProof.lua').read_text())
            self.assertIn('replayLine=' + str(proof['replayLine']), helper.read_text())
            self.assertEqual(washing.REPLAY_BODY_SHA256, proof['helperSha256'])
            source = (ROOT / 'PZSurvivorToolkit/42' / washing.REPLAY_PATH).read_text()
            shifted = self.sealed_replay(root, '-- unrelated insertion above helper\n' + source)
            self.assertEqual(proof['replayLine'] + 1, shifted['replayLine'])
            self.assertNotEqual(proof['checksum'], shifted['checksum'])
            self.assertEqual(proof['helperSha256'], shifted['helperSha256'])
            for body in (source.replace('local planned, transfers, incoming = {}, {}, {}', 'local planned, transfers, incoming = {}, {}, {} -- changed body'),
                         source + '\n    for _, action in ipairs(planned) do add(action) end\n'):
                with self.assertRaises(ValueError): self.sealed_replay(root, body)
            # SP neither derives nor requires replay metadata.
            with patch.object(washing.craft, 'stage_common'), patch.object(washing, 'replay_source', side_effect=AssertionError('SP proof evaluated')):
                washing.stage(ROOT, root, None, None, evidence()[0], {}, {})

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT is required for native source checksum parity')
    def test_mp_generated_checksum_matches_actual_native_sourceproof(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp);proof = self.sealed_replay(root)
            source = root / 'client1/mods/PZSurvivorToolkit/42' / washing.REPLAY_PATH
            script = "local P=assert(loadfile(arg[1]))();local f=assert(io.open(arg[2],'rb'));print(P.checksum({readLine=function()local s=f:read('*l');return s and s:gsub('\\r$','')end},true));f:close()"
            result = subprocess.run([shutil.which('luajit'), '-', str(ROOT / 'PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'), str(source)], input=script, text=True, capture_output=True)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertEqual(proof['checksum'], int(result.stdout.strip()))

    def test_menu_family_progress_and_shared_migration_cannot_be_claimed_by_queue_idle(self):
        for change in ('menu', 'aggregate', 'bag', 'methods', 'family', 'proof', 'progress', 'root',
                       'duration', 'local-defer', 'no-shared', 'duplicate-boundary', 'incomplete-boundary', 'tail'):
            with self.subTest(change=change):
                d = evidence();row = d[1];wash = row['records'][1]
                if change == 'menu': row['menu']['method'] = 'fixtureScoped'
                elif change == 'aggregate': row['menu']['exactArguments'] = False
                elif change == 'bag': row['menu']['bagWorn'] = False
                elif change == 'methods': wash['methodsUnchanged'] = False
                elif change == 'family': wash['behavior'] = 'compat.selected-chains'
                elif change == 'proof': wash['sourceProof'] = False
                elif change == 'progress': wash['progress'] = False
                elif change == 'root': wash['inputRoot'] = False
                elif change == 'duration': wash['duration'] = 1
                elif change == 'local-defer': row['localDeferrals'] = 1
                elif change == 'no-shared': wash['begin']['perform'] = wash['finish']['perform'] = 0
                elif change == 'duplicate-boundary': wash['begin']['perform'] = wash['finish']['perform'] = 2
                elif change == 'incomplete-boundary': wash['finish']['perform'] = 0
                else: row['tailProgress'] = False
                self.assertTrue(washing.check_case(*d))

    def test_exact_consumption_cleaning_and_conservation_are_authoritative(self):
        for change in ('free-water', 'double-water', 'free-soap', 'double-soap', 'dirt', 'part', 'dry',
                       'duplicate', 'root', 'new-id', 'transform', 'foreign-output', 'tail'):
            with self.subTest(change=change):
                d = evidence(single=change == 'free-soap');receipt = d[3];item = receipt['garments'][0]
                if change == 'free-water': receipt['sink']['amount'] = 20
                elif change == 'double-water': receipt['sink']['amount'] = 0
                elif change == 'free-soap': receipt['soap']['uses'] = 20
                elif change == 'double-soap': receipt['soap']['uses'] = 16
                elif change == 'dirt': item['dirt'] = 1
                elif change == 'part': item['parts'][0]['blood'] = .15
                elif change == 'dry': item['wetness'] = 101
                elif change == 'duplicate': item['totalCount'] = 2
                elif change == 'root': item.update(rootCount=1, sourceCount=0)
                elif change == 'new-id': item['id'] += 10
                elif change == 'transform': item['transforming'] = True
                elif change == 'foreign-output': receipt['allIds'].append(888)
                else: receipt['tailRead'] = False
                self.sync(d)
                self.assertTrue(washing.check_case(*d))

    def test_local_view_cannot_echo_wrong_server_effects_or_disagree(self):
        for key in ('soap', 'sink', 'garments'):
            d = evidence();actual = d[1]['actualResources']
            if key == 'soap': actual[key]['uses'] += 1
            elif key == 'sink': actual[key]['amount'] += 1
            else: actual[key][0]['sourceCount'] = 0
            with self.subTest(key=key): self.assertTrue(washing.check_case(*d))

    def test_actual_menu_flags_and_both_native_soap_list_shapes_control_costs(self):
        for single in (False, True):
            for shape in ('lua-table', 'java-list'):
                d = evidence(single=single);d[1]['menu']['soapList']['shape'] = shape
                self.assertEqual([], washing.check_case(*d))
                for change in ('flag', 'soap-shape', 'soap-id', 'soap-count', 'soap-cost', 'no-soap-duration'):
                    with self.subTest(single=single, shape=shape, change=change):
                        bad = copy.deepcopy(d)
                        if change == 'flag': bad[1]['menu']['noSoap'] = single
                        elif change == 'soap-shape': bad[1]['menu']['soapList']['shape'] = 'invented-list'
                        elif change == 'soap-id': bad[1]['menu']['soapList']['items'][0]['id'] += 1
                        elif change == 'soap-count': bad[1]['menu']['soapList']['count'] = 2
                        elif change == 'soap-cost':
                            bad[3]['soap']['uses'] = 20 if single else 18;self.sync(bad)
                        elif not single:
                            bad[1]['records'][1]['duration'] = 187.5
                        else: continue
                        self.assertTrue(washing.check_case(*bad))

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT is required for actual observer delegation check')
    def test_actual_reset_observer_preserves_queue_add_and_records_only_native_creation_provenance(self):
        script = r'''
for _,name in ipairs({'PZSurvivorToolkit/ActionQueuePanel','TimedActions/ISReadABook','ISUI/WMI_WashingSubmenus'})do package.loaded[name]={}end
local testKind=arg[3]or 'sp'
package.loaded.QueueTestSelection={mode='toolkit',kind=testKind,cases={'cancel-after-pickup'}}
local replay={mod='PZSurvivorToolkit',path='media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua',checksum=123,
 replayLine=1100,frameSuffix='/mods/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua',verified=true}
if testKind=='mp'then
 package.loaded.QueueWashingReplayProof=replay
 package.loaded['PZSurvivorToolkit/SourceProof']={matches=function()error('dispatch is not exercised by this creation observer test')end}
end
package.loaded.QueueHealthEvents=assert(loadfile(arg[2]))();package.loaded.QueueWashingFixture={}
Events={};for _,name in ipairs({'OnServerCommand','OnGameStart','OnPlayerUpdate','OnTick'})do Events[name]={Add=function()end}end
local ctor=function()end;ISInventoryTransferAction={new=ctor}
local observed;ISTimedActionQueue={add=function(action,a,b)observed={action,a,b};return 'original-result',42 end}
local queue={toolkitOperationGeneration=6};ISTimedActionQueue.getTimedActionQueue=function()return queue end
PZSurvivorToolkit={ActionQueueLifecycle={registerObserver=function()return true end},ActionQueueOperations={deferCompletion=function()end},
 ActionQueueCompat={isInstalled=function(id)return id=='P4TidyUpMeister'end}}
assert(loadfile(arg[1]))()
local function set(fn,wanted,value)
 for i=1,100 do local name,found=debug.getupvalue(fn,i);if not name then break end
  if name==wanted then if value~=nil then debug.setupvalue(fn,i,value)end;return found end
 end;error('missing fixture upvalue '..wanted)
end
local actor={};function getPlayer()return actor end;function getTimestampMs()return 12345 end
local bag={getID=function()return 10 end,getFullType=function()return 'Base.Bag_ALICEpack_Army'end}
local root={contains=function()return true end};local source={getContainingItem=function()return bag end}
local item={getID=function()return 100 end,getFullType=function()return 'Base.Tshirt_DefaultTEXTURE_TINT'end,getContainer=function()return root end}
local run={resetting=true,allowed={[100]=true},creations={},creationCount=0,creationOverflow=false}
if testKind=='mp'then run.replayProof=replay end
set(ISTimedActionQueue.add,'run',run);set(set(ISTimedActionQueue.add,'creationTrace'),'state',{root=root,source=source})
local frames={{file='client/P4TidyUpMeister.lua',line=895},{file='client/P4TidyUpMeister.lua',line=839},{file='client/ZZWashing.lua',line=42}}
function getCurrentCoroutine()return 'native-coroutine'end
function getCallframeTop(c)assert(c=='native-coroutine');return #frames end
function getCoroutineCallframeStack(c,i)assert(c=='native-coroutine');return frames[i+1]end
function getFilenameOfCallframe(f)return f.file end;function getLineNumber(f)return f.line end
local action={Type='ISInventoryTransferAction',item=item,character=actor,srcContainer=root,destContainer=source}
local a,b=ISTimedActionQueue.add(action,'unchanged',77)
assert(a=='original-result'and b==42 and observed[1]==action and observed[2]=='unchanged'and observed[3]==77)
assert(ISInventoryTransferAction.new==ctor,'observer changed native constructor')
local trace=assert(run.creations[action]);assert(trace.p4RestoreSite and trace.stackAvailable and trace.p4SourceVerified)
assert(trace.itemId==100 and trace.actorMatches and trace.fromRoot and trace.toDeclaredBag and trace.rootPresent)
assert(trace.destinationBagId==10 and trace.noCallbacks and trace.onComplete=='nil'and trace.generation==6 and trace.at==12345)
for _,bad in ipairs({
 {{file='client/P4TidyUpMeister.lua',line=915}},
 {{file='client/P4TidyUpMeister.lua',line=839}},
 {{file='other/P4TidyUpMeister.lua',line=895},{file='client/P4TidyUpMeister.lua',line=839}},
 {{file='client/P4TidyUpMeister.lua',line=839},{file='client/P4TidyUpMeister.lua',line=895}}
})do
 frames=bad;local other={Type='ISInventoryTransferAction',item=item,character=actor,srcContainer=root,destContainer=source}
 ISTimedActionQueue.add(other);assert(not run.creations[other].p4RestoreSite,'observer accepted another site/caller')
end
frames={{file='client/ISUI/WMI_WashingSubmenus.lua',line=341}}
local child={Type='ISInventoryTransferAction',item=item,character=actor,srcContainer=root,destContainer=source,onCompleteFunc=function()end}
ISTimedActionQueue.add(child);assert(not run.creations[child].p4RestoreSite and not run.creations[child].noCallbacks)
assert(run.creationCount==6 and not run.creationOverflow)
if testKind=='mp'then
 frames={{file='/sealed/client1'..replay.frameSuffix,line=replay.replayLine}}
 local function observeReplay()
  local a={Type='ISInventoryTransferAction',item=item,character=actor,srcContainer=root,destContainer=source}
  ISTimedActionQueue.add(a);return assert(run.creations[a])
 end
 local recorded=observeReplay();assert(recorded.compatReplaySite and not recorded.p4RestoreSite and recorded.replayProof==replay)
 frames[1].line=replay.replayLine-1;assert(not observeReplay().compatReplaySite)
 frames[1].line=replay.replayLine;frames[1].file='/unowned/ActionQueueCompat.lua';assert(not observeReplay().compatReplaySite)
 frames[1].file='/sealed/client1'..replay.frameSuffix;replay.verified=false;assert(not observeReplay().compatReplaySite)
 assert(run.creationCount==10 and not run.creationOverflow)
end
print('actual native reset creation observer preserves delegation and provenance')
'''
        for kind in ('sp', 'mp'):
            result = subprocess.run([shutil.which('luajit'), '-', str(ROOT / 'tests/native_queue/washing/client/ZZWashing.lua'),
                                     str(ROOT / 'tests/native_queue/health/shared/QueueHealthEvents.lua'), kind],
                                    input=script, text=True, capture_output=True)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertIn('actual native reset creation observer preserves delegation and provenance', result.stdout)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT is required for actual menu selection check')
    def test_actual_selector_preserves_aggregate_no_soap_and_selects_individual_soap(self):
        script = r'''
for _,name in ipairs({'PZSurvivorToolkit/ActionQueuePanel','TimedActions/ISReadABook','ISUI/WMI_WashingSubmenus'})do package.loaded[name]={}end
local config={mode='toolkit',cases={'borrowed-batch'}};package.loaded.QueueTestSelection=config
package.loaded.QueueHealthEvents=assert(loadfile(arg[2]))()
package.loaded.QueueWashingFixture={noSoap=function(case)return case=='borrowed-batch'end}
local tick
Events={};for _,name in ipairs({'OnServerCommand','OnGameStart','OnPlayerUpdate','OnTick'})do
 local event=name;Events[name]={Add=function(fn)if event=='OnTick'then tick=fn end end}
end
PZSurvivorToolkit={ActionQueueLifecycle={registerObserver=function()return true end},ActionQueueOperations={deferCompletion=function()end}}
ISTimedActionQueue={add=function()end}
assert(loadfile(arg[1]))()
local function upvalue(fn,wanted,value)
 for i=1,100 do local name,found=debug.getupvalue(fn,i);if not name then break end
  if name==wanted then if value~=nil then debug.setupvalue(fn,i,value)end;return found end
 end;error('missing fixture upvalue '..wanted)
end
local dispatch=upvalue(tick,'dispatch');local selectOption=upvalue(dispatch,'menuOption')
local actor,sink,source={},{},{}
function getPlayer()return actor end
function instanceof(value,kind)return type(value)=='table'and(kind=='InventoryItem'and value.id~=nil or kind=='Clothing'and value.clothing==true)end
local function item(id,kind,clothing)
 return {id=id,clothing=clothing,getID=function()return id end,getFullType=function()return kind end,
  getCurrentUses=function()return 20 end,getContainer=function()return source end}
end
local soap=item(30,'Base.Soap2',false);local a,b=item(100,'Base.Tshirt_DefaultTEXTURE_TINT',true),item(101,'Base.Shirt_FormalWhite',true)
upvalue(selectOption,'state',{sink=sink,soap=soap,source=source})
upvalue(selectOption,'ids',{garments={{id=100},{id=101}}})
local callback=function()end
local aggregate={name='bag all',target=actor,onSelect=callback,param1=sink,param2={soap},param3={a,b},param5=true}
local individual={name='one shirt',target=actor,onSelect=callback,param1=sink,param2={soap},param3={a},param5=false}
local all={name='aggregate body/items',target=actor,onSelect=callback,param1=sink,param2={soap},param3={regularItems={a,b}},param5=true}
local header={name='header',param2=false}
local menu={options={header,all,aggregate,individual}}
local selected,index,option,tree,soaps=selectOption(menu,{[100]=true,[101]=true})
assert(selected==menu and index==3 and option==aggregate and option.param5==true)
assert(soaps.shape=='lua-table'and soaps.count==1 and #tree.rows==4 and tree.rows[3].noSoap=='true')
config.cases[1]='borrowed-single-soap';upvalue(selectOption,'ids',{garments={{id=100}}})
selected,index,option,tree,soaps=selectOption(menu,{[100]=true})
assert(index==4 and option==individual and option.param5==false and soaps.shape=='lua-table')
individual.param2={size=function()return 1 end,get=function(_,i)assert(i==0);return soap end}
selected,index,option,tree,soaps=selectOption(menu,{[100]=true});assert(index==4 and soaps.shape=='java-list')
assert(aggregate.param5==true and individual.param5==false,'selector rewrote native callback arguments')
print('actual native menu shape/flag selection passed')
'''
        result = subprocess.run([shutil.which('luajit'), '-', str(ROOT / 'tests/native_queue/washing/client/ZZWashing.lua'),
                                 str(ROOT / 'tests/native_queue/health/shared/QueueHealthEvents.lua')],
                                input=script, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn('actual native menu shape/flag selection passed', result.stdout)

    def test_natural_one_tick_wait_is_counted_without_fake_progress_or_longer_duration(self):
        for mode in ('native', 'toolkit'):
            d = evidence(kind='mp', mode=mode)
            boundary = dict(perform=int(mode == 'toolkit'), complete=0, stop=0)
            wait = dict(kind='WMI_WaitForInvUpdate', id=100, duration=1, progress=False,
                        behavior=washing.BEHAVIOR if mode == 'toolkit' else None, sourceProof=mode == 'toolkit', methodsUnchanged=True,
                        begin=boundary, finish=copy.deepcopy(boundary))
            d[1]['records'].insert(1, wait);d[1]['waitsObserved'] = 1
            self.assertEqual([], washing.check_case(*d))
            for change in ('count', 'duration', 'identity', 'finish'):
                bad = copy.deepcopy(d)
                if change == 'count': bad[1]['waitsObserved'] = 0
                elif change == 'duration': bad[1]['records'][1]['duration'] = 100
                elif change == 'identity': bad[1]['records'][1]['id'] = 555
                else: bad[1]['records'][1]['finish']['complete'] = 1
                with self.subTest(mode=mode, change=change): self.assertTrue(washing.check_case(*bad))

    def test_native_reset_preserves_dirty_root_item_and_fresh_generation_only(self):
        for change in ('not-reset', 'pre-pickup', 'late-cancel', 'old-tail', 'same-generation', 'fresh-grouped',
                       'late-action', 'old-return', 'washed-anyway', 'water', 'soap', 'short-watch'):
            with self.subTest(change=change):
                d = evidence(True);row = d[1];reset = row['resetProof']
                if change == 'not-reset': row['reset'] = False
                elif change == 'pre-pickup': reset['rootObserved'] = False
                elif change == 'late-cancel': reset['progress'] = .8
                elif change == 'old-tail': row['originalTailStarted'] = True
                elif change == 'same-generation': reset['afterGeneration'] = reset['beforeGeneration']
                elif change == 'fresh-grouped': reset['freshIndependent'] = False
                elif change == 'late-action': row['lateSourceActions'] = 1
                elif change == 'old-return': row['records'][2]['progress'] = True
                elif change == 'washed-anyway': d[3]['garments'][0].update(blood=0, dirt=0)
                elif change == 'water': d[3]['sink']['amount'] -= 5
                elif change == 'soap': d[3]['soap']['uses'] -= 1
                else: row['lateObservedMs'] = 0
                self.sync(d)
                self.assertTrue(washing.check_case(*d))

    def restored(self, mode='native', kind='sp', behavior='native.ISInventoryTransferAction'):
        d = evidence(True, kind=kind, mode=mode);row, prep, receipt = d[1:]
        restore = dict(copy.deepcopy(row['records'][2]), postReset=True, ownedRestore=True, progress=True,
                       behavior=behavior, sourceProof=True,transactionDuration=50)
        restore['creation'] = dict(itemId=prep['garments'][0]['id'],itemKind=prep['garments'][0]['kind'],actorMatches=True,
            fromRoot=True,toDeclaredBag=True,destinationBagId=prep['bagId'],destinationBagType=prep['bagType'],
            rootPresent=True,noCallbacks=True,p4SourceVerified=True,p4RestoreSite=True,stackAvailable=True,
            onStart='nil',onComplete='nil',onCancel='nil',generation=2,at=1234,
            frames=[dict(file='client/P4TidyUpMeister.lua',line=839),dict(file='client/P4TidyUpMeister.lua',line=895)])
        row['records'].append(restore);row['ownedCleanupActions']=1
        receipt['garments'][0].update(rootCount=0,sourceCount=1);self.sync(d)
        return d

    def test_queue_off_preserves_unowned_native_execution_and_cannot_claim_shared_ownership(self):
        d = evidence(mode='native')
        self.assertEqual([], washing.check_case(*d))
        for change in ('compat', 'claimed-proof', 'claimed-shared', 'foreign-native'):
            bad=copy.deepcopy(d);record=bad[1]['records'][1]
            if change=='compat': record.update(behavior=washing.BEHAVIOR,sourceProof=True)
            elif change=='claimed-proof': record['sourceProof']=True
            elif change=='claimed-shared': record['begin']['perform']=record['finish']['perform']=1
            else: record.update(behavior='native.ISWashClothing',sourceProof=True)
            with self.subTest(change=change): self.assertTrue(washing.check_case(*bad))
        d=evidence(mode='toolkit');d[1]['records'][1].update(behavior=None,sourceProof=False)
        self.assertTrue(washing.check_case(*d),'enabled primary family proof must stay strict')

    def test_only_proven_native_p4_restore_can_change_the_post_reset_endpoint(self):
        for mode in ('native','toolkit'):
            for kind in ('sp','mp'):
                for behavior in (('native.ISInventoryTransferAction','compat.tidy-transfers') if mode=='toolkit' else ('native.ISInventoryTransferAction',)):
                    with self.subTest(mode=mode,kind=kind,behavior=behavior):
                        d=self.restored(mode,kind,behavior)
                        self.assertEqual([],washing.check_case(*d))
        self.assertTrue(washing.check_case(*self.restored(behavior='compat.tidy-transfers')),
                        'disabled queue cannot claim compat cleanup ownership')
        for change in ('unproven','wmi','wrong-site','legacy-site','missing-caller','different-file','reordered','wrong-file','wrong-bag','wrong-item','foreign-actor',
                       'callback','unknown-behavior','unpaid','duplicate','old-return','late-wash','late-wait','shared-claim','still-root'):
            with self.subTest(change=change):
                d=self.restored();r=d[1]['records'][-1];trace=r['creation']
                if change=='unproven': r.pop('creation')
                elif change=='wmi': trace['frames']=[dict(file='ISUI/WMI_WashingSubmenus.lua',line=341)]
                elif change=='wrong-site': trace['frames'][0]['line']=473
                elif change=='legacy-site': trace['frames']=[dict(file='client/P4TidyUpMeister.lua',line=915)]
                elif change=='missing-caller': trace['frames']=trace['frames'][:1]
                elif change=='different-file': trace['frames'][1]['file']='other/P4TidyUpMeister.lua'
                elif change=='reordered': trace['frames'].reverse()
                elif change=='wrong-file': trace['frames'][0]['file']='NotP4TidyUpMeister.lua'
                elif change=='wrong-bag': trace['destinationBagId']+=1
                elif change=='wrong-item': trace['itemId']+=1
                elif change=='foreign-actor': trace['actorMatches']=False
                elif change=='callback': trace.update(noCallbacks=False,onComplete='function: foreign')
                elif change=='unknown-behavior': r['behavior']='compat.selected-chains'
                elif change=='unpaid': r['progress']=False
                elif change=='duplicate': d[1]['records'].append(copy.deepcopy(r));d[1]['ownedCleanupActions']=2
                elif change=='old-return': d[1]['records'][2]['progress']=True
                elif change in ('late-wash','late-wait'): r['kind']='ISWashClothing' if change=='late-wash' else 'WMI_WaitForInvUpdate'
                elif change=='shared-claim': r['begin']['perform']=r['finish']['perform']=1
                else: d[3]['garments'][0].update(rootCount=1,sourceCount=0);self.sync(d)
                self.assertTrue(washing.check_case(*d))

    def test_mp_cleanup_requires_exact_live_and_independently_sealed_replay_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            proof = self.sealed_replay(Path(tmp))
            for mode in ('native', 'toolkit'):
                d = self.restored(mode=mode, kind='mp')
                trace = d[1]['records'][-1]['creation']
                d[1]['replayProof'] = dict(proof, verified=True)
                trace.update(p4RestoreSite=False, compatReplaySite=True, replayProof=dict(proof, verified=True),
                             frames=[dict(file='/sealed/client1' + proof['frameSuffix'], line=proof['replayLine'])])
                self.assertEqual([], washing.check_case(*d, proof))
                for change in ('no-sealed-proof', 'stale-row', 'stale-trace', 'unverified', 'wrong-line', 'wrong-file',
                               'fallback', 'p4-unverified', 'callback', 'sp', 'primary-family'):
                    bad = copy.deepcopy(d);r = bad[1]['records'][-1];trace = r['creation'];expected = proof
                    if change == 'no-sealed-proof': expected = None
                    elif change == 'stale-row': bad[1]['replayProof']['checksum'] += 1
                    elif change == 'stale-trace': trace['replayProof']['checksum'] += 1
                    elif change == 'unverified': trace['replayProof']['verified'] = False
                    elif change == 'wrong-line': trace['frames'][0]['line'] += 1
                    elif change == 'wrong-file': trace['frames'][0]['file'] = '/unknown/ActionQueueCompat.lua'
                    elif change == 'fallback': trace['frames'][0]['line'] -= 65
                    elif change == 'p4-unverified': trace['p4SourceVerified'] = False
                    elif change == 'callback': trace['noCallbacks'] = False
                    elif change == 'sp': bad[0]['kind'] = 'sp'
                    elif mode == 'toolkit': bad[1]['records'][1].update(behavior=None, sourceProof=False)
                    else: bad[1]['records'][1].update(behavior=washing.BEHAVIOR, sourceProof=True)
                    with self.subTest(mode=mode, change=change): self.assertTrue(washing.check_case(*bad, expected))

    def test_malformed_envelopes_fail_without_verifier_crashes(self):
        for index, value in ((1, None), (2, None), (3, [])):
            d = list(evidence());d[index] = value
            self.assertTrue(washing.check_case(*d))
        for target, key, value in ((1, 'records', None), (3, 'garments', [None]), (1, 'actualResources', []),
                                   (2, 'garments', None), (2, 'sink', None), (1, 'menu', None)):
            d = evidence();d[target][key] = value
            with self.subTest(key=key): self.assertTrue(washing.check_case(*d))

    def logs(self, root, kind, mode):
        data = [evidence(cancel, kind, mode, single=single) for cancel, single in ((False, False), (False, True), (True, False))]
        selection = dict(data[0][0], cases=list(washing.CLOTHING_CASES))
        context = dict(suite='washing', kind=kind, mode=mode, actor='client1')
        rows = [dict(event='setup', cases=washing.CLOTHING_CASES, expected=len(data), queueEnabled=mode == 'toolkit', nativeDurations=True)]
        raw = []
        replay = dict(self.sealed_replay(root), verified=True) if kind == 'mp' else None
        for _, row, prep, receipt in data:
            if kind == 'mp': row['replayProof'] = replay
            rows.append(dict(row, event='case', id=prep['case']))
            raw += [('PREPARED', prep), ('VERIFIED', receipt)]
        rows.append(dict(event='complete', cases=washing.CLOTHING_CASES, expected=len(data), performed=len(data), failed=0, skipped=0))
        text = '\n'.join('[QUEUE_CHECK] ' + json.dumps(dict(row, **context)) for row in rows) + '\n[WASHING_TEST] COMPLETE\n'
        authority = '\n'.join('[WASHING_TEST] ' + key + ' ' + json.dumps(value) for key, value in raw)
        (root / 'client1-launch.log').write_text(text + ('\n' + authority if kind == 'sp' else ''))
        if kind == 'mp': (root / 'server-launch.log').write_text(authority)
        return selection

    def test_log_gate_requires_authority_exact_order_and_no_native_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for kind in ('sp', 'mp'):
                for mode in ('toolkit', 'native'):
                    selection = self.logs(root, kind, mode)
                    self.assertEqual([], washing.verify(root, selection, {})['issues'])
                    for change in ('failure', 'duplicate', 'missing', 'server-echo', 'source-body', 'source-different', 'live-proof'):
                        if change in ('server-echo', 'source-body', 'source-different', 'live-proof') and kind == 'sp': continue
                        with self.subTest(kind=kind, mode=mode, change=change):
                            self.logs(root, kind, mode)
                            path = root / ('server-launch.log' if kind == 'mp' else 'client1-launch.log')
                            text = path.read_text()
                            if change == 'failure': text += '\n[QUEUE_TEST] FAIL late washing callback'
                            elif change == 'duplicate': text += '\n' + next(line for line in text.splitlines() if '] VERIFIED ' in line)
                            elif change == 'missing': text = '\n'.join(line for line in text.splitlines() if '] PREPARED ' not in line)
                            elif change == 'server-echo':
                                (root / 'client1-launch.log').write_text((root / 'client1-launch.log').read_text() + '\n' + text)
                                text = ''
                            elif change in ('source-body', 'source-different'):
                                source = root / 'server/mods/PZSurvivorToolkit/42' / washing.REPLAY_PATH
                                original = source.read_text()
                                source.write_text(original.replace('local planned, transfers, incoming = {}, {}, {}', 'local planned, transfers, incoming = {}, {}, {} -- changed body')
                                                  if change == 'source-body' else '-- unrelated offset\n' + original)
                            else:
                                actor = root / 'client1-launch.log'
                                actor.write_text(actor.read_text().replace('"verified": true', '"verified": false'))
                            path.write_text(text)
                            self.assertTrue(washing.verify(root, selection, {})['issues'])
        self.assertFalse(washing.complete({}, 'server', '[WASHING_TEST] COMPLETE'))
        self.assertFalse(washing.complete({}, 'client1', '[WASHING_TEST] COMPLETE\n[WASHING_TEST] COMPLETE'))

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT is required for native fixture syntax')
    def test_native_fixture_sources_parse(self):
        for path in (ROOT / 'tests/native_queue/washing').rglob('*.lua'):
            result = subprocess.run([shutil.which('luajit'), '-', str(path)], input='assert(loadfile(arg[1]))', capture_output=True, text=True)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT is required for native fixture setup check')
    def test_finite_source_constructs_the_declared_native_entity_not_an_untyped_sink(self):
        script = r'''
package.loaded['TimedActions/ISWashClothing']={}
package.loaded.QueueHealthEvents=assert(loadfile(arg[2]))()
local F=assert(loadfile(arg[1]))()
local sink=assert(F.createSource,'fixture source helper missing')
local entity={name='Base.WaterDispenser'}
function getScriptManager()return {getGameEntityScript=function(_,name)assert(name==entity.name);return entity end}end
function getTimestampMs()return 1 end
Fluid={Water={}}
IsoFlagType={waterPiped='waterPiped'}
local objects={}
local sq={getX=function()return 1 end,getY=function()return 0 end,getZ=function()return 0 end,
 getBuilding=function()return nil end,getRoom=function()return nil end,isNoWater=function()return false end,canStand=function()return true end,isFree=function()return true end,
 getObjects=function()return {size=function()return #objects end,get=function(_,i)return objects[i+1]end}end,
 AddSpecialObject=function(_,obj)objects[#objects+1]=obj;obj.index=#objects-1 end}
local origin={getX=function()return 0 end,getY=function()return 0 end,getZ=function()return 0 end,isBlockedTo=function()return false end}
local player={getSquare=function()return origin end,getBuilding=function()return nil end,getUsername=function()return 'client1'end}
function getCell()return {getGridSquare=function(_,x,y,z)if x==1 and y==0 and z==0 then return sq end end}end
function getSprite(name)return {getName=function()return name end,getProperties=function()return {get=function()return nil end,has=function()return false end}end}end
IsoObject={new=function(_,square,sprite)
 local obj={index=-1,data={},square=square,sprite=sprite}
 function obj:getSquare()return self.square end
 function obj:getObjectIndex()return self.index end
 function obj:getSprite()return self.sprite end
 function obj:getModData()return self.data end
 function obj:setMovedThumpable(v)self.moved=v end
 function obj:isMovedThumpable()return self.moved end
 function obj:setUsesExternalWaterSource(v)self.external=v end
 function obj:getUsesExternalWaterSource()return self.external end
 function obj:getFluidContainer()return self.fluid end
 function obj:getFluidAmount()return self.fluid:getAmount()end
 function obj:getEntityScript()return self.entity end
 return obj
end}
GameEntityFactory={CreateIsoEntityFromCellLoading=function()end,CreateIsoObjectEntity=function(obj,script,first)
 assert(script==entity and first==true);obj.entity=script
 obj.fluid={amount=3,locked=true,getAmount=function(self)return self.amount end,getCapacity=function()return 15 end,
  isInputLocked=function(self)return self.locked end,setInputLocked=function(self,value)self.locked=value end,
  canAddFluid=function(self)return not self.locked end,
  Empty=function(self)self.amount=0 end,addFluid=function(self,kind,amount)assert(kind==Fluid.Water);if not self.locked then self.amount=amount end end,
  isPureFluid=function(self,kind)return self.amount>0 and kind==Fluid.Water end,canPlayerEmpty=function()return true end}
end}
local obj,spec=sink(player,'borrowed-batch')
assert(obj.entity==entity and obj:getFluidAmount()==15 and spec.capacity==15 and spec.entity==entity.name)
assert(obj.fluid:isInputLocked() and spec.inputLocked,'native input lock was not restored')
assert(F.resolveSink(spec)==obj and #objects==1)
local diagnostic=F.sinkDiagnostic(obj,spec)
assert(diagnostic.pureWater and diagnostic.fluidAmount==15 and diagnostic.objectAmount==15 and diagnostic.inputLocked and not diagnostic.canAddWater)
assert(diagnostic.hasWater=='not-exposed')
obj.fluid:setInputLocked(false)
local missing,reason=F.resolveSink(spec);assert(not missing and reason=='native-input-lock-changed')
obj.fluid:setInputLocked(true)
print('declared native finite entity setup passed')
'''
        result = subprocess.run([shutil.which('luajit'), '-', str(ROOT / 'tests/native_queue/washing/shared/QueueWashingFixture.lua'),
                                 str(ROOT / 'tests/native_queue/health/shared/QueueHealthEvents.lua')],
                                input=script, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn('declared native finite entity setup passed', result.stdout)


if __name__ == '__main__':
    unittest.main()
