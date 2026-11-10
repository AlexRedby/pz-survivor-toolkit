import copy
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import adapters
from queue_checks.adapters import wring_clothing as a
from tests.test_queue_tv_controls_adapter import placement_proof as tile_placement_proof

PROJECT = Path(__file__).resolve().parents[1]


def placement_proof(target, mode='local'):
    proof = tile_placement_proof(target, mode)
    proof.update(centered=True, centers=1 if mode == 'local' else 0)
    proof['actual'].update(x=target['x'] + .5, y=target['y'] + .5)
    return proof


def worn_alias_fixture():
    from lupa.lua51 import LuaRuntime
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().fixture = str(PROJECT / 'tests/native_queue/wring-clothing/shared/QueueWringClothing.lua')
    lua.execute(r'''
package.loaded.QueueEnergyPlacement={atCentered=function()return true end}
function instanceof(value,kind)return value.class==kind end
function getClassSimpleName(value)return value.class end
F=dofile(fixture)
local function location(name)return setmetatable({class='ItemBodyLocation'},{__tostring=function()return 'base:'..name end})end
local shoes,socks=location('shoes'),location('socks')
ItemBodyLocation=setmetatable({SHOES=shoes,SOCKS=socks},{__index=function(_,key)return key end})
root={};local values={};local slot
local function item(id,kind,body)
 return{class='Clothing',getID=function()return id end,getFullType=function()return kind end,
 getBodyLocation=function()return body end,getContainer=function()return root end,getWetness=function()return 99 end,
 getActualWeight=function()return .1 end,hasTag=function()return false end,getCategory=function()return 'Clothing'end,
 IsClothing=function()return true end,setJobType=function()end,setJobDelta=function()end,getName=function()return kind end}
end
function root:getItems()return{size=function()return #values end,get=function(_,i)return values[i+1]end}end
function root:getItemById(id)for _,value in ipairs(values)do if value:getID()==id then return value end end end
player={getInventory=function()return root end,getWornItem=function(_,body)return body==shoes and slot or nil end,
 setWornItem=function(_,body,value)assert(body==shoes);slot=value end,
 getWornItems=function()return{contains=function(_,value)return value==slot end,
 getItemById=function(_,id)return slot and slot:getID()==id and slot or nil end}end,
 reportEvent=function()end,playSound=function()return 0 end,
 getHumanVisual=function()return{getHairModel=function()return{contains=function()return false end}end}end}
ids={case='worn',nativeWearSetup=true,origin={},source={kind='worn',bag=false,world=false},items={}}
for i,name in ipairs(F.names)do
 local shoe=name=='target'or name=='tail';local body=shoe and shoes or socks
 local kind=shoe and 'Base.Shoes_FlipFlop'or 'Base.Socks_Ankle'
 local value=item(i,kind,body);values[i]=value
 local spec=F.nativeWetnessContract(value);spec.id=i;spec.type=kind;ids.items[name]=spec
end
canonical=values[2];proxy=item(2,'Base.Shoes_FlipFlop',shoes);slot=proxy
assert(F.resolve(player,ids)==nil,'same-ID worn alias was accepted as canonical')
state=assert(F.resolve(player,ids,true),'declared provisional native wear input could not resolve')
assert(F.wearBaseline(state)==nil,'same-ID worn alias became authority baseline')
local diagnostic=F.preparedDiagnostic(player,ids)
assert(diagnostic.items.target.present and diagnostic.items.target.exactOwner and diagnostic.items.target.wetness==99)
assert(diagnostic.items.target.wornId==2 and diagnostic.items.target.slotId==2 and not diagnostic.items.target.wornSame)
assert(not diagnostic.items.target.canonicalWorn and not diagnostic.items.target.slotSame,'prepared diagnostic hid worn alias')
''')
    return lua


