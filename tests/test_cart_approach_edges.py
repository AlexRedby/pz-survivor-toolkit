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
            # 60 native .005 steps reach a real boundary; 45 further requests are rejected.
            for step in range(106):
                lines.append('[CART_APPROACH_CALIBRATION] '+json.dumps(dict(case=name,start=start,
                    wall=start-2500+step*17,x=.03+max(0,60-step)*.005,y=.5,
                    dx=0 if step==105 else -.005,dy=0)))
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

    def test_blocked_requires_real_native_calibration_before_public_approach(self):
        text,lifecycle=fixture()
        for mode in ('missing','no-travel','no-rejection','short-rejection','wrong-primitive','drift','wrong-goal'):
            lines=[]
            for line in text.splitlines():
                if line.startswith('[CART_APPROACH_CALIBRATION] '):
                    if mode=='missing': continue
                    row=json.loads(line.split('] ',1)[1])
                    if mode=='no-travel': row['x']=.03
                    if mode=='no-rejection': row['x']=.03+(160000-row['wall'])*.00001
                    if mode=='short-rejection': row['wall']=160000+(row['wall']-160000)//2
                    if mode=='wrong-primitive' and row['dx']: row['dx']=-.02
                    if mode=='drift': row['x']+=.02
                    line='[CART_APPROACH_CALIBRATION] '+json.dumps(row)
                lines.append(line)
            values=('\n'.join(lines),lifecycle)
            if mode=='wrong-goal':
                values=change_rows(values,lambda row: row.update(goalX=.02) if row['case']=='precise-blocked' else None)
            with self.subTest(mode=mode),self.assertRaisesRegex(AssertionError,'calibrat|precise requests|native precise'):
                analyzer.analyze(*values)

    @unittest.skipUnless(shutil.which('luajit'),'Requires LuaJIT')
    def test_calibration_uses_resolved_native_steps_and_cannot_accept_ignored_movement(self):
        source=(SOURCE/'scenario-approach.lua').read_text()
        body=source.split("local WallCalibration=",1)[1].split('local function removeWorld',1)[0]
        script=r'''
            clock=0;boundary=0.3;ignore=false;nextX=1
            p={x=1,getX=function(self) return self.x end,getY=function() return .5 end,
               getVehicle=function() return nil end,moveUnmodded=function(self,dx,dy)
                   assert(dx==-.005 and dy==0);nextX=self.x+dx
               end}
            function getTimestampMs() return clock end
            ISBaseTimedAction={derive=function(_,name) return {Type=name} end,
                new=function(self,character) local o={character=character};return setmetatable(o,{__index=self}) end}
        '''+'\nlocal WallCalibration='+body+r'''
            function WallCalibration:forceStop() self.stopped=true end
            local calibration=WallCalibration:new()
            for i=1,400 do
                clock=i*17;calibration:update()
                if calibration.done then break end
                p.x=math.max(boundary,nextX) -- test stand-in resolves collision AFTER action update
            end
            assert(calibration.done and calibration.stopped and calibration.blocked>=45)
            assert(math.abs(p.x-boundary)<.00001 and calibration.startX-p.x>.6)
            assert(calibration.rows[#calibration.rows].dx==0)
            p.x=1;clock=0;local ignored=WallCalibration:new()
            for i=1,400 do clock=i*17;ignored:update() end
            assert(not ignored.done and not ignored.stopped) -- no native travel is never a calibrated wall
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
