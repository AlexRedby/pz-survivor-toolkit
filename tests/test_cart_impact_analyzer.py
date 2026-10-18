"""Native impact recovery requires complete, finite, phase-aware evidence."""
import csv
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT=Path(__file__).parent/'native_queue/contributions/wooden_cart_motion/analyze-impact.py'
spec=importlib.util.spec_from_file_location('cart_impact',SCRIPT)
analyzer=importlib.util.module_from_spec(spec);spec.loader.exec_module(analyzer)


def fixture(root):
    name='male-empty-native-impact';start=100000
    lines=['[WOOD_BANK] RUN_STARTED',f'[WOOD_BANK] CASE {name} attempt=0 wall={start}',
           f'[CART_IMPACT_EVENT] case={name} wall={start+2000} elapsed=2000 source=native-action-event']
    poses,grips=[],[]
    for t in range(0,12000,40):
        state='CollideWithWallState' if 2080<=t<2720 else 'PlayerGetUpState' if 2720<=t<3520 else 'PlayerMovementState'
        protected=state in analyzer.PROTECTED
        row=dict(case=name,wall=start+t,elapsed=t,x=10+max(0,t-7000)/2000,y=20,
                 state=state,action='collide' if state=='CollideWithWallState' else 'getup' if protected else 'sprint',
                 run=False,sprint=not protected,enabled=not protected,steering=not protected,
                 hit=False,knocked=False,getup=state=='PlayerGetUpState',ragdoll=False,ignore=protected,
                 pivot=not protected,brake=False,stepX=0,stepY=0 if protected else 1,pace=0 if protected else 1,
                 id=1,secondary=1,cargo=0,itemPhase=.5,brace=0)
        lines.append('[CART_IMPACT_SAMPLE] '+' '.join(f'{k}={str(v).lower() if isinstance(v,bool) else v}' for k,v in row.items()))
        matrix=[1.,0,0,0,0,1.,0,0,0,0,1.,0,0,0,0,1.]
        poses.append(dict(wallTimeMillis=start+t,bones={key:matrix for key in analyzer.BONEMAP},
                          tracks=[dict(name='Bob_SprintIntoWall' if state=='CollideWithWallState' else 'Bob_Idle',weight=1)]))
        if not protected:grips.append(dict(wallTimeMillis=start+t,result=True,threw=False))
    lines += [f'[WOOD_BANK] COMPLETE {name} wall={start}', '[WOOD_BANK] ALL_COMPLETE cases=1']
    (root/'action-tail-poses.jsonl').write_text(''.join(json.dumps(r)+'\n' for r in poses))
    (root/'wood-grip-poses.jsonl').write_text(''.join(json.dumps(r)+'\n' for r in grips))
    with (root/'wood-wheel-native.csv').open('w') as stream:
        writer=csv.DictWriter(stream,fieldnames=['event','wallTimeMillis','phase','wheelX','wheelY','wheelZ','contactZ']);writer.writeheader()
        writer.writerows(dict(event='draw',wallTimeMillis=r['wallTimeMillis'],phase=.5,wheelX=1,wheelY=2,wheelZ=7,contactZ=7) for r in grips)
    return '\n'.join(lines),[name]