def evidence(kind='mp', mode='toolkit', case='root'):
    origin = dict(x=11, y=20, z=0)
    source = dict(kind=case, bag=20 if case == 'worn-bag' else False,
                  world=dict(x=11, y=19, z=0, index=1) if case == 'world' else False)
    specs = {}
    for index, name in enumerate(a.NAMES):
        shoes = name == 'tail' or name == 'target' and case in ('worn', 'world')
        specs[name] = dict(id=10 + index, type='Base.Shoes_FlipFlop' if shoes else 'Base.Socks_Ankle',
                           cap=10, nativeShoe=False, bodyLocationClass='ItemBodyLocation',
                           bodyLocation='base:shoes' if shoes else 'base:socks', initial=100, weight=.1)
    ids = dict(case=case, mode=mode, source=source, origin=origin, items=specs,
               placementProof=placement_proof(origin, 'replica' if kind == 'mp' else 'local'))
    native_wear = kind == 'mp' and case in ('worn', 'worn-bag')
    if native_wear: ids['nativeWearSetup'] = True
    def snapshot(final):
        return dict(case=case, source=copy.deepcopy(source), items={
            name: dict(id=spec['id'], type=spec['type'], wetness=99 if not final or name == 'cancelled' else spec['cap'],
                       native={key: spec[key] for key in ('bodyLocation', 'bodyLocationClass', 'nativeShoe', 'cap')},
                       weight=.1, worn=not final and case == 'worn' and name == 'target', counts=a._counts(case, name, final))
            for name, spec in specs.items()})
    editing = mode == 'toolkit' and case == 'root'
    plan = [('front', 'ISWringClothing')]
    if editing: plan += [('cancelled', 'ISWringClothing')]
    if case == 'worn': plan += [('target', 'ISUnequipAction')]
    if case in ('worn-bag', 'world'): plan += [('target', 'ISInventoryTransferAction')]
    plan += [('target', 'ISWringClothing')]
    if editing: plan += [('repeat', 'ISWringClothing')]
    plan += [('tail', 'ISWringClothing')]
    commands = []
    for index, (name, type_) in enumerate(plan):
        cancelled = editing and name in ('cancelled', 'repeat')
        command = dict(name=name, type=type_, producer=a.PRODUCER, item=specs['target' if name == 'repeat' else name]['id'],
                       duration=495 if type_ == 'ISWringClothing' else -1 if type_ == 'ISInventoryTransferAction' and kind == 'mp' else 50,
                       started=not cancelled, progress=not cancelled)
        if cancelled: command['cancelled'] = True
        else: command['startedAt'] = 100 + index
        if type_ == 'ISWringClothing': command.update(constructorWetness=99, callbacksUntouched=True)
        commands.append(command)
    final = snapshot(True)
    row = dict(ids=copy.deepcopy(ids), clientPlacement=placement_proof(origin), input=snapshot(False),
               client=copy.deepcopy(final), server=copy.deepcopy(final), status='passed', queueIdle=True,
               settleMilliseconds=1000, commands=commands,
               edit=dict(cancelled=editing, reordered=editing, repeatDenied=editing, untouched=True))
    if native_wear:
        row.update(authorityBaseline=snapshot(False), wearSetup=dict(type='ISWearClothing', producer='native ISWearClothing constructor',
            item=specs['target']['id'] if case == 'worn' else source['bag'], duration=50, started=True, progress=True, startedAt=10))
    return row, dict(kind=kind, mode=mode), ids, final


