"""Rapid action evidence rejects missing scenes, fake restarts and shared native clocks."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

path = Path(__file__).resolve().parents[1]/'tests/native_queue/contributions/wooden_cart_motion/analyze-repeat.py'
spec = importlib.util.spec_from_file_location('cart_repeat',path)
analyzer = importlib.util.module_from_spec(spec);spec.loader.exec_module(analyzer)
MATRIX = [1,0,0,0,0,1,0,0,0,0,1,0,0,1,0,1]
CART = [76.5,0,0,0,0,76.5,0,0,0,0,76.5,0,0,0,0,1]


def fixture():
    lines = ['[WOOD_BANK] RUN_STARTED'];life=[];body=[];grip=[];world=[];draws=[];tail=[]
    for index,name in enumerate(analyzer.CASES):
        sex,load,kind = name.split('-',2);start=100000+index*25000;item=index+1
        plan = [('pickup',False),('drop',False),('pickup',False),('drop',False)] if kind=='complete-chain' else \
               [('pickup',True),('pickup',True),('pickup',False),('drop',False)] if kind=='pickup-restart' else \
               [('pickup',False),('drop',True),('drop',True),('drop',False)]
        beginnings=[800+i*2050 for i in range(4)];ends=[v+2000 for v in beginnings]
        queues=[700]+[v+25 for v in ends[:-1]]
        phases=[.55 if i==(0 if kind=='pickup-restart' else 1) else .88 if cancelled else 1 for i,(_,cancelled) in enumerate(plan)]
        def row(elapsed,serial=None):
            owned=False
            for i,(action,cancelled) in enumerate(plan):
                if elapsed>=ends[i] and not cancelled: owned=action=='pickup'
            current=next((i for i in range(4) if beginnings[i]<=elapsed<ends[i]),None)
            action=plan[current][0] if current is not None else ''
            selected=serial if serial is not None else max([i+1 for i,q in enumerate(queues) if q<=elapsed] or [0])
            return dict(case=name,start=start,wall=start+elapsed,elapsed=elapsed,id=item,actionSerial=selected,
                        cartType='SaucedWheelbarrow.WheelbarrowWood',female=sex=='female',cargo=50 if load=='full' else 0,cargoCount=int(load=='full'),cargoIDs='stable' if load=='full' else '',condition=100,
                        worldCount=int(not owned),woodWorldCount=int(not owned),worldID=-1 if owned else item,inventoryCount=int(owned),
                        heldID=item if owned else -1,secondaryID=item if owned else -1,worldAlpha=1,
                        nativeActions=int(bool(action)),luaActions=int(bool(action)),actionType=analyzer.TYPES.get(action,''),progress=phases[current]*(elapsed-beginnings[current])/2000 if current is not None else 0,
                        active=bool(action),authored=bool(action),ik=bool(action),recovering=False,rendered=bool(action),ToolkitWoodCartAction=bool(action),IsPerformingAnAction=bool(action),PerformingAction='ToolkitWoodCart' if action else '')
        def event(name,elapsed,serial=None):
            receipt=dict(row(elapsed,serial),event=name)
            if name=='cancelRequested': receipt['progress']=phases[serial-1]
            lines.append('[WOOD_INTERACTION_EVENT] '+json.dumps(receipt))
        lines.append(f'[WOOD_BANK] CASE {name} attempt=0 wall={start}')
        schedule=[(0,'prepared',0)]
        for i,(_,cancelled) in enumerate(plan):
            schedule.append((queues[i],'actionQueued',i+1))
            if cancelled: schedule.append((ends[i]-25,'cancelRequested',i+1))
            schedule.append((ends[i]+25,'cancelCleared' if cancelled else 'actionCompleted',i+1))
            identity=index*4+i+1
            for event_name,elapsed in [('start',beginnings[i])]+([('stop',ends[i])] if cancelled else [('perform',ends[i]),('complete',ends[i])]):
                life.append(dict(event=event_name,wallTimeMillis=start+elapsed,nativeActionId=identity,metaType=analyzer.TYPES[plan[i][0]],phase='exit',playerNum=0,threw=None,finished=event_name in ('perform','complete')))
        schedule += [(ends[-1]+25,'dropped',4),(19000,'finalCleanup',4)]
        # Stable sorting keeps completion/clear before a queue on the same tick.
        schedule.sort(key=lambda r:r[0])
        for elapsed,event_name,serial in schedule: event(event_name,elapsed,serial)
        for elapsed in range(0,20001,25):
            sample=row(elapsed);lines.append('[WOOD_INTERACTION_SAMPLE] '+json.dumps(sample))
            seam=any(plan[i][1] and ends[i]<=elapsed<=beginnings[i+1]+100 for i in range(3))
            bones={name:MATRIX[:] for name in ('Bip01_Spine',)+analyzer.ARM_BONES}
            for side in 'LR':
                for part,x in [('UpperArm',-.3),('Forearm',0),('Hand',.3)]: bones['Bip01_'+side+'_'+part][12]=x
            body.append(dict(wallTimeMillis=start+elapsed,bones=bones,cart=CART[:]))
            grip.append(dict(wallTimeMillis=start+elapsed,result=True,threw=False))
            world.append(dict(wallTimeMillis=start+elapsed,itemId=item,renderStatus='Ready',alpha=1))
            draws.append(dict(wall=start+elapsed,source='held' if seam or sample['active'] or sample['inventoryCount'] else 'world',itemId=item,x=0,y=0,angle=0,phase=0,cart=CART[:]))
            clip_tracks=[]
            for i in range(4):
                if beginnings[i]<=elapsed<=ends[i]+200:
                    retired=elapsed>=ends[i]
                    clip_tracks.append(dict(trackId=index*4+i+1,name=analyzer.CLIP,reverse=plan[i][0]=='drop',clockBinding=None if retired else analyzer.CLOCK,
                                            time=(1-phases[i]*min(1,(elapsed-beginnings[i])/2000) if plan[i][0]=='drop' else phases[i]*min(1,(elapsed-beginnings[i])/2000)),duration=1,weight=.5 if retired else 1,field=1))
            tail.append(dict(wallTimeMillis=start+elapsed,bones=bones,tracks=clip_tracks,cartModelCount=int(seam or bool(sample['active']) or bool(sample['inventoryCount']))))
        lines.append(f'[WOOD_BANK] COMPLETE {name} wall={start} file=/owned/{name}.mp4 frames=600 seconds=20.0')
    lines.append('[WOOD_BANK] ALL_COMPLETE cases=12')
    return '\n'.join(lines),life,body,grip,world,draws,tail


def edit_log(values,change):
    lines=[]
    for line in values[0].splitlines():
        if line.startswith(('[WOOD_INTERACTION_SAMPLE] ','[WOOD_INTERACTION_EVENT] ')):
            prefix,raw=line.split('] ',1);record=json.loads(raw);change(record);line=prefix+'] '+json.dumps(record)
        lines.append(line)
    return ('\n'.join(lines),*values[1:])


class RepeatChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.values=fixture()

    def assert_rejected(self,values,reason):
        with self.assertRaisesRegex(AssertionError,reason): analyzer.analyze(*values)

    def test_valid_full_bank(self):
        result=analyzer.analyze(*self.values)
        self.assertTrue(all(result[k] for k in ('functionalPass','clockVerified','recoveryVerified','wheelCoverageVerified')))
        self.assertEqual(len(result['cases']),12)
        self.assertEqual(len(result['cases'][0]['transitions']),3)

    def test_metal_track_selector_requires_its_exact_cart_type_and_distinct_clip(self):
        frame=copy.deepcopy(next(frame for frame in self.values[6] if frame['tracks']))
        frame['tracks'][0]['name']='Toolkit_MetalCart_Pickup'
        selected=analyzer.tracks(frame,'SaucedWheelbarrow.WheelbarrowMetal')
        self.assertEqual(list(selected.values()),frame['tracks'])

    def test_track_selector_rejects_wrong_clip_even_beside_correct_track(self):
        for cart_type,wrong_clip in [('SaucedWheelbarrow.WheelbarrowMetal','Toolkit_WoodCart_Pickup'),
                                     ('SaucedWheelbarrow.WheelbarrowWood','Toolkit_MetalCart_Pickup')]:
            with self.subTest(cart_type=cart_type):
                frame=copy.deepcopy(next(frame for frame in self.values[6] if frame['tracks']))
                frame['tracks'][0]['name']=analyzer.CLIPS[cart_type]
                frame['tracks'].append(dict(frame['tracks'][0],name=wrong_clip,trackId=99999))
                with self.assertRaisesRegex(AssertionError,'Wrong cart clip'):
                    analyzer.tracks(frame,cart_type)

    def test_arbitrary_clock_bound_clip_cannot_impersonate_cart_clip(self):
        frame=copy.deepcopy(next(frame for frame in self.values[6] if frame['tracks']))
        frame['tracks'][0]['name']='Unrelated_Pickup'
        for cart_type in analyzer.CLIPS:
            with self.subTest(cart_type=cart_type), self.assertRaisesRegex(AssertionError,'Wrong cart clip'):
                analyzer.tracks(frame,cart_type)
        with self.assertRaisesRegex(AssertionError,'Unsupported captured'):
            analyzer.tracks(frame,'Unrelated_Pickup')

    def test_full_metal_repeat_cannot_claim_wooden_wheel_proof(self):
        values=edit_log(self.values,lambda row: row.update(cartType='SaucedWheelbarrow.WheelbarrowMetal'))
        self.assert_rejected(values,'wooden wheel calibration')

    def test_captured_cart_type_must_be_supported_and_stable(self):
        values=edit_log(self.values,lambda row: row.update(cartType='SaucedCarts.ShoppingCart'))
        self.assert_rejected(values,'Unsupported captured')
        def corrupt(row):
            if row['case']==analyzer.CASES[0] and row['elapsed']==1000:
                row['cartType']='SaucedWheelbarrow.WheelbarrowMetal'
        self.assert_rejected(edit_log(self.values,corrupt),'cart type changed')

    def test_stable_action_rejects_one_missing_authored_ik_frame(self):
        for field in ('active','authored','rendered','ik'):
            with self.subTest(field=field):
                def corrupt(row):
                    if row['case']==analyzer.CASES[0] and row['elapsed']==5050: row[field]=False
                self.assert_rejected(edit_log(self.values,corrupt),'Stable authored')

    def test_initial_draw_and_last_two_percent_are_outside_stable_gate(self):
        def corrupt(row):
            if row['case']==analyzer.CASES[0] and (row['elapsed'] in (800,900) or row['progress']>=.98):
                for field in ('authored','rendered','ik'): row[field]=False
        self.assertTrue(analyzer.analyze(*edit_log(self.values,corrupt))['functionalPass'])

    def test_stable_action_requires_enough_state_evidence(self):
        def corrupt(row):
            if row['case']==analyzer.CASES[0] and 900<row['elapsed']<2800: row['progress']=.99
        self.assert_rejected(edit_log(self.values,corrupt),'Missing stable')

    def test_native_zero_track_id_is_valid(self):
        values=list(copy.deepcopy(self.values))
        for frame in values[6]:
            for track in frame['tracks']: track['trackId']-=1
        self.assertTrue(analyzer.analyze(*values)['clockVerified'])

    def test_missing_scene_and_short_window(self):
        values=self.values
        self.assert_rejected((values[0].replace('[WOOD_BANK] COMPLETE male-empty-complete-chain','[WOOD_BANK] OMITTED male-empty-complete-chain'),*values[1:]),'scenes')
        def corrupt(row):
            if row['case']==analyzer.CASES[0] and row['elapsed']>19000: row['case']='not-selected'
        self.assert_rejected(edit_log(values,corrupt),'sample window')

    def test_delayed_native_restart(self):
        values=list(copy.deepcopy(self.values))
        for row in values[1]:
            if row['nativeActionId']==2 and row['event']=='start': row['wallTimeMillis']+=200
        self.assert_rejected(values,'restart delayed')

    def test_cargo_and_ownership_changes(self):
        for field,value in [('cargoIDs','changed'),('worldCount',2),('heldID',-2)]:
            with self.subTest(field=field):
                def corrupt(row):
                    if row['case']==analyzer.CASES[0] and row['elapsed']==1000: row[field]=value
                self.assert_rejected(edit_log(self.values,corrupt),'cargo|duplicated|ownership')

    def test_final_cleanup_receipt_does_not_hide_leak(self):
        def corrupt(row):
            if row['case']==analyzer.CASES[0] and row['elapsed']>=19500: row['recovering']=True
        self.assert_rejected(edit_log(self.values,corrupt),'cleanup')

    def test_final_native_track_leak_fails(self):
        values=list(copy.deepcopy(self.values))
        for frame in values[6]:
            if 119500<=frame['wallTimeMillis']<=120000:
                frame['tracks']=[dict(trackId=99,name=analyzer.CLIP,reverse=False,clockBinding=analyzer.CLOCK,time=.2,duration=1,weight=.1,field=1)]
        self.assert_rejected(values,'Final native')

    def test_missing_native_perform_and_duplicate_native_completion(self):
        for duplicate in (False,True):
            with self.subTest(duplicate=duplicate):
                values=list(copy.deepcopy(self.values));position=next(i for i,r in enumerate(values[1]) if r['event']=='perform')
                if duplicate: values[1].insert(position+1,dict(values[1][position]))
                else: values[1].pop(position)
                self.assert_rejected(values,'lifecycle')

    def test_track_reuse_binding_and_reset_are_rejected(self):
        for failure in ('reuse','binding','reset','no-overlap','no-progress'):
            with self.subTest(failure=failure):
                values=list(copy.deepcopy(self.values))
                for frame in values[6]:
                    elapsed=frame['wallTimeMillis']-100000
                    if not 0<=elapsed<=20000: continue
                    for track in frame['tracks']:
                        if failure=='reuse' and track['trackId']==2: track['trackId']=1
                        if failure=='binding' and track['trackId']==1 and elapsed>=2800: track['clockBinding']=analyzer.CLOCK
                        if failure=='reset' and track['trackId']==1 and elapsed>=2900: track['time']=0
                        if failure=='no-progress' and track['trackId']==2: track['time']=0
                    if failure=='no-overlap' and elapsed>=2800: frame['tracks']=[t for t in frame['tracks'] if t['trackId']!=1]
                self.assert_rejected(values,'track|clip|clock')

    def test_missing_body_wheel_and_nonfinite_pose_fail(self):
        for target in (2,5,6):
            with self.subTest(target=target):
                values=list(self.values);values[target]=[]
                self.assert_rejected(values,'poses|draws|window')
        values=list(copy.deepcopy(self.values));values[2][40]['cart'][0]=float('nan')
        self.assert_rejected(values,'Nonfinite')

    def test_one_frame_cancelled_retry_cart_loss_fails(self):
        values=list(copy.deepcopy(self.values))
        frame=next(f for f in values[6] if f['wallTimeMillis']==127825)
        frame['cartModelCount']=0
        self.assert_rejected(values,'Cancelled-retry cart presentation disappeared')

    def test_actual_world_draw_during_cancelled_retry_fails_even_with_model(self):
        values=list(copy.deepcopy(self.values))
        frame=next(f for f in values[5] if f['wall']==127825)
        frame['source']='world'
        self.assert_rejected(values,'Cancelled-retry exposed actual world')

    def test_cancelled_retry_requires_seam_coverage(self):
        values=list(self.values)
        values[6]=[f for f in values[6] if not 127800<=f['wallTimeMillis']<=127900]
        self.assert_rejected(values,'sampling gap|presentation window')

    def test_cancelled_retry_brackets_33ms_phase_after_old_window(self):
        values=list(copy.deepcopy(self.values));fresh=127850
        for target,key in ((6,'wallTimeMillis'),(5,'wall')):
            original=values[target]
            replacement=[]
            for offset in range(-130,200,33):
                stamp=fresh+offset
                frame=copy.deepcopy(min(original,key=lambda r:abs(r[key]-stamp)))
                frame[key]=stamp;replacement.append(frame)
            values[target]=sorted([f for f in original if not fresh-150<=f[key]<=fresh+200]+replacement,key=lambda r:r[key])
        within_old=[r['wallTimeMillis']-fresh for r in values[6] if fresh<=r['wallTimeMillis']<=fresh+100]
        self.assertEqual(within_old,[2,35,68])
        self.assertTrue(analyzer.analyze(*values)['functionalPass'])

    def test_cancelled_retry_requires_samples_before_and_after_boundaries(self):
        for target,key in ((6,'wallTimeMillis'),(5,'wall')):
            for lower,upper in ((127750,127800),(127950,128000)):
                with self.subTest(target=target,lower=lower):
                    values=list(self.values)
                    values[target]=[f for f in values[target] if not lower<=f[key]<=upper]
                    self.assert_rejected(values,'presentation window|actual held draws')

    def test_restart_cart_and_arm_jump_fail(self):
        for failure in ('cart','arm'):
            with self.subTest(failure=failure):
                values=list(copy.deepcopy(self.values))
                if failure=='cart': values[2][116]['cart'][12]+=.04
                else: values[6][116]['bones']['Bip01_L_Hand'][12]+=.01
                self.assert_rejected(values,'Cart jumped|arm segment')

    def test_cli_preserves_missing_evidence_reason(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);log=root/'capture.log';log.write_text('[WOOD_BANK] RUN_STARTED\n');output=root/'report.json'
            result=subprocess.run([sys.executable,str(path),'--profile',str(root),'--log',str(log),'--output',str(output)],capture_output=True,text=True)
            self.assertEqual(result.returncode,1)
            report=json.loads(output.read_text());self.assertFalse(report['functionalPass']);self.assertIn('action-lifecycle.jsonl',report['failures'][0])


if __name__=='__main__': unittest.main()
