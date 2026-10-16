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
                f'[QUEUE_TEST] PREFLIGHT_COMPLETE mods=1 mode={mode}\n'
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
