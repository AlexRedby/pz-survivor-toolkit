"""Synthetic evidence rejection and executable Host input/admission contracts."""
import copy
import json
import math
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'tests/native_queue/contributions/wooden_cart_multiplayer'
BASE=runpy.run_path(str(SOURCE/'analyze.py'))
VISUAL=runpy.run_path(str(SOURCE/'analyze-visual-extended.py'))
SELF=runpy.run_path(str(SOURCE/'self_check.py'))
EPOCH=100000
CONTROL=152000
END=CONTROL+VISUAL['CONTROL_DURATION']


def fixture(root):
    SELF['fixture'](root,fast=True,variant='shopping-cart')
    selection=json.loads((root/'selection.json').read_text())
    selection['options'].update(mp_host=True,cart_visual_extended=True,cart_actions=True)
    (root/'selection.json').write_text(json.dumps(selection))
    spec=dict(id=42,cargoID=99,cargoWeight=70,worldPose=dict(x=1.5,y=2.5,z=7,rotation=45))
    def emit(lines,kind,row):lines.append('[CART_MP_VISUAL] '+kind+' '+json.dumps(dict(version=1,**row)))
    matrix=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    for role in BASE['ROLES']:
        path=root/(role+'-launch.log');original=path.read_text().splitlines();lines=[]
        state=json.loads(next(line.split('[CART_MP_STATE] ',1)[1] for line in original if '[CART_MP_STATE] ' in line))
        for line in original:
            if '[CART_MP_STATE] ' in line:
                if json.loads(line.split('[CART_MP_STATE] ',1)[1])['wall']>=EPOCH+15000:continue
            if '[CART_MP] PHASE ' in line:
                if int(line.rsplit('elapsed=',1)[1])>=15000:continue
            for marker in ('[CART_MP] CART_PAD ','[CART_MP] SETUP ','[CART_MP] PAD_READY '):
                if marker in line:
                    prefix,raw=line.split(marker,1);row=json.loads(raw)
                    row.update(minX=-31,minY=-31,bankVersion=6,size=63)
                    if marker.endswith('PAD_READY '):row['floors']=3969
                    line=prefix+marker+json.dumps(row)
            if '[QUEUE_CHECK] ' in line:
                prefix,raw=line.split('[QUEUE_CHECK] ',1);row=json.loads(raw)
                if row['event']=='case':row.update(cartActions=True,cartVisualExtended=True)
                line=prefix+'[QUEUE_CHECK] '+json.dumps(row)
            lines.append(line)
        poses=[]
        if role!='server':
            poses=[json.loads(line) for line in (root/role/'body-clearance.jsonl').read_text().splitlines()
                   if json.loads(line)['wallTimeMillis']<EPOCH+15000]
            pose=copy.deepcopy(poses[0])
        for t in range(15000,31001,100):
            phase,start=max((p for p in VISUAL['MOTION_PHASES'] if p[1]<=t),key=lambda p:p[1])
            running=18000<=t<21000;sprinting=23000<=t<26000
            yaw=-.16*min(1,(t-15000)/300)-.35*max(0,min(1,(t-19500)/350))+.35*max(0,min(1,(t-24500)/350))
            distance=.001*(max(0,min(t,21000)-18000)+max(0,min(t,26000)-23000))
            row=dict(state,wall=EPOCH+t,heading=yaw,x=1+distance,run=running,sprint=sprinting)
            lines.append('[CART_MP_STATE] '+json.dumps(row))
            if role!='server':poses.append(dict(pose,wallTimeMillis=EPOCH+t))
            if role=='client1' and t<31000:
                drive,gait=(1,1) if running else (1,2) if sprinting else (0,0)
                if phase=='short-correction':drive=5 if t<15300 else 1
                if phase=='run-turn':drive=5 if t<19900 else 1
                if phase=='sprint-turn':drive=8 if t<24900 else 1
                emit(lines,'INPUT',dict(actor=role,phase=phase,wall=EPOCH+t,epoch=EPOCH,elapsed=t,drive=drive,gait=gait,heading=yaw,id=42))
        if role!='server':
            for name,t in VISUAL['MOTION_PHASES'][6:]:lines.append(f'[CART_MP] PHASE {name} wall={EPOCH+t} elapsed={t}')
            (root/role/'body-clearance.jsonl').write_text('\n'.join(map(json.dumps,poses))+'\n')
        path.write_text('\n'.join(lines)+'\n')
    SELF['action_fixture'](root,EPOCH,31000,matrix,'ShoppingCartFullModel',VISUAL['ACTION_PHASES'],VISUAL['ACTION_GROUND'],True)
    route=VISUAL['control_route'](dict(minX=-31,minY=-31,size=63,z=7))
    for role in BASE['ROLES']:
        lines=[]
        if role=='server':
            for actor in ('client1','client2'):emit(lines,'READY',dict(actor=actor,id=42,wall=148020))
            emit(lines,'CONTROL_SETUP',dict(id=42,spec=spec,route=route,wall=148030))
            for actor in ('client1','client2'):
                emit(lines,'CONTROL_POSITIONED',dict(actor=actor,id=42,wall=148200,heading=route['heading'],**route['owner' if actor=='client1' else 'observer']))
            emit(lines,'CONTROL_START',dict(epoch=CONTROL,wall=149000,spec=spec,route=route,duration=VISUAL['CONTROL_DURATION']))
        else:
            emit(lines,'CONTROL_POSITIONED',dict(actor=role,id=42,wall=148050,heading=route['heading'],**route['owner' if role=='client1' else 'observer']))
            emit(lines,'CONTROL_START',dict(actor=role,epoch=CONTROL,wall=149010,spec=spec,route=route,duration=VISUAL['CONTROL_DURATION']))
            emit(lines,'VIDEO_START',dict(actor=role,epoch=EPOCH,wall=98000,file='/owned/'+role+'.mp4'))
            for name,t,drive,gait in VISUAL['CONTROL_PHASES']:
                emit(lines,'CONTROL_PHASE',dict(actor=role,phase=name,epoch=CONTROL,wall=CONTROL+t,elapsed=t,drive=drive,gait=gait))
            emit(lines,'CONTROL_COMPLETE',dict(actor=role,id=42,epoch=CONTROL,wall=END,elapsed=VISUAL['CONTROL_DURATION'],inputReleased=True))
            emit(lines,'VIDEO_STOP',dict(actor=role,epoch=CONTROL,wall=END+10))
            emit(lines,'DONE',dict(actor=role,id=42,epoch=CONTROL,wall=END+100,inputReleased=True,videoCompleted=True))
            emit(lines,'CLEANUP_READY',dict(actor=role,id=42,cargoID=99,epoch=CONTROL,wall=END+300,floors=0,worldCount=0))
            lines.append('[CART_MP] VIDEO_FINAL '+json.dumps(dict(file='/owned/'+role+'.mp4',seconds=(END+10-98000)/1000,frames=1980,captured=1980)))
        if role=='server':
            for actor in ('client1','client2'):emit(lines,'DONE',dict(actor=actor,id=42,epoch=CONTROL,wall=END+200))
            emit(lines,'CLEANUP',dict(id=42,cargoID=99,epoch=CONTROL,wall=END+250,floors=3969))
        distance=0
        for t in range(0,VISUAL['CONTROL_DURATION'],100):
            # Delayed observer native states are explicitly measured by the analyzer.
            native=max(0,t-(200 if role=='client2' else 0))
            name,start,drive,gait=max((p for p in VISUAL['CONTROL_PHASES'] if p[1]<=native),key=lambda p:p[1])
            if drive:distance+=.04
            row=dict(state,wall=CONTROL+t,x=4.5+distance,y=4.5,heading=0,primary=-1,secondary=-1,item='none',enabled=False,
                     visualEnabled=False,motion=False,run=gait==1,sprint=gait==2,nativeMoving=bool(drive),characterActions=0,
                     hasPath=False,trackProgress=[dict(name='Bob_Run' if gait else 'Bob_Walk',time=(t%1000)/1000,duration=1,weight=1)])
            lines.append('[CART_MP_STATE] '+json.dumps(row))
            emit(lines,'CONTROL_ENDPOINT',dict(actor=role,epoch=CONTROL,wall=CONTROL+t,elapsed=t,**spec,
                 primaryID=-1,secondaryID=-1,worldCount=1,cargoPreserved=True,nativeActions=0,hasPath=False,
                 pathScope='remote-network' if role=='client2' else 'authoritative-approach',
                 luaActions=None if role=='server' else 0,queueScope='native-server' if role=='server' else 'client-lua-and-native'))
        with (root/(role+'-launch.log')).open('a') as output:output.write('\n'.join(lines)+'\n')


