"""Synthetic Host wall protocol regression tests; no game or native-mesh claim."""
import copy
import json
import math
from pathlib import Path
import runpy
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT/'tests/native_queue/contributions/wooden_cart_multiplayer'
COMMON = runpy.run_path(str(SOURCE/'analyze.py'))
WALL = runpy.run_path(str(SOURCE/'analyze-wall.py'))


class CartMPWallTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.selection=dict(suite='cart_motion_mp',kind='mp',mode='toolkit',cases=['owner_observer_motion'],
                            options=dict(mp_host=True,cart_wall_exit='left',cart_variant='wooden-wheelbarrow'))
        (self.root/'selection.json').write_text(json.dumps(self.selection))
        (self.root/'execution.json').write_text('{"status":"completed"}')
        self.logs={r:[] for r in COMMON['ROLES']};self.frames={r:[] for r in ('client1','client2')}
        self.epoch=100000
        front=getattr(self, 'FRONT', False)
        duration=WALL['FRONT_DURATION'] if front else WALL['DURATION']
        phases=WALL['FRONT_PHASES'] if front else WALL['PHASES']
        if front:self.selection['options']['cart_wall_exit']='front'
        self.pad=dict(minX=0,minY=0,z=7,size=63,margin=2,bankVersion=4,elevated=True,vegetationFree=True,
                      floorSprite='carpentry_02_57',wallSprite='walls_exterior_wooden_01_0',wallSide='left',
                      wallX=28,wallMinY=7,wallMaxY=55,ownedWalls=49,initialHeading=3*math.pi/4)
        if front:self.pad.update(wallSide='front',initialHeading=math.pi)
        self.spec=dict(id=42,variant='wooden-wheelbarrow',cartType='SaucedWheelbarrow.WheelbarrowWood',cargoType='Base.Log',
                       cargoCount=1,cargoID=43,cargoWeight=50,capacity=50)
        for role in COMMON['ROLES']:
            self.logs[role].append('[CART_MP] START epoch=100000')
            if role=='server':
                self.add(role,'[CART_MP] CART_PAD ',self.pad)
                self.add(role,'[CART_MP] CART_SPEC ',self.spec)
                for actor in ('client1','client2'):self.add(role,'[CART_MP_WALL] ARMED ',dict(actor=actor,wall=99900,floors=3969,walls=49,bankVersion=4))
                self.add(role,'[CART_MP_WALL] CLEANUP ',dict(wall=self.epoch+duration+100,walls=49))
            else:
                (self.root/role).mkdir()
                self.add(role,'[CART_MP] SETUP ',self.pad)
                self.add(role,'[CART_MP] PAD_READY ',dict(self.pad,wall=99900,floors=3969,walls=49))
                self.add(role,'[CART_MP_WALL] CLEANUP_READY ',dict(wall=self.epoch+duration+200,walls=0))
                for name,t in phases:self.logs[role].append(f'[CART_MP] PHASE {name} wall={self.epoch+t} elapsed={t}')
                for e in (dict(event='setup',cases=['owner_observer_motion'],expected=1),dict(event='case',id='owner_observer_motion',status='captured'),
                          dict(event='complete',expected=1,performed=1,failed=0,skipped=0)):
                    self.add(role,'[QUEUE_CHECK] ',dict(e,actor=role,suite='cart_motion_mp',kind='mp'))
            for t in range(0,duration+1,100):
                stage=max((p for p in phases if p[1]<=t),key=lambda p:p[1])[0]
                heading=self.heading(t)
                x=30.8 if t<1000 else 30.8-2.2*min(1,(t-1000)/2000) if t<9500 else 28.6+(t-9500)*.0005 if t<15500 else 31.6 if t<16000 else 31.6+(min(t,26000)-16000)*.0007
                y=31.5 if t<1000 else 31.5+(t-1000)*.001 if t<9500 else 40-(min(t,15500)-9500)*.0006
                stopped=t<1000 or 15500<=t<16000 or t>=26000
                back=9500<=t<15500
                gait='Bob_WalkBwdNoAim1Hand' if back else 'Bob_Walk'
                bracing=False
                if front:
                    heading=math.pi;y=31.5
                    x=(29.8 if t<1000 else 29.8-1.2*min(1,(t-1000)/3000) if t<7500
                       else 28.6+min(2500,t-7500)*.0005 if t<10800
                       else 29.85-1.25*min(1,(t-10800)/2500))
                    bracing=4000<=t<6500 or 13300<=t<15500
                    back=7500<=t<10000
                    stopped=t<1000 or 4000<=t<7500 or 10000<=t<10800 or t>=13300
                    gait='Toolkit_WoodCartBrace' if bracing else 'Bob_Idle' if stopped else 'Bob_WalkBwdNoAim1Hand' if back else 'Bob_Walk'
                row=dict(wall=self.epoch+t,id=1,user='client1',local_=role=='client1',enabled=True,run=False,sprint=False,motion=True,pivot=True,
                         x=x,y=y,z=7,heading=heading,stepX=0,stepY=0 if stopped else -1 if back else 1,pace=0 if stopped else 1,bank=0,
                         primary=42,secondary=42,item=self.spec['cartType'],tracks=f'{gait}=1@1;',female=False,hasPath=False,characterActions=0,performing=False,
                         inventoryCount=0 if role=='client2' else 1,inventoryScope='remote-hand-snapshot' if role=='client2' else 'owner-inventory',worldID=-1,
                         cargoCount=1,cargoID=43,cargoWeight=50,pose=f'1,42,{t//100+1},0,0,1,1,1,0,0,0,0,0',
                         trackProgress=[dict(name=gait,time=(t%900)/1000,duration=1,weight=1)])
                if front:row.update(brace=bracing,pose=f'1,42,{t//100+1},{9 if bracing else 1},0,0,0,0,0,0,0,0,0')
                row['local']=row.pop('local_')
                self.add(role,'[CART_MP_STATE] ',row)
                if role=='client1':
                    drive=0 if stopped else 4 if back else 1
                    if 12000<=t<13500:drive=6
                    if 16000<=t<17500 or 21000<=t<22500:drive=5
                    if front:drive=0 if stage in ('idle','release','reverse-stop','settled') else 4 if stage=='reverse' else 1
                    input_row=dict(wall=self.epoch+t,elapsed=t,stage=stage,drive=drive,gait=0,acceptedHeading=heading,
                        id=42,primary=42,secondary=42,inventoryCount=1,worldID=-1,cargoID=43,cargoWeight=50,queue=0,actions=0,path=False,
                        front=1.26,blocked=bracing if front else 1000<=t<9500,recovering=False,clear=True)
                    if front:input_row.update(brace=float(bracing),nativeBlocked=True,wantsMove=drive!=0)
                    self.add(role,'[CART_MP_WALL] INPUT ',input_row)
                if role!='server':
                    frame=dict(wallTimeMillis=self.epoch+t,id=1,primary=42,secondary=42,local_=role=='client1',enabled=True,female=False,
                               cart=[76.5,0,0,0,0,76.5,0,0,0,0,76.5,0,0,0,0,1],
                               bones={f'Bip01_{s}_Hand':[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1] for s in 'LR'},model='WheelbarrowWood',
                               slotX=x,slotY=y,slotZ=7,slotAngle=heading+math.pi/2)
                    if front:
                        for side in 'LR':
                            for part in ('Foot','Toe0'):frame['bones'][f'Bip01_{side}_{part}']=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
                    frame['local']=frame.pop('local_');self.frames[role].append(frame)
            for t in range(0,duration+1,1000):self.add(role,'[CART_MP_TRAFFIC] ',dict(wall=self.epoch+t,packets=t//100,serializedBytes=t))

    def heading(self,t):
        if t<1000:return 3*math.pi/4
        if t<12000:return math.pi/2
        if t<13500:return math.pi/2+(t-12000)/1500*math.pi/4
        if t<16000:return 3*math.pi/4
        if t<17500:return 3*math.pi/4-(t-16000)/1500*math.pi/2
        if t<21000:return math.pi/4
        if t<22500:return math.pi/4-(t-21000)/1500*math.pi/4
        return 0

    def add(self,role,marker,row):self.logs[role].append((marker,copy.deepcopy(row)))
    def rows(self,role,marker):return [r for entry in self.logs[role] if isinstance(entry,tuple) for m,r in [entry] if m==marker]
    def analyze(self):
        (self.root/'selection.json').write_text(json.dumps(self.selection))
        for role,entries in self.logs.items():
            (self.root/(role+'-launch.log')).write_text('\n'.join(e if isinstance(e,str) else e[0]+json.dumps(e[1]) for e in entries))
        for role,rows in self.frames.items():(self.root/role/'body-clearance.jsonl').write_text('\n'.join(json.dumps(r) for r in rows))
        # Mesh-resource validation has independent native-mesh tests. Here replace only that dependency,
        # retaining all timeline, geometry-plane, ownership, drive, gait and traffic gates.
        fake=SimpleNamespace(slot_matches=lambda f,rows,times: min(math.dist((f['slotX'],f['slotY']),(r['x'],r['y'])) for r in rows)<=1,mesh=lambda _: (None,'fixture-sha'),world_bounds=lambda f,_:dict(minX=f['slotX']-.5,maxX=f['slotX']+.5,minY=f['slotY']-.5,maxY=f['slotY']+.5))
        spec=SimpleNamespace(loader=SimpleNamespace(exec_module=lambda _:None))
        original=WALL['importlib'].util.spec_from_file_location
        def load(name,path):return spec if name=='cart_mp_wall_footprint' else original(name,path)
        with patch.object(WALL['importlib'].util,'spec_from_file_location',side_effect=load),patch.object(WALL['importlib'].util,'module_from_spec',return_value=fake):
            return COMMON['analyze'](self.root)

    def test_complete_bounded_evidence_keeps_visual_limit(self):
        report=self.analyze()
        self.assertTrue(report['evidenceComplete'])
        self.assertEqual(report['actualSex'],'male')
        self.assertEqual(len(report['manualTurns']),3)
        self.assertIn('unsupported',report['scope'])
        self.assertIn('not authoritative',report['observerFootprint']['scope'])
        self.assertEqual(report['traffic']['senderIntervalMs'],100)

    def test_two_sample_reverse_stop_accepts_sampler_jitter_and_held_pivot(self):
        entries=self.logs['client1']
        self.logs['client1']=[e for e in entries if not (isinstance(e,tuple) and e[0]=='[CART_MP_STATE] ' and e[1]['wall']==self.epoch+15900)]
        for row in self.rows('client1','[CART_MP_STATE] '):
            if row['wall']==self.epoch+15700:row['wall']=self.epoch+15775
            elif row['wall']==self.epoch+15800:row['wall']=self.epoch+15891
        self.assertTrue(self.analyze()['evidenceComplete'])

    def test_reverse_stop_and_final_settle_reject_actual_yaw_or_step_motion(self):
        for t,key,value in ((15800,'heading',self.heading(15800)+.03),(15800,'stepX',.02),(15800,'stepY',.02),
                            (28600,'heading',.03),(28600,'stepX',.02),(28600,'stepY',.02)):
            with self.subTest(t=t,key=key):
                row=next(r for r in self.rows('client1','[CART_MP_STATE] ') if r['wall']==self.epoch+t)
                saved=row[key];row[key]=value
                with self.assertRaisesRegex(ValueError,'did not stop|did not settle'):self.analyze()
                row[key]=saved

    def test_final_settle_accepts_200ms_server_cadence_but_rejects_600ms_gap(self):
        def remove(predicate):
            self.logs['server']=[e for e in self.logs['server'] if not (isinstance(e,tuple) and e[0]=='[CART_MP_STATE] ' and predicate(e[1]['wall']-self.epoch))]
        remove(lambda t:28000<=t<=29000 and t%200!=0)
        self.assertTrue(self.analyze()['evidenceComplete'])
        remove(lambda t:28000<t<28600)
        with self.assertRaisesRegex(ValueError,'gap exceeds 500ms'):self.analyze()

    def test_traffic_coalesces_only_identical_consecutive_snapshots(self):
        entries=self.logs['client2']
        at=next(i for i,e in enumerate(entries) if isinstance(e,tuple) and e[0]=='[CART_MP_TRAFFIC] ' and e[1]['wall']==self.epoch+20000)
        entries.insert(at+1,copy.deepcopy(entries[at]))
        self.assertEqual(self.analyze()['traffic']['roles']['client2']['identicalSnapshotsCoalesced'],1)
        entries[at+1][1]['packets']+=1
        with self.assertRaisesRegex(ValueError,'reset/regression'):self.analyze()
        entries[at+1][1]['packets']-=1
        entries[at+1][1]['wall']-=1
        with self.assertRaisesRegex(ValueError,'reset/regression'):self.analyze()

    def test_mirrored_right_wall_exit_uses_the_same_strict_contract(self):
        self.selection['options']['cart_wall_exit']='right'
        for role,entries in self.logs.items():
            for entry in entries:
                if not isinstance(entry,tuple):continue
                marker,row=entry
                if marker in ('[CART_MP] CART_PAD ','[CART_MP] SETUP ','[CART_MP] PAD_READY '):
                    row['wallSide']='right';row['initialHeading']*=-1
                if marker=='[CART_MP_STATE] ':row['heading']*=-1;row['y']=63-row['y']
                if marker=='[CART_MP_WALL] INPUT ':
                    row['acceptedHeading']*=-1;row['drive']={6:7,5:8}.get(row['drive'],row['drive'])
        for frames in self.frames.values():
            for frame in frames:frame['slotY']=63-frame['slotY'];frame['slotAngle']=math.pi-frame['slotAngle']
        self.assertEqual(self.analyze()['wallSide'],'right')

    def test_rejects_unfrozen_host_or_mixed_banks(self):
        for key,value in (('cart_wall_exit','auto'),('mp_host',False),('cart_fast_motion',True),('cart_actions',True),('cart_variant','shopping-cart')):
            with self.subTest(key=key):
                saved=copy.deepcopy(self.selection);self.selection['options'][key]=value
                with self.assertRaises(ValueError):self.analyze()
                self.selection=saved

    def test_rejects_transient_identity_cargo_or_path_change(self):
        for role,key,value in (('server','cargoID',44),('client1','inventoryCount',0),('client2','secondary',99),('server','hasPath',True),('client1','female',True)):
            with self.subTest(role=role,key=key):
                row=self.rows(role,'[CART_MP_STATE] ')[33];saved=row[key];row[key]=value
                with self.assertRaises(ValueError):self.analyze()
                row[key]=saved

    def test_rejects_missing_wall_cleanup_or_native_geometry(self):
        for role,marker,key,value in (('server','[CART_MP] CART_PAD ','ownedWalls',48),('client2','[CART_MP] PAD_READY ','walls',48),
                                     ('client1','[CART_MP_WALL] CLEANUP_READY ','walls',1),('server','[CART_MP] CART_SPEC ','cargoType','Base.Plank'),
                                     ('server','[CART_MP] CART_SPEC ','capacity',51)):
            with self.subTest(marker=marker,key=key):
                row=self.rows(role,marker)[0];saved=row[key];row[key]=value
                with self.assertRaises(ValueError):self.analyze()
                row[key]=saved

    def test_rejects_automatic_reverse_steering_repress_and_yaw_drift(self):
        for t,key,value in ((3000,'drive',4),(14000,'drive',6),(14300,'acceptedHeading',2.31),(13200,'acceptedHeading',1.4),(18000,'queue',1)):
            with self.subTest(t=t,key=key):
                row=self.rows('client1','[CART_MP_WALL] INPUT ')[t//100];saved=row[key];row[key]=value
                with self.assertRaises(ValueError):self.analyze()
                row[key]=saved

    def test_rejects_native_gait_freeze_and_traffic_counter_reset(self):
        for r in self.rows('client1','[CART_MP_STATE] '):
            if 10500<=r['wall']-self.epoch<=11800:r['trackProgress'][0]['time']=0
        with self.assertRaisesRegex(ValueError,'animation time'):self.analyze()
        self.setUp()
        self.rows('client1','[CART_MP_TRAFFIC] ')[20]['packets']=0
        with self.assertRaisesRegex(ValueError,'regression'):self.analyze()

    def test_rejects_owner_mesh_but_reports_remote_drift(self):
        self.frames['client2'][80]['slotX']=28.0
        self.assertLess(self.analyze()['observerFootprint']['minClearance'],0)
        self.frames['client1'][80]['slotX']=28.0
        with self.assertRaisesRegex(ValueError,'enters native W wall'):self.analyze()

    def test_rejects_missing_samples_sender_overrate_and_mesh_error(self):
        rows=self.rows('client1','[CART_MP_WALL] INPUT ')
        row=rows[100];row['wall']+=1000
        with self.assertRaisesRegex(ValueError,'unordered'):self.analyze()
        row['wall']-=1000
        for r in self.rows('client1','[CART_MP_TRAFFIC] '):r['packets']*=2
        with self.assertRaisesRegex(ValueError,'sender budget'):self.analyze()
        for r in self.rows('client1','[CART_MP_TRAFFIC] '):r['packets']//=2
        (self.root/'client1/wood-wheel-mesh-error.json').write_text('{}')
        with self.assertRaisesRegex(ValueError,'mesh probe failed'):self.analyze()



class CartMPFrontBraceTests(unittest.TestCase):
    FRONT=True
    setUp=CartMPWallTests.setUp
    add=CartMPWallTests.add
    rows=CartMPWallTests.rows
    analyze=CartMPWallTests.analyze
    heading=CartMPWallTests.heading

    def test_front_brace_release_reverse_restart_and_packet_budget(self):
        report=self.analyze()
        self.assertTrue(report['evidenceComplete'] and report['brace']['verified'])
        self.assertEqual(report['wallSide'],'front')
        self.assertEqual(len(report['brace']['contact']),4)
        self.assertEqual(report['brace']['payloadFields'],13)
        self.assertEqual(report['traffic']['senderIntervalMs'],100)
        self.assertEqual(report['manualTurns'],[])
        self.assertIn('separate reported defect',report['scope'])

    def test_owner_and_observer_require_actual_brace_and_native_track(self):
        for role,key,value in (('client1','brace',False),('client2','brace',False),('client2','brace','true'),
                               ('client1','trackProgress',[]),('client2','trackProgress',[])):
            with self.subTest(role=role,key=key):
                row=next(r for r in self.rows(role,'[CART_MP_STATE] ') if r['wall']==105500)
                saved=row[key];row[key]=value
                with self.assertRaisesRegex(ValueError,'[Bb]race|track'):self.analyze()
                row[key]=saved

    def test_payload_remains_v1_13_fields_with_bit8_at_all_roles(self):
        for role in COMMON['ROLES']:
            row=next(r for r in self.rows(role,'[CART_MP_STATE] ') if r['wall']==105500)
            saved=row['pose']
            for payload in (saved.replace(',9,',',1,'),saved+',0',saved.replace('1,42,','2,42,'),saved.replace(',9,',',8,')):
                with self.subTest(role=role,payload=payload):
                    row['pose']=payload
                    with self.assertRaisesRegex(ValueError,'pose|flags|brace'):self.analyze()
            row['pose']=saved

    def test_release_and_manual_reverse_clear_flags_and_brace_tracks(self):
        for t in (7000,8500,17500):
            for role in ('client1','client2'):
                row=next(r for r in self.rows(role,'[CART_MP_STATE] ') if r['wall']==self.epoch+t)
                saved=copy.deepcopy(row)
                row['brace']=True
                with self.assertRaisesRegex(ValueError,'latched'):self.analyze()
                row.clear();row.update(saved)
                row['trackProgress']=[dict(name='Toolkit_WoodCartBrace',time=.1,duration=1,weight=1)]
                with self.assertRaisesRegex(ValueError,'remains'):self.analyze()
                row.clear();row.update(saved)

    def test_server_stale_brace_and_reverse_before_manual_input_are_rejected(self):
        rows=self.rows('server','[CART_MP_STATE] ')
        payload=next(r['pose'] for r in rows if r['wall']==106400)
        for row in rows:
            if 106500<=row['wall']<=107300:row['pose']=payload
        with self.assertRaisesRegex(ValueError,'flag remains'):self.analyze()
        for row in rows:
            t=row['wall']-self.epoch
            if 6500<=t<=7300:row['pose']=f'1,42,{t//100+1},1,0,0,0,0,0,0,0,0,0'
        row=next(r for r in self.rows('client1','[CART_MP_STATE] ') if r['wall']==103000)
        row['stepY']=-.1
        with self.assertRaisesRegex(ValueError,'Automatic reverse'):self.analyze()

    def test_native_wall_and_held_input_are_required_for_contact(self):
        row=next(r for r in self.rows('client1','[CART_MP_WALL] INPUT ') if r['elapsed']==5500)
        for key,value in (('nativeBlocked',False),('wantsMove',False),('brace',.8),('drive',4)):
            with self.subTest(key=key):
                saved=row[key];row[key]=value
                with self.assertRaises(ValueError):self.analyze()
                row[key]=saved

    def test_zero_root_budget_does_not_require_displacement_blocked_flag(self):
        for row in self.rows('client1','[CART_MP_WALL] INPUT '):
            if 5000<=row['elapsed']<=6300 or 14500<=row['elapsed']<=15300:
                row.update(blocked=False,clear=True)
        # The server relays the payload; actual animation variables/tracks exist on clients.
        for row in self.rows('server','[CART_MP_STATE] '):
            row.pop('brace');row.pop('trackProgress')
        self.assertTrue(self.analyze()['brace']['verified'])
        # A live brace flag/amount still cannot replace rendered near-wall contact geometry.
        for row in self.rows('client1','[CART_MP_STATE] '):
            if 105000<=row['wall']<=106300:row['x']+=1
        for frame in self.frames['client1']:
            if 105000<=frame['wallTimeMillis']<=106300:frame['slotX']+=1
        with self.assertRaisesRegex(ValueError,'never reaches wall contact'):self.analyze()

    def test_rendered_feet_and_root_must_stay_planted_for_both_roles(self):
        for role in ('client1','client2'):
            frame=next(f for f in self.frames[role] if f['wallTimeMillis']==105500)
            bone=frame['bones']['Bip01_L_Foot'];bone[13]=.03
            with self.assertRaisesRegex(ValueError,'feet'):self.analyze()
            bone[13]=0;bone[12]=.02
            with self.assertRaisesRegex(ValueError,'feet'):self.analyze()
            bone[12]=0
            row=next(r for r in self.rows(role,'[CART_MP_STATE] ') if r['wall']==105500)
            row['x']+=.02
            with self.assertRaisesRegex(ValueError,'root'):self.analyze()
            row['x']-=.02

    def test_missing_contact_coverage_and_automatic_reverse_are_rejected(self):
        row=next(r for r in self.rows('client1','[CART_MP_WALL] INPUT ') if r['elapsed']==5500)
        saved=row['drive'];row['drive']=4
        with self.assertRaisesRegex(ValueError,'physical drive'):self.analyze()
        row['drive']=saved
        self.frames['client2']=[f for f in self.frames['client2'] if not 105000<=f['wallTimeMillis']<=106300]
        with self.assertRaisesRegex(ValueError,'gap exceeds|insufficient'):self.analyze()

    def test_existing_remote_approach_penetration_is_still_reported(self):
        self.frames['client2'][20]['slotX']=28.0
        report=self.analyze()
        self.assertLess(report['observerFootprint']['minClearance'],0)
        self.assertIn('separate reported defect',report['scope'])

if __name__=='__main__':unittest.main()
