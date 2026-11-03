"""The common readiness barrier is independent of game processes and GUI access."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.preflight import ClientPreflight, PREFIX, RELEASE, SETUP


class ClientPreflightTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.roles = ['client1', 'client2']
        self.token = 'a' * 32
        self.selection = {'kind': 'mp', 'clients': 2}
        self.runtime = {'fixture': {'preflight': {'version': 2, 'token': self.token, 'roles': self.roles,
                                                'setup_timeout_seconds': 120}},
                        'roles': {role: {'cache': str(self.root / role)} for role in self.roles}}
        for role in self.roles:
            (self.root / role / 'Lua').mkdir(parents=True)
        self.monitor = ClientPreflight(self.root, self.runtime, self.selection)
        self.execution = {}

    def receipt(self, role, event='ready', **fields):
        return PREFIX + json.dumps(dict(event=event, token=self.token, role=role, **fields)) + '\n'

    def test_every_required_role_must_pass_before_either_grant(self):
        logs = {'client1': self.receipt('client1'), 'client2': ''}
        self.assertFalse(self.monitor.check(logs, self.execution))
        self.assertFalse((self.root / 'client1/Lua' / SETUP).exists())
        logs['client2'] = self.receipt('client2')
        self.assertFalse(self.monitor.check(logs, self.execution))
        self.assertEqual((self.root / 'client1/Lua' / SETUP).read_text(), self.token + '\n')
        self.assertFalse((self.root / 'client1/Lua' / RELEASE).exists())
        logs['client1'] += self.receipt('client1', 'setup-ready')
        self.assertFalse(self.monitor.check(logs, self.execution))
        logs['client2'] += self.receipt('client2', 'setup-ready')
        self.assertTrue(self.monitor.check(logs, self.execution))
        self.assertTrue(self.execution['preflight']['released'])
        for role in self.roles:
            self.assertEqual((self.root / role / 'Lua' / RELEASE).read_text(), self.token + '\n')

    def test_role_failure_wins_over_readiness_and_later_completion(self):
        logs = {role: self.receipt(role) for role in self.roles}
        logs['client2'] += self.receipt('client2', 'failed', phase='preflight', reason='viewport mismatch')
        logs['client2'] += '[QUEUE_CHECK] {"event":"complete","failed":0}\n'
        with self.assertRaisesRegex(RuntimeError, 'viewport mismatch'):
            self.monitor.check(logs, self.execution)
        self.assertEqual({key: self.execution['setup_failure'][key] for key in ('kind', 'role', 'phase', 'reason')},
                         {'kind': 'client-preflight', 'role': 'client2', 'phase': 'preflight', 'reason': 'viewport mismatch'})
        self.assertFalse((self.root / 'client1/Lua' / SETUP).exists())

    def test_unterminated_or_embedded_markers_are_not_receipts(self):
        logs = {'client1': 'prefix ' + self.receipt('client1'), 'client2': self.receipt('client2').rstrip('\n')}
        self.assertFalse(self.monitor.check(logs, self.execution))
        self.assertEqual(self.execution['preflight']['ready'], {})

    def test_native_lua_log_prefix_is_supported(self):
        logs = {role: '[02-11-26 20:10:00.123] LOG  : Lua , 123> ' + self.receipt(role) for role in self.roles}
        self.monitor.check(logs, self.execution)
        self.assertTrue(self.monitor.setup_released)

    def test_stale_malformed_or_wrong_role_records_fail_closed(self):
        for line in (PREFIX + 'bad\n', self.receipt('client2'), self.receipt('client1').replace(self.token, 'b' * 32)):
            with self.subTest(line=line), self.assertRaises(RuntimeError):
                self.monitor.check({'client1': line}, {})

    def test_setup_cannot_claim_success_before_runner_grant(self):
        with self.assertRaisesRegex(RuntimeError, 'preceded required preflights'):
            self.monitor.check({'client1': self.receipt('client1') + self.receipt('client1', 'setup-ready')}, self.execution)

    def test_setup_started_pause_is_role_bound_and_does_not_release_gameplay(self):
        logs = {role: self.receipt(role) for role in self.roles}
        self.monitor.check(logs, self.execution)
        for role, paused in (('client1', True), ('client2', None)):
            logs[role] += self.receipt(role, 'setup-started', paused=paused)
        self.assertFalse(self.monitor.check(logs, self.execution))
        self.assertEqual(self.execution['preflight']['setup_started'],
                         {'client1': {'line': 2, 'paused': True}, 'client2': {'line': 2, 'paused': None}})
        self.assertFalse((self.root / 'client1/Lua' / RELEASE).exists())

    def test_setup_started_rejects_nonboolean_pause_and_pregrant_receipts(self):
        with self.assertRaises(RuntimeError):
            self.monitor.check({'client1': self.receipt('client1') +
                               self.receipt('client1', 'setup-started', paused=True)}, self.execution)
        logs = {role: self.receipt(role) for role in self.roles}
        self.monitor.check(logs, self.execution)
        for paused in (0, 1, 'true', [], {}):
            with self.subTest(paused=paused), self.assertRaises(RuntimeError):
                self.monitor.check(dict(logs, client1=logs['client1'] +
                                       self.receipt('client1', 'setup-started', paused=paused)), self.execution)

    def test_setup_failure_blocks_case_grant_for_every_peer(self):
        logs = {role: self.receipt(role) for role in self.roles}
        self.monitor.check(logs, self.execution)
        logs['client1'] += self.receipt('client1', 'setup-ready')
        logs['client2'] += self.receipt('client2', 'failed', phase='fixture-setup', reason='fixture spawn failed')
        with self.assertRaisesRegex(RuntimeError, 'fixture spawn failed'):
            self.monitor.check(logs, self.execution)
        self.assertEqual(self.execution['setup_failure']['phase'], 'fixture-setup')
        self.assertFalse((self.root / 'client1/Lua' / RELEASE).exists())

    def test_legacy_failure_marker_is_structured_and_first_failure_is_preserved(self):
        existing = {'kind': 'original', 'role': 'client1', 'phase': 'readiness', 'reason': 'first'}
        self.execution['setup_failure'] = existing
        with self.assertRaisesRegex(RuntimeError, 'bad viewport'):
            self.monitor.check({'client2': '[QUEUE_TEST] FAIL release preflight bad viewport\n'}, self.execution)
        self.assertIs(self.execution['setup_failure'], existing)

    def test_missing_config_and_preexisting_grants_require_fresh_snapshot(self):
        for config in (None, {}, {'version': 1, 'token': self.token, 'roles': ['client1']}):
            with self.subTest(config=config), self.assertRaises(ValueError):
                ClientPreflight(self.root, dict(self.runtime, fixture={'preflight': config}), self.selection)
        (self.root / 'client1/Lua' / SETUP).write_text(self.token + '\n')
        with self.assertRaisesRegex(ValueError, 'already exists'):
            ClientPreflight(self.root, self.runtime, self.selection)

    def test_final_audit_detects_late_failure_without_granting_execution(self):
        logs = {role: self.receipt(role) for role in self.roles}
        self.monitor.check(logs, self.execution, release=False)
        self.assertFalse((self.root / 'client1/Lua' / SETUP).exists())
        logs['client2'] += self.receipt('client2', 'failed', phase='preflight', reason='late failure')
        with self.assertRaisesRegex(RuntimeError, 'late failure'):
            self.monitor.check(logs, self.execution, release=False)

    def test_generic_failure_is_structured_only_while_setup_is_pending(self):
        self.monitor.record_exception(self.execution, OSError('launcher unavailable'))
        self.assertEqual(self.execution['setup_failure']['phase'], 'readiness')
        self.assertEqual(self.execution['setup_failure']['reason'], 'launcher unavailable')
        self.monitor.record_exception(self.execution, RuntimeError('later failure'))
        self.assertEqual(self.execution['setup_failure']['reason'], 'launcher unavailable')
        self.monitor.record_exception({}, KeyboardInterrupt('user stopped'))
        later = {}
        self.monitor.released = True
        self.monitor.record_exception(later, RuntimeError('gameplay action failed'))
        self.assertNotIn('setup_failure', later)

    def test_fixture_entrypoints_use_common_lifecycle_registration(self):
        # Manual cart scenario scripts are loaded by the already admitted
        # QueueCartStartup tick; their standalone console use stays independent.
        violations = []
        for path in (ROOT / 'tests/native_queue').rglob('*.lua'):
            if ('server' in path.parts or path.name.lower().endswith('server.lua')
                    or path.name in ('QueuePreflight.lua', 'ZZReleasePreflight.lua', 'check.lua', 'protocol.lua')
                    or path.name.endswith('Check.lua')
                    or 'wooden_cart_motion' in path.parts and path.name.startswith('scenario-')):
                continue
            for number, line in enumerate(path.read_text().splitlines(), 1):
                if 'Events.OnGameStart.Add(' in line or 'Events.OnTick.Add(' in line:
                    violations.append(str(path.relative_to(ROOT)) + ':' + str(number))
        self.assertEqual(violations, [])


class LuaPreflightTests(unittest.TestCase):
    def test_fixture_start_and_ticks_use_two_explicit_grants(self):
        lua = shutil.which('luajit') or shutil.which('lua')
        if not lua:
            self.skipTest('Lua interpreter unavailable')
        source = r'''
local path=arg[1]
local function environment()
 local env=setmetatable({},{__index=_G});env._G=env
 local events={};env.Events={}
 for _,name in ipairs({'OnGameStart','OnTick','OnTickEvenPaused'}) do
  local list={};events[name]=list
  env.Events[name]={Add=function(fn)list[#list+1]=fn end,Remove=function(fn)for i=#list,1,-1 do if list[i]==fn then table.remove(list,i)end end end}
 end
 local files,logs={},{}
 env.isServer=function()return false end
 env.getFileReader=function(name)
  local value=name=='smoke-user.txt' and 'client1' or files[name]
  if not value then return end
  return {readLine=function()return value end,close=function()end}
 end
 env.require=function(name)assert(name=='QueuePreflightConfig');return {token=string.rep('a',32),roles={'client1','client2'}}end
 env.print=function(line)logs[#logs+1]=line end
 local chunk=assert(loadfile(path));setfenv(chunk,env);local P=chunk()
 local function fire(name)for _,fn in ipairs(events[name])do fn()end end
 return P,files,logs,fire,env
end
local P,files,logs,fire,env=environment()
local nativeEvents=env.Events;local started,ticks=0,0
P.onGameStart(env.Events,function()
 assert(logs[#logs]:find('"event":"setup%-started"')and logs[#logs]:find('"paused":true'),
  'setup callback ran before token/role-bound pause-at-start evidence')
 started=started+1
end)
local tick=function()ticks=ticks+1 end;P.onTick(env.Events,tick)
-- Match the engine: a paused native client dispatches only EvenPaused.
-- Ordinary fixture ticks must stay gated even when startup is admitted.
local paused=true
env.isGamePaused=function()return paused end
local function frame()
 fire('OnTickEvenPaused')
 if not paused then fire('OnTick')end
end
fire('OnGameStart');frame();assert(started==0 and ticks==0)
files['queue-preflight-setup.txt']=string.rep('a',32)
frame();assert(started==0 and ticks==0,'setup token admitted work before raw readiness')
files['queue-preflight-setup.txt']=nil
P.complete();frame();assert(started==0 and ticks==0,'readiness bypassed the setup grant')
files['queue-preflight-setup.txt']=string.rep('a',32)
fire('OnTick');assert(started==0 and ticks==0,'coordinator ran on gameplay OnTick')
frame();assert(started==1 and ticks==0 and logs[#logs]:find('setup%-ready'))
frame();assert(started==1 and ticks==0,'paused startup callback ran twice')
local setupReceipts,setupStarts,startIndex,readyIndex=0,0,nil,nil
for i,line in ipairs(logs)do
 if line:find('"event":"setup%-started"')then
  setupStarts=setupStarts+1;startIndex=i
  assert(line:find('"token":"'..string.rep('a',32)..'"')and line:find('"role":"client1"')and line:find('"paused":true'))
 end
 if line:find('"event":"setup%-ready"')then setupReceipts=setupReceipts+1;readyIndex=i end
end
assert(setupStarts==1 and setupReceipts==1 and startIndex<readyIndex,'setup receipts duplicated or reordered')
files['queue-preflight-release.txt']=string.rep('a',32)
frame();frame();assert(started==1 and ticks==0 and env.Events==nativeEvents,
 'release synthesized a gameplay tick while paused')
paused=false;frame();assert(ticks==1,'genuine native OnTick was not admitted after release')
P.removeTick(env.Events,tick);frame();assert(ticks==1)
P.fail('preflight','late rejection');P.onTick(env.Events,tick);frame();assert(ticks==1)
P.complete();assert(logs[#logs]:find('late rejection'))
local Q,qfiles,qlogs,qfire,qenv=environment()
local case=0
Q.onGameStart(qenv.Events,function()error('fixture failed')end)
Q.onGameStart(qenv.Events,function()case=case+1 end);Q.onTick(qenv.Events,function()case=case+1 end)
qfire('OnGameStart');Q.complete();qfiles['queue-preflight-setup.txt']=string.rep('a',32)
qfiles['queue-preflight-release.txt']=string.rep('a',32)
qfire('OnTickEvenPaused');qfire('OnTickEvenPaused');qfire('OnTick');assert(case==0 and qlogs[#qlogs]:find('fixture%-setup'))
local failedStart=0
for _,line in ipairs(qlogs)do
 if line:find('"event":"setup%-started"')then failedStart=failedStart+1;assert(line:find('"paused":null'))end
 assert(not line:find('"event":"setup%-ready"'),'throwing callback claimed setup-ready')
end
assert(failedStart==1,'throwing callback lost or duplicated setup-started')
local T,tfiles,tlogs,tfire,tenv=environment()
tenv.isGamePaused=function()return false end
T.onGameStart(tenv.Events,function()coroutine.yield('stalled callback')end)
local stalledTicks=0;T.onTick(tenv.Events,function()stalledTicks=stalledTicks+1 end)
tfire('OnGameStart');T.complete()
tfiles['queue-preflight-setup.txt']=string.rep('a',32);tfiles['queue-preflight-release.txt']=string.rep('a',32)
local co=coroutine.create(function()tfire('OnTickEvenPaused')end)
local ok,why=coroutine.resume(co);assert(ok and why=='stalled callback'and coroutine.status(co)=='suspended')
tfire('OnTickEvenPaused');tfire('OnTick')
local stalledStarts=0
for _,line in ipairs(tlogs)do
 if line:find('"event":"setup%-started"')then stalledStarts=stalledStarts+1;assert(line:find('"paused":false'))end
 assert(not line:find('"event":"setup%-ready"'),'stalled callback claimed setup-ready')
end
assert(stalledStarts==1 and stalledTicks==0,'stalled setup repeated its callback or admitted gameplay')
for _,probe in ipairs({function()error('pause probe unavailable')end,function()return 'unknown'end})do
 local U,ufiles,ulogs,ufire,uenv=environment();uenv.isGamePaused=probe
 local called=0;U.onGameStart(uenv.Events,function()called=called+1 end)
 ufire('OnGameStart');U.complete();ufiles['queue-preflight-setup.txt']=string.rep('a',32)
 ufire('OnTickEvenPaused');assert(called==1)
 assert(ulogs[#ulogs-1]:find('"event":"setup%-started"')and ulogs[#ulogs-1]:find('"paused":null'),
  'unavailable pause state was invented or prevented setup')
end
local R,rfiles,rlogs,rfire,renv=environment()
R.onGameStart(renv.Events,function()error('must never start')end);rfire('OnGameStart')
R.complete();R.fail('preflight','wrong viewport')
rfiles['queue-preflight-setup.txt']=string.rep('a',32);rfiles['queue-preflight-release.txt']=string.rep('a',32)
rfire('OnTickEvenPaused');rfire('OnTick');assert(rlogs[#rlogs]:find('wrong viewport'))
local S,sfiles,slogs,sfire,senv=environment()
local rejected=0
S.onGameStart(senv.Events,function()rejected=rejected+1 end)
S.onTick(senv.Events,function()rejected=rejected+1 end)
sfire('OnGameStart');S.complete()
sfiles['queue-preflight-setup.txt']=string.rep('b',32)
sfire('OnTickEvenPaused')
sfiles['queue-preflight-setup.txt']=string.rep('a',32);sfiles['queue-preflight-release.txt']=string.rep('a',32)
sfire('OnTickEvenPaused');sfire('OnTick')
assert(rejected==0 and slogs[#slogs]:find('release token differs'),'bad token admitted paused fixture work')
print('PASS paused native scheduler, two explicit grants, failure/token dominance, removal and native Events ownership')

-- Reproduce the actual native release-preflight rejection, with the dependent
-- callback registered first: callback registration order must not admit work.
local B,bfiles,blogs,bfire,benv=environment()
local originalRequire=benv.require
benv.require=function(name)
 if name=='QueuePreflight'then return B end
 if name=='QueueTestSelection'then return {mods={},mode='native',window_size={1280,720}}end
 return originalRequire(name)
end
benv.getCore=function()return {getScreenWidth=function()return 1024 end,getScreenHeight=function()return 720 end}end
benv.isClient=function()return false end
local starts,cases=0,0
B.onGameStart(benv.Events,function()starts=starts+1 end)
B.onTick(benv.Events,function()cases=cases+1 end)
local release=assert(loadfile(arg[2]));setfenv(release,benv);release()
bfire('OnGameStart')
bfiles['queue-preflight-setup.txt']=string.rep('a',32);bfiles['queue-preflight-release.txt']=string.rep('a',32)
bfire('OnTickEvenPaused');bfire('OnTickEvenPaused');bfire('OnTick')
assert(starts==0 and cases==0,'actual failed native preflight admitted dependent fixture callbacks')
local structured=false
for _,line in ipairs(blogs)do if line:find('"event":"failed"',1,true)and line:find('"phase":"preflight"',1,true)then structured=true end end
assert(structured,'actual native preflight failure lost role/reason receipt')
print('PASS actual native viewport rejection blocks dependent callbacks regardless of registration order')
'''
        result = subprocess.run([lua, '-', str(ROOT / 'tests/native_queue/support/QueuePreflight.lua'),
                                 str(ROOT / 'tests/native_queue/support/ZZReleasePreflight.lua')],
                                input=source, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
