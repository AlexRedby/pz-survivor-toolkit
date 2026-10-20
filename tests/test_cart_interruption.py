"""Cancellation analyzer must reject lifecycle, cargo and first-render failures."""
import importlib.util
import json
import math
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest

path=Path(__file__).resolve().parents[1]/'tests/native_queue/contributions/wooden_cart_motion/analyze-interruption.py'
spec=importlib.util.spec_from_file_location('cart_interruption',path)
analyzer=importlib.util.module_from_spec(spec);spec.loader.exec_module(analyzer)


def fixture(matrix=False, fast=False):
    lines=['[WOOD_BANK] RUN_STARTED'];life=[];body=[];grip=[];world=[];draws=[];tail=[]
    cases=analyzer.FAST_CASES if fast else analyzer.MATRIX_CASES if matrix else analyzer.CASES
    for index,name in enumerate(cases):
        parts=name.split('-');action,phase,route=parts[-3:];owned=action=='drop'
        female=(matrix or fast) and parts[0]=='female';full=not (matrix or fast) or parts[1]=='full'
        start=100000+index*25000;request=6000 if owned else 1500
        sustained=matrix and route=='walk' or fast and route!='reset'
        early_release=fast and route in ('runrelease','sprintrelease')
        pace_change=fast and route in ('runsprint','sprintwalk')
        release=request+(175 if early_release else 925);change=request+175
        retry=request+(2425 if fast else 1425 if sustained else 950);end=10500 if owned else 5000
        events={0:'prepared',700:'pickupQueued',request:'cancelRequested',request+25:'cancelled',retry:'retryQueued',
                **({4000:'pickedUp',5100:'dropQueued',10500:'dropped'} if owned else {5000:'pickedUp',6100:'dropQueued',9500:'dropped'})}
        if sustained: events[release]='movementReleased'
        if pace_change: events[change]='paceChanged'
        lines.append(f'[WOOD_BANK] CASE {name} attempt=0 wall={start}')
        for elapsed in range(0,20001,25):
            cancelled=request+25<=elapsed<retry
            held=4000<=elapsed<10500 if owned else 5000<=elapsed<9500
            current=('pickup' if 700<=elapsed<4000 else 'drop' if 5100<=elapsed<10500 else '') if owned else ('pickup' if 700<=elapsed<5000 else 'drop' if 6100<=elapsed<9500 else '')
            if cancelled or request<elapsed<=retry: current=''
            recovering=cancelled and elapsed<request+425 and not (fast and route=='reset')
            gait=(2 if route.startswith('sprint') else 1) if fast and sustained and request<=elapsed<=release else 0
            if pace_change and change<elapsed<=release: gait=2 if route=='runsprint' else 0
            recovery_progress=max(0,analyzer.THRESHOLDS[phase]*(1-(elapsed-request-25)/400))
            row=dict(case=name,start=start,wall=start+elapsed,elapsed=elapsed,id=index+1,
                stage='cancelled' if cancelled else 'other',heldID=index+1 if held else -1,secondaryID=index+1 if held else -1,
                worldID=-1 if held else index+1,worldCount=int(not held),woodWorldCount=int(not held),inventoryCount=int(held),
                actionType=analyzer.TYPES.get(current,''),progress=analyzer.THRESHOLDS[phase] if elapsed==request else .2,
                female=female,cargo=50 if full else 0,cargoIDs='stable' if full else '',cargoCount=int(full),
                x=max(0,min(elapsed-request,release-request))*.00004 if sustained else 0,y=0,z=7,
                driveCommand=int(sustained and request<=elapsed<=release),gaitCommand=gait,sprintSkill=10 if fast else 0,run=gait==1,sprint=gait==2,condition=100,worldAlpha=1,worldX=1,worldY=2,worldZ=7,worldRotation=135,worldObjectAlpha=1,
                nativeActions=int(bool(current)),luaActions=int(bool(current)),active=bool(current),recovering=recovering,presentationProgress=recovery_progress if recovering else .2,rendered=bool(current) or recovering,
                ToolkitWoodCartAction=bool(current),PerformingAction='ToolkitWoodCart' if current else '',IsPerformingAnAction=bool(current),
                ToolkitCartMotion=held and not current)
            lines.append('[WOOD_INTERACTION_SAMPLE] '+json.dumps(row))
            if elapsed in events:
                receipt=dict(row,event=events[elapsed])
                if events[elapsed]=='movementReleased': receipt.update(driveCommand=0,gaitCommand=0)
                if events[elapsed]=='paceChanged': receipt['gaitCommand']=2 if route=='runsprint' else 0
                lines.append('[WOOD_INTERACTION_EVENT] '+json.dumps(receipt))
            if request-75<=elapsed<retry:
                cart_matrix=[76.5,0,0,0,0,76.5,0,0,0,0,76.5,0,0,.097179376,0,1]
                bones={}
                for bone_name in ('Bip01_Spine','Bip01_L_Hand','Bip01_R_Hand'):
                    bone=[1,0,0,0,0,1,0,0,0,0,1,0,0,1,0,1];bones[bone_name]=bone
                for side in 'LR':
                    for part,x in [('UpperArm',-.3),('Forearm',0),('Hand',.3)]:
                        bones['Bip01_'+side+'_'+part]=[1,0,0,0,0,1,0,0,0,0,1,0,x,1,0,1]
                    for part,y,z in [('Thigh',1,0),('Calf',.5,.1),('Foot',0,0),('Toe0',0,.2)]:
                        bones['Bip01_'+side+'_'+part]=[1,0,0,0,0,1,0,0,0,0,1,0,0,y,z,1]
                frame=dict(wallTimeMillis=start+elapsed,female=female,cart=cart_matrix,bones=bones,cartModelCount=1)
                if elapsed==request+25: frame['afterStopActionId']=index*2+1
                body.append(frame);tail.append(frame)
                source='held' if elapsed<request+425 or owned else 'world'
                draws.append(dict(wall=start+elapsed,source=source,itemId=-1 if source=='held' else index+1,
                                  x=0.,y=0.,angle=0.,phase=0.,cart=cart_matrix))
            if cancelled:
                grip.append(dict(wallTimeMillis=start+elapsed,result=True,threw=False))
                world.append(dict(wallTimeMillis=start+elapsed,itemId=index+1,renderStatus='Ready',alpha=1))
        for event,elapsed,identity in [('start',1000 if not owned else 5200,index*2+1),('stop',request+1,index*2+1),
                                      ('start',retry+25,index*2+2),('perform',end,index*2+2),('complete',end,index*2+2)]:
            life.append(dict(wallTimeMillis=start+elapsed,event=event,metaType=analyzer.TYPES[action],nativeActionId=identity,
                             finished=event in ('perform','complete'),threw=False))
        lines.append(f'[WOOD_BANK] COMPLETE {name} wall={start} file=/owned/{name}.mp4 frames=600 seconds=20.0')
    lines.append('[WOOD_BANK] ALL_COMPLETE cases='+str(len(cases)))
    return '\n'.join(lines),life,body,grip,world,draws,tail


