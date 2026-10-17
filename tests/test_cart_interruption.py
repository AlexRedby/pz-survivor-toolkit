"""Cancellation analyzer must reject lifecycle, cargo and first-render failures."""
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest

path=Path(__file__).resolve().parents[1]/'tests/native_queue/contributions/wooden_cart_motion/analyze-interruption.py'
spec=importlib.util.spec_from_file_location('cart_interruption',path)
analyzer=importlib.util.module_from_spec(spec);spec.loader.exec_module(analyzer)


def fixture():
    lines=['[WOOD_BANK] RUN_STARTED'];life=[];body=[];grip=[];world=[];draws=[];tail=[]
    for index,name in enumerate(analyzer.CASES):
        start=100000+index*25000;action,phase,route=name.split('-');owned=action=='drop'
        request=6000 if owned else 1500;retry=request+950;end=10500 if owned else 5000
        events={0:'prepared',700:'pickupQueued',request:'cancelRequested',request+25:'cancelled',retry:'retryQueued',
                **({4000:'pickedUp',5100:'dropQueued',10500:'dropped'} if owned else {5000:'pickedUp',6100:'dropQueued',9500:'dropped'})}
        lines.append(f'[WOOD_BANK] CASE {name} attempt=0 wall={start}')
        for elapsed in range(0,20001,25):
            cancelled=request+25<=elapsed<retry
            held=4000<=elapsed<10500 if owned else 5000<=elapsed<9500
            current=('pickup' if 700<=elapsed<4000 else 'drop' if 5100<=elapsed<10500 else '') if owned else ('pickup' if 700<=elapsed<5000 else 'drop' if 6100<=elapsed<9500 else '')
            if cancelled or request<elapsed<=retry: current=''
            recovering=cancelled and elapsed<request+425
            recovery_progress=max(0,analyzer.THRESHOLDS[phase]*(1-(elapsed-request-25)/400))
            row=dict(case=name,start=start,wall=start+elapsed,elapsed=elapsed,id=index+1,
                stage='cancelled' if cancelled else 'other',heldID=index+1 if held else -1,secondaryID=index+1 if held else -1,
                worldID=-1 if held else index+1,worldCount=int(not held),woodWorldCount=int(not held),inventoryCount=int(held),
                actionType=analyzer.TYPES.get(current,''),progress=analyzer.THRESHOLDS[phase] if elapsed==request else .2,
                cargo=50,cargoIDs='stable',cargoCount=1,condition=100,worldAlpha=1,worldX=1,worldY=2,worldZ=7,worldRotation=135,worldObjectAlpha=1,
                nativeActions=int(bool(current)),luaActions=int(bool(current)),active=bool(current),recovering=recovering,presentationProgress=recovery_progress if recovering else .2,rendered=bool(current) or recovering,
                ToolkitWoodCartAction=bool(current),PerformingAction='ToolkitWoodCart' if current else '',IsPerformingAnAction=bool(current),
                ToolkitCartMotion=held and not current)
            lines.append('[WOOD_INTERACTION_SAMPLE] '+json.dumps(row))
            if elapsed in events: lines.append('[WOOD_INTERACTION_EVENT] '+json.dumps(dict(row,event=events[elapsed])))
            if request-75<=elapsed<retry:
                matrix=[76.5,0,0,0,0,76.5,0,0,0,0,76.5,0,0,.097179376,0,1]
                bones={}
                for bone_name in ('Bip01_Spine','Bip01_L_Hand','Bip01_R_Hand'):
                    bone=[1,0,0,0,0,1,0,0,0,0,1,0,0,1,0,1];bones[bone_name]=bone
                for side in 'LR':
                    for part,y,z in [('Thigh',1,0),('Calf',.5,.1),('Foot',0,0),('Toe0',0,.2)]:
                        bones['Bip01_'+side+'_'+part]=[1,0,0,0,0,1,0,0,0,0,1,0,0,y,z,1]
                frame=dict(wallTimeMillis=start+elapsed,cart=matrix,bones=bones,cartModelCount=1)
                if elapsed==request+25: frame['afterStopActionId']=index*2+1
                body.append(frame);tail.append(frame)
                source='held' if elapsed<request+425 or owned else 'world'
                draws.append(dict(wall=start+elapsed,source=source,itemId=-1 if source=='held' else index+1,
                                  x=0.,y=0.,angle=0.,phase=0.,cart=matrix))
            if cancelled:
                grip.append(dict(wallTimeMillis=start+elapsed,result=True,threw=False))
                world.append(dict(wallTimeMillis=start+elapsed,itemId=index+1,renderStatus='Ready',alpha=1))
        for event,elapsed,identity in [('start',1000 if not owned else 5200,index*2+1),('stop',request+1,index*2+1),
                                      ('start',retry+25,index*2+2),('perform',end,index*2+2),('complete',end,index*2+2)]:
            life.append(dict(wallTimeMillis=start+elapsed,event=event,metaType=analyzer.TYPES[action],nativeActionId=identity,
                             finished=event in ('perform','complete'),threw=False))
        lines.append(f'[WOOD_BANK] COMPLETE {name} wall={start} file=/owned/{name}.mp4 frames=600 seconds=20.0')
    lines.append('[WOOD_BANK] ALL_COMPLETE cases=12')
    return '\n'.join(lines),life,body,grip,world,draws,tail


