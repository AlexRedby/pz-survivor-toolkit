import copy
import json
import tempfile
import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from queue_checks.adapters import device_battery_binding as a
from tests.test_queue_tv_controls_adapter import placement_proof


def evidence(kind='mp',mode='toolkit',case='root'):
    origin=dict(x=11,y=20,z=0);wrong=dict(x=10,y=20,z=0,index=1);target=dict(wrong,index=2)
    source=dict(kind=case,bag=dict(id=20,type='Base.Bag_Military',location='Back') if case=='worn-bag' else False,
                world=dict(x=11,y=19,z=0,index=3) if case=='world' else False)
    ids=dict(case=case,source=source,mode=mode,origin=origin,placementProof=placement_proof(origin,'replica' if kind=='mp' else 'local'),
             wrong=wrong,target=target,battery=dict(id=10,uses=50,maxUses=100),
             front=dict(id=11,type='Base.BookCarpentry1',pages=220,initial=218),tail=dict(id=12,type='Base.BookCooking1',pages=220,initial=218))
    def snapshot(phase):
        return dict(case=case,source=source,sourceCount=1 if phase=='input' else 0,rootCount=1 if phase=='input' and case=='root' else 0,actorCount=1 if phase=='input' and case!='world' else 0,wrong=dict(identity=wrong,battery=False,power=0),
          target=dict(identity=target,battery=phase=='baseline',power=.5 if phase=='baseline' else 0),inputPresent=phase=='input',
          batteries=[dict(id=10 if phase=='input' else 13,uses=50,maxUses=100)] if phase=='final' or phase=='input' and case!='world' else [],
          books={n:dict(id=ids[n]['id'],root=True,pages=220 if phase=='final' else 218,characterPages=220 if phase=='final' else 218) for n in ('front','tail')})
    commands=[];acks=[]
    for index,name in enumerate(('insert','front','eject','tail')):
        battery=name in ('insert','eject');c=dict(name=name,type='ISDeviceBatteryAction' if battery else 'ISReadABook',
          producer='native RWMPower callback' if battery else 'native ISReadABook constructor',duration=30 if battery else 52800,
          started=True,progress=True,startedAt=100+index)
        if kind=='mp' and battery:
            ack=dict(kind='ISDeviceBatteryAction',transaction=index+1,token=f'{index+1:08x}-1234-1234-1234-123456789abc',state='completed');c['ack']=ack
            acks.extend(dict(case=case,name=name,kind=ack['kind'],transaction=ack['transaction'],token=ack['token'],state=s) for s in ('started','completed'))
        commands.append(c)
    if mode=='toolkit' and case=='root':
        commands.insert(2,dict(name='cancelled-eject',type='ISDeviceBatteryAction',producer='native RWMPower callback',duration=30,started=False,progress=False,cancelled=True))
    baseline=snapshot('baseline');final=snapshot('final')
    row=dict(ids=copy.deepcopy(ids),clientPlacement=placement_proof(origin),input=snapshot('input'),baseline=copy.deepcopy(baseline),
       authorityBaseline=copy.deepcopy(baseline),client=copy.deepcopy(final),server=copy.deepcopy(final),commands=commands,
       status='passed',edit=dict(cancelled=mode=='toolkit' and case=='root',reordered=mode=='toolkit' and case=='root',untouched=True),queueIdle=True,settleMilliseconds=1000)
    selection=dict(kind=kind,mode=mode)
    return row,selection,ids,baseline,final,acks


class BatteryEvidenceTests(unittest.TestCase):
    def test_receipts(self):
        for kind in ('sp','mp'):
            for mode in ('native','toolkit'):
                for case in a.CASES:
                    self.assertEqual([],a.check_case(*evidence(kind,mode,case)))
    def test_grouped_logs_require_ordered_authority(self):
        cases=list(a.CASES);selection=dict(kind='mp',mode='toolkit')
        client=['[QUEUE_CHECK] '+json.dumps(dict(suite='device-battery-binding',event='setup',cases=cases,queueEnabled=True,nativeDurations=True))]
        server=[]
        for case in cases:
            row,_,ids,baseline,final,acks=evidence(case=case)
            row.update(suite='device-battery-binding',event='case',id=case,actor='client1',kind='mp',mode='toolkit')
            client.append(a.PREFIX+'CLIENT_PLACEMENT '+json.dumps(dict(case=case,proof=row['clientPlacement'])))
            client.append('[QUEUE_CHECK] '+json.dumps(row))
            client.extend(a.PREFIX+'ACK '+json.dumps(ack) for ack in acks)
            for marker,value in [('PREPARED',ids),('BASELINE',baseline),('VERIFIED',final)]: server.append(a.PREFIX+marker+' '+json.dumps(value))
        client.append('[QUEUE_CHECK] '+json.dumps(dict(suite='device-battery-binding',event='complete',cases=cases,performed=len(cases),failed=0,skipped=0)))
        client.append(a.PREFIX+'COMPLETE '+json.dumps(dict(cases=cases)))
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'client1-launch.log').write_text('\n'.join(client));(root/'server-launch.log').write_text('\n'.join(server))
            self.assertEqual([],a.verify(root,selection,{})['issues'])
            (root/'server-launch.log').write_text('\n'.join(server[:-1]))
            self.assertTrue(a.verify(root,selection,{})['issues'])
    def test_wrong_source_and_retained_battery_rejected(self):
        e=evidence(case='worn-bag');e[0]['baseline']['sourceCount']=1;self.assertTrue(a.check_case(*e))
        e=evidence(case='world');e[2]['source']['world']['x']+=1;e[0]['ids']=copy.deepcopy(e[2]);self.assertTrue(a.check_case(*e))
        e=evidence(case='worn-bag');e[0]['input']['rootCount']=1;self.assertTrue(a.check_case(*e))
    def test_wrong_target_and_lost_charge_rejected(self):
        e=evidence();e[0]['server']['wrong']['battery']=True;self.assertTrue(a.check_case(*e))
        e=evidence();e[0]['client']['batteries'][0]['uses']=5;self.assertTrue(a.check_case(*e))
        e=evidence();next(c for c in e[0]['commands']if c['name']=='eject')['ack']['token']=e[0]['commands'][0]['ack']['token'];self.assertTrue(a.check_case(*e))
