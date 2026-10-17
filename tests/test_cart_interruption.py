"""Cancellation analyzer must reject lifecycle, cargo and first-render failures."""
import importlib.util
import json
from pathlib import Path
import unittest

path=Path(__file__).resolve().parents[1]/'tests/native_queue/contributions/wooden_cart_motion/analyze-interruption.py'
spec=importlib.util.spec_from_file_location('cart_interruption',path)
analyzer=importlib.util.module_from_spec(spec);spec.loader.exec_module(analyzer)


def fixture():
    lines=['[WOOD_BANK] RUN_STARTED'];life=[];body=[];grip=[];world=[]
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
            row=dict(case=name,start=start,wall=start+elapsed,elapsed=elapsed,id=index+1,
                stage='cancelled' if cancelled else 'other',heldID=index+1 if held else -1,secondaryID=index+1 if held else -1,
                worldID=-1 if held else index+1,worldCount=int(not held),woodWorldCount=int(not held),inventoryCount=int(held),
                actionType=analyzer.TYPES.get(current,''),progress=analyzer.THRESHOLDS[phase] if elapsed==request else .2,
                cargo=50,cargoIDs='stable',cargoCount=1,condition=100,worldAlpha=1,worldX=1,worldY=2,worldZ=7,worldRotation=135,worldObjectAlpha=1,
                nativeActions=int(bool(current)),luaActions=int(bool(current)),active=bool(current),rendered=bool(current),
                ToolkitWoodCartAction=bool(current),PerformingAction='ToolkitWoodCart' if current else '',IsPerformingAnAction=bool(current),
                ToolkitCartMotion=held and not current)
            lines.append('[WOOD_INTERACTION_SAMPLE] '+json.dumps(row))
            if elapsed in events: lines.append('[WOOD_INTERACTION_EVENT] '+json.dumps(dict(row,event=events[elapsed])))
            if cancelled:
                body.append(dict(wallTimeMillis=start+elapsed,cart=[0]*13+[.097179376,0,1],
                                 afterStopActionId=index*2 if elapsed==request+25 else 0))
                grip.append(dict(wallTimeMillis=start+elapsed,result=True,threw=False))
                world.append(dict(wallTimeMillis=start+elapsed,itemId=index+1,renderStatus='Ready',alpha=1))
        for event,elapsed,identity in [('start',1000 if not owned else 5200,index*2),('stop',request+1,index*2),
                                      ('start',retry+25,index*2+1),('perform',end,index*2+1),('complete',end,index*2+1)]:
            life.append(dict(wallTimeMillis=start+elapsed,event=event,metaType=analyzer.TYPES[action],nativeActionId=identity,
                             finished=event in ('perform','complete'),threw=False))
        lines.append(f'[WOOD_BANK] COMPLETE {name} wall={start} file=/owned/{name}.mp4 frames=600 seconds=20.0')
    lines.append('[WOOD_BANK] ALL_COMPLETE cases=12')
    return '\n'.join(lines),life,body,grip,world


class CancellationChecks(unittest.TestCase):
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
        for position in (1,2,3,4):
            broken=list(values);broken[position]=[]
            with self.assertRaises(AssertionError): analyzer.analyze(*broken)
        broken=list(values);broken[2]=[r for r in values[2] if not r.get('afterStopActionId')]
        with self.assertRaises(AssertionError): analyzer.analyze(*broken)


if __name__=='__main__': unittest.main()
