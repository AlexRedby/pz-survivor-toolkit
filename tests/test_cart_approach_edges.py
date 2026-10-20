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
VEHICLE_STATE='id=42 z=7.0 static=true active=false bodyBlocked=true crossBlocked=true hull=-2.0,-1.5,-0.27,-1.5,-0.27,2.5,-2.0,2.5'
spec = importlib.util.spec_from_file_location('cart_approach', SOURCE/'analyze-approach.py')
analyzer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analyzer)


def fixture():
    lines, lifecycle = ['[WOOD_BANK] RUN_STARTED'], []
    for index, name in enumerate(analyzer.CASES):
        start, item = 100000+index*20000, index+1
        success = name in analyzer.SUCCESS
        terminal = 4000
        def row(elapsed):
            owned = success and elapsed >= (4000 if name == 'container-equip' else 3000)
            lost = name == 'approach-target-loss' and elapsed > 1000
            active = 750 <= elapsed < terminal
            tail = name in ('approach-target-loss', 'approach-tail-success') and elapsed >= 3000
            x, y = (2., .5)
            if name == 'wall-detour':
                x=-1+3*max(0,min(1,(elapsed-1500)/1000))
                y=.5+2.5*max(0,min(1,(elapsed-700)/1000))-2.5*max(0,min(1,(elapsed-2500)/1000))
            elif name == 'wrong-side': x=4-2*max(0,min(1,(elapsed-700)/2000))
            elif name in ('approach-target-loss','approach-tail-success'):
                y=.5+max(0,min(1,(elapsed-3000)/1000))
            if elapsed >= terminal:
                x, y = ((2., 1.5) if tail else (.03, .5) if name == 'precise-blocked' else (2., .5))
            elif name == 'precise-blocked':
                x = .03
            return dict(case=name, start=start, wall=start+elapsed, elapsed=elapsed, id=item,
                        cargoID=100+item, cargoWeight=1., z=7,
                        collisionKind='vehicle' if name=='precise-blocked' else '',collisionX=-.27,vehicleState=VEHICLE_STATE if name=='precise-blocked' else '',
                        inventoryCount=int(owned), worldCount=int(not owned and not lost and name != 'container-equip'),
                        containerCount=int(not owned and name == 'container-equip'), removed=lost,
                        primaryID=item if owned else -1, secondaryID=item if owned else -1,
                        x=x, y=y, startX=-1. if name == 'wall-detour' else 4. if name=='wrong-side' else .03 if name=='precise-blocked' else 2., startY=.5,
                        goalX=0. if name == 'precise-blocked' else 2., goalY=.5,
                        tailX=2., tailY=1.5, wallX=0, wallY=0,cartX=3.,cartY=.5,
                        nativeActions=int(active), luaActions=2 if active and name in ('approach-cancel','approach-target-loss','approach-tail-success') else int(active),
                        hasPath=active and (name != 'container-equip'),
                        actionType=('ISCartEquipAction' if name == 'container-equip' else 'ISWalkToTimedActionF') if active else '',
                        approachResult='Failed' if name == 'precise-blocked' and elapsed >= terminal else 'Succeeded' if elapsed >= terminal and name != 'container-equip' else '',
                        tailResult='Succeeded' if tail and elapsed >= terminal else '',
                        active=False, recovering=False, rendered=False, ToolkitWoodCartAction=False,
                        route='inventory-menu' if name == 'container-equip' else 'world-menu')
        lines.append(f'[WOOD_BANK] CASE {name} attempt=0 wall={start}')
        if name=='precise-blocked':
            # Ten real native approach completions advance .03 each; the final action stalls.
            for number in range(1,12):
                begin=start-4500+(number-1)*200
                initial=.33-.03*(number-1);goal=round(.33-.03*number,5)
                failed=number==11
                times=[(0,'queued')]+[(t,'sample') for t in range(25,801 if failed else 126,25)]+[(825 if failed else 150,'terminal')]
                for elapsed,event in times:
                    x=initial if failed else max(goal,initial-.03*elapsed/125)
                    lines.append('[CART_APPROACH_CALIBRATION] '+json.dumps(dict(case=name,start=start,round=number,
                        wall=begin+elapsed,x=x,y=.5,collisionKind='vehicle',collisionX=-.27,vehicleState=VEHICLE_STATE,goalX=goal,goalY=.5,nativeTargetX=goal,nativeTargetY=.5,
                        started=event!='queued',hasPath=event=='sample',actionType='ISWalkToTimedActionF',event=event,
                        result=('Failed' if failed else 'Succeeded') if event=='terminal' else 'Working')))
                for event,when in [('start',1)]+([('stop',824)] if failed else [('perform',149),('complete',149)]):
                    lifecycle.append(dict(event=event,wallTimeMillis=begin+when,nativeActionId=1000+number,
                        metaType='ISWalkToTimedActionF',phase='exit',playerNum=0,threw=None))
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
            stopped=group==0 and name in ('precise-blocked','approach-cancel')
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

    def test_cart_and_cargo_identity_and_container_route(self):
        for key,value in [('cargoID',999),('worldCount',2),('primaryID',999),('route','direct-constructor')]:
            with self.subTest(key=key):
                values=change_rows(fixture(),lambda row: row.update({key:value}) if row['case']=='container-equip' and row['elapsed']==1000 else None)
                with self.assertRaises(AssertionError): analyzer.analyze(*values)

    def test_blocked_general_path_failure_is_not_precise_arrival_evidence(self):
        values=change_rows(fixture(),lambda row: row.update(x=.03+min(.27,max(0,row['elapsed']-700)*.002)) if row['case']=='precise-blocked' else None)
        with self.assertRaisesRegex(AssertionError,'final alignment'): analyzer.analyze(*values)

    def test_blocked_requires_real_production_path_calibration_before_public_approach(self):
        text,lifecycle=fixture()
        for mode in ('missing','wrong-action','clipped-target','no-rejection','short-rejection','jump','wrong-goal','vehicle-moved','missing-map-proof'):
            lines=[]
            for line in text.splitlines():
                if line.startswith('[CART_APPROACH_CALIBRATION] '):
                    if mode=='missing': continue
                    row=json.loads(line.split('] ',1)[1])
                    if mode=='wrong-action': row['actionType']='CartApproachWallCalibration'
                    if mode=='clipped-target' and row['round']==11: row['nativeTargetX']+=.02
                    if mode=='no-rejection' and row['round']==11: row['hasPath']=False
                    if mode=='short-rejection' and row['round']==11: row['wall']=157500+(row['wall']-157500)//2
                    if mode=='jump' and row['round']==2: row['x']+=.02
                    if mode=='vehicle-moved' and row['round']==2: row['vehicleState']=row['vehicleState'].replace('-0.27','-0.26')
                    if mode=='missing-map-proof': row['vehicleState']=row['vehicleState'].replace('bodyBlocked=true','bodyBlocked=false')
                    line='[CART_APPROACH_CALIBRATION] '+json.dumps(row)
                lines.append(line)
            values=('\n'.join(lines),lifecycle)
            if mode=='wrong-goal':
                values=change_rows(values,lambda row: row.update(goalX=.02) if row['case']=='precise-blocked' else None)
            with self.subTest(mode=mode),self.assertRaisesRegex(AssertionError,'calibration'):
                analyzer.analyze(*values)
        missing_native=[r for r in lifecycle if r['nativeActionId']!=1011]
        with self.assertRaisesRegex(AssertionError,'calibration.*native action'):
            analyzer.analyze(text,missing_native)

    @unittest.skipUnless(shutil.which('luajit'),'Requires LuaJIT')
    def test_calibration_queues_actual_walk_class_and_rejects_planner_failure_and_clipping(self):
        source=(SOURCE/'scenario-approach.lua').read_text()
        body=source.split('-- Native calibration begin.',1)[1].split('-- Native calibration end.',1)[0]
        body=body.split('\n',1)[1]
        script=r'''
            wallX=0;wallY=0;collisionX=0;calibrationAt=0;calibration={rows={},round=0,startX=1};now=0
            local pending={};local originalPerform=function() end
            BehaviorResult={Succeeded='Succeeded',Failed='Failed',Working='Working'}
            p={x=1,path=false,getX=function(self) return self.x end,getY=function() return .5 end,
               hasPath=function(self) return self.path end,getPathFindBehavior2=function() return path end}
            path={getTargetX=function() return calibration.goalX end,getTargetY=function() return .5 end}
            item={getWorldItem=function() return world end};world={getWorldPosX=function() return cartX end,getWorldPosY=function() return cartY end}
            function empty() return #pending==0 and not p.path end
            function queue() return pending end
            function encode() return '{}' end
            function cartLabVehicleState() return 'owned vehicle' end
            function ground(x,y) cartX=x;cartY=y;stance={x=x,y=y} end
            Vector3f={new=function(x,y,z) return {x=function() return x end,y=function() return y end} end}
            area={z=7,checkPosition=function() end}
            ISWalkToTimedActionF={perform=originalPerform,new=function(self,actor,location)
                return {Type='ISWalkToTimedActionF',perform=originalPerform,isStarted=function(self) return self.started end}
            end}
            ISTimedActionQueue={add=function(action)
                assert(action.perform==originalPerform and not action.onCompleteFunc and not action.additionalTest)
                assert(action.toolkitWoodCartItem==item);pending={action}
            end}
        '''+body+r'''
            startCalibrationRound(0)
            assert(calibration.action.Type=='ISWalkToTimedActionF' and math.abs(calibration.goalX-.97)<.00001)
            local action=calibration.action;action.started=true;p.path=true
            -- A genuine successful approach reaches the exact original target and drains before the next round.
            p.x=calibration.goalX;action.result=BehaviorResult.Succeeded;p.path=false;pending={}
            assert(not calibrate(150) and calibration.nextRound)
            assert(not calibrate(175) and calibration.round==2 and not calibration.nextRound)
            action=calibration.action;action.started=true;action.result=BehaviorResult.Failed;pending={}
            assert(not pcall(calibrate,200)) -- no active-path stall: planner-only failure
            pending={action};action.result=BehaviorResult.Working;p.path=true
            path.getTargetX=function() return calibration.goalX+.02 end
            assert(not pcall(calibrate,225)) -- native planner clipping must never calibrate the helper
            -- Reproduce native06's first integer placement randomization, then fractional placement.
            -- The live pre-queue guard must reject it before any native action can start.
            pending={};p.path=false;local calls=0
            ground=function(x,y) calls=calls+1;cartX=x;cartY=y;stance={x=x+(calls==1 and .15 or 0),y=y} end
            local before=calibration.action
            assert(not pcall(startCalibrationRound,250) and #pending==0 and calibration.action==before)
        '''
        result=subprocess.run([shutil.which('luajit'),'-'],input=script,text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

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
