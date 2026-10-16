"""Load-only readiness rejects menu-only, preflight failures and incomplete peers."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import startup


class StartupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.selection = {'suite': 'startup', 'cases': ['loaded'], 'kind': 'sp', 'mode': 'native',
                          'clients': 1, 'languages': ['EN'], 'mods': ['PZSurvivorToolkit'], 'options': {}}

    def logs(self):
        kind, mode = self.selection['kind'], self.selection['mode']
        return ('[QUEUE_TEST] ' + ('NATIVE_CONNECTED' if kind == 'mp' else 'TRUE_SP') + '\n'
                f'[QUEUE_TEST] PREFLIGHT_COMPLETE mods={len(self.selection["mods"])} mode={mode}\n'
                f'[STARTUP_TEST] GAME_START kind={kind} mode={mode}\n'
                '[STARTUP_TEST] PLAYER_READY square=10835,10144,0 tick=true\n'
                '[STARTUP_TEST] COMPLETE case=loaded\n')

    def verify(self, text):
        (self.root / 'client1-launch.log').write_text(text)
        return startup.verify(self.root, self.selection, {})

    def test_selection_rejects_unsupported_combinations_and_sp_restore(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                startup.validate(dict(self.selection, kind=kind, mode=mode, languages=['RU']))
        for change in ({'cases': ['unknown']}, {'kind': 'unknown'}, {'mode': 'unknown'},
                       {'clients': True}, {'clients': 2}, {'languages': ['EN', 'RU']},
                       {'options': {'world_template': '/saved/sp'}}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                startup.validate(dict(self.selection, **change))
        startup.validate(dict(self.selection, kind='mp', options={'world_template': '/saved/mp'}))

    def test_stage_uses_common_fixture_without_animal_helpers(self):
        runtime = {'fixture': {'mods': []}}
        startup.stage(ROOT, self.root, None, None, self.selection, {}, runtime)
        self.assertEqual(runtime['fixture'], {'mods': [], 'server_ready': '[STARTUP_TEST] SERVER_READY'})
        sources = startup.sources(ROOT, self.selection)
        self.assertEqual({p.name for p in sources}, {'ZZStartup.lua', 'ZZStartupServer.lua'})
        self.assertTrue(all('startup' in p.parts for p in sources))

    def test_explicit_connection_is_mp_only_and_validates_both_fields(self):
        valid = {'username': 'animal-fixture', 'password': 'isolated-native-only'}
        startup.validate(dict(self.selection, kind='mp', options={'startup_connection': valid}))
        for connection in (None, [], {}, {'username': 'client1'}, dict(valid, extra=True),
                           dict(valid, username=''), dict(valid, username='../client1'),
                           dict(valid, username='x' * 65), dict(valid, username=1),
                           dict(valid, password=''), dict(valid, password='x' * 257),
                           dict(valid, password='a\nb'), dict(valid, password='a\rb'),
                           dict(valid, password='a\0b'), dict(valid, password='a\x01b'),
                           dict(valid, password='a\x7fb'), dict(valid, password=True)):
            with self.subTest(connection=connection), self.assertRaises(ValueError):
                startup.validate(dict(self.selection, kind='mp', options={'startup_connection': connection}))
        with self.assertRaises(ValueError):
            startup.validate(dict(self.selection, options={'startup_connection': valid}))

    def test_verifier_requires_exact_ordered_native_readiness(self):
        text = self.logs()
        self.assertEqual([], self.verify(text)['issues'])
        lines = text.splitlines(keepends=True)
        broken = [text.replace(line, '') for line in lines]
        broken += [text + line for line in lines]
        broken += [lines[2] + ''.join(lines[:2] + lines[3:]),
                   text.replace('square=10835,10144,0', 'square=nan,10144,0'),
                   text.replace('tick=true', 'tick=false'), text.replace('mods=1', 'mods=2'),
                   text.replace('mode=native', 'mode=toolkit'), text.replace('kind=sp', 'kind=mp'),
                   text + '[QUEUE_TEST] FAIL release preflight missing mod\n']
        for value in broken:
            with self.subTest(value=value):
                self.assertEqual('failed', self.verify(value)['outcomes'][0]['status'])
        self.assertTrue(startup.complete(self.selection, 'client1', text))
        self.assertFalse(startup.complete(self.selection, 'server', text))
        self.assertFalse(startup.complete(self.selection, 'client1', text + lines[-1]))
        self.assertFalse(startup.complete(self.selection, 'client1', '[STARTUP_TEST] COMPLETE case=loaded-other\n'))

    def test_mp_requires_real_server_readiness(self):
        self.selection['kind'] = 'mp'
        self.assertTrue(self.verify(self.logs())['issues'])
        path = self.root / 'server-launch.log'
        for server in ('', '[STARTUP_TEST] SERVER_READY\n' * 2):
            path.write_text(server)
            self.assertTrue(self.verify(self.logs())['issues'])
        path.write_text('[STARTUP_TEST] SERVER_READY\n')
        self.assertEqual([], self.verify(self.logs())['issues'])

    def room_selection(self, mode='migrate'):
        return dict(self.selection, kind='mp', mods=['ZombieBuddy', 'PZToolkitJavaPatches'],
                    options={'world_template': '/fixture/world', 'room_state_roundtrip': mode})

    def room_logs(self, mode='migrate'):
        return ('[PZToolkitJavaPatches] Room state persistence loaded: legacy equal flags; provenance will be added on save\n'
                + ('[PZToolkitJavaPatches] Room state persistence serialized: bound owner provenance\n' if mode == 'migrate' else '')
                + '[PZToolkitJavaPatches] Room state persistence loaded: validated provenance\n'
                + '[ROOM_STATE_TEST] COMPLETE mode=' + mode + '\n[STARTUP_TEST] SERVER_READY\n')

    def verify_rooms(self, server):
        (self.root / 'server-launch.log').write_text(server)
        return self.verify(self.logs())

    def test_room_roundtrip_valid_options_and_complete_logs(self):
        for mode in ('migrate', 'reload'):
            with self.subTest(mode=mode):
                self.selection = self.room_selection(mode)
                startup.validate(self.selection)
                result = self.verify_rooms(self.room_logs(mode))
                self.assertEqual(result['issues'], [])
                self.assertEqual(result['outcomes'][0]['status'], 'passed')
                self.assertIn('without player walking', result['evidence']['limits'][0])

    def test_room_roundtrip_invalid_option_types_and_dependencies(self):
        invalid = []
        for value in (None, True, 1, [], {}, '', 'roundtrip'):
            selection = self.room_selection(); selection['options']['room_state_roundtrip'] = value; invalid.append(selection)
        for value in (None, True, [], {}, '', ' ', 'relative/world'):
            selection = self.room_selection(); selection['options']['world_template'] = value; invalid.append(selection)
        for value in (None, True, [], 'PZToolkitJavaPatches', ['PZSurvivorToolkit']):
            selection = self.room_selection(); selection['mods'] = value; invalid.append(selection)
        for value in (None, True, [], 'migrate'):
            selection = self.room_selection(); selection['options'] = value; invalid.append(selection)
        selection = self.room_selection(); del selection['options']['world_template']; invalid.append(selection)
        selection = self.room_selection(); selection['kind'] = 'sp'; invalid.append(selection)
        for selection in invalid:
            with self.subTest(selection=selection), self.assertRaises(ValueError): startup.validate(selection)

    def test_room_roundtrip_missing_duplicate_wrong_mode_and_failed_markers(self):
        for mode in ('migrate', 'reload'):
            self.selection = self.room_selection(mode)
            good = self.room_logs(mode)
            complete = '[ROOM_STATE_TEST] COMPLETE mode=' + mode + '\n'
            variants = [good.replace(complete, ''), good + complete,
                        good.replace(complete, '[ROOM_STATE_TEST] COMPLETE mode=other\n'),
                        good + '[ROOM_STATE_TEST] COMPLETE mode=other\n', good + '[ROOM_STATE_TEST] FAIL injected\n',
                        good.replace('Room state persistence loaded: validated provenance', 'unrelated load message'),
                        good.replace(complete, '').replace('[STARTUP_TEST] SERVER_READY\n',
                                                           '[STARTUP_TEST] SERVER_READY\n' + complete)]
            if mode == 'migrate':
                variants.append(good.replace('Room state persistence serialized: bound owner provenance', 'unrelated save message'))
            for server in variants:
                with self.subTest(mode=mode, server=server):
                    result = self.verify_rooms(server)
                    self.assertTrue(result['issues'])
                    self.assertEqual(result['outcomes'][0]['status'], 'failed')

    def test_actual_server_room_fixture_roundtrip_reload_and_failure_readiness(self):
        lua = shutil.which('lua5.4') or shutil.which('lua') or shutil.which('luajit')
        if not lua:
            self.skipTest('Lua interpreter unavailable')
        code = r'''
local source=arg[1]
local cases={{},{mode='migrate'},{mode='reload'},{mode='migrate',broken='missing'},
 {mode='migrate',broken='same-room'},{mode='migrate',broken='same-id'},
 {mode='reload',broken='flags'},{mode='reload',broken='access-flags'},
 {mode='migrate',broken='save'},{mode='migrate',broken='load'},
 {mode='migrate',broken='native-loss'},{mode='migrate',broken='ids'},{mode='unknown',broken='mode'}}
for _,case in ipairs(cases)do
 local handlers,logs={},{}
 Events={OnServerStarted={Add=function(fn)handlers.started=fn end}}
 package.loaded.QueueTestSelection={options={room_state_roundtrip=case.mode}}
 print=function(text)logs[#logs+1]=text end
 local mutations=0
 local function room(id,name)
  local r={id=id,name=name,explored=false,roof=false}
  function r:getID()return self.id end
  function r:getName()return self.name end
  function r:getX()return 10707 end
  function r:getY()return 9484 end
  function r:getZ()return 0 end
  function r:getW()return 1 end
  function r:getH()return 4 end
  function r:isExplored()return self.explored end
  function r:isRoofFixed()return self.roof end
  function r:setExplored(value)mutations=mutations+1;self.explored=value end
  function r:setRoofFixed(value)mutations=mutations+1;self.roof=value end
  return r
 end
 local base,access,other=room(107,'hall'),room(306,'hall'),room(500,'other')
 if case.mode=='reload'and not case.broken then base.explored=true;access.roof=true end
 if case.broken=='access-flags'then base.explored=true end
 if case.broken=='same-id'then access.id=base.id end
 local saves,loads,queries=0,0,0
 ArrayList={new=function()return {values={},size=function(self)return #self.values end,
  get=function(self,index)return self.values[index+1]end}end}
 local grid={}
 function grid:getRoomsIntersecting(x,y,w,h,found)
  assert(x==10707 and y==9484 and w==1 and h==4,'query changed')
  queries=queries+1
  found.values=case.broken=='missing'and {access,other}or case.broken=='same-room'and {base,base}or {access,other,base}
 end
 local saved
 function grid:save()
  saves=saves+1
  if case.broken=='save'then error('injected save')end
  saved={base.explored,base.roof,access.explored,access.roof}
  assert(saved[1]and not saved[2]and not saved[3]and saved[4],'fixture did not set divergent flags')
 end
 function grid:load()
  loads=loads+1
  if case.broken=='load'then error('injected load')end
  base.explored,base.roof,access.explored,access.roof=saved[1],saved[2],saved[3],saved[4]
  if case.broken=='native-loss'then base.explored=false end
  if case.broken=='ids'then access.id=307 end
 end
 function getWorld()return {getMetaGrid=function()return grid end}end
 dofile(source);handlers.started()
 local ready,complete,failed=0,0,0
 for _,line in ipairs(logs)do
  if line=='[STARTUP_TEST] SERVER_READY'then ready=ready+1 end
  if line:find('[ROOM_STATE_TEST] COMPLETE ',1,true)then complete=complete+1 end
  if line:find('[ROOM_STATE_TEST] FAIL ',1,true)then failed=failed+1 end
 end
 if case.broken then assert(ready==0 and complete==0 and failed==1,'failure escaped server readiness gate')
 elseif case.mode then
  assert(ready==1 and complete==1 and failed==0 and queries==2,'successful room check not completed')
  assert(saves==(case.mode=='migrate'and 1 or 0)and loads==saves,'reload mutated/reloaded the started world')
  assert(mutations==(case.mode=='migrate'and 4 or 0),'unexpected room state mutation')
  assert(logs[#logs-1]=='[ROOM_STATE_TEST] COMPLETE mode='..case.mode,'readiness preceded completion')
 else assert(ready==1 and complete==0 and failed==0 and queries==0 and saves==0 and loads==0,'plain readiness changed')end
 if case.mode=='reload'then assert(mutations==0 and saves==0 and loads==0,'reload must inspect only')end
end
'''
        result = subprocess.run([lua, '-', str(ROOT / 'tests/native_queue/startup/server/ZZStartupServer.lua')],
                                input=code, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_actual_bootstrap_waits_for_game_start_tick_square_and_connection(self):
        lua = shutil.which('lua5.4') or shutil.which('lua') or shutil.which('luajit')
        if not lua:
            self.skipTest('Lua interpreter unavailable')
        code = r'''
local source=arg[1]
for index,kind in ipairs({'sp','mp','mp'})do
 local handlers,logs={},{}
 Events=setmetatable({},{__index=function(self,key)
  local event={Add=function(fn)handlers[key]=fn end};rawset(self,key,event);return event
 end})
 local connection=index==3 and {username='animal-fixture',password='isolated-native-only'} or nil
 package.loaded.QueueTestSelection={kind=kind,mode='native',port=17463,options={startup_connection=connection}}
 local ingame,connected,player=false,false,nil
 function isClient()return connected end
 function isIngameState()return ingame end
 function getPlayer()return player end
 print=function(s)logs[#logs+1]=s end
 local connects,worlds,nexts=0,0,0
 MainScreen={instance={charCreationProfession={getIsVisible=function()return true end,onOptionMouseDown=function()nexts=nexts+1 end},
  charCreationMain={onOptionMouseDown=function()nexts=nexts+1 end},setDefaultSandboxVars=function()end}}
 MapSpawnSelect={instance={getIsVisible=function()return false end,useDefaultSpawnRegion=function()end,setVisible=function()end}}
 ConnectToServer={instance={connect=function(self,screen,name,user,password,host,unused,port)
  assert(user==(connection and connection.username or 'client1')and port=='17463')
  assert(password==(connection and connection.password or 'smoke-local-only'),'explicit credentials must reach native connect')
  connects=connects+1
 end}}
 function getCore()return {setOptionPauseOnFocusloss=function()end}end
 local world={setGameMode=function()end,setWorld=function(self,name)assert(name=='QueueStartup');worlds=worlds+1 end,setMap=function()end}
 function getWorld()return world end
 function getSandboxOptions()return {getOptionByName=function()return {setValue=function(self,value)assert(value==6)end}end,toLua=function()end}end
 local copied={};ActiveMods={getById=function()return {getMods=function()return {clear=function()end,add=function(self,id)copied[#copied+1]=id end}end}end}
 function getActivatedMods()return {size=function()return 1 end,get=function()return 'PZSurvivorToolkit'end}end
 dofile(source)
 handlers.OnTick();assert(#logs==0,'menu ticks are not startup evidence')
 handlers.OnMainMenuEnter();handlers.OnMainMenuEnter();handlers.OnPreUIDraw();handlers.OnPreUIDraw()
 assert(nexts==2,'character creation must advance only once')
 assert(connects==(kind=='mp'and 1 or 0)and worlds==(kind=='sp'and 1 or 0))
 if kind=='sp'then assert(copied[1]=='PZSurvivorToolkit'and MainScreen.instance.createWorld)end
 handlers.OnGameStart();assert(#logs==1,'OnGameStart alone is insufficient')
 handlers.OnTick();assert(#logs==1)
 ingame=true;handlers.OnTick();assert(#logs==1,'missing player must wait')
 local square=nil;local dead=true;local online=-1
 player={isDead=function()return dead end,getSquare=function()return square end,getOnlineID=function()return online end}
 handlers.OnTick();assert(#logs==1)
 dead=false;handlers.OnTick();assert(#logs==1,'unloaded square must wait')
 square={getX=function()return 10835 end,getY=function()return 10144 end,getZ=function()return 0 end}
 if kind=='mp'then
  handlers.OnTick();assert(#logs==1,'disconnected MP must wait')
  connected=true;handlers.OnTick();assert(#logs==1,'unassigned online identity must wait');online=7
 end
 handlers.OnTick();assert(#logs==3 and logs[2]:find('square=10835,10144,0 tick=true',1,true))
 assert(logs[3]=='[STARTUP_TEST] COMPLETE case=loaded')
 handlers.OnTick();assert(#logs==3,'completion must occur exactly once')
end
'''
        result = subprocess.run([lua, '-', str(ROOT / 'tests/native_queue/startup/client/ZZStartup.lua')],
                                input=code, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
