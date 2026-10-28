"""Extended cart staging and rejection boundaries; no game or visual acceptance."""
import copy
import json
import math
import unittest
from unittest.mock import patch

from tests import test_queue_cart_adapters as fixtures
from tests import test_cart_sp_visual_extended as sp_fixture

carts = fixtures.carts


class ExtendedCartAdapterTests(unittest.TestCase):
    def adapter(self):
        case = fixtures.CartAdapterTests()
        case.setUp()
        self.addCleanup(case.doCleanups)
        return case

    def test_sp_opt_in_is_bounded_and_staged_without_extra_capture(self):
        case = self.adapter()
        case.selection['cases'] = ['controls']
        case.options.update(cart_controls_extended=True, cart_scenes=['shopping-cart'])
        case.options.pop('mesh_fbx')
        case.stage()
        source = case.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']
        self.assertIn('["controlsExtended"]=true', fixtures.Path(source).read_text())
        for value in ('true', 1):
            case.options['cart_controls_extended'] = value
            with self.assertRaises(ValueError): carts.validate(case.selection)
        case.options['cart_controls_extended'] = True
        for scenes in ([], ['wooden-wheelbarrow'], ['shopping-cart', 'metal-wheelbarrow']):
            case.options['cart_scenes'] = scenes
            with self.assertRaises(ValueError): carts.validate(case.selection)

    def test_host_opt_in_requires_exact_topology_and_keeps_module_out_of_old_banks(self):
        case = self.adapter()
        case.selection.update(suite=carts.MP, cases=['owner_observer_motion'], kind='mp', languages=['EN','RU'])
        case.role('server'); case.role('client2')
        case.options.update(mp_host=True,cart_variant='shopping-cart',cart_fast_motion=True,cart_actions=True,
                            cart_visual_extended=True)
        case.stage()
        for role in ('server','client1','client2'):
            path = case.output/role/'mods/ActionQueueTest/42/media/lua/shared/CartMPVisualExtended.lua'
            self.assertTrue(path.is_file())
        for key,value in [('cart_visual_extended','true'), ('mp_host',False), ('cart_variant','wooden-wheelbarrow'),
                          ('cart_fast_motion',False), ('cart_actions',False), ('cart_timeline',True),
                          ('cart_lease_menu',True), ('cart_injury',True), ('cart_time_alignment',True)]:
            with self.subTest(key=key):
                original = dict(case.options)
                case.options[key] = value
                with self.assertRaises(ValueError): carts.validate(case.selection)
                case.options.clear(); case.options.update(original)
        old = self.adapter()
        old.selection.update(suite=carts.MP, cases=['owner_observer_motion'], kind='mp', languages=['EN','RU'])
        old.role('server'); old.role('client2'); old.options.update(mp_host=True)
        old.stage()
        self.assertFalse((old.output/'client1/mods/ActionQueueTest/42/media/lua/shared/CartMPVisualExtended.lua').exists())

    @staticmethod
    def movement():
        events=[(kind,dict(row)) for kind,row in fixtures.CartAdapterTests.control_log() if row['case']=='shopping-cart']
        last=next(row for kind,row in reversed(events) if kind=='SAMPLE')
        x,y,heading,frame=(last[key] for key in ('x','y','heading','frame'))
        for phase,drive,gait,duration in carts.CONTROL_EXTENDED_PHASES:
            if phase in carts.CONTROL_EXTENDED_POSES: x=y=heading=0
            turn=-.3 if phase=='correction-left' else .3 if phase=='correction-right' else 0
            for index in range(11):
                frame+=1
                if index:
                    yaw=turn/10;distance=0 if drive==0 else .06
                    x+=distance*math.cos(heading+yaw/2);y+=distance*math.sin(heading+yaw/2);heading+=yaw
                events.append(('SAMPLE',dict(case='shopping-cart',phase=phase,sample=index,elapsed=duration*index/10,
                    frame=frame,x=x,y=y,heading=heading,acceptedHeading=heading)))
            events.append(('PHASE',dict(case='shopping-cart',kind=carts.VARIANTS['shopping-cart'],phase=phase,
                id=42,cargoID=99,cargoWeight=1,primaryID=42,secondaryID=42,inventoryCount=1,worldCount=0,
                luaActions=0,nativeActions=0,hasPath=False,drive=drive,gait=gait,gaitSeen=True,elapsed=duration,samples=11)))
        return events

    def test_short_correction_requires_measured_small_yaw_and_continuous_release(self):
        events=self.movement()
        with patch.object(carts,'_controls_action_coverage',return_value={'nativeActionsVerified':True}):
            self.assertTrue(carts._controls_coverage(fixtures.CartAdapterTests.controls_text(events),['shopping-cart'],True)['briefSteeringVerified'])
            for fault in ('zero-yaw','broad-yaw','reset-release','missing-phase','coarse-sampling'):
                with self.subTest(fault=fault):
                    bad=copy.deepcopy(events)
                    for kind,row in bad:
                        if row['phase']=='correction-left' and kind=='SAMPLE':
                            if fault=='zero-yaw': row['heading']=row['acceptedHeading']=0
                            if fault=='broad-yaw': row['heading']*=10;row['acceptedHeading']*=10
                            if fault=='coarse-sampling' and row['sample']==1:row['elapsed']=120
                        if fault=='reset-release' and row['phase']=='correction-left-release' and kind=='SAMPLE':row['x']+=2
                    if fault=='missing-phase':bad=[(k,r) for k,r in bad if r['phase']!='correction-left']
                    with self.assertRaises(ValueError):carts._controls_coverage(fixtures.CartAdapterTests.controls_text(bad),['shopping-cart'],True)
            with self.assertRaises(ValueError):carts._controls_coverage(fixtures.CartAdapterTests.controls_text(events),['shopping-cart'])

    @unittest.skipUnless(sp_fixture.LuaRuntime,'Requires Lupa Lua51')
    def test_actual_sp_fixture_action_stream_is_accepted_and_mutations_are_rejected(self):
        producer=sp_fixture.CartSPVisualExtendedTests()
        lua=producer.boot(setup='approach=true');producer.run_done(lua)
        lines=producer.lines(lua)
        motion=producer.rows(lua,'PHASE','CART_CONTROLS')
        text='\n'.join(lines)
        result=carts._controls_action_coverage(text,motion)
        self.assertEqual([r['phase'] for r in result['phases']],['drop','pickup'])
        self.assertFalse(result['animationEquivalencePass'])
        for fault in ('missing-queued','missing-native','no-progress','fixed-progress','wrong-native-duration',
                      'stock-action-type','wrong-cart','wrong-cargo','tail-active','short-tail','duplicate-sample','truncated-video'):
            with self.subTest(fault=fault):
                bad=[];duplicated=False
                for line in lines:
                    if '[CART_CONTROLS_ACTION] ' in line:
                        prefix,event,raw=line.split(' ',2);row=json.loads(raw)
                        if fault=='missing-queued' and event=='QUEUED':continue
                        if fault=='missing-native':row['nativeStarted']=False
                        if fault=='no-progress':row['progress']=0
                        if fault=='fixed-progress' and 0<row['progress']<1:row['progress']=.5
                        if fault=='wrong-native-duration' and row['nativeStarted']:row['nativeMaxTime']+=1
                        if fault=='stock-action-type':
                            row['actionType']={'ToolkitWoodCartSetdown':'ISUnequipAction','ToolkitWoodCartPickup':'ISCartPickupAction'}.get(row['actionType'],row['actionType'])
                            row['actionTypeSeen']={'ToolkitWoodCartSetdown':'ISUnequipAction','ToolkitWoodCartPickup':'ISCartPickupAction'}.get(row.get('actionTypeSeen'),row.get('actionTypeSeen'))
                        if fault=='wrong-cart':row['id']=123
                        if fault=='wrong-cargo':row['cargoID']=123
                        if fault=='tail-active' and event=='SAMPLE' and row['settledElapsed']>100:row['luaActions']=1
                        if fault=='short-tail' and event=='COMPLETE':row['settledElapsed']=699
                        line=f'{prefix} {event} '+json.dumps(row)
                        if fault=='duplicate-sample' and event=='SAMPLE' and not duplicated:bad.append(line);duplicated=True
                    if fault=='truncated-video' and '[WOOD_BANK] COMPLETE ' in line:line=line.rsplit('seconds=',1)[0]+'seconds=1'
                    bad.append(line)
                with self.assertRaises(ValueError):carts._controls_action_coverage('\n'.join(bad),motion)


if __name__=='__main__': unittest.main()
