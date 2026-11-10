"""Magazine native receipts: exact input/output units, immutable callbacks and pending edits."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / 'tools'))
from queue_checks.adapters import magazine_unload as a
from tests.test_queue_wring_clothing import placement_proof


def ammo(identifier, kind=a.AMMO, uses=1, path=None):
    path = [] if path is None else path
    return dict(id=identifier, type=kind, uses=uses, class_='ComboItem', factoryCount=5 if kind == a.AMMO else 6,
                root=not path, path=path)


def ammo_record(identifier, kind=a.AMMO, uses=1, path=None):
    value = ammo(identifier, kind, uses, path); value['class'] = value.pop('class_'); return value


def totals(value):
    value['looseUnits'] = sum(item['uses'] for item in value['ammo'] if item['type'] == a.AMMO)
    value['loadedUnits'] = sum(item['loaded'] for item in value['magazines'].values())
    value['totalUnits'] = value['looseUnits'] + value['loadedUnits']


def evidence(kind='mp', mode='toolkit', case='direct'):
    editing = mode == 'toolkit'; origin = dict(x=11, y=20, z=0)
    specs = {name: dict(id=10 + index, type='Base.9mmClip', loaded=a.LOADS[name], maxAmmo=15, ammoType=a.AMMO,
                       factoryCount=1, condition=10, **{'class': 'ComboItem'}) for index, name in enumerate(a.NAMES)}
    initial = [ammo_record(20), ammo_record(21), ammo_record(22, a.OTHER)]
    ids = dict(case=case, mode=mode, origin=origin, placementProof=placement_proof(origin, 'replica' if kind == 'mp' else 'local'),
               magazines=specs, seedAmmo=[20, 21], otherAmmo=22, initialAmmo=initial, ammoUnit='currentUses')
    def snapshot(phase):
        magazines = {}
        for name, spec in specs.items():
            loaded = spec['loaded']
            if phase == 'final' and name != 'unrelated' and not (editing and name == 'cancelled'): loaded = 0
            if phase == 'pending' and name == 'front': loaded = 4
            magazines[name] = dict(spec, present=True, actorCount=1, rootCount=1, equipped=False, favorite=False, loaded=loaded)
        decrement = sum(a.LOADS[name] - item['loaded'] for name, item in magazines.items())
        value = dict(case=case, magazines=magazines, ammo=copy.deepcopy(initial) + [ammo_record(30 + index) for index in range(decrement)])
        totals(value); return value
    final = snapshot('final'); pending = snapshot('pending')
    commands = []
    order = ['front', 'tail', 'target'] if editing else ['front', 'target', 'cancelled', 'tail']
    for name in ('front', 'target', 'cancelled', 'tail'):
        cancelled = editing and name == 'cancelled'
        command = dict(name=name, type='ISUnloadBulletsFromMagazine', item=specs[name]['id'], producer=a.PRODUCERS[case],
                       duration=-1, constructorAmmo=a.LOADS[name], callbacksUntouched=True, ownedBulkGuard=case == 'bulk',
                       started=not cancelled, progress=not cancelled, partialCounts=[] if cancelled else [a.LOADS[name] - 1])
        if cancelled: command['cancelled'] = True
        else: command['startedAt'] = 100 + order.index(name) * 100
        commands.append(command)
    calls = ([dict(names=[name], entries=1, queued=1) for name in ('front', 'target', 'cancelled', 'tail')] if case == 'direct' else
             [dict(names=['front'], entries=1, queued=1), dict(names=['target', 'cancelled', 'tail'], entries=3, queued=3)])
    row = dict(ids=copy.deepcopy(ids), input=snapshot('input'), client=copy.deepcopy(final), server=copy.deepcopy(final),
               clientPlacement=placement_proof(origin), commands=commands, producerCalls=calls,
               pendingBefore=copy.deepcopy(pending), pendingAfter=copy.deepcopy(pending),
               status='passed', queueIdle=True, settleMilliseconds=1000,
               edit=dict(cancelled=editing, reordered=editing, untouched=True))
    return row, dict(kind=kind, mode=mode), ids, final


class MagazineUnloadTests(unittest.TestCase):
    def test_grouped_full_pack_and_sp_menu_host_modes(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                selection = dict(suite='magazine-unload', cases=list(a.CASES), kind=kind, mode=mode, clients=1,
                                 languages=['EN'], mods=a.MODS, options={'mp_host': True} if kind == 'mp' else {})
                a.validate(selection)
                for case in a.CASES: self.assertEqual([], a.check_case(*evidence(kind, mode, case)))
        selection['options'] = {}
        with self.assertRaises(ValueError): a.validate(selection)
        selection['options'] = {'mp_host': True, 'world_template': 'old-world'}
        with self.assertRaises(ValueError): a.validate(selection)

    def test_missing_or_forged_magazine_consumption_is_rejected(self):
        for name in a.NAMES:
            result = evidence(); result[0]['client']['magazines'][name]['loaded'] += 1
            self.assertTrue(a.check_case(*result), name)
        for field, value in [('id', 999), ('type', 'Base.M14Clip'), ('class', 'HandWeapon'), ('rootCount', 0),
                             ('actorCount', 2), ('equipped', True), ('favorite', True), ('present', False)]:
            result = evidence(); result[0]['client']['magazines']['target'][field] = value
            self.assertTrue(a.check_case(*result), field)

    def test_round_outputs_must_be_new_unique_exact_root_actionable_units(self):
        for change in ('missing', 'duplicate', 'alias', 'wrong-type', 'wrong-units', 'nested', 'replayed'):
            result = evidence(); value = result[0]['client']
            if change == 'missing': value['ammo'].pop()
            if change == 'duplicate': value['ammo'].append(copy.deepcopy(value['ammo'][-1]))
            if change == 'alias': value['ammo'][-1]['id'] = result[2]['magazines']['target']['id']
            if change == 'wrong-type': value['ammo'][-1].update(type=a.OTHER, factoryCount=6)
            if change == 'wrong-units': value['ammo'][-1]['uses'] = 5
            if change == 'nested': value['ammo'][-1].update(root=False, path=[99])
            if change == 'replayed': value['ammo'].append(ammo_record(900))
            totals(value); self.assertTrue(a.check_case(*result), change)

    def test_initial_ammo_and_unrelated_inputs_cannot_be_lost_or_credited(self):
        for identifier in (20, 21, 22):
            result = evidence(); value = result[0]['client']; value['ammo'] = [item for item in value['ammo'] if item['id'] != identifier]
            totals(value); self.assertTrue(a.check_case(*result))
        result = evidence(); result[0]['client']['magazines']['unrelated']['loaded'] = 0
        self.assertTrue(a.check_case(*result))
        result = evidence(); result[0]['client']['ammo'][0]['uses'] = 2
        self.assertTrue(a.check_case(*result))
        result = evidence(); result[0]['client']['looseUnits'] *= 5
        self.assertTrue(a.check_case(*result), 'factory count must never inflate physical round credit')

    def test_preexisting_actionable_uses_are_preserved_without_factory_count_multiplication(self):
        result = evidence(); extra = ammo_record(90, uses=3, path=[99])
        result[2]['initialAmmo'].append(copy.deepcopy(extra)); result[0]['ids'] = copy.deepcopy(result[2])
        for phase in ('input', 'client', 'server', 'pendingBefore', 'pendingAfter'):
            result[0][phase]['ammo'].append(copy.deepcopy(extra)); totals(result[0][phase])
        result[3].update(copy.deepcopy(result[0]['server']))
        self.assertEqual([], a.check_case(*result))

    def test_real_partial_progress_callbacks_and_duration_are_required(self):
        changes = [('duration', 1), ('callbacksUntouched', False), ('ownedBulkGuard', True), ('started', False),
                   ('progress', False), ('constructorAmmo', 0), ('partialCounts', []), ('partialCounts', [5]),
                   ('partialCounts', [3, 4]), ('partialCounts', [3, 3]), ('type', 'ISUnloadBulletsFromFirearm')]
        for field, value in changes:
            result = evidence(); result[0]['commands'][0][field] = value
            self.assertTrue(a.check_case(*result), field)
        result = evidence(case='bulk'); result[0]['commands'][0]['ownedBulkGuard'] = False
        self.assertTrue(a.check_case(*result))

    def test_pending_cancel_reorder_and_tail_must_have_real_effects(self):
        for change in ('cancel-started', 'cancel-empty', 'unchanged-order', 'missing-tail', 'fake-edit', 'physical-edit', 'public-bulk-call'):
            result = evidence(case='bulk'); row = result[0]
            if change == 'cancel-started': row['commands'][2]['started'] = True
            if change == 'cancel-empty': row['client']['magazines']['cancelled']['loaded'] = 0
            if change == 'unchanged-order': row['commands'][1]['startedAt'], row['commands'][3]['startedAt'] = 200, 300
            if change == 'missing-tail': row['commands'].pop()
            if change == 'fake-edit': row['edit']['reordered'] = False
            if change == 'physical-edit': row['pendingAfter']['magazines']['target']['loaded'] = 0
            if change == 'public-bulk-call': row['producerCalls'][1]['entries'] = 1
            self.assertTrue(a.check_case(*result), change)

    def test_grouped_authority_readiness_and_complete_receipts(self):
        for kind in ('sp', 'mp'):
            selection = dict(kind=kind, mode='toolkit'); cases = list(a.CASES)
            client = ['[QUEUE_TEST] ' + marker for marker in ('VOICE_DISABLED', 'DISPLAY_READY', 'PREFLIGHT_COMPLETE', 'NATIVE_CONNECTED' if kind == 'mp' else 'TRUE_SP')]
            client += ['[QUEUE_CHECK] ' + json.dumps(dict(suite='magazine-unload', event='setup', cases=cases, queueEnabled=True, nativeDurations=True, adapterInstalled=True))]
            server = ['[STARTUP_TEST] SERVER_READY']
            for case in cases:
                row, _, ids, final = evidence(kind=kind, case=case)
                row.update(suite='magazine-unload', event='case', id=case, actor='client1', kind=kind, mode='toolkit')
                client += [a.PREFIX + 'CLIENT_PLACEMENT ' + json.dumps(dict(case=case, proof=row['clientPlacement'])), '[QUEUE_CHECK] ' + json.dumps(row)]
                server += [a.PREFIX + 'PREPARED ' + json.dumps(ids), a.PREFIX + 'VERIFIED ' + json.dumps(final)]
            if kind == 'sp': client += server
            client += ['[QUEUE_CHECK] ' + json.dumps(dict(suite='magazine-unload', event='complete', cases=cases, performed=len(cases), failed=0, skipped=0)),
                       a.PREFIX + 'COMPLETE ' + json.dumps(dict(cases=cases))]
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); (root / 'client1-launch.log').write_text('\n'.join(client)); (root / 'server-launch.log').write_text('\n'.join(server))
                self.assertEqual([], a.verify(root, selection, {})['issues'])
                (root / 'client1-launch.log').write_text('\n'.join(client[1:]))
                self.assertTrue(a.verify(root, selection, {})['issues'])
                (root / 'client1-launch.log').write_text('\n'.join(client[:-1]))
                self.assertTrue(a.verify(root, selection, {})['issues'])
                if kind == 'mp':
                    (root / 'client1-launch.log').write_text('\n'.join(client)); (root / 'server-launch.log').write_text('\n'.join(server[:-1]))
                    self.assertTrue(a.verify(root, selection, {})['issues'])

    def test_native_source_audit_refuses_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); data = b'current native fixture source'; expected = {name: zlib.crc32(data) for name in a.NATIVE_CRC}
            for relative in expected:
                path = root / relative; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
            with patch.object(a, 'NATIVE_CRC', expected):
                self.assertEqual(expected, a.audit_native(root))
                (root / next(iter(expected))).write_bytes(b'modified callback')
                with self.assertRaises(ValueError): a.audit_native(root)

    def test_report_verifier_is_declared_from_first_capture(self):
        from queue_checks import provenance
        selection = dict(suite='magazine-unload')
        with patch.object(provenance.adapters, 'get', return_value=a):
            declared = {path.resolve() for path in provenance.verifier_sources(PROJECT, selection)}
            inputs = {path.resolve() for path in a.sources(PROJECT, selection)} | declared | {Path(a.__file__).resolve()}
            roles = provenance.source_roles(PROJECT, selection, {str(path): provenance.digest(path) for path in inputs})
        verifier = Path(a.__file__).with_name('magazine_unload_verifier.py').resolve()
        self.assertIn(str(verifier), roles['verifier']); self.assertIn(str(Path(__file__).resolve()), roles['verifier'])
        self.assertIn(str(Path(a.__file__).resolve()), roles['runtime'])
        self.assertIn(str(PROJECT / 'tests/native_queue/magazine-unload/client/ZZMagazineUnload.lua'), roles['runtime'])

    def test_fixture_compiles_and_never_accelerates_or_injects_native_events(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True); compile_ = lua.eval('function(source)local f,e=loadstring(source);assert(f,e)end')
        root = PROJECT / 'tests/native_queue/magazine-unload'
        for file in root.rglob('*.lua'):
            text = file.read_text(); compile_(text)
            self.assertNotRegex(text, r'\.(?:maxTime|animEvent|serverStart|complete|perform)\s*=(?!=)')
            self.assertNotIn('emulateAnimEvent(', text)
            self.assertNotIn(':animEvent(', text)
        client = (root / 'client/ZZMagazineUnload.lua').read_text()
        self.assertIn('ISInventoryPaneContextMenu.onUnloadBulletsFromMagazine(player,item)', client)
        self.assertIn('BulkFirearms.unloadEntries(player,rows)', client)
        self.assertIn('BulkFirearms.queueUnload(player,entries)', client)
        self.assertIn('ActionQueue.cancelOperation(', client); self.assertIn('ActionQueue.move(', client)

    def test_shared_fixture_conservation_and_cleanup_execute_with_realistic_ammo_metadata(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().fixture = str(PROJECT / 'tests/native_queue/magazine-unload/shared/QueueMagazineUnload.lua')
        lua.execute(r'''
package.loaded.QueueEnergyPlacement={}
function instanceof(value,kind)return value.class==kind end
function getClassSimpleName(value)return value.class end
function isServer()return false end
local F=dofile(fixture)
for _,mode in ipairs({'native','toolkit'})do
 local values={};local root={}
 local function item(id,kind,loaded,uses)
  local value={class='ComboItem',id=id,kind=kind,loaded=loaded or 0,uses=uses or 1}
  function value:getID()return self.id end
  function value:getFullType()return self.kind end
  function value:getContainer()return root end
  function value:getCurrentAmmoCount()return self.loaded end
  function value:getMaxAmmo()return self.kind=='Base.9mmClip'and 15 or 0 end
  function value:getAmmoType()return self.kind=='Base.9mmClip'and{getItemKey=function()return 'Base.Bullets9mm'end}or nil end
  function value:getCount()return self.kind=='Base.9mmClip'and 1 or self.kind=='Base.Bullets9mm'and 5 or 6 end
  function value:getCurrentUses()return self.uses end
  function value:getCondition()return 10 end
  function value:isFavorite()return false end
  values[#values+1]=value;return value
 end
 function root:getItems()return{size=function()return #values end,get=function(_,i)return values[i+1]end}end
 function root:getItemById(id)for _,value in ipairs(values)do if value.id==id then return value end end end
 function root:Remove(item)for i,value in ipairs(values)do if value==item then table.remove(values,i);return end end end
 local player={getInventory=function()return root end,isEquipped=function()return false end}
 local ids={case='direct',mode=mode,magazines={},seedAmmo={20,21},otherAmmo=22}
 local state={player=player,ids=ids,items={}}
 for index,name in ipairs(F.names)do
  local value=item(index,'Base.9mmClip',F.loads[name]);state.items[name]=value
  ids.magazines[name]={id=index,type=value.kind,class='ComboItem',loaded=value.loaded,maxAmmo=15,ammoType='Base.Bullets9mm',factoryCount=1,condition=10}
 end
 item(20,'Base.Bullets9mm');item(21,'Base.Bullets9mm');item(22,'Base.ShotgunShells');local untouched=item(99,'Base.Bullets9mm',0,3)
 state.input=F.snapshot(state);ids.initialAmmo=state.input.ammo;assert(F.baseline(state))
 local nextID=100
 for _,name in ipairs({'front','target','cancelled','tail'})do
  if mode=='native'or name~='cancelled'then
   local magazine=state.items[name]
   while magazine.loaded>0 do magazine.loaded=magazine.loaded-1;item(nextID,'Base.Bullets9mm');nextID=nextID+1 end
  end
 end
 assert(F.verify(state),'native-shaped output conservation failed')
 local output=values[#values];output.uses=5;assert(not F.verify(state),'factoryCount confused with actionable round uses');output.uses=1
 local missing=table.remove(values);assert(not F.verify(state),'missing round accepted');values[#values+1]=missing
 state.items.unrelated.loaded=0;assert(not F.verify(state),'unrelated magazine was allowed to unload');state.items.unrelated.loaded=6
 assert(F.verify(state));F.dispose(state)
 assert(#values==1 and values[1]==untouched and untouched.uses==3,'cleanup touched preexisting ammo')
end
''')

    def test_installed_kahlua_native_constructor_uses_exact_fixture_owned_guard_read(self):
        game, jdk = os.environ.get('PZ_GAME'), os.environ.get('PZ_JDK')
        if not game or not jdk: self.skipTest('PZ_GAME and PZ_JDK required for installed Kahlua own-slot regression')
        a.audit_native(game)
        client = (PROJECT / 'tests/native_queue/magazine-unload/client/ZZMagazineUnload.lua').read_text()
        self.assertIn('local guard=F.ownStartGuard(action)', client)
        self.assertNotRegex(client, r"rawget\s*\(action\s*,\s*['\"]isValidStart")
        java_source = r'''
import java.nio.file.*;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.*;
public final class MagazineOwnGuardChecks {
 static final J2SEPlatform platform=J2SEPlatform.getInstance();
 static KahluaTable env;
 static KahluaThread thread;
 static void filenames(Prototype p,String name){p.filename=name;for(Prototype child:p.prototypes)filenames(child,name);}
 static Object run(String source,String name)throws Exception{
  LuaClosure chunk=LuaCompiler.loadstring(source,name,env);filenames(chunk.prototype,name);
  return thread.call(chunk,new Object[0]);
 }
 static Object load(Path path)throws Exception{return run(Files.readString(path),path.getFileName().toString());}
 static void source(Object value,String method,String file){
  if(!(value instanceof KahluaTable table)||!(table.rawget(method) instanceof LuaClosure closure)
   ||!file.equals(closure.prototype.filename))throw new AssertionError("native/fixture source capture differs: "+method);
 }
 public static void main(String[] args)throws Exception{
  Path game=Path.of(args[0]),project=Path.of(args[1]);env=platform.newTable();env.rawset("_G",env);env.rawset("_VERSION","Kahlua");
  se.krka.kahlua.stdlib.BaseLib.register(env);se.krka.kahlua.j2se.MathLib.register(platform,env);
  se.krka.kahlua.stdlib.RandomLib.register(platform,env);se.krka.kahlua.stdlib.StringLib.register(platform,env);
  se.krka.kahlua.stdlib.CoroutineLib.register(platform,env);se.krka.kahlua.stdlib.OsLib.register(platform,env);
  se.krka.kahlua.stdlib.TableLib.register(platform,env);LuaCompiler.register(env);
  thread=new KahluaThread(System.out,platform,env);thread.debugOwnerThread=Thread.currentThread();
  try(var stream=Files.newInputStream(game.resolve("stdlib.lbc"))){thread.call(Prototype.loadByteCode(stream,env),new Object[0]);}
  run("require=function()return{}end","bootstrap");
  load(game.resolve("media/lua/shared/ISBaseObject.lua"));
  load(game.resolve("media/lua/shared/TimedActions/ISBaseTimedAction.lua"));
  load(game.resolve("media/lua/shared/TimedActions/ISUnloadBulletsFromMagazine.lua"));
  Object fixture=load(project.resolve("tests/native_queue/magazine-unload/shared/QueueMagazineUnload.lua"));env.rawset("Fixture",fixture);
  source(env.rawget("ISUnloadBulletsFromMagazine"),"new","ISUnloadBulletsFromMagazine.lua");
  source(env.rawget("ISBaseTimedAction"),"isValidStart","ISBaseTimedAction.lua");
  source(fixture,"ownStartGuard","QueueMagazineUnload.lua");
  run("local actor,magazine={},{};local action=ISUnloadBulletsFromMagazine:new(actor,magazine);"
   +"assert(action.character==actor and action.magazine==magazine and action.maxTime==-1 and action.Type=='ISUnloadBulletsFromMagazine');"
   +"assert(type(action.isValidStart)=='function' and rawget(action,'isValidStart')==ISBaseTimedAction.isValidStart,'installed rawget no longer demonstrates inherited native guard');"
   +"local direct=Fixture.ownStartGuard(action);assert(direct==nil,'direct native action falsely owns inherited guard');"
   +"local guard=function()error('own-slot observation executed guard')end;action.isValidStart=guard;"
   +"assert(Fixture.ownStartGuard(action)==guard,'owned start callback was not returned exactly');"
   +"assert(ISBaseTimedAction.isValidStart~=guard and action.maxTime==-1,'guard read mutated native constructor/base');",
   "fixture-own-guard-regression");
  System.out.println("KAHLUA_NATIVE_OWN_GUARD_OK");
 }
}
'''
        with tempfile.TemporaryDirectory(prefix='pz-magazine-kahlua-own-') as temporary:
            root = Path(temporary); source = root / 'MagazineOwnGuardChecks.java'; source.write_text(java_source)
            jar = Path(game) / 'projectzomboid.jar'
            environment = {key: value for key, value in os.environ.items() if key not in ('JDK_JAVA_OPTIONS', 'JAVA_TOOL_OPTIONS', '_JAVA_OPTIONS')}
            compiled = subprocess.run([str(Path(jdk) / 'bin/javac'), '--release', '25', '-cp', str(jar), '-d', str(root), str(source)],
                                      capture_output=True, text=True, timeout=30, env=environment)
            self.assertEqual(0, compiled.returncode, compiled.stdout + compiled.stderr)
            checked = subprocess.run([str(Path(jdk) / 'bin/java'), '-cp', str(root) + os.pathsep + str(jar),
                                      'MagazineOwnGuardChecks', str(game), str(PROJECT)], capture_output=True, text=True, timeout=20, env=environment)
            self.assertEqual(0, checked.returncode, checked.stdout + checked.stderr)
            self.assertIn('KAHLUA_NATIVE_OWN_GUARD_OK', checked.stdout)

    def test_installed_native_remove_bullet_uses_one_output_per_decrement_complete_is_empty(self):
        game = os.environ.get('PZ_GAME')
        if not game: self.skipTest('PZ_GAME required for installed native unload source regression')
        source = Path(game) / 'media/lua/shared/TimedActions/ISUnloadBulletsFromMagazine.lua'
        self.assertEqual(a.NATIVE_CRC[str(source.relative_to(game))], zlib.crc32(source.read_bytes()))
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True); lua.globals().source = str(source)
        lua.execute(r'''
require=function()end
ISBaseTimedAction={derive=function(_,name)local c={Type=name};c.__index=c;return c end}
function isServer()return true end
function isClient()return false end
function isMultiplayer()return true end
local created,loaded=0,3
function instanceItem(kind)assert(kind=='Base.Bullets9mm');created=created+1;return{getCurrentUses=function()return 1 end,getCount=function()return 5 end}end
function sendAddItemToContainer()end
function syncItemFields()end
dofile(source)
local inventory={AddItem=function(_,item)assert(item:getCurrentUses()==1 and item:getCount()==5)end}
local magazine={getCurrentAmmoCount=function()return loaded end,setCurrentAmmoCount=function(_,n)loaded=n end,
 getAmmoType=function()return{getItemKey=function()return 'Base.Bullets9mm'end}end}
local action=setmetatable({magazine=magazine,character={getInventory=function()return inventory end}},ISUnloadBulletsFromMagazine)
assert(action:getDuration()==-1 and action:complete()and loaded==3 and created==0)
-- Offline callback unit test only; the native fixture never injects animation events.
action:animEvent('RemoveBullet',nil);assert(loaded==2 and created==1)
assert(action:complete()and loaded==2 and created==1)
action:animEvent('RemoveBullet',nil);action:animEvent('RemoveBullet',nil);assert(loaded==0 and created==3)
action:animEvent('RemoveBullet',nil);assert(loaded==0 and created==3)
''')


if __name__ == '__main__':
    unittest.main()
