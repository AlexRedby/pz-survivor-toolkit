import copy
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
    def selection(self,mode='toolkit',kind='sp',supplies=False,moves=False):
        value= dict(suite='makeup',cases=list(m.SP_CASES if kind=='sp' else m.MP_CASES),mode=mode,kind=kind,
                    clients=1,languages=['EN'],mods=list(m.MODS),options={'mp_host':True} if kind=='mp' else {})
        if supplies:value['options']['makeup_supplies']=True;value['cases']=list(m.cases(value))
        if moves:value['options']['makeup_moves']=True;value['cases']=list(m.cases(value))
        return value

    def evidence(self,case,selection):
        if selection.get('options',{}).get('makeup_moves'):return self.move_evidence(case,selection)
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
        base=copy.deepcopy(selection);base['options'].pop('makeup_moves')
        if case=='move-deny-nested':
            base['options']['makeup_supplies']=True;row=self.supply_evidence('apply-nested-bag',base)
        else:row=self.evidence('apply-replace' if case=='move-earlier' else 'apply-empty',base)
        ids=row['ids'];row['id']=ids['case']=case;ids['move']=True;ids['placement']=dict(x=10,y=20,z=0)
        ids['items']['middle']=5;ids['types']['middle']='Base.BookCooking1';ids['middleTotal']=100;ids['middleInitial']=99;ids['frontInitial']=92
        if case=='move-deny-nested':ids['items'].pop('old');ids['types'].pop('old');row['submitted']['previous']=False;row.pop('applyQueues')
        if case=='move-deny-writer':ids['items']['writer']=6;ids['types']['writer']='Base.Socks_Ankle'
        values=[ids['baseline'],row['clientFinal'],row['receipt']['snapshot'],row['beforeTail']['snapshot']]
        for point in row['checkpoints']:
            for role in ('client','authority'):point[role]['case']=case;values.append(point[role]['snapshot'])
            if case=='move-deny-nested' and point['client']['preview']:point['client']['preview']['previous']=False
        row['receipt']['case']=case
        for value in values:
            value['case']=case;value['root'].append(dict(id=5,kind='Base.BookCooking1'))
            value['placement']=dict(tile=dict(x=10,y=20,z=0),square=dict(x=10,y=20,z=0))
            late=value['kit']['uses']==4
            value['frontPages']=100 if late else 92;value['middlePages']=100 if late else 99
            if case=='move-deny-nested':value['root']=[v for v in value['root'] if v['id']!=4];value['worn']=[v for v in value['worn'] if v['id']!=4]
            if case=='move-deny-writer':
                # The native actor already wears another sock item. Wear replaces
                # its slot while preserving both physical items in root.
                value['root'].extend([dict(id=6,kind='Base.Socks_Ankle'),dict(id=7,kind='Base.Socks_Ankle')])
                value['worn'].append(dict(id=6 if late else 7,kind='Base.Socks_Ankle',slot='base:socks',root=True,sameReference=True,container='root'))
            value['root'].sort(key=lambda v:v['id']);value['worn'].sort(key=lambda v:v['slot'])
        before,after,starts,accepted=m.move_orders(case,selection['mode']=='toolkit')
        edit=dict(at=25,accepted=accepted,reason=False if accepted or selection['mode']=='native' else 'dependent',before=before,after=after,
            bodyUnallocated=True,ownershipPreserved=True,frontPages=93,frontDelta=.125,frontNativeBefore='native-front',frontNativeAfter='native-front',frontRetained=True,tailRetained=True)
        row['edit']=edit;row['startOrder']=starts;row['supplyTransferStarts']=0
        if case=='move-promote' and accepted:row['readerResume']=dict(pages=93,resumedPages=93,native='native-resumed-front')
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
        self.assertEqual([case['id'] for case in suite['cases']],m.MP_CASES+m.SUPPLY_MP_CASES+m.MOVE_CASES)

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
                             'tail-early','middle-short','kit-cost','output-reference','old-proxy','writer-lost','nested-root','transfer','admission','receipt-cost'):
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
                elif mutation=='nested-root':rows[4]['checkpoints'][1]['client']['snapshot']['kit']['root']=True
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
        self.assertEqual(len([path for path in sources if '/makeup/'in str(path)]),4)


if __name__=='__main__':unittest.main()
