"""Dedicated Host inventory menu receipts must bind each native/server/observer source."""
import copy
import json
from pathlib import Path
import runpy
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
HERE = ROOT / 'tests/native_queue/contributions/wooden_cart_multiplayer'
ANALYZER = runpy.run_path(str(HERE / 'analyze-inventory-equip.py'))
MATRIX = [1 if i % 5 == 0 else 0 for i in range(16)]
BONES = {name: MATRIX[:] for name in ('Bip01_L_Hand', 'Bip01_R_Hand', 'Bip01_L_Foot', 'Bip01_R_Foot', 'Bip01_Spine')}


def fixture():
    producer = ANALYZER['PRODUCER']
    native_producer = ANALYZER['NATIVE']
    def receipt(role, event, wall, **values):
        return dict(producer=producer, actor=role, event=event, wall=wall, **values)
    spec = dict(id=42, ownerID=7, variant='female-empty', female=True, load='empty',
                cartType='SaucedWheelbarrow.WheelbarrowWood', cargoIDs='', cargoCount=0, cargoWeight=0)
    def endpoint(role, wall, held=True):
        values = dict(spec, phase='settled-tail' if held else 'pre-walk', worldAttached=False, worldCount=0,
                      primaryID=42 if held else -1, secondaryID=42 if held else -1, handSameItem=held,
                      nativeActions=0, luaActions=0, hasPath=False, pantsType='Base.Trousers_JeanBaggy',
                      pantsModel='skinned/clothes/kate_trousers', wornCount=3,
                      inventoryScope='remote-hand-snapshot' if role == 'client2' else 'owner-inventory')
        if role != 'client2': values['inventoryCount'] = 1
        if role == 'server': values.pop('luaActions');values['queueScope'] = 'native-server-only'
        return receipt(role, 'sample', wall, **values)
    rows = {role: [receipt(role, 'start', 100, epoch=1000, id=42, ownerID=7)] for role in ('server', 'client1', 'client2')}
    rows['server'].insert(0, receipt('server', 'spec', 50, **spec))
    rows['client1'].append(receipt('client1', 'queued', 3100, id=42, ownerID=7, actionType='ISCartEquipAction',
                                    sourceType='inventory', menuSource='OnFillInventoryObjectContextMenu', duration=30, maxTime=30,
                                    nativeMaxTime=30, luaMaxTime=30.003, maxTimeScope='native-action', cartId=42, characterExact=True, walkDistance=.5))
    check = endpoint('client1', 3650);check.update(actor='server', event='owner-check', receivedActor='client1', nativeFinished=False,
                                                 nativeForceComplete=False, nativeProgress=1, nativeTime=36, nativeMaxTime=30,
                                                 nativeActionPresent=True, elapsed=550, actionType='ISCartEquipAction', duration=30)
    rows['client1'].append(dict(check, actor='client1', event='terminal-probe', wall=3649))
    observed = endpoint('client2', 3900);observed.update(actor='server', event='observer', receivedActor='client2')
    ack = endpoint('server', 4000);ack.update(event='ack', ok=True, holdMs=200)
    rows['server'].extend([check, observed, ack])
    rows['server'].extend(endpoint('server', wall, False) for wall in [*range(1300, 2701, 100), *range(3100, 3651, 100)])
    rows['server'].append(receipt('server', 'complete', 6100, id=42, ok=True))
    native, poses, cameras = {}, {}, {}
    gate = dict(visualEnabled=True, steeringEnabled=True, supportedHeldCart=True,
                IsPerformingAnAction=False, ToolkitCartMotion=False, PerformingAction='', Weapon='cart')
    for role in ('client1', 'client2'):
        rows[role].append(receipt(role, 'ack', 4010, id=42, ownerID=7, serverWall=4000, holdMs=200))
        rows[role].extend(endpoint(role, wall) for wall in range(4050, 5651, 100))
        rows[role].extend([receipt(role, 'video-start', 500, id=42, ownerID=7, file=role + '.mp4'),
                           receipt(role, 'video-final', 6000, id=42, ownerID=7, file=role + '.mp4', frames=100, seconds=5, state='completed'),
                           receipt(role, 'complete', 6000, id=42, ok=True)])
        def native_row(event, wall, **values):
            return dict(producer=native_producer, actor=role, ownerID=7, female=True, local_=role == 'client1', event=event, wall=wall, **values)
        native[role] = []
        phases = [(range(1300, 2701, 100), False, True), (range(3120, 3621, 100), False, False), (range(4050, 5651, 100), True, False)]
        capture = 0
        for times, held, moving in phases:
            for wall in times:
                capture += 1
                row = native_row('body', wall, captureId=capture, primaryID=42 if held else -1, secondaryID=42 if held else -1,
                                 moving=moving, nativeActions=0, models=['media/models_X/Skinned/Clothes/Kate_Trousers.X'],
                                 bones=copy.deepcopy(BONES), tracks=[dict(name='Walk', time=wall/1000, weight=1)],
                                 actions=[dict(actionId=5, id=42, type='ISCartEquipAction')] if 3100 < wall < 3650 and role == 'client1' else [])
                row['local'] = row.pop('local_');native[role].append(row)
        for wall in (3600, 3650, 3700):
            stage = dict(wall=wall, slotToken=10, cartDataToken=20, id=42, primaryID=42, secondaryID=42,
                         readiness=copy.deepcopy(gate), cart=MATRIX[:], bones=copy.deepcopy(BONES))
            row = native_row('grounding-pair', wall, before=stage, after=copy.deepcopy(stage))
            row['local'] = row.pop('local_');native[role].append(row)
        poses[role], cameras[role] = [], []
        for capture, wall in enumerate(range(4050, 5651, 100), 1):
            poses[role].append(dict(wallTimeMillis=wall, id=7, primary=42, secondary=42, female=True,
                                    local_=role == 'client1', enabled=True, cart=MATRIX[:], bones=copy.deepcopy(BONES),
                                    cartItemId=42, cartItemSource='hands', model='WheelbarrowWood', cartModelCount=1,
                                    captureId=capture, slotToken=10))
            poses[role][-1]['local'] = poses[role][-1].pop('local_')
            cameras[role].extend(dict(captureId=capture, part=part, id=7, slotToken=10, preparedPrimary=42, preparedSecondary=42) for part in ('body', 'cart'))
    for method, stage, wall, progress, finished in [('start', 'enter', 3120, 0, False), ('start', 'exit', 3121, 0, False),
              ('update', 'enter', 3150, .1, False), ('update', 'enter', 3300, .5, False), ('update', 'enter', 3500, .9, False),
              ('update', 'exit', 3600, 1, False), ('perform', 'enter', 3619, 1, False), ('perform', 'exit', 3620, 1, False)]:
        native['client1'].append(dict(producer=native_producer, actor='client1', ownerID=7, female=True, local_=True, event='lifecycle',
                                      wall=wall, actionId=5, method=method, stage=stage, id=42, actionType='ISCartEquipAction',
                                      sourceType='inventory', maxTime=30, threw=False, forceComplete=wall>=3600, forceStop=False, progress=progress, finished=finished,
                                      luaMaxTime=30.003, luaCharacterExact=True,
                                      time=36 if wall>=3600 else progress*30, waitForFinished=wall!=3120, transactionId=3, networkOwnerID=7,
                                      networkActionPresent=not(method=='perform' and stage=='exit'), networkActionExact=not(method=='perform' and stage=='exit'),
                                      networkActionType='ISCartEquipAction', networkDone=wall>=3600 and not(method=='perform' and stage=='exit'), networkRejected=False))
        native['client1'][-1]['local'] = native['client1'][-1].pop('local_')
    return rows, native, poses, cameras


