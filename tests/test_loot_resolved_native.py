"""Boundary tests for the native loot opt-in, authority handshake and captured receipts."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import native
from queue_checks.adapters import loot_resolved as A
LUAJIT = shutil.which('luajit')

F = ROOT / 'tests/chunk_integration/loot_resolved_runtime'
spec = importlib.util.spec_from_file_location('_loot_build_contract', F / 'build.py')
BUILD = importlib.util.module_from_spec(spec); spec.loader.exec_module(BUILD)
spec = importlib.util.spec_from_file_location('_loot_compare_contract', F / 'compare.py')
COMPARE = importlib.util.module_from_spec(spec); spec.loader.exec_module(COMPARE)


class LootResolvedNative(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.selection = dict(suite=A.SUITE, cases=['bank'], kind='sp', mode='toolkit', clients=1,
            languages=['EN'], mods=A.MODS, resources={'exclusive': True},
            options=dict(loot_runtime_mode='control', preload_toolkit_fonts=True,
                         mod_sources={A.MOD: str(self.root / 'explicit-source')}))
        source = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in F.iterdir() if p.is_file()}
        for name, path in [('ResolvedCandidate.java', F.parent/'loot_resolved/ResolvedCandidate.java'),
                           ('../loot_resolved/run.py', F.parent/'loot_resolved/run.py')]:
            source[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        self.receipt = dict(format=1, test_only=True, mode='control', sources=source,
            native_hashes=BUILD.load_guards(), headless_checks=['missing-token','already-loaded','initial-definition','preload'],
            success_path_checked=False, entry_point='lootResolvedRuntimeRun',
            terminal_marker='[LOOT_RESOLVED_RUNTIME] FINISH status=', required_preload=A.BOOT)
        self.cache = self.root / 'client1'
        self.mod(self.cache)

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True); path.write_text(text)

    def mod(self, cache, receipt=None, manifest=True):
        value = self.receipt if receipt is None else receipt
        layer = cache/'mods'/A.MOD
        self.write(layer/'42/mod.info', (F/'mod.info.template').read_text())
        self.write(layer/'42/media/lua/shared/ZZLootResolvedRuntime.lua', (F/'ZZLootResolvedRuntime.lua').read_text())
        for name in (A.BOOT, A.RUNTIME):
            path = layer/name; path.parent.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(path, 'w') as jar:
                jar.writestr('META-INF/loot-runtime-inputs.json', json.dumps(value))
                if name == A.BOOT:
                    jar.writestr('META-INF/MANIFEST.MF', 'Manifest-Version: 1.0\nZB-Preload: '+str(manifest).lower()+'\n\n')
                    jar.writestr('toolkit/lootresolved/bootstrap/token.txt', 'a'*32+'\n')
                    jar.writestr('toolkit/lootresolved/bootstrap/mode.txt', value['mode']+'\n')
        fonts = cache/'mods/PZToolkitJavaPatches/42'
        self.write(fonts/'mod.info', 'id=PZToolkitJavaPatches\njavaPkgName=net.alexredby.pztoolkitjavapatches\njavaJarFile=media/java/PZToolkitJavaPatches.jar\n')
        self.write(fonts/'media/java/PZToolkitJavaPatches.jar', 'ordinary runtime')
        path=fonts/'media/bootstrap/PZToolkitFonts.jar';path.parent.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(path,'w') as jar: jar.writestr('META-INF/MANIFEST.MF','Manifest-Version: 1.0\nZB-Preload: true\n\n')

    def event(self, kind, value): return A.MARKER+kind+' '+json.dumps(value)+'\n'

    def authority(self, source, role='client1'):
        return self.event('AUTHORITY', dict(role=role, case='bank', runtimeMode='control', status='complete',cases=8,source=source))

    def completed(self):
        return self.event('COMPLETE', dict(role='client1',case='bank',runtimeMode='control',status='complete',authority=True))

    def finish(self): return '[LOOT_RESOLVED_RUNTIME] FINISH status=complete cases=8 reason=\n'

    def bank(self, pid=100):
        h=self.receipt['native_hashes']['zombie/inventory/ItemPickerJava.class']
        for process in ({100,pid}):
            self.write(self.cache/f'loot-resolved-runtime-activation-{process}.txt',
                f'state=active\nmode=control\npid={process}\ndefinitions=1\nrng_audit_definitions=1\ninput={h}\noutput={h}\n')
        self.write(self.cache/'loot-resolved-runtime-status.txt',f'status=complete\nmode=control\npid={pid}\ncases=8\nreason=\nsource_square=uncovered\nlive_script_reload=uncovered\nmodule_item_replacement=uncovered\n')
        rows=['kind\tcase\tdetail\n']
        for case in COMPARE.EXPECTED_CASES:
            rows.append(f'BEGIN\t{case}\tseed\n')
            if case in ('direct-real-items','bag-real-items'):rows.append(f'ITEM\t{case}\tBase.Nails:initialized=true\n')
            if case=='native-nested-fill-reentrant':rows.append(f'FILL\t{case}\tactual callback\n')
            rows.extend([f'CLEANUP\t{case}\tdone\n',f'END\t{case}\trng=1\n'])
        self.write(self.cache/'loot-resolved-runtime.tsv',''.join(rows))

    def run_files(self, host=False):
        self.bank(200 if host else 100)
        runtime=dict(project=str(ROOT),roles={'client1':{'cache':str(self.cache)}})
        processes={'client1':{'pid':100}}
        if host:
            self.selection['kind']='mp';self.selection['options']['mp_host']=True
            runtime['host_cache']=str(self.cache)
            processes['server']=dict(pid=200,parent_role='client1',cache=str(self.cache))
            request=dict(role='client1',case='bank',runtimeMode='control',onlineID=3)
            self.write(self.root/'client1-launch.log',self.event('REQUEST',request)+self.authority('server-response')+self.completed())
            request['role']='server'
            self.write(self.root/'server-launch.log',self.event('REQUEST',request)+A.DIAGNOSTIC+'\n'+self.finish()+self.authority('server-main-tick','server'))
        else:self.write(self.root/'client1-launch.log',A.DIAGNOSTIC+'\n'+self.finish()+self.authority('sp-main-tick')+self.completed())
        self.write(self.root/'runtime.json',json.dumps(runtime));self.write(self.root/'execution.json',json.dumps({'processes':processes}))

    def test_strict_selection_and_optimizer_opt_in(self):
        A.validate(self.selection)
        for update in ({'clients':True},{'languages':['RU']},{'mode':'native'},{'resources':{}},{'kind':'mp'}):
            with self.subTest(update=update), self.assertRaises(ValueError):A.validate(dict(self.selection,**update))
        for key,value in [('preload_toolkit_fonts',False),('loot_runtime_mode','patched'),('world_template','/old')]:
            s=dict(self.selection, options=dict(self.selection['options'],**{key:value}))
            with self.subTest(key=key),self.assertRaises(ValueError):A.validate(s)
        archive=self.root/'official.zip';archive.write_bytes(b'fixture')
        s=dict(self.selection, options=dict(self.selection['options'],optimizer_archive=str(archive)))
        with self.assertRaises(ValueError):A.validate(s)
        s['options']['optimizer_prewarm']=True;A.validate(s)

    def test_one_composed_loader_parameter_and_ordinary_approvals(self):
        value=native.font_preload(self.cache,self.selection,project=ROOT)
        self.assertEqual(value.count(',patches_jar='),1)
        parts=value.removeprefix(',patches_jar=').split(';')
        self.assertEqual(len(parts),2)
        self.assertTrue(parts[0].endswith('PZToolkitFonts.jar:net.alexredby.pztoolkitbootstrap'))
        self.assertTrue(parts[1].endswith('PZLootResolvedBootstrap.jar:'+A.PACKAGE))
        approved=native._approvals(self.cache,['PZToolkitJavaPatches',A.MOD])
        self.assertEqual({x['jar_hash'] for x in approved},{native.sha256(self.cache/'mods/PZToolkitJavaPatches/42/media/java/PZToolkitJavaPatches.jar'),native.sha256(self.cache/'mods'/A.MOD/A.RUNTIME)})
        other=dict(self.selection,suite='startup')
        self.assertNotIn('PZLootResolvedBootstrap',native.font_preload(self.cache,other,project=ROOT))
        self.assertFalse((self.cache/A.TOKEN).exists())

    def test_foreign_sources_mode_and_manifest_cannot_arm(self):
        value=json.loads(json.dumps(self.receipt));value['sources']['Main.java']='0'*64;self.mod(self.cache,value)
        with self.assertRaisesRegex(ValueError,'Foreign/stale'):A.early_preload(self.cache,self.selection,project=ROOT)
        self.mod(self.cache,manifest=False)
        with self.assertRaisesRegex(ValueError,'manifest'):A.early_preload(self.cache,self.selection,project=ROOT)
        self.mod(self.cache)
        bad=dict(self.selection,options=dict(self.selection['options'],loot_runtime_mode='candidate'))
        with self.assertRaisesRegex(ValueError,'mode'):A.early_preload(self.cache,bad,project=ROOT)
        badcache=self.root/'bad;cache';self.mod(badcache)
        with self.assertRaisesRegex(ValueError,'separators'):A.early_preload(badcache,self.selection,project=ROOT)

    def test_token_stage_requires_actual_lua_owner_and_preserves_default_population_seed(self):
        runtime=dict(roles={'client1':{'cache':str(self.cache)}},fixture={'mods':[]})
        self.write(self.cache/'smoke-user.txt','client1\n')
        with self.assertRaisesRegex(ValueError,'actual owned'):A.stage(ROOT,self.root,self.root/'game',self.root/'jdk',self.selection,{},runtime)
        self.assertFalse((self.cache/A.TOKEN).exists())
        self.write(self.cache/'Lua/smoke-user.txt','foreign\n')
        with self.assertRaises(ValueError):A.stage(ROOT,self.root,self.root/'game',self.root/'jdk',self.selection,{},runtime)
        self.write(self.cache/'Lua/smoke-user.txt','client1\n')
        with patch.object(A.optimizer_profile,'stage') as optimizer:A.stage(ROOT,self.root,self.root/'game',self.root/'jdk',self.selection,{},runtime)
        optimizer.assert_called_once()
        self.assertEqual((self.cache/A.TOKEN).read_text(),'a'*32+'\n')
        starter=(self.cache/'mods/ActionQueueTest/42/media/lua/client/ZZStartup.lua').read_text()
        self.assertIn('HOST_REQUEST',starter);self.assertIn(A.SEED,starter)
        self.assertIn("getOptionByName('Zombies'):setValue(3)",starter)
        self.assertNotIn("getOptionByName('Zombies'):setValue(6)",starter)
        self.assertEqual(runtime['fixture']['sandbox'],A.SANDBOX)
        with self.assertRaisesRegex(ValueError,'fresh'):A.stage(ROOT,self.root,self.root/'game',self.root/'jdk',self.selection,{},runtime)

    def test_startup_loaded_and_completion_alone_never_finish_suite(self):
        self.assertFalse(A.complete(self.selection,'client1','[STARTUP_TEST] COMPLETE case=loaded\n'))
        self.assertFalse(A.complete(self.selection,'client1',self.completed()))
        self.assertFalse(A.complete(self.selection,'client1',self.authority('sp-main-tick')+self.completed()))
        good=self.finish()+self.authority('sp-main-tick')+self.completed()
        self.assertTrue(A.complete(self.selection,'client1',good))
        self.assertFalse(A.complete(self.selection,'client1',good+self.completed()))
        self.assertFalse(A.complete(self.selection,'client1',good.replace('status=complete cases=8','status=failed cases=8')))

    def test_capture_requires_real_bank_receipts_and_matching_execution_pids(self):
        for host in (False,True):
            with self.subTest(host=host):
                self.run_files(host)
                result=A.verify(self.root,self.selection,{})
                self.assertEqual(result['issues'],[]);self.assertEqual(result['outcomes'][0]['status'],'captured')
                path=self.cache/'loot-resolved-runtime-status.txt';old=path.read_text()
                path.write_text(old.replace('pid=200' if host else 'pid=100','pid=999'))
                self.assertTrue(A.verify(self.root,self.selection,{})['issues'])
                path.write_text(old);path.unlink()
                self.assertTrue(A.verify(self.root,self.selection,{})['issues'])
                self.selection['kind']='sp';self.selection['options'].pop('mp_host',None)

    def test_failed_activation_and_diagnostic_duplicates_remain_visible(self):
        self.run_files()
        activation=self.cache/'loot-resolved-runtime-activation-100.txt';old=activation.read_text()
        activation.write_text(old.replace('state=active','state=disabled'))
        self.assertTrue(A.verify(self.root,self.selection,{})['issues'])
        activation.write_text(old)
        log=self.root/'client1-launch.log';log.write_text(log.read_text()+A.DIAGNOSTIC+'\n')
        self.assertTrue(A.verify(self.root,self.selection,{})['issues'])

    def test_optimizer_ready_marker_matches_actual_sp_and_host_contract(self):
        archive=self.root/'official.zip';archive.write_bytes(b'fixture')
        self.selection['options'].update(optimizer_archive=str(archive),optimizer_prewarm=True)
        for host in (False,True):
            self.run_files(host)
            path=self.root/'client1-launch.log';original=path.read_text()
            path.write_text('[OptimizerTrial] bridge ready mode=Optimized\n'+original)
            self.assertTrue(A.verify(self.root,self.selection,{})['issues'])
            profile='multiplayer client=true' if host else 'singleplayer client=false'
            path.write_text('[OptimizerTrial] bridge ready mode='+profile+' server=false session=1\n'+original)
            if host:
                path=self.root/'server-launch.log';path.write_text('[OptimizerTrialProbe] native server resources=1 overlayAbsent=true\n'+path.read_text())
            self.assertEqual(A.verify(self.root,self.selection,{})['issues'],[])
            self.selection['kind']='sp';self.selection['options'].pop('mp_host',None)

    def test_host_completion_without_server_request_or_response_is_rejected(self):
        self.run_files(True)
        log=self.root/'server-launch.log';text=log.read_text()
        log.write_text(text.replace(A.MARKER+'REQUEST ', '[IGNORED] REQUEST '))
        self.assertTrue(A.verify(self.root,self.selection,{})['issues'])
        log.write_text(text.replace('"onlineID": 3','"onlineID": 4'))
        self.assertTrue(A.verify(self.root,self.selection,{})['issues'])


@unittest.skipUnless(LUAJIT, 'LuaJIT is unavailable')
class LootLuaHandshake(unittest.TestCase):
    def run_lua(self, body):
        harness = r"""
