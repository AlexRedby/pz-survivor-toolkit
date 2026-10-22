"""Reject incomplete/fabricated approach, collision, ownership and native queue-tail evidence."""
import copy
import importlib.util
import json
import shutil
import subprocess
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'tests/native_queue/contributions/wooden_cart_motion'
VEHICLE_STATE='id=42 z=7.0 static=true active=false bodyBlocked=true crossBlocked=true hull=-2.0,-1.5,-0.10,-1.5,-0.10,2.5,-2.0,2.5'
spec = importlib.util.spec_from_file_location('cart_approach', SOURCE/'analyze-approach.py')
analyzer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analyzer)


def fixture():
    lines, lifecycle = ['[WOOD_BANK] RUN_STARTED'], []
    for index, name in enumerate(analyzer.CASES):
        start, item = 100000+index*20000, index+1
        success = name in analyzer.SUCCESS
        terminal = 1800 if name=='precise-blocked' else 4000
        def row(elapsed):
            owned = success and elapsed >= (4000 if name == 'container-equip' else 3000)
            lost = name == 'approach-target-loss' and elapsed > 1000
            active = 750 <= elapsed < terminal
            tail = name in ('approach-target-loss', 'approach-tail-success') and elapsed >= 3000
            x, y = (.30 if name=='precise-blocked' else 2., .5)
            if name == 'wall-detour':
                x=-1+3*max(0,min(1,(elapsed-1500)/1000))
                y=.5+2.5*max(0,min(1,(elapsed-700)/1000))-2.5*max(0,min(1,(elapsed-2500)/1000))
            elif name == 'wrong-side': x=4-2*max(0,min(1,(elapsed-700)/2000))
            elif name in ('approach-target-loss','approach-tail-success'):
                y=.5+max(0,min(1,(elapsed-3000)/1000))
            if elapsed >= terminal:
                x, y = ((2., 1.5) if tail else (.05, .5) if name == 'precise-blocked' else (2., .5))
            elif name == 'precise-blocked':
                x=.30-.25*max(0,min(1,(elapsed-700)/800))
            return dict(case=name, start=start, wall=start+elapsed, elapsed=elapsed, id=item,
                        cargoID=100+item, cargoWeight=1., z=7,
                        collisionKind='vehicle' if name=='precise-blocked' else '',collisionX=-.10,vehicleState=VEHICLE_STATE if name=='precise-blocked' else '',
                        inventoryCount=int(owned), worldCount=int(not owned and not lost and name != 'container-equip'),
                        containerCount=int(not owned and name == 'container-equip'), removed=lost,
                        primaryID=item if owned else -1, secondaryID=item if owned else -1,
                        x=x, y=y, startX=-1. if name == 'wall-detour' else 4. if name=='wrong-side' else .30 if name=='precise-blocked' else 2., startY=.5,
                        goalX=0. if name == 'precise-blocked' else 2., goalY=.5,
                        nativeTargetX=.05 if name=='precise-blocked' and elapsed>=750 else 0. if name=='precise-blocked' else 2.,nativeTargetY=.5,
                        tailX=2., tailY=1.5, wallX=0, wallY=0,cartX=3.,cartY=.5,
                        nativeActions=int(active), luaActions=2 if active and name in ('approach-cancel','approach-target-loss','approach-tail-success') else int(active),
                        hasPath=active and (name != 'container-equip'),
                        actionType=('ISCartEquipAction' if name == 'container-equip' else 'ISWalkToTimedActionF') if active else '',
                        approachResult='Succeeded' if elapsed >= terminal and name != 'container-equip' else '',
                        tailResult='Succeeded' if tail and elapsed >= terminal else '',
                        active=False, recovering=False, rendered=False, ToolkitWoodCartAction=False,
                        route='inventory-menu' if name == 'container-equip' else 'world-menu')
        lines.append(f'[WOOD_BANK] CASE {name} attempt=0 wall={start}')
        events = [(0, 'prepared'), (700, 'queued')]
        if name in ('approach-cancel','approach-target-loss'):
            events.append((1000, 'cancelRequested' if name == 'approach-cancel' else 'targetRemoved'))
        events += [(terminal,'terminal'),(terminal+1000,'settled')]
        for elapsed in range(0,terminal+1001,25):
            value=row(elapsed)
            lines.append('[CART_APPROACH_SAMPLE] '+json.dumps(value))
            for when,event in events:
                if when==elapsed:
                    lines.append('[CART_APPROACH_EVENT] '+json.dumps(dict(value,event=event)))
        types=['ISCartEquipAction'] if name=='container-equip' else ['ISWalkToTimedActionF']+(['ToolkitWoodCartPickup'] if success else [])
        if name in ('approach-target-loss','approach-tail-success'): types.append('ISWalkToTimedActionF')
        for group,kind in enumerate(types):
            stopped=group==0 and name=='approach-cancel'
            begin=750+group*1000;end=begin+900
            for event,elapsed in [('start',begin)]+([('stop',end)] if stopped else [('perform',end),('complete',end)]):
                lifecycle.append(dict(event=event,wallTimeMillis=start+elapsed,nativeActionId=index*10+group,
                                      metaType=kind,phase='exit',playerNum=0,threw=None))
        lines.append(f'[WOOD_BANK] COMPLETE {name} wall={start} file=/owned/{name}.mp4 frames=150 seconds=5.0')
    lines.extend(['[CART_APPROACH] CLEANUP_COMPLETE','[WOOD_BANK] ALL_COMPLETE cases=7'])
    return '\n'.join(lines),lifecycle


