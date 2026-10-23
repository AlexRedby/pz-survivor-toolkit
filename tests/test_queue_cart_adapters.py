"""Cart adapter staging and evidence boundaries, without native launch/attachment."""
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys
import struct
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import carts


class CartAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.output = self.root / 'run'
        self.output.mkdir()
        self.runtime = {'game': str(self.root / 'game'), 'server_name': 'queue-smoke', 'roles': {}}
        self.options = {}
        for key in ('ffmpeg', 'ffprobe', 'patch_jar', 'mesh_fbx'):
            path = self.root / key
            path.write_bytes(b'explicit dependency')
            path.chmod(0o755)
            self.options[key] = str(path)
        self.locations = {}
        for mod in carts.MODS:
            path = self.root / 'mods' / mod
            path.mkdir(parents=True)
            self.locations[mod] = path
        (self.locations['PZToolkitJavaPatches'] / 'candidate.jar').write_bytes(b'explicit dependency')
        self.options['mod_sources'] = {mod: str(self.locations[mod]) for mod in ('PZSurvivorToolkit', 'PZToolkitJavaPatches')}
        self.selection = dict(suite=carts.SP, cases=['reverse'], kind='sp', mode='toolkit', languages=['RU'],
                              mods=list(carts.MODS), ports=[17373, 17374], options=self.options)
        self.role('client1')

    def role(self, name):
        cache = self.output / name
        for sub in ('classes', 'Lua', 'mods'):
            (cache / sub).mkdir(parents=True)
        (cache / 'options.ini').write_text('height=720\nvoiceEnable=false\n')
        self.runtime['roles'][name] = dict(cache=str(cache), classes=str(cache / 'classes'))
        return cache

    @staticmethod
    def compiler(command, **kwargs):
        classes = Path(command[command.index('-d') + 1])
        for source in [Path(value) for value in command if value.endswith('.java')]:
            target = classes / ('net/alexredby/cartlab/Main.class' if source.stem == 'Main' else source.stem + '.class')
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b'compiled test class')
        return SimpleNamespace(returncode=0, stdout='', stderr='')

    def stage(self):
        with patch.object(carts.subprocess, 'run', side_effect=self.compiler) as compiler:
            carts.stage(ROOT, self.output, self.root / 'game', self.root / 'jdk', self.selection, self.locations, self.runtime)
        return compiler

    def test_entry_contact_repro_is_scoped_to_supported_public_menu_scenes(self):
        self.selection['cases'] = ['approach']
        self.options.update(cart_entry_contact_repro=True, cart_scenes=['container-equip', 'wrong-side'])
        carts.validate(self.selection)
        for change in ({'cart_entry_contact_repro': 'true'}, {'cart_scenes': ['wall-detour']}, {'cart_scenes': []}):
            original = dict(self.options)
            self.options.update(change)
            with self.subTest(change=change), self.assertRaisesRegex(ValueError, 'cart_entry_contact_repro'):
                carts.validate(self.selection)
            self.options.clear(); self.options.update(original)
        self.selection.update(suite=carts.MP, cases=['owner_observer_motion'], kind='mp', languages=['EN', 'RU'])
        with self.assertRaisesRegex(ValueError, 'cart_entry_contact_repro'):
            carts.validate(self.selection)

    def test_entry_sex_and_load_options_require_the_scoped_reproducer(self):
        self.selection['cases']=['approach'];self.options.update(cart_entry_contact_repro=True,cart_scenes=['container-equip'])
        for female in (False,True):
            for load in ('empty','full'):
                self.options.update(cart_entry_female=female,cart_entry_load=load)
                carts.validate(self.selection)
        for change in ({'cart_entry_female':'yes'},{'cart_entry_load':'partial'},{'cart_entry_contact_repro':False}):
            original=dict(self.options);self.options.update(change)
            with self.subTest(change=change),self.assertRaises(ValueError):carts.validate(self.selection)
            self.options.clear();self.options.update(original)

    def test_sp_stage_builds_three_sealed_agents_and_waits_for_owned_probe_gate(self):
        compiler = self.stage()
        self.assertEqual(compiler.call_count, 2)
        self.assertTrue(all('--release' in call.args[0] and '25' in call.args[0] for call in compiler.call_args_list))
        spec = self.runtime['roles']['client1']
        runtime = Path(spec['env']['PZ_CART_RUNTIME_FILE'])
        text = runtime.read_text()
        self.assertIn((ROOT / 'tests/native_queue/contributions/wooden_cart_motion/test-area.lua').read_text(), text)
        self.assertIn('ALL_COMPLETE cases=', text)
        lua = shutil.which('luajit') or shutil.which('lua')
        if lua:
            subprocess.run([lua, '-e', 'assert(loadfile(' + json.dumps(str(runtime)) + '))'], check=True, capture_output=True)
        attaches = self.runtime['fixture']['attach']['client1']
        self.assertEqual(len(attaches), 3)
        for row in attaches:
            self.assertTrue(Path(row['jar']).is_relative_to(self.output / 'client1/classes'))
            self.assertEqual(row['output'], str(self.output / 'client1'))
            self.assertEqual(row['ready'], '[CART_ADAPTER] PROBE_ATTACH_READY')
            with zipfile.ZipFile(row['jar']) as jar:
                self.assertIn(b'Agent-Class:', jar.read('META-INF/MANIFEST.MF'))
        startup = (self.output / 'client1/mods/ActionQueueTest/42/media/lua/client/QueueCartStartup.lua').read_text()
        self.assertIn(f'posX={int(carts.AREA["x"])},posY={int(carts.AREA["y"])},posZ=0', startup)
        self.assertIn("getFileReader('queue-probes-ready.txt',false)", startup)
        self.assertIn("assert(ready=='ready'", startup)
        self.assertFalse((self.output / 'client1/Lua/queue-probes-ready.txt').exists())
        self.assertIn('toggleToSprint=false', (self.output / 'client1/options.ini').read_text())
        self.assertEqual(self.runtime['roles']['client1']['env']['PZ_CART_TEST_PAD'], 'true')

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT required for actual cart startup callback')
    def test_sp_startup_probe_gate_waits_for_exact_default_wood_or_selected_metal(self):
        source = ROOT / 'tests/native_queue/support/QueueCartStartup.lua'
        script = r'''
local startup=STARTUP_SOURCE
local originalPrint=print
for _,variant in ipairs({'default-wood','metal-wheelbarrow'}) do
 local expected=variant=='metal-wheelbarrow' and 'SaucedWheelbarrow.WheelbarrowMetal' or 'SaucedWheelbarrow.WheelbarrowWood'
 local config={cases={'interaction'}}
 if variant=='metal-wheelbarrow' then config.options={cart_variant=variant} end
 package.loaded.QueueTestSelection=nil
 package.preload.QueueTestSelection=function() return config end
 local callbacks,markers={},{}
 Events={}
 for _,name in ipairs({'OnMainMenuEnter','OnPreUIDraw','OnGameStart','OnTick'}) do
  Events[name]={Add=function(fn) assert(not callbacks[name]);callbacks[name]=fn end}
 end
 print=function(value) markers[#markers+1]=value end
 local reloads,checks,reads,closed=0,0,0,0
 local itemType,actorZ,gate=nil,7,false
 local item={getFullType=function() return itemType end}
 local player={getPrimaryHandItem=function() return itemType and item or nil end,getZ=function() return actorZ end}
 getPlayer=function() return player end
 CartTestArea={ready=false,z=7,check=function(p) assert(p==player);checks=checks+1 end}
 cartLabReload=function() reloads=reloads+1 end
 getFileReader=function(name,create)
  assert(name=='queue-probes-ready.txt' and create==false)
  reads=reads+1
  if not gate then return nil end
  return {readLine=function() return 'ready' end,close=function() closed=closed+1 end}
 end
 assert(loadfile(startup))()
 callbacks.OnTick();assert(reloads==0 and #markers==0,'unstarted fixture emitted readiness')
 callbacks.OnGameStart();assert(reloads==1,'game start did not load bootstrap exactly once')
 callbacks.OnTick();assert(checks==0 and reads==0 and #markers==0,'unready area emitted attach marker')
 CartTestArea.ready=true
 for _,wrong in ipairs({'SaucedCarts.ShoppingCart',variant=='metal-wheelbarrow' and 'SaucedWheelbarrow.WheelbarrowWood' or 'SaucedWheelbarrow.WheelbarrowMetal'}) do
  itemType=wrong;callbacks.OnTick()
  assert(checks==0 and reads==0 and #markers==0 and reloads==1,'wrong cart passed startup gate: '..variant)
 end
 itemType=expected;actorZ=0;callbacks.OnTick()
 assert(checks==0 and reads==0 and #markers==0,'wrong floor passed startup gate')
 actorZ=7;callbacks.OnTick()
 assert(checks==1 and reads==1 and reloads==1 and #markers==1 and markers[1]=='[CART_ADAPTER] PROBE_ATTACH_READY',
  'matching exact cart did not request native probe attachment: '..variant)
 callbacks.OnTick();assert(checks==2 and reads==2 and #markers==1 and reloads==1,'unconfirmed probe gate advanced or duplicated request')
 gate=true;callbacks.OnTick()
 assert(checks==3 and reads==3 and closed==1 and reloads==2 and #markers==1,'confirmed probe attachment did not reload scenario once')
 callbacks.OnTick();assert(checks==3 and reads==3 and closed==1 and reloads==2 and #markers==1,'launched fixture repeated startup')
end
print=originalPrint
print('PASS actual SP startup waits for exact wood/metal, owned probe receipt and one scenario reload')
'''.replace('STARTUP_SOURCE', json.dumps(str(source)))
        result = subprocess.run([shutil.which('luajit'), '-'], input=script, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS actual SP startup', result.stdout)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT required for actual interaction ownership tick')
    def test_interaction_tick_checks_exact_selected_type_count_for_wood_and_metal(self):
        source = (ROOT / 'tests/native_queue/contributions/wooden_cart_motion/scenario-interaction.lua').read_text()
        # Execute the real counter/snapshot helpers and recording tick through its ownership guard.
        # Video/actions after that guard are outside this narrow counter regression.
        helpers = source[source.index('local function cargo()'):source.index('local function event(name,now)')]
        tick = source[source.index('local function tick()'):]
        guard = re.search(r"^ assert\(row\.worldCount<=1.*'Cart duplicated or disappeared'\)", tick, re.M)
        self.assertIsNotNone(guard, 'actual recording tick lost its ownership assertion')
        chunk = helpers + '\n' + tick[:guard.end()] + '\n return row\nend\nreturn tick'
        script = r'''
local chunk=ACTUAL_CHUNK
local matrixCount=0
local function list(values)
 return {size=function() return #values end,get=function(_,i) return values[i+1] end}
end
for _,kind in ipairs({'SaucedWheelbarrow.WheelbarrowWood','SaucedWheelbarrow.WheelbarrowMetal'}) do
 for _,case in ipairs({'grounded','held','other-type-nearby','duplicate-world','extra-same-type','replaced-wrong-type','duplicate-inventory','disappeared','world-and-inventory'}) do
  local item={getID=function() return 42 end,getFullType=function() return kind end,
   getInventory=function() return {getItems=function() return list({}) end,getCapacityWeight=function() return 0 end} end,
   getCondition=function() return 100 end,getWorldAlpha=function() return 1 end,getWorldZRotation=function() return 0 end}
  local worlds,inventory={},{}
  local square={getX=function() return 0 end,getY=function() return 0 end,getZ=function() return 0 end}
  local function world(value)
   return {getItem=function() return value end,getSquare=function() return square end,
    getAlpha=function() return 1 end,isOutlineHighlight=function() return false end,
    getOffX=function() return .5 end,getOffY=function() return .5 end,getOffZ=function() return 0 end}
  end
  local function candidate(id,fullType) return {getID=function() return id end,getFullType=function() return fullType end} end
  if case=='held' or case=='duplicate-inventory' then inventory={item} else worlds={world(item)} end
  if case=='other-type-nearby' then worlds[#worlds+1]=world(candidate(99,'SaucedCarts.ShoppingCart')) end
  if case=='duplicate-world' then worlds[#worlds+1]=world(item) end
  if case=='extra-same-type' then worlds[#worlds+1]=world(candidate(99,kind)) end
  if case=='replaced-wrong-type' then worlds={world(candidate(42,'SaucedCarts.ShoppingCart'))} end
  if case=='duplicate-inventory' then inventory[#inventory+1]=item end
  if case=='disappeared' then worlds={} end
  if case=='world-and-inventory' then inventory={item} end
  square.getWorldObjects=function() return list(worlds) end
  local empty={getWorldObjects=function() return list({}) end}
  local player={getInventory=function() return {getItems=function() return list(inventory) end} end,
   getPrimaryHandItem=function() return inventory[1] end,getSecondaryHandItem=function() return inventory[1] end,
   getX=function() return .5 end,getY=function() return .5 end,getZ=function() return 0 end,
   isFemale=function() return false end,isRunning=function() return false end,isSprinting=function() return false end,
   getPerkLevel=function() return 0 end,getPlayerNum=function() return 0 end,
   getCharacterActions=function() return list({}) end,getVariableString=function() return '' end,getVariableBoolean=function() return false end}
  local env={item=item,kind=kind,p=player,initialCargo=0,initialCargoIDs='',config={interruptions=true},
   cases={{name=case}},phase=1,since=0,sampleSince=100,mode='record',stage=case=='held' and 'held' or 'grounded',
   cycle=1,driveStage=0,gaitStage=0,actionSerial=0,restartCount=0,Perks={Sprinting=1},
   CartTestArea={x=.5,y=.5,z=0,contains=function() return true end},
   getCell=function() return {getGridSquare=function(_,x,y) return x==0 and y==0 and square or empty end} end,
   getTimestampMs=function() return 100 end,getPlayerData=function() return nil end,
   getCore=function() return {setAutoZoom=function() end,getZoom=function() return .25 end} end,
   toolkitVideoStatus=function() return {state='recording'} end,
   ISTimedActionQueue={getTimedActionQueue=function() return {queue={}} end}}
  setmetatable(env,{__index=_G})
  local loader=assert(loadstring(chunk));setfenv(loader,env)
  local ok,row=pcall(loader())
  local valid=case=='grounded' or case=='held' or case=='other-type-nearby'
  assert(ok==valid,'actual tick ownership result changed: '..kind..'/'..case..' '..tostring(row))
  if valid then
   assert(row.cartType==kind and row.cartWorldCount==row.worldCount,'selected-type counter lost exact identity')
   if kind=='SaucedWheelbarrow.WheelbarrowMetal' then assert(row.woodWorldCount==nil,'metal evidence acquired a false wood count') end
  else
   assert(tostring(row):find('Cart duplicated or disappeared',1,true),'counter failed outside the ownership guard: '..tostring(row))
  end
  matrixCount=matrixCount+1
 end
end
print('PASS actual selected-type ownership tick '..matrixCount..' cases')
'''.replace('ACTUAL_CHUNK', json.dumps(chunk))
        result = subprocess.run([shutil.which('luajit'), '-'], input=script, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS actual selected-type ownership tick 18 cases', result.stdout)

    def test_clean_capture_defaults_and_override(self):
        for case, override, expected in [('reverse',None,True),('manual',None,False),('reverse',False,False),('manual',True,True)]:
            with self.subTest(case=case,override=override):
                shutil.rmtree(self.output);self.output.mkdir();self.runtime.pop('fixture',None);self.role('client1')
                self.selection['cases']=[case]
                if override is None: self.options.pop('cart_hide_ui',None)
                else: self.options['cart_hide_ui']=override
                self.stage()
                text=Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']).read_text()
                self.assertIn('["hideUI"]='+str(expected).lower(),text)
        for invalid in (1,'false',None):
            self.options['cart_hide_ui']=invalid
            with self.assertRaisesRegex(ValueError,'cart_hide_ui'): carts.validate(self.selection)

    def test_manual_sp_stage_only_bootstraps_without_autonomous_scenarios_or_probes(self):
        self.selection['cases'] = ['manual']
        compiler = self.stage()
        self.assertEqual(compiler.call_count, 1)
        self.assertEqual(carts.scene_names('manual'), [])
        self.assertEqual(carts.selected_scenes(self.selection), [])
        self.assertEqual(self.runtime['fixture']['attach'], {})
        self.assertTrue(self.runtime['fixture']['manual'])
        runtime = Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']).read_text()
        self.assertIn((ROOT / 'tests/native_queue/contributions/wooden_cart_motion/bootstrap.lua').read_text(), runtime)
        for autonomous_source in [row[0] for bank,row in carts.SP_CASES.items() if bank!='manual']:
            self.assertNotIn((ROOT / 'tests/native_queue/contributions/wooden_cart_motion' / autonomous_source).read_text(), runtime)
        self.assertNotIn('["authoredClip"]=', runtime)
        self.assertFalse(carts.complete(self.selection, 'client1', '[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] ALL_COMPLETE cases=0\n'))
        self.assertFalse(carts.complete(self.selection, 'client1', '[WOOD_PROTOTYPE] BOOTSTRAP_READY\n'))

    def test_relative_motion_and_obstacle_matrices_keep_exact_axes_and_sources(self):
        for bank, count, required in (
                ('motion-matrix', 36, 'female-full-sprint-slalom-down'),
                ('obstacle-matrix', 72, 'female-full-sprint-door-open')):
            with self.subTest(bank=bank):
                names = carts.scene_names(bank)
                self.assertEqual(len(names), count)
                self.assertEqual(len(set(names)), count)
                self.assertIn(required, names)
                for sex in ('male', 'female'):
                    for load in ('empty', 'full'):
                        for gait in ('walk', 'run', 'sprint'):
                            self.assertEqual(sum(n.startswith(f'{sex}-{load}-{gait}-') for n in names), count//12)
                self.selection['cases'] = [bank]
                paths = carts.sources(ROOT, self.selection)
                intake = ROOT/'tests/native_queue/contributions/wooden_cart_motion'
                self.assertIn(intake/f'scenario-{bank}.lua', paths)
                self.assertIn(intake/f'analyze-{bank}.py', paths)
                self.assertTrue(carts.complete(self.selection, 'client1', f'[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] ALL_COMPLETE cases={count}\n'))
                self.assertFalse(carts.complete(self.selection, 'client1', '[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] ALL_COMPLETE cases=12\n'))

    def test_approach_bank_stages_native_vehicle_polygon_for_precise_collision(self):
        self.selection['cases'] = ['approach']
        self.stage()
        runtime = Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']).read_text()
        self.assertIn('["vehicles"]=true', runtime)
        intake = ROOT/'tests/native_queue/contributions/wooden_cart_motion'
        self.assertIn((intake/'vehicles.lua').read_text(), runtime)
        self.assertIn((intake/'scenario-approach.lua').read_text(), runtime)
        self.assertLess(runtime.index((intake/'vehicles.lua').read_text()), runtime.index((intake/'scenario-approach.lua').read_text()))

    def test_vehicle_bank_stages_only_owned_vehicle_fixture_and_exact_scenes(self):
        self.selection['cases'] = ['vehicles']
        self.stage()
        runtime = Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']).read_text()
        self.assertIn('["vehicles"]=true', runtime)
        self.assertIn((ROOT / 'tests/native_queue/contributions/wooden_cart_motion/vehicles.lua').read_text(), runtime)
        self.assertIn((ROOT / 'tests/native_queue/contributions/wooden_cart_motion/scenario-vehicles.lua').read_text(), runtime)
        lua = shutil.which('luajit') or shutil.which('lua')
        if lua:
            path = self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']
            subprocess.run([lua, '-e', 'assert(loadfile(' + json.dumps(path) + '))'], check=True, capture_output=True)
        names = carts.scene_names('vehicles')
        self.assertEqual(len(names), 12)
        self.assertEqual(len(set(names)), 12)
        self.assertIn('male-full-vehicle-yaw45-slide-right', names)
        self.assertTrue(carts.complete(self.selection, 'client1', '[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] ALL_COMPLETE cases=12\n'))
        self.assertFalse(carts.complete(self.selection, 'client1', '[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] ALL_COMPLETE cases=8\n'))

    def test_variants_stage_without_wooden_probes_mesh_or_numpy(self):
        self.selection['cases'] = ['variants']
        self.options.pop('mesh_fbx')
        with patch.object(carts.importlib, 'import_module', side_effect=ModuleNotFoundError('numpy')) as dependency:
            compiler = self.stage()
        dependency.assert_not_called()
        self.assertEqual(compiler.call_count, 1)
        self.assertEqual(self.runtime['fixture']['attach'], {'client1': []})
        self.assertIn('[CART_VARIANT] FAIL', self.runtime['fixture']['failure_markers'])
        runtime = Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE'])
        source = runtime.read_text()
        self.assertIn((ROOT / 'tests/native_queue/contributions/wooden_cart_motion/scenario-variants.lua').read_text(), source)
        self.assertIn("triggerEvent('OnFillWorldObjectContextMenu'", source)
        self.assertIn("triggerEvent('OnFillInventoryObjectContextMenu'", source)
        self.assertIn('ISInventoryPaneContextMenu.onUnEquip({item}', source)
        lua = shutil.which('luajit') or shutil.which('lua')
        if lua:
            subprocess.run([lua, '-e', 'assert(loadfile(' + json.dumps(str(runtime)) + '))'], check=True, capture_output=True)
        self.assertTrue(carts.sources(ROOT, self.selection))

    @staticmethod
    def variant_log():
        records = []
        for name, kind in carts.VARIANTS.items():
            for phase in carts.VARIANT_PHASES:
                ground = phase.startswith('drop-')
                records.append(dict(case=name, kind=kind, phase=phase, id=42, cargoIDs='99:Base.Log:1', cargoWeight=1,
                    primaryID=-1 if ground else 42, secondaryID=-1 if ground else 42,
                    inventoryCount=0 if ground else 1, worldCount=1 if ground else 0,
                    luaActions=0, nativeActions=0, hasPath=False, elapsed=2500, distance=1, gaitSeen=True,
                    approachDistance=2.25 if phase=='pickup-far' else .5))
        return records

    def test_variants_verifies_native_phases_and_rejects_missing_identity_ownership_or_gait(self):
        self.selection['cases'] = ['variants']
        def log(rows):
            return '[WOOD_BANK] RUN_STARTED\n' + '\n'.join('[CART_VARIANT] PHASE ' + json.dumps(row) for row in rows)
        records = self.variant_log()
        report = carts._variant_coverage(log(records), carts.scene_names('variants'))
        self.assertTrue(report['functionalPass'])
        for label, index, key, value in [('cart identity', 1, 'id', 43), ('cargo identity', 1, 'cargoIDs', '100:Base.Log:1'),
                ('cargo weight', 1, 'cargoWeight', 2), ('one hand', 1, 'secondaryID', -1),
                ('duplicate world', 4, 'worldCount', 2), ('queue', 5, 'nativeActions', 1),
                ('path', 7, 'hasPath', True), ('no movement', 2, 'distance', 0), ('wrong gait', 3, 'gaitSeen', False),
                ('far not exercised', 7, 'approachDistance', .5), ('timeout', 9, 'elapsed', 15000)]:
            with self.subTest(label=label):
                bad=[dict(row) for row in records];bad[index][key]=value
                with self.assertRaises(ValueError): carts._variant_coverage(log(bad), carts.scene_names('variants'))
        for rows in (records[:-1], records + [records[-1]], list(reversed(records))):
            with self.assertRaisesRegex(ValueError, 'phases'):
                carts._variant_coverage(log(rows), carts.scene_names('variants'))

    def test_variants_verify_keeps_functional_scope_and_skips_geometry_analyzers(self):
        self.selection['cases'] = ['variants']
        rows=self.variant_log()
        text='[WOOD_BANK] RUN_STARTED\n' + '\n'.join('[CART_VARIANT] PHASE ' + json.dumps(row) for row in rows)
        text+='\n[WOOD_BANK] ALL_COMPLETE cases=3\n'
        (self.output/'client1-launch.log').write_text(text)
        with patch.object(carts, '_videos', return_value=[]), patch.object(carts, '_run') as analyzer:
            result=carts.verify(self.output,self.selection,{})
        analyzer.assert_not_called()
        self.assertEqual(result['issues'], [])
        self.assertTrue(result['outcomes'][0]['outcome']['functionalPass'])
        self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
        self.assertIn('wooden mesh', result['evidence']['scope'])
        (self.output/'client1-launch.log').write_text(text.replace('"secondaryID": 42', '"secondaryID": -1', 1))
        with patch.object(carts, '_videos', return_value=[]):
            self.assertTrue(carts.verify(self.output,self.selection,{})['issues'])

    def test_showcase_stages_native_capture_and_requires_ordered_gait_and_ownership(self):
        self.selection['cases'] = ['showcase']
        self.options.pop('mesh_fbx')
        self.stage()
        self.assertEqual(self.runtime['fixture']['attach'], {'client1': []})
        source = Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']).read_text()
        self.assertIn((ROOT / 'tests/native_queue/contributions/wooden_cart_motion/scenario-showcase.lua').read_text(), source)
        rows = []
        for name in carts.scene_names('showcase'):
            kind = carts.VARIANTS[name]
            for phase in carts.SHOWCASE_PHASES:
                ground = phase == 'putdown'
                rows.append(dict(case=name, kind=kind, phase=phase, id=42, cargoIDs='99:Base.Log:1', cargoWeight=1,
                    primaryID=-1 if ground else 42, secondaryID=-1 if ground else 42,
                    inventoryCount=int(not ground), worldCount=int(ground), luaActions=0, nativeActions=0,
                    hasPath=False, elapsed=1500, distance=1, gaitSeen=True))
        def log(records):
            return '\n'.join('[CART_SHOWCASE] PHASE ' + json.dumps(row) for row in records)
        self.assertTrue(carts._showcase_coverage(log(rows), carts.scene_names('showcase'))['requestedPhasesCaptured'])
        for index, key, value in ((1, 'gaitSeen', False), (2, 'distance', 0), (3, 'id', 43),
                                  (8, 'worldCount', 0), (8, 'secondaryID', 42)):
            bad = [dict(row) for row in rows]; bad[index][key] = value
            with self.assertRaises(ValueError):
                carts._showcase_coverage(log(bad), carts.scene_names('showcase'))
        with self.assertRaises(ValueError):
            carts._showcase_coverage(log(rows[:-1]), carts.scene_names('showcase'))

    def test_manual_sp_rejects_automatic_scene_selection(self):
        self.selection['cases'] = ['manual']
        self.options['cart_scenes'] = ['male-full-corner']
        with self.assertRaisesRegex(ValueError, 'cart_scenes'):
            carts.validate(self.selection)

    def test_controls_stage_real_keys_without_geometry_probes(self):
        self.selection['cases'] = ['controls']; self.options.pop('mesh_fbx')
        with patch.object(carts.importlib, 'import_module', side_effect=ModuleNotFoundError('numpy')) as dependency:
            compiler = self.stage()
        dependency.assert_not_called()
        self.assertEqual(compiler.call_count, 1)
        self.assertEqual(self.runtime['fixture']['attach'], {'client1': []})
        self.assertEqual(carts.scene_names('controls'), list(carts.VARIANTS))
        source = (ROOT / 'tests/native_queue/contributions/wooden_cart_motion/scenario-controls.lua').read_text()
        runtime = Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE'])
        self.assertIn(source, runtime.read_text())
        self.assertIn('cartLabGait(phase.gait);cartLabDrive(phase.drive)', source)
        self.assertIn('heading=cartLabHeading()', source)
        self.assertIn('acceptedHeading=cartLabSteeringHeading()', source)
        self.assertIn('frame=cartLabFrame()', source)
        bridge = (ROOT / 'tests/native_queue/contributions/wooden_cart_motion/Main.java').read_text()
        self.assertIn('@LuaMethod(name="cartLabFrame", global=true)', bridge)
        self.assertIn('return zombie.iso.IsoWorld.instance.getFrameNo();', bridge)
        self.assertNotIn('setVariable(', source)
        for phase, drive, gait, duration in carts.CONTROL_PHASES:
            self.assertIn("name='" + phase + "',drive=" + str(drive) + ',gait=' + str(gait) + ',duration=' + str(duration), source)
        lua = shutil.which('luajit') or shutil.which('lua')
        if lua:
            subprocess.run([lua, '-e', 'assert(loadfile(' + json.dumps(str(runtime)) + '))'], check=True, capture_output=True)
        self.assertIn(ROOT / 'tests/native_queue/contributions/wooden_cart_motion/scenario-controls.lua', carts.sources(ROOT, self.selection))

    @staticmethod
    def control_log():
        events = []
        frame = 100
        for scene, kind in carts.VARIANTS.items():
            x = y = heading = 0
            for phase, drive, gait, duration in carts.CONTROL_PHASES:
                if phase in carts.CONTROL_POSES:
                    x = y = 0; heading = carts.CONTROL_POSES[phase]
                turn = (-4 if drive == 5 else 4 if drive == 8 else -.7 if drive == 2 else .7 if drive == 3
                        else .6 if drive == 6 else -.6 if drive == 7 else 0)
                for index in range(11):
                    frame += max(1, round(duration*.006)) if index else 1
                    if index:
                        yaw = turn/10
                        distance = (0 if drive in (0, 2, 3) else -.06 if drive in (4, 6, 7) else .08)
                        if phase == 'moving-reverse' and index <= 2: distance = .03
                        if phase.endswith('-stop') and index <= 3: distance = .03
                        x += distance*math.cos(heading+yaw/2); y += distance*math.sin(heading+yaw/2)
                        heading = math.atan2(math.sin(heading+yaw), math.cos(heading+yaw))
                    events.append(('SAMPLE', dict(case=scene, phase=phase, sample=index, elapsed=duration*index/10,
                                                  frame=frame, x=x, y=y, heading=heading, acceptedHeading=heading)))
                events.append(('PHASE', dict(case=scene, kind=kind, phase=phase, id=42, cargoID=99, cargoWeight=1,
                    primaryID=42, secondaryID=42, inventoryCount=1, worldCount=0, luaActions=0, nativeActions=0,
                    hasPath=False, drive=drive, gait=gait, gaitSeen=True, elapsed=duration, samples=11)))
        return events

    @staticmethod
    def controls_text(events):
        return '[WOOD_BANK] RUN_STARTED\n' + '\n'.join('[CART_CONTROLS] ' + kind + ' ' + json.dumps(row) for kind, row in events)

    def test_controls_analyzer_uses_native_samples_and_rejects_wrong_direction_order_and_identity(self):
        events = self.control_log()
        self.assertTrue(carts._controls_coverage(self.controls_text(events), list(carts.VARIANTS))['controlsVerified'])
        for label, change in (
                ('wrong forward', lambda rows: [row.update(x=-row['x']) for kind, row in rows if kind=='SAMPLE' and row['phase']=='forward-0']),
                ('wrong yaw', lambda rows: [row.update(heading=-row['heading']) for kind, row in rows if kind=='SAMPLE' and row['phase']=='left-held']),
                ('identity', lambda rows: rows[11][1].update(id=43)),
                ('missing ID', lambda rows: rows[11][1].pop('id')),
                ('one hand', lambda rows: rows[11][1].update(secondaryID=-1)),
                ('cargo', lambda rows: rows[11][1].update(cargoID=100)),
                ('action', lambda rows: rows[11][1].update(nativeActions=1)),
                ('path', lambda rows: rows[11][1].update(hasPath=True)),
                ('no gait', lambda rows: rows[11][1].update(gaitSeen=False)),
                ('nan', lambda rows: rows[0][1].update(x=float('nan'))),
                ('missing accepted heading', lambda rows: rows[0][1].pop('acceptedHeading')),
                ('nonfinite accepted heading', lambda rows: rows[0][1].update(acceptedHeading=float('nan'))),
                ('missing frame', lambda rows: rows[0][1].pop('frame')),
                ('boolean frame', lambda rows: rows[0][1].update(frame=True)),
                ('frame reset', lambda rows: rows[1][1].update(frame=0)),
                ('duplicate frame', lambda rows: rows[1][1].update(frame=rows[0][1]['frame'])),
                ('sample ID', lambda rows: rows[1][1].update(sample=9)),
                ('reordered', lambda rows: rows.reverse()),
                ('missing', lambda rows: rows.pop(11))):
            with self.subTest(label=label):
                bad = [(kind, dict(row)) for kind, row in events]; change(bad)
                with self.assertRaises(ValueError): carts._controls_coverage(self.controls_text(bad), list(carts.VARIANTS))

    def test_controls_release_distinguishes_accepted_yaw_from_native_visual_blend(self):
        events = self.control_log()
        selected = [row for kind, row in events if kind=='SAMPLE' and row['case']=='wooden-wheelbarrow' and row['phase']=='right-release']
        initial = selected[0]['heading']
        # Observed SP01 visual tail: .257 radians of catch-up, then stable after 350ms.
        tail = [(0, 0), (118, .1552555464), (232, .2431426007), (332, .2575082727),
                (448, .2566645109), (548, .2568545303), (616, .2571349110)]
        accepted = initial+tail[-1][1]
        for row in selected:
            for (a, x), (b, y) in zip(tail, tail[1:]):
                if a <= row['elapsed'] <= b:
                    row['heading'] = initial+x+(y-x)*(row['elapsed']-a)/(b-a)
                    break
            row['acceptedHeading'] = accepted
        previous = [row for kind, row in events if kind=='SAMPLE' and row['case']=='wooden-wheelbarrow' and row['phase']=='right-held'][-1]
        previous['acceptedHeading'] = accepted
        report = carts._controls_coverage(self.controls_text(events), list(carts.VARIANTS))
        release = next(phase for case in report['cases'] if case['case']=='wooden-wheelbarrow'
                       for phase in case['phases'] if phase['phase']=='right-release')
        self.assertGreater(release['visualYawArc'], .25)
        self.assertEqual(release['acceptedYawArc'], 0)
        self.assertLess(release['lateVisualYawArc'], .002)
        for label, change in (
                ('accepted steering continues', lambda row: row.update(acceptedHeading=accepted+max(0,row['elapsed']-60)*.0001)),
                ('visual turn continues late', lambda row: row.update(heading=row['heading']+max(0,row['elapsed']-350)*.0001)),
                ('unbounded visual tail', lambda row: row.update(heading=row['heading']+.7 if row['elapsed']==180 else row['heading']))):
            with self.subTest(label=label):
                bad = [(kind, dict(row)) for kind, row in events]
                for kind, row in bad:
                    if kind=='SAMPLE' and row['case']=='wooden-wheelbarrow' and row['phase']=='right-release': change(row)
                with self.assertRaisesRegex(ValueError, 'relative movement/yaw'):
                    carts._controls_coverage(self.controls_text(bad), list(carts.VARIANTS))

    def test_controls_paused_gap_needs_few_native_frames_and_small_pose_change(self):
        a = dict(elapsed=0, frame=100, x=0., y=0., heading=0., acceptedHeading=0.)
        b = dict(a, elapsed=600, frame=102, x=.01, heading=.02, acceptedHeading=.02)
        proof = carts._controls_paused_gap(a,b)
        self.assertEqual((proof['wallGapMs'],proof['nativeFrames']),(600,2))
        for change in (dict(frame=136),dict(x=.3),dict(heading=.3),dict(acceptedHeading=.3),dict(elapsed=2100)):
            with self.subTest(change=change), self.assertRaisesRegex(ValueError,'paused-frame'):
                carts._controls_paused_gap(a,dict(b,**change))
        events = self.control_log()
        target = [row for kind,row in events if kind=='SAMPLE' and row['case']=='shopping-cart' and row['phase']=='right-held']
        before = dict(target[3])
        paused = dict(before, elapsed=before['elapsed']+600, frame=before['frame']+2,
                      x=before['x']+.01, heading=before['heading']+.02, acceptedHeading=before['acceptedHeading']+.02)
        for row in target[4:]:row['elapsed'] += 600
        at = next(i for i,(kind,row) in enumerate(events) if row is target[3])
        events.insert(at+1,('SAMPLE',paused))
        for index,row in enumerate([before_row for kind,before_row in events if kind=='SAMPLE' and before_row['case']=='shopping-cart' and before_row['phase']=='right-held']):
            row['sample']=index
        receipt = next(row for kind,row in events if kind=='PHASE' and row['case']=='shopping-cart' and row['phase']=='right-held')
        receipt.update(samples=12,elapsed=4600)
        report = carts._controls_coverage(self.controls_text(events),list(carts.VARIANTS))
        phase = next(row for row in report['cases'][0]['phases'] if row['phase']=='right-held')
        self.assertEqual(phase['pausedFrameGaps'][0]['nativeFrames'],2)
        self.assertEqual(phase['pausedFrameGaps'][0]['wallGapMs'],600)

    def test_controls_paused_straight_sprint_uses_prior_native_update_budget(self):
        # Immutable SP07: two native updates during a586ms capture pause; each moved less than the prior healthy interval.
        def row(elapsed,frame,x,y):
            return dict(case='shopping-cart',phase='sprint',elapsed=elapsed,frame=frame,x=x,y=y,
                        heading=1.2999999529989328,acceptedHeading=1.2999999523162842)
        c = row(445,1923,10825.9306640625,10144.052734375)
        a = row(569,1929,10826.19140625,10144.9892578125)
        b = row(1155,1931,10826.2763671875,10145.296875)
        proof = carts._controls_paused_gap(a,b,(c,a))
        self.assertEqual(proof['method'],'straight-sprint-native-budget')
        self.assertEqual((proof['nativeFrames'],proof['referenceFrames']),(2,6))
        self.assertAlmostEqual(proof['distance'],.31913428983155206)
        self.assertLess(proof['distance']/proof['nativeFrames'],proof['referencePerUpdate'])
        self.assertGreater(proof['float32Allowance'],0)
        self.assertLess(proof['maxDistance'],.327)
        heading = a['acceptedHeading']
        faster = dict(b,x=b['x']+.1*math.cos(heading),y=b['y']+.1*math.sin(heading))
        lateral = dict(b,x=b['x']-.01*math.sin(heading),y=b['y']+.01*math.cos(heading))
        reverse = dict(b,x=2*a['x']-b['x'],y=2*a['y']-b['y'])
        for label,first,last,reference in (
                ('faster',a,faster,(c,a)),('lateral',a,lateral,(c,a)),('reverse',a,reverse,(c,a)),
                ('turn',a,dict(b,heading=b['heading']+.01),(c,a)),
                ('accepted-turn',a,dict(b,acceptedHeading=b['acceptedHeading']+.01),(c,a)),
                ('no-reference',a,b,None),('non-sprint',dict(a,phase='run'),dict(b,phase='run'),(c,a)),
                ('too-many-updates',a,dict(b,frame=a['frame']+5),(c,a)),
                ('frame-reset',a,dict(b,frame=a['frame']-1),(c,a)),
                ('long-pause',a,dict(b,elapsed=a['elapsed']+2001),(c,a)),
                ('unhealthy-reference',a,b,(dict(c,elapsed=-100),a)),
                ('reference-frame-reset',a,b,(dict(c,frame=a['frame']),a)),
                ('reference-turn',a,b,(dict(c,heading=c['heading']+.01),a)),
                ('foreign-phase',a,b,(dict(c,phase='run'),a)),
                ('foreign-case',a,dict(b,case='metal-wheelbarrow'),(c,a))):
            with self.subTest(label=label),self.assertRaisesRegex(ValueError,'paused-frame'):
                carts._controls_paused_gap(first,last,reference)

    def test_controls_verify_requires_videos_and_keeps_capture_scope(self):
        self.selection['cases'] = ['controls']
        text = self.controls_text(self.control_log()) + '\n[WOOD_BANK] ALL_COMPLETE cases=3\n'
        (self.output / 'client1-launch.log').write_text(text)
        with patch.object(carts, '_videos', return_value=[]) as videos, patch.object(carts, '_run') as analyzer:
            result = carts.verify(self.output, self.selection, {})
        videos.assert_called_once(); analyzer.assert_not_called()
        self.assertFalse(result['issues'])
        self.assertEqual(result['outcomes'][0]['status'], 'captured')
        self.assertTrue(result['outcomes'][0]['outcome']['controlsVerified'])
        self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
        with patch.object(carts, '_videos', side_effect=ValueError('Missing video')):
            self.assertEqual(carts.verify(self.output, self.selection, {})['outcomes'][0]['status'], 'failed')
        with self.assertRaisesRegex(ValueError, 'controls videos'):
            carts._videos(self.output, self.selection, 'client1', '[WOOD_BANK] COMPLETE wrong wall=0 file=x frames=1 seconds=1\n')

    def test_manual_review_never_claims_automated_animation_verification(self):
        self.selection['cases']=['manual']
        for ready in (False,True):
            (self.output/'client1-launch.log').write_text('[WOOD_PROTOTYPE] BOOTSTRAP_READY' if ready else '')
            result=carts.verify(self.output,self.selection,{})
            row=result['outcomes'][0]
            self.assertEqual(row['status'],'captured' if ready else 'failed')
            self.assertTrue(row['outcome']['manualReview'])
            self.assertFalse(row['outcome']['animationEquivalencePass'])
            self.assertFalse(row['outcome']['evidenceComplete'])

    def test_mp_stage_composes_original_methods_and_identical_selection(self):
        self.selection.update(suite=carts.MP, cases=['owner_observer_motion'], kind='mp', languages=['EN', 'RU'])
        self.role('client2'); server = self.role('server')
        self.stage()
        source = (self.output / 'cart-build/Main.java').read_text()
        self.assertIn((ROOT / 'tests/native_queue/contributions/wooden_cart_multiplayer/MPMain.methods').read_text(), source)
        self.assertEqual(source.count('    public static void main(String[] args)'), 1)
        relative = 'mods/ActionQueueTest/42/media/lua/shared/QueueTestSelection.lua'
        self.assertEqual((server / relative).read_bytes(), (self.output / 'client1' / relative).read_bytes())
        for role in ('client1', 'client2'):
            self.assertEqual(len(self.runtime['fixture']['attach'][role]), 1)
            self.assertIn('CartLab', self.runtime['fixture']['mods'])
        startup = ROOT / 'tests/native_queue/startup/client/ZZStartup.lua'
        self.assertIn(startup, carts.sources(ROOT, self.selection))
        for role in ('client1', 'client2'):
            target = self.output / role / 'mods/ActionQueueTest/42/media/lua/client/QueueCartMPStartup.lua'
            self.assertEqual(target.read_bytes(), startup.read_bytes())
            client = (target.parent / 'ZZCartMP.lua').read_text()
            self.assertNotIn('ConnectToServer.instance:connect', client)
            self.assertEqual((target.parent / 'CartMPActions.lua').read_bytes(), (ROOT / 'tests/native_queue/contributions/wooden_cart_multiplayer/actions.lua').read_bytes())
        self.assertNotIn('server', self.runtime['fixture']['attach'])
        for role in ('client1', 'client2', 'server'):
            self.assertEqual(self.runtime['roles'][role]['env']['PZ_CART_TEST_PAD'], 'false')
            self.assertNotIn('PZ_CART_TIMELINE', self.runtime['roles'][role]['env'])
            lua = self.output / role / 'mods/ActionQueueTest/42/media/lua'
            self.assertFalse(any(lua.rglob('*InventoryEquip*.lua')))

    def test_mp_timeline_requires_explicit_boolean_and_enables_all_owned_roles(self):
        self.options['cart_timeline']=True
        with self.assertRaisesRegex(ValueError,'MP boolean'): carts.validate(self.selection)
        self.selection.update(suite=carts.MP,cases=['owner_observer_motion'],kind='mp',languages=['EN','RU'])
        self.options['cart_timeline']='true'
        with self.assertRaisesRegex(ValueError,'MP boolean'): carts.validate(self.selection)
        self.options['cart_timeline']=True
        self.role('client2');self.role('server');self.stage()
        for role in ('client1','client2','server'):
            self.assertEqual(self.runtime['roles'][role]['env']['PZ_CART_TIMELINE'],'true')
        self.assertIn(ROOT/'tests/native_queue/contributions/wooden_cart_multiplayer/analyze-timeline.py',
                      carts.sources(ROOT,self.selection))

    def test_native_time_sampling_requires_separate_host_optin_and_stages_clients_only(self):
        self.selection.update(suite=carts.MP,cases=['owner_observer_motion'],kind='mp',languages=['EN','RU'])
        self.options.update(cart_time_alignment=True)
        with self.assertRaisesRegex(ValueError,'cart_time_alignment'):carts.validate(self.selection)
        self.options.update(cart_timeline=True,mp_host=True)
        self.role('client2');self.role('server');self.stage()
        for role in ('client1','client2'):
            self.assertEqual(self.runtime['roles'][role]['env']['PZ_CART_TIME_ALIGNMENT'],'true')
        self.assertNotIn('PZ_CART_TIME_ALIGNMENT',self.runtime['roles']['server']['env'])
        source=(self.output/'cart-build/Main.java').read_text()
        for name in ('NativeTime.methods','ClockTime.methods'):
            path=ROOT/'tests/native_queue/contributions/wooden_cart_multiplayer'/name
            self.assertIn(path.read_text(),source)
            self.assertIn(path,carts.sources(ROOT,self.selection))
        for key,value in [('cart_time_alignment','true'),('mp_host',False),('cart_inventory_equip',True),('cart_actions',True),('cart_wall_exit','front')]:
            original=dict(self.options);self.options[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):carts.validate(self.selection)
            self.options.clear();self.options.update(original)

    def test_mp_inventory_equip_explicit_false_does_not_stage_autoloading_modules(self):
        self.selection.update(suite=carts.MP,cases=['owner_observer_motion'],kind='mp',languages=['EN','RU'])
        self.options.update(mp_host=True,cart_inventory_equip=False)
        self.role('client2');self.role('server');self.stage()
        for role in ('client1','client2','server'):
            lua=self.output/role/'mods/ActionQueueTest/42/media/lua'
            self.assertFalse(any(lua.rglob('*InventoryEquip*.lua')))
            self.assertTrue((lua/'client/ZZCartMP.lua').is_file())
            self.assertTrue((lua/'server/ZZCartMP_Server.lua').is_file())

    def test_mp_inventory_equip_requires_an_isolated_host_bank_and_stages_it(self):
        self.options.update(cart_inventory_equip=True, mp_host=True)
        with self.assertRaisesRegex(ValueError, 'MP boolean'): carts.validate(self.selection)
        self.selection.update(suite=carts.MP, cases=['owner_observer_motion'], kind='mp', languages=['EN', 'RU'])
        for variant in ('female-empty','female-full','male-empty','male-full'):
            self.options['cart_inventory_equip_variant']=variant;carts.validate(self.selection)
        for key,value in [('mp_host',False),('cart_inventory_equip','true'),('cart_variant','metal-wheelbarrow'),
                          ('cart_actions',True),('cart_fast_motion',True),('cart_wall_exit','left'),
                          ('cart_hotkey_key',18),('cart_inventory_equip_variant','unknown')]:
            original=dict(self.options);self.options[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):carts.validate(self.selection)
            self.options.clear();self.options.update(original)
        self.role('client2');self.role('server');self.stage()
        for role in ('client1','client2'):
            self.assertEqual(self.runtime['roles'][role]['env']['PZ_CART_INVENTORY_EQUIP'],'true')
        self.assertNotIn('PZ_CART_INVENTORY_EQUIP',self.runtime['roles']['server']['env'])
        for role in ('client1','client2','server'):
            lua=self.output/role/'mods/ActionQueueTest/42/media/lua'
            for source,target in [('inventory-equip-client.lua','client/CartMPInventoryEquipClient.lua'),
                                  ('inventory-equip-server.lua','server/CartMPInventoryEquipServer.lua'),
                                  ('inventory-equip-protocol.lua','shared/CartMPInventoryEquipProtocol.lua')]:
                self.assertEqual((lua/target).read_bytes(),(ROOT/'tests/native_queue/contributions/wooden_cart_multiplayer'/source).read_bytes())

    def test_mp_inventory_equip_uses_dedicated_receipts_and_rejects_missing_evidence(self):
        self.selection.update(suite=carts.MP,cases=['owner_observer_motion'],kind='mp',languages=['EN','RU'])
        self.options.update(mp_host=True,cart_inventory_equip=True,cart_inventory_equip_variant='female-empty')
        self.role('client2')
        for role in ('client1','client2'):
            (self.output/role/'console.txt').write_text('[CART_MP] VIDEO_FINAL {}\n{"event":"complete"}\n')
        seen=[]
        def analyze(root,selection):
            seen.append((root,selection));return dict(evidenceComplete=True,scope='selected native Host')
        with patch.object(carts,'_videos',return_value=[]),patch.object(carts,'_load',return_value=SimpleNamespace(analyze=analyze)) as loader:
            result=carts.verify(self.output,self.selection,{})
        self.assertEqual(loader.call_args.args[0].name,'analyze-inventory-equip.py')
        self.assertEqual(len(seen),1)
        self.assertEqual([row['status'] for row in result['outcomes']],['captured','captured'])
        with patch.object(carts,'_videos',return_value=[]),patch.object(carts,'_load',return_value=SimpleNamespace(analyze=lambda *args:dict(evidenceComplete=False))):
            result=carts.verify(self.output,self.selection,{})
        self.assertTrue(all(row['status']=='failed' for row in result['outcomes']))
        self.assertFalse(result['outcomes'][0]['outcome']['evidenceComplete'])

    def test_mp_wall_exit_requires_host_wooden_isolated_bank(self):
        self.options.update(cart_wall_exit='left', mp_host=True)
        with self.assertRaisesRegex(ValueError, 'native MP Host'): carts.validate(self.selection)
        self.selection.update(suite=carts.MP, cases=['owner_observer_motion'], kind='mp', languages=['EN', 'RU'])
        for side in ('left', 'right', 'front'):
            self.options['cart_wall_exit']=side
            carts.validate(self.selection)
        for value in ('LEFT', None, True, [], {}):
            self.options['cart_wall_exit']=value
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, 'native MP Host'): carts.validate(self.selection)
        self.options['cart_wall_exit']='left'
        for key, value in [('mp_host', False), ('cart_variant', 'shopping-cart'), ('cart_fast_motion', True),
                           ('cart_actions', True), ('cart_hotkey_setdown', True), ('cart_hotkey_key', 18)]:
            before=dict(self.options); self.options[key]=value
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'cart_wall_exit'): carts.validate(self.selection)
            self.options.clear();self.options.update(before)
        with patch.object(carts.importlib, 'import_module', side_effect=ModuleNotFoundError('numpy')):
            with self.assertRaisesRegex(ValueError, 'MP wall analyzers require'): carts.validate(self.selection)
        self.role('client2'); self.role('server'); self.stage()
        for role in ('client1', 'client2', 'server'):
            lua=self.output/role/'mods/ActionQueueTest/42/media/lua'
            self.assertEqual((lua/'shared/CartMPWall.lua').read_bytes(),
                (ROOT/'tests/native_queue/contributions/wooden_cart_multiplayer/wall.lua').read_bytes())
        self.assertTrue(any(path.name=='analyze-wall.py' for path in carts.sources(ROOT,self.selection)))
        self.assertIn(ROOT/'JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartMotionSync.kt', carts.sources(ROOT,self.selection))

    def test_cart_variant_requires_exact_enum_and_allows_three_action_families(self):
        self.options['cart_variant'] = 'wooden-wheelbarrow'
        carts.validate(self.selection)
        self.selection.update(suite=carts.MP, cases=['owner_observer_motion'], kind='mp', languages=['EN', 'RU'])
        for invalid in (None, True, 1, [], {}, 'unknown', 'SaucedCarts.ShoppingCart'):
            self.options['cart_variant'] = invalid
            with self.subTest(invalid=invalid), self.assertRaisesRegex(ValueError, 'exact cart variant'):
                carts.validate(self.selection)
        for variant in carts.VARIANTS:
            self.options.update(cart_variant=variant, cart_actions=False, cart_fast_motion=True)
            carts.validate(self.selection)
            self.options['cart_actions'] = True
            carts.validate(self.selection)
        self.options.pop('cart_variant'); self.options['cart_actions'] = True
        carts.validate(self.selection)

    def test_metal_sp_stages_selected_reusable_banks_and_actual_model_probes(self):
        self.options['cart_variant'] = 'metal-wheelbarrow'
        for case in ('interaction', 'interruption-fast', 'sprint', 'stop-timing', 'stationary', 'hotkey'):
            with self.subTest(case=case):
                self.output = self.root / ('metal-' + case); self.output.mkdir(); self.role('client1')
                self.selection['cases'] = [case]
                self.options['cart_scenes'] = carts.scene_names(case)[:1]
                compiler = self.stage()
                sources = [value for call in compiler.call_args_list for value in call.args[0] if value.endswith('.java')]
                self.assertFalse(any(value.endswith('WoodenWheelNativeProbe.java') for value in sources))
                self.assertTrue(any(value.endswith('GripPoseProbe.java') for value in sources))
                self.assertTrue(any(value.endswith('ClearanceProbe.java') for value in sources))
                self.assertEqual(len(self.runtime['fixture']['attach']['client1']), 2)
                runtime = Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE'])
                source = runtime.read_text()
                self.assertIn('["cartType"]="SaucedWheelbarrow.WheelbarrowMetal"', source)
                self.assertIn('["cartVariant"]="metal-wheelbarrow"', source)
                self.assertIn("local kind=config.cartType or 'SaucedWheelbarrow.WheelbarrowWood'", source)
                subprocess.run([shutil.which('luajit'), '-e', 'assert(loadfile(' + json.dumps(str(runtime)) + '))'], check=True, capture_output=True)
        self.options.pop('cart_scenes')
        for variant, case in (('shopping-cart', 'stationary'), ('metal-wheelbarrow', 'impact'), ('metal-wheelbarrow', 'variants')):
            self.options['cart_variant'] = variant; self.selection['cases'] = [case]
            with self.subTest(variant=variant, case=case), self.assertRaisesRegex(ValueError, 'SP .*cart_variant'):
                carts.validate(self.selection)

    def test_shopping_sp_stages_only_explicit_action_banks_and_model_sources(self):
        self.options.update(cart_variant='shopping-cart', cart_mesh_fbx={model: self.options['mesh_fbx'] for model in carts.SHOPPING_MODELS})
        for case in ('interaction', 'repeat', 'wheel'):
            with self.subTest(case=case):
                self.output = self.root / ('shopping-' + case); self.output.mkdir(); self.role('client1')
                self.selection['cases'] = [case]; self.options['cart_scenes'] = carts.scene_names(case)[:1]
                compiler = self.stage()
                sources = [value for call in compiler.call_args_list for value in call.args[0] if value.endswith('.java')]
                self.assertFalse(any(value.endswith('WoodenWheelNativeProbe.java') for value in sources))
                self.assertEqual(len(self.runtime['fixture']['attach']['client1']), 3 if case == 'wheel' else 2)
                self.assertEqual(any(value.endswith('ShoppingWheelProbe.java') for value in sources), case == 'wheel')
                self.assertIn(Path(self.options['mesh_fbx']), carts.sources(ROOT, self.selection))
                runtime = Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE'])
                self.assertIn('["cartType"]="SaucedCarts.ShoppingCart"', runtime.read_text())
                subprocess.run([shutil.which('luajit'), '-e', 'assert(loadfile(' + json.dumps(str(runtime)) + '))'], check=True, capture_output=True)
        self.options.pop('cart_scenes')
        for meshes in (None, {}, {'WheelbarrowMetal': self.options['mesh_fbx']}, {'ShoppingCartModel': 'relative.fbx'}):
            self.options['cart_mesh_fbx'] = meshes
            with self.subTest(meshes=meshes), self.assertRaisesRegex(ValueError, 'cart_mesh_fbx'):
                carts.validate(self.selection)

    def test_metal_capture_checks_actual_model_mesh_and_temporal_grip_without_wood_geometry(self):
        import numpy as np

        self.selection['cases'] = ['stationary']
        name = carts.scene_names('stationary')[0]
        self.options.update(cart_variant='metal-wheelbarrow', cart_scenes=[name])
        cache = self.output / 'client1'
        matrix = [1 if i % 5 == 0 else 0 for i in range(16)]
        # Metal FBX doubles quantize by several micro-units when imported to float32.
        # These real-scale coordinates differ under decimal-seven rounding, while
        # the actual native buffer is exactly the float32 representation.
        source_point = (-39.86699879169464, -4.5117199420928955, -44.233399629592896)
        native = struct.pack('<8f', source_point[0], source_point[1], -source_point[2], 0, 0, 0, 0, 0)
        (cache / 'WheelbarrowMetal.bin').write_bytes(native)
        proof = dict(model='WheelbarrowMetal', stride=32, bytes=len(native), sha256=hashlib.sha256(native).hexdigest(), source='CartWheelSpin.render-exit')
        (cache / 'cart-mesh-WheelbarrowMetal.json').write_text(json.dumps(proof))
        rows = [dict(wallTimeMillis=100000+t, model='WheelbarrowMetal', female=False, cart=matrix,
                     bones={'Bip01_L_Hand': matrix, 'Bip01_R_Hand': matrix}, result=True, threw=False) for t in range(0, 12000, 100)]
        def write_rows(filename, values):
            (cache / filename).write_text('\n'.join(map(json.dumps, values)))
        write_rows('body-clearance.jsonl', rows); write_rows('wood-grip-poses.jsonl', rows)
        write_rows('action-lifecycle.jsonl', []); write_rows('world-cart-poses.jsonl', [])
        text = '[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] COMPLETE '+name+' wall=100000 file=scene.mp4 frames=360 seconds=12\n[WOOD_BANK] ALL_COMPLETE cases=1\n'
        (self.output / 'client1-launch.log').write_text(text)
        original_load = carts._load
        vertices = np.array([source_point])
        def load(path):
            if path.name == 'fbx_mesh.py':
                return SimpleNamespace(read_nodes=lambda path: [('Objects', [], [('Geometry', [], [('Vertices', [vertices], [])])])])
            return original_load(path)
        with patch.object(carts, '_load', side_effect=load), patch.object(carts, '_videos', return_value=[]), patch.object(carts, '_run') as wood_analyzer:
            report = carts.verify(self.output, self.selection, {})
            self.assertFalse(report['issues'], report['issues'])
            outcome = report['outcomes'][0]['outcome']
            self.assertTrue(outcome['measurementReady'])
            self.assertFalse(outcome['geometryVerified']); self.assertFalse(outcome['animationEquivalencePass'])
            self.assertTrue(report['evidence']['modelCapture']['nativeVBO']['fbxPositionsMatch'])
            wood_analyzer.assert_not_called()
            for change in ('wrong-model', 'grip-failure', 'nonfinite-matrix', 'temporal-gap', 'wrong-fbx', 'one-native-float-step-fbx', 'wrong-proof'):
                with self.subTest(change=change):
                    mutated = json.loads(json.dumps(rows))
                    if change == 'wrong-model': mutated[5]['model'] = 'WheelbarrowWood'
                    elif change == 'grip-failure': mutated[5]['result'] = False
                    elif change == 'nonfinite-matrix': mutated[5]['cart'][0] = None
                    elif change == 'temporal-gap': mutated = mutated[:5]
                    elif change == 'wrong-fbx': vertices[0, 0] = .5
                    elif change == 'one-native-float-step-fbx':
                        vertices[0, 0] = float(np.nextafter(np.float32(source_point[0]), np.float32(np.inf)))
                    else:
                        (cache / 'cart-mesh-WheelbarrowMetal.json').write_text(json.dumps(dict(proof, sha256='wrong')))
                    write_rows('wood-grip-poses.jsonl', mutated)
                    failed = carts.verify(self.output, self.selection, {})
                    self.assertTrue(failed['issues'], change)
                    self.assertEqual(failed['outcomes'][0]['status'], 'failed')
                    vertices[0, 0] = source_point[0]
                    (cache / 'cart-mesh-WheelbarrowMetal.json').write_text(json.dumps(proof))
                    write_rows('wood-grip-poses.jsonl', rows)

    def test_metal_action_capture_rejects_wrong_identity_ownership_ik_and_lifecycle(self):
        self._assert_variant_action_capture('metal-wheelbarrow')

    def test_shopping_action_capture_requires_actual_fill_meshes_ownership_and_lifecycle(self):
        self._assert_variant_action_capture('shopping-cart')

    def shopping_wheel_fixture(self):
        cache = self.output / 'client1'
        points = [(i * .01, 0, 0) for i in range(21)]
        positions = b''.join(struct.pack('<3f', *p) for p in points)
        vertices = b''.join(struct.pack('<8f', *p, 0, 0, 0, 0, 0) for p in points)
        indices = struct.pack('<21I', *range(21))
        bits = sorted({struct.unpack('<3I', positions[i:i+12]) for i in range(0, len(positions), 12)})
        mesh = dict(meshId=1, vertices=21, indices=21, stride=32, positionOffset=0,
                    vboBytes=len(vertices), eboBytes=len(indices), gpuByteOrder='little-endian', positionsByteOrder='little-endian',
                    vboFile='shopping-wheel-1-vertices.bin', eboFile='shopping-wheel-1-indices.bin', positionsFile='shopping-wheel-1-positions.bin',
                    vboSha256=hashlib.sha256(vertices).hexdigest(), eboSha256=hashlib.sha256(indices).hexdigest(),
                    positionsSha256=hashlib.sha256(positions).hexdigest(),
                    positionSetSha256=hashlib.sha256(b''.join(struct.pack('<3I', *p) for p in bits)).hexdigest())
        for field, raw in (('vboFile', vertices), ('eboFile', indices), ('positionsFile', positions)):
            (cache / mesh[field]).write_bytes(raw)
        (cache / 'shopping-wheel-1-mesh.json').write_text(json.dumps(mesh))
        identity = [int(i % 5 == 0) for i in range(16)]
        records = []
        for i in range(12):
            held = i < 6
            calls = [dict(part=part, restore=False, transpose=held, firstIndex=part*3, indexCount=3, matrix=identity[:]) for part in range(7)]
            calls.append(dict(part=-1, restore=True, transpose=held, matrix=identity[:]))
            records.append(dict(wallTimeMillis=100000+i*350, itemId=42, source='held' if held else 'world', result=True,
                                transpose=held, matrixOrder='column-major', cart=identity[:], phases=[0]*4, casters=[0]*2,
                                relative=[identity[:] for _ in range(7)], submittedParts=[identity[:] for _ in range(7)], calls=calls,
                                nativeFollow=dict(x=10, y=20, angle=0, producerNanoTime=i, returnNanoTime=i+1,
                                                  wallTimeMillis=100000+i*350, cart=identity[:], matrixOrder='column-major'), mesh=dict(mesh)))
        return cache, records, {mesh['vboSha256']}

    def test_shopping_wheel_capture_requires_exact_recording_window_and_complete_shader_receipts(self):
        cache, records, hashes = self.shopping_wheel_fixture()
        report = carts._shopping_wheel_capture(cache, records, 100000, 4, 42, hashes)
        self.assertEqual(report, dict(heldDrawSamples=6, worldDrawSamples=6, meshProofs=1, shaderDrawCaptureReady=True))
        originals = {p: p.read_bytes() for p in cache.glob('shopping-wheel-*')}
        for change in ('foreign-item', 'outside-window', 'truncated-window', 'failed-draw', 'missing-world',
                       'nonfinite-phase', 'nonfinite-caster', 'nonfinite-part', 'missing-part', 'nonfinite-follow',
                       'missing-follow', 'missing-restore', 'bad-restore', 'index-gap', 'index-coverage',
                       'tampered-hash', 'tampered-binary', 'truncated-binary', 'missing-proof'):
            with self.subTest(change=change):
                rows = json.loads(json.dumps(records)); row = rows[2]
                if change == 'foreign-item':
                    for r in rows: r['itemId'] = 99
                elif change == 'outside-window':
                    for r in rows: r['wallTimeMillis'] += 10000
                elif change == 'truncated-window': rows = rows[:5]
                elif change == 'failed-draw': row['result'] = False
                elif change == 'missing-world':
                    for r in rows: r.update(source='held', transpose=True)
                elif change == 'nonfinite-phase': row['phases'][0] = float('nan')
                elif change == 'nonfinite-caster': row['casters'][0] = float('inf')
                elif change == 'nonfinite-part': row['submittedParts'][0][0] = None
                elif change == 'missing-part': row['submittedParts'].pop()
                elif change == 'nonfinite-follow': row['nativeFollow']['angle'] = float('nan')
                elif change == 'missing-follow': row.pop('nativeFollow')
                elif change == 'missing-restore': row['calls'].pop()
                elif change == 'bad-restore': row['calls'][-1]['matrix'][12] = 1
                elif change == 'index-gap': row['calls'][2]['firstIndex'] += 3
                elif change == 'index-coverage': row['calls'][-2]['indexCount'] += 3
                elif change == 'tampered-hash': row['mesh']['eboSha256'] = 'f'*64
                elif change == 'tampered-binary': (cache / row['mesh']['eboFile']).write_bytes(b'x' * row['mesh']['eboBytes'])
                elif change == 'truncated-binary': (cache / row['mesh']['vboFile']).write_bytes(b'partial')
                else: (cache / 'shopping-wheel-1-mesh.json').unlink()
                with self.assertRaisesRegex(ValueError, 'Shopping wheel capture'):
                    carts._shopping_wheel_capture(cache, rows, 100000, 4, 42, hashes)
                for path, raw in originals.items(): path.write_bytes(raw)

    def _assert_variant_action_capture(self, variant):
        import numpy as np

        self.selection['cases'] = ['interaction']; self.options['cart_variant'] = variant
        shopping = variant == 'shopping-cart'
        if shopping:
            self.options['cart_mesh_fbx'] = {model: self.options['mesh_fbx'] for model in carts.SHOPPING_MODELS}
        analyzer = carts._load(ROOT / 'tests/native_queue/contributions/wooden_cart_motion/analyze-interaction.py')
        text, body, grip = analyzer.fixture()
        matrix = [1 if i % 5 == 0 else 0 for i in range(16)]
        kind = carts.VARIANTS[variant]; cache = self.output / 'client1'
        samples, lines, worlds, lifecycle = [], [], [], []
        for line in text.splitlines():
            if '[WOOD_INTERACTION_SAMPLE] ' in line:
                row = json.loads(line.split('] ', 1)[1]); row.update(cartType=kind, recovering=False)
                if row['stage'] == 'held': row['ToolkitCartMotion'] = True
                samples.append(row); line = '[WOOD_INTERACTION_SAMPLE] ' + json.dumps(row)
                if row['worldCount'] == 1 and row['stage'] in ('grounded', 'dropped'):
                    worlds.append(dict(wallTimeMillis=row['wall'], itemId=row['id'], cartType=kind, renderStatus='Ready', transform=matrix))
            lines.append(line)
        text = '\n'.join(lines)
        for records in (body, grip):
            for row in records:
                row.update(model=('ShoppingCartFullModel' if row['wallTimeMillis'] >= 140000 else 'ShoppingCartModel') if shopping else 'WheelbarrowMetal', female=140000 <= row['wallTimeMillis'] < 156000)
                row.setdefault('cart', matrix); row.setdefault('bones', {'Bip01_L_Hand': matrix, 'Bip01_R_Hand': matrix})
        for start in (100000, 120000, 140000, 160000):
            for action in ('ToolkitWoodCartPickup', 'ToolkitWoodCartSetdown'):
                for event in ('start', 'complete'):
                    lifecycle.append(dict(wallTimeMillis=start+2000, metaType=action, event=event))
        def write(filename, values): (cache / filename).write_text('\n'.join(map(json.dumps, values)))
        write('body-clearance.jsonl', body); write('wood-grip-poses.jsonl', grip)
        write('action-lifecycle.jsonl', lifecycle); write('world-cart-poses.jsonl', worlds)
        native = struct.pack('<8f', .01, .02, -.03, 0, 0, 0, 0, 0)
        for model in ({r['model'] for r in body} if shopping else {'WheelbarrowMetal'}):
            (cache / (model + '.bin')).write_bytes(native)
            (cache / ('cart-mesh-' + model + '.json')).write_text(json.dumps(dict(model=model, stride=32,
                bytes=len(native), sha256=hashlib.sha256(native).hexdigest(), source='CartWheelSpin.render-exit')))
        original_load = carts._load
        def load(path):
            if path.name == 'fbx_mesh.py':
                return SimpleNamespace(read_nodes=lambda path: [('Objects', [], [('Geometry', [], [('Vertices', [np.array([[.01,.02,.03]])], [])])])])
            return original_load(path)
        with patch.object(carts, '_load', side_effect=load):
            report = carts._model_capture_coverage(cache, text, self.selection)
            self.assertEqual(len(report['scenes']), 4)
            self.assertFalse(report['geometryVerified']); self.assertFalse(report['animationEquivalencePass'])
            self.assertEqual(len(report['nativeVBOs']), 2 if shopping else 1)
            if shopping:
                self.selection['cases'] = ['wheel']
                with patch.object(carts, 'selected_scenes', return_value=[r['scene'] for r in report['scenes']]):
                    for truncated in (False, True):
                        with self.subTest(missing_wheel_probe=not truncated):
                            if truncated: (cache / 'shopping-wheel-draws.jsonl').write_text('{"wallTimeMillis":')
                            with self.assertRaisesRegex(ValueError, 'Shopping wheel capture: missing or truncated draw file'):
                                carts._model_capture_coverage(cache, text, self.selection)
                    (cache / 'shopping-wheel-draws.jsonl').unlink()
                self.selection['cases'] = ['interaction']
                full_proof = cache / 'cart-mesh-ShoppingCartFullModel.json'
                original_proof = full_proof.read_text()
                full_proof.write_text(original_proof.replace('ShoppingCartFullModel', 'ShoppingCartPartialModel'))
                with self.assertRaisesRegex(ValueError, 'VBO render receipt'):
                    carts._model_capture_coverage(cache, text, self.selection)
                full_proof.write_text(original_proof)
                full_mesh = cache / 'ShoppingCartFullModel.bin'
                original_mesh = full_mesh.read_bytes()
                full_mesh.write_bytes(original_mesh + original_mesh)
                with self.assertRaisesRegex(ValueError, 'VBO render receipt'):
                    carts._model_capture_coverage(cache, text, self.selection)
                full_mesh.write_bytes(original_mesh)
                self.options['cart_mesh_fbx'].pop('ShoppingCartFullModel')
                with self.assertRaisesRegex(ValueError, 'Missing cart_mesh_fbx'):
                    carts._model_capture_coverage(cache, text, self.selection)
                self.options['cart_mesh_fbx']['ShoppingCartFullModel'] = self.options['mesh_fbx']
            self.assertTrue(all(row['ownershipAndCargoVerified'] for row in report['scenes']))
            for change in ('wrong-type', 'held-identity', 'missing-ik', 'missing-native-complete', 'missing-world'):
                with self.subTest(change=change):
                    changed_text = text
                    if change == 'wrong-type': changed_text = text.replace(kind, 'Base.Hammer')
                    elif change == 'held-identity':
                        changed_text = text.replace('"heldID": 1000', '"heldID": 1001')
                    elif change == 'missing-ik': changed_text = text.replace('"ik": true', '"ik": false')
                    elif change == 'missing-native-complete': write('action-lifecycle.jsonl', [r for r in lifecycle if r['event'] != 'complete'])
                    else: write('world-cart-poses.jsonl', [])
                    with self.assertRaises(ValueError): carts._metal_coverage(cache, changed_text, self.selection)
                    write('action-lifecycle.jsonl', lifecycle); write('world-cart-poses.jsonl', worlds)

    def test_mp_extra_capture_options_reject_nonbooleans_and_sp(self):
        for flag in ('cart_fast_motion', 'cart_actions'):
            self.options[flag] = True
            with self.assertRaisesRegex(ValueError, 'MP boolean'):
                carts.validate(self.selection)
            self.selection.update(suite=carts.MP, cases=['owner_observer_motion'], kind='mp', languages=['EN', 'RU'])
            carts.validate(self.selection)
            self.options[flag] = 1
            with self.assertRaisesRegex(ValueError, 'MP boolean'):
                carts.validate(self.selection)
            self.options.pop(flag)
            self.selection.update(suite=carts.SP, cases=['reverse'], kind='sp', languages=['RU'])

    def test_stop_and_reversal_stage_their_own_scenarios(self):
        self.assertEqual([case['id'] for case in carts.definitions()[carts.SP]['cases']],
                         ['sprint', 'reverse', 'reversal', 'stop', 'stop-timing', 'pivot', 'stationary', 'maneuvers', 'motion-matrix', 'obstacle-matrix', 'collision', 'footprint', 'vehicles', 'brace', 'fast-slide', 'wall-exit', 'wall-manual-exit', 'wall-fast-manual-exit', 'impact', 'wheel', 'interaction', 'approach', 'interruption-fast', 'interruption', 'interruption-matrix', 'repeat', 'hotkey', 'manual', 'path', 'variants', 'controls', 'showcase', 'native-e'])
        for case, count in [('stop', 24), ('stop-timing', 4), ('reversal', 20), ('stationary', 20), ('maneuvers', 32), ('collision', 24), ('footprint', 24), ('brace', 8), ('fast-slide', 16), ('wall-exit', 24), ('wall-manual-exit', 16), ('wall-fast-manual-exit', 32), ('impact', 8), ('wheel', 1), ('interaction', 4), ('approach', 7), ('interruption-fast', 14), ('interruption', 12), ('interruption-matrix', 48), ('repeat', 12), ('path', 24)]:
            with self.subTest(case=case):
                self.output = self.root / case
                self.output.mkdir()
                self.role('client1')
                self.selection['cases'] = [case]
                self.stage()
                text = Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']).read_text()
                source='stop' if case=='stop-timing' else 'collision' if case in ('collision','footprint','impact','brace','fast-slide','wall-exit','wall-manual-exit','wall-fast-manual-exit') else 'interaction' if case in ('interruption','interruption-matrix','interruption-fast','wheel','repeat') else case
                self.assertIn((ROOT / f'tests/native_queue/contributions/wooden_cart_motion/scenario-{source}.lua').read_text(), text)
                if case in ('collision','footprint','brace','fast-slide','wall-exit','wall-manual-exit','wall-fast-manual-exit'): self.assertIn('["footprint"]=true',text)
                if case == 'fast-slide': self.assertIn('["fastSlide"]=true',text)
                if case in ('wall-exit','wall-manual-exit','wall-fast-manual-exit'): self.assertIn('["wallExit"]=true',text)
                if case in ('wall-manual-exit','wall-fast-manual-exit'): self.assertIn('["wallManualExit"]=true',text)
                if case == 'wall-fast-manual-exit': self.assertIn('["wallFastManualExit"]=true',text)
                if case == 'impact': self.assertIn('["impact"]=true',text)
                if case == 'wheel': self.assertIn('["wheelCycle"]=true',text)
                if case in ('interruption', 'interruption-matrix', 'interruption-fast'): self.assertIn('["interruptions"]=true',text)
                if case == 'interruption-fast': self.assertIn('["fastInterruptions"]=true',text)
                if case == 'interruption-matrix': self.assertIn('["interruptionMatrix"]=true',text)
                if case == 'repeat': self.assertIn('["rapidRepeats"]=true',text)
                if case == 'stop-timing': self.assertIn('["stopTiming"]=true',text)
                self.assertIn('["size"]=96',text)
                self.assertEqual(len(self.runtime['fixture']['attach']['client1']), 3)
                self.assertTrue(carts.complete(self.selection, 'client1', f'[WOOD_BANK] ALL_COMPLETE cases={count}\n'))
                for wrong in (count + 1, count * 10):
                    self.assertFalse(carts.complete(self.selection, 'client1', f'[WOOD_BANK] ALL_COMPLETE cases={wrong}\n'))
                self.assertFalse(carts.complete(self.selection, 'client1',
                    f'[WOOD_BANK] ALL_COMPLETE cases={count}\n[WOOD_BANK] RUN_STARTED\n'))

    def test_wheel_cycle_detects_phase_reset_from_actual_draws(self):
        analyzer = carts._load(ROOT / 'tests/native_queue/contributions/wooden_cart_motion/analyze-wheel-cycle.py')
        analyzer.self_check()

    def test_interaction_requires_actions_identity_cargo_rendered_ik_and_scoped_coverage(self):
        self.selection['cases'] = ['interaction']
        analyzer = carts._load(ROOT / 'tests/native_queue/contributions/wooden_cart_motion/analyze-interaction.py')
        analyzer.self_check()
        text, body, grip = analyzer.fixture()
        tail, life = analyzer.entry_fixture()
        cache = self.output / 'client1'
        log = self.output / 'client1-launch.log'
        log.write_text(text)
        for filename, rows in [('body-clearance.jsonl', body), ('wood-grip-poses.jsonl', grip),
                               ('action-tail-poses.jsonl', tail), ('action-lifecycle.jsonl', life),
                               ('world-cart-poses.jsonl', analyzer.world_fixture())]:
            (cache / filename).write_text('\n'.join(map(json.dumps, rows)))
        native = struct.pack('<8f', .01,.02,-.03,0,0,0,0,0)
        (cache / 'WheelbarrowWood.bin').write_bytes(native)
        (cache / 'wood-wheel-mesh-proof.json').write_text(json.dumps(dict(matchesOriginal=True,
            proofAfterPhaseChanged=False, bytes=len(native), sha256=hashlib.sha256(native).hexdigest())))
        (self.output / 'runtime.json').write_text(json.dumps(self.runtime))
        commands = {}
        original_run = carts._run
        def run(command, directory, name):
            commands[name] = command
            if name == 'interaction':
                return original_run(command, directory, name)
            return {'exit_code': 0}
        with patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
            result = carts.verify(self.output, self.selection, {})
            self.assertFalse(result['issues'], result['issues'])
            self.assertTrue(result['evidence']['interaction']['functionalPass'])
            self.assertTrue(result['evidence']['interaction']['worldHandoff']['pass'])
            self.assertTrue(result['evidence']['interaction']['entryMotion']['pass'])
            self.assertTrue(result['evidence']['nativeMotionNotApplicable'])
            self.assertNotIn('native', commands)
            self.assertNotIn('nativePartialDiagnostic', result['evidence'])
            self.assertEqual(set(commands), {'aabb', 'body', 'pants', 'interaction'})
            self.assertEqual(result['outcomes'][0]['status'], 'captured')
            self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
            bad_tail = json.loads(json.dumps(tail))
            bad_tail[2]['bones']['Bip01_R_Hand'][13] += .10
            (cache / 'action-tail-poses.jsonl').write_text('\n'.join(map(json.dumps, bad_tail)))
            result = carts.verify(self.output, self.selection, {})
            self.assertFalse(result['evidence']['interaction']['entryMotion']['pass'])
            self.assertTrue(result['issues'])
            self.assertEqual(result['outcomes'][0]['status'], 'failed')
            (cache / 'action-tail-poses.jsonl').write_text('\n'.join(map(json.dumps, tail)))
            log.write_text(text.replace('"ik": true', '"ik": false'))
            result = carts.verify(self.output, self.selection, {})
            self.assertTrue(result['issues'])
            self.assertEqual(result['outcomes'][0]['status'], 'failed')
            for stage, changes in [('held', {'heldID': -1, 'secondaryID': -1}),
                                   ('dropped', {'active': True, 'rendered': True, 'ik': False})]:
                with self.subTest(stage=stage):
                    lines = []
                    for line in text.splitlines():
                        if '[WOOD_INTERACTION_SAMPLE]' in line:
                            row = json.loads(line.split('] ', 1)[1])
                            if row['stage'] == stage:
                                row.update(changes)
                            line = '[WOOD_INTERACTION_SAMPLE] ' + json.dumps(row)
                        lines.append(line)
                    log.write_text('\n'.join(lines))
                    result = carts.verify(self.output, self.selection, {})
                    self.assertFalse(result['evidence']['interaction']['functionalPass'])
                    self.assertTrue(result['issues'])
                    self.assertEqual(result['outcomes'][0]['status'], 'failed')
            log.write_text(text)
            late_hidden = analyzer.world_fixture()
            late_hidden.append(dict(late_hidden[2], wallTimeMillis=112000, alpha=0))
            (cache / 'world-cart-poses.jsonl').write_text('\n'.join(map(json.dumps, late_hidden)))
            result = carts.verify(self.output, self.selection, {})
            self.assertTrue(result['evidence']['interaction']['functionalPass'])
            self.assertFalse(result['evidence']['interaction']['worldHandoff']['pass'])
            self.assertTrue(result['issues'])
            self.assertEqual(result['outcomes'][0]['status'], 'failed')

    @staticmethod
    def one_cart_scene(text, name):
        first=text.index('[WOOD_BANK] CASE '+name+' ')
        last=text.index('\n',text.index('[WOOD_BANK] COMPLETE '+name+' ',first))
        cleanup='[CART_APPROACH] CLEANUP_COMPLETE\n' if '[CART_APPROACH] CLEANUP_COMPLETE' in text else ''
        return '[WOOD_BANK] RUN_STARTED\n'+text[first:last]+'\n'+cleanup+'[WOOD_BANK] ALL_COMPLETE cases=1\n'

    def test_approach_full_bank_runs_its_verifier_without_held_geometry_dependencies(self):
        self.selection['cases']=['approach']
        fixture=carts._load(ROOT/'tests/test_cart_approach_edges.py')
        text,lifecycle=fixture.fixture();cache=self.output/'client1'
        (self.output/'client1-launch.log').write_text(text)
        (cache/'action-lifecycle.jsonl').write_text('\n'.join(map(json.dumps,lifecycle)))
        original_run=carts._run
        with patch.object(carts,'_videos',return_value=[]) as videos, \
             patch.object(carts,'_run',wraps=original_run) as analyzer, \
             patch.object(carts,'_debug_coverage',side_effect=AssertionError('approach must bypass held geometry')):
            result=carts.verify(self.output,self.selection,{})
            self.assertFalse(result['issues'],result)
            videos.assert_called_once();analyzer.assert_called_once()
            command=analyzer.call_args.args[0]
            self.assertEqual(Path(command[1]).name,'analyze-approach.py')
            self.assertNotIn('--scene',command)
            self.assertEqual(set(result['evidence']['analyzers']),{'approach'})
            self.assertEqual(len(result['evidence']['approach']['cases']),7)
            outcome=result['outcomes'][0]
            self.assertEqual(outcome['status'],'captured')
            self.assertTrue(outcome['outcome']['functionalPass'] and outcome['outcome']['approachVerified'])
            self.assertFalse(outcome['outcome']['partialCoverage'] or outcome['outcome']['animationEquivalencePass'])
            self.assertFalse((cache/'body-clearance.jsonl').exists())
            self.assertFalse((cache/'wood-grip-poses.jsonl').exists())
            self.assertFalse((self.output/'runtime.json').exists())
            # The adapter must execute the verifier and propagate its failure, not just trust ALL_COMPLETE.
            (cache/'action-lifecycle.jsonl').write_text('\n'.join(map(json.dumps,lifecycle[:-1])))
            failed=carts.verify(self.output,self.selection,{})
            self.assertTrue(failed['issues'])
            self.assertFalse(failed['evidence']['approach']['functionalPass'])
            self.assertEqual(failed['outcomes'][0]['status'],'failed')

    def test_selected_failed_approach_runs_scene_verifier_and_marks_partial_without_held_phases(self):
        name='precise-blocked';self.selection['cases']=['approach'];self.options['cart_scenes']=[name]
        fixture=carts._load(ROOT/'tests/test_cart_approach_edges.py')
        text,lifecycle=fixture.fixture();cache=self.output/'client1'
        (self.output/'client1-launch.log').write_text(self.one_cart_scene(text,name))
        start=100000+fixture.analyzer.CASES.index(name)*20000
        selected=[row for row in lifecycle if start<=row['wallTimeMillis']<start+20000]
        (cache/'action-lifecycle.jsonl').write_text('\n'.join(map(json.dumps,selected)))
        original_run=carts._run
        with patch.object(carts,'_videos',return_value=[]),patch.object(carts,'_run',wraps=original_run) as analyzer, \
             patch.object(carts,'_debug_coverage',side_effect=AssertionError('failure-only scene has no held phase')):
            result=carts.verify(self.output,self.selection,{})
            self.assertFalse(result['issues'],result)
            analyzer.assert_called_once();command=analyzer.call_args.args[0]
            self.assertEqual(command[command.index('--scene'):],['--scene',name])
            self.assertEqual(set(result['evidence']['analyzers']),{'approach'})
            self.assertEqual([row['case'] for row in result['evidence']['approach']['cases']],[name])
            self.assertEqual(result['evidence']['selectedScenes'],[name])
            outcome=result['outcomes'][0]
            self.assertEqual(outcome['status'],'captured')
            self.assertTrue(outcome['outcome']['partialCoverage'] and outcome['outcome']['approachVerified'])
            self.assertFalse(outcome['outcome']['animationEquivalencePass'])
            self.assertFalse((cache/'body-clearance.jsonl').exists())
            self.assertFalse((cache/'wood-grip-poses.jsonl').exists())
            selected[-1]['event']='stop'
            (cache/'action-lifecycle.jsonl').write_text('\n'.join(map(json.dumps,selected)))
            failed=carts.verify(self.output,self.selection,{})
            self.assertTrue(failed['issues'])
            self.assertFalse(failed['evidence']['approach']['approachVerified'])
            self.assertEqual(failed['outcomes'][0]['status'],'failed')
            self.assertTrue(failed['outcomes'][0]['outcome']['partialCoverage'])

    def test_selected_fast_interruption_runs_fast_scene_gates_before_debug_capture(self):
        name='male-full-pickup-contact-sprint'
        self.selection['cases']=['interruption-fast'];self.options['cart_scenes']=[name]
        fixture=carts._load(ROOT/'tests/test_cart_interruption.py')
        text,lifecycle,body,grip,world,draws,tail=fixture.fixture(fast=True)
        (self.output/'client1-launch.log').write_text(self.one_cart_scene(text,name))
        (self.output/'runtime.json').write_text(json.dumps(self.runtime));cache=self.output/'client1'
        for filename,rows in [('action-lifecycle.jsonl',lifecycle),('body-clearance.jsonl',body),
                              ('wood-grip-poses.jsonl',grip),('world-cart-poses.jsonl',world),
                              ('wheel-roll-draws.jsonl',draws),('action-tail-poses.jsonl',tail)]:
            (cache/filename).write_text('\n'.join(map(json.dumps,rows)))
        original_run=carts._run;commands={}
        def run(command,directory,bank):
            commands[bank]=command
            return original_run(command,directory,bank) if bank=='interruption-fast' else {'exit_code':0}
        with patch.object(carts,'_run',side_effect=run),patch.object(carts,'_videos',return_value=[]), \
             patch.object(carts,'_debug_coverage',return_value=[{'scene':name}]) as coverage:
            result=carts.verify(self.output,self.selection,{})
            self.assertFalse(result['issues'],result)
            self.assertEqual(set(commands),{'aabb','body','pants','interruption-fast'})
            self.assertIn('--fast',commands['interruption-fast'])
            self.assertEqual(commands['interruption-fast'][-2:],['--scene',name])
            self.assertTrue(result['evidence']['interruption']['functionalPass'])
            self.assertTrue(result['outcomes'][0]['outcome']['partialCoverage'])
            self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
            coverage.assert_called_once()
            # A native completed action cannot be accepted as cancellation merely because this is debug mode.
            start=100000+fixture.analyzer.FAST_CASES.index(name)*25000
            row=next(row for row in lifecycle if start<=row['wallTimeMillis']<start+20000 and row['event']=='stop')
            row['event']='complete';coverage.reset_mock()
            (cache/'action-lifecycle.jsonl').write_text('\n'.join(map(json.dumps,lifecycle)))
            failed=carts.verify(self.output,self.selection,{})
            self.assertTrue(failed['issues']);self.assertEqual(failed['outcomes'][0]['status'],'failed')
            coverage.assert_not_called()

    def test_interruption_adapter_requires_native_stop_retry_and_first_render_receipts(self):
        for case, matrix in [('interruption', False), ('interruption-matrix', True), ('interruption-fast', False)]:
            self.selection['cases'] = [case]
            fixture = carts._load(ROOT / 'tests/test_cart_interruption.py')
            text, lifecycle, body, grip, world, draws, tail = fixture.fixture(matrix=matrix,fast=case=='interruption-fast')
            cache = self.output / 'client1'
            (self.output / 'client1-launch.log').write_text(text)
            (self.output / 'runtime.json').write_text(json.dumps(self.runtime))
            for filename, rows in [('action-lifecycle.jsonl', lifecycle), ('body-clearance.jsonl', body),
                                   ('wood-grip-poses.jsonl', grip), ('world-cart-poses.jsonl', world),
                                   ('wheel-roll-draws.jsonl', draws), ('action-tail-poses.jsonl', tail)]:
                (cache / filename).write_text('\n'.join(map(json.dumps, rows)))
            original_run = carts._run
            commands = []
            def run(command, directory, name):
                commands.append(name)
                return original_run(command, directory, name) if name == case else {'exit_code': 0}
            with patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
                result = carts.verify(self.output, self.selection, {})
                self.assertFalse(result['issues'], result['issues'])
                self.assertTrue(result['evidence']['interruption']['functionalPass'])
                self.assertEqual(set(commands), {'aabb', 'body', 'pants', case})
                self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
                lifecycle[1]['event'] = 'complete'
                (cache / 'action-lifecycle.jsonl').write_text('\n'.join(map(json.dumps, lifecycle)))
                result = carts.verify(self.output, self.selection, {})
                self.assertTrue(result['issues'])
                self.assertEqual(result['outcomes'][0]['status'], 'failed')

    def test_repeat_adapter_requires_clock_recovery_and_wheel_gates(self):
        self.selection['cases'] = ['repeat']
        (self.output / 'client1-launch.log').write_text('[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] ALL_COMPLETE cases=12\n')
        (self.output / 'runtime.json').write_text(json.dumps(self.runtime))
        required = ('functionalPass', 'clockVerified', 'recoveryVerified', 'wheelCoverageVerified')
        for failure in (None, *required):
            commands = []
            def run(command, directory, name):
                commands.append(name)
                if name == 'repeat':
                    self.assertIn('analyze-repeat.py', command[1])
                    self.assertIn('--profile', command)
                    report = dict.fromkeys(required, True)
                    if failure: report[failure] = False
                    report['failures'] = [failure] if failure else []
                    Path(command[command.index('--output')+1]).write_text(json.dumps(report))
                return {'exit_code': int(bool(failure)) if name == 'repeat' else 0}
            with self.subTest(failure=failure), patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
                result = carts.verify(self.output, self.selection, {})
                self.assertEqual(bool(result['issues']), bool(failure))
                self.assertEqual(result['outcomes'][0]['status'], 'failed' if failure else 'captured')
                self.assertEqual(set(commands), {'aabb', 'body', 'pants', 'repeat'})
                self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])

    def test_hotkey_case_stages_native_event_and_requires_mp_actions(self):
        self.selection['cases'] = ['hotkey']
        carts.validate(self.selection)
        self.stage()
        text = Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']).read_text()
        self.assertIn('["hotkeySetdown"]=true', text)
        self.assertIn('["rapidRepeats"]=true', text)
        self.selection.update(suite=carts.MP, cases=['owner_observer_motion'], kind='mp', languages=['EN', 'RU'])
        self.options['cart_hotkey_setdown'] = True
        with self.assertRaisesRegex(ValueError, 'requires cart_actions'):
            carts.validate(self.selection)
        self.options['cart_actions'] = True
        self.options['cart_hotkey_key'] = 100
        carts.validate(self.selection)
        for bad in (0, -1, 256, True, '100'):
            self.options['cart_hotkey_key'] = bad
            with self.assertRaisesRegex(ValueError, 'key code'):
                carts.validate(self.selection)
        self.options['cart_hotkey_key'] = 100
        self.options['cart_hotkey_setdown'] = 'true'
        with self.assertRaisesRegex(ValueError, 'boolean'):
            carts.validate(self.selection)

    def test_native_e_stages_without_geometry_probes_and_validates_strict_receipts(self):
        self.selection['cases'] = ['native-e']; self.options.pop('mesh_fbx')
        self.assertEqual(carts.scene_names('native-e'), ['native-e'])
        self.assertEqual(self.stage().call_count, 1)
        self.assertEqual(self.runtime['fixture']['attach']['client1'], [])
        source = Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']).read_text()
        self.assertIn("cartLabKeyState(Keyboard.KEY_E,true)", source)
        self.assertNotIn('p:doContext()', source)
        records = []
        for phase in carts.NATIVE_E_PHASES:
            native = phase in ('native-before', 'native-after')
            ground = phase not in ('pickup', 'pickup-repeat')
            records.append(dict(phase=phase, id=42, cargoID=99, cargoWeight=1, cargoType='Base.Log', key=18, doorOpen=native,
                capturedSeen=not native, ignoreRestored=True, nativeDownSeen=True,
                inventoryCount=int(not ground), worldCount=int(ground), primaryID=-1 if ground else 42,
                secondaryID=-1 if ground else 42, luaActions=0, nativeActions=0, hasPath=False,
                cancelled=phase=='pickup-cancel', elapsed=1200, longSeen=phase=='drop-long'))
        def log(rows): return '\n'.join('[CART_NATIVE_E] RECEIPT ' + json.dumps(row) for row in rows)
        self.assertTrue(carts._native_e_coverage(log(records))['nativeEVerified'])
        for index, field, value in ((0,'doorOpen',False),(1,'doorOpen',True),(1,'nativeDownSeen',False),(1,'capturedSeen',None),(1,'cargoWeight',2),
                (2,'longSeen',False),(3,'cancelled',False),(4,'id',43),(5,'worldCount',2),
                (6,'ignoreRestored',False),(6,'key',47)):
            with self.subTest(index=index, field=field):
                bad = [dict(row) for row in records];bad[index][field]=value
                with self.assertRaises(ValueError): carts._native_e_coverage(log(bad))
        with self.assertRaises(ValueError): carts._native_e_coverage(log(records[:-1]))
        with self.assertRaises(ValueError): carts._native_e_coverage(log(records+records[-1:]))

    def test_missing_candidates_and_native_mode_are_rejected(self):
        self.selection['mode'] = 'native'
        with self.assertRaisesRegex(ValueError, 'toolkit mode'):
            carts.validate(self.selection)
        self.selection['mode'] = 'toolkit'
        self.selection['options']['mod_sources'].pop('PZSurvivorToolkit')
        with self.assertRaisesRegex(ValueError, 'Explicit candidate'):
            carts.validate(self.selection)

    def test_missing_numpy_fails_before_cart_fixture_compilation(self):
        with patch.object(carts.importlib, 'import_module', side_effect=ModuleNotFoundError('numpy')) as dependency, \
             patch.object(carts, '_compile') as compiler:
            with self.assertRaisesRegex(ValueError, 'NumPy in ' + re.escape(sys.executable)):
                self.stage()
        dependency.assert_called_once_with('numpy')
        compiler.assert_not_called()
        self.assertFalse((self.output / 'cart-build').exists())

    def test_mp_analysis_does_not_require_numpy(self):
        self.selection.update(suite=carts.MP, cases=['owner_observer_motion'], kind='mp', languages=['EN', 'RU'])
        with patch.object(carts.importlib, 'import_module', side_effect=ModuleNotFoundError('numpy')) as dependency:
            carts.validate(self.selection)
        dependency.assert_not_called()

    def test_scene_catalog_matches_every_lua_bank_and_selected_order(self):
        lua=shutil.which('luajit') or shutil.which('lua')
        if not lua: self.skipTest('Lua interpreter unavailable')
        intake=ROOT/'tests/native_queue/contributions/wooden_cart_motion'
        for bank,(source,count) in carts.SP_CASES.items():
            full=carts.scene_names(bank)
            self.assertEqual(len(full),count,bank)
            self.assertEqual(len(set(full)),count,bank)
            if bank=='manual': continue
            text=(intake/source).read_text()
            start=text.index('local specs=') if bank == 'obstacle-matrix' else text.index('local cases=')
            marker='cases=CartLabSelectScenes(cases)'
            body=text[start:text.index(marker,start)+len(marker)]
            flags=dict(disposable=True,footprint=bank in ('collision','footprint','brace','fast-slide','wall-exit','wall-manual-exit','wall-fast-manual-exit'),vehicles=bank=='vehicles',brace=bank=='brace',fastSlide=bank=='fast-slide',wallExit=bank in ('wall-exit','wall-manual-exit','wall-fast-manual-exit'),wallManualExit=bank in ('wall-manual-exit','wall-fast-manual-exit'),wallFastManualExit=bank=='wall-fast-manual-exit',
                       wheelCycle=bank=='wheel',interruptions=bank in ('interruption','interruption-matrix','interruption-fast'),fastInterruptions=bank=='interruption-fast',
                       interruptionMatrix=bank=='interruption-matrix',rapidRepeats=bank in ('repeat','hotkey'),stopTiming=bank=='stop-timing',impact=bank=='impact')
            from queue_checks.native import _lua
            for chosen in (None,[full[-1],full[0]] if count>1 else [full[0]]):
                if chosen: flags['scenes']=chosen
                code='CartMotionConfig='+_lua(flags)+';local config=CartMotionConfig;local footprint=config.footprint==true;local brace=config.brace==true;local fastSlide=config.fastSlide==true;local wallExit=config.wallExit==true;local wallManualExit=config.wallManualExit==true;local wallFastManualExit=config.wallFastManualExit==true;dofile('+json.dumps(str(intake/'scene-selection.lua'))+');'+body+(';for _,c in ipairs(cases) do assert(c.female==(c.name:sub(1,7)==\"female-\"), \"scene sex metadata differs\") end' if bank in ('wall-manual-exit','wall-fast-manual-exit') else '')+';for _,c in ipairs(cases) do print(c.name) end'
                result=subprocess.run([lua,'-e',code],check=True,text=True,capture_output=True)
                self.assertEqual(result.stdout.splitlines(),[n for n in full if chosen is None or n in chosen],bank)

    def test_fast_manual_runway_pose_is_mirrored_and_bare_controls_stay_centered(self):
        lua=shutil.which('luajit') or shutil.which('lua')
        if not lua:self.skipTest('Lua interpreter unavailable')
        source=(ROOT/'tests/native_queue/contributions/wooden_cart_motion/scenario-collision.lua').read_text()
        pose=source[source.index('local function pose('):source.index('local function sprinting(')]
        pose_case=source[source.index('local function poseCase('):source.index('local function reverseDrive(')]
        control_block=source[source.index("if mode=='control-layout' then\n"):]
        control_pose=next(line.strip() for line in control_block.splitlines() if line.strip().startswith('pose('))
        code="""
local p={}
for _,axis in ipairs({'X','Y','Z','NextX','NextY','LastX','LastY'}) do
 p['set'..axis]=function(self,value) self[axis]=value end
end
for _,method in ipairs({'ensureOnTile','setCurrentSquareFromPosition','setMovingSquareNow'}) do p[method]=function() end end
local CartTestArea={x=103.5,y=200.5,z=7,checkPosition=function() end}
local wallX,southY=100,202
local cases,phase={{spec='wall-slide',startYaw=0}},1
local wallExit,brace,footprint=true,false,true
local config={impact=false}
local function cartLabPoseHeading() end
local function controlHeading() return 0 end
"""+pose+pose_case+"""
for _,fast in ipairs({false,true}) do
 wallFastManualExit=fast
 for _,spec in ipairs({'wall-slide','wall-slide-right'}) do
  cases[1].spec=spec;poseCase()
  print('cart',tostring(fast),spec,p.X,p.Y,p.Z)
 end
 for _,kind in ipairs({'wall','corner','passage','wall-slide-left','wall-slide-right'}) do
 """+control_pose+"""
  print('control',tostring(fast),kind,p.X,p.Y,p.Z)
 end
end
"""
        result=subprocess.run([lua,'-e',code],check=True,text=True,capture_output=True)
        rows=[line.split() for line in result.stdout.splitlines()]
        self.assertEqual(len(rows),14)
        for kind,fast,spec,x,y,z in rows:
            expected_y=(220.5 if spec.endswith('right') else 180.5) if kind=='cart' and fast=='true' else 200.5
            with self.subTest(kind=kind,fast=fast,spec=spec):
                self.assertEqual(tuple(map(float,(x,y,z))),(102.8 if kind=='cart' else 103.5,expected_y,7.))

    def test_scene_selection_is_strict_and_is_staged_in_snapshot_order(self):
        self.selection['cases']=['path']
        for bad in (None,[],True,'male-full-corner',['unknown'],['male-full-corner']*2,[2],['male-full-yaw0']):
            self.options['cart_scenes']=bad
            with self.subTest(bad=bad),self.assertRaisesRegex(ValueError,'cart_scenes'):
                carts.validate(self.selection)
        self.options['cart_scenes']=['female-full-corner','male-empty-cancel']
        self.stage()
        text=Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']).read_text()
        self.assertIn('["scenes"]={"male-empty-cancel","female-full-corner"}',text)
        self.assertLess(text.index('function CartLabSelectScenes'),text.index('local cases='))
        log='[WOOD_BANK] RUN_STARTED\n'+''.join('[WOOD_BANK] COMPLETE '+n+' wall=100\n' for n in carts.selected_scenes(self.selection))+'[WOOD_BANK] ALL_COMPLETE cases=2'
        self.assertTrue(carts.complete(self.selection,'client1',log))
        self.assertFalse(carts.complete(self.selection,'client1',log.replace('male-empty-cancel','male-full-cancel')))
        self.assertFalse(carts.complete(self.selection,'client1',log.replace('cases=2','cases=24')))
        self.selection.update(suite=carts.MP,cases=['owner_observer_motion'],kind='mp',languages=['EN','RU'])
        with self.assertRaisesRegex(ValueError,'SP cart'): carts.validate(self.selection)

    def test_female_manual_banks_stage_only_exact_selected_scenes(self):
        for bank,count in (('wall-manual-exit',8),('wall-fast-manual-exit',16)):
            self.output=self.root/bank;self.output.mkdir();self.role('client1')
            self.selection['cases']=[bank]
            names=[name for name in carts.scene_names(bank) if name.startswith('female-')]
            self.assertEqual(len(names),count)
            self.options['cart_scenes']=list(reversed(names))
            carts.validate(self.selection)
            self.assertEqual(carts.selected_scenes(self.selection),names)
            self.stage()
            text=Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']).read_text()
            self.assertIn('["scenes"]={'+','.join(json.dumps(name) for name in names)+'}',text)
            self.assertNotIn('\"male-empty-',text.splitlines()[0])
            self.assertNotIn('\"male-full-',text.splitlines()[0])

    def test_direct_fast_walk_requires_boolean_in_sp_sprint(self):
        self.selection['cases'] = ['sprint']
        for value in (False, True):
            self.options['cart_direct_fast_walk'] = value
            carts.validate(self.selection)
        for value in ('true', 1, None):
            self.options['cart_direct_fast_walk'] = value
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, 'cart_direct_fast_walk'):
                carts.validate(self.selection)
        for value in (False, True):
            self.options['cart_direct_fast_walk'] = value
            self.selection['cases'] = ['reverse']
            with self.assertRaisesRegex(ValueError, 'SP sprint'):
                carts.validate(self.selection)
            self.selection.update(suite=carts.MP, cases=['owner_observer_motion'], kind='mp', languages=['EN', 'RU'])
            with self.assertRaisesRegex(ValueError, 'SP sprint'):
                carts.validate(self.selection)
            self.selection.update(suite=carts.SP, cases=['sprint'], kind='sp', languages=['RU'])

    def test_direct_fast_walk_stages_default_false_and_preserves_scene_ids(self):
        self.selection['cases'] = ['sprint']
        names = carts.scene_names('sprint')
        self.assertEqual(len(names), 16)
        gait_names = ['male-empty-gait-left', 'male-full-gait-right',
                      'female-empty-gait-left', 'female-full-gait-right']
        self.assertEqual([name for name in names if '-gait-' in name], gait_names)
        for index, value in enumerate((None, False, True)):
            with self.subTest(value=value):
                self.output = self.root / ('direct-fast-walk-' + str(index))
                self.output.mkdir()
                self.role('client1')
                self.runtime.pop('fixture', None)
                if value is None:
                    self.options.pop('cart_direct_fast_walk', None)
                else:
                    self.options['cart_direct_fast_walk'] = value
                self.options['cart_scenes'] = gait_names
                self.stage()
                text = Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']).read_text()
                self.assertIn('["directFastWalk"]=' + str(value is True).lower(), text.splitlines()[0])
                self.assertEqual(carts.selected_scenes(self.selection), gait_names)
                self.assertEqual(carts.scene_names('sprint'), names)
                paths = carts.sources(ROOT, self.selection)
                self.assertIn(Path(carts.__file__), paths)
                self.assertIn(ROOT / 'tests/native_queue/contributions/wooden_cart_motion/scenario-clips.lua', paths)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT required for actual sprint bank plan')
    def test_direct_fast_walk_changes_only_two_gait_steps_in_actual_lua_plan(self):
        source = (ROOT / 'tests/native_queue/contributions/wooden_cart_motion/scenario-clips.lua').read_text()
        plan = source[source.index('local cases={}'):source.index('cases=CartLabSelectScenes(cases)')]
        script = r'''
local chunk=ACTUAL_PLAN..'\nreturn cases'
local function plan(config)
 local loader=assert(loadstring(chunk))
 setfenv(loader,{config=config,ipairs=ipairs,assert=assert})
 return loader()
end
local default,disabled,enabled=plan({}),plan({directFastWalk=false}),plan({directFastWalk=true})
assert(#default==16 and #disabled==16 and #enabled==16)
local changed=0
for i,original in ipairs(default) do
 local off,on=disabled[i],enabled[i]
 assert(original.name==off.name and original.name==on.name,'scene ID changed')
 assert(#original.steps==#off.steps and #original.steps==#on.steps)
 local seen={}
 for j,step in ipairs(original.steps) do
  for field=1,3 do
   assert(off.steps[j][field]==step[field],'explicit false changed default plan')
   local expected=step[field]
   if original.spec=='gait' and field==2 and step[1]==6300 then expected=0;changed=changed+1 end
   if original.spec=='gait' and field==2 and step[1]==8500 then expected=1;changed=changed+1 end
   assert(on.steps[j][field]==expected,'unexpected schedule change: '..original.name)
  end
  if on.steps[j][2]~=nil then seen[on.steps[j][2]]=true end
 end
 if original.spec=='gait' then
  assert(seen[0] and seen[1] and seen[2],'gait coverage lost')
  assert(on.steps[2][2]==1 and on.steps[3][2]==2 and on.steps[5][2]==0 and on.steps[6][2]==1)
  assert(on.steps[#on.steps][3]==0,'final stop lost')
 end
end
assert(changed==8,'expected two changed steps in each of four gait scenes')
print('PASS actual sprint plan default/false/direct with unchanged scene IDs')
'''.replace('ACTUAL_PLAN', json.dumps(plan))
        result = subprocess.run([shutil.which('luajit'), '-'], input=script, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS actual sprint plan', result.stdout)

    def test_authored_clip_pilot_is_explicit_sp_boolean(self):
        for bad in ('true', 1, None):
            self.options['cart_authored_clip']=bad
            with self.subTest(bad=bad), self.assertRaisesRegex(ValueError,'SP boolean'):
                carts.validate(self.selection)
        self.selection['cases']=['interaction']
        self.options['cart_authored_clip']=True
        self.stage()
        text=Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']).read_text()
        self.assertIn('["authoredClip"]=true',text)
        self.assertIn("if config.authoredClip~=nil then player:setVariable('ToolkitWoodCartClipPilot',config.authoredClip) end",text)
        self.selection.update(suite=carts.MP,cases=['owner_observer_motion'],kind='mp',languages=['EN','RU'])
        with self.assertRaisesRegex(ValueError,'SP boolean'): carts.validate(self.selection)

    def test_authored_clip_explicit_false_keeps_legacy_comparison(self):
        self.options['cart_authored_clip']=False
        self.stage()
        text=Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']).read_text()
        self.assertIn('["authoredClip"]=false',text)

    def test_missing_authored_clip_option_preserves_production_default(self):
        self.stage()
        text=Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']).read_text()
        self.assertNotIn('["authoredClip"]=',text)

    def test_selected_scene_capture_keeps_diagnostics_and_explicit_partial_scope(self):
        self.selection['cases']=['path'];self.options['cart_scenes']=['male-full-corner']
        cache=self.output/'client1';(self.output/'runtime.json').write_text(json.dumps(self.runtime))
        text='[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] COMPLETE male-full-corner wall=1000 file=owned.mp4 frames=361 seconds=12.033\n[WOOD_BANK] ALL_COMPLETE cases=1'
        (self.output/'client1-launch.log').write_text(text)
        body=[dict(wallTimeMillis=1000+i*100,cart=[1.]*16,female=False) for i in range(120)]
        grip=[dict(wallTimeMillis=1000+i*100,result=i!=4) for i in range(120)]
        for file,rows in [('body-clearance.jsonl',body),('wood-grip-poses.jsonl',grip)]:
            (cache/file).write_text(''.join(json.dumps(r)+'\n' for r in rows))
        data=b'calibrated';(cache/'WheelbarrowWood.bin').write_bytes(data)
        (cache/'wood-wheel-mesh-proof.json').write_text(json.dumps(dict(matchesOriginal=True,proofAfterPhaseChanged=True,bytes=len(data),sha256=hashlib.sha256(data).hexdigest())))
        calls=[]
        def run(command,directory,name):
            calls.append(name)
            if name=='native':
                self.assertIn('--scenes',command)
                self.assertNotIn('--partial',command)
                contract=json.loads(Path(command[command.index('--scenes')+1]).read_text())
                self.assertEqual([r['name'] for r in contract['scenes']],['male-full-corner'])
                self.assertEqual(contract['scenes'][0]['measurementEndMs'],11800)
                metrics={'cases':[dict(case='male-full-corner',gripSamples=120,wheelFloorMaxError=.01,body={'samples':120},pants={'samples':120})]}
                (directory/'native-metrics.json').write_text(json.dumps(metrics))
            return dict(exit_code=1 if name=='pants' else 0)
        with patch.object(carts,'_run',side_effect=run),patch.object(carts,'_videos',return_value=[]):
            result=carts.verify(self.output,self.selection,{})
            self.assertFalse(result['issues'],result)
            self.assertEqual(calls,['aabb','body','pants','native'])
            self.assertTrue(result['outcomes'][0]['outcome']['partialCoverage'])
            self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
            self.assertTrue(result['evidence']['diagnosticOnly'])
            self.assertEqual(result['evidence']['sceneProbes'][0]['gripFailures'],1)
            self.assertEqual(result['evidence']['fullSceneCount'],24)
            for failure in ('empty','wrong-body','nonfinite','sparse'):
                rows=json.loads(json.dumps(body))
                if failure=='empty': rows=[]
                if failure=='wrong-body': rows[0]['female']=True
                if failure=='nonfinite': rows[0]['cart'][0]=float('nan')
                if failure=='sparse': rows=rows[:6]
                (cache/'body-clearance.jsonl').write_text(''.join(json.dumps(r)+'\n' for r in rows))
                with self.subTest(failure=failure):
                    failed=carts.verify(self.output,self.selection,{})
                    self.assertTrue(failed['issues'])
                    self.assertTrue(failed['outcomes'][0]['outcome']['partialCoverage'])

    def test_action_debug_requires_pose_coverage_only_during_rendered_and_held_phases(self):
        self.selection['cases']=['interaction'];self.options['cart_scenes']=['male-empty-yaw0']
        cache=self.output/'client1';name='male-empty-yaw0';start=100000
        records=[dict(case=name,start=start,wall=start+t,elapsed=t,id=1,female=False,
                      rendered=1000<=t<=6000,heldID=1 if 3000<=t<=7000 else -1,
                      ToolkitCartMotion=3500<=t<=7000) for t in range(0,16001,100)]
        body=[dict(wallTimeMillis=start+t,cart=[1.]*16,female=False) for t in range(1000,7001,100)]
        grip=[dict(wallTimeMillis=start+t,result=True) for t in range(6100,7001,100)]
        data=b'calibrated static mesh';(cache/'WheelbarrowWood.bin').write_bytes(data)
        (cache/'wood-wheel-mesh-proof.json').write_text(json.dumps(dict(matchesOriginal=True,proofAfterPhaseChanged=False,bytes=len(data),sha256=hashlib.sha256(data).hexdigest())))
        for failure in (None,'body-gap','grip-gap','telemetry-gap','short-tail','missing-held-phase'):
            rows=[dict(r) for r in records]
            poses=list(body);hands=list(grip)
            if failure=='body-gap': poses=poses[:6]
            if failure=='grip-gap': hands=hands[:6]
            if failure=='telemetry-gap': rows=[r for r in rows if not 6000<r['elapsed']<10000]
            if failure=='short-tail': rows=rows[:80]
            if failure=='missing-held-phase':
                for row in rows: row['ToolkitCartMotion']=False
            for file,values in [('body-clearance.jsonl',poses),('wood-grip-poses.jsonl',hands)]:
                (cache/file).write_text(''.join(json.dumps(r)+'\n' for r in values))
            text='[WOOD_BANK] RUN_STARTED\n'+''.join('[WOOD_INTERACTION_SAMPLE] '+json.dumps(r)+'\n' for r in rows)
            text+='[WOOD_BANK] COMPLETE '+name+' wall=100000 file=owned.mp4 frames=481 seconds=16.033\n[WOOD_BANK] ALL_COMPLETE cases=1'
            with self.subTest(failure=failure):
                if failure:
                    with self.assertRaises(ValueError): carts._debug_coverage(cache,text,self.selection)
                else:
                    self.assertEqual(carts._debug_coverage(cache,text,self.selection)[0]['scene'],name)

    def test_unknown_or_combined_sp_cases_are_rejected(self):
        for cases in (['unknown'], ['stop', 'reversal']):
            self.selection['cases'] = cases
            with self.assertRaisesRegex(ValueError, 'one capture case'):
                carts.validate(self.selection)

    def test_mp_exact_analyzer_preserves_captured_and_rejects_render_window_gap(self):
        intake = ROOT / 'tests/native_queue/contributions/wooden_cart_multiplayer'
        fixture = carts._load(intake / 'self_check.py')
        self.temp.cleanup()
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name).resolve()
        fixture.fixture(self.output)
        self.selection.update(suite=carts.MP, cases=['owner_observer_motion'], kind='mp', languages=['EN', 'RU'])
        (self.output / 'selection.json').write_text(json.dumps(dict(self.selection)))
        for role in ('client1', 'client2'):
            path = self.output / (role + '-launch.log')
            path.write_text(path.read_text() + '\n[CART_MP] VIDEO_FINAL {}\n')
        with patch.object(carts, '_videos', return_value=[]):
            result = carts.verify(self.output, self.selection, {})
            self.assertFalse(result['issues'])
            self.assertTrue(all(row['status'] == 'captured' and row['outcome']['animationEquivalencePass'] is False for row in result['outcomes']))
            pose = self.output / 'client2/body-clearance.jsonl'
            rows = [json.loads(line) for line in pose.read_text().splitlines()]
            pose.write_text('\n'.join(json.dumps(row) for row in rows if not 110500 <= row['wallTimeMillis'] <= 111500))
            result = carts.verify(self.output, self.selection, {})
            self.assertTrue(result['issues'])
            self.assertTrue(all(row['status'] == 'failed' for row in result['outcomes']))

    def coverage_fixture(self, count=20, text=None, end_ms=11800):
        cache = self.output / 'client1'
        if text is None:
            text = '[WOOD_BANK] RUN_STARTED\n' + ''.join(
                f'[WOOD_BANK] COMPLETE case-{index} wall={100000 + index * 15000}\n' for index in range(count))
        samples, metrics = [], {'cases': []}
        for name, start in re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)', text):
            start = int(start)
            times=range(900,end_ms-200,500)
            samples += [{'wallTimeMillis': start + elapsed} for elapsed in times]
            metrics['cases'].append(dict(case=name, measurementEndAfterCaseMs=end_ms, gripSamples=len(times),
                                        wheelFloorMaxError=.1, body={'samples':len(times)}, pants={'samples':len(times)}))
        for name in ('body-clearance.jsonl', 'wood-grip-poses.jsonl'):
            (cache / name).write_text('\n'.join(map(json.dumps, samples)))
        native = b'actual native test bytes'
        (cache / 'WheelbarrowWood.bin').write_bytes(native)
        (cache / 'wood-wheel-mesh-proof.json').write_text(json.dumps(dict(matchesOriginal=True, proofAfterPhaseChanged=True, bytes=len(native), sha256=hashlib.sha256(native).hexdigest())))
        return text, samples, metrics

    def test_sp_coverage_requires_each_probe_window_and_mesh_presence(self):
        cache = self.output / 'client1'
        text, samples, metrics = self.coverage_fixture()
        carts._coverage(cache, text, 20, metrics)
        metrics['cases'][7]['pants']['samples'] = 0
        with self.assertRaisesRegex(ValueError, 'pose/mesh'):
            carts._coverage(cache, text, 20, metrics)
        metrics['cases'][7]['pants']['samples'] = 22
        (cache / 'wood-grip-poses.jsonl').write_text('\n'.join(map(json.dumps, samples[22:])))
        with self.assertRaisesRegex(ValueError, 'probe window'):
            carts._coverage(cache, text, 20, metrics)

    def test_same_tick_duplicate_probes_do_not_establish_window_coverage(self):
        text, samples, metrics = self.coverage_fixture(1)
        repeated = [samples[0]] * 100
        (self.output / 'client1/wood-grip-poses.jsonl').write_text('\n'.join(map(json.dumps, repeated)))
        with self.assertRaisesRegex(ValueError, 'probe window'):
            carts._coverage(self.output / 'client1', text, 1, metrics)

    def test_vehicle_native_metrics_include_late_grip_and_clothing_failures(self):
        cache = self.output / 'client1'
        names = ('male-full-vehicle-yaw0-slide-left', 'male-full-vehicle-yaw0-front')
        log = self.output / 'client1-launch.log'
        log.write_text('[WOOD_BANK] RUN_STARTED\n' + ''.join(
            f'[WOOD_BANK] CASE {name} attempt=0 wall={start}\n[WOOD_BANK] COMPLETE {name} wall={start}\n'
            for name, start in zip(names, (100000,130000))))
        matrix = [0.] * 16; matrix[13] = .008
        (cache / 'body-clearance.jsonl').write_text('\n'.join(json.dumps(dict(wallTimeMillis=at,cart=matrix)) for at in (113000,143000)))
        (cache / 'wood-grip-poses.jsonl').write_text('\n'.join(json.dumps(dict(wallTimeMillis=at,result=False)) for at in (113000,143000)))
        columns = ['spineRootOrientationMaxDelta','spineRootDx','spineRootDy','spineRootDz','maxLegMatrixDelta',
                   'leftArmLengthBefore','leftArmLengthAfter','rightArmLengthBefore','rightArmLengthAfter','contactLocalY']
        (cache / 'wood-wheel-native.csv').write_text('event,'+','.join(columns)+'\ngrounding,'+','.join('0' for _ in columns)+'\n')
        script = ROOT / 'tests/native_queue/contributions/wooden_cart_motion/evidence/analyze-native.py'
        for extended in (False,True):
            output = self.root / ('extended' if extended else 'legacy'); output.mkdir()
            for kind in ('hip','pants'):
                (output / (kind+'-triangle-frames.json')).write_text(json.dumps([
                    dict(time=at,L=int(kind=='pants'),R=0) for at in (113000,143000)]))
            subprocess.run([sys.executable,str(script),'--profile',str(cache),'--log',str(log),'--output',str(output),'--partial']
                           + (['--vehicles'] if extended else []),check=True,capture_output=True)
            metrics = json.loads((output / 'native-metrics.json').read_text())
            slide, front = metrics['cases']
            self.assertEqual(slide['measurementEndAfterCaseMs'],14800 if extended else 11800)
            self.assertEqual(slide['gripFailures'],int(extended))
            self.assertEqual(slide['failureStages'],{'vehicle-reverse':1} if extended else {})
            self.assertEqual(slide['pants']['shaftIntersections']['L'],int(extended))
            self.assertEqual(front['measurementEndAfterCaseMs'],11800)
            self.assertEqual(front['gripSamples'],0)

        log.write_text(log.read_text().replace(names[0],'male-full-wall-release').replace(names[1],'female-full-wall-restart'))
        times=(117000,147000)
        (cache / 'body-clearance.jsonl').write_text('\n'.join(json.dumps(dict(wallTimeMillis=at,cart=matrix)) for at in times))
        (cache / 'wood-grip-poses.jsonl').write_text('\n'.join(json.dumps(dict(wallTimeMillis=at,result=False)) for at in times))
        output=self.root / 'brace';output.mkdir()
        for kind in ('hip','pants'):
            (output / (kind+'-triangle-frames.json')).write_text(json.dumps([
                dict(time=at,L=int(kind=='pants'),R=0) for at in times]))
        command=[sys.executable,str(script),'--profile',str(cache),'--log',str(log),'--output',str(output),'--partial','--brace']
        subprocess.run(command,check=True,capture_output=True)
        metrics=json.loads((output / 'native-metrics.json').read_text())
        self.assertEqual(metrics['gripFailures'],2)
        for row in metrics['cases']:
            self.assertEqual(row['measurementEndAfterCaseMs'],17800)
            self.assertEqual(row['gripFailures'],1)
            self.assertEqual(row['failureStages'],{'release':1})
            self.assertEqual(row['pants']['shaftIntersections']['L'],1)
        invalid=subprocess.run(command+['--vehicles'],capture_output=True)
        self.assertNotEqual(invalid.returncode,0)
        self.assertIn(b'not allowed with argument',invalid.stderr)

    def test_slide_and_exit_native_metrics_label_contact_and_later_failures(self):
        cache=self.output / 'client1'
        names=('male-full-sprint-wall-slide','female-empty-run-wall-slide-right')
        log=self.output / 'client1-launch.log'
        log.write_text('[WOOD_BANK] RUN_STARTED\n'+''.join(
            f'[WOOD_BANK] CASE {name} attempt=0 wall={at}\n[WOOD_BANK] COMPLETE {name} wall={at}\n'
            for name,at in zip(names,(100000,130000))))
        times=(103000,138000)
        matrix=[0.]*16;matrix[13]=.008
        (cache / 'body-clearance.jsonl').write_text('\n'.join(json.dumps(dict(wallTimeMillis=t,cart=matrix))for t in times))
        (cache / 'wood-grip-poses.jsonl').write_text('\n'.join(json.dumps(dict(wallTimeMillis=t,result=False))for t in times))
        columns=['spineRootOrientationMaxDelta','spineRootDx','spineRootDy','spineRootDz','maxLegMatrixDelta',
                 'leftArmLengthBefore','leftArmLengthAfter','rightArmLengthBefore','rightArmLengthAfter','contactLocalY']
        (cache / 'wood-wheel-native.csv').write_text('event,'+','.join(columns)+'\ngrounding,'+','.join('0'for _ in columns)+'\n')
        output=self.root / 'fast-slide';output.mkdir()
        for kind in ('hip','pants'):
            (output / (kind+'-triangle-frames.json')).write_text(json.dumps([dict(time=t,L=1,R=0)for t in times]))
        script=ROOT / 'tests/native_queue/contributions/wooden_cart_motion/evidence/analyze-native.py'
        command=[sys.executable,str(script),'--profile',str(cache),'--log',str(log),'--output',str(output),'--partial','--fast-slide']
        subprocess.run(command,check=True,capture_output=True)
        metrics=json.loads((output / 'native-metrics.json').read_text())
        self.assertEqual(metrics['gripFailures'],2)
        self.assertEqual([r['failureStages']for r in metrics['cases']],[{'wall-slide':1},{'reverse':1}])
        for row in metrics['cases']:
            self.assertEqual(row['measurementEndAfterCaseMs'],11800)
            self.assertEqual(row['pants']['shaftIntersections']['L'],1)
        invalid=subprocess.run(command+['--brace'],capture_output=True)
        self.assertNotEqual(invalid.returncode,0)
        self.assertIn(b'not allowed with argument',invalid.stderr)

        log.write_text(log.read_text().replace(names[0],names[0]+'-out90').replace(names[1],'male-empty-run-wall-slide-right-out45'))
        output=self.root / 'wall-exit';output.mkdir()
        for kind in ('hip','pants'):
            (output / (kind+'-triangle-frames.json')).write_text(json.dumps([dict(time=t,L=1,R=0)for t in times]))
        exit_command=[sys.executable,str(script),'--profile',str(cache),'--log',str(log),'--output',str(output),'--partial','--wall-exit']
        subprocess.run(exit_command,check=True,capture_output=True)
        metrics=json.loads((output / 'native-metrics.json').read_text())
        self.assertEqual(metrics['gripFailures'],2)
        self.assertEqual([r['failureStages']for r in metrics['cases']],[{'wall-slide':1},{'turn-out':1}])
        for row in metrics['cases']:
            self.assertEqual(row['measurementEndAfterCaseMs'],11800)
            self.assertEqual(row['pants']['shaftIntersections']['L'],1)
        invalid=subprocess.run(exit_command+['--fast-slide'],capture_output=True)
        self.assertNotEqual(invalid.returncode,0)
        self.assertIn(b'not allowed with argument',invalid.stderr)

        manual_names=('male-full-walk-wall-slide-manual-out90','male-empty-walk-wall-slide-right-manual-out45')
        log.write_text('[WOOD_BANK] RUN_STARTED\n'+''.join(
            f'[WOOD_BANK] CASE {name} attempt=0 wall={at}\n[WOOD_BANK] COMPLETE {name} wall={at}\n'
            for name,at in zip(manual_names,(100000,130000))))
        times=(128000,158000)
        (cache / 'body-clearance.jsonl').write_text('\n'.join(json.dumps(dict(wallTimeMillis=t,cart=matrix))for t in times))
        (cache / 'wood-grip-poses.jsonl').write_text('\n'.join(json.dumps(dict(wallTimeMillis=t,result=False))for t in times))
        output=self.root / 'wall-manual-exit';output.mkdir()
        for kind in ('hip','pants'):
            (output / (kind+'-triangle-frames.json')).write_text(json.dumps([dict(time=t,L=1,R=0)for t in times]))
        manual_command=[sys.executable,str(script),'--profile',str(cache),'--log',str(log),'--output',str(output),'--partial','--wall-manual-exit']
        subprocess.run(manual_command,check=True,capture_output=True)
        metrics=json.loads((output / 'native-metrics.json').read_text())
        self.assertEqual(metrics['gripFailures'],2)
        self.assertEqual([r['failureStages']for r in metrics['cases']],[{'release':1},{'release':1}])
        for row in metrics['cases']:
            self.assertEqual(row['measurementEndAfterCaseMs'],28800)
            self.assertEqual(row['pants']['shaftIntersections']['L'],1)
        invalid=subprocess.run(manual_command+['--wall-exit'],capture_output=True)
        self.assertNotEqual(invalid.returncode,0)
        self.assertIn(b'not allowed with argument',invalid.stderr)

    def test_probe_coverage_rejects_truncated_extended_vehicle_tail(self):
        text, _, metrics = self.coverage_fixture(1)
        for end in (14800,17800,28800):
            metrics['cases'][0]['measurementEndAfterCaseMs'] = end
            with self.subTest(end=end),self.assertRaisesRegex(ValueError,'probe window'):
                carts._coverage(self.output / 'client1',text,1,metrics)
        metrics['cases'][0]['measurementEndAfterCaseMs'] = 0
        with self.assertRaisesRegex(ValueError,'Invalid native measurement window'):
            carts._coverage(self.output / 'client1',text,1,metrics)

    def test_stop_coverage_rejects_wrong_count_case_and_duplicate_completion(self):
        text, _, metrics = self.coverage_fixture(24)
        cache = self.output / 'client1'
        carts._coverage(cache, text, 24, metrics)
        for invalid in (text.replace('COMPLETE case-0 ', 'COMPLETE case-1 '),
                        '\n'.join(text.splitlines()[:-1])):
            with self.assertRaisesRegex(ValueError, 'Missing/duplicate cart cases'):
                carts._coverage(cache, invalid, 24, metrics)
        metrics['cases'][0]['case'] = 'unexpected'
        with self.assertRaisesRegex(ValueError, 'Native metrics'):
            carts._coverage(cache, text, 24, metrics)

    def test_stop_video_count_and_duplicates_are_checked_before_decode(self):
        self.selection['cases'] = ['stop']
        videos = self.output / 'client1/videos'
        videos.mkdir()
        lines = []
        for index in range(24):
            path = videos / f'{index}.mp4'
            path.write_bytes(b'video')
            lines.append(f'[WOOD_BANK] COMPLETE case-{index} wall=100 file={path} frames=360 seconds=12.0')
        probe = SimpleNamespace(stdout=json.dumps({'streams': [dict(codec_type='video', codec_name='h264', nb_read_frames='360', duration='12.0')]}))
        with patch.object(carts.subprocess, 'run', return_value=probe) as decode:
            text = lines[0] + '\n[WOOD_BANK] RUN_STARTED\n' + '\n'.join(lines)
            self.assertEqual(len(carts._videos(self.output, self.selection, 'client1', text)), 24)
            self.assertEqual(decode.call_count, 48)
            decode.reset_mock()
            for invalid in ('\n'.join(lines[:-1]), '\n'.join(lines[:-1] + [lines[0]])):
                with self.assertRaisesRegex(ValueError, 'Missing/duplicate completed cart clips'):
                    carts._videos(self.output, self.selection, 'client1', invalid)
            decode.assert_not_called()

    def test_impact_requires_separate_natural_control_videos_before_decode(self):
        self.selection['cases'] = ['impact']
        self.selection['options']['cart_scenes'] = ['male-full-sprint-wall', 'male-full-native-impact']
        videos = self.output / 'client1/videos'
        videos.mkdir()
        controls, scenes = [], []
        for index, name in enumerate(['natural-run-wall', 'natural-sprint-wall', *self.selection['options']['cart_scenes']]):
            path = videos / f'{index}.mp4'
            path.write_bytes(b'video')
            if index < 2:
                controls.append(f'[CART_NATURAL_CONTROL] COMPLETE spec={name} wall=100 file={path} frames=240 seconds=8.0')
            else:
                scenes.append(f'[WOOD_BANK] COMPLETE {name} wall=100 file={path} frames=240 seconds=8.0')
        probe = SimpleNamespace(stdout=json.dumps({'streams': [dict(codec_type='video', codec_name='h264', nb_read_frames='240', duration='8.0')]}))
        with patch.object(carts.subprocess, 'run', return_value=probe) as decode:
            text = '[WOOD_BANK] RUN_STARTED\n' + '\n'.join(controls + scenes)
            self.assertEqual(len(carts._videos(self.output, self.selection, 'client1', text)), 4)
            decode.reset_mock()
            for invalid in [scenes, controls[::-1]+scenes, controls+controls[:1]+scenes]:
                with self.assertRaisesRegex(ValueError, 'natural impact control videos'):
                    carts._videos(self.output, self.selection, 'client1', '\n'.join(invalid))
            decode.assert_not_called()

    def test_sp_impact_requires_actual_settle_recoil_and_propagates_rejection(self):
        self.selection['cases'] = ['impact']
        self.selection['options']['cart_scenes'] = ['male-full-native-impact']
        (self.output / 'runtime.json').write_text(json.dumps(self.runtime))
        (self.output / 'client1/console.txt').write_text('complete fixture')
        mesh_pass, mesh_exit = True, 0
        def run(command, directory, name):
            if name == 'impact-clearance':
                self.assertIn('male-full-native-impact', command)
                (directory / 'impact-clearance.json').write_text(json.dumps({'meshPass': mesh_pass}))
                return {'exit_code': mesh_exit}
            return {'exit_code': 0}
        with patch.object(carts, 'complete', return_value=True), patch.object(carts, '_videos', return_value=[]), \
                patch.object(carts, '_run', side_effect=run), patch.object(carts, '_load') as load:
            analyze = load.return_value.analyze
            analyze.return_value = {'functionalPass': True, 'failures': []}
            result = carts.verify(self.output, self.selection, {})
            self.assertEqual(result['issues'], [])
            self.assertEqual(analyze.call_args.kwargs, {'require_natural': True, 'require_settle': True, 'require_recoil': True})
            self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
            for error in ('Actual settle handle step exceeds 2 tiles/s',
                          'Emergency actor forward intrusion .365234 exceeds .02 tile after exact drop'):
                with self.subTest(error=error):
                    analyze.side_effect = AssertionError(error)
                    result = carts.verify(self.output, self.selection, {})
                    self.assertTrue(any(error in issue for issue in result['issues']))
                    self.assertEqual(result['outcomes'][0]['status'], 'failed')

            analyze.side_effect = None
            for mesh_pass, mesh_exit in ((False, 1), (False, 0), (True, 1), (None, 0)):
                with self.subTest(mesh_pass=mesh_pass, mesh_exit=mesh_exit):
                    result = carts.verify(self.output, self.selection, {})
                    self.assertTrue(any('leg/handle clearance failed' in issue for issue in result['issues']))
                    self.assertEqual(result['outcomes'][0]['status'], 'failed')

    def test_stop_uses_selected_original_log_and_retains_failed_motion_diagnostics(self):
        self.selection['cases'] = ['stop']
        fixture = carts._load(ROOT / 'tests/test_cart_stop_analyzer.py')
        text = fixture.evidence().replace('Bob_SprintToStop2h_Heavy', 'Bob_RunToStop2H_Heavy')
        _, _, metrics = self.coverage_fixture(text=text)
        (self.output / 'runtime.json').write_text(json.dumps(self.runtime))
        original_run = carts._run
        for filename in ('client1/console.txt', 'client1-launch.log'):
            with self.subTest(log=filename):
                log = self.output / filename
                log.write_text(text)
                console = self.output / 'client1/console.txt'
                if filename == 'client1-launch.log':
                    console.write_text('[WOOD_BANK] ALL_COMPLETE cases=24\n')
                commands = {}
                def run(command, directory, name):
                    commands[name] = command
                    if name == 'stop':
                        return original_run(command, directory, name)
                    if name == 'native':
                        (directory / 'native-metrics.json').write_text(json.dumps(metrics))
                    return {'exit_code': 0}
                with patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]) as videos:
                    result = carts.verify(self.output, self.selection, {})
                self.assertFalse(result['issues'], result['issues'])
                self.assertEqual(result['outcomes'][0]['status'], 'captured')
                self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
                self.assertTrue(result['evidence']['nativeSelectedScenes'])
                self.assertEqual(result['evidence']['analyzers']['stop']['exit_code'], 1)
                self.assertTrue(result['evidence']['motion']['problems'])
                self.assertIn('--scenes', commands['native'])
                self.assertEqual(commands['native'][commands['native'].index('--log') + 1], str(log))
                self.assertEqual(commands['stop'][commands['stop'].index('--log') + 1], str(log))
                self.assertEqual(videos.call_args.args[3], text)
                self.assertEqual(log.read_text(), text)
                self.assertFalse((self.output / 'client1/native-launch.log').exists())
                if filename == 'client1-launch.log':
                    self.assertEqual(console.read_text(), '[WOOD_BANK] ALL_COMPLETE cases=24\n')
                log.unlink()

    def test_stationary_uses_original_log_and_preserves_native_motion_report(self):
        import csv
        self.selection['cases'] = ['stationary']
        fixture = carts._load(ROOT / 'tests/test_cart_stationary_analyzer.py')
        text, wheel = fixture.evidence()
        _, _, metrics = self.coverage_fixture(text=text)
        cache = self.output / 'client1'
        with (cache / 'wood-wheel-native.csv').open('w') as stream:
            writer = csv.DictWriter(stream, fieldnames=wheel[0]); writer.writeheader(); writer.writerows(wheel)
        log = self.output / 'client1-launch.log'
        log.write_text(text)
        (cache / 'console.txt').write_text('Wrong console must not replace original stdout')
        (self.output / 'runtime.json').write_text(json.dumps(self.runtime))
        original_run, commands = carts._run, {}
        def run(command, directory, name):
            commands[name] = command
            if name == 'stationary':
                return original_run(command, directory, name)
            if name == 'native':
                (directory / 'native-metrics.json').write_text(json.dumps(metrics))
            return {'exit_code': 0}
        for bad in (False, True):
            with self.subTest(failed_motion=bad):
                captured = text.replace('run=false', 'run=true') if bad else text
                log.write_text(captured)
                with patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
                    result = carts.verify(self.output, self.selection, {})
                self.assertFalse(result['issues'], result['issues'])
                self.assertEqual(result['outcomes'][0]['status'], 'captured')
                self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
                self.assertEqual(result['evidence']['motion']['motionPass'], not bad)
                self.assertEqual(result['evidence']['analyzers']['stationary']['exit_code'], int(bad))
                saved = Path(result['evidence']['analysis']) / 'stationary-motion.json'
                self.assertEqual(json.loads(saved.read_text()), result['evidence']['motion'])
                self.assertEqual(commands['stationary'][commands['stationary'].index('--log') + 1], str(log))
                self.assertIn('--scenes', commands['native'])
                self.assertEqual(log.read_text(), captured)
                self.assertFalse((cache / 'native-launch.log').exists())

    def test_maneuvers_keep_failed_motion_separate_from_complete_capture(self):
        self.selection['cases'] = ['maneuvers']
        fixture = carts._load(ROOT / 'tests/test_cart_maneuvers_analyzer.py')
        text = fixture.evidence()
        _, _, metrics = self.coverage_fixture(text=text)
        log = self.output / 'client1-launch.log'
        log.write_text(text)
        (self.output / 'runtime.json').write_text(json.dumps(self.runtime))
        original_run = carts._run
        def run(command, directory, name):
            if name == 'maneuvers':
                self.assertEqual(command[command.index('--log') + 1], str(log))
                return original_run(command, directory, name)
            if name == 'native':
                self.assertIn('--scenes', command)
                (directory / 'native-metrics.json').write_text(json.dumps(metrics))
            return {'exit_code': 0}
        for bad in (False, True):
            with self.subTest(bad=bad):
                log.write_text(text.replace('run=false', 'run=true') if bad else text)
                with patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
                    result = carts.verify(self.output, self.selection, {})
                self.assertFalse(result['issues'], result['issues'])
                self.assertEqual(result['outcomes'][0]['status'], 'captured')
                self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
                self.assertEqual(result['evidence']['motion']['motionPass'], not bad)
                self.assertEqual(result['evidence']['analyzers']['maneuvers']['exit_code'], int(bad))
                saved = Path(result['evidence']['analysis']) / 'maneuvers-motion.json'
                self.assertEqual(json.loads(saved.read_text()), result['evidence']['motion'])

    def test_collision_and_footprint_keep_mesh_motion_and_capture_gates_separate(self):
        fixture = carts._load(ROOT / 'tests/test_cart_footprint_analyzer.py')
        text, _ = fixture.fixture(self.output / 'client1')
        _, _, metrics = self.coverage_fixture(text=text)
        log = self.output / 'client1-launch.log';log.write_text(text)
        (self.output / 'runtime.json').write_text(json.dumps(self.runtime))
        bad = False
        def run(command, directory, name):
            if name in ('collision', 'footprint'):
                self.assertTrue(command[1].endswith('analyze-footprint.py'))
                self.assertEqual(command[command.index('--log') + 1], str(log))
                self.assertEqual(command[command.index('--profile') + 1], str(self.output / 'client1'))
                report = dict(motionPass=not bad, footprintPass=not bad, controlCount=5)
                (directory / (name + '-motion.json')).write_text(json.dumps(report))
                return {'exit_code': int(bad)}
            if name == 'native':
                self.assertIn('--scenes', command)
                (directory / 'native-metrics.json').write_text(json.dumps(metrics))
            return {'exit_code': 0}
        for case in ('collision', 'footprint'):
            self.selection['cases'] = [case]
            for bad in (False, True):
                with self.subTest(case=case, failed_diagnostic=bad), patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
                    result = carts.verify(self.output, self.selection, {})
                self.assertFalse(result['issues'], result['issues'])
                self.assertEqual(result['outcomes'][0]['status'], 'captured')
                self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
                self.assertEqual(result['evidence']['motion']['motionPass'], not bad)
                self.assertEqual(result['evidence']['motion']['footprintPass'], not bad)
                self.assertEqual(result['evidence']['analyzers'][case]['exit_code'], int(bad))
                saved = Path(result['evidence']['analysis']) / (case + '-motion.json')
                self.assertEqual(json.loads(saved.read_text()), result['evidence']['motion'])
        bad = False
        with patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]), patch.object(carts, '_coverage', side_effect=ValueError('Incomplete grip window')):
            result = carts.verify(self.output, self.selection, {})
        self.assertEqual(result['outcomes'][0]['status'], 'failed')
        self.assertFalse(result['outcomes'][0]['outcome']['evidenceComplete'])
        self.assertIn('Incomplete grip window', result['issues'])
        self.assertTrue(result['evidence']['motion']['motionPass'])
        self.assertTrue((Path(result['evidence']['analysis']) / 'footprint-motion.json').is_file())

    def test_native_obstacle_banks_require_motion_and_mesh_proof_independently(self):
        for bank,source,count,end in (('vehicles','vehicle',12,11800),('brace','brace',8,17800),('fast-slide','footprint',16,11800),('wall-exit','footprint',24,11800),('wall-manual-exit','footprint',16,28800),('wall-fast-manual-exit','footprint',32,28800)):
            self.selection['cases'] = [bank]
            fixture = carts._load(ROOT / ('tests/test_cart_'+source+'_analyzer.py'))
            text, _ = fixture.fixture(self.output / 'client1',**({'fast_slide':True} if bank=='fast-slide' else {'wall_exit':True} if bank=='wall-exit' else {'wall_manual_exit':True} if bank=='wall-manual-exit' else {'wall_fast_manual_exit':True} if bank=='wall-fast-manual-exit' else {}))
            _, _, metrics = self.coverage_fixture(count, text, end)
            log = self.output / 'client1-launch.log'; log.write_text(text)
            (self.output / 'runtime.json').write_text(json.dumps(self.runtime))
            for failed in (None, 'motionPass', 'footprintPass'):
                def run(command, directory, name):
                    if name == 'native':
                        self.assertIn('--scenes',command)
                        spec=json.loads(Path(command[command.index('--scenes')+1]).read_text())
                        self.assertEqual(spec['bank'],bank)
                        self.assertEqual(len(spec['scenes']),count)
                        (directory / 'native-metrics.json').write_text(json.dumps(metrics))
                    if name == bank:
                        self.assertTrue(command[1].endswith('analyze-'+('footprint' if bank in ('fast-slide','wall-exit','wall-manual-exit','wall-fast-manual-exit') else bank)+'.py'))
                        self.assertEqual(command[command.index('--log')+1], str(log))
                        if bank in ('fast-slide','wall-exit','wall-manual-exit','wall-fast-manual-exit'):self.assertIn('--'+bank,command)
                        report = dict(motionPass=failed!='motionPass', footprintPass=failed!='footprintPass',
                                      motionFailures=['motion'] if failed=='motionPass' else [],
                                      footprintFailures=['mesh'] if failed=='footprintPass' else [])
                        (directory / (bank+'-motion.json')).write_text(json.dumps(report))
                    return {'exit_code': int(name==bank and failed is not None)}
                with self.subTest(bank=bank,failed=failed), patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
                    result = carts.verify(self.output, self.selection, {})
                self.assertEqual(result['outcomes'][0]['status'], 'failed' if failed else 'captured')
                self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
                if failed:
                    self.assertIn('motion' if failed=='motionPass' else 'mesh', str(result['issues']))

    def test_native_path_requires_route_and_footprint_proof(self):
        self.selection['cases'] = ['path']
        fixture = carts._load(ROOT / 'tests/test_cart_path_analyzer.py')
        text, _ = fixture.fixture()
        _, _, metrics = self.coverage_fixture(24, text)
        log = self.output / 'client1-launch.log'; log.write_text(text)
        (self.output / 'runtime.json').write_text(json.dumps(self.runtime))
        for failed in (None, 'motionPass', 'footprintVerified'):
            def run(command, directory, name):
                if name == 'native':
                    (directory / 'native-metrics.json').write_text(json.dumps(metrics))
                if name == 'path':
                    self.assertTrue(command[1].endswith('analyze-path.py'))
                    self.assertEqual(command[command.index('--log')+1], str(log))
                    report = dict(motionPass=failed!='motionPass', footprintVerified=failed!='footprintVerified', failures=[])
                    (directory / 'path-motion.json').write_text(json.dumps(report))
                return {'exit_code': int(name=='path' and failed is not None)}
            with self.subTest(failed=failed), patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
                result = carts.verify(self.output, self.selection, {})
            self.assertEqual(bool(result['issues']), failed is not None, result)
            self.assertEqual(result['outcomes'][0]['status'], 'failed' if failed else 'captured')
            self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])

    def test_reversal_capture_preserves_motion_report_and_failed_diagnostics(self):
        self.selection['cases'] = ['reversal']
        fixture = carts._load(ROOT / 'tests/test_cart_reversal_analyzer.py')
        text, _, metrics = self.coverage_fixture(text=fixture.evidence())
        log = self.output / 'client1-launch.log'
        log.write_text(text)
        (self.output / 'runtime.json').write_text(json.dumps(self.runtime))
        def run(command, directory, name):
            if name == 'native':
                self.assertIn('--scenes', command)
                (directory / 'native-metrics.json').write_text(json.dumps(metrics))
            return {'exit_code': 0}
        with patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
            result = carts.verify(self.output, self.selection, {})
        self.assertFalse(result['issues'], result['issues'])
        self.assertEqual(result['outcomes'][0]['status'], 'captured')
        self.assertTrue(result['evidence']['motion']['motionPass'])
        self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
        saved = Path(result['evidence']['analysis']) / 'reversal-motion.json'
        self.assertEqual(json.loads(saved.read_text()), result['evidence']['motion'])
        log.write_text(text.replace('run=false', 'run=true'))
        with patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
            result = carts.verify(self.output, self.selection, {})
        self.assertEqual(result['outcomes'][0]['status'], 'captured')
        self.assertFalse(result['evidence']['motion']['motionPass'])
        self.assertTrue(result['evidence']['motion']['failures'])
        log.write_text(text.replace('case=male-empty-walk-switch ', 'case=unexpected ').replace('COMPLETE male-empty-walk-switch ', 'COMPLETE unexpected '))
        metrics['cases'][0]['case'] = 'unexpected'
        with patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
            result = carts.verify(self.output, self.selection, {})
        self.assertEqual(result['outcomes'][0]['status'], 'failed')
        self.assertIn('Missing, duplicate or unexpected reversal cases', result['issues'])

    def test_cart_completion_alone_never_produces_capture_evidence(self):
        (self.output / 'client1/console.txt').write_text('[WOOD_BANK] ALL_COMPLETE cases=20\n')
        result = carts.verify(self.output, self.selection, {})
        self.assertTrue(result['issues'])
        self.assertEqual(result['outcomes'][0]['status'], 'failed')
        self.assertIs(result['outcomes'][0]['outcome']['animationEquivalencePass'], False)


if __name__ == '__main__':
    unittest.main()