class ImpactTests(unittest.TestCase):
    def test_guarded_wall_needs_actual_contact_and_quiet_xy(self):
        with tempfile.TemporaryDirectory() as path:
            root=Path(path);text,names=fixture(root)
            old=names[0];name='male-empty-sprint-wall';lines=[]
            for line in text.replace(old,name).splitlines():
                if '[CART_IMPACT_EVENT]' in line:continue
                if '[CART_IMPACT_SAMPLE]' in line:
                    r=analyzer.fields(line.split('[CART_IMPACT_SAMPLE] ',1)[1]);t=int(r['elapsed'])
                    r.update(state='PlayerMovementState',action='sprint',enabled='true',steering='true',pivot='true',getup='false',ignore='false',sprint='true',
                             x=10-4.3*max(0,min(1,(t-1000)/3000))+max(0,t-7000)/2000,
                             stepY=0 if 4000<=t<6000 else 1,pace=0 if 4000<=t<6000 else 1,brace=1 if 4000<=t<6000 else 0)
                    line='[CART_IMPACT_SAMPLE] '+' '.join(f'{k}={v}' for k,v in r.items())
                lines.append(line)
            text='\n'.join(lines).replace('[WOOD_BANK] RUN_STARTED',f'[WOOD_BANK] RUN_STARTED\n[CART_COLLISION_LAYOUT] case={name} wallX=4')
            self.assertTrue(analyzer.analyze(root,text,[name])['functionalPass'])
            for bad in (text.replace('x=5.7','x=10'),text.replace('y=20','y=21',130),text.replace('brace=1','brace=0')):
                with self.assertRaises(AssertionError):analyzer.analyze(root,bad,[name])

    def test_complete_native_lifecycle(self):
        with tempfile.TemporaryDirectory() as path:
            root=Path(path);text,names=fixture(root)
            result=analyzer.analyze(root,text,names)
            self.assertTrue(result['functionalPass'])
            self.assertEqual(result['cases'][0]['protectedStates'],['CollideWithWallState','PlayerGetUpState'])

    def test_rejects_missing_or_unsafe_evidence(self):
        mutations={
            'retained controller':lambda s:s.replace('state=CollideWithWallState action=collide run=false sprint=false enabled=false','state=CollideWithWallState action=collide run=false sprint=false enabled=true'),
            'no getup':lambda s:s.replace('PlayerGetUpState','PlayerMovementState'),
            'nan':lambda s:s.replace('itemPhase=0.5','itemPhase=nan',1),
            'wrong owner':lambda s:s.replace('secondary=1','secondary=2',1),
            'cargo changed':lambda s:s.replace('cargo=0','cargo=1',1),
            'no actual sprint':lambda s:s.replace('sprint=true','sprint=false'),
            'no recovery':lambda s:s.replace('state=PlayerMovementState action=sprint run=false sprint=true enabled=true','state=PlayerMovementState action=sprint run=false sprint=true enabled=false'),
            'no event provenance':lambda s:s.replace('source=native-action-event','source=physical-wall'),
            'missing phase samples':lambda s:'\n'.join(line for line in s.splitlines() if 'state=CollideWithWallState' not in line),
            'incomplete scene':lambda s:s.replace('ALL_COMPLETE cases=1','ALL_COMPLETE cases=0'),
        }
        for name,mutate in mutations.items():
            with self.subTest(name=name),tempfile.TemporaryDirectory() as path:
                root=Path(path);text,names=fixture(root)
                with self.assertRaises((AssertionError,KeyError,ValueError)):
                    analyzer.analyze(root,mutate(text),names)

    def test_render_and_grip_are_required(self):
        for filename,content in [('action-tail-poses.jsonl',''),('wood-grip-poses.jsonl',''),
                                 ('action-tail-poses.jsonl',json.dumps(dict(wallTimeMillis=100000,bones={'foot':[float('nan')]*16},tracks=[]))+'\n')]:
            with self.subTest(filename=filename),tempfile.TemporaryDirectory() as path:
                root=Path(path);text,names=fixture(root);(root/filename).write_text(content)
                with self.assertRaises(AssertionError):analyzer.analyze(root,text,names)

    def test_rejects_bad_samples_beside_good_samples(self):
        for defect in ('grip','bones','tracks','wheel'):
            with self.subTest(defect=defect),tempfile.TemporaryDirectory() as path:
                root=Path(path);text,names=fixture(root)
                if defect=='wheel':
                    p=root/'wood-wheel-native.csv';s=p.read_text().replace('draw,101000,0.5','draw,101000,NaN');p.write_text(s)
                else:
                    p=root/('wood-grip-poses.jsonl' if defect=='grip' else 'action-tail-poses.jsonl')
                    rows=[json.loads(line) for line in p.read_text().splitlines()]
                    row=next(r for r in rows if r['wallTimeMillis']==101000)
                    if defect=='grip':row['result']=False
                    elif defect=='bones':row['bones']={}
                    else:row['tracks'][0]['weight']=float('nan')
                    p.write_text(''.join(json.dumps(r)+'\n' for r in rows))
                with self.assertRaises(AssertionError):analyzer.analyze(root,text,names)


if __name__=='__main__':unittest.main()
