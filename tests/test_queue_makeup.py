import copy
import os
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import struct
import zlib
import shutil
import subprocess

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from queue_checks.adapters import makeup as m


class MakeupEvidenceTests(unittest.TestCase):
    def selection(self,mode='toolkit',kind='sp',supplies=False,moves=False,carried_moves=False,world_moves=False,depletion_moves=False,held_moves=False):
        value= dict(suite='makeup',cases=list(m.SP_CASES if kind=='sp' else m.MP_CASES),mode=mode,kind=kind,
                    clients=1,languages=['EN'],mods=list(m.MODS),options={'mp_host':True} if kind=='mp' else {})
        if supplies:value['options']['makeup_supplies']=True;value['cases']=list(m.cases(value))
        if moves:value['options']['makeup_moves']=True;value['cases']=list(m.cases(value))
        if carried_moves:value['options']['makeup_carried_moves']=True;value['cases']=list(m.cases(value))
        if world_moves:value['options']['makeup_world_moves']=True;value['cases']=list(m.cases(value))
        if depletion_moves:value['options']['makeup_depletion_moves']=True;value['cases']=list(m.cases(value))
        if held_moves:value['options']['makeup_held_moves']=True;value['cases']=list(m.cases(value))
        return value

    def evidence(self,case,selection):
        if m.moving(selection):return self.move_evidence(case,selection)
        if selection.get('options',{}).get('makeup_supplies'):return self.supply_evidence(case,selection)
        native=selection['mode']=='native';mp=selection['kind']=='mp'
        items=dict(kit=1,front=2,tail=3,**({'old':4} if case!='apply-empty' else {}))
        types=dict(kit='Base.MakeupEyeshadow',front='Base.BookCarpentry1',tail='Base.BookFirstAid1',**({'old':m.OLD} if 'old'in items else {}))
        ids=dict(case=case,actor=7,items=items,types=types,target=m.TARGET,oldType=m.OLD,alternate=m.ALTERNATE,different=m.DIFFERENT,
                 slot=m.SLOT,otherSlot=m.OTHER_SLOT,producer='ISMakeUpUI.onApplyMakeUp',duration=1,kitUses=5,kitType='Eyes',
                 frontTotal=100,frontInitial=97,tailTotal=100,tailInitial=99)
        def worn(item,kind,slot,root):return dict(id=item,kind=kind,slot=slot,root=root,sameReference=root,container='root' if root else False)
        baseline=dict(case=case,actor=7,root=[dict(id=value,kind=types[name]) for name,value in items.items()],
                      worn=[worn(4,m.OLD,m.SLOT,True)] if 'old'in items else [],
                      kit=dict(id=1,kind=types['kit'],uses=5,maxUses=5,root=True),frontPages=97,tailPages=99)
        ids['baseline']=copy.deepcopy(baseline)
        submitted=dict(id=100,kind=m.TARGET,slot=m.SLOT,root=False,previous=items.get('old',False))
        second=dict(id=103,kind=m.ALTERNATE,slot=m.SLOT,root=False,previous=100 if native else items.get('old',False)) if case=='apply-while-preview' else False
        paid=case.startswith('apply-')or case=='cancel-waiting'and native
        output=(200 if mp else 100) if paid else False
        edit=dict(at=15,accepted=not native,bodyUnallocated=True,bodyAbsent=not native,frontSame=True,frontNative='native-front',tailRetained=True,reason=False) if case=='cancel-waiting' else False
        points=[]
        for sequence,label in enumerate(m.labels(case),1):
            value=copy.deepcopy(baseline);selected=False;render=False
            late=label in ('after-body','final')or label=='closed'and case=='apply-while-preview'
            if late:
                if paid:
                    value['root'].append(dict(id=output,kind=m.TARGET));value['kit']['uses']=4
                    if 'old'in items and not(native and mp):value['root']=[r for r in value['root']if r['id']!=4]
                    value['worn']=[worn(output,m.TARGET,m.SLOT,True)]
                if mp and(case.startswith('apply-')or case=='cancel-waiting'):value['frontPages']=100
                if label=='final':value['tailPages']=100
            if label in ('preview','same-preview','different-preview','overlap-preview'):
                selected=copy.deepcopy(submitted if label=='preview' else second if label=='overlap-preview' else
                    dict(id=101 if label=='same-preview'else 102,kind=m.ALTERNATE if label=='same-preview'else m.DIFFERENT,
                         slot=m.SLOT if label=='same-preview'else m.OTHER_SLOT,root=False,previous=items.get('old',False) if label=='same-preview'else False))
                render=dict(ok=True,actorUnchanged=True,selected=selected['id'],uiType='UI3DModel',source='native-worn'if native else'toolkitMakeupAvatarPreview',nativeRendered=True,stableFrames=3,stableMs=500)
                if native:
                    value['worn']=[r for r in value['worn']if r['slot']!=selected['slot']]
                    value['worn'].append(worn(selected['id'],selected['kind'],selected['slot'],False))
            if native and label=='location-cleared':value['worn']=[]
            if native and mp and label=='location-cleared':value['worn']=[worn(101,m.ALTERNATE,m.SLOT,False)]
            if native and mp and case=='preview-location'and label in ('closed','final'):
                value['worn'].append(worn(102,m.DIFFERENT,m.OTHER_SLOT,False))
            if native and label=='cancelled':value['worn']=[worn(100,m.TARGET,m.SLOT,False)]
            if native and case=='apply-while-preview'and label in ('closed','final'):value['worn']=[worn(100,m.TARGET,m.SLOT,False)]
            if case=='apply-while-preview'and label=='after-body':selected=copy.deepcopy(second)
            value['root'].sort(key=lambda r:r['id']);value['worn'].sort(key=lambda r:r['slot'])
            local=dict(case=case,label=label,sequence=sequence,at=sequence*10,snapshot=copy.deepcopy(value),preview=selected,render=render,
                       bodyUnallocated=not(mp and paid and late),edit=copy.deepcopy(edit) if label in ('cancelled','after-body','final')else False)
            remote=dict(case=case,label=label,sequence=sequence,at=sequence*10+1,snapshot=copy.deepcopy(value))
            if native and mp and case=='preview-close'and label=='preview':remote['snapshot']['worn']=copy.deepcopy(baseline['worn'])
            points.append(dict(client=local,authority=remote))
        receipt=dict(case=case,sequence=len(points),snapshot=copy.deepcopy(points[-1]['authority']['snapshot']))
        body=False;outcomes=[]
        if mp and(case.startswith('apply-')or case=='cancel-waiting'):
            body=dict(duration=1,starts=int(paid),finishes=[dict(phase='perform',succeeded=True,at=90)]if paid else[],nativeRef='native-body'if paid else False)
            if paid:
                outcomes=[dict(protocol=1,player=7,transaction=9,kind='ISApplyMakeUp',token='00000000-0000-0000-0000-000000000001',state=v)for v in ('started','completed')]
        before_tail=copy.deepcopy(points[-1]['client']['snapshot']);before_tail['tailPages']=99
        return dict(event='case',suite='makeup',kind=selection['kind'],mode=selection['mode'],actor='client1',id=case,status='passed',ids=ids,
                    checkpoints=points,receipt=receipt,clientFinal=copy.deepcopy(points[-1]['client']['snapshot']),submitted=submitted,second=second,
                    output=output,body=body,outcomes=outcomes,edit=edit,beforeTail=dict(at=100,snapshot=before_tail),nativeMethodsUnchanged=True)

    def supply_evidence(self,case,selection):
        source_selection=copy.deepcopy(selection);source_selection['options'].pop('makeup_supplies')
        row=self.evidence('cancel-waiting' if m.cancelling(case) else 'apply-replace',source_selection)
        kind=case.split('-',1)[1]
        world=False;ancestors=[];contents=[dict(id=1,kind='Base.MakeupEyeshadow'),dict(id=15,kind='Base.Pencil')]
        if kind in ('worn-bag','nested-bag'):
            ancestors=[dict(id=10,kind='Base.Bag_Schoolbag',parent='root')]
            if kind=='nested-bag':ancestors.append(dict(id=11,kind='Base.Bag_Schoolbag',parent=10))
        else:
            world=dict(kind=kind,x=11,y=20,z=0,index=1,owner='owned-native-source',type='Base.Bag_Schoolbag' if kind=='world-bag' else 'crate')
            if kind=='world-bag':world['id']=12
            else:world.update(sprite='carpentry_01_16',containerIndex=0)
        spec=dict(kind=kind,world=world,ancestors=ancestors)
        source=dict(kind=kind,world=copy.deepcopy(world),ancestors=[],items=contents,access=dict(blocked=False) if world else False)
        for i,ancestor in enumerate(ancestors):
            members=contents if i==len(ancestors)-1 else [dict(id=11,kind='Base.Bag_Schoolbag'),dict(id=16,kind='Base.Pencil')]
            source['ancestors'].append(dict(ancestor,items=copy.deepcopy(members)))
        row['id']=case;row['ids']['case']=case;row['ids']['supply']=spec;row['ids']['placement']=dict(x=10,y=20,z=0)
        row['applyQueues']=dict(before=dict(types=[],hasTimedActions=False,nativeActions=0),after=dict(
            types=(['ISReadABook'] if m.cancelling(case) else [])+['ISApplyMakeUp'] if selection['kind']=='mp' else [],
            hasTimedActions=selection['kind']=='mp',nativeActions=int(selection['kind']=='mp')))
        row['supplyTransferStarts']=0
        values=[row['ids']['baseline'],row['clientFinal'],row['receipt']['snapshot'],row['beforeTail']['snapshot']]
        for point in row['checkpoints']:
            for role in ('client','authority'):
                point[role]['case']=case;values.append(point[role]['snapshot'])
        row['receipt']['case']=case
        for value in values:
            value['case']=case;value['kit']['root']=False
            value['root']=[item for item in value['root'] if item['id']!=1]
            if ancestors:
                value['root'].append(dict(id=10,kind='Base.Bag_Schoolbag'))
                value['worn'].append(dict(id=10,kind='Base.Bag_Schoolbag',slot='base:back',root=True,sameReference=True,container='root'))
            value['root'].sort(key=lambda item:item['id']);value['worn'].sort(key=lambda item:item['slot'])
            value['supply']=copy.deepcopy(source);value['placement']=dict(tile=dict(x=10,y=20,z=0),square=dict(x=10,y=20,z=0))
            if not m.cancelling(case):value['frontPages']=row['ids']['frontInitial']
        return row

    def move_evidence(self,case,selection):
        base=copy.deepcopy(selection);base['options'].pop('makeup_moves',None);base['options'].pop('makeup_carried_moves',None);base['options'].pop('makeup_world_moves',None);base['options'].pop('makeup_depletion_moves',None);base['options'].pop('makeup_held_moves',None)
        if case in m.MOVE_SUPPLIES:
            base['options']['makeup_supplies']=True;row=self.supply_evidence('apply-'+m.MOVE_SUPPLIES[case],base)
        else:row=self.evidence('apply-replace' if case=='move-earlier' else 'apply-empty',base)
        kind=m.MOVE_KINDS[case]
        ids=row['ids'];row['id']=ids['case']=case;ids['move']=True;ids['placement']=dict(x=10,y=20,z=0)
        ids['items']['middle']=5;ids['types']['middle']='Base.BookCooking1';ids['middleTotal']=100;ids['middleInitial']=99;ids['frontInitial']=97 if case in m.MOVE_SUPPLIES or case in m.DEPLETION_MOVE_CASES or case in m.HELD_MOVE_CASES else 92
        if case in m.MOVE_SUPPLIES:ids['items'].pop('old');ids['types'].pop('old');row['submitted']['previous']=False;row.pop('applyQueues')
        if case in m.FINAL_USE_CASES:ids['depletion']=True;ids['kitUses']=1
        held=m.HELD_SPECS.get(case)
        if held:
            ids['held']=True;ids['handSpec']=dict(initial=copy.deepcopy(held['initial']),post=copy.deepcopy(held['post']))
            if any(v=='hammer' for phase in ('initial','post') for v in held[phase].values()):ids['items']['hammer']=6;ids['types']['hammer']='Base.Hammer'
        if kind=='deny-writer':ids['items']['writer']=6;ids['types']['writer']='Base.Socks_Ankle'
        values=[ids['baseline'],row['clientFinal'],row['receipt']['snapshot'],row['beforeTail']['snapshot']]
        for point in row['checkpoints']:
            for role in ('client','authority'):point[role]['case']=case;values.append(point[role]['snapshot'])
            if case in m.MOVE_SUPPLIES and point['client']['preview']:point['client']['preview']['previous']=False
        row['receipt']['case']=case
        for value in values:
            value['case']=case;value['root'].append(dict(id=5,kind='Base.BookCooking1'))
            value['placement']=dict(tile=dict(x=10,y=20,z=0),square=dict(x=10,y=20,z=0))
            late=value['kit']['uses']==4
            value['frontPages']=100 if late else ids['frontInitial'];value['middlePages']=100 if late else 99
            if case in m.MOVE_SUPPLIES:value['root']=[v for v in value['root'] if v['id']!=4];value['worn']=[v for v in value['worn'] if v['id']!=4]
            if kind=='deny-writer':
                # The native actor already wears another sock item. Wear replaces
                # its slot while preserving both physical items in root.
                value['root'].extend([dict(id=6,kind='Base.Socks_Ankle'),dict(id=7,kind='Base.Socks_Ankle')])
                value['worn'].append(dict(id=6 if late else 7,kind='Base.Socks_Ankle',slot='base:socks',root=True,sameReference=True,container='root'))
            if held and 'hammer' in ids['items']:value['root'].append(dict(id=6,kind='Base.Hammer'))
            if case in m.FINAL_USE_CASES:
                if late:
                    value['kit']=False;value['root']=[v for v in value['root'] if v['id']!=1]
                    if 'supply' in value:
                        value['supply']['items']=[v for v in value['supply']['items'] if v['id']!=1]
                        for ancestor in value['supply']['ancestors']:ancestor['items']=[v for v in ancestor['items'] if v['id']!=1]
                else:value['kit']['uses']=1
            if held:value['hands']=m.expected_hands(ids,'post' if late else 'initial')
            value['root'].sort(key=lambda v:v['id']);value['worn'].sort(key=lambda v:v['slot'])
        before,after,starts,accepted=m.move_orders(case,selection['mode']=='toolkit')
        edit=dict(at=25,accepted=accepted,reason=False if accepted or selection['mode']=='native' else 'dependent',before=before,after=after,
            bodyUnallocated=True,ownershipPreserved=True,frontPages=ids['frontInitial']+1,frontDelta=1/(ids['frontTotal']-ids['frontInitial']),frontNativeBefore='native-front',frontNativeAfter='native-front',frontRetained=True,tailRetained=True)
        if held:edit['hands']=copy.deepcopy(m.expected_hands(ids,'initial'))
        row['edit']=edit;row['startOrder']=starts;row['supplyTransferStarts']=0
        if kind=='deny-equip':row['equipWriter']=dict(item=ids['items']['hammer'],primary=True,twoHands=False,duration=50,starts=1,nativeRef='native-equip-writer',finishes=[dict(phase='perform',succeeded=True,at=80)])
        if kind=='deny-walk':
            origin=copy.deepcopy(ids['placement']);out=dict(x=8,y=20,z=0)
            ids['walk']=dict(origin=origin,via=dict(x=9,y=20,z=0),out=out,source=copy.deepcopy(ids['supply']['world']))
            def witness(at,tile):return dict(at=at,placement=dict(tile=copy.deepcopy(tile),square=copy.deepcopy(tile)),
                source=copy.deepcopy(ids['baseline']['supply']),kit=dict(ids['baseline']['kit'],uses=4))
            row['walk']=dict(out=dict(duration=-1,starts=1,dequeues=1,nativeRef='native-walk-out',finishes=[dict(phase='perform',succeeded=True,at=26)],dequeuedAt=27),
                back=dict(duration=-1,starts=1,dequeues=1,nativeRef='native-walk-back',finishes=[dict(phase='perform',succeeded=True,at=28)],dequeuedAt=29),
                outEndpoint=witness(27,out),returnedOrigin=witness(29,origin))
        if kind=='promote' and accepted:row['readerResume']=dict(pages=ids['frontInitial']+1,resumedPages=ids['frontInitial']+1,native='native-resumed-front')
        for point in row['checkpoints']:
            if point['client']['label'] in ('after-body','final'):point['client']['edit']=copy.deepcopy(edit)
        return row

    def write(self,root,selection,rows):
        def raw(marker,row):return m.PREFIX+marker+' '+json.dumps(row)+'\n'
        def event(row):return '[QUEUE_CHECK] '+json.dumps(row)+'\n'
        context=dict(suite='makeup',kind=selection['kind'],mode=selection['mode'],actor='client1')
        client=event(dict(context,event='setup',cases=selection['cases'],queueEnabled=selection['mode']=='toolkit',nativeDurations=True,avatarSupported=True,captureSupported=True))
        authority=''
        for row in rows:
            authority+=raw('PREPARED',row['ids'])
            for point in row['checkpoints']:
                client+=raw('CLIENT_SNAPSHOT',point['client']);authority+=raw('SNAPSHOT',point['authority'])
            if row.get('walk'):
                for label in ('outEndpoint','returnedOrigin'):client+=raw('WALK',dict(case=row['id'],label=label,evidence=row['walk'][label]))
            for outcome in row['outcomes']:client+=raw('OUTCOME',dict(case=row['id'],receipt=outcome))
            if row['edit']:client+=raw('EDIT',dict(case=row['id'],evidence=row['edit']))
            if row.get('applyQueues'):client+=raw('APPLY_QUEUES',dict(case=row['id'],evidence=row['applyQueues']))
            client+=raw('BEFORE_TAIL',dict(case=row['id'],evidence=row['beforeTail']))
            authority+=raw('VERIFIED',row['receipt'])
            if selection['kind']=='sp':client+=authority;authority=''
            client+=event(row)
        client+=event(dict(context,event='complete',cases=selection['cases'],performed=len(rows),failed=0,skipped=0))
        client+=raw('COMPLETE',dict(cases=selection['cases']))
        filename='makeup-preview-'+selection['kind']+'-'+selection['mode']+'.png'
        client+=raw('SCREENSHOT',dict(case=selection['cases'][0],file=filename,renderFrames=3,renderMs=500,fadeClear=True,nativeRendered=True))
        image=root/'client1/Screenshots'/filename;image.parent.mkdir(parents=True,exist_ok=True)
        def chunk(kind,body):return struct.pack('>I',len(body))+kind+body+struct.pack('>I',zlib.crc32(kind+body))
        image.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',128,128,8,2,0,0,0))
            +chunk(b'IDAT',zlib.compress((b'\0'+b'\0'*384)*128))+chunk(b'IEND',b''))
        (root/'client1-launch.log').write_text(client)
        if selection['kind']=='mp':(root/'server-launch.log').write_text(authority)

    def verify(self,selection,rows):
        with tempfile.TemporaryDirectory()as directory:
            root=Path(directory);self.write(root,selection,rows);return m.verify(root,selection,{})

    def test_all_canonical_sp_host_and_native_controls(self):
        for kind in ('sp','mp'):
            for mode in ('toolkit','native'):
                with self.subTest(kind=kind,mode=mode):
                    selection=self.selection(mode,kind);rows=[self.evidence(case,selection)for case in selection['cases']]
                    result=self.verify(selection,rows)
                    self.assertEqual(result['issues'],[])
                    self.assertTrue(all(row['status']=='passed'for row in result['outcomes']))

    def test_own_identity_conservation_cost_and_renderer_falsifications_fail(self):
        for kind in ('sp','mp'):
            selection=self.selection(kind=kind)
            for mutation in ('root-preview','worn-preview','cost-preview','render-false','render-source','old-lost','kit-id','duplicate-root','tail-early',
                             'paid-output-lost','output-alias','old-resurrect','extra-output','tail-short','actor','source'):
                with self.subTest(kind=kind,mutation=mutation):
                    rows=[self.evidence(case,selection)for case in selection['cases']]
                    row=rows[0]if mutation in ('root-preview','worn-preview','cost-preview','render-false','render-source','old-lost','kit-id','duplicate-root','tail-early')else rows[3]
                    preview=row['checkpoints'][1]['client'];final=row['checkpoints'][-1]['client']['snapshot']
                    if mutation=='root-preview':preview['snapshot']['root'].append(dict(id=100,kind=m.TARGET))
                    elif mutation=='worn-preview':preview['snapshot']['worn']=[dict(id=100,kind=m.TARGET,slot=m.SLOT,root=False,sameReference=False,container=False)]
                    elif mutation=='cost-preview':preview['snapshot']['kit']['uses']=4
                    elif mutation=='render-false':preview['render']['ok']=False
                    elif mutation=='render-source':preview['render']['source']='double'
                    elif mutation=='old-lost':preview['snapshot']['root']=[r for r in preview['snapshot']['root']if r['id']!=4]
                    elif mutation=='kit-id':preview['snapshot']['kit']['id']=88
                    elif mutation=='duplicate-root':preview['snapshot']['root'].append(copy.deepcopy(preview['snapshot']['root'][0]))
                    elif mutation=='tail-early':preview['snapshot']['tailPages']=100
                    elif mutation=='paid-output-lost':final['root']=[r for r in final['root']if r['id']!=row['output']]
                    elif mutation=='output-alias':row['output']=1
                    elif mutation=='old-resurrect':final['root'].append(dict(id=4,kind=m.OLD));final['root'].sort(key=lambda r:r['id'])
                    elif mutation=='extra-output':final['root'].append(dict(id=999,kind=m.TARGET))
                    elif mutation=='tail-short':final['tailPages']=99
                    elif mutation=='actor':final['actor']=8
                    elif mutation=='source':row['nativeMethodsUnchanged']=False
                    self.assertTrue(self.verify(selection,rows)['issues'])

    def test_host_receipt_cancel_and_overlap_cannot_be_forged(self):
        selection=self.selection(kind='mp')
        for mutation in ('cancel-start','cancel-complete','cancel-tail','cancel-denied','overlap-unrendered','overlap-id','overlap-stale-close',
                         'duration','receipt-missing','receipt-replay','receipt-token','authority-preview','authority-root','frame-unrendered','frame-unstable'):
            with self.subTest(mutation=mutation):
                rows=[self.evidence(case,selection)for case in selection['cases']];cancel,overlap=rows[4:6]
                if mutation=='cancel-start':cancel['body']['starts']=1
                elif mutation=='cancel-complete':cancel['outcomes']=[dict(state='completed')]
                elif mutation=='cancel-tail':cancel['edit']['tailRetained']=False
                elif mutation=='cancel-denied':cancel['edit']['accepted']=False
                elif mutation=='overlap-unrendered':overlap['checkpoints'][2]['client']['render']=False
                elif mutation=='overlap-id':overlap['second']['id']=100
                elif mutation=='overlap-stale-close':overlap['checkpoints'][-1]['client']['snapshot']['worn'][0]['id']=100
                elif mutation=='duration':overlap['body']['duration']=0
                elif mutation=='receipt-missing':overlap['outcomes'].pop()
                elif mutation=='receipt-replay':overlap['outcomes'].append(copy.deepcopy(overlap['outcomes'][-1]))
                elif mutation=='receipt-token':overlap['outcomes'][-1]['token']='00000000-0000-0000-0000-000000000002'
                elif mutation=='authority-preview':overlap['checkpoints'][1]['authority']['snapshot']['worn'][0]['id']=100
                elif mutation=='authority-root':overlap['receipt']['snapshot']['root']=[r for r in overlap['receipt']['snapshot']['root']if r['id']!=200]
                elif mutation=='frame-unrendered':overlap['checkpoints'][2]['client']['render']['nativeRendered']=False
                elif mutation=='frame-unstable':overlap['checkpoints'][2]['client']['render']['stableMs']=499
                self.assertTrue(self.verify(selection,rows)['issues'])

    def test_native_paid_root_gap_is_not_waived(self):
        selection=self.selection('native','mp')
        for case in m.MP_CASES[2:]:
            with self.subTest(case=case):
                rows=[self.evidence(selected,selection)for selected in selection['cases']]
                row=next(row for row in rows if row['id']==case)
                for point in row['checkpoints']:
                    if point['client']['label']in ('after-body','closed','final'):
                        value=point['client']['snapshot'];value['root']=[r for r in value['root']if r['id']!=row['output']]
                        for worn in value['worn']:
                            if worn['id']==row['output']:worn.update(root=False,sameReference=False,container=False)
                row['clientFinal']=copy.deepcopy(row['checkpoints'][-1]['client']['snapshot'])
                self.assertTrue(self.verify(selection,rows)['issues'])

    def test_native_host_reference_alias_controls_are_explicit_and_bounded(self):
        selection=self.selection('native','mp');rows=[self.evidence(case,selection)for case in selection['cases']]
        outcomes=self.verify(selection,rows)['outcomes']
        self.assertEqual(outcomes[0]['outcome']['nativeControlBaseline'],[
            dict(label='preview',role='authority',reason='initial-preview-send-ready-gated')])
        self.assertEqual(outcomes[1]['outcome']['nativeControlBaseline'],[
            dict(label=label,role=role,reason='native-selected-reference-not-worn')
            for label in ('location-cleared','closed','final')for role in ('client','authority')])
        for mutation in ('initial-foreign','wrong-retained-id','wrong-retained-type','physical-preview','charged-preview','wrong-final-id'):
            with self.subTest(mutation=mutation):
                changed=copy.deepcopy(rows);first,location=changed[:2]
                cleared=location['checkpoints'][3]['client']['snapshot']
                if mutation=='initial-foreign':first['checkpoints'][1]['authority']['snapshot']['worn'][0]['id']=777
                elif mutation=='wrong-retained-id':cleared['worn'][0]['id']=100
                elif mutation=='wrong-retained-type':cleared['worn'][0]['kind']=m.TARGET
                elif mutation=='physical-preview':cleared['root'].append(dict(id=101,kind=m.ALTERNATE))
                elif mutation=='charged-preview':cleared['kit']['uses']=4
                elif mutation=='wrong-final-id':location['checkpoints'][-1]['authority']['snapshot']['worn'][-1]['id']=100
                self.assertTrue(self.verify(selection,changed)['issues'])

    def test_native_alias_control_does_not_allow_toolkit_or_sp_preview_writes(self):
        for mode,kind in [('toolkit','mp'),('native','sp')]:
            with self.subTest(mode=mode,kind=kind):
                selection=self.selection(mode,kind);rows=[self.evidence(case,selection)for case in selection['cases']]
                point=rows[1]['checkpoints'][3]['client']['snapshot']
                point['worn']=[dict(id=101,kind=m.ALTERNATE,slot=m.SLOT,root=False,sameReference=False,container=False)]
                self.assertTrue(self.verify(selection,rows)['issues'])

    def test_native_unaliased_removal_and_delivered_initial_preview_remain_valid(self):
        selection=self.selection('native','mp');rows=[self.evidence(case,selection)for case in selection['cases']]
        rows[0]['checkpoints'][1]['authority']['snapshot']=copy.deepcopy(rows[0]['checkpoints'][1]['client']['snapshot'])
        location=rows[1]
        for point in location['checkpoints']:
            label=point['client']['label']
            if label not in ('location-cleared','closed','final'):continue
            for role in ('client','authority'):
                value=point[role]['snapshot']
                value['worn']=[]if label=='location-cleared'else copy.deepcopy(location['ids']['baseline']['worn'])
        location['clientFinal']=copy.deepcopy(location['checkpoints'][-1]['client']['snapshot'])
        location['receipt']['snapshot']=copy.deepcopy(location['checkpoints'][-1]['authority']['snapshot'])
        self.assertEqual(self.verify(selection,rows)['issues'],[])

    def test_raw_markers_order_and_failure_are_required(self):
        selection=self.selection(kind='mp');rows=[self.evidence(case,selection)for case in selection['cases']]
        for mutation in ('authority-missing','client-marker-duplicate','server-order','client-order','failure','renderer-failure','completion','setup-cases','shot-missing','shot-unrendered','shot-unstable','png-missing','png-corrupt'):
            with self.subTest(mutation=mutation),tempfile.TemporaryDirectory()as directory:
                root=Path(directory);self.write(root,selection,rows)
                path=root/('server-launch.log'if mutation in ('authority-missing','server-order')else'client1-launch.log')
                lines=path.read_text().splitlines()
                if mutation=='authority-missing':lines=[line for line in lines if m.PREFIX+'PREPARED 'not in line]
                elif mutation=='client-marker-duplicate':lines.append(next(line for line in lines if m.PREFIX+'CLIENT_SNAPSHOT 'in line))
                elif mutation=='server-order':lines[0],lines[1]=lines[1],lines[0]
                elif mutation=='client-order':
                    a=next(i for i,line in enumerate(lines)if m.PREFIX+'CLIENT_SNAPSHOT 'in line)
                    b=next(i for i,line in enumerate(lines)if '"event": "case"'in line)
                    lines.insert(a,lines.pop(b))
                elif mutation=='failure':lines.append('[QUEUE_TEST] FAIL makeup source failed')
                elif mutation=='renderer-failure':lines.append(m.PREFIX+'RENDER_FAILURE '+json.dumps(dict(case='preview-close',error='bad renderer')))
                elif mutation=='completion':lines=[line for line in lines if m.PREFIX+'COMPLETE 'not in line]
                elif mutation=='setup-cases':
                    setup=json.loads(lines[0].split('[QUEUE_CHECK] ',1)[1]);setup['cases']=[];lines[0]='[QUEUE_CHECK] '+json.dumps(setup)
                if mutation=='shot-missing':lines=[line for line in lines if m.PREFIX+'SCREENSHOT 'not in line]
                elif mutation in ('shot-unrendered','shot-unstable'):
                    i=next(i for i,line in enumerate(lines)if m.PREFIX+'SCREENSHOT 'in line)
                    shot=json.loads(lines[i].split(m.PREFIX+'SCREENSHOT ',1)[1])
                    if mutation=='shot-unrendered':shot['nativeRendered']=False
                    else:shot['renderMs']=499
                    lines[i]=m.PREFIX+'SCREENSHOT '+json.dumps(shot)
                elif mutation in ('png-missing','png-corrupt'):
                    image=root/'client1/Screenshots'/('makeup-preview-'+selection['kind']+'-'+selection['mode']+'.png')
                    if mutation=='png-missing':image.unlink()
                    else:image.write_bytes(b'not-a-png')
                path.write_text('\n'.join(lines)+'\n')
                self.assertTrue(m.verify(root,selection,{})['issues'])

    def test_selection_requires_order_full_pack_fresh_host_and_no_sp_cancel(self):
        for mutation in ('order','subset','duplicate','sp-cancel','mods','language','clients','world','not-host'):
            selection=self.selection(kind='mp')
            if mutation=='order':selection['cases'].reverse()
            elif mutation=='subset':selection['cases']=selection['cases'][:1]
            elif mutation=='duplicate':selection['cases'][1]=selection['cases'][0]
            elif mutation=='sp-cancel':selection['kind']='sp'
            elif mutation=='mods':selection['mods'].pop()
            elif mutation=='language':selection['languages']=['RU']
            elif mutation=='clients':selection['clients']=2
            elif mutation=='world':selection['options']['world_template']='old'
            elif mutation=='not-host':selection['options']['mp_host']=False
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):m.validate(selection)

    def test_optional_supply_bank_sp_host_native_and_toolkit(self):
        for kind in ('sp','mp'):
            for mode in ('native','toolkit'):
                selection=self.selection(mode,kind,supplies=True)
                with self.subTest(kind=kind,mode=mode):
                    rows=[self.evidence(case,selection) for case in selection['cases']]
                    self.assertEqual(self.verify(selection,rows)['issues'],[])

    def test_supply_ancestor_member_source_and_empty_queue_falsifications_fail(self):
        selection=self.selection(kind='mp',supplies=True)
        for mutation in ('ancestor-id','ancestor-parent','ancestor-type','ancestor-member','ancestor-root-alias','ancestor-member-alias','ancestor-wrong-slot','source-member','source-reorder',
                         'source-duplicate','source-moved-root','source-world-id','source-world-owner','kit-cost',
                         'queue-front','queue-native','queue-active','queue-transfer','transfer-start','output-lost','output-reference','tail-front'):
            with self.subTest(mutation=mutation):
                rows=[self.evidence(case,selection) for case in selection['cases']]
                row=rows[3] if mutation.startswith('source-world') else rows[1]
                point=row['checkpoints'][2]['authority']['snapshot'];source=point['supply']
                if mutation=='ancestor-id':source['ancestors'][0]['id']=999
                elif mutation=='ancestor-parent':source['ancestors'][1]['parent']=999
                elif mutation=='ancestor-type':source['ancestors'][1]['kind']='Base.Bag_DuffelBagTINT'
                elif mutation=='ancestor-member':source['ancestors'][0]['items'].pop()
                elif mutation=='ancestor-root-alias':point['root'].append(dict(id=11,kind='Base.Bag_Schoolbag'));point['root'].sort(key=lambda item:item['id'])
                elif mutation=='ancestor-member-alias':source['ancestors'][0]['items'].append(dict(id=15,kind='Base.Pencil'));source['ancestors'][0]['items'].sort(key=lambda item:item['id'])
                elif mutation=='ancestor-wrong-slot':next(item for item in point['worn'] if item['id']==10)['slot']='base:hat'
                elif mutation=='source-member':source['items'].pop()
                elif mutation=='source-reorder':source['items'].reverse()
                elif mutation=='source-duplicate':source['items'].append(copy.deepcopy(source['items'][0]))
                elif mutation=='source-moved-root':point['root'].append(dict(id=1,kind='Base.MakeupEyeshadow'));point['kit']['root']=True
                elif mutation=='source-world-id':source['world']['id']=999
                elif mutation=='source-world-owner':source['world']['owner']='foreign-owner'
                elif mutation=='kit-cost':point['kit']['uses']=3
                elif mutation=='queue-front':row['applyQueues']['before']['types']=['ISReadABook']
                elif mutation=='queue-native':row['applyQueues']['before']['nativeActions']=1
                elif mutation=='queue-active':row['applyQueues']['before']['hasTimedActions']=True
                elif mutation=='queue-transfer':row['applyQueues']['after']['types'].insert(0,'ISInventoryTransferAction')
                elif mutation=='transfer-start':row['supplyTransferStarts']=1
                elif mutation=='output-lost':point['root']=[item for item in point['root'] if item['id']!=row['output']]
                elif mutation=='output-reference':next(item for item in point['worn'] if item['id']==row['output'])['sameReference']=False
                elif mutation=='tail-front':row['checkpoints'][-1]['client']['snapshot']['frontPages']=100
                self.assertTrue(self.verify(selection,rows)['issues'])

    def test_supply_settled_placement_and_adjacent_unblocked_world_sources_are_required(self):
        selection=self.selection(kind='mp',supplies=True)
        for mutation in ('target-missing','position-missing','stale-current-square','stale-floor-coordinate',
                         'authority-position','later-tile','world-distance','world-level','world-wall'):
            with self.subTest(mutation=mutation):
                rows=[self.evidence(case,selection) for case in selection['cases']];row=rows[2]
                point=row['checkpoints'][1]['client']['snapshot']
                if mutation=='target-missing':row['ids'].pop('placement')
                elif mutation=='position-missing':point.pop('placement')
                elif mutation=='stale-current-square':point['placement']['square']['y']-=1
                elif mutation=='stale-floor-coordinate':point['placement']['tile']['y']-=1
                elif mutation=='authority-position':row['checkpoints'][1]['authority']['snapshot']['placement']['square']['x']-=1
                elif mutation=='later-tile':
                    row['ids']['placement']['y']+=1
                    for value in [row['ids']['baseline'],row['clientFinal'],row['receipt']['snapshot'],row['beforeTail']['snapshot'],
                                  *[p[role]['snapshot'] for p in row['checkpoints'] for role in ('client','authority')]]:
                        value['placement']['tile']['y']+=1;value['placement']['square']['y']+=1
                        value['supply']['world']['y']+=1
                    row['ids']['supply']['world']['y']+=1
                elif mutation in ('world-distance','world-level'):
                    axis='x' if mutation=='world-distance' else 'z'
                    row['ids']['supply']['world'][axis]+=1
                    for value in [row['ids']['baseline'],row['clientFinal'],row['receipt']['snapshot'],row['beforeTail']['snapshot'],
                                  *[p[role]['snapshot'] for p in row['checkpoints'] for role in ('client','authority')]]:
                        value['supply']['world'][axis]+=1
                else:point['supply']['access']['blocked']=True
                self.assertTrue(self.verify(selection,rows)['issues'])

    def test_supply_native_cancel_and_authority_receipts_remain_strict(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',supplies=True)
            for mutation in ('cancel-cost','cancel-output','cancel-body','authority-source','queue-boundary-missing'):
                with self.subTest(mode=mode,mutation=mutation):
                    rows=[self.evidence(case,selection) for case in selection['cases']];row=rows[4]
                    if mutation=='cancel-cost':row['checkpoints'][-1]['client']['snapshot']['kit']['uses']=3
                    elif mutation=='cancel-output':row['output']=999
                    elif mutation=='cancel-body':row['body']['starts']=1-int(mode=='native')
                    elif mutation=='authority-source':row['receipt']['snapshot']['supply']['items'].pop()
                    else:row.pop('applyQueues')
                    self.assertTrue(self.verify(selection,rows)['issues'])

    def test_supply_cases_register_without_relabeling_old_bank_contracts(self):
        from queue_checks import scenarios
        suite=m.definitions()['makeup'];scenarios.validate(suite)
        checks=suite['scenario_actions']['native-makeup-ui']['checks']
        self.assertEqual(list(checks['success-queued']),m.MP_CASES)
        self.assertEqual(list(checks['success-empty']),m.SUPPLY_SP_CASES)
        self.assertEqual(list(checks['cancel-waiting']),['cancel-waiting',*m.SUPPLY_MP_CASES[4:]])
        self.assertEqual([case['id'] for case in suite['cases']],m.MP_CASES+m.SUPPLY_MP_CASES+m.MOVE_CASES+m.CARRIED_MOVE_CASES+m.WORLD_MOVE_CASES+m.DEPLETION_MOVE_CASES+m.HELD_MOVE_CASES)

    def test_supply_option_cannot_silently_replace_or_mix_default_bank(self):
        for mutation in ('false','non-bool','missing','mixed'):
            selection=self.selection(supplies=True)
            if mutation=='false':selection['options']['makeup_supplies']=False
            elif mutation=='non-bool':selection['options']['makeup_supplies']='true'
            elif mutation=='missing':selection['options'].pop('makeup_supplies')
            else:selection['cases'][0]=m.SP_CASES[0]
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):m.validate(selection)

    def test_optional_moves_host_controls_and_toolkit(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',moves=True);rows=[self.evidence(case,selection) for case in selection['cases']]
            with self.subTest(mode=mode):self.assertEqual(self.verify(selection,rows)['issues'],[])

    def test_optional_carried_moves_host_controls_and_toolkit(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',carried_moves=True)
            rows=[self.evidence(case,selection) for case in selection['cases']]
            with self.subTest(mode=mode):self.assertEqual(self.verify(selection,rows)['issues'],[])

    def test_carried_move_bank_is_explicit_host_only_and_exclusive(self):
        for mutation in ('sp','missing','false','string','root','supply','order','subset','host','mods'):
            selection=self.selection(kind='mp',carried_moves=True)
            if mutation=='sp':selection['kind']='sp'
            elif mutation=='missing':selection['options'].pop('makeup_carried_moves')
            elif mutation=='false':selection['options']['makeup_carried_moves']=False
            elif mutation=='string':selection['options']['makeup_carried_moves']='true'
            elif mutation=='root':selection['options']['makeup_moves']=True
            elif mutation=='supply':selection['options']['makeup_supplies']=True
            elif mutation=='order':selection['cases'].reverse()
            elif mutation=='subset':selection['cases'].pop()
            elif mutation=='host':selection['options']['mp_host']=False
            else:selection['mods'].pop()
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):m.validate(selection)

    def test_carried_move_ancestry_owner_members_root_charge_and_output_are_strict(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',carried_moves=True)
            for mutation in ('ancestor-id','ancestor-parent','ancestor-type','ancestor-member','source-member','source-reorder','source-duplicate',
                             'nested-root-alias','member-root-alias','outer-worn-proxy','outer-wrong-slot','owner','placement','topology',
                             'source-missing','transfer','kit-charge','output-root-lost','output-worn-proxy','authority-output'):
                rows=[self.evidence(case,selection) for case in selection['cases']];row=rows[1]
                value=row['checkpoints'][2]['client']['snapshot'];source=value['supply']
                if mutation=='ancestor-id':source['ancestors'][0]['id']=999
                elif mutation=='ancestor-parent':source['ancestors'][1]['parent']=999
                elif mutation=='ancestor-type':source['ancestors'][1]['kind']='Base.Bag_DuffelBagTINT'
                elif mutation=='ancestor-member':source['ancestors'][0]['items'].pop()
                elif mutation=='source-member':source['items'].pop()
                elif mutation=='source-reorder':source['items'].reverse()
                elif mutation=='source-duplicate':source['items'].append(copy.deepcopy(source['items'][0]))
                elif mutation=='nested-root-alias':value['root'].append(dict(id=11,kind='Base.Bag_Schoolbag'));value['root'].sort(key=lambda v:v['id'])
                elif mutation=='member-root-alias':value['root'].append(dict(id=1,kind='Base.MakeupEyeshadow'));value['root'].sort(key=lambda v:v['id'])
                elif mutation=='outer-worn-proxy':next(v for v in value['worn'] if v['id']==10)['sameReference']=False
                elif mutation=='outer-wrong-slot':next(v for v in value['worn'] if v['id']==10)['slot']='base:hat'
                elif mutation=='owner':value['actor']=8
                elif mutation=='placement':value['placement']['square']['x']-=1
                elif mutation=='topology':row['ids']['supply']['kind']='worn-bag'
                elif mutation=='source-missing':row['ids'].pop('supply')
                elif mutation=='transfer':row['supplyTransferStarts']=1
                elif mutation=='kit-charge':value['kit']['uses']=3
                elif mutation=='output-root-lost':value['root']=[v for v in value['root'] if v['id']!=row['output']]
                elif mutation=='output-worn-proxy':next(v for v in value['worn'] if v['id']==row['output'])['sameReference']=False
                else:row['receipt']['snapshot']['worn']=[v for v in row['receipt']['snapshot']['worn'] if v['id']!=row['output']]
                with self.subTest(mode=mode,mutation=mutation):self.assertTrue(self.verify(selection,rows)['issues'])

    def test_carried_promotion_and_writer_keep_native_order_checkpoint_and_exact_clothing(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',carried_moves=True)
            for mutation in ('order','ownership','allocated','reader-pages','reader-checkpoint','reader-native','writer-admitted','writer-original-root','writer-original-worn','writer-proxy','writer-before-tail'):
                rows=[self.evidence(case,selection) for case in selection['cases']];promote=rows[2];writer=rows[3]
                if mutation=='order':promote['startOrder'].reverse()
                elif mutation=='ownership':promote['edit']['ownershipPreserved']=False
                elif mutation=='allocated':promote['edit']['bodyUnallocated']=False
                elif mutation=='reader-pages':promote['edit']['frontPages']=92
                elif mutation=='reader-checkpoint':
                    if mode=='toolkit':promote['readerResume']['resumedPages']=92
                    else:promote['readerResume']=dict(pages=93,resumedPages=93,native='manufactured')
                elif mutation=='reader-native':
                    if mode=='toolkit':promote['readerResume']['native']='native-front'
                    else:promote['edit']['frontNativeAfter']='replacement'
                elif mutation=='writer-admitted':writer['edit']['accepted']=True
                elif mutation=='writer-original-root':writer['checkpoints'][2]['authority']['snapshot']['root']=[v for v in writer['checkpoints'][2]['authority']['snapshot']['root'] if v['id']!=7]
                else:
                    value=writer['beforeTail']['snapshot'] if mutation=='writer-before-tail' else writer['checkpoints'][2]['client']['snapshot']
                    worn=next(v for v in value['worn'] if v['slot']=='base:socks')
                    if mutation=='writer-proxy':worn['sameReference']=False
                    else:worn['id']=7
                with self.subTest(mode=mode,mutation=mutation):self.assertTrue(self.verify(selection,rows)['issues'])

    def test_optional_world_moves_host_controls_and_toolkit(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',world_moves=True)
            rows=[self.evidence(case,selection) for case in selection['cases']]
            with self.subTest(mode=mode):self.assertEqual(self.verify(selection,rows)['issues'],[])

    def test_world_move_bank_is_explicit_host_only_and_exclusive(self):
        for mutation in ('sp','missing','false','string','root','carried','supply','order','subset','host','mods','language','world'):
            selection=self.selection(kind='mp',world_moves=True)
            if mutation=='sp':selection['kind']='sp'
            elif mutation=='missing':selection['options'].pop('makeup_world_moves')
            elif mutation=='false':selection['options']['makeup_world_moves']=False
            elif mutation=='string':selection['options']['makeup_world_moves']='true'
            elif mutation=='root':selection['options']['makeup_moves']=True
            elif mutation=='carried':selection['options']['makeup_carried_moves']=True
            elif mutation=='supply':selection['options']['makeup_supplies']=True
            elif mutation=='order':selection['cases'].reverse()
            elif mutation=='subset':selection['cases'].pop()
            elif mutation=='host':selection['options']['mp_host']=False
            elif mutation=='mods':selection['mods'].pop()
            elif mutation=='language':selection['languages']=['RU']
            else:selection['options']['world_template']='existing'
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):m.validate(selection)

    def test_world_source_members_owner_access_paid_identity_and_resume_are_strict(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',world_moves=True)
            for mutation in ('world-id','world-owner','world-index','world-type','world-distance','source-member','source-duplicate','source-reorder',
                             'kit-root-alias','kit-root-owner','source-blocked','placement','actor','transfer','charge','paid-root-lost','paid-worn-proxy','writer-injected','resume','start-order'):
                rows=[self.evidence(case,selection) for case in selection['cases']];row=rows[1]
                value=row['checkpoints'][2]['client']['snapshot'];world=value['supply']['world']
                if mutation=='world-id':world['id']=999
                elif mutation=='world-owner':world['owner']='foreign-source'
                elif mutation=='world-index':world['index']+=1
                elif mutation=='world-type':world['type']='Base.Bag_DuffelBagTINT'
                elif mutation=='world-distance':world['x']+=2
                elif mutation=='source-member':value['supply']['items'].pop()
                elif mutation=='source-duplicate':value['supply']['items'].append(copy.deepcopy(value['supply']['items'][0]))
                elif mutation=='source-reorder':value['supply']['items'].reverse()
                elif mutation=='kit-root-alias':value['root'].append(dict(id=1,kind='Base.MakeupEyeshadow'));value['root'].sort(key=lambda v:v['id'])
                elif mutation=='kit-root-owner':value['kit']['root']=True
                elif mutation=='source-blocked':value['supply']['access']['blocked']=True
                elif mutation=='placement':value['placement']['square']['x']-=1
                elif mutation=='actor':value['actor']=8
                elif mutation=='transfer':row['supplyTransferStarts']=1
                elif mutation=='charge':value['kit']['uses']=3
                elif mutation=='paid-root-lost':value['root']=[v for v in value['root'] if v['id']!=row['output']]
                elif mutation=='paid-worn-proxy':next(v for v in value['worn'] if v['id']==row['output'])['sameReference']=False
                elif mutation=='writer-injected':row['ids']['items']['writer']=6;row['ids']['types']['writer']='Base.Socks_Ankle'
                elif mutation=='resume':
                    if mode=='toolkit':rows[2]['readerResume']['resumedPages']=97
                    else:rows[2]['readerResume']=dict(pages=98,resumedPages=98,native='manufactured')
                else:rows[2]['startOrder'].reverse()
                with self.subTest(mode=mode,mutation=mutation):self.assertTrue(self.verify(selection,rows)['issues'])

    def test_world_walk_denial_requires_real_out_return_refs_order_and_exact_endpoints(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',world_moves=True)
            for mutation in ('admitted','before-order','after-order','start-order','walk-missing','walk-unexpected','route-origin','route-via','route-out','route-source',
                             'out-starts','back-starts','out-dequeues','back-dequeues','ref-missing','ref-shared','ref-front','duration','finish-failed','finish-duplicate',
                             'dequeue-late','out-position','back-position','out-square','out-time','source-owner','source-member','source-access','kit-charge','final-placement','raw-marker'):
                rows=[self.evidence(case,selection) for case in selection['cases']];row=rows[3];walk=row['walk']
                if mutation=='admitted':row['edit']['accepted']=True
                elif mutation=='before-order':row['edit']['before'].reverse()
                elif mutation=='after-order':row['edit']['after'].reverse()
                elif mutation=='start-order':row['startOrder'].reverse()
                elif mutation=='walk-missing':row.pop('walk')
                elif mutation=='walk-unexpected':rows[0]['walk']=copy.deepcopy(walk)
                elif mutation=='route-origin':row['ids']['walk']['origin']['x']+=1
                elif mutation=='route-via':row['ids']['walk']['via']['x']-=1
                elif mutation=='route-out':row['ids']['walk']['out']['x']+=1
                elif mutation=='route-source':row['ids']['walk']['source']['owner']='foreign-source'
                elif mutation=='out-starts':walk['out']['starts']=2
                elif mutation=='back-starts':walk['back']['starts']=0
                elif mutation=='out-dequeues':walk['out']['dequeues']=0
                elif mutation=='back-dequeues':walk['back']['dequeues']=2
                elif mutation=='ref-missing':walk['out']['nativeRef']=False
                elif mutation=='ref-shared':walk['back']['nativeRef']=walk['out']['nativeRef']
                elif mutation=='ref-front':walk['out']['nativeRef']='native-front'
                elif mutation=='duration':walk['out']['duration']=1
                elif mutation=='finish-failed':walk['back']['finishes'][0]['succeeded']=False
                elif mutation=='finish-duplicate':walk['out']['finishes'].append(copy.deepcopy(walk['out']['finishes'][0]))
                elif mutation=='dequeue-late':walk['back']['dequeuedAt']=31
                elif mutation=='out-position':walk['outEndpoint']['placement']=copy.deepcopy(walk['returnedOrigin']['placement'])
                elif mutation=='back-position':walk['returnedOrigin']['placement']=copy.deepcopy(walk['outEndpoint']['placement'])
                elif mutation=='out-square':walk['outEndpoint']['placement']['square']['x']+=1
                elif mutation=='out-time':walk['outEndpoint']['at']=24
                elif mutation=='source-owner':walk['outEndpoint']['source']['world']['owner']='foreign-source'
                elif mutation=='source-member':walk['outEndpoint']['source']['items'].pop()
                elif mutation=='source-access':walk['returnedOrigin']['source']['access']['blocked']=True
                elif mutation=='kit-charge':walk['outEndpoint']['kit']['uses']=3
                elif mutation=='final-placement':row['checkpoints'][2]['client']['snapshot']['placement']['tile']['x']-=2
                if mutation=='raw-marker':
                    with tempfile.TemporaryDirectory()as directory:
                        root=Path(directory);self.write(root,selection,rows);log=root/'client1-launch.log'
                        log.write_text('\n'.join(line for line in log.read_text().splitlines() if m.PREFIX+'WALK 'not in line)+'\n')
                        with self.subTest(mode=mode,mutation=mutation):self.assertTrue(m.verify(root,selection,{})['issues'])
                else:
                    with self.subTest(mode=mode,mutation=mutation):self.assertTrue(self.verify(selection,rows)['issues'])

    def test_final_use_moves_require_exact_physical_deletion_for_all_five_sources(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',depletion_moves=True)
            rows=[self.evidence(case,selection) for case in selection['cases']]
            result=self.verify(selection,rows)
            with self.subTest(mode=mode):
                self.assertEqual(result['issues'],[])
                self.assertTrue(all(v['outcome']['depletionVerified'] for v in result['outcomes']))

    def test_final_use_bank_requires_explicit_exclusive_host_selection(self):
        for mutation in ('sp','missing','false','string','root','carried','world-moves','supplies','order','subset','host','mods','language'):
            selection=self.selection(kind='mp',depletion_moves=True)
            if mutation=='sp':selection['kind']='sp'
            elif mutation=='missing':selection['options'].pop('makeup_depletion_moves')
            elif mutation=='false':selection['options']['makeup_depletion_moves']=False
            elif mutation=='string':selection['options']['makeup_depletion_moves']='true'
            elif mutation=='root':selection['options']['makeup_moves']=True
            elif mutation=='carried':selection['options']['makeup_carried_moves']=True
            elif mutation=='world-moves':selection['options']['makeup_world_moves']=True
            elif mutation=='supplies':selection['options']['makeup_supplies']=True
            elif mutation=='order':selection['cases'].reverse()
            elif mutation=='subset':selection['cases'].pop()
            elif mutation=='host':selection['options']['mp_host']=False
            elif mutation=='mods':selection['mods'].pop()
            else:selection['languages']=['RU']
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):m.validate(selection)

    def test_final_use_rejects_placeholders_remaining_ids_and_non_kit_source_changes(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',depletion_moves=True)
            for mutation in ('flag-missing','initial-uses','early-absent','zero-placeholder','root-retained','supply-retained','ancestor-retained',
                             'client-root-kit','authority-root-kit','moved-root','replacement-kit','sentinel-lost','ancestor-lost','world-owner','world-id',
                             'output-lost','output-proxy','output-reuses-kit','extra-output','receipt-kit','tail-early','transfer','duplicate-body','duplicate-receipt'):
                rows=[self.evidence(case,selection) for case in selection['cases']];row=rows[1]
                value=row['checkpoints'][2]['client']['snapshot']
                if mutation=='flag-missing':row['ids'].pop('depletion')
                elif mutation=='initial-uses':row['ids']['baseline']['kit']['uses']=5
                elif mutation=='early-absent':row['checkpoints'][1]['authority']['snapshot']['kit']=False
                elif mutation=='zero-placeholder':value['kit']=dict(row['ids']['baseline']['kit'],uses=0)
                elif mutation=='root-retained':rows[0]['checkpoints'][2]['client']['snapshot']['kit']=dict(rows[0]['ids']['baseline']['kit'])
                elif mutation=='supply-retained':value['supply']['items'].insert(0,dict(id=1,kind='Base.MakeupEyeshadow'))
                elif mutation=='ancestor-retained':value['supply']['ancestors'][0]['items'].insert(0,dict(id=1,kind='Base.MakeupEyeshadow'))
                elif mutation in ('client-root-kit','authority-root-kit','moved-root'):
                    actual=rows[0]['checkpoints'][2]['authority' if mutation=='authority-root-kit' else 'client']['snapshot'] if mutation!='moved-root' else value
                    actual['root'].append(dict(id=1,kind='Base.MakeupEyeshadow'));actual['root'].sort(key=lambda v:v['id'])
                elif mutation=='replacement-kit':value['supply']['items'].append(dict(id=999,kind='Base.MakeupEyeshadow'))
                elif mutation=='sentinel-lost':value['supply']['items'].clear()
                elif mutation=='ancestor-lost':value['supply']['ancestors'].pop()
                elif mutation=='world-owner':rows[2]['checkpoints'][2]['authority']['snapshot']['supply']['world']['owner']='foreign-source'
                elif mutation=='world-id':rows[3]['checkpoints'][2]['client']['snapshot']['supply']['world']['id']=999
                elif mutation=='output-lost':value['root']=[v for v in value['root'] if v['id']!=row['output']]
                elif mutation=='output-proxy':next(v for v in value['worn'] if v['id']==row['output'])['sameReference']=False
                elif mutation=='output-reuses-kit':row['output']=1
                elif mutation=='extra-output':value['root'].append(dict(id=999,kind=m.TARGET))
                elif mutation=='receipt-kit':row['receipt']['snapshot']['kit']=dict(row['ids']['baseline']['kit'])
                elif mutation=='tail-early':row['beforeTail']['snapshot']['tailPages']=100
                elif mutation=='transfer':row['supplyTransferStarts']=1
                elif mutation=='duplicate-body':row['body']['starts']=2
                else:row['outcomes'].append(copy.deepcopy(row['outcomes'][-1]))
                with self.subTest(mode=mode,mutation=mutation):self.assertTrue(self.verify(selection,rows)['issues'])

    def test_final_use_before_tail_records_real_packet_order_without_paid_projection(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',depletion_moves=True)
            for index in (0,1,3):
                for timing in ('pending-both','removed-before-output','output-before-removal','output-before-wear'):
                    rows=[self.evidence(case,selection) for case in selection['cases']];row=rows[index];ids=row['ids']
                    actual=copy.deepcopy(ids['baseline']);actual['frontPages']=ids['frontTotal'];actual['middlePages']=ids['middleTotal']
                    if timing in ('removed-before-output','output-before-wear'):
                        actual['kit']=False;actual['root']=[v for v in actual['root'] if v['id']!=1]
                        if 'supply' in actual:
                            actual['supply']['items']=[v for v in actual['supply']['items'] if v['id']!=1]
                            for ancestor in actual['supply']['ancestors']:ancestor['items']=[v for v in ancestor['items'] if v['id']!=1]
                    if timing in ('output-before-removal','output-before-wear'):
                        actual['root'].append(dict(id=row['output'],kind=m.TARGET));actual['root'].sort(key=lambda v:v['id'])
                    if timing=='output-before-removal':actual['worn'].append(dict(id=row['output'],kind=m.TARGET,slot=m.SLOT,root=True,sameReference=True,container='root'));actual['worn'].sort(key=lambda v:v['slot'])
                    row['beforeTail']['snapshot']=actual
                    with self.subTest(mode=mode,index=index,timing=timing):self.assertEqual(self.verify(selection,rows)['issues'],[])

    def test_final_use_before_tail_preserves_full_unrelated_worn_records(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',depletion_moves=True)
            for index in (0,4):
                for mutation in ('foreign-detached','lost-baseline','spoofed-reference'):
                    rows=[self.evidence(case,selection) for case in selection['cases']];row=rows[index]
                    values=[row['ids']['baseline'],row['clientFinal'],row['receipt']['snapshot'],row['beforeTail']['snapshot'],
                            *[point[role]['snapshot'] for point in row['checkpoints'] for role in ('client','authority')]]
                    for value in values:
                        value['root'].append(dict(id=8,kind='Base.Hat_Beany'));value['root'].sort(key=lambda v:v['id'])
                        value['worn'].append(dict(id=8,kind='Base.Hat_Beany',slot='base:hat',root=True,sameReference=True,container='root'))
                        value['worn'].sort(key=lambda v:v['slot'])
                    actual=row['beforeTail']['snapshot']
                    if mutation=='foreign-detached':actual['worn'].append(dict(id=999,kind='Base.Socks_Ankle',slot='zz:foreign',root=False,sameReference=False,container=False))
                    elif mutation=='lost-baseline':actual['worn']=[w for w in actual['worn'] if w['id']!=8]
                    else:
                        worn=next(w for w in actual['worn'] if w['id']==8);worn['sameReference']=False;worn['container']=False
                    with self.subTest(mode=mode,index=index,mutation=mutation):self.assertTrue(self.verify(selection,rows)['issues'])

    def test_final_use_before_tail_allows_only_known_pending_cosmetic_transitions(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',depletion_moves=True)
            for index in (0,1,2,3,4):
                for transition in ('baseline','paid','paid-proxy','wear-before-root','native-preview'):
                    rows=[self.evidence(case,selection) for case in selection['cases']];row=rows[index]
                    actual=row['beforeTail']['snapshot'];actual['worn']=[w for w in actual['worn'] if w['slot']!=m.SLOT]
                    if transition!='baseline':
                        preview=transition=='native-preview';root=transition!='wear-before-root' and not preview
                        actual['worn'].append(dict(id=row['submitted']['id'] if preview else row['output'],kind=m.TARGET,slot=m.SLOT,
                            root=root,sameReference=root and transition!='paid-proxy',container='root' if root and transition!='paid-proxy' else False))
                        actual['worn'].sort(key=lambda w:w['slot'])
                    if transition=='wear-before-root':actual['root']=[v for v in actual['root'] if v['id']!=row['output']]
                    result=self.verify(selection,rows)
                    with self.subTest(mode=mode,index=index,transition=transition):
                        if transition=='native-preview' and mode=='toolkit':self.assertTrue(result['issues'])
                        else:self.assertEqual(result['issues'],[])

    def test_final_use_before_tail_rejects_unknown_cosmetic_transition_identity(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',depletion_moves=True)
            for mutation in ('foreign-id','wrong-kind','preview-root-reference'):
                rows=[self.evidence(case,selection) for case in selection['cases']];row=rows[0]
                actual=row['beforeTail']['snapshot'];worn=next(w for w in actual['worn'] if w['slot']==m.SLOT)
                if mutation=='foreign-id':worn.update(id=999,root=False,sameReference=False,container=False)
                elif mutation=='wrong-kind':worn['kind']='Base.MakeUp_EyesShadowWhite'
                else:worn.update(id=row['submitted']['id'],root=False,sameReference=False,container='root')
                with self.subTest(mode=mode,mutation=mutation):self.assertTrue(self.verify(selection,rows)['issues'])

    def test_final_use_move_resume_writer_and_ordinary_bank_absence_remain_strict(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',depletion_moves=True)
            for mutation in ('move-order','native-order','ownership','promotion','resume','writer-admitted','writer-original','writer-proxy','ordinary-kit-false'):
                rows=[self.evidence(case,selection) for case in selection['cases']]
                if mutation=='move-order':rows[0]['edit']['after'].reverse()
                elif mutation=='native-order':rows[1]['startOrder'].reverse()
                elif mutation=='ownership':rows[0]['edit']['ownershipPreserved']=False
                elif mutation=='promotion':rows[2]['edit']['accepted']=not rows[2]['edit']['accepted']
                elif mutation=='resume':
                    if mode=='toolkit':rows[2]['readerResume']['resumedPages']=97
                    else:rows[2]['readerResume']=dict(pages=98,resumedPages=98,native='manufactured')
                elif mutation=='writer-admitted':rows[4]['edit']['accepted']=True
                elif mutation in ('writer-original','writer-proxy'):
                    sock=next(v for v in rows[4]['checkpoints'][2]['client']['snapshot']['worn'] if v['slot']=='base:socks')
                    if mutation=='writer-original':sock['id']=7
                    else:sock['sameReference']=False
                else:
                    ordinary=self.selection(mode,'mp',moves=True);rows=[self.evidence(case,ordinary) for case in ordinary['cases']]
                    rows[0]['checkpoints'][2]['client']['snapshot']['kit']=False
                    with self.subTest(mode=mode,mutation=mutation):self.assertTrue(self.verify(ordinary,rows)['issues'])
                    continue
                with self.subTest(mode=mode,mutation=mutation):self.assertTrue(self.verify(selection,rows)['issues'])

    def test_held_root_moves_preserve_exact_hands_and_one_paid_effect_in_both_modes(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',held_moves=True)
            rows=[self.evidence(case,selection) for case in selection['cases']]
            result=self.verify(selection,rows)
            with self.subTest(mode=mode):
                self.assertEqual(result['issues'],[])
                self.assertTrue(all(v['outcome']['handsVerified'] for v in result['outcomes']))
                self.assertIs(rows[1]['clientFinal']['hands']['primary'],False)
                self.assertEqual(rows[1]['clientFinal']['kit']['uses'],4)

    def test_held_move_bank_is_explicit_exclusive_and_host_only(self):
        for mutation in ('sp','missing','false','string','root','carried','world','depletion','supplies','order','subset','host','mods','language'):
            selection=self.selection(kind='mp',held_moves=True)
            if mutation=='sp':selection['kind']='sp'
            elif mutation=='missing':selection['options'].pop('makeup_held_moves')
            elif mutation=='false':selection['options']['makeup_held_moves']=False
            elif mutation=='string':selection['options']['makeup_held_moves']='true'
            elif mutation in ('root','carried','world','depletion','supplies'):
                option={'root':'makeup_moves','carried':'makeup_carried_moves','world':'makeup_world_moves','depletion':'makeup_depletion_moves','supplies':'makeup_supplies'}[mutation]
                selection['options'][option]=True
            elif mutation=='order':selection['cases'].reverse()
            elif mutation=='subset':selection['cases'].pop()
            elif mutation=='host':selection['options']['mp_host']=False
            elif mutation=='mods':selection['mods'].pop()
            else:selection['languages']=['RU']
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):m.validate(selection)

    def test_held_snapshots_reject_wrong_lost_stale_extra_hands_and_references(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',held_moves=True)
            for mutation in ('flag','hand-spec','missing-hands','wrong-initial-slot','initial-proxy','initial-owner','extra-slot',
                             'ghost-primary','ghost-secondary','lost-retained','retained-wrong-slot','retained-proxy','retained-owner','retained-cost','retained-deleted',
                             'lost-sentinel','wrong-sentinel','sentinel-proxy','equip-hammer-lost','equip-hammer-proxy','paid-cosmetic-hand',
                             'before-tail-extra','before-tail-sentinel-lost','before-tail-retained-proxy','root-kit-returned','ordinary-extra-hands'):
                rows=[self.evidence(case,selection) for case in selection['cases']]
                if mutation=='flag':rows[0]['ids'].pop('held')
                elif mutation=='hand-spec':rows[0]['ids']['handSpec']['post']['primary']='kit'
                elif mutation=='missing-hands':rows[0]['checkpoints'][1]['client']['snapshot'].pop('hands')
                elif mutation=='wrong-initial-slot':rows[1]['checkpoints'][0]['client']['snapshot']['hands']=dict(primary=copy.deepcopy(rows[1]['ids']['baseline']['hands']['secondary']),secondary=False)
                elif mutation in ('initial-proxy','initial-owner'):
                    hand=rows[0]['checkpoints'][0]['authority']['snapshot']['hands']['primary']
                    if mutation=='initial-owner':hand['equipParent']=False
                    else:hand['sameReference']=False;hand['container']=False
                elif mutation=='extra-slot':rows[0]['clientFinal']['hands']['third']=False
                elif mutation in ('ghost-primary','ghost-secondary'):
                    row=rows[0] if mutation=='ghost-primary' else rows[2];slot='primary' if mutation=='ghost-primary' else 'secondary'
                    hand=copy.deepcopy(row['ids']['baseline']['hands'][slot]);hand.update(root=False,sameReference=False,container=False,equipParent=False)
                    row['checkpoints'][2]['authority']['snapshot']['hands'][slot]=hand
                elif mutation in ('lost-retained','retained-wrong-slot','retained-proxy','retained-owner','retained-cost','retained-deleted'):
                    value=rows[1]['checkpoints'][2]['client']['snapshot']
                    if mutation=='lost-retained':value['hands']['secondary']=False
                    elif mutation=='retained-wrong-slot':value['hands']=dict(primary=value['hands']['secondary'],secondary=False)
                    elif mutation=='retained-proxy':value['hands']['secondary']['sameReference']=False;value['hands']['secondary']['container']=False
                    elif mutation=='retained-owner':value['hands']['secondary']['equipParent']=False
                    elif mutation=='retained-cost':value['kit']['uses']=3
                    else:value['kit']=False
                elif mutation in ('lost-sentinel','wrong-sentinel','sentinel-proxy'):
                    hand=rows[3]['checkpoints'][2]['client']['snapshot']['hands']['secondary']
                    if mutation=='lost-sentinel':rows[3]['checkpoints'][2]['client']['snapshot']['hands']['secondary']=False
                    elif mutation=='wrong-sentinel':hand.update(id=999,root=False,sameReference=False,container=False)
                    else:hand['sameReference']=False;hand['container']=False
                elif mutation=='equip-hammer-lost':rows[4]['checkpoints'][2]['authority']['snapshot']['hands']['primary']=False
                elif mutation=='equip-hammer-proxy':rows[4]['clientFinal']['hands']['primary']['sameReference']=False
                elif mutation=='paid-cosmetic-hand':rows[0]['checkpoints'][2]['client']['snapshot']['hands']['primary']=dict(id=rows[0]['output'],kind=m.TARGET,root=True,sameReference=True,container='root',equipParent=True)
                elif mutation=='before-tail-extra':rows[0]['beforeTail']['snapshot']['hands']['secondary']=copy.deepcopy(rows[0]['ids']['baseline']['hands']['primary'])
                elif mutation=='before-tail-sentinel-lost':rows[3]['beforeTail']['snapshot']['hands']['secondary']=False
                elif mutation=='before-tail-retained-proxy':rows[1]['beforeTail']['snapshot']['hands']['secondary']['sameReference']=False
                elif mutation=='root-kit-returned':rows[0]['checkpoints'][2]['client']['snapshot']['root'].insert(0,dict(id=1,kind='Base.MakeupEyeshadow'))
                else:
                    ordinary=self.selection(mode,'mp',moves=True);rows=[self.evidence(case,ordinary) for case in ordinary['cases']]
                    rows[0]['checkpoints'][2]['client']['snapshot']['hands']=dict(primary=False,secondary=False)
                    with self.subTest(mode=mode,mutation=mutation):self.assertTrue(self.verify(ordinary,rows)['issues'])
                    continue
                with self.subTest(mode=mode,mutation=mutation):self.assertTrue(self.verify(selection,rows)['issues'])

    def test_held_move_admission_requires_live_initial_hand_refs(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',held_moves=True)
            for mutation in ('missing','cleared','wrong-id','proxy','owner','extra'):
                rows=[self.evidence(case,selection) for case in selection['cases']];edit=rows[0]['edit']
                if mutation=='missing':edit.pop('hands')
                elif mutation=='cleared':edit['hands']['primary']=False
                elif mutation=='wrong-id':edit['hands']['primary']['id']=999
                elif mutation=='proxy':edit['hands']['primary']['sameReference']=False
                elif mutation=='owner':edit['hands']['primary']['equipParent']=False
                else:edit['hands']['secondary']=copy.deepcopy(edit['hands']['primary'])
                with self.subTest(mode=mode,mutation=mutation):self.assertTrue(self.verify(selection,rows)['issues'])

    def test_held_before_tail_allows_only_matching_kit_clears_and_preserves_other_hands(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',held_moves=True)
            for index in (0,2,3):
                for pending in ('retained-before-removal','detached-before-equip-packet','one-side-cleared'):
                    rows=[self.evidence(case,selection) for case in selection['cases']];row=rows[index];actual=row['beforeTail']['snapshot'];ids=row['ids']
                    initial=copy.deepcopy(ids['baseline']['hands'])
                    if pending=='retained-before-removal':
                        actual['kit']=copy.deepcopy(ids['baseline']['kit']);actual['root'].append(dict(id=1,kind='Base.MakeupEyeshadow'));actual['root'].sort(key=lambda v:v['id'])
                    else:
                        for slot,hand in initial.items():
                            if hand and hand['id']==1:hand.update(root=False,sameReference=False,container=False,equipParent=False)
                        if pending=='one-side-cleared':initial['primary']=False
                    actual['hands']=initial
                    with self.subTest(mode=mode,index=index,pending=pending):self.assertEqual(self.verify(selection,rows)['issues'],[])

    def test_held_equip_writer_and_move_lifecycle_proof_are_required(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',held_moves=True)
            for mutation in ('admitted','order','writer-missing','writer-item','writer-primary','writer-twohands','writer-duration','writer-starts','writer-ref','writer-ref-alias','writer-failed','writer-duplicate','writer-late','promotion-resume','body-duplicate','receipt-duplicate'):
                rows=[self.evidence(case,selection) for case in selection['cases']];row=rows[4];writer=row['equipWriter']
                if mutation=='admitted':row['edit']['accepted']=True
                elif mutation=='order':row['startOrder'].reverse()
                elif mutation=='writer-missing':row.pop('equipWriter')
                elif mutation=='writer-item':writer['item']=999
                elif mutation=='writer-primary':writer['primary']=False
                elif mutation=='writer-twohands':writer['twoHands']=True
                elif mutation=='writer-duration':writer['duration']=1
                elif mutation=='writer-starts':writer['starts']=2
                elif mutation=='writer-ref':writer['nativeRef']=False
                elif mutation=='writer-ref-alias':writer['nativeRef']=row['body']['nativeRef']
                elif mutation=='writer-failed':writer['finishes'][0]['succeeded']=False
                elif mutation=='writer-duplicate':writer['finishes'].append(copy.deepcopy(writer['finishes'][0]))
                elif mutation=='writer-late':writer['finishes'][0]['at']=row['body']['finishes'][0]['at']+1
                elif mutation=='promotion-resume':
                    if mode=='toolkit':rows[2]['readerResume']['resumedPages']=97
                    else:rows[2]['readerResume']=dict(pages=98,resumedPages=98,native='manufactured')
                elif mutation=='body-duplicate':row['body']['starts']=2
                else:row['outcomes'].append(copy.deepcopy(row['outcomes'][-1]))
                with self.subTest(mode=mode,mutation=mutation):self.assertTrue(self.verify(selection,rows)['issues'])

    def test_moves_selection_is_host_only_explicit_and_exclusive(self):
        for mutation in ('sp','missing','string','supply','order','subset','mods','host'):
            selection=self.selection(kind='mp',moves=True)
            if mutation=='sp':selection['kind']='sp'
            elif mutation=='missing':selection['options'].pop('makeup_moves')
            elif mutation=='string':selection['options']['makeup_moves']='true'
            elif mutation=='supply':selection['options']['makeup_supplies']=True
            elif mutation=='order':selection['cases'].reverse()
            elif mutation=='subset':selection['cases'].pop()
            elif mutation=='mods':selection['mods'].pop()
            elif mutation=='host':selection['options']['mp_host']=False
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):m.validate(selection)

    def test_move_order_ownership_reader_checkpoint_and_exact_cost_falsifications(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',moves=True)
            for mutation in ('before-order','after-order','start-order','ownership','allocated','reader-pages','reader-native','tail-lost',
                             'tail-early','middle-short','kit-cost','output-reference','old-proxy','writer-lost','transfer','admission','receipt-cost'):
                rows=[self.evidence(case,selection) for case in selection['cases']];row=rows[0]
                if mutation=='before-order':row['edit']['before'].reverse()
                elif mutation=='after-order':row['edit']['after'].reverse()
                elif mutation=='start-order':row['startOrder'].reverse()
                elif mutation=='ownership':row['edit']['ownershipPreserved']=False
                elif mutation=='allocated':row['edit']['bodyUnallocated']=False
                elif mutation=='reader-pages':row['edit']['frontPages']=92
                elif mutation=='reader-native':row['edit']['frontNativeAfter']='replacement'
                elif mutation=='tail-lost':row['edit']['tailRetained']=False
                elif mutation=='tail-early':row['beforeTail']['snapshot']['tailPages']=100
                elif mutation=='middle-short':row['clientFinal']['middlePages']=99
                elif mutation=='kit-cost':row['checkpoints'][2]['authority']['snapshot']['kit']['uses']=3
                elif mutation=='output-reference':next(v for v in row['clientFinal']['worn'] if v['id']==row['output'])['sameReference']=False
                elif mutation=='old-proxy':row['ids']['baseline']['worn'][0]['sameReference']=False
                elif mutation=='writer-lost':rows[3]['clientFinal']['worn']=[]
                elif mutation=='transfer':row['supplyTransferStarts']=1
                elif mutation=='admission':rows[3]['edit']['accepted']=True
                else:row['receipt']['snapshot']['kit']['uses']=3
                with self.subTest(mode=mode,mutation=mutation):self.assertTrue(self.verify(selection,rows)['issues'])

    def test_writer_original_sock_transition_identity_and_other_slot_falsifications(self):
        for mode in ('native','toolkit'):
            selection=self.selection(mode,'mp',moves=True)
            for mutation in ('original-root-lost','original-still-worn','early-writer','baseline-writer','baseline-proxy',
                             'writer-wrong-id','writer-wrong-type','writer-proxy','before-tail-old','receipt-old','other-slot-lost'):
                rows=[self.evidence(case,selection) for case in selection['cases']];row=rows[3]
                values=[row['ids']['baseline'],row['clientFinal'],row['receipt']['snapshot'],row['beforeTail']['snapshot'],
                        *[point[role]['snapshot'] for point in row['checkpoints'] for role in ('client','authority')]]
                # A separate untouched worn slot makes broad slot normalization
                # observable: the evaluator must still conserve this exact hat.
                for value in values:
                    value['root'].append(dict(id=8,kind='Base.Hat_Beany'));value['root'].sort(key=lambda v:v['id'])
                    value['worn'].append(dict(id=8,kind='Base.Hat_Beany',slot='base:hat',root=True,sameReference=True,container='root'))
                    value['worn'].sort(key=lambda v:v['slot'])
                late=row['checkpoints'][2]['client']['snapshot']
                def sock(value):return next(w for w in value['worn'] if w['slot']=='base:socks')
                if mutation=='original-root-lost':late['root']=[v for v in late['root'] if v['id']!=7]
                elif mutation=='original-still-worn':sock(late)['id']=7
                elif mutation=='early-writer':sock(row['checkpoints'][1]['authority']['snapshot'])['id']=6
                elif mutation=='baseline-writer':
                    for value in [row['ids']['baseline'],*[row['checkpoints'][0][role]['snapshot'] for role in ('client','authority')]]:sock(value)['id']=6
                elif mutation=='baseline-proxy':sock(row['ids']['baseline'])['sameReference']=False
                elif mutation=='writer-wrong-id':sock(late)['id']=999
                elif mutation=='writer-wrong-type':sock(late)['kind']='Base.Socks_Long'
                elif mutation=='writer-proxy':sock(late)['sameReference']=False
                elif mutation=='before-tail-old':sock(row['beforeTail']['snapshot'])['id']=7
                elif mutation=='receipt-old':sock(row['receipt']['snapshot'])['id']=7
                else:late['worn']=[w for w in late['worn'] if w['slot']!='base:hat']
                with self.subTest(mode=mode,mutation=mutation):self.assertTrue(self.verify(selection,rows)['issues'])

    def test_promotion_requires_native_checkpoint_resume(self):
        selection=self.selection(kind='mp',moves=True)
        for mutation in ('missing','rollback','same-native','wrong-sequence','double-body'):
            rows=[self.evidence(case,selection) for case in selection['cases']];row=rows[2]
            if mutation=='missing':row.pop('readerResume')
            elif mutation=='rollback':row['readerResume']['resumedPages']=92
            elif mutation=='same-native':row['readerResume']['native']='native-front'
            elif mutation=='wrong-sequence':row['startOrder']=['front','middle','body','front','tail']
            else:row['body']['starts']=2
            with self.subTest(mutation=mutation):self.assertTrue(self.verify(selection,rows)['issues'])

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_selected_cart_guard_factory_observation_preserves_behavior_and_exact_binding(self):
        from cart_blender import game_default
        selected=os.environ.get('PZ_TEST_SAUCED_CARTS_SOURCE')
        if not selected:self.skipTest('Set PZ_TEST_SAUCED_CARTS_SOURCE to the locked selected mod source')
        sauce=Path(selected);sauce=sauce/'42' if (sauce/'42').is_dir() else sauce
        self.assertTrue((sauce/'media/lua/shared/SaucedCarts/ForceDropGuard.lua').is_file(),'Selected guard source is missing')
        game=Path(os.environ['PZ_GAME_DIR']) if os.environ.get('PZ_GAME_DIR') else game_default()
        if not game or not (game/'media/lua/shared/TimedActions/ISEquipWeaponAction.lua').is_file():self.skipTest('Native game Lua unavailable')
        project=Path(__file__).resolve().parents[1];text=(project/'tests/native_queue/makeup/client/ZZMakeup.lua').read_text()
        seal=text[text.index('function M.forceDropMatches(callback)'):text.index('function M.kind()')]+text[text.index('function M.captureEquip()'):text.index('local previewShotFrames')]
        prefix="""
local game,project,sauce,scenario=arg[1],arg[2],arg[3],arg[4]
local function reader(path)
 local file=assert(io.open(path,'r'));return {readLine=function()local s=file:read('*l');if s then s=s:gsub('\\r$','')end;return s end,close=function()file:close()end}
end
getFilenameOfClosure=function(callback)return debug.getinfo(callback,'S').source:gsub('^@','')end
getGameFilesInput=function(path)
 if scenario=='native-source-mismatch'and path=='media/lua/shared/TimedActions/ISEquipWeaponAction.lua'then
  local sent=false;return {readLine=function()if not sent then sent=true;return 'unsupported native version'end end,close=function()end}
 end
 return reader(game..'/'..path)
end
getModFileReader=function(mod,path,create)
 assert(mod=='SaucedCarts'and create==false)
 if scenario=='source-mismatch'and path:find('ForceDropGuard.lua',1,true)then
  local sent=false;return {readLine=function()if not sent then sent=true;return 'unsupported guard version'end end,close=function()end}
 end
 return reader(sauce..'/'..path)
end
local Proof=assert(loadfile(project..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))()
package.loaded['PZSurvivorToolkit/SourceProof']=Proof
assert(loadfile(game..'/media/lua/shared/ISBaseObject.lua'))()
package.preload['ISBaseObject']=function()return ISBaseObject end
package.preload['TimedActions/ISBaseTimedAction']=function()assert(loadfile(game..'/media/lua/shared/TimedActions/ISBaseTimedAction.lua'))();return ISBaseTimedAction end
assert(loadfile(game..'/media/lua/shared/TimedActions/ISEquipWeaponAction.lua'))()
local native=forceDropHeavyItems
local callbacks={};Events={OnGameStart={Add=function(fn)callbacks[#callbacks+1]=fn end},OnServerStarted={Add=function()end}}
getDebug=function()return false end;SandboxVars={SaucedCarts={}};getPlayer=function()return nil end;getScriptManager=function()return nil end
getActivatedMods=function()return {contains=function(_,id)return id=='SaucedCarts'end}end
local core=assert(loadfile(sauce..'/media/lua/shared/SaucedCarts/Core.lua'))();core.CartTypes={['Fixture.Cart']={}}
package.loaded['SaucedCarts/Core']=core
local guard=assert(loadfile(sauce..'/media/lua/shared/SaucedCarts/ForceDropGuard.lua'))();package.loaded['SaucedCarts/ForceDropGuard']=guard
local factory,predicate=guard.makeGuardedForceDrop,core.isCart
local Binding=assert(loadfile(project..'/tests/native_queue/makeup/shared/QueueMakeupDropBinding.lua'))()
local T={ActionQueue={}};local M={dropBinding=Binding,dropMatches=Binding.matches}
local function pack(...)return {n=select('#',...),...}end
local function foreign(callback,filename)return assert(loadstring('local before=...;return function(...)return before(...)end',filename or '@ForeignDropGuard.lua'))(callback)end
local foreignCalls,predicateCalls=0,0
local function foreignOriginal(...)foreignCalls=foreignCalls+1;return 'foreign-result',nil,73 end
local function foreignPredicate(item)predicateCalls=predicateCalls+1;return predicate(item)end
local function startEvents()for _,fn in ipairs(callbacks)do fn()end end
local kit,hammer,cart;local primary,secondary;local cartWorld;local cartPresent=false
local heavy,clears,spawns,persistentCalls=0,0,0,0
local world={setIgnoreRemoveSandbox=function(_,value)assert(value==true);persistentCalls=persistentCalls+1 end}
local square={AddWorldInventoryItem=function(_,item)assert(item==cart);spawns=spawns+1;cartWorld=world end}
local root={getItemById=function(_,id)if id==6 then return hammer end end,
 contains=function(_,item)return item==kit or item==hammer or item==cart and cartPresent end,
 Remove=function(_,item)assert(item==cart);cartPresent=false end}
local player={getCurrentSquare=function()return square end,getInventory=function()return root end,
 getPrimaryHandItem=function()return primary end,getSecondaryHandItem=function()return secondary end,
 removeFromHands=function(_,item)clears=clears+1;if primary==item then primary=nil end;if secondary==item then secondary=nil end end,
 setSecondaryHandItem=function(_,item)clears=clears+1;secondary=item end,
 getPlayerNum=function()return 0 end,isTimedActionInstant=function()return false end}
local function item(id,kind,isCart)
 local value=newproxy(true);local methods={getID=function()return id end,getFullType=function()return kind end,
  isForceDropHeavyItem=function()heavy=heavy+1;return isCart end,getWorldItem=function()return isCart and cartWorld or nil end,
  isTwoHandWeapon=function()return false end,isRequiresEquippedBothHands=function()return false end,getName=function()return kind end}
 getmetatable(value).__index=methods;return value
end
kit=item(1,'Base.MakeupEyeshadow',false);hammer=item(6,'Base.Hammer',false);cart=item(7,'Fixture.Cart',true)
instanceof=function(item,kind)return type(item)=='userdata'and(kind=='InventoryItem'or item==hammer and kind=='HandWeapon')end
isServer=function()return false end;ISInventoryPage={};ISTransferAction={GetDropItemOffset=function()return .5,.5,0 end}
sendRemoveItemFromContainer=function(container,item)assert(container==root and item==cart)end
getPlayerHotbar=function()return nil end;getText=function(key)return key end
local state={player=player};local ids={items={hammer=6}}
"""
        suffix="""
assert(guard.makeGuardedForceDrop==factory and forceDropHeavyItems==native and not Binding.matches(native),'passive module modified installation')
if scenario=='passive'then return end
if scenario=='opaque-before-start'then
 startEvents();local opaque=forceDropHeavyItems;assert(opaque~=native)
 assert(not Binding.start()and forceDropHeavyItems==opaque and guard.makeGuardedForceDrop==factory and not Binding.matches(opaque));return
end
if scenario=='foreign-factory-before'then guard.makeGuardedForceDrop=foreign(factory)
elseif scenario=='foreign-predicate-before'then core.isCart=foreignPredicate
elseif scenario=='foreign-original-before'then forceDropHeavyItems=foreignOriginal end
local allowed=Binding.start()
if scenario=='foreign-factory-before'or scenario=='foreign-predicate-before'or scenario=='foreign-original-before'or scenario=='source-mismatch'or scenario=='native-source-mismatch'then
 assert(not allowed and not Binding.matches(forceDropHeavyItems));startEvents();assert(not Binding.matches(forceDropHeavyItems));assert(not pcall(M.captureEquip));return
end
assert(allowed and guard.install==callbacks[#callbacks]and Binding.matches(native),'observer changed installer or lost unwrapped native binding')
if scenario=='factory-error'then
 local sentinel={};local count=0
 local function invoke(callback)
  debug.sethook(function()if debug.getinfo(2,'f').func==factory then count=count+1;error(sentinel,0)end end,'c')
  local result=pack(pcall(callback,native,predicate));debug.sethook();return result
 end
 local direct,observed=invoke(factory),invoke(guard.makeGuardedForceDrop)
 assert(direct.n==2 and observed.n==2 and direct[1]==false and observed[1]==false and direct[2]==sentinel and observed[2]==sentinel and count==2,'factory error identity/arity or delegation count changed')
 return
end
if scenario=='factory-args-results'then
 local direct=pack(factory(foreignOriginal,foreignPredicate,'extra',nil))
 local observed=pack(guard.makeGuardedForceDrop(foreignOriginal,foreignPredicate,'extra',nil))
 assert(direct.n==1 and observed.n==1 and type(observed[1])=='function','factory result arity changed')
 local result=pack(observed[1](nil));assert(result.n==3 and result[1]=='foreign-result'and result[2]==nil and result[3]==73 and foreignCalls==1,'factory rewrote predecessor arguments/results')
 assert(not Binding.matches(observed[1]));return
end
if scenario=='foreign-original-install'then forceDropHeavyItems=foreignOriginal
elseif scenario=='foreign-predicate-install'then core.isCart=foreignPredicate
elseif scenario=='foreign-factory-install'then guard.makeGuardedForceDrop=foreign(guard.makeGuardedForceDrop)end
local factoryCalls=0
debug.sethook(function()if debug.getinfo(2,'f').func==factory then factoryCalls=factoryCalls+1 end end,'c')
startEvents();debug.sethook();assert(factoryCalls==1,'observer did not call original factory exactly once')
local installed=forceDropHeavyItems;assert(installed~=native and guard.install==callbacks[#callbacks])
if scenario=='foreign-original-install'then
 local result=pack(installed(nil));assert(result.n==3 and result[1]=='foreign-result'and result[3]==73 and foreignCalls==1,'foreign predecessor was rewritten')
 assert(not Binding.matches(installed));assert(not pcall(M.captureEquip));return
elseif scenario=='foreign-predicate-install'then
 primary,secondary=kit,hammer;installed(player);assert(predicateCalls>0,'predicate argument was rewritten')
 assert(not Binding.matches(installed));assert(not pcall(M.captureEquip));return
elseif scenario=='foreign-factory-install'then assert(not Binding.matches(installed));assert(not pcall(M.captureEquip));return end
assert(Binding.matches(installed),'reviewed actual returned wrapper was not witnessed')
assert(Binding.start()and guard.makeGuardedForceDrop~=factory,'observation was not idempotent')
guard.install();assert(forceDropHeavyItems==installed and Binding.matches(installed),'native installation idempotence changed')
if scenario=='post-global'then forceDropHeavyItems=foreign(installed,'@ForceDropGuard.lua')
elseif scenario=='post-factory'then guard.makeGuardedForceDrop=foreign(guard.makeGuardedForceDrop,'@ForceDropGuard.lua')
elseif scenario=='post-predicate'then core.isCart=foreign(predicate,'@Core.lua')
elseif scenario=='post-installer'then guard.install=foreign(guard.install,'@ForceDropGuard.lua')
elseif scenario=='post-persistent'then core.markDropPersistent=foreign(core.markDropPersistent,'@Core.lua')
elseif scenario=='post-debug'then core.debug=foreign(core.debug,'@Core.lua')
elseif scenario=='post-registry'then core.CartTypes={['Fixture.Cart']={}}
elseif scenario=='held-type-registered'then core.CartTypes['Base.Hammer']={}
elseif scenario=='post-owner'then SaucedCarts={}end
if scenario~='normal'then assert(not Binding.matches(forceDropHeavyItems));assert(not pcall(M.captureEquip));return end
primary,secondary=kit,hammer;installed(player)
assert(primary==kit and secondary==hammer and heavy==2 and clears==0 and spawns==0,'reviewed guard changed ordinary held kit/Hammer or double-delegated')
primary,secondary=cart,hammer;cartWorld=world;cartPresent=false;heavy,clears,spawns,persistentCalls=0,0,0,0
installed(player)
assert(primary==nil and secondary==hammer and heavy==1 and clears==1 and spawns==0 and persistentCalls==1,'stale-cart guard/persistence behavior was bypassed')
primary,secondary=cart,hammer;cartWorld=nil;cartPresent=true;heavy,clears,spawns,persistentCalls=0,0,0,0
installed(player)
assert(primary==nil and secondary==hammer and heavy==2 and clears==1 and spawns==1 and persistentCalls==1,'native cart drop/persistence behavior was changed')
M.captureEquip();M.writer=ISEquipWeaponAction:new(player,hammer,50,true,false);M.assertEquip(M.writer)
assert(forceDropHeavyItems==installed and Binding.matches(installed),'fixture replaced or unwrapped the gameplay guard')
"""
        scenarios=('normal','passive','opaque-before-start','foreign-factory-before','foreign-predicate-before','foreign-original-before','source-mismatch','native-source-mismatch',
                   'factory-error','factory-args-results','foreign-original-install','foreign-predicate-install','foreign-factory-install','post-global','post-factory',
                   'post-predicate','post-installer','post-persistent','post-debug','post-registry','held-type-registered','post-owner')
        for scenario in scenarios:
            result=subprocess.run([shutil.which('luajit'),'-',str(game),str(project),str(sauce),scenario],input=prefix+seal+suffix,capture_output=True,text=True)
            with self.subTest(scenario=scenario):self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_real_native_hammer_writer_provenance_and_post_capture_identity_are_sealed(self):
        from cart_blender import game_default
        game=Path(os.environ['PZ_GAME_DIR']) if os.environ.get('PZ_GAME_DIR') else game_default()
        if not game or not (game/'media/lua/shared/TimedActions/ISEquipWeaponAction.lua').is_file():self.skipTest('Native game Lua unavailable')
        project=Path(__file__).resolve().parents[1];source=project/'tests/native_queue/makeup/client/ZZMakeup.lua';text=source.read_text()
        seal=text[text.index('function M.forceDropMatches(callback)'):text.index('function M.kind()')]+text[text.index('function M.captureEquip()'):text.index('local previewShotFrames')]
        start=text.index('   local hammer=assert(');last=text.index('   ISTimedActionQueue.add(M.writer)',start)
        constructor=text[start:text.index('\n',last)+1]
        intact=text[text.index('local function intact()'):text.index('local function observe(callback)')]
        self.assertIn('M.assertEquip(M.equipWriter and M.writer or nil)',intact)
        self.assertEqual(constructor.count('M.assertEquip('),2)
        prefix="""
local game,project,scenario=arg[1],arg[2],arg[3]
getFilenameOfClosure=function(callback)return debug.getinfo(callback,'S').source:gsub('^@','')end
getGameFilesInput=function(path)
 if scenario=='source-mismatch'and path=='media/lua/shared/TimedActions/ISEquipWeaponAction.lua'then
  local sent=false;return {readLine=function()if not sent then sent=true;return 'foreign source'end end,close=function()end}
 end
 local file=assert(io.open(game..'/'..path,'r'));return {readLine=function()local line=file:read('*l');if line then line=line:gsub('\\r$','')end;return line end,close=function()file:close()end}
end
local Proof=assert(loadfile(project..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))()
assert(loadfile(game..'/media/lua/shared/ISBaseObject.lua'))()
package.preload['ISBaseObject']=function()return ISBaseObject end
package.preload['TimedActions/ISBaseTimedAction']=function()
 assert(loadfile(game..'/media/lua/shared/TimedActions/ISBaseTimedAction.lua'))();return ISBaseTimedAction
end
assert(loadfile(game..'/media/lua/shared/TimedActions/ISEquipWeaponAction.lua'))()
local hammer={getID=function()return 6 end,isTwoHandWeapon=function()return false end,isRequiresEquippedBothHands=function()return false end,getName=function()return 'Hammer'end}
local root={getItemById=function(_,id)assert(id==6);return hammer end}
local player={getInventory=function()return root end,getPlayerNum=function()return 0 end,getSecondaryHandItem=function()return nil end,isTimedActionInstant=function()return false end}
isServer=function()return false end;getPlayerHotbar=function()return nil end
instanceof=function(item,kind)return item==hammer and kind=='HandWeapon'end
getText=function(key)return key end
local state={player=player};local ids={items={hammer=6}};local T={ActionQueue={}};local M={};local queued
ISTimedActionQueue={add=function(action)assert(not queued);queued=action end}
local function foreign(callback,filename)
 return assert(loadstring('local before=...;return function(...)return before(...)end',filename or '@ForeignEquip.lua'))(callback)
end
if scenario=='foreign-constructor'then ISEquipWeaponAction.new=foreign(ISEquipWeaponAction.new)
elseif scenario=='foreign-executor'then ISEquipWeaponAction.complete=foreign(ISEquipWeaponAction.complete)
elseif scenario=='foreign-base'then ISBaseTimedAction.new=foreign(ISBaseTimedAction.new)
elseif scenario=='foreign-helper'then forceDropHeavyItems=foreign(forceDropHeavyItems)
elseif scenario=='missing-own-executor'then ISEquipWeaponAction.complete=nil
elseif scenario=='extra-class-function'then ISEquipWeaponAction.foreignHook=function()end
elseif scenario=='foreign-inherited-hook'then ISBaseTimedAction.begin=foreign(ISBaseTimedAction.begin)
elseif scenario=='approved-queue-hook'then ISBaseTimedAction.begin=foreign(ISBaseTimedAction.begin,'@ActionQueue.lua')end
"""
        after_capture="""
M.captureEquip()
if scenario=='replaced-constructor'then ISEquipWeaponAction.new=foreign(ISEquipWeaponAction.new,'@ISEquipWeaponAction.lua')
elseif scenario=='replaced-executor'then ISEquipWeaponAction.complete=foreign(ISEquipWeaponAction.complete,'@ISEquipWeaponAction.lua')
elseif scenario=='replaced-base'then ISBaseTimedAction.new=foreign(ISBaseTimedAction.new,'@ISBaseTimedAction.lua')
elseif scenario=='replaced-helper'then forceDropHeavyItems=foreign(forceDropHeavyItems,'@ISEquipWeaponAction.lua')
elseif scenario=='replaced-owner'then ISEquipWeaponAction={}
elseif scenario=='replaced-queue'then T.ActionQueue={}
elseif scenario=='extra-base-function'then ISBaseTimedAction.foreignHook=function()end end
M.assertEquip()
"""
        after_constructor="""
if scenario=='instance-executor'then M.writer.complete=foreign(M.writer.complete)
elseif scenario=='instance-callback'then M.writer.onCompleteFunc=function()end
elseif scenario=='instance-extra-function'then M.writer.foreignHook=function()end
elseif scenario=='instance-inherited-hook'then M.writer.begin=foreign(M.writer.begin)end
M.assertEquip(M.writer)
assert(queued==M.writer and M.equipWriter.starts==0 and M.writer.item==hammer and M.writer.maxTime==50,'native constructor did not preserve the exact ordinary writer')
"""
        scenarios=('native','approved-queue-hook','foreign-constructor','foreign-executor','foreign-base','foreign-helper','missing-own-executor','extra-class-function','foreign-inherited-hook',
                   'source-mismatch','replaced-constructor','replaced-executor','replaced-base','replaced-helper','replaced-owner','replaced-queue','extra-base-function',
                   'instance-executor','instance-callback','instance-extra-function','instance-inherited-hook')
        for scenario in scenarios:
            result=subprocess.run([shutil.which('luajit'),'-',str(game),str(project),scenario],input=prefix+seal+after_capture+constructor+after_constructor,capture_output=True,text=True)
            with self.subTest(scenario=scenario):
                if scenario in ('native','approved-queue-hook'):self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                else:
                    self.assertNotEqual(result.returncode,0);self.assertIn('native Hammer writer',result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_held_native_specs_match_expected_initial_cost_and_posthands(self):
        source=Path(__file__).resolve().parents[1]/'tests/native_queue/makeup/shared/QueueMakeup.lua'
        script="""
package.preload['Definitions/MakeUpDefinitions']=function()end
ItemBodyLocation={MAKE_UP_FULL_FACE='face',MAKE_UP_EYES='eyes',MAKE_UP_EYES_SHADOW='shadow',MAKE_UP_LIPS='lips'}
local F=assert(loadfile(arg[1]))();assert(#F.heldMoves==5)
for i=2,#arg,6 do
 local case,uses=arg[i],tonumber(arg[i+1]);local spec=assert(F.spec(case))
 assert(F.heldCase(case)and spec.uses==uses and F.depletionCase(case)==(uses==1))
 assert((spec.initialHands.primary or 'empty')==arg[i+2]and(spec.initialHands.secondary or 'empty')==arg[i+3])
 assert((spec.postHands.primary or 'empty')==arg[i+4]and(spec.postHands.secondary or 'empty')==arg[i+5])
end
"""
        arguments=[value for case,spec in m.HELD_SPECS.items() for value in (case,str(spec['uses']),spec['initial']['primary'] or 'empty',spec['initial']['secondary'] or 'empty',spec['post']['primary'] or 'empty',spec['post']['secondary'] or 'empty')]
        result=subprocess.run([shutil.which('luajit'),'-',str(source),*arguments],input=script,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_held_snapshot_and_readiness_use_actual_hands_without_repair_or_detached_cost(self):
        source=Path(__file__).resolve().parents[1]/'tests/native_queue/makeup/shared/QueueMakeup.lua'
        script="""
package.preload['Definitions/MakeUpDefinitions']=function()end
ItemBodyLocation={MAKE_UP_FULL_FACE='face',MAKE_UP_EYES='eyes',MAKE_UP_EYES_SHADOW='shadow',MAKE_UP_LIPS='lips'}
local F=assert(loadfile(arg[1]))();local case=arg[2];local spec=F.spec(case)
local root,player={},{};local live={};local primary,secondary,worn;local uses=spec.uses
local function member(id)for _,v in ipairs(live)do if v:getID()==id then return v end end end
local function item(id,kind)
 local value={getID=function()return id end,getFullType=function()return kind end}
 value.getContainer=function()return member(id)==value and root or nil end
 value.getEquipParent=function()return (primary==value or secondary==value)and player or nil end
 return value
end
local kit,hammer,front,tail,output=item(1,'Base.MakeupEyeshadow'),item(6,'Base.Hammer'),item(2,'Base.BookCarpentry1'),item(4,'Base.BookFirstAid1'),item(3,'Base.MakeUp_Crow')
kit.getCurrentUses=function()assert(member(1)==kit,'detached kit uses were read');return uses end;kit.getMaxUses=function()return 5 end
local function choose(name)if name=='kit'then return kit elseif name=='hammer'then return hammer end end
local hasHammer=spec.initialHands.secondary=='hammer'or spec.postHands.primary=='hammer'
local function inventory(withKit,withOutput)
 live={front,tail};if withKit then live[#live+1]=kit end;if hasHammer then live[#live+1]=hammer end;if withOutput then live[#live+1]=output end
end
root.getItems=function()return {size=function()return #live end,get=function(_,i)return live[i+1]end}end
root.getItemById=function(_,id)return member(id)end
player.getInventory=function()return root end;player.getOnlineID=function()return 7 end;player.getAlreadyReadPages=function()return 99 end
player.getPrimaryHandItem=function()return primary end;player.getSecondaryHandItem=function()return secondary end
player.getWornItem=function(_,slot)assert(slot=='eyes');return worn end
player.getWornItems=function()return {size=function()return worn and 1 or 0 end,get=function()return {getItem=function()return worn end,getLocation=function()return 'eyes'end}end}end
local ids={case=case,held=true,actor=7,target='Base.MakeUp_Crow',slot='eyes',items={kit=1,hammer=6},
 types={kit='Base.MakeupEyeshadow',hammer='Base.Hammer',front='Base.BookCarpentry1',tail='Base.BookFirstAid1'}}
if spec.depletion then ids.depletion=true end
local state={player=player,ids=ids};inventory(true,false);primary=choose(spec.initialHands.primary);secondary=choose(spec.initialHands.secondary)
assert(F.handsReady(state,false),'exact initial native hands not recognized')
local baseline=F.snapshot(state);ids.baseline=baseline
for _,slot in ipairs({'primary','secondary'})do
 local hand=baseline.hands[slot]
 if not spec.initialHands[slot]then assert(hand==false,'empty primary was aliased to secondary')else assert(hand.sameReference and hand.equipParent and hand.container=='root')end
end
local slot=spec.initialHands.primary=='kit'and'primary'or'secondary';local proxy=item(1,'Base.MakeupEyeshadow')
if slot=='primary'then primary=proxy else secondary=proxy end
assert(not F.handsReady(state,false),'same-ID foreign hand reference was accepted')
assert((slot=='primary'and primary or secondary)==proxy,'readiness repaired client hands')
primary=choose(spec.postHands.primary);secondary=choose(spec.postHands.secondary);worn=output
inventory(not spec.depletion,true);if not spec.depletion then uses=4 end
assert(F.handsReady(state,true),'exact posthands not recognized')
if spec.depletion then assert(F.depletionReady(state),'paid deletion did not include exact posthands')end
local paid=F.snapshot(state)
if spec.depletion then assert(paid.kit==false)else assert(paid.kit.uses==4 and paid.hands.primary==false and paid.hands.secondary.sameReference)end
if spec.postHands.primary then primary=nil else primary=kit end
assert(not F.handsReady(state,true),'lost native item or extra ghost kit was accepted')
if spec.depletion then
 assert(not F.depletionReady(state),'ghost/lost hand passed paid readiness')
 local pending=F.snapshot(state,true);assert(pending.hands.primary~=nil,'actual transition hands were not captured')
end
"""
        for case in m.HELD_MOVE_CASES:
            with self.subTest(case=case):
                result=subprocess.run([shutil.which('luajit'),'-',str(source),case],input=script,capture_output=True,text=True)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_controller_hammer_writer_uses_native_equip_argument_order(self):
        source=Path(__file__).resolve().parents[1]/'tests/native_queue/makeup/client/ZZMakeup.lua'
        text=source.read_text();start=text.index('   local hammer=assert(');last=text.index('   ISTimedActionQueue.add(M.writer)',start)
        block=text[start:text.index('\n',last)+1]
        prefix="""
local hammer={getID=function()return 6 end};local player={getInventory=function()return {getItemById=function(_,id)assert(id==6);return hammer end}end}
local state={player=player};local ids={items={hammer=6}};local M={assertEquip=function()end};local queued
ISEquipWeaponAction={new=function(_,actor,item,maxTimeInit,primary,twoHands,alwaysTurnOn)
 assert(actor==player and item==hammer and maxTimeInit==50 and primary==true and twoHands==false and alwaysTurnOn==nil,'NATIVE_EQUIP_ARGUMENT_ORDER')
 return {item=item,primary=primary,twoHands=twoHands,maxTime=maxTimeInit}
end}
ISTimedActionQueue={add=function(action)assert(not queued);queued=action end}
"""
        suffix="""
assert(queued==M.writer and M.equipWriter.item==6 and M.equipWriter.starts==0 and M.equipWriter.nativeRef==false,'constructor manufactured native execution')
"""
        def run(actual):return subprocess.run([shutil.which('luajit'),'-'],input=prefix+actual+suffix,capture_output=True,text=True)
        result=run(block);self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        wrong=block.replace('ISEquipWeaponAction:new(state.player,hammer,50,true,false)','ISEquipWeaponAction:new(state.player,hammer,true,false)')
        self.assertNotEqual(wrong,block);result=run(wrong)
        self.assertNotEqual(result.returncode,0);self.assertIn('NATIVE_EQUIP_ARGUMENT_ORDER',result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_depletion_snapshot_reads_physical_membership_without_detached_uses(self):
        source=Path(__file__).resolve().parents[1]/'tests/native_queue/makeup/shared/QueueMakeup.lua'
        script="""
package.preload['Definitions/MakeUpDefinitions']=function()end
ItemBodyLocation={MAKE_UP_FULL_FACE='face',MAKE_UP_EYES='eyes',MAKE_UP_EYES_SHADOW='shadow',MAKE_UP_LIPS='lips'}
local F=assert(loadfile(arg[1]))();local live={};local root={};local worn
local function item(id,kind)return {getID=function()return id end,getFullType=function()return kind end,getContainer=function()return root end}end
local front,tail,output=item(2,'Base.BookCarpentry1'),item(4,'Base.BookFirstAid1'),item(3,'Base.MakeUp_Crow')
local detached=item(1,'Base.MakeupEyeshadow');detached.getCurrentUses=function()error('detached uses must not be read')end
local values={size=function()return #live end,get=function(_,i)return live[i+1]end}
root.getItems=function()return values end
root.getItemById=function(_,id)for _,value in ipairs(live)do if value:getID()==id then return value end end end
local player={getInventory=function()return root end,getOnlineID=function()return 7 end,getAlreadyReadPages=function()return 99 end,
 getWornItem=function(_,slot)assert(slot=='eyes');return worn end,
 getWornItems=function()return {size=function()return worn and 1 or 0 end,get=function(_,i)
  assert(i==0 and worn);return {getItem=function()return worn end,getLocation=function()return 'eyes'end}
 end}end}
local ids={case='deplete-root-earlier',actor=7,depletion=true,target='Base.MakeUp_Crow',slot='eyes',items={kit=1},
 types={kit='Base.MakeupEyeshadow',front='Base.BookCarpentry1',tail='Base.BookFirstAid1'},
 baseline={root={{id=1,kind='Base.MakeupEyeshadow'},{id=2,kind='Base.BookCarpentry1'},{id=4,kind='Base.BookFirstAid1'}}}}
local state={player=player,ids=ids};live={front,output,tail};worn=output
assert(F.depletionReady(state),'exact physical deletion and paid root/worn output were not recognized')
local paid=F.snapshot(state);assert(paid.kit==false and #paid.root==3 and paid.worn[1].sameReference)
live={front,tail};worn=nil
assert(not F.depletionReady(state),'missing paid output was accepted')
assert(not pcall(F.snapshot,state),'ordinary paid snapshot accepted missing physical output')
local pending=F.snapshot(state,true);assert(pending.kit==false and #pending.root==2 and #pending.worn==0,'transition snapshot fabricated a consumed item/output')
live={detached,front,output,tail};worn=output
assert(not F.depletionReady(state),'physically retained kit was treated as deleted')
"""
        result=subprocess.run([shutil.which('luajit'),'-',str(source)],input=script,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_authority_depletion_checkpoint_waits_for_real_deletion_and_paid_output(self):
        source=Path(__file__).resolve().parents[1]/'tests/native_queue/makeup/server/ZZMakeupServer.lua'
        script="""
isServer=function()return true end
local handlers={};Events={}
for _,name in ipairs({'OnServerStarted','OnClientCommand','OnTick'})do Events[name]={Add=function(fn)handlers[name]=fn end}end
local tile={x=10,y=20,z=0};local player={getUsername=function()return 'client1'end}
local clock,reads,replies,prepared=0,0,0,0;local ready=false
local paid={kit=false};getTimestampMs=function()return clock end
sendServerCommand=function(actor,module,name,args)
 assert(actor==player and module=='MakeupTest')
 if name=='Prepared'then prepared=prepared+1 else assert(name=='Snapshot'and ready and args.snapshot==paid);replies=replies+1 end
end
package.loaded.QueueHealthEvents={encode=function()return '{}'end}
package.loaded.QueueTestSelection={cases={'deplete-root-earlier'},options={makeup_depletion_moves=true}}
package.loaded.QueueMakeup={validPlacement=function(v)return v==tile end,same=function(a,b)return a==b end,
 atPlacement=function(actor,value)return actor==player and value==tile end,
 prepare=function()return {ids={case='deplete-root-earlier',depletion=true}}end,
 depletionReady=function()return ready end,snapshot=function()assert(ready,'authority read before exact paid proof');reads=reads+1;return paid end}
assert(loadfile(arg[1]))()
handlers.OnClientCommand('MakeupTest','Prepare',player,{case='deplete-root-earlier',placement=tile});handlers.OnTick()
assert(prepared==1)
handlers.OnClientCommand('MakeupTest','Snapshot',player,{case='deplete-root-earlier',label='after-body',sequence=1})
handlers.OnTick();clock=500;handlers.OnTick();assert(reads==0 and replies==0,'authority predicted native removal/output')
ready=true;clock=1000;handlers.OnTick();assert(reads==1 and replies==0)
clock=1600;handlers.OnTick();assert(reads==2 and replies==1,'authority did not publish converged real paid state')
"""
        result=subprocess.run([shutil.which('luajit'),'-',str(source)],input=script,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_controller_walk_constructor_does_not_expand_resolver_message_into_callback(self):
        source=Path(__file__).resolve().parents[1]/'tests/native_queue/makeup/client/ZZMakeup.lua'
        text=source.read_text();start=text.index('   local function square(tile)')
        last=text.index("   assert(M.walkActions.out.toolkitQueueOperation~=M.walkActions.back.toolkitQueueOperation",start)
        block=text[start:text.index('\n',last)+1]
        resolver=block[:block.index('   M.walkActions=')]
        # Execute the actual controller block, including its constructor guards.
        # Native new(character, location, additionalTest, additionalContext) gets
        # all values from a final argument expression, including assert's message.
        prefix="""
local player={};local origin={x=10,y=20,z=0};local out={x=8,y=20,z=0}
local state={player=player};local ids={walk={origin=origin,out=out}};local M={}
local calls,queued={},{}
getCell=function()return {getGridSquare=function(_,x,y,z)
 assert(z==0);if x==origin.x and y==origin.y then return origin end
 assert(x==out.x and y==out.y);return out
end}end
ISWalkToTimedAction={new=function(_,actor,location,additionalTest,additionalContext)
 assert(actor==player and(location==origin or location==out))
 assert(additionalTest==nil and additionalContext==nil,'EXTRA_NATIVE_WALK_CALLBACK')
 local action={maxTime=-1,location=location,additionalTest=additionalTest,additionalContext=additionalContext}
 if arg[1]~='clean'then action[arg[1]]=function()end end
 calls[#calls+1]=action;return action
end}
ISTimedActionQueue={add=function(action)
 action.toolkitQueueOperation={};queued[#queued+1]=action
end}
"""
        suffix="""
assert(#calls==2 and #queued==2 and calls[1]==queued[1]and calls[2]==queued[2])
assert(calls[1].location==out and calls[2].location==origin,'native walk targets changed')
assert(M.walkRecord.out.starts==0 and M.walkRecord.back.starts==0,'constructor manufactured execution')
"""
        def run(actual,mode='clean'):
            return subprocess.run([shutil.which('luajit'),'-',mode],input=prefix+actual+suffix,capture_output=True,text=True)
        result=run(block);self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        previous="   local function square(tile)return assert(getCell():getGridSquare(tile.x,tile.y,tile.z),'native makeup walk square unavailable')end\n"
        result=run(block.replace(resolver,previous,1))
        self.assertNotEqual(result.returncode,0);self.assertIn('EXTRA_NATIVE_WALK_CALLBACK',result.stderr)
        for field in ('additionalTest','additionalContext'):
            with self.subTest(field=field):
                result=run(block,field);self.assertNotEqual(result.returncode,0)
                self.assertIn('native walk constructor/duration/callback changed',result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_native_world_walk_route_requires_two_free_unblocked_steps_out_of_source_reach(self):
        source=Path(__file__).resolve().parents[1]/'tests/native_queue/makeup/shared/QueueMakeup.lua'
        script="""
package.preload['Definitions/MakeUpDefinitions']=function()end
ItemBodyLocation={MAKE_UP_FULL_FACE='face',MAKE_UP_EYES='eyes',MAKE_UP_EYES_SHADOW='shadow',MAKE_UP_LIPS='lips'}
local F=assert(loadfile(arg[1]))();local blocked=false;local free=true;local squares={}
local function square(x,y)
 local key=x..':'..y;if squares[key]then return squares[key]end
 local value={getX=function()return x end,getY=function()return y end,getZ=function()return 0 end,
  canStand=function()return true end,isFree=function()return free end,isBlockedTo=function()return blocked end}
 squares[key]=value;return value
end
getCell=function()return {getGridSquare=function(_,x,y,z)assert(z==0);return square(x,y)end}end
local origin=square(10,20);local player={getCurrentSquare=function()return origin end}
local source={kind='world-bag',x=11,y=20,z=0,id=123,owner='owned-source'}
local route=F.walkRoute(player,source)
assert(F.same(route.origin,{x=10,y=20,z=0})and F.same(route.via,{x=9,y=20,z=0})and F.same(route.out,{x=8,y=20,z=0}))
assert(route.source==source,'walk lost exact source descriptor')
blocked=true;assert(not pcall(F.walkRoute,player,source),'blocked native route admitted')
blocked=false;free=false;assert(not pcall(F.walkRoute,player,source),'occupied native route admitted')
"""
        result=subprocess.run([shutil.which('luajit'),'-',str(source)],input=script,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_native_move_case_kind_and_carried_source_mapping_matches_adapter(self):
        source=Path(__file__).resolve().parents[1]/'tests/native_queue/makeup/shared/QueueMakeup.lua'
        script="""
package.preload['Definitions/MakeUpDefinitions']=function()end
ItemBodyLocation={MAKE_UP_FULL_FACE='face',MAKE_UP_EYES='eyes',MAKE_UP_EYES_SHADOW='shadow',MAKE_UP_LIPS='lips'}
local F=assert(loadfile(arg[1]))()
assert(#F.moves==4 and #F.carriedMoves==4 and #F.worldMoves==4 and #F.depletionMoves==5 and #F.heldMoves==5)
for i=2,#arg,3 do
 local case,kind,source=arg[i],arg[i+1],arg[i+2]
 assert(F.moveCase(case)and F.moveKind(case)==kind,'native move kind mapping differs')
 assert((F.moveSupply(case)or 'root')==source and F.placed(case),'native move ancestry mapping differs')
end
assert(not F.moveCase('move-unknown')and not F.moveSupply('move-unknown'))
"""
        arguments=[value for case,kind in m.MOVE_KINDS.items() for value in (case,kind,m.MOVE_SUPPLIES.get(case,'root'))]
        result=subprocess.run([shutil.which('luajit'),'-',str(source),*arguments],input=script,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_move_old_cosmetic_waits_for_client_root_ack_before_authority_wear(self):
        source=Path(__file__).resolve().parents[1]/'tests/native_queue/makeup/server/ZZMakeupServer.lua'
        script="""
isServer=function()return true end
local handlers={};Events={}
for _,name in ipairs({'OnServerStarted','OnClientCommand','OnTick'})do Events[name]={Add=function(fn)handlers[name]=fn end}end
local prepared,wears,markers,failures=0,0,0,0
local tile={x=10,y=20,z=0};local player={getUsername=function()return 'client1'end}
local ids={case='move-earlier',items={old=4},wearPending=true}
getTimestampMs=function()return 1000 end
print=function(value)if value:find('[MAKEUP_TEST] PREPARED ',1,true)then markers=markers+1 end end
sendServerCommand=function(actor,module,name,args)
 assert(actor==player and module=='MakeupTest')
 if name=='Prepared'then assert(args.wearPending and wears==0);prepared=prepared+1
 elseif name=='WornPrepared'then assert(not args.wearPending and wears==1)
 else assert(name=='Failed');failures=failures+1 end
end
package.loaded.QueueHealthEvents={encode=function()return '{}'end}
package.loaded.QueueTestSelection={cases={'move-earlier'},options={makeup_moves=true}}
package.loaded.QueueMakeup={validPlacement=function(v)return v==tile end,same=function(a,b)return a==b end,
 atPlacement=function(actor,value)return actor==player and value==tile end,
 prepare=function()return {ids=ids}end,
 wearPrepared=function(s)assert(prepared==1 and markers==0 and s.ids==ids and ids.wearPending);wears=wears+1;ids.wearPending=nil end}
assert(loadfile(arg[1]))()
handlers.OnClientCommand('MakeupTest','Prepare',player,{case='move-earlier',placement=tile});handlers.OnTick()
assert(prepared==1 and wears==0 and markers==0,'old worn before root acknowledgement')
handlers.OnClientCommand('MakeupTest','WearPrepared',player,{case='move-earlier',item=999})
assert(failures==1 and wears==0,'foreign item acknowledged root ownership')
handlers.OnClientCommand('MakeupTest','WearPrepared',player,{case='move-earlier',item=4})
assert(wears==1 and markers==1,'authority did not publish exact acknowledged worn baseline')
"""
        result=subprocess.run([shutil.which('luajit'),'-',str(source)],input=script,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_supply_placement_uses_floor_and_current_square_before_any_setup_mutation(self):
        source=Path(__file__).resolve().parents[1]/'tests/native_queue/makeup/shared/QueueMakeup.lua'
        script="""
package.preload['Definitions/MakeUpDefinitions']=function()end
ItemBodyLocation={MAKE_UP_FULL_FACE='face',MAKE_UP_EYES='eyes',MAKE_UP_EYES_SHADOW='shadow',MAKE_UP_LIPS='lips'}
isClient=function()return false end
local F=assert(loadfile(arg[1]))()
local x,y,z=10.1,20.9,0
local sx,sy,sz=10,20,0
local square={getX=function()return sx end,getY=function()return sy end,getZ=function()return sz end}
local player={getX=function()return x end,getY=function()return y end,getZ=function()return z end,
 getCurrentSquare=function()return square end,getInventory=function()error('setup mutated before settled placement')end}
local target={x=10,y=20,z=0}
assert(F.atPlacement(player,target),'non-centered integer teleport destination should settle')
sy=19;assert(not F.atPlacement(player,target),'stale currentSquare admitted')
local ok,problem=pcall(F.prepare,player,'apply-world-container',nil,target)
assert(not ok and tostring(problem):find('has not settled',1,true),'setup mutation preceded placement guard')
sy=20;x=11.1;assert(not F.atPlacement(player,target),'stale floor position admitted')
x=10.1;assert(not F.atPlacement(player,nil)and not F.atPlacement(player,{x=10.5,y=20,z=0}))
ok,problem=pcall(F.prepare,player,'apply-nested-bag',nil,nil)
assert(not ok and tostring(problem):find('has not settled',1,true),'missing placement reached setup')
-- Schoolbags expose canBeEquipped()=BACK; their clothing BodyLocation may be nil.
ItemBodyLocation.BACK='back'
local bag={getID=function()return 10 end,getFullType=function()return 'Base.Bag_Schoolbag'end,
 getItemContainer=function()return {setExplored=function()end}end,
 canBeEquipped=function()return ItemBodyLocation.BACK end,
 getBodyLocation=function()error('backpack clothing BodyLocation was used')end}
local empty={size=function()return 0 end}
player.getInventory=function()return {getItems=function()return empty end,AddItem=function(_,kind)
 assert(kind=='Base.Bag_Schoolbag');return bag end}end
player.getWornItem=function()return nil end;player.getOnlineID=function()return 7 end
player.setGodMod=function()end;player.setGhostMode=function()end;player.setAutoDrink=function()end
player.isTimedActionInstant=function()return false end;getDebug=function()return false end
player.setWornItem=function(_,slot,item)
 assert(slot==ItemBodyLocation.BACK and item==bag,'schoolbag used an invalid native equipment slot')
 error('BACK_SLOT_CONFIRMED')
end
ok,problem=pcall(F.prepare,player,'apply-worn-bag',nil,target)
assert(not ok and tostring(problem):find('BACK_SLOT_CONFIRMED',1,true),'native backpack slot was not used before source setup: '..tostring(problem))
"""
        result=subprocess.run([shutil.which('luajit'),'-',str(source)],input=script,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_supply_server_prepare_waits_for_real_actor_coordinates_without_relocation(self):
        source=Path(__file__).resolve().parents[1]/'tests/native_queue/makeup/server/ZZMakeupServer.lua'
        script="""
isServer=function()return true end
local handlers={};Events={}
for _,name in ipairs({'OnServerStarted','OnClientCommand','OnTick'})do
 Events[name]={Add=function(callback)handlers[name]=callback end}
end
local settled=false;local calls=0;local failures=0;local replies=0;local clock=0
local target={x=10,y=20,z=0}
local player={getUsername=function()return 'client1'end}
getTimestampMs=function()return clock end
sendServerCommand=function(actor,module,name,args)
 assert(actor==player and module=='MakeupTest')
 if name=='Failed'then failures=failures+1 else assert(name=='Prepared');replies=replies+1 end
end
package.loaded.QueueHealthEvents={encode=function()return '{}'end}
package.loaded.QueueTestSelection={cases={'apply-worn-bag'},options={makeup_supplies=true}}
package.loaded.QueueMakeup={
 validPlacement=function(value)return value==target end,
 same=function(a,b)return a==b end,
 atPlacement=function(actor,value)assert(actor==player and value==target);return settled end,
 prepare=function(actor,case,previous,value)
  assert(settled and actor==player and case=='apply-worn-bag'and previous==nil and value==target)
  calls=calls+1;return {ids={case=case,placement=value}}
 end}
assert(loadfile(arg[1]))()
handlers.OnClientCommand('MakeupTest','Prepare',player,{case='apply-worn-bag'})
assert(failures==1 and calls==0,'missing placement was admitted')
handlers.OnClientCommand('MakeupTest','Prepare',player,{case='apply-worn-bag',placement=target})
assert(calls==0 and replies==0,'prepare seeded before authority position settled')
clock=500;handlers.OnTick();assert(calls==0 and replies==0)
settled=true;clock=1000;handlers.OnTick()
assert(calls==1 and replies==1,'authority failed to acknowledge exact settled position')
handlers.OnTick();assert(calls==1,'authority setup repeated after acknowledgement')
"""
        result=subprocess.run([shutil.which('luajit'),'-',str(source)],input=script,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_native_fixture_lua_parses(self):
        root=Path(__file__).resolve().parents[1]/'tests/native_queue/makeup'
        for path in root.rglob('*.lua'):
            result=subprocess.run([shutil.which('luajit'),'-',str(path)],input='assert(loadfile(arg[1]))',capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_stage_and_source_membership(self):
        selection=self.selection(supplies=True);project=Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory()as directory:
            root=Path(directory);cache=root/'cache';lua=cache/'mods/ActionQueueTest/42/media/lua'
            for side in ('client','shared','server'):(lua/side).mkdir(parents=True)
            runtime={'roles':{'client1':{'cache':str(cache)}}}
            def javac(command,**kwargs):
                classes=Path(command[command.index('-d')+1]);main=classes/'net/alexredby/makeupcapturefixture/Main.class'
                main.parent.mkdir(parents=True);main.write_bytes(b'test-class')
            with patch.object(m.subprocess,'run',side_effect=javac):m.stage(project,root,root,root,selection,{},runtime)
            self.assertEqual(runtime['fixture']['mods'],['MakeupAvatarCaptureProbe'])
            self.assertTrue((cache/'mods/MakeupAvatarCaptureProbe/42/media/java/MakeupAvatarCaptureProbe.jar').is_file())
            info=(cache/'mods/MakeupAvatarCaptureProbe/42/mod.info').read_text()
            self.assertIn('require=\\ZombieBuddy',info);self.assertIn('javaPkgName=net.alexredby.makeupcapturefixture',info)
            self.assertTrue((lua/'client/ZZStartup.lua').is_file());self.assertTrue((lua/'shared/QueueHealthEvents.lua').is_file())
            self.assertIn('[QUEUE_TEST] FAIL makeup',runtime['fixture']['failure_markers'])
        sources=m.sources(project,selection)
        self.assertTrue(all(path.is_file()for path in sources))
        self.assertEqual(len([path for path in sources if '/makeup/'in str(path)]),5)


if __name__=='__main__':unittest.main()