def edit_records(values, change):
    lines=[]
    for line in values[0].splitlines():
        if line.startswith(('[WOOD_INTERACTION_SAMPLE] ', '[WOOD_INTERACTION_EVENT] ')):
            prefix,raw=line.split('] ',1);row=json.loads(raw);change(row)
            line=prefix+'] '+json.dumps(row)
        lines.append(line)
    return ('\n'.join(lines),*values[1:])


def native_toe_off_frame():
    # Native41 SP male/full pickup-early-walk: the near-vertical toe tips across the horizontal foot plane.
    bones={
        'Bip01_L_Thigh': [-0.006506972, -0.98334116, -0.18166272, 0.0, -0.99938864, 0.012644663, -0.03264789, 0.0, 0.03440081, 0.18133865, -0.9828198, 0.0, 0.062075626, 0.5000758, 0.015133669, 1.0],
        'Bip01_L_Calf': [-0.03258551, -0.66319895, 0.747735, 0.0, -0.999395, 0.012424089, -0.032533467, 0.0, 0.012286233, -0.7483423, -0.66320133, 0.0, 0.060530245, 0.2665324, -0.028011288, 1.0],
        'Bip01_L_Foot': [-0.013892477, -0.6444393, 0.7645304, 0.0, -0.99977773, -0.0032417653, -0.0209001, 0.0, 0.01594727, -0.7646505, -0.64425, 0.0, 0.05379022, 0.12935565, 0.12665096, 1.0],
        'Bip01_L_Toe0': [0.016352251, -0.77442014, -0.63246286, 0.0, -0.9998184, -0.006385807, -0.018031042, 0.0, 0.009924535, 0.63264203, -0.7743822, 0.0, 0.053941734, 0.036415707, 0.13382024, 1.0],
    }
    for part,y,z in [('Thigh',1,0),('Calf',.5,.1),('Foot',0,0),('Toe0',0,.2)]:
        bones['Bip01_R_'+part]=[1,0,0,0,0,1,0,0,0,0,1,0,0,y,z,1]
    return dict(bones=bones)