def analyze(data):
    rows, native, poses, cameras = data
    logs = {role: '\n'.join(ANALYZER['MARKER'] + json.dumps(row) for row in values) for role, values in rows.items()}
    return ANALYZER['analyze_data'](logs, native, poses, cameras)


class InventoryEquipEvidenceTests(unittest.TestCase):
    def test_all_sources_join_native_start_perform_without_client_complete(self):
        report = analyze(fixture())
        self.assertTrue(report['evidenceComplete'])
        self.assertFalse(report['animationEquivalencePass'])
        self.assertFalse(report['nativeClientCompleteRequired'])
        self.assertFalse(report['nativeClientFinishedFlagRequired'])
        self.assertEqual(report['nativeTransactionID'], 3)

    def test_wrong_receipt_producer_is_rejected(self):
        data = fixture();data[0]['client2'][0]['producer'] = 'cart-motion-mp'
        with self.assertRaisesRegex(ValueError, 'producer'): analyze(data)

    def test_raw_lua_adjustment_does_not_replace_exact_native_duration(self):
        data = fixture()
        self.assertTrue(analyze(data)['evidenceComplete'])
        queued = next(row for row in data[0]['client1'] if row['event'] == 'queued')
        queued['nativeMaxTime'] = 1
        with self.assertRaisesRegex(ValueError, 'native Walk'): analyze(data)

    def test_missing_adjusted_lua_native_diagnostics_is_rejected(self):
        data = fixture();next(row for row in data[1]['client1'] if row['event'] == 'lifecycle').pop('luaMaxTime')
        with self.assertRaisesRegex(ValueError, 'exact non-rejected'): analyze(data)

    def test_wrong_native_producer_is_rejected(self):
        data = fixture();data[1]['client2'][0]['producer'] = 'sp-native'
        with self.assertRaisesRegex(ValueError, 'source file'): analyze(data)

    def test_authoritative_cart_id_mismatch_is_rejected(self):
        data = fixture();next(row for row in data[0]['server'] if row['event'] == 'ack')['id'] = 43
        with self.assertRaisesRegex(ValueError, 'authoritative'): analyze(data)

    def test_observer_cannot_claim_remote_inventory(self):
        data = fixture();next(row for row in data[0]['server'] if row['event'] == 'observer')['inventoryCount'] = 1
        with self.assertRaisesRegex(ValueError, 'Observer claimed'): analyze(data)

    def test_missing_observer_server_receipt_is_rejected(self):
        data = fixture();data[0]['server'] = [row for row in data[0]['server'] if row['event'] != 'observer']
        with self.assertRaisesRegex(ValueError, 'observer'): analyze(data)

    def test_native_action_id_must_match_rendered_action(self):
        data = fixture()
        for row in data[1]['client1']:
            if row['event'] == 'lifecycle': row['actionId'] = 6
        with self.assertRaisesRegex(ValueError, 'IDs not joined'): analyze(data)

    def test_missing_native_lifecycle_id_is_rejected(self):
        data = fixture();next(row for row in data[1]['client1'] if row['event'] == 'lifecycle').pop('actionId')
        with self.assertRaisesRegex(ValueError, 'lifecycle IDs'): analyze(data)

    def test_start_without_native_perform_is_rejected(self):
        data = fixture();data[1]['client1'] = [row for row in data[1]['client1'] if row.get('method') != 'perform']
        with self.assertRaisesRegex(ValueError, 'boundaries'): analyze(data)

    def test_mp_force_completion_requires_canonical_exact_network_done_receipt(self):
        data = fixture();data[1]['client1'] = [row for row in data[1]['client1']
            if not (row.get('method') == 'update' and row.get('stage') == 'exit')]
        with self.assertRaisesRegex(ValueError, 'server-done'): analyze(data)

    def test_done_from_other_native_transaction_is_rejected(self):
        data = fixture();next(row for row in data[1]['client1'] if row.get('method') == 'update' and row.get('stage') == 'exit')['transactionId'] = 4
        with self.assertRaisesRegex(ValueError, 'owner/transaction'): analyze(data)

    def test_done_without_exact_registered_network_action_is_rejected(self):
        for field, value in (('networkActionExact', False), ('networkOwnerID', 8), ('networkActionType', 'ISCartPickupAction')):
            data = fixture();next(row for row in data[1]['client1'] if row.get('method') == 'update' and row.get('stage') == 'exit')[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError): analyze(data)

    def test_forced_completion_before_server_done_is_rejected(self):
        data = fixture();next(row for row in data[1]['client1'] if row.get('method') == 'update' and row.get('stage') == 'enter')['forceComplete'] = True
        with self.assertRaisesRegex(ValueError, 'before canonical'): analyze(data)

    def test_post_queue_force_flag_clear_does_not_weaken_canonical_boundary(self):
        data = fixture()
        self.assertTrue(analyze(data)['evidenceComplete'])
        canonical = next(row for row in data[1]['client1'] if row.get('method') == 'update' and row.get('stage') == 'exit')
        canonical['forceComplete'] = False
        with self.assertRaisesRegex(ValueError, 'server-done'): analyze(data)

    def test_terminal_probe_must_precede_and_match_server_receipt(self):
        data = fixture();probe = next(row for row in data[0]['client1'] if row['event'] == 'terminal-probe');probe['nativeTime'] = 0
        with self.assertRaisesRegex(ValueError, 'terminal diagnostic'): analyze(data)

    def test_same_slot_grounding_pair_identity_is_required(self):
        data = fixture();next(row for row in data[1]['client2'] if row['event'] == 'grounding-pair')['after']['cartDataToken'] = 21
        with self.assertRaisesRegex(ValueError, 'source slot'): analyze(data)

    def test_native_trouser_model_is_required(self):
        data = fixture();data[1]['client2'][0]['models'] = ['media/models_X/Skinned/FemaleBody.X']
        with self.assertRaisesRegex(ValueError, 'actual trousers'): analyze(data)

    def test_pre_setup_native_random_sex_is_outside_authoritative_epoch(self):
        data = fixture();old = dict(data[1]['client1'][0], wall=100, female=False, models=[])
        data[1]['client1'].insert(0, old)
        self.assertTrue(analyze(data)['evidenceComplete'])

    def test_observer_requires_consumed_native_body_and_cart_draws(self):
        data = fixture();data[3]['client2'] = [row for row in data[3]['client2'] if row['part'] != 'cart']
        with self.assertRaisesRegex(ValueError, 'consumed body/cart'): analyze(data)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT required')
    def test_real_menu_callback_uses_native_duration_after_stock_lua_adjustment(self):
        game = Path.home() / 'Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java'
        native = game / 'media/lua/shared/TimedActions/ISBaseTimedAction.lua'
        if not native.is_file(): self.skipTest('Native ISBaseTimedAction.lua required')
        stock = native.read_text()
        adjustment = 'function ISBaseTimedAction:adjustMaxTime(maxTime)' + stock.split('function ISBaseTimedAction:adjustMaxTime(maxTime)', 1)[1].split('function ISBaseTimedAction:setActionAnim', 1)[0]
        source = (HERE / 'inventory-equip-client.lua').read_text()
        menu = 'local function findPush(context)' + source.split('local function findPush(context)', 1)[1].split('Events.OnServerCommand.Add', 1)[0]
        setup = '''
local P=dofile(%s)
local spec={id=42,ownerID=7,variant='female-empty',female=true,cargoIDs='',cargoCount=0,cargoWeight=0}
local user='client1';local walkX,walkY=0,0;local phase,menuAt,action
local q,receipts={},{}
local function queue() return q end
local function terminal() return #q==0 end
local p={}
local cart={}
function p:isTimedActionInstant() return false end
function p:getPlayerNum() return 0 end
function p:getX() return 1 end
function p:getY() return 1 end
function p:getInventory() return {getItemById=function(_,id) assert(id==42);return cart end} end
function p:getMoodles() return {getMoodleLevel=function() return 0 end} end
function p:getBodyDamage() return {getBodyPart=function() return {getPain=function() return 0 end} end} end
function p:getTimedActionTimeModifier() return 1.0001 end
MoodleType={UNHAPPY=1,DRUNK=2};BodyPartType={Hand_L=0,ForeArm_R=0,ToIndex=function() return 0 end,FromIndex=function(i) return i end}
ISBaseTimedAction={}
local function inspect()
 return {producer=P.producer,actor=user,id=42,ownerID=7,variant='female-empty',female=true,cartType=P.cartType,
  cargoIDs='',cargoCount=0,cargoWeight=0,worldCount=0,worldAttached=false,inventoryScope='owner-inventory',inventoryCount=1,primaryID=-1,secondaryID=-1}
end
local function emit(event,row)
 local copy={event=event};for k,v in pairs(row) do copy[k]=v end;receipts[#receipts+1]=copy
end
local function send(command,args) assert(command=='Begin' and args.id==42) end
local context={options={},hideAndChildren=function(self) self.closed=true end}
ISContextMenu={get=function(num,x,y) assert(num==0);context.closed=false;return context end}
function getText() return 'Push Cart' end
local candidateDuration,nativeTime=30,30
local callbackCount=0
function triggerEvent(name,num,ctx,items)
 assert(name=='OnFillInventoryObjectContextMenu' and num==0 and ctx==context and items[1]==cart)
 ctx.options={{name='Push Cart',target=items,param1=num,param2=cart,onSelect=function(target,player,item)
  assert(context.closed and target==items and player==0 and item==cart);callbackCount=callbackCount+1
  local a={Type='ISCartEquipAction',cartId=42,character=p,sourceType='inventory',maxTime=30,getDuration=function() return candidateDuration end}
  a.maxTime=ISBaseTimedAction.adjustMaxTime(a,a.maxTime)
  a.action={getTime=function() return nativeTime end};q={a}
 end}}
end
''' % json.dumps(str(HERE / 'inventory-equip-protocol.lua'))
        checks = '''
menu(p,3000)
assert(callbackCount==1 and #receipts==2 and receipts[1].event=='queued-probe' and receipts[2].event=='queued')
assert(math.abs(receipts[1].luaMaxTime-30.003)<.000001 and receipts[1].nativeMaxTime==30)
assert(receipts[2].maxTime==30 and receipts[2].maxTimeScope=='native-action' and action.maxTime==receipts[1].luaMaxTime)
q={};receipts={};nativeTime=1
local ok,error=pcall(menu,p,3100);assert(not ok and error:find('actual native equip duration',1,true))
assert(#receipts==1 and receipts[1].event=='queued-probe' and receipts[1].nativeMaxTime==1)
q={};receipts={};nativeTime=30;candidateDuration=1
ok,error=pcall(menu,p,3200);assert(not ok and error:find('getDuration',1,true))
assert(#receipts==1 and receipts[1].duration==1)
'''
        result = subprocess.run([shutil.which('luajit'), '-'], input=setup + adjustment + '\n' + menu + '\n' + checks,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT required')
    def test_actual_lua_protocol_enforces_empty_cargo_and_observer_scope(self):
        script = '''
local P=dofile(%s)
local spec={id=42,ownerID=7,variant='female-empty',female=true,cargoIDs='',cargoCount=0,cargoWeight=0}
local row={producer=P.producer,actor='client2',id=42,ownerID=7,variant='female-empty',female=true,cartType=P.cartType,
 cargoIDs='',cargoCount=0,cargoWeight=0,worldCount=0,worldAttached=false,inventoryScope='remote-hand-snapshot',
 phase='settled-tail',primaryID=42,secondaryID=42,handSameItem=true,nativeActions=0,luaActions=0,hasPath=false,
 pantsType='Base.Trousers_JeanBaggy',wornCount=3,pantsModel='skinned/clothes/kate_trousers'}
assert(P.settled(row,spec,'client2'))
row.inventoryCount=1;assert(not pcall(P.settled,row,spec,'client2'));row.inventoryCount=nil
row.cargoIDs='43:Base.Log:1';assert(not pcall(P.settled,row,spec,'client2'));row.cargoIDs=''
row.ownerID=8;assert(not pcall(P.settled,row,spec,'client2'));row.ownerID=7
row.producer='other';assert(not pcall(P.settled,row,spec,'client2'))
for _,name in ipairs({'female-empty','female-full','male-empty','male-full'}) do assert(P.variant(name).name==name) end
assert(not pcall(P.variant,'all'))
local finished={actionType='ISCartEquipAction',duration=30,nativeFinished=false,nativeForceComplete=true,nativeTime=36,nativeProgress=1,nativeMaxTime=30}
assert(P.nativeTerminal(finished)) -- finished() stays false during the canonical MP waitForFinished lifecycle
finished.nativeProgress=.9;assert(not pcall(P.nativeTerminal,finished));finished.nativeProgress=1
finished.nativeTime=10;assert(not pcall(P.nativeTerminal,finished));finished.nativeTime=36
finished.nativeForceComplete=false;assert(P.nativeTerminal(finished)) -- updateInternal clears this flag after perform and native queue removal
finished.nativeForceComplete=nil;assert(not pcall(P.nativeTerminal,finished));finished.nativeForceComplete=false
finished.nativeMaxTime=1;assert(not pcall(P.nativeTerminal,finished))
''' % json.dumps(str(HERE / 'inventory-equip-protocol.lua'))
        result = subprocess.run([shutil.which('luajit'), '-'], input=script, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__': unittest.main()