def change_rows(values, callback):
    lines=[]
    for line in values[0].splitlines():
        if line.startswith(('[CART_APPROACH_SAMPLE] ','[CART_APPROACH_EVENT] ')):
            prefix,raw=line.split('] ',1);row=json.loads(raw);callback(row);line=prefix+'] '+json.dumps(row)
        lines.append(line)
    return '\n'.join(lines),values[1]


class ApproachChecks(unittest.TestCase):
    def test_complete_evidence(self):
        report=analyzer.analyze(*fixture())
        self.assertTrue(report['functionalPass'] and report['approachVerified'])
        self.assertEqual(len(report['cases']),7)

    def test_entry_contact_requires_actual_pre_menu_walk_and_outfit(self):
        def entry(row):
            elapsed=row['elapsed']
            row.update(entryContactRepro=True,female=False,pantsType='Base.Trousers_JeanBaggy',pantsID=42,pantsModel='Skinned/Clothes/Bob_Trousers',
                       preWalkStartedAt=row['start']+300 if elapsed>=300 else -1,
                       preWalkReleasedAt=row['start']+650 if elapsed>=650 else -1,
                       preWalkSeen=elapsed>=650,preWalkDistance=.2*max(0,min(1,(elapsed-300)/350)),
                       preWalkDrive=int(300<=elapsed<650))
            row['x']+=row['preWalkDistance']
        text,life=change_rows(fixture(),entry)
        lines=[line for line in text.splitlines() if ('container-equip' in line or line.startswith('[WOOD_BANK] RUN_STARTED'))]
        lines+=['[CART_APPROACH] CLEANUP_COMPLETE','[WOOD_BANK] ALL_COMPLETE cases=1']
        text='\n'.join(lines);life=[r for r in life if r['nativeActionId']==0]
        self.assertTrue(analyzer.analyze(text,life,scenes=['container-equip'],entry_contact=True)['functionalPass'])
        for field,value in [('preWalkSeen',False),('preWalkDistance',0),('pantsType','Base.Skirt')]:
            changed=change_rows((text,life),lambda row:row.update({field:value}))
            with self.subTest(field=field),self.assertRaises(AssertionError):
                analyzer.analyze(*changed,scenes=['container-equip'],entry_contact=True)
        with self.assertRaisesRegex(AssertionError,'moved before'):
            analyzer.analyze(text,life,scenes=['container-equip'])

    def test_native_completion_must_be_exactly_once(self):
        for mode in ('missing','duplicate','wrong-type'):
            values=list(copy.deepcopy(fixture()))
            pos=next(i for i,r in enumerate(values[1]) if r['metaType']=='ToolkitWoodCartPickup' and r['event']=='complete')
            if mode=='missing': values[1].pop(pos)
            elif mode=='duplicate': values[1].insert(pos,dict(values[1][pos]))
            else: values[1][pos]['metaType']='ISCartEquipAction'
            with self.subTest(mode=mode),self.assertRaisesRegex(AssertionError,'lifecycle|identity'):
                analyzer.analyze(*values)

    def test_target_loss_cannot_consume_independent_tail(self):
        values=fixture()
        # Target-loss scene has one approach (50) and one independent walk (51).
        values=(values[0],[r for r in values[1] if r['nativeActionId']!=51])
        with self.assertRaisesRegex(AssertionError,'independent tail'): analyzer.analyze(*values)

    def test_cancelled_tail_must_not_run(self):
        values=list(copy.deepcopy(fixture()))
        values[1].extend(dict(event=e,wallTimeMillis=181800+i*100,nativeActionId=49,metaType='ISWalkToTimedActionF',phase='exit',playerNum=0,threw=None)
                         for i,e in enumerate(('start','perform','complete')))
        with self.assertRaisesRegex(AssertionError,'independent tail'): analyzer.analyze(*values)

    def test_cancel_accepts_captured_bare_walk_blend_same_ms_order_and_exact_native_stop(self):
        values=self.cancel_blend_fixture()
        report=analyzer.analyze(*values)
        cancel=next(row for row in report['cases'] if row['case']=='approach-cancel')
        self.assertLessEqual(cancel['nativeCancelPeakDrift'],.06)
        self.assertGreater(cancel['nativeCancelPeakDrift'],.04)
        self.assertEqual(cancel['nativeCancelStopWall'],184001)
        self.assertLessEqual(cancel['nativeCancelSettledByMillis'],500)

    @staticmethod
    def cancel_blend_fixture():
        # Native09 measured offsets from cancellation terminal, with native stop one ms later.
        # The last pre-terminal sample shares its timestamp but still contains the active path/tail.
        points=[(0,0.,0.),(100,.04296875,-.009765625),(200,.04296875,-.015625),
                (467,.015625,-.013671875),(1000,.015625,-.013671875)]
        def blend(row):
            if row['case']!='approach-cancel' or row['elapsed']<4000: return
            if row['elapsed']==4000:
                if 'event' not in row:
                    row.update(luaActions=2,nativeActions=1,hasPath=True,actionType='ISWalkToTimedActionF')
                return
            elapsed=row['elapsed']-4000
            for a,b in zip(points,points[1:]):
                if a[0]<=elapsed<=b[0]:
                    weight=(elapsed-a[0])/(b[0]-a[0])
                    row['x']=2+a[1]+(b[1]-a[1])*weight;row['y']=.5+a[2]+(b[2]-a[2])*weight
                    break
        text,lifecycle=change_rows(fixture(),blend)
        for row in lifecycle:
            if row['nativeActionId']==40 and row['event']=='stop': row['wallTimeMillis']=184001
        return text,lifecycle

    def test_cancel_still_rejects_renewed_work_large_drift_and_nonsettlement(self):
        for mode in ('path','tail','drift','nonsettlement'):
            def corrupt(row):
                if row['case']!='approach-cancel' or row['elapsed']<=4000: return
                if mode=='path' and row['elapsed']==4050: row['hasPath']=True
                if mode=='tail' and row['elapsed']==4050: row.update(luaActions=1,nativeActions=1)
                if mode=='drift' and row['elapsed']==4100: row['x']=2.07
                if mode=='nonsettlement' and row['elapsed']==4750: row['x']+=.01
            with self.subTest(mode=mode),self.assertRaises(AssertionError):
                analyzer.analyze(*change_rows(self.cancel_blend_fixture(),corrupt))
        text,lifecycle=self.cancel_blend_fixture()
        for row in lifecycle:
            if row['nativeActionId']==40 and row['event']=='stop': row['wallTimeMillis']=184100
        with self.assertRaisesRegex(AssertionError,'stop occurred after post-terminal'):
            analyzer.analyze(text,lifecycle)

    def test_other_scenes_still_require_immediate_terminal_position(self):
        values=change_rows(fixture(),lambda row: row.update(x=row['x']+.003)
                           if row['case']=='wrong-side' and row['elapsed']==4050 else None)
        with self.assertRaisesRegex(AssertionError,'Actor moved after native terminal'):
            analyzer.analyze(*values)

    def test_cart_and_cargo_identity_and_container_route(self):
        for key,value in [('cargoID',999),('worldCount',2),('primaryID',999),('route','direct-constructor')]:
            with self.subTest(key=key):
                values=change_rows(fixture(),lambda row: row.update({key:value}) if row['case']=='container-equip' and row['elapsed']==1000 else None)
                with self.assertRaises(AssertionError): analyzer.analyze(*values)

    def test_blocked_general_path_failure_is_not_precise_arrival_evidence(self):
        values=change_rows(fixture(),lambda row: row.update(x=.30) if row['case']=='precise-blocked' else None)
        with self.assertRaisesRegex(AssertionError,'clipped native arrival'): analyzer.analyze(*values)

    def test_static_blocked_denial_requires_native_clipping_map_proof_and_no_equip(self):
        for mode in ('no-clipping','no-path','moved-vehicle','missing-map-proof','wrong-goal','equipped'):
            def corrupt(row):
                if row['case']!='precise-blocked': return
                if mode=='no-clipping': row['nativeTargetX']=row['goalX']
                if mode=='no-path': row['hasPath']=False
                if mode=='moved-vehicle' and row['elapsed']>1000: row['vehicleState']=row['vehicleState'].replace('-0.10','-0.09')
                if mode=='missing-map-proof': row['vehicleState']=row['vehicleState'].replace('bodyBlocked=true','bodyBlocked=false')
                if mode=='wrong-goal': row['goalX']=.02
                if mode=='equipped' and row['elapsed']>=1800:
                    row.update(primaryID=row['id'],secondaryID=row['id'],inventoryCount=1,worldCount=0)
            with self.subTest(mode=mode),self.assertRaises(AssertionError):
                analyzer.analyze(*change_rows(fixture(),corrupt))
        report=analyzer.analyze(*fixture())
        self.assertFalse(report['preciseStallExercised'])

    @unittest.skipUnless(shutil.which('luajit'),'Requires LuaJIT')
    def test_native_ground_zero_offset_randomization_is_corrected_before_stance_and_telemetry(self):
        source=(SOURCE/'scenario-approach.lua').read_text()
        body=source.split('-- Native ground placement begin.',1)[1].split('-- Native ground placement end.',1)[0].split('\n',1)[1]
        script=r'''
            p={};area={z=7};cartX=0;cartY=0;local world
            item={getWorldItem=function() return world end,getContainer=function() return nil end,
                setWorldZRotation=function(_,angle) assert(angle==135) end}
            function removeWorld() world=nil end
            local square={AddWorldInventoryItem=function(_,value,x,y,z,flag)
                assert(value==item and flag)
                -- Actual IsoWorldInventoryObject constructor semantics: exactly zero means random offset.
                world={xoff=x==0 and .153 or x,yoff=y==0 and .487 or y,
                    setOffX=function(self,value) self.xoff=value end,setOffY=function(self,value) self.yoff=value end,
                    getWorldPosX=function(self) return squareX+self.xoff end,getWorldPosY=function(self) return squareY+self.yoff end}
            end}
            function getCell() return {getGridSquare=function(_,x,y,z) squareX=x;squareY=y;return square end} end
            SaucedCarts={markDropPersistent=function() return true end,updateCartVisual=function() end}
            function toolkitWoodCartStance(_,value) return {x=value:getWorldPosX()+.4,y=value:getWorldPosY()+.45} end
        '''+body+r'''
            ground(10827,10142.5)
            assert(cartX==10827 and cartY==10142.5 and world.xoff==0)
            assert(stance.x==cartX+.4 and stance.y==cartY+.45)
            ground(10827.25,10142)
            assert(cartX==10827.25 and cartY==10142 and world.yoff==0)
            assert(stance.x==cartX+.4 and stance.y==cartY+.45)
        '''
        result=subprocess.run([shutil.which('luajit'),'-'],input=script,text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_detour_cannot_claim_clear_straight_line(self):
        values=change_rows(fixture(),lambda row: row.update(y=.5) if row['case']=='wall-detour' else None)
        with self.assertRaisesRegex(AssertionError,'route around real wall'): analyzer.analyze(*values)

    def test_wrong_side_must_be_opposite_handles(self):
        values=change_rows(fixture(),lambda row: row.update(cartX=1.) if row['case']=='wrong-side' else None)
        with self.assertRaisesRegex(AssertionError,'opposite the handles'): analyzer.analyze(*values)

    def test_missing_scene_sampling_and_cleanup_fail(self):
        values=fixture()
        for old,new in [('[WOOD_BANK] COMPLETE wrong-side','[WOOD_BANK] OMITTED wrong-side'),
                        ('[CART_APPROACH] CLEANUP_COMPLETE',''),('[WOOD_BANK] ALL_COMPLETE cases=7','')]:
            with self.subTest(old=old),self.assertRaises(AssertionError): analyzer.analyze(values[0].replace(old,new),values[1])
        rows=change_rows(values,lambda row: row.update(recovering=True) if row['case']=='wrong-side' and row['elapsed']>=5000 else None)
        with self.assertRaisesRegex(AssertionError,'cleanup'): analyzer.analyze(*rows)


if __name__=='__main__': unittest.main()