class WringClothingEvidenceTests(unittest.TestCase):
    def test_selected_pack_and_grouped_sp_host_modes(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                selection = dict(suite='wring-clothing', cases=list(a.CASES), kind=kind, mode=mode, languages=['EN'],
                                 clients=1, mods=a.MODS, options={'mp_host': True} if kind == 'mp' else {})
                a.validate(selection)
                self.assertIs(adapters.get('wring-clothing'), a)
                for case in a.CASES:
                    self.assertEqual([], a.check_case(*evidence(kind, mode, case)))
        selection['options'] = {}
        with self.assertRaises(ValueError): a.validate(selection)
        selection['options'] = {'mp_host': True, 'world_template': 'old-save'}
        with self.assertRaises(ValueError): a.validate(selection)

    def test_centered_placement_rejects_tile_edges_and_unproven_centering(self):
        for kind in ('sp', 'mp'):
            result = evidence(kind=kind)
            result[0]['clientPlacement']['actual']['x'] = result[2]['origin']['x']
            self.assertTrue(a.check_case(*result))
            result = evidence(kind=kind)
            result[2]['placementProof']['actual']['y'] = result[2]['origin']['y']
            result[0]['ids'] = copy.deepcopy(result[2])
            self.assertTrue(a.check_case(*result))
            result = evidence(kind=kind)
            del result[0]['clientPlacement']['centered']
            self.assertTrue(a.check_case(*result))
            result = evidence(kind=kind)
            result[0]['clientPlacement']['centers'] = 0
            self.assertTrue(a.check_case(*result))

    def test_drying_bounds_preserve_observed_native_caps(self):
        for case in a.CASES:
            result = evidence(case=case)
            for phase in ('client', 'server'):
                for name in ('front', 'target', 'tail'):
                    result[0][phase]['items'][name]['wetness'] -= 1
            result[3].update(copy.deepcopy(result[0]['server']))
            self.assertEqual([], a.check_case(*result))
        for case, name, wetness in [('root', 'target', 60), ('world', 'target', 60), ('root', 'cancelled', 10)]:
            result = evidence(case=case); result[0]['client']['items'][name]['wetness'] = wetness
            self.assertTrue(a.check_case(*result))

    def test_exact_input_source_debit_identity_and_equipment(self):
        for case in a.CASES:
            for phase in ('input', 'client', 'server'):
                result = evidence(case=case); result[0][phase]['items']['target']['counts']['source'] += 1
                self.assertTrue(a.check_case(*result))
                result = evidence(case=case); result[0][phase]['items']['target']['id'] += 1
                self.assertTrue(a.check_case(*result))
        result = evidence(case='worn'); result[0]['client']['items']['target']['worn'] = True
        self.assertTrue(a.check_case(*result))
        result = evidence(case='world'); result[2]['source']['world']['x'] += 1; result[0]['ids'] = copy.deepcopy(result[2])
        self.assertTrue(a.check_case(*result))
        for case in ('worn-bag', 'world'):
            result = evidence(case=case); result[0]['client']['items']['target']['counts']['root'] = 1
            self.assertTrue(a.check_case(*result))

    def test_native_preludes_durations_and_pending_only_edits(self):
        for case in ('worn', 'worn-bag', 'world'):
            result = evidence(case=case); result[0]['commands'].pop(1)
            self.assertTrue(a.check_case(*result))
        for change in ('callbacks', 'duration', 'progress', 'cancelled', 'dependency', 'untouched', 'tail'):
            result = evidence(); row = result[0]
            if change == 'callbacks': row['commands'][0]['callbacksUntouched'] = False
            if change == 'duration': row['commands'][0]['duration'] = 1
            if change == 'progress': row['commands'][0]['progress'] = False
            if change == 'cancelled': row['commands'][1]['started'] = True
            if change == 'dependency': row['edit']['repeatDenied'] = False
            if change == 'untouched': row['edit']['untouched'] = False
            if change == 'tail': row['commands'].pop()
            self.assertTrue(a.check_case(*result), change)

    def test_transfer_wait_sentinel_is_specific_to_native_mp_wrapper(self):
        for case in ('worn-bag', 'world'):
            for mode in ('native', 'toolkit'):
                result = evidence(mode=mode, case=case)
                self.assertEqual([], a.check_case(*result))
                for duration in (0, -2, 50, False):
                    result = evidence(mode=mode, case=case); result[0]['commands'][1]['duration'] = duration
                    self.assertTrue(a.check_case(*result))
                result = evidence(kind='sp', mode=mode, case=case); result[0]['commands'][1]['duration'] = -1
                self.assertTrue(a.check_case(*result))
        for case, index in (('root', 0), ('worn', 1)):
            result = evidence(case=case); result[0]['commands'][index]['duration'] = -1
            self.assertTrue(a.check_case(*result), 'wring/unequip must not inherit transfer sentinel')

    def test_captured_v6_host_command_rows_preserve_transfer_constructor_sentinel(self):
        # Emitted v6 Host receipts; IDs/clocks are normalized by evidence().
        captured = [('front', 'ISWringClothing', 500), ('target', 'ISInventoryTransferAction', -1),
                    ('target', 'ISWringClothing', 500), ('tail', 'ISWringClothing', 500)]
        for case in ('worn-bag', 'world'):
            result = evidence(mode='native', case=case)
            for command, (name, kind, duration) in zip(result[0]['commands'], captured):
                self.assertEqual((name, kind), (command['name'], command['type']))
                command['duration'] = duration
                if kind == 'ISWringClothing': command['constructorWetness'] = 100
            self.assertEqual([], a.check_case(*result))

    def test_authority_receipts_require_all_grouped_cases(self):
        selection = dict(kind='mp', mode='toolkit'); cases = list(a.CASES)
        client = ['[QUEUE_CHECK] ' + json.dumps(dict(suite='wring-clothing', event='setup', cases=cases, queueEnabled=True, nativeDurations=True, adapterInstalled=True))]
        server = []
        for case in cases:
            row, _, ids, verified = evidence(case=case)
            row.update(suite='wring-clothing', event='case', id=case, actor='client1', kind='mp', mode='toolkit')
            client += [a.PREFIX + 'CLIENT_PLACEMENT ' + json.dumps(dict(case=case, proof=row['clientPlacement'])), '[QUEUE_CHECK] ' + json.dumps(row)]
            server.append(a.PREFIX + 'PREPARED ' + json.dumps(ids))
            if ids.get('nativeWearSetup'): server.append(a.PREFIX + 'WEAR_BASELINE ' + json.dumps(row['authorityBaseline']))
            server.append(a.PREFIX + 'VERIFIED ' + json.dumps(verified))
        client += ['[QUEUE_CHECK] ' + json.dumps(dict(suite='wring-clothing', event='complete', cases=cases, performed=len(cases), failed=0, skipped=0)),
                   a.PREFIX + 'COMPLETE ' + json.dumps(dict(cases=cases))]
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); (root / 'client1-launch.log').write_text('\n'.join(client)); (root / 'server-launch.log').write_text('\n'.join(server))
            self.assertEqual([], a.verify(root, selection, {})['issues'])
            false_setup = client.copy(); false_setup[0] = false_setup[0].replace('"adapterInstalled": true', '"adapterInstalled": false')
            (root / 'client1-launch.log').write_text('\n'.join(false_setup))
            self.assertTrue(a.verify(root, selection, {})['issues'])

            (root / 'client1-launch.log').write_text('\n'.join(client))
            (root / 'server-launch.log').write_text('\n'.join(server[:-1]))
            self.assertTrue(a.verify(root, selection, {})['issues'])

    def test_host_native_wear_setup_requires_exact_input_and_authority_baseline(self):
        for case in ('worn', 'worn-bag'):
            result = evidence(case=case)
            self.assertEqual([], a.check_case(*result, copy.deepcopy(result[0]['authorityBaseline'])))
            result = evidence(case=case); result[0]['wearSetup']['duration'] = 1
            self.assertTrue(a.check_case(*result))
            result = evidence(case=case); result[0]['wearSetup']['progress'] = False
            self.assertTrue(a.check_case(*result))
            result = evidence(case=case); result[0]['wearSetup']['item'] += 100
            self.assertTrue(a.check_case(*result))
            result = evidence(case=case); result[0]['authorityBaseline']['items']['target']['wetness'] = 10
            self.assertTrue(a.check_case(*result))
            result = evidence(case=case); baseline = copy.deepcopy(result[0]['authorityBaseline']); baseline['items']['target']['counts']['source'] = 0
            self.assertTrue(a.check_case(*result, baseline))
            result = evidence(case=case); del result[0]['authorityBaseline']
            self.assertTrue(a.check_case(*result))


    def test_prepared_wait_diagnoses_same_id_alias_without_accepting_it(self):
        lua = worn_alias_fixture()
        lua.execute("player:setWornItem(canonical:getBodyLocation(),canonical);assert(F.resolve(player,ids));assert(F.wearBaseline(state))")

    def test_host_bag_provisional_resolution_never_weakens_final_worn_identity(self):
        lua = worn_alias_fixture()
        lua.execute(r'''
local old=root:getItems();local front,tail,cancelled=old:get(0),old:get(2),old:get(3)
local function list(values)return{size=function()return #values end,get=function(_,i)return values[i+1]end}end
local source={getItems=function()return list({canonical})end}
local bag={class='InventoryContainer',getID=function()return 10 end,getFullType=function()return 'Base.Bag_Military'end,
 getContainer=function()return root end,getItemContainer=function()return source end,canBeEquipped=function()return 'Back'end}
local worn
function root:getItems()return list({front,tail,cancelled,bag})end
function root:getItemById(id)if id==10 then return bag end end
canonical.getContainer=function()return source end
player.getWornItems=function()return{contains=function(_,value)return value==worn end,
 getItemById=function(_,id)return worn and worn:getID()==id and worn or nil end}end
player.getWornItem=function(_,slot)return slot=='Back'and worn or nil end
ids.case='worn-bag';ids.source={kind='worn-bag',bag=10,world=false}
assert(not F.resolve(player,ids),'unworn bag became ready baseline')
local s=assert(F.resolve(player,ids,true));assert(not F.wearBaseline(s))
worn={getID=function()return 10 end};assert(not F.resolve(player,ids),'same-ID bag alias accepted')
local diagnostic=F.preparedDiagnostic(player,ids)
assert(diagnostic.bag.slotId==10 and not diagnostic.bag.slotSame and not diagnostic.bag.canonicalWorn)
worn=bag;assert(F.resolve(player,ids));assert(F.wearBaseline(s))
worn=nil;assert(not F.resolve(player,ids)and not F.wearBaseline(s))
assert(not pcall(F.verify,s),'nativeWearSetup permanently relaxed final canonical worn bag identity')
''')

    def test_native_wear_source_rebinds_and_completes_exact_root_item(self):
        game = os.environ.get('PZ_GAME')
        if not game: self.skipTest('PZ_GAME required for installed native wear source regression')
        native = Path(game) / 'media/lua/shared/TimedActions/ISWearClothing.lua'
        self.assertEqual(a.NATIVE_CRC['media/lua/shared/TimedActions/ISWearClothing.lua'], zlib.crc32(native.read_bytes()))
        lua = worn_alias_fixture(); lua.globals().nativeWearSource = str(native)
        lua.execute(r'''
require=function()end
ISBaseTimedAction={derive=function(_,name)local cls={Type=name};cls.__index=cls;return cls end}
ItemTag={WEARABLE='wearable',REPLACE_PRIMARY='primary'}
function isClient()return true end
function getText(value)return value end
dofile(nativeWearSource)
local action=setmetatable({item=proxy,character=player,setActionAnim=function()end,setAnimVariable=function()end,
 forceComplete=function()error('same-ID proxy must not force-complete canonical wear')end},ISWearClothing)
action:start();assert(action.item==canonical,'native wear start did not rebind exact root item')
assert(action:complete(),'native wear complete failed')
assert(player:getWornItem(canonical:getBodyLocation())==canonical and F.resolve(player,ids))
assert(F.wearBaseline(state),'native canonical wear did not satisfy strict baseline')
''')

    def test_native_source_audit_fails_before_launch_on_drift(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); data = b'native source fixture'
            paths = {name: zlib.crc32(data) for name in a.NATIVE_CRC}
            for relative in paths:
                path = root / relative; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
            with patch.object(a, 'NATIVE_CRC', paths):
                self.assertEqual(paths, a.audit_native(root))
                (root / next(iter(paths))).write_bytes(b'changed native method')
                with self.assertRaises(ValueError): a.audit_native(root)

    def test_report_verifier_has_explicit_separate_source_roles(self):
        from queue_checks import provenance
        selection = {'suite': 'wring-clothing'}
        declared = {path.resolve() for path in provenance.verifier_sources(PROJECT, selection)}
        verifier = Path(a.__file__).with_name('wring_clothing_verifier.py').resolve()
        self.assertIn(verifier, declared)
        self.assertIn(Path(__file__).resolve(), declared)
        inputs = {path.resolve() for path in a.sources(PROJECT, selection)} | declared | {Path(a.__file__).resolve()}
        manifest = {str(path): provenance.digest(path) for path in inputs}
        roles = provenance.source_roles(PROJECT, selection, manifest)
        self.assertEqual({str(path) for path in declared}, set(roles['verifier']))
        self.assertIn(str(Path(a.__file__).resolve()), roles['runtime'])
        self.assertIn(str(PROJECT / 'tests/native_queue/wring-clothing/client/ZZWringClothing.lua'), roles['runtime'])
        self.assertNotIn(str(verifier), roles['runtime'])
        sentinel = object()
        with patch('queue_checks.provenance.run_verifier', return_value=sentinel) as run:
            self.assertIs(sentinel, a.verify(Path('unused-evidence'), selection, {}))
        self.assertEqual(verifier, Path(run.call_args.args[0]).resolve())
        self.assertEqual('queue_checks.adapters', run.call_args.args[1])

    def test_fixture_native_callbacks_and_dry_baseline(self):
        root = PROJECT / 'tests/native_queue/wring-clothing'
        shared = (root / 'shared/QueueWringClothing.lua').read_text()
        client = (root / 'client/ZZWringClothing.lua').read_text()
        self.assertIn('precipitation:setEnableAdmin(true)', shared)
        self.assertEqual(shared.count('item:setWetness('), 1)
        self.assertIn('item:setWetness(100)', shared)
        self.assertIn("nativeShoe=location=='Shoes'", shared)
        self.assertIn('player:getInventoryWeight()<player:getMaxWeight()', shared)
        self.assertIn('if item:getContainer()==root then sendAddItemToContainer(root,item)end', shared)
        self.assertIn('pcall(ISInventoryPaneContextMenu.onWringClothing', client)
        for name in ('complete', 'perform', 'getDuration', 'isValid'):
            self.assertNotIn('ISWringClothing.' + name + '=', client)
        self.assertNotRegex(client, r'\.maxTime\s*=(?!=)')
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        compile_ = lua.eval('function(source) local f,e=loadstring(source); assert(f,e) end')
        for file in root.rglob('*.lua'):
            compile_(file.read_text())

    def test_unique_canonical_clothing_handle_replacement_preserves_identity(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        source = PROJECT / 'tests/native_queue/wring-clothing/shared/QueueWringClothing.lua'
        script = r'''
package.loaded.QueueEnergyPlacement={}
function instanceof(value,kind)return value.class==kind end
function getClassSimpleName(value)return value.class end
local F=dofile(arg[1])
local values={};local root={}
local socks=setmetatable({class='ItemBodyLocation'},{__tostring=function()return 'base:socks'end})
local function item(id,kind)
 return {class='Clothing',getID=function()return id end,getFullType=function()return kind end,
 getWetness=function()return 99 end,getActualWeight=function()return .1 end,getContainer=function()return root end,
 getBodyLocation=function()return socks end}
end
function root:getItems()return{size=function()return #values end,get=function(_,i)return values[i+1]end}end
local player={getInventory=function()return root end,getWornItems=function()return{contains=function()return false end}end}
local s={player=player,source=root,items={},ids={case='root',source={kind='root',bag=false,world=false},items={}}}
for i,name in ipairs(F.names)do
 s.ids.items[name]={id=i,type='Base.Socks_Ankle',bodyLocation='base:socks',bodyLocationClass='ItemBodyLocation',nativeShoe=false,cap=10}
 s.items[name]=item(i,'Base.Socks_Ankle');values[i]=item(i,'Base.Socks_Ankle')
end
local snapshot=F.snapshot(s)
for i,name in ipairs(F.names)do
 assert(s.items[name]==values[i]and snapshot.items[name].counts.root==1 and snapshot.items[name].counts.source==1)
end
values[5]=item(2,'Base.Socks_Ankle');assert(not pcall(F.snapshot,s),'duplicate ID accepted');values[5]=nil
values[2]=item(2,'Base.Shoes_FlipFlop');assert(not pcall(F.snapshot,s),'wrong-type replacement accepted')
values[2]=item(200,'Base.Socks_Ankle');assert(not pcall(F.snapshot,s),'unowned replacement accepted')
'''
        lua.globals().arg = lua.table_from([str(source)])
        lua.execute(script)

    def test_enum_valued_shoe_location_preserves_native_string_predicate(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().fixture = str(PROJECT / 'tests/native_queue/wring-clothing/shared/QueueWringClothing.lua')
        lua.execute(r'''
package.loaded.QueueEnergyPlacement={}
function getClassSimpleName(value)return type(value)=='string'and 'String'or value.class end
local F=dofile(fixture)
local location=setmetatable({class='ItemBodyLocation'},{__tostring=function()return 'base:shoes'end})
local actual=F.nativeWetnessContract({getBodyLocation=function()return location end})
assert(actual.bodyLocation=='base:shoes'and actual.bodyLocationClass=='ItemBodyLocation')
assert(actual.nativeShoe==false and actual.cap==10,'enum-valued shoes must retain the native false string branch')
local legacy=F.nativeWetnessContract({getBodyLocation=function()return 'Shoes'end})
assert(legacy.nativeShoe==true and legacy.cap==60,'fixture must report the native expression, not force a cap')
''')
        result = evidence(case='world')
        for spec in (result[0]['ids']['items']['target'], result[2]['items']['target']):
            spec.update(nativeShoe=True, cap=60)
        self.assertTrue(a.check_case(*result), 'unobserved string-valued shoe branch must not pass')


if __name__ == '__main__':
    unittest.main()