class CancellationChecks(unittest.TestCase):
    def test_cli_preserves_failed_evidence_reason(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);log=root/'capture.log';log.write_text('[WOOD_BANK] RUN_STARTED\n')
            output=root/'failed.json'
            result=subprocess.run([sys.executable,str(path),'--profile',str(root),'--log',str(log),'--output',str(output)],capture_output=True,text=True)
            self.assertEqual(result.returncode,1)
            report=json.loads(output.read_text())
            self.assertFalse(report['functionalPass']);self.assertFalse(report['recoveryVerified'])
            self.assertFalse(report['wheelCoverageVerified']);self.assertIn('action-lifecycle.jsonl',report['failures'][0])

    def test_valid_and_corrupted_native_receipts(self):
        values=fixture()
        self.assertTrue(analyzer.analyze(*values)['functionalPass'])
        for position,field,value in [(2,'cart',[0]*13+[.17,0,1]),(3,'result',False),(4,'transitionHidden',True)]:
            with self.subTest(field=field):
                broken=list(values);broken[position]=[dict(row,**{field:value}) for row in values[position]]
                self.assertFalse(analyzer.analyze(*broken)['functionalPass'])
        for field,value in [('event','complete'),('nativeActionId',-100)]:
            broken=list(values);broken[1]=[dict(row,**{field:value}) if row['event']=='stop' else row for row in values[1]]
            with self.assertRaises(AssertionError): analyzer.analyze(*broken)
        broken=list(values);broken[0]=values[0].replace('"cargoIDs": "stable"','"cargoIDs": "changed"',1)
        self.assertFalse(analyzer.analyze(*broken)['functionalPass'])
        for position in (1,2,3,4,5,6):
            broken=list(values);broken[position]=[]
            with self.assertRaises(AssertionError): analyzer.analyze(*broken)
        broken=list(values);broken[2]=[r for r in values[2] if 'afterStopActionId' not in r]
        with self.assertRaises(AssertionError): analyzer.analyze(*broken)
        broken=list(values);broken[5]=[dict(r) for r in values[5]];broken[5][5]['phase']=.3
        self.assertFalse(analyzer.analyze(*broken)['functionalPass'])
        broken=list(values);broken[6]=json.loads(json.dumps(values[6]));broken[6][5]['bones']['Bip01_Spine'][13]+=.1
        self.assertFalse(analyzer.analyze(*broken)['functionalPass'])
        broken=list(values);broken[6]=[dict(r,cartModelCount=2) for r in values[6]]
        self.assertFalse(analyzer.analyze(*broken)['functionalPass'])
        broken=list(values);broken[6]=[{k:v for k,v in r.items() if k!='cartModelCount'} for r in values[6]]
        with self.assertRaises(KeyError): analyzer.analyze(*broken)
        broken=list(values);broken[2]=json.loads(json.dumps(values[2]));broken[2][5]['bones']['Bip01_L_Calf'][14]=-.1
        self.assertFalse(analyzer.analyze(*broken)['functionalPass'])
        broken=list(values);broken[0]=values[0].replace('"recovering": true','"recovering": false')
        with self.assertRaises(AssertionError): analyzer.analyze(*broken)


if __name__=='__main__': unittest.main()
