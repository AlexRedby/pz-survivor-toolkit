"""Native path proof rejects fake input, missing lifecycle and unsafe cart bounds."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('cart_path', ROOT/'tests/native_queue/contributions/wooden_cart_motion/analyze-path.py')
analyzer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analyzer)


def fixture():
    lines = ['[WOOD_BANK] RUN_STARTED']
    life = []
    for index, name in enumerate(sorted(analyzer.CASES)):
        start = 100000+index*15000
        kind = name.split('-', 2)[2]
        end = 1700 if kind == 'cancel' else 3500
        manual, stopped = end+300, end+1200
        success = kind in ('straight', 'door-open')
        result = 'Succeeded' if success else 'Working' if kind == 'cancel' else 'Failed'
        sx, tx = (.65 if kind == 'overlap' else 2.5), -2.5
        ex = tx if success else sx if kind == 'overlap' else sx-.5
        events = {0:'prepared',1000:'queued',end:'terminal',manual:'manual',stopped:'manualStopped',12000:'settled'}
        if kind == 'cancel':
            events[1600] = 'cancelRequested'
        for at in range(0, 12001, 100):
            active = 1000 < at < end
            x = sx+(ex-sx)*max(0, min(1, (at-1000)/(end-1000))) + .2*max(0, min(1, (at-manual)/900))
            row = dict(case=name,start=start,wall=start+at,elapsed=at,x=x,y=.5,z=7,
                       female=name.startswith('female'),id=200+index,cargo=30 if '-full-' in name else 0,
                       hasPath=active,nativeActions=int(active),luaActions=int(active),motion=True,
                       pivot=at>manual,result=result if at>=end else 'Working' if active else '',
                       heading=3.14159,drive=7 if manual<at<=stopped else 0,
                       goalX=tx,goalY=.5,startX=sx,startY=.5,wallX=0,gapY=0,doorOpen=kind=='door-open')
            lines.append('[CART_PATH_SAMPLE] '+json.dumps(row))
            if at in events:
                receipt=dict(row,event=events[at])
                if at==manual:
                    receipt['drive']=7
                if at==stopped:
                    receipt['drive']=0
                lines.append('[CART_PATH_EVENT] '+json.dumps(receipt))
        phases = [('start',1001),('perform',end-5),('complete',end-4)] if success else [('start',1001),('stop',end-5)]
        for event, at in phases:
            life.append(dict(wallTimeMillis=start+at,metaType='ISWalkToTimedActionF',event=event,
                             nativeActionId=index+1,primaryHandItemId=200+index,secondaryHandItemId=200+index,threw=None))
        lines.append(f'[WOOD_BANK] COMPLETE {name} wall={start}')
    lines.append('[WOOD_BANK] ALL_COMPLETE cases=24')
    return '\n'.join(lines), life


def corrupt(text, change):
    lines=[]
    for line in text.splitlines():
        if line.startswith('[CART_PATH_'):
            prefix, value=line.split('] ',1)
            row=json.loads(value)
            change(row)
            line=prefix+'] '+json.dumps(row)
        lines.append(line)
    return '\n'.join(lines)


class PathAnalyzerTests(unittest.TestCase):
    def test_valid_stock_route_and_same_tick_input_events(self):
        result,cases=analyzer.motion(*fixture())
        self.assertTrue(result['motionPass'])
        self.assertEqual(len(cases),24)

    def test_cancel_and_terminal_can_share_a_clock_tick(self):
        text, life=fixture()
        def edit(row):
            if row['case'].endswith('-cancel') and row.get('event')=='cancelRequested':
                row['elapsed']=1700;row['wall']=row['start']+1700
        tied=corrupt(text,edit)
        with self.assertRaises(AssertionError):
            analyzer.motion(tied,life)
        # Keep native stop after the request even when all receipts share a millisecond.
        starts={r['nativeActionId']:r['wallTimeMillis']-1001 for r in life if r['event']=='start'}
        for row in life:
            if row['event']=='stop' and row['wallTimeMillis']-starts[row['nativeActionId']]==1695:
                row['wallTimeMillis']=starts[row['nativeActionId']]+1700
        self.assertTrue(analyzer.motion(tied,life)[0]['motionPass'])

    def test_rejects_visual_input_ownership_and_cleanup_failures(self):
        text, life=fixture()
        target='female-empty-straight'
        for failure in ('visual','pivot-takeover','fake-input','wrong-cart','leaked-path','missing-manual','failed-clear-route','false-success','nonfinite'):
            with self.subTest(failure=failure):
                def edit(row):
                    if row['case']!=target:
                        return
                    if failure=='visual' and row['hasPath']: row['motion']=False
                    if failure=='pivot-takeover' and row['hasPath']: row['pivot']=True
                    if failure=='fake-input' and row['elapsed']==1200: row['drive']=1
                    if failure=='wrong-cart' and row['elapsed']==1200: row['id']+=1
                    if failure=='leaked-path' and row.get('event')=='terminal': row['hasPath']=True
                    if failure=='missing-manual' and row['elapsed']>3900: row['pivot']=False
                    if failure=='failed-clear-route' and row.get('event')=='terminal': row['result']='Failed'
                    if failure=='false-success' and row.get('event')=='terminal': row['x']=row['startX']
                    if failure=='nonfinite' and row['elapsed']==1200: row['x']=float('nan')
                with self.assertRaises(AssertionError):
                    analyzer.motion(corrupt(text,edit),life)

    def test_rejects_missing_stop_and_wrong_native_item(self):
        text, life=fixture()
        for failure in ('missing','wrong-item'):
            with self.subTest(failure=failure):
                broken=json.loads(json.dumps(life))
                if failure=='missing':
                    broken.pop(next(i for i,r in enumerate(broken) if r['event']=='stop'))
                else:
                    broken[0]['secondaryHandItemId']=-1
                with self.assertRaises(AssertionError):
                    analyzer.motion(text,broken)

    def test_sampled_wall_gap_and_overlap_gates(self):
        for kind, failure in [('door-closed',False),('door-closed',True),('door-open',False),('door-open',True),
                              ('corner',False),('corner',True),('overlap',False),('overlap',True)]:
            with self.subTest(kind=kind,failure=failure), tempfile.TemporaryDirectory() as folder:
                root=Path(folder)
                name='male-empty-'+kind
                cases={name:dict(start=100000,first=dict(wallX=0,gapY=0),spec=kind)}
                frames=[]
                for index in range(120):
                    low=-.3+index*.005 if kind=='overlap' else .1
                    if failure:
                        low=-.1 if kind!='overlap' else -.3
                    bounds=dict(minX=low,maxX=.6,minY=.2,maxY=1.2 if kind=='door-open' and failure else .8)
                    frames.append(dict(wallTimeMillis=100000+index*100,female=False,slotX=0,slotY=0,bounds=bounds))
                if kind=='door-open':
                    for frame in frames: frame['bounds']['minX']=-.1
                (root/'action-lifecycle.jsonl').write_text('')
                (root/'body-clearance.jsonl').write_text(''.join(json.dumps(r)+'\n' for r in frames))
                with patch.object(analyzer,'motion',return_value=(dict(motionPass=True,cases=[]),cases)), \
                     patch.object(analyzer.footprint,'mesh',return_value=(None,'test-mesh')), \
                     patch.object(analyzer.footprint,'world_bounds',side_effect=lambda frame,_:frame['bounds']):
                    result=analyzer.analyze('',root)
                self.assertEqual(result['footprintVerified'],not failure,result)


if __name__=='__main__':
    unittest.main()