local root=arg[1]
local JSON=assert(loadfile(root..'/tests/native_queue/health/shared/QueueHealthEvents.lua'))()
local function state(host,server)
 local e=setmetatable({outputs={},handlers={},sent={},bankRuns=0,bankStatus='not-run'},{__index=_G})
 e.selection={suite='loot-resolved',kind=host and 'mp' or 'sp',options={loot_runtime_mode='control'}}
 e.Events=setmetatable({}, {__index=function(t,k)local v={Add=function(f)e.handlers[k]=e.handlers[k]or{};table.insert(e.handlers[k],f)end};rawset(t,k,v);return v end})
 e.fire=function(name,...)for _,f in ipairs(e.handlers[name]or{})do f(...)end end
 e.print=function(v)table.insert(e.outputs,v)end
 e.require=function(n)return n=='QueueTestSelection'and e.selection or JSON end
 e.isClient=function()return host and not server end;e.isServer=function()return server end
 e.isIngameState=function()return true end;e.getTimestampMs=function()return 1000 end
 e.player={isDead=function()return false end,getSquare=function()return{}end,getOnlineID=function()return 3 end,getUsername=function()return 'client1'end}
 e.getPlayer=function()return e.player end
 e.getFileReader=function()return{readLine=function()return 'client1'end,close=function()end}end
 e.lootResolvedRuntimeStatus=function()return e.bankStatus end
 e.lootResolvedRuntimeRun=function()e.bankRuns=e.bankRuns+1;e.bankStatus='complete';e.print('[LOOT_RESOLVED_RUNTIME] FINISH status=complete cases=8 reason=');return true end
 e.sendClientCommand=function(m,c,a)e.sent={module=m,command=c,args=a}end
 e.sendServerCommand=function(p,m,c,a)e.sent={module=m,command=c,args=a}end
 local side=server and 'server/ZZLootResolvedServer.lua'or'client/ZZLootResolved.lua'
 local code=assert(loadfile(root..'/tests/native_queue/loot-resolved/'..side));setfenv(code,e);code()
 return e
