"""Execute the actual peer coordinator before spending a native Host launch."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT=Path(__file__).resolve().parents[1]


class PeerFixtureTests(unittest.TestCase):
    def test_real_server_phase_release_keeps_identity_until_both_peer_acks(self):
        lua=shutil.which('luajit')
        if not lua:self.skipTest('LuaJIT not installed')
        source=r"""
local config={suite='queue-transfer-peers',cases={'disjoint-returns','shared-capacity'}}
local events,sent={},{}
local F={module='QueueTransferPeersTest',roles={'client1','client2'}}
local players={}
for _,role in ipairs(F.roles)do
 players[role]={getUsername=function()return role end,hasTimedActions=function()return false end,
  getCharacterActions=function()return{isEmpty=function()return true end}end}
end
isServer=function()return true end;getTimestampMs=function()return 10 end
require=function(name)if name=='QueueTestSelection'then return config elseif name=='QueueTransferPeers'then return F end;error(name)end
local command,tick
Events={OnClientCommand={Add=function(f)command=f end},OnTick={Add=function(f)tick=f end}}
sendServerCommand=function(player,module,name,row)sent[#sent+1]={player=player,name=name,row=row}end
F.emit=function(name,row)events[#events+1]={name=name,row=row}end
F.prepare=function(p)return{players=p}end
F.seed=function(s,case,index)s.seed={case=case,index=index,token='token-'..index};return s.seed end
F.snapshot=function(s)assert(s.seed);return{case=s.seed.case,index=s.seed.index,token=s.seed.token,items={}}end
F.capacity=function(s)return F.snapshot(s)end
F.release=function(s)assert(s.seed);s.seed=nil end
F.cleanup=function(s)assert(not s.seed);s.cleaned=true end
assert(loadfile(arg[1]))()
local function call(role,name,index,extra)
 local args=extra or{};args.case=config.cases[index];args.index=index;args.token='token-'..index
 command(F.module,name,players[role],args)
end
call('client1','Hello',1);call('client2','Hello',1)
assert(events[1].name=='SEED'and events[1].row.index==1)
for index=1,2 do
 call('client1','Ready',index);call('client2','Ready',index)
 call('client1','BodyReady',index);call('client2','BodyReady',index)
 call('client1','Result',index,{result={role='client1'}});call('client2','Result',index,{result={role='client2'}})
 tick()
 local before=#events
 call('client1','Released',index)
 assert(#events==before,'one peer advanced/released a phase alone')
 call('client2','Released',index)
 assert(events[#events].name==(index==1 and'SEED'or'COMPLETE'),'lost phase identity after authority cleanup')
end
assert(events[#events].row.restored and events[#events].row.performed==2)
for _,event in ipairs(events)do assert(event.name~='FAIL','real coordinator rejected valid acknowledgements')end
os.exit(0)
"""
        subprocess.run([lua,'-e',source,'--','unused',str(ROOT/'tests/native_queue/queue-transfer-peers/server/ZZQueueTransferPeersServer.lua')],check=True)

    def run_lua(self, source, *args):
        lua=shutil.which('luajit')
        if not lua:self.skipTest('LuaJIT not installed')
        subprocess.run([lua,'-e',source,'--','unused',*args],check=True)

    def test_current_observer_never_polls_a_completed_native_object(self):
        text=(ROOT/'tests/native_queue/queue-transfer-peers/client/ZZQueueTransferPeers.lua').read_text()
        first=text.index('local function observe()');body=text[first:text.index('local function start()',first)]
        source=r"""
local active={action={},isStarted=function()return true end,getJobDelta=function()return .5 end}
local retired={action={},isStarted=function()return true end,getJobDelta=function()error('retired progress queried')end}
local a,b={started=false,progress=false},{started=true,progress=false}
local q={queue={active},current=active}
R={tracks={[active]=a,[retired]=b}}
queue=function()return q end;register=function()end;nativeIdentity=function()end
local calls=0;sample=function(action,row,point)assert(action==active and row==a and point=='started');calls=calls+1 end
local observe=assert(loadstring(arg[1]..' return observe'))()
observe();assert(calls==1 and a.started and a.progress and not b.progress)
q.current=nil;q.queue={};observe();assert(calls==1,'idle queue republished stale started state')
os.exit(0)
"""
        self.run_lua(source,body)

    def test_recursive_actor_inventory_is_not_misreported_as_direct_root(self):
        source=r"""
require=function()return{}end;instanceof=function(item,name)return item.bag==true end
local function container(items)return{getItems=function()return{size=function()return #items end,get=function(_,i)return items[i+1]end}end}end
local function item(id)return{getID=function()return id end}end
local direct,nested=item(1),item(2);local bag=item(3);bag.bag=true
local contents=container({nested});bag.getItemContainer=function()return contents end
local root=container({direct,bag});local player={getInventory=function()return root end}
local F=assert(loadfile(arg[1]))()
local s={player=player,role='client1',stores={source1=container({})}}
local _,where,count=F.find(s,1);assert(where=='client1-root'and count==1)
_,where,count=F.find(s,2);assert(where=='client1-root-nested'and count==1,'nested book acquired direct-root proof')
_,where,count=F.find(s,3);assert(where=='client1-root'and count==1)
os.exit(0)
"""
        self.run_lua(source,str(ROOT/'tests/native_queue/queue-transfer-peers/shared/QueueTransferPeers.lua'))

    def test_unknown_probe_count_brackets_recovery_preview(self):
        text=(ROOT/'tests/native_queue/queue-transfer-peers/client/ZZQueueTransferPeers.lua').read_text()
        first=text.index('local function result()');body=text[first:text.index('Events.OnGameStart.Add',first)]
        source=r"""
local count=1
R={tracks={},records={},state={ids={front={id=1,ft='Book',initial=216,total=220},tail={ft='Tail',initial=219,total=220}}},
 player={getOnlineID=function()return 0 end,getAlreadyReadPages=function()return 219 end},seed={case='lost-done',token='t'},index=1,role='client1',unknown={}}
T={ActionQueueExecution={blockedReturns=function()return{}end},ActionQueueRecovery={preview=function()count=count+1;return{count=1,skipped=1,reason='started_operation'}end}}
config={mode='toolkit'};intact=function()end;empty=function()return true end
queuePeersReplyLossState=function()return{attempts=count}end
local emitted;F={emit=function(_,row)emitted=row end};request=function()end
local result=assert(loadstring(arg[1]..' return result'))();result()
assert(emitted.unknown.afterProbe.attempts==2,'preview request escaped final no-replay observation')
os.exit(0)
"""
        self.run_lua(source,body)

    def test_actual_instant_episode_capture_does_not_fabricate_start(self):
        lua=shutil.which('luajit')
        if not lua:self.skipTest('LuaJIT not installed')
        text=(ROOT/'tests/native_queue/queue-transfer-peers/client/ZZQueueTransferPeers.lua').read_text()
        first=text.index('local function nativeIdentity(')
        body=text[first:text.index('local function begin(',first)]
        source=r"""
ref=function(value)return value end
local capture=assert(loadstring(arg[1]..' return nativeIdentity'))()
local native={};local action={action=native};local row={nativeRef=false,started=false,progress=false}
capture(action,row)
assert(row.nativeRef==native and not row.started and not row.progress)
action.action={};local ok=pcall(capture,action,row);assert(not ok,'changed native episode accepted')
local absent={nativeRef=false};capture({},absent);assert(absent.nativeRef==false)
os.exit(0)
"""
        subprocess.run([lua,'-e',source,'--','unused',body],check=True)
