"""Host injury protocol and native evidence rejection; synthetic fixtures only."""
import copy
import json
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parent.parent
SOURCE=ROOT/'tests/native_queue/contributions/wooden_cart_multiplayer'
COMMON=runpy.run_path(str(SOURCE/'analyze.py'))
INJURY=runpy.run_path(str(SOURCE/'analyze-injury.py'))
FIXTURE=runpy.run_path(str(SOURCE/'self_check.py'))['fixture']


def capture(root,side='left',severity='mild',variant='wooden-wheelbarrow'):
    FIXTURE(root,fast=True,variant=variant)
    selection=json.loads((root/'selection.json').read_text())
    selection['options'].update(mp_host=True,cart_injury=True,cart_injury_side=side,cart_injury_severity=severity)
    (root/'selection.json').write_text(json.dumps(selection))
    for role in COMMON['ROLES']:
        path=root/(role+'-launch.log');lines=path.read_text().splitlines()
        for i,line in enumerate(lines):
            for marker in ('[CART_MP] CART_PAD ','[CART_MP] SETUP ','[CART_MP] PAD_READY '):
                if marker in line:
                    prefix,raw=line.split(marker,1);pad=json.loads(raw)
                    pad.update(minX=-31,minY=-31,size=63,bankVersion=5)
                    if marker.endswith('PAD_READY '):pad['floors']=3969
                    lines[i]=prefix+marker+json.dumps(pad)
        lines=[line.replace('"status": "captured"','"status": "captured", "cartInjury": true') for line in lines]
        base=json.loads(next(line.split('[CART_MP_STATE] ',1)[1] for line in reversed(lines) if '[CART_MP_STATE] ' in line))
        lines=[line for line in lines if '[CART_MP_STATE] ' not in line or json.loads(line.split('[CART_MP_STATE] ',1)[1])['wall']<126000]
        frames=[]
        if role!='server':
            frame=json.loads((root/role/'body-clearance.jsonl').read_text().splitlines()[-1])
            for name,t,drive,gait in INJURY['PHASES']:
                lines.append(f'[CART_MP] PHASE {name} wall={100000+t} elapsed={t}')
        for t in range(26000,INJURY['DURATION'],100):
            name,start,drive,gait=max((p for p in INJURY['PHASES'] if p[1]<=t),key=lambda p:p[1])
            injured=28000<=t<41000
            scalar=(1 if side=='left' else -1)*(.4 if severity=='mild' else 1) if injured else 0
            clip=('Bob_WalkLightLimp' if severity=='mild' else 'Bob_WalkHeavyLimp')+('R' if side=='left' else 'L') if injured else 'Bob_Walk' if drive else 'Bob_Idle'
            x=7+(min(t,43000)-26000)*.0002
            heading=-3
            for i,(_,begin,mask,_) in enumerate(INJURY['PHASES']):
                end=INJURY['PHASES'][i+1][1] if i+1<len(INJURY['PHASES']) else INJURY['DURATION']
                heading+=(-1 if mask==5 else 1 if mask==8 else 0)*min(end-begin,max(0,t-begin))*.0002
            row=dict(base,wall=100000+t,x=x,y=-1,heading=heading,run=bool(gait and severity=='mild'),sprint=False,
                     walkInjury=scalar,walkSpeed=1.,motion=True,visualEnabled=True,stepY=1 if drive else 0,
                     inventoryCount=0 if role=='client2' else 1,primaryInInventory=role!='client2',worldID=-1,
                     characterActions=0,hasPath=False,performing=False,injuryProbeVersion=1,god=False,dead=False,
                     tracks=clip+'=.8@1;',trackProgress=[dict(name=clip,time=(t%1000)/1000,duration=1,weight=1)],
                     leftScratch=0,rightScratch=0,leftFracture=0,rightFracture=0)
            if injured:row[side+('Scratch' if severity=='mild' else 'Fracture')]=8 if severity=='mild' else 35
            lines.append('[CART_MP_STATE] '+json.dumps(row))
            if role=='client1':
                if t==start:
                    event=dict(phase=name,wall=100000+t,elapsed=t,side=side,severity=severity,drive=drive,gait=gait,x=x,y=-1,
                               authority='server-request',mutation='injure' if name=='injury-apply' else 'heal' if name=='injury-heal' else 'none')
                    lines.append('[CART_MP_INJURY] PHASE '+json.dumps(event))
                lines.append('[CART_MP_INJURY] INPUT '+json.dumps(dict(wall=100000+t,elapsed=t,phase=name,drive=drive,gait=gait,
                    id=42,cargoID=99,cargoWeight=70,inventoryCount=1,luaActions=0,nativeActions=0,hasPath=False,god=False,dead=False)))
            if role!='server':
                frames.append(dict(frame,wallTimeMillis=100000+t,walkInjury=scalar,walkSpeed=1.,tracks=row['tracks']))
            if t==start and name in ('injury-healthy','injury-apply','injury-heal'):
                receipt=dict(phase=name,id=42,wall=100000+t+10,side=side,severity=severity,source='NetworkPlayerAI.syncDamage',
                             walkInjury=scalar,**{key:row[key] for key in INJURY['FOOT']})
                if role=='server':lines.append('[CART_MP_INJURY] SERVER_MUTATION '+json.dumps(receipt))
                if role=='client1':
                    lines.append('[CART_MP_INJURY] ACK '+json.dumps(dict(receipt,wall=100000+t+20,serverWall=receipt['wall'],requestWall=100000+t)))
        path.write_text('\n'.join(lines)+'\n')
        if role!='server':
            with (root/role/'body-clearance.jsonl').open('a') as output:output.write('\n'.join(map(json.dumps,frames))+'\n')


class CartMPInjuryTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        capture(self.root)

    def analyze(self):return COMMON['analyze'](self.root)

    def mutate(self,role,marker,fn):
        path=self.root/(role+'-launch.log');lines=[]
        for line in path.read_text().splitlines():
            if marker in line:
                prefix,raw=line.split(marker,1);row=json.loads(raw)
                if row.get('wall',0)>=126000:fn(row)
                line=prefix+marker+json.dumps(row)
            lines.append(line)
        path.write_text('\n'.join(lines)+'\n')

    def test_native_matrix_all_sides_severities_and_cart_models(self):
        for variant in COMMON['VARIANTS']:
            for side in ('left','right'):
                for severity in ('mild','heavy'):
                    with self.subTest(variant=variant,side=side,severity=severity),tempfile.TemporaryDirectory() as directory:
                        root=Path(directory);capture(root,side,severity,variant)
                        result=COMMON['analyze'](root)['injury']
                        self.assertTrue(result['injuryVerified'])
                        self.assertTrue(result['observerNativeLimpVerified'])
                        self.assertEqual(result['nativeDamageSnapshots'],3)
                        self.assertFalse(result['geometryVerified'])
                        self.assertEqual(len(result['phases']),9)
                        self.assertFalse(next(r for r in result['phases'] if r['phase']=='injury-sprint')['roles']['client1']['actualSprint'])

    def test_owner_body_damage_cannot_be_replaced_by_scalar(self):
        self.mutate('client1','[CART_MP_STATE] ',lambda row:row.update(leftScratch=0))
        with self.assertRaisesRegex(ValueError,'BodyDamage'):self.analyze()

    def test_server_body_damage_must_persist_after_native_snapshot(self):
        self.mutate('server','[CART_MP_STATE] ',lambda row:row.update(leftScratch=0))
        with self.assertRaisesRegex(ValueError,'server: real owner BodyDamage'):self.analyze()

    def test_native_damage_authority_and_matching_ack_required(self):
        path=self.root/'server-launch.log';original=path.read_text()
        path.write_text('\n'.join(line for line in original.splitlines() if '[CART_MP_INJURY] SERVER_MUTATION ' not in line)+'\n')
        with self.assertRaisesRegex(ValueError,'authority or acknowledgement'):self.analyze()
        path.write_text(original)
        self.mutate('client1','[CART_MP_INJURY] ACK ',lambda row:row.update(source='local-bodydamage'))
        with self.assertRaisesRegex(ValueError,'acknowledgement differs'):self.analyze()

    def test_observer_must_receive_native_injury(self):
        self.mutate('client2','[CART_MP_STATE] ',lambda row:row.update(walkInjury=0))
        with self.assertRaisesRegex(ValueError,'injury side/scalar'):self.analyze()

    def test_observer_limp_must_follow_native_blend(self):
        self.mutate('client2','[CART_MP_STATE] ',lambda row:row.update(tracks='Bob_Walk=.8@1;'))
        with self.assertRaisesRegex(ValueError,'limp blend'):self.analyze()

    def test_render_tracks_cannot_be_replaced_by_state_tracks(self):
        path=self.root/'client2/body-clearance.jsonl';rows=[json.loads(line) for line in path.read_text().splitlines()]
        for row in rows:
            if 128500<=row['wallTimeMillis']<129900:row['tracks']='Bob_Walk=.8@1;'
        path.write_text('\n'.join(map(json.dumps,rows))+'\n')
        with self.assertRaisesRegex(ValueError,'limp blend'):self.analyze()

    def test_observer_limp_clock_must_advance(self):
        self.mutate('client2','[CART_MP_STATE] ',lambda row:row.update(trackProgress=[dict(name='Bob_WalkLightLimpR',time=0,duration=1,weight=1)]))
        with self.assertRaisesRegex(ValueError,'frozen'):self.analyze()

    def test_heal_requires_native_injury_and_limp_to_clear(self):
        self.mutate('client2','[CART_MP_STATE] ',lambda row:row.update(walkInjury=.4) if row['wall']>=141500 else None)
        with self.assertRaisesRegex(ValueError,'remained'):self.analyze()

    def test_observer_native_movement_packet_delay_is_bounded_and_reported(self):
        def delayed(row,time):
            if 128000<=time<128800:
                row.update(walkInjury=0,tracks='Bob_Walk=.8@1;')
            if 141000<=time<141800:
                row.update(walkInjury=.4,tracks='Bob_WalkLightLimpR=.8@1;')
        self.mutate('client2','[CART_MP_STATE] ',lambda row:delayed(row,row['wall']))
        path=self.root/'client2/body-clearance.jsonl'
        rows=[json.loads(line) for line in path.read_text().splitlines()]
        for row in rows:delayed(row,row['wallTimeMillis'])
        path.write_text('\n'.join(map(json.dumps,rows))+'\n')
        result=self.analyze()['injury']
        self.assertEqual(result['nativeObserverTransitions']['injury-apply']['firstObservedNativeScalarMs'],800)
        self.assertEqual(result['nativeObserverTransitions']['injury-heal']['firstObservedNativeScalarMs'],800)
        self.mutate('client2','[CART_MP_STATE] ',lambda row:row.update(walkInjury=.4)
                    if 141800<=row['wall']<142200 else None)
        with self.assertRaises(ValueError):self.analyze()

    def test_healing_cannot_stop_and_restart_walking(self):
        self.mutate('client1','[CART_MP_STATE] ',lambda row:row.update(stepY=0) if 140100<=row['wall']<141000 else None)
        with self.assertRaisesRegex(ValueError,'continuous forward'):self.analyze()

    def test_identity_cargo_and_actions_remain_guarded(self):
        original=(self.root/'client2-launch.log').read_text()
        for change in ({'cargoID':100},{'primary':43},{'characterActions':1},{'hasPath':True}):
            with self.subTest(change=change):
                (self.root/'client2-launch.log').write_text(original)
                self.mutate('client2','[CART_MP_STATE] ',lambda row:row.update(change))
                with self.assertRaises(ValueError):self.analyze()

    def test_server_packet_snapshot_can_repeat_across_a_short_client_turn(self):
        self.mutate('server','[CART_MP_STATE] ',lambda row:row.update(x=7.9,heading=-3.1)
                    if 130000<=row['wall']<=132300 else None)
        result=self.analyze()['injury']
        turn=next(p for p in result['phases'] if p['phase']=='injury-left')
        self.assertEqual(turn['roles']['server']['distance'],0)
        self.assertGreater(turn['roles']['client1']['distance'],.03)
        self.assertTrue(result['injuryVerified'])

    def test_server_must_still_receive_overall_injury_movement(self):
        self.mutate('server','[CART_MP_STATE] ',lambda row:row.update(x=7,y=-1,heading=-3))
        with self.assertRaisesRegex(ValueError,'Authoritative injury bank movement'):self.analyze()

    def test_passive_server_uses_whole_unchanged_wound_phase_at_five_hz(self):
        path=self.root/'server-launch.log';lines=[]
        for line in path.read_text().splitlines():
            if '[CART_MP_STATE] ' in line:
                row=json.loads(line.split('[CART_MP_STATE] ',1)[1])
                if 139600<=row['wall']<141000 and row['wall']%200!=0:continue
            lines.append(line)
        path.write_text('\n'.join(lines)+'\n')
        result=self.analyze()['injury']
        phase=next(p for p in result['phases'] if p['phase']=='injury-moving')
        self.assertEqual(phase['roles']['server']['samples'],7)
        self.assertTrue(result['injuryVerified'])

    def test_observer_and_server_must_reconcile_after_healing_stop(self):
        self.mutate('client2','[CART_MP_STATE] ',lambda row:row.update(x=row['x']+.5)
                    if row['wall']>=143000 else None)
        with self.assertRaisesRegex(ValueError,'positions did not reconcile'):self.analyze()

    def test_relayed_actual_running_gait_owns_tracks_after_walk_request(self):
        def relayed(row,time):
            if 139600<=time<140600:
                row.update(run=True,walkSpeed=-.1,tracks='Bob_RunLightLimpR=.8@1;')
                if 'trackProgress' in row:
                    row['trackProgress']=[dict(name='Bob_RunLightLimpR',time=(time%1000)/1000,duration=1,weight=1)]
        self.mutate('client2','[CART_MP_STATE] ',lambda row:relayed(row,row['wall']))
        path=self.root/'client2/body-clearance.jsonl'
        rows=[json.loads(line) for line in path.read_text().splitlines()]
        for row in rows:relayed(row,row['wallTimeMillis'])
        path.write_text('\n'.join(map(json.dumps,rows))+'\n')
        self.assertTrue(self.analyze()['injury']['injuryVerified'])

    def test_remote_body_damage_mutation_receipt_is_rejected(self):
        event=next(line for line in (self.root/'client1-launch.log').read_text().splitlines() if '[CART_MP_INJURY] PHASE ' in line)
        with (self.root/'client2-launch.log').open('a') as output:output.write(event+'\n')
        with self.assertRaisesRegex(ValueError,'mutation is forbidden'):self.analyze()

    def test_render_coverage_is_required_in_each_injury_window(self):
        path=self.root/'client2/body-clearance.jsonl';rows=[json.loads(line) for line in path.read_text().splitlines()]
        path.write_text('\n'.join(json.dumps(r) for r in rows if not 130000<=r['wallTimeMillis']<132400)+'\n')
        with self.assertRaisesRegex(ValueError,'injury-left/client2/render'):self.analyze()

    def test_native_local_only_injury_mutation_and_uninterrupted_input(self):
        lua=shutil.which('luajit') or shutil.which('lua')
        if not lua:self.skipTest('Lua unavailable')
        code='''
local cfg={disposable=true,options={mp_host=true,cart_fast_motion=true,cart_injury=true,cart_injury_side='left',cart_injury_severity='mild'}}
package.preload.QueueTestSelection=function() return cfg end
package.preload.CartMPJSON=function() return {encode=function() return '{}' end} end
isClient=function() return true end;isServer=function() return false end
BodyPartType={Foot_L=1,Foot_R=2}
local god=true;local sent={};local now=126000
local p={isLocalPlayer=function() return true end,getUsername=function() return 'client1' end,
 isGodMod=function() return god end,setGodMod=function(_,v) god=v end,isDead=function() return false end,
 getBodyDamage=function() error('Client must never mutate BodyDamage') end,getX=function() return 1 end,getY=function() return 2 end,
 getPrimaryHandItem=function() return {getID=function() return 42 end} end}
getPlayer=function() return p end;toolkitCartInjurySupported=function() return true end
cartLabDrive=function() error('Injury mutation must not touch held input') end
getTimestampMs=function() return now end
sendClientCommand=function(module,command,args) assert(module=='CartMP');sent[#sent+1]={command=command,args=args} end
local bank=dofile(%s)
local function ack(phase)
 bank.command({phase=phase,id=42,source='NetworkPlayerAI.syncDamage',side='left',severity='mild',wall=now})
end
bank.phase(p,'injury-healthy',now,100000);ack('injury-healthy');assert(not god)
now=128000;bank.phase(p,'injury-apply',now,100000);ack('injury-apply')
assert(not pcall(ack,'injury-apply'),'Duplicate native ack accepted')
now=141000;bank.phase(p,'injury-heal',now,100000);ack('injury-heal');assert(not god)
local remote={};assert(not pcall(bank.phase,remote,'injury-apply',128000,100000))
bank.finish(p);bank.finish(p);assert(#sent==3 and god)
for _,entry in ipairs(sent) do assert(entry.command=='InjuryMutation' and entry.args.id==42) end
''' % json.dumps(str(SOURCE/'injury.lua'))
        result=subprocess.run([lua,'-e',code],text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_server_authority_rejects_duplicate_and_foreign_requests_before_mutation(self):
        lua=shutil.which('luajit') or shutil.which('lua')
        if not lua:self.skipTest('Lua unavailable')
        source=(SOURCE/'server.lua').read_text()
        source=source[source.index('local injuryIndex,'):source.index('local function broadcast(')]
        code='''
local config={options={cart_injury=true,mp_host=true,cart_fast_motion=true,cart_injury_side='left',cart_injury_severity='heavy'}}
local mutations,snapshots,now=0,0,126000
local part={getScratchTime=function() return 0 end,getFractureTime=function() return mutations>0 and 35 or 0 end,
 setFractureTime=function(_,v)assert(v==35);mutations=mutations+1 end,SetInfected=function() end,setInfectedWound=function() end}
local damage={RestoreToFullHealth=function() end,getBodyPart=function()return part end}
local inventory={};local cart={getID=function()return 42 end,getFullType=function()return 'Cart' end,getContainer=function()return inventory end}
local p={getUsername=function()return 'client1' end,getPrimaryHandItem=function()return cart end,getSecondaryHandItem=function()return cart end,
 getInventory=function()return inventory end,setGodMod=function()end,getBodyDamage=function()return damage end}
local players={client1=p};local cartSession={id=42};local epoch=100000;local cartType='Cart'
BodyPartType={Foot_L=1,Foot_R=2};local J={encode=function()return '{}' end}
getTimestampMs=function()return now end
cartMPInjurySync=function(who,id)assert(who==p and id==42);snapshots=snapshots+1;return mutations>0 and 1 or 0 end
sendServerCommand=function(who,module,cmd,args)assert(who==p and module=='CartMP' and cmd=='InjuryAck' and args.source=='NetworkPlayerAI.syncDamage') end
''' + source + '''
local function args(phase,id)return {phase=phase,id=id or 42,side='left',severity='heavy'} end
assert(not pcall(injuryMutation,p,args('injury-apply')) and snapshots==0)
injuryMutation(p,args('injury-healthy'));now=128000
assert(not pcall(injuryMutation,{},args('injury-apply')) and snapshots==1)
assert(not pcall(injuryMutation,p,args('injury-apply',43)) and mutations==0)
injuryMutation(p,args('injury-apply'));assert(mutations==1 and snapshots==2)
assert(not pcall(injuryMutation,p,args('injury-apply')) and mutations==1 and snapshots==2)
now=141000;injuryMutation(p,args('injury-heal'));assert(snapshots==3)
'''
        result=subprocess.run([lua,'-e',code],text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)


if __name__=='__main__':unittest.main()