end
local function log(e)return table.concat(e.outputs,'\n')end
"""
        result=subprocess.run([LUAJIT,'-',str(ROOT)],input=harness+body+"\nprint('LOOT_HANDSHAKE_PASS')\n",
                              text=True,capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('LOOT_HANDSHAKE_PASS',result.stdout)

    def test_sp_waits_for_valid_game_tick_and_runs_once(self):
        self.run_lua("""
local e=state(false,false);e.fire('OnTick');assert(e.bankRuns==0)
e.fire('OnGameStart');e.fire('OnTick');e.fire('OnTick');assert(e.bankRuns==1)
assert(log(e):find('AUTHORITY',1,true)<log(e):find('COMPLETE',1,true))
""")

    def test_host_requires_request_server_tick_and_response_before_complete(self):
        self.run_lua("""
local c,s=state(true,false),state(true,true)
c.fire('OnGameStart');c.fire('OnTick');assert(c.bankRuns==0 and c.sent.command=='RunBank')
assert(not log(c):find('COMPLETE',1,true))
s.fire('OnClientCommand',c.sent.module,c.sent.command,s.player,c.sent.args);assert(s.bankRuns==0)
s.fire('OnTick');assert(s.bankRuns==1 and s.sent.command=='BankStatus')
c.fire('OnServerCommand',s.sent.module,s.sent.command,s.sent.args)
assert(c.bankRuns==0 and log(c):find('COMPLETE',1,true))
c.fire('OnServerCommand',s.sent.module,s.sent.command,s.sent.args);assert(log(c):find('FAIL',1,true))
""")

    def test_foreign_actor_or_missing_api_never_completes(self):
        self.run_lua("""
local s=state(true,true);s.player.getUsername=function()return 'client2'end
s.fire('OnClientCommand','LootResolvedNativeTest','RunBank',s.player,{role='client1',case='bank',runtimeMode='control'})
s.fire('OnTick');assert(s.bankRuns==0 and log(s):find('FAIL',1,true))
local c=state(false,false);c.lootResolvedRuntimeRun=false;c.fire('OnGameStart');c.fire('OnTick')
assert(log(c):find('FAIL',1,true)and not log(c):find('COMPLETE',1,true))
""")


if __name__=='__main__':unittest.main()
