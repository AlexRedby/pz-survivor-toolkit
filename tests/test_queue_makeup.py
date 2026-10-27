import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import struct
import zlib

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from queue_checks.adapters import makeup as m


class MakeupEvidenceTests(unittest.TestCase):
    def selection(self,mode='toolkit',kind='sp'):
        return dict(suite='makeup',cases=list(m.SP_CASES if kind=='sp' else m.MP_CASES),mode=mode,kind=kind,
                    clients=1,languages=['EN'],mods=list(m.MODS),options={'mp_host':True} if kind=='mp' else {})

    def evidence(self,case,selection):
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
            client+=raw('BEFORE_TAIL',dict(case=row['id'],evidence=row['beforeTail']))
            authority+=raw('VERIFIED',row['receipt'])
            if selection['kind']=='sp':client+=authority;authority=''
            client+=event(row)
        client+=event(dict(context,event='complete',cases=selection['cases'],performed=len(rows),failed=0,skipped=0))
        client+=raw('COMPLETE',dict(cases=selection['cases']))
        filename='makeup-preview-'+selection['kind']+'-'+selection['mode']+'.png'
        client+=raw('SCREENSHOT',dict(case='preview-close',file=filename,renderFrames=3,renderMs=500,fadeClear=True,nativeRendered=True))
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

    def test_stage_and_source_membership(self):
        selection=self.selection();project=Path(__file__).resolve().parents[1]
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