class HostVisualExtended(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name);fixture(self.root)

    def analyze(self):return BASE['analyze'](self.root)

    def mutate(self,role,marker,fn):
        path=self.root/(role+'-launch.log');lines=[]
        for line in path.read_text().splitlines():
            if marker in line:
                prefix,raw=line.split(marker,1);row=json.loads(raw);fn(row);line=prefix+marker+json.dumps(row)
            lines.append(line)
        path.write_text('\n'.join(lines)+'\n')

    def test_complete_capture_reports_only_evidence_and_native_control_delay(self):
        report=self.analyze()['visualExtended']
        self.assertTrue(report['evidenceComplete']);self.assertEqual(report['visualVerdict'],'unreviewed')
        self.assertEqual(report['nativeTransitionsMs']['control-walk']['observerMinusOwnerMs'],200)
        self.assertEqual(len(self.analyze()['actions']['phases']['client2']),7)

    def test_frozen_selection_shape_omits_lua_runtime_disposable_guard(self):
        selection=json.loads((self.root/'selection.json').read_text())
        self.assertNotIn('disposable',selection)
        self.assertTrue(VISUAL['validate_options'](selection,BASE['require']))
        for key in ('cart_lease_menu','cart_timeline','cart_observer_association'):
            bad=copy.deepcopy(selection);bad['options'][key]=True
            with self.subTest(option=key),self.assertRaises(ValueError):
                VISUAL['validate_options'](bad,BASE['require'])
        bad=copy.deepcopy(selection);bad['kind']='sp'
        with self.assertRaises(ValueError):VISUAL['validate_options'](bad,BASE['require'])

    def test_safe_ground_return_at_control_completion_is_outside_capture_pad_guard(self):
        path=self.root/'server-launch.log'
        original=path.read_text()
        row=json.loads(next(line.split('[CART_MP_STATE] ',1)[1] for line in reversed(original.splitlines()) if '[CART_MP_STATE] ' in line))
        row.update(wall=CONTROL+VISUAL['CONTROL_DURATION'],x=.5,y=.5,z=0)
        path.write_text(original+'[CART_MP_STATE] '+json.dumps(row)+'\n')
        self.assertTrue(self.analyze()['visualExtended']['evidenceComplete'])
        row['wall']-=1
        path.write_text(original+'[CART_MP_STATE] '+json.dumps(row)+'\n')
        with self.assertRaisesRegex(ValueError,'pad interior'):self.analyze()

    def test_opt_in_admission_rejects_wrong_role_variant_or_incomplete_dependencies(self):
        path=self.root/'selection.json';original=path.read_text()
        for key,value in [('mp_host',False),('cart_variant','wooden-wheelbarrow'),('cart_actions',False),('cart_fast_motion',False),('cart_wall_exit','left'),('cart_visual_extended',1)]:
            with self.subTest(key=key):
                selection=json.loads(original);selection['options'][key]=value;path.write_text(json.dumps(selection))
                with self.assertRaises(ValueError):self.analyze()

    def test_independent_native_route_has_both_setup_receipts_and_guarded_envelope(self):
        route=VISUAL['control_route'](dict(minX=-31,minY=-31,size=63,z=7))
        self.assertEqual(route['owner'],dict(x=4.5,y=4.5,z=7))
        self.assertEqual(route['observer'],dict(x=6.5,y=7.5,z=7))
        self.assertAlmostEqual(route['bounds']['minX'],-30.952186130069787)
        self.assertAlmostEqual(route['bounds']['maxX'],8.9095454429505)
        self.assertAlmostEqual(route['bounds']['minY'],-29.86173157302029)
        self.assertGreater(route['owner']['x']+route['bounds']['minX'],-29)
        self.assertGreater(route['owner']['y']+route['bounds']['minY'],-29)
        self.assertLess(route['owner']['x']+route['bounds']['maxX'],30)
        # The fixed observer remains inside the pad and within the guarded native camera reach.
        owner,observer,bounds=route['owner'],route['observer'],route['bounds']
        self.assertEqual((observer['x']-owner['x'],observer['y']-owner['y']),(2,3))
        self.assertTrue(-29<observer['x']<30 and -29<observer['y']<30)
        self.assertLess(max(math.hypot(owner['x']+x-observer['x'],owner['y']+y-observer['y'])
                            for x in (bounds['minX']-.2,bounds['maxX']+.2) for y in (bounds['minY']-.2,.2)),48)
        self.assertEqual(VISUAL['CONTROL_PHASES'][3],('control-run',4000,3,1))
        for role in ('server','client1','client2'):
            path=self.root/(role+'-launch.log');original=path.read_text()
            path.write_text('\n'.join(line for line in original.splitlines() if '[CART_MP_VISUAL] CONTROL_POSITIONED ' not in line))
            with self.subTest(role=role),self.assertRaises(ValueError):self.analyze()
            path.write_text(original)

    def test_native_control_setup_rejects_wrong_position_heading_or_late_ack(self):
        for change in [dict(x=8),dict(heading=0),dict(wall=CONTROL)]:
            path=self.root/'client1-launch.log';original=path.read_text()
            self.mutate('client1','[CART_MP_VISUAL] CONTROL_POSITIONED ',lambda row:row.update(change))
            with self.subTest(change=change),self.assertRaisesRegex(ValueError,'setup receipt'):self.analyze()
            path.write_text(original)
        self.mutate('server','[CART_MP_VISUAL] CONTROL_START ',lambda row:row['route']['owner'].update(x=8))
        with self.assertRaisesRegex(ValueError,'setup/route authority'):self.analyze()

    def test_visual_provenance_keeps_exact_correlated_timestamps(self):
        for role,kind in [('server','CONTROL_START'),('client1','CONTROL_PHASE'),('client2','CONTROL_ENDPOINT')]:
            path=self.root/(role+'-launch.log');original=path.read_text()
            self.mutate(role,'[CART_MP_VISUAL] '+kind+' ',lambda row:row.update(wall=row['wall']+1))
            with self.subTest(role=role,kind=kind),self.assertRaises(ValueError):self.analyze()
            path.write_text(original)

    @unittest.skipUnless(shutil.which('luajit'),'LuaJIT required')
    def test_visual_emitter_uses_caller_observed_tick_across_clock_boundary(self):
        script='local M=dofile('+json.dumps(str(SOURCE/'visual-extended.lua'))+')\n'+r'''
local clock=1000;local reads=0;local captured
getTimestampMs=function() reads=reads+1;clock=clock+1;return clock end
package.preload.CartMPJSON=function() return {encode=function(row) captured=row;return '{}' end} end
print=function() end
local observed=getTimestampMs();local epoch=observed+M.controlLead
M.emit('CONTROL_START',{epoch=epoch},observed)
assert(reads==1 and captured.wall==observed and captured.epoch-captured.wall==3000,'Emitter re-read epoch clock')
observed=getTimestampMs();getTimestampMs() -- Serialization crosses another real millisecond.
M.emit('CONTROL_PHASE',{epoch=1000,elapsed=observed-1000},observed)
assert(reads==3 and captured.wall-captured.epoch==captured.elapsed,'Emitter re-read elapsed clock')
M.emit('READY',{})
assert(reads==4 and captured.wall==clock,'Command event did not take its own timestamp')
'''
        subprocess.run([shutil.which('luajit'),'-e',script],check=True,capture_output=True,text=True)

    def test_native_flag_latency_and_physical_braking_are_independent(self):
        for role in BASE['ROLES']:
            def brake(row):
                t=row['wall']-CONTROL
                if t<0:return
                row['x']+=2*max(0,min(1,(t-5600)/1200))+3.8*max(0,min(1,(t-11800)/1800))
                if 5600<=t<8600:row['nativeMoving']=t-5600<dict(client1=0,server=900,client2=1700)[role]
                if 11800<=t<15800:row['nativeMoving']=t-11800<dict(client1=0,server=1100,client2=2600)[role]
            self.mutate(role,'[CART_MP_STATE] ',brake)
        report=self.analyze()['visualExtended']
        self.assertEqual(report['nativeTransitionsMs']['control-run-stop']['client1'],0)
        self.assertEqual(report['nativeTransitionsMs']['control-run-stop']['client2'],1700)
        self.assertGreater(report['physicalSettlementMs']['control-run-stop']['client1'],900)
        self.assertGreater(report['physicalSettlementMs']['control-stop']['client1'],1600)
        self.assertEqual(report['physicalSettlementMs']['control-stop']['client2'],2600)

    def test_native_control_requires_centred_initial_state_and_route_bounds(self):
        for change in [dict(x=8),dict(y=28)]:
            path=self.root/'client1-launch.log';original=path.read_text()
            self.mutate('client1','[CART_MP_STATE] ',lambda row:row.update(change) if CONTROL<=row['wall']<CONTROL+1200 else None)
            with self.subTest(change=change),self.assertRaises(ValueError):self.analyze()
            path.write_text(original)

    def test_missing_no_cart_receipts_rejected(self):
        for role,marker in [('server','CONTROL_START'),('client2','CONTROL_COMPLETE'),('client1','CLEANUP_READY'),('server','CLEANUP')]:
            with self.subTest(role=role,marker=marker):
                path=self.root/(role+'-launch.log');original=path.read_text()
                path.write_text('\n'.join(line for line in original.splitlines() if '[CART_MP_VISUAL] '+marker+' ' not in line))
                with self.assertRaises(ValueError):self.analyze()
                path.write_text(original)

    def test_control_requires_actual_release_authority_and_observer_endpoint(self):
        self.mutate('client2','[CART_MP_ACTION] OBSERVER_RECEIPT ',lambda row:row.update(cargoID=100) if row['index']==7 else None)
        with self.assertRaisesRegex(ValueError,'observer native endpoint'):self.analyze()

    def test_no_cart_control_rejects_cart_identity_or_synthetic_held_state(self):
        self.mutate('client2','[CART_MP_VISUAL] CONTROL_ENDPOINT ',lambda row:row.update(id=43))
        with self.assertRaisesRegex(ValueError,'ground/cargo endpoint'):self.analyze()

    def test_no_cart_control_rejects_pending_lua_action(self):
        self.mutate('client1','[CART_MP_VISUAL] CONTROL_ENDPOINT ',lambda row:row.update(luaActions=1))
        with self.assertRaisesRegex(ValueError,'ground/cargo endpoint'):self.analyze()

    def test_remote_network_path_is_preserved_without_weakening_authority(self):
        # IsoGameCharacter.hasPath only checks path2 != null; native remote movement
        # uses that same path2 independently of owner Lua/native action queues.
        for role,kind in [('client2','OBSERVER_RECEIPT'),('server','SERVER_OBSERVATION')]:
            self.mutate(role,'[CART_MP_ACTION] '+kind+' ',lambda row:row.update(hasPath=True))
        self.mutate('client2','[CART_MP_STATE] ',lambda row:row.update(hasPath=True) if row['wall']>=CONTROL else None)
        self.mutate('client2','[CART_MP_VISUAL] CONTROL_ENDPOINT ',lambda row:row.update(hasPath=True))
        self.assertTrue(self.analyze()['visualExtended']['evidenceComplete'])

    def test_owner_and_server_stale_paths_still_fail(self):
        for role,marker in [('client1','[CART_MP_ACTION] RECEIPT '),('server','[CART_MP_ACTION] SERVER_RECEIPT '),
                            ('client1','[CART_MP_VISUAL] CONTROL_ENDPOINT '),('server','[CART_MP_VISUAL] CONTROL_ENDPOINT '),
                            ('client1','[CART_MP_STATE] '),('server','[CART_MP_STATE] ')]:
            with self.subTest(role=role,marker=marker):
                path=self.root/(role+'-launch.log');original=path.read_text()
                self.mutate(role,marker,lambda row:row.update(hasPath=True))
                with self.assertRaises(ValueError):self.analyze()
                path.write_text(original)

    def test_remote_endpoint_requires_idle_position_and_exact_identity(self):
        for change in [dict(nativeMoving=True),dict(position=dict(x=2,y=2,z=0)),dict(position=dict(x=1.15,y=2.15,z=0)),dict(position=dict(x=1,y=2,z=1)),
                       dict(position=None),dict(hasPath=None),dict(pathScope='authoritative-approach'),dict(id=43)]:
            with self.subTest(change=change):
                path=self.root/'client2-launch.log';original=path.read_text()
                self.mutate('client2','[CART_MP_ACTION] OBSERVER_RECEIPT ',lambda row:row.update(change))
                with self.assertRaises(ValueError):self.analyze()
                path.write_text(original)

    def test_remote_control_still_requires_settled_native_motion(self):
        for change in [dict(nativeMoving=True),dict(x=100)]:
            with self.subTest(change=change):
                path=self.root/'client2-launch.log';original=path.read_text()
                self.mutate('client2','[CART_MP_STATE] ',lambda row:row.update(change) if CONTROL+15100<=row['wall']<CONTROL+15600 else None)
                with self.assertRaises(ValueError):self.analyze()
                path.write_text(original)

    def test_frozen_native_no_cart_animation_rejected(self):
        self.mutate('client2','[CART_MP_STATE] ',lambda row:row.update(trackProgress=[dict(name='Bob_Walk',time=0,duration=1,weight=1)]) if row['wall']>=CONTROL else None)
        with self.assertRaisesRegex(ValueError,'clocks frozen'):self.analyze()

    def test_video_must_include_entire_control_tail(self):
        self.mutate('client2','[CART_MP] VIDEO_FINAL ',lambda row:row.update(seconds=17))
        with self.assertRaisesRegex(ValueError,'video duration'):self.analyze()

    def test_short_correction_rejects_broad_pivot(self):
        self.mutate('client1','[CART_MP_VISUAL] INPUT ',lambda row:row.update(drive=5) if row['phase']=='short-correction' else None)
        with self.assertRaisesRegex(ValueError,'steering|correction'):self.analyze()

    def test_short_fast_turn_onset_is_not_lost_to_later_steady_window(self):
        def early_turn(row):
            t=row['wall']-EPOCH
            if 19500<=t<21000:row['heading']=-.16 if t<19600 else -.51
            if 24500<=t<26000:row['heading']=-.51 if t<24600 else -.16
        self.mutate('client1','[CART_MP_STATE] ',early_turn)
        report=self.analyze()['visualExtended']['fastMotion']
        self.assertAlmostEqual(report['run-turn']['yaw'],-.35)
        self.assertAlmostEqual(report['sprint-turn']['yaw'],.35)

    def test_fast_forward_requires_real_native_gait(self):
        self.mutate('client1','[CART_MP_STATE] ',lambda row:row.update(run=False) if 118000<=row['wall']<121000 else None)
        with self.assertRaisesRegex(ValueError,'fast mode'):self.analyze()

    @unittest.skipUnless(shutil.which('luajit'),'LuaJIT required')
    def test_real_role_scripts_publish_observer_identity_and_complete_control_protocol(self):
        script='local source='+json.dumps(str(SOURCE))+'\n'+r"""
local now=100000
local function noOp() end
local function list(values) return {size=function() return #values end,get=function(_,i) return values[i+1] end,isEmpty=function() return #values==0 end} end
local held=true;local clients={};local server;local setUps={};local messages={};local receipts={};local clean=false
local origin={x=4.5,y=.5,z=7,minX=-31,minY=-31,size=63,margin=2,bankVersion=6,elevated=true,
 vegetationFree=true,floorSprite='carpentry_02_57',returnX=.5,returnY=.5,returnZ=0}
local cargo={getID=function() return 99 end,getFullType=function() return 'Base.Log' end,
 getActualWeight=function() return 70 end,setActualWeight=noOp,setCustomWeight=noOp}
local cargoInventory={getItems=function() return list({cargo}) end,AddItem=function() return cargo end,
 getEffectiveCapacity=function() return 70 end}
local cart,world,square
local ownerInventory={AddItem=function() return cart end,getItems=function() return list(held and {cart} or {}) end,
 getItemById=function(_,id) assert(id==42);return held and cart or nil end}
cart={getID=function() return 42 end,getFullType=function() return 'SaucedCarts.ShoppingCart' end,
 getInventory=function() return cargoInventory end,getContainer=function() return held and ownerInventory or nil end,
 getWorldItem=function() return not held and world or nil end,getWorldZRotation=function() return 45 end}
world={getItem=function() return cart end,getSquare=function() return square end,
 getWorldPosX=function() return 4.5 end,getWorldPosY=function() return .5 end,getWorldPosZ=function() return 7 end}
local floor={getSpriteName=function() return origin.floorSprite end}
square={getFloor=function() return floor end,TreatAsSolidFloor=function() return true end,isFree=function() return true end,isVehicleIntersecting=function() return false end,
 getWorldObjects=function() return list(not held and {world} or {}) end}
local players={}
for _,role in ipairs({'client1','client2'}) do
 local p={user=role,x=.5,y=.5,z=0}
 p.getUsername=function(self) return self.user end;p.getX=function(self) return self.x end
 p.getY=function(self) return self.y end;p.getZ=function(self) return self.z end
 p.getCurrentSquare=function() return square end;p.getPerkLevel=function() return 10 end
 p.getPrimaryHandItem=function() return role=='client1' and held and cart or nil end
 p.getSecondaryHandItem=p.getPrimaryHandItem
 p.getInventory=function() return role=='client1' and ownerInventory or {getItems=function() return list({}) end} end
 p.getCharacterActions=function() return list({}) end;p.hasPath=function() return false end
 p.getStats=function() return {reset=noOp} end
 p.teleportTo=function(self,x,y,z) self.x=x;self.y=y;self.z=z end
 p.setX=function(self,x) self.x=x end;p.setY=function(self,y) self.y=y end;p.setZ=function(self,z) self.z=z end
 for _,name in ipairs({'setNextX','setNextY','setLastX','setLastY','setLastZ','ensureOnTile','setCurrentSquareFromPosition',
  'setMovingSquareNow','setPrimaryHandItem','setSecondaryHandItem','updateHandEquips','setGodMod','setGhostMode','setAutoDrink'}) do p[name]=noOp end
 players[role]=p
end
local config={kind='mp',disposable=true,mode='toolkit',cases={'owner_observer_motion'},ffmpeg='/owned/ffmpeg',
 videoRoot={client1='/owned/client1',client2='/owned/client2'},options={mp_host=true,cart_visual_extended=true,
 cart_variant='shopping-cart',cart_fast_motion=true,cart_actions=true}}
local phases={'drop-complete','pickup-complete','drop-cancel','drop-repeat','pickup-cancel','pickup-repeat','control-release'}
local grounds={true,false,false,true,true,false,true};local actionIndex=0;local pending=false;local actionsDone=false
local function command(name,p,args) server.handlers.OnClientCommand('CartMP',name,p,args or {}) end
local function boot(role)
 local env=setmetatable({},{__index=_G});env._G=env;env.handlers={};env.role=role;env.drive=0;env.gait=0;env.video='idle'
 env.Events=setmetatable({},{__index=function(_,name) return {Add=function(fn) env.handlers[name]=fn end} end})
 env.isClient=function() return role~='server' end;env.isServer=function() return role=='server' end;env.ISTimedActionQueue={queues={}}
 env.getTimestampMs=function() return now end;env.getPlayer=function() return players[role] end
 env.getOnlinePlayers=function() return list({players.client1,players.client2}) end
 env.getCell=function() return {getGridSquare=function() return square end} end
 env.getCore=function() return {setOptionPauseOnFocusloss=noOp,setOptionAutoDrink=noOp,
  getZoom=function() return role=='client2' and 1 or .25 end,TakeFullScreenshot=noOp} end
 env.getFileReader=function() return {readLine=function() return role end,close=noOp} end
 env.PZAPI={ModOptions={getOptions=function() return {getOption=function() return {setValue=noOp} end} end}}
 env.SaucedCarts={applyCartPose=noOp,updateCartVisual=noOp};env.Perks={Sprinting=1};env.CharacterStat={ENDURANCE=1}
 env.cartLabDrive=function(drive) env.drive=drive end;env.cartLabGait=function(gait) env.gait=gait end
 env.cartLabPoseHeading=function(heading)
  assert(not server or not server.controlEpoch or now<server.controlEpoch,'Measured control rewrote native heading')
  env.heading=heading
 end;env.cartLabHeading=function() return env.heading end;env.cartLabSteeringHeading=function() return 0 end
 env.cartMPControlCamera=function(owner) assert(role=='client2' and owner==players.client1);env.controlCamera=true;env.controlCameraStarted=true end
 env.cartMPControlCameraStop=function() env.controlCamera=false end
 env.cartMPZoom=function(observer) return observer and 1 or .25 end;env.cartMPCamera=noOp;env.cartMPHideUI=noOp
 env.cartMPState=function() return '{}' end;env.cartMPTraffic=function() return '{}' end
 env.cartMPSeedSprinting=function() return 10 end;env.sendAddItemToContainer=noOp
 env.toolkitVideoStart=function() env.video='recording';return true end
 env.toolkitVideoStop=function() assert(env.video=='recording');env.video='completed';return true end
 env.toolkitVideoStatus=function() return {state=env.video,file='/owned/'..role..'.mp4',frames=2000,captured=2000,seconds=70} end
 env.print=function(line) assert(not line:find('[QUEUE_TEST] FAIL',1,true),line) end
 local visual=setfenv(assert(loadfile(source..'/visual-extended.lua')),env)()
 visual.emit=function(kind,row,observedWall)
  row.wall=observedWall or now
  if row.elapsed then assert(row.wall-row.epoch==row.elapsed,'Mixed tick timestamps in real role receipt') end
  if kind=='CONTROL_START' and role=='server' then assert(row.epoch-row.wall==3000,'Mixed server epoch clock') end
  receipts[#receipts+1]={role=role,kind=kind,row=row}
  if kind=='CONTROL_START' and role=='server' then env.controlEpoch=row.epoch end
 end
 visual.ground=function(p,spec) assert(not held and spec.id==42 and spec.cargoID==99);return {id=42,cargoID=99} end
 visual.cleanup=function(spec,area) assert(role=='server' and spec.id==42 and area==origin);clean=true;return 3969 end
 visual.cleanupReady=function() return clean end
 local actions={sample=noOp,done=function() return actionsDone end}
 actions.command=function(name,args)
  if name=='ActionAudit' and role=='client2' then
   command('ActionObservation',players.client2,{actor='client2',index=args.index,phase=args.phase,id=42,cargoID=99,cargoWeight=70,
    cargoPreserved=true,inventoryScope='remote-hand-snapshot',inventoryCount=nil,itemSource=held and 'hands' or 'world',
    handSameItem=held,worldAttached=not held,worldCount=held and 0 or 1,primaryID=held and 42 or -1,secondaryID=held and 42 or -1,
    luaActions=0,nativeActions=0,hasPath=false,pathScope='remote-network',nativeMoving=false,position=args.expectedPosition})
  elseif name=='ActionAck' then pending=false
  elseif name=='ActionsDone' then actionsDone=true end
 end
 actions.tick=function()
  if pending or actionsDone then return end
  actionIndex=actionIndex+1;pending=true
  local args={index=actionIndex,phase=assert(phases[actionIndex]),id=42}
  command('ActionBegin',players.client1,args);held=not grounds[actionIndex];command('ActionCheck',players.client1,args)
 end
 env.require=function(name)
  if name=='QueueTestSelection' then return config end
  if name=='CartMPVisualExtended' then return visual end
  if name=='CartMPJSON' then return {encode=function() return '{}' end,emit=function(row) assert(row.event~='error',row.reason) end} end
  if name=='CartMPActions' then return actions end
  if name=='CartMPPlacement' then return function() return origin end end
  assert(name=='SaucedCarts/Core' or name=='SaucedCarts/CartVisuals',name);return {}
 end
 env.sendClientCommand=function(module,name,args) assert(module=='CartMP');command(name,players[role],args) end
 env.sendServerCommand=function(p,module,name,args)
  assert(module=='CartMP');messages[#messages+1]={role=p.user,name=name,args=args}
  if name=='Setup' then setUps[p.user]=args end
  if name=='Start' then env.motionEpoch=args.epoch end
  clients[p.user].handlers.OnServerCommand(module,name,args)
 end
 return env
end
server=boot('server');clients.client1=boot('client1');clients.client2=boot('client2')
setfenv(assert(loadfile(source..'/server.lua')),server)()
for _,role in ipairs({'client1','client2'}) do
 setfenv(assert(loadfile(source..'/client.lua')),clients[role])();clients[role].handlers.OnGameStart()
end
command('Ready',players.client2);assert(not setUps.client2,'Observer armed before exact cart existed')
command('Ready',players.client1);command('Ready',players.client2)
assert(setUps.client1.cartId==42 and setUps.client2.cartId==42,'Observer setup lost authoritative exact cart')
local function tick()
 clients.client1.handlers.OnTick();clients.client2.handlers.OnTick();server.handlers.OnTick()
end
tick();assert(server.motionEpoch)
now=server.motionEpoch-1000;tick();now=server.motionEpoch;tick()
for i=0,24 do now=server.motionEpoch+31000+i*100;tick() end
assert(actionsDone and actionIndex==7 and server.controlEpoch,'Native endpoint authority did not start control')
local starts=0
for _,event in ipairs(receipts) do if event.kind=='CONTROL_START' and event.role~='server' then
 starts=starts+1;assert(event.row.spec.id==42)
end end
assert(starts==2,'Both real client handlers must accept the generated control start')
for _,t in ipairs({0,1200,2800,4000,5600,8600,10200,11800,15800,15900}) do
 now=server.controlEpoch+t;tick()
 if t==1200 or t==4000 or t==8600 then
  assert(clients.client1.drive==(t==4000 and 3 or 1) and clients.client1.gait==(t==4000 and 1 or t==8600 and 2 or 0),'Native control input was cleared between ticks')
 end
end
assert(clients.client2.controlCameraStarted and not clients.client2.controlCamera,'Static observer control camera lifecycle differed')
assert(clean and clients.client1.video=='completed' and clients.client2.video=='completed')
assert(clients.client1.drive==0 and clients.client1.gait==0 and clients.client2.drive==0 and clients.client2.gait==0)
local positioned=0
for _,event in ipairs(receipts) do if event.kind=='CONTROL_POSITIONED' then
 positioned=positioned+1;assert(event.row.wall==nil or event.row.wall<server.controlEpoch,'Late control setup receipt')
end end
assert(positioned==4,'Both clients and independent server setup receipts required')
local complete=0
for _,event in ipairs(receipts) do if event.kind=='CLEANUP_READY' then complete=complete+1;assert(event.row.id==42) end end
assert(complete==2,'Both real client roles must finish cleanup with authoritative cart identity')
"""
        result=subprocess.run([shutil.which('luajit'),'-e',script],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)

    @unittest.skipUnless(shutil.which('luajit'),'LuaJIT required')
    def test_exact_native_ground_identity_and_cleanup_preflight_before_any_removal(self):
        script='local M=dofile('+json.dumps(str(SOURCE/'visual-extended.lua'))+')\n'+r'''
local function list(values) return {size=function() return #values end,get=function(_,i) return values[i+1] end} end
isServer=function() return true end;isClient=function() return false end;cartMPPadHost=function() return true end
local spec={id=42,cargoID=99,cargoWeight=70,worldPose={x=.5,y=.5,z=7,rotation=45}}
local floor={getSpriteName=function() return 'owned-floor' end}
local world,square,item
local cargoID=99
local cargo={getID=function() return cargoID end,getFullType=function() return 'Base.Log' end,getActualWeight=function() return 70 end}
item={getID=function() return 42 end,getFullType=function() return 'SaucedCarts.ShoppingCart' end,
 getWorldItem=function() return world end,getWorldZRotation=function() return 45 end,
 getInventory=function() return {getItems=function() return list({cargo}) end} end}
world={getItem=function() return item end,getSquare=function() return square end,
 getWorldPosX=function() return .5 end,getWorldPosY=function() return .5 end,getWorldPosZ=function() return 7 end}
local objects={floor,world};local worlds={world};local currentFloor=floor;local moving={};local removed=0
square={getFloor=function() return currentFloor end,getObjects=function() return list(objects) end,
 getWorldObjects=function() return list(worlds) end,getSpecialObjects=function() return list({}) end,
 getStaticMovingObjects=function() return list({}) end,getMovingObjects=function() return list(moving) end,
 transmitRemoveItemFromSquare=function(_,object)
  removed=removed+1
  if object==world then worlds={};objects={floor} else assert(object==floor);currentFloor=nil;objects={} end
  return 0
 end}
getCell=function() return {getGridSquare=function(_,x,y,z) assert(z==7);return x==0 and y==0 and square or nil end} end
local p={getPrimaryHandItem=function() return nil end,getSecondaryHandItem=function() return nil end,
 getInventory=function() return {getItems=function() return list({}) end} end,
 getCharacterActions=function() return {isEmpty=function() return true end} end,hasPath=function() return false end,
 isLocalPlayer=function() return true end}
assert(M.ground(p,spec).cargoPreserved)
isClient=function() return true end
ISTimedActionQueue={queues={[p]={queue={{}}}}}
assert(not pcall(M.ground,p,spec),'Lua queue admitted no-cart control')
ISTimedActionQueue.queues[p].queue={};assert(M.ground(p,spec).luaActions==0)
-- Native remote network movement can retain path2 after stopping. Never invent false hasPath.
p.hasPath=function() return true end
assert(not pcall(M.ground,p,spec),'Local native approach path was admitted')
p.isLocalPlayer=function() return false end
local remote=M.ground(p,spec);assert(remote.hasPath==true and remote.pathScope=='remote-network')
ISTimedActionQueue.queues[p].queue={{}};assert(not pcall(M.ground,p,spec),'Remote Lua action was admitted')
ISTimedActionQueue.queues[p].queue={};p.hasPath=function() return false end
isClient=function() return false end
cargoID=100;assert(not pcall(M.ground,p,spec));cargoID=99
worlds={world,world};assert(not pcall(M.ground,p,spec));worlds={world}
M.ownFloor(square,floor)
local area={size=1,minX=0,minY=0,z=7,floorSprite='owned-floor'}
currentFloor={};assert(not pcall(M.cleanup,spec,area) and removed==0);currentFloor=floor
objects={floor,world,{}};assert(not pcall(M.cleanup,spec,area) and removed==0);objects={floor,world}
moving={{}};assert(not pcall(M.cleanup,spec,area) and removed==0);moving={}
cargoID=100;assert(not pcall(M.cleanup,spec,area) and removed==0);cargoID=99
assert(M.cleanup(spec,area)==1 and removed==2 and M.cleanupReady(area))
'''
        subprocess.run([shutil.which('luajit'),'-e',script],check=True,capture_output=True,text=True)

    @unittest.skipUnless(shutil.which('luajit'),'LuaJIT required')
    def test_lua_native_input_schedule_is_latched_and_admission_is_fail_closed(self):
        script='local M=dofile('+json.dumps(str(SOURCE/'visual-extended.lua'))+')\n'+r'''
local c={kind='mp',disposable=true,options={mp_host=true,cart_visual_extended=true,cart_variant='shopping-cart',cart_fast_motion=true,cart_actions=true}}
M.validate(c)
c.disposable=false;assert(not pcall(M.validate,c));c.disposable=true
for _,key in ipairs({'mp_host','cart_actions','cart_fast_motion'}) do
 c.options[key]=false;assert(not pcall(M.validate,c));c.options[key]=true
end
assert(#M.steps(false)==14 and M.motionDuration==31000)
local steps=M.steps(true);assert(#steps==8 and M.controlDuration==15800)
local step=M.steps(false)[7];local state={}
assert(M.drive(step,state,3.1,15000)==5)
assert(M.drive(step,state,3.0,15100)==5)
assert(M.drive(step,state,2.93,15200)==1)
assert(M.drive(step,state,3.1,15300)==1,'Released correction re-pressed')
state={};assert(M.drive(step,state,0,15000)==5)
assert(M.drive(step,state,0,15350)==1,'No-motion correction did not time out')
assert(steps[2][2]==1 and steps[4][2]==3 and steps[4][3]==1 and steps[6][2]==1 and steps[6][3]==2)
for _,step in ipairs(steps) do print(step[4]..' '..step[1]..' '..step[2]..' '..step[3]) end
'''
        result=subprocess.run([shutil.which('luajit'),'-e',script],check=True,capture_output=True,text=True)
        self.assertEqual([tuple(line.split()) for line in result.stdout.splitlines()],
                         [(name,str(t),str(drive),str(gait)) for name,t,drive,gait in VISUAL['CONTROL_PHASES']])


if __name__=='__main__':unittest.main()