class CancellationChecks(unittest.TestCase):
    def test_valid_fast_cancel_and_reset_bank(self):
        result=analyzer.analyze(*fixture(fast=True),fast=True)
        self.assertTrue(result['functionalPass'],result['failures'])
        self.assertEqual(len(result['cases']),14)
        self.assertEqual(sum(r['forcedPresentationReset'] for r in result['cases']),2)

    def test_fast_bank_requires_real_gait_and_release_during_recovery(self):
        values=fixture(fast=True)
        for failure in ('no-sprint','late-release','no-recovery','no-pace-change'):
            with self.subTest(failure=failure):
                def corrupt(row):
                    if failure=='no-sprint' and row['case']=='male-full-pickup-contact-sprint': row['sprint']=False
                    if failure=='late-release' and row['case']=='male-full-pickup-contact-runrelease' and row.get('event')=='movementReleased':
                        row['elapsed']+=200;row['wall']+=200
                    if failure=='no-recovery' and row['case']=='male-full-pickup-contact-runrelease' and row.get('event')=='movementReleased': row['recovering']=False
                    if failure=='no-pace-change' and row['case']=='female-empty-pickup-late-runsprint': row['gaitCommand']=1
                try: report=analyzer.analyze(*edit_records(values,corrupt),fast=True)
                except AssertionError: continue
                self.assertFalse(report['functionalPass'])

    def test_forced_reset_still_requires_wheel_continuity_and_no_recovery(self):
        values=fixture(fast=True)
        target='male-full-pickup-late-reset'
        start=100000+analyzer.FAST_CASES.index(target)*25000
        broken=list(values);broken[5]=json.loads(json.dumps(values[5]))
        for row in broken[5]:
            if start+1525<=row['wall']<start+1600: row['phase']=.5
        report=analyzer.analyze(*broken,fast=True)
        self.assertFalse(report['functionalPass'])
        self.assertTrue(any('wheel phase' in str(r) for r in report['failures']))
        def recover(row):
            if row['case']==target and row.get('stage')=='cancelled': row['recovering']=True
        with self.assertRaisesRegex(AssertionError,'Forced reset'):
            analyzer.analyze(*edit_records(values,recover),fast=True)

    def test_fast_wheel_evidence_must_cover_release_and_settled_tail(self):
        values=list(fixture(fast=True));values[5]=[
            r for r in values[5] if (r['wall']-100000)%25000 <= (6000 if analyzer.FAST_CASES[(r['wall']-100000)//25000].split('-')[2]=='drop' else 1500)+699]
        with self.assertRaisesRegex(AssertionError,'Wheel draw tail'):
            analyzer.analyze(*values,fast=True)

    def test_native_toe_off_keeps_forward_local_knee_hinge(self):
        frame=native_toe_off_frame()
        self.assertLess(analyzer.shared['knee_direction'](frame)[0],-.1)
        left,right=analyzer.moving_knee_angles(frame)
        self.assertAlmostEqual(left,1.028008,places=5)
        self.assertEqual(right,0)

    def test_moving_knee_angles_reject_missing_and_invalid_matrices(self):
        for failure in ('missing','short','nonfinite','singular'):
            with self.subTest(failure=failure):
                frame=native_toe_off_frame();name='Bip01_L_Calf'
                if failure=='missing': del frame['bones'][name]
                elif failure=='short': frame['bones'][name]=frame['bones'][name][:-1]
                elif failure=='nonfinite': frame['bones'][name][0]=float('nan')
                else: frame['bones'][name][:12]=[0]*12
                with self.assertRaises((AssertionError,KeyError,ValueError)):
                    analyzer.moving_knee_angles(frame)

    def test_matrix_walk_rejects_backward_local_knee_hinge(self):
        values=fixture(matrix=True);target='female-empty-pickup-early-walk'
        start=100000+analyzer.MATRIX_CASES.index(target)*25000
        for angle in (.2,-.2):
            with self.subTest(angle=angle):
                broken=list(values);broken[2]=json.loads(json.dumps(values[2]))
                for frame in broken[2]:
                    if not start+1501<=frame['wallTimeMillis']<=start+2101: continue
                    calf=frame['bones']['Bip01_L_Calf']
                    calf[0]=calf[10]=math.cos(angle)
                    calf[2]=-math.sin(angle);calf[8]=math.sin(angle)
                result=analyzer.analyze(*broken,matrix=True)
                self.assertEqual(result['functionalPass'],angle>0,result['failures'])
                if angle<0:
                    self.assertTrue(any('knee' in str(reason) for reason in result['failures']))

    def assert_rejected(self, values, matrix=False):
        try:
            result=analyzer.analyze(*values,matrix=matrix)
        except AssertionError:
            return
        self.assertFalse(result['functionalPass'])

    def test_valid_sustained_matrix(self):
        result=analyzer.analyze(*fixture(matrix=True),matrix=True)
        self.assertTrue(result['functionalPass'],result['failures'])
        self.assertEqual(len(result['cases']),48)

    def test_matrix_rejects_actual_sex_and_load_mismatch(self):
        values=fixture(matrix=True)
        for field,value in [('female',False),('cargo',1),('cargoCount',1)]:
            with self.subTest(field=field):
                def corrupt(row):
                    if row['case']=='female-empty-pickup-early-cancel': row[field]=value
                self.assert_rejected(edit_records(values,corrupt),matrix=True)
        for field in ('cargo','cargoCount'):
            with self.subTest(full_field=field):
                def corrupt(row):
                    if row['case']=='male-full-drop-late-cancel': row[field]=0
                self.assert_rejected(edit_records(values,corrupt),matrix=True)

    def test_matrix_requires_sustained_held_key_and_release_tail(self):
        values=fixture(matrix=True)
        target='female-empty-pickup-contact-walk';request=1500
        for failure in ('early-release','released-key','short-release-tail'):
            with self.subTest(failure=failure):
                def corrupt(row):
                    if row['case']!=target: return
                    if failure=='early-release' and row.get('event')=='movementReleased':
                        row['elapsed']=request+225;row['wall']=row['start']+row['elapsed']
                    elif failure=='released-key' and request+100<=row['elapsed']<request+925:
                        row['driveCommand']=0
                    elif failure=='short-release-tail':
                        row['driveCommand']=int(request<=row['elapsed']<request+1375)
                        row['x']=max(0,min(row['elapsed']-request,1375))*.00004
                        if row.get('event')=='movementReleased':
                            row['elapsed']=request+1375;row['wall']=row['start']+row['elapsed'];row['driveCommand']=0
                self.assert_rejected(edit_records(values,corrupt),matrix=True)

    def test_release_tick_uses_log_order_when_sample_and_event_share_time(self):
        values=fixture(matrix=True)
        result=analyzer.analyze(*values,matrix=True)
        self.assertTrue(result['functionalPass'],result['failures'])
        # An equally timed pressed-key sample after the event must still fail.
        lines=values[0].splitlines()
        for index,line in enumerate(lines):
            if line.startswith('[WOOD_INTERACTION_EVENT] ') and '"event": "movementReleased"' in line:
                lines[index-1],lines[index]=lines[index],lines[index-1]
                break
        self.assert_rejected(('\n'.join(lines),*values[1:]),matrix=True)

    def test_matrix_requires_movement_during_and_after_recovery(self):
        values=fixture(matrix=True);target='female-empty-pickup-contact-walk';request=1500
        for failure in ('none','only-during','only-after'):
            with self.subTest(failure=failure):
                def corrupt(row):
                    if row['case']!=target: return
                    elapsed=row['elapsed']-request
                    if failure=='none': row['x']=0
                    elif failure=='only-during': row['x']=max(0,min(elapsed,400))*.00004
                    else: row['x']=max(0,min(elapsed-650,275))*.00004
                self.assert_rejected(edit_records(values,corrupt),matrix=True)

    def test_pose_step_uses_exact_elapsed_time_and_still_rejects_native_endpoint_jump(self):
        # Real native Sprint moved a wrist .09130752 m over 31 ms; the old Run endpoint jumped .12 m in 17 ms.
        for distance,elapsed,accepted in ((.09130752,31,True),(.12,17,False)):
            with self.subTest(distance=distance,elapsed=elapsed):
                values=list(fixture());values[6]=json.loads(json.dumps(values[6]))
                frames=values[6];index=8
                frames[index]['wallTimeMillis']=frames[index-1]['wallTimeMillis']+elapsed
                first_case_end=125000
                for frame in frames[index:]:
                    if frame['wallTimeMillis']>=first_case_end: break
                    # Translate the complete arm so segment lengths stay valid and isolate the discontinuity gate.
                    for part in ('UpperArm','Forearm','Hand'):
                        frame['bones']['Bip01_L_'+part][14]+=distance
                report=analyzer.analyze(*values)
                self.assertEqual(report['functionalPass'],accepted,report['failures'])
                case=report['cases'][0]
                self.assertGreater(case['maxBoneSteps']['Bip01_L_Hand'],.07)
                self.assertEqual(case['maxBoneStepsAt60Hz']['Bip01_L_Hand']<=.07,accepted)

    def test_recovery_rejects_stretched_arm(self):
        for matrix in (False,True):
            with self.subTest(matrix=matrix):
                values=list(fixture(matrix=matrix));values[6]=json.loads(json.dumps(values[6]))
                # A 1cm extension stays below the hand-step threshold but changes the forearm length.
                values[6][5]['bones']['Bip01_L_Hand'][12]+=.01
                self.assert_rejected(values,matrix=matrix)

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
