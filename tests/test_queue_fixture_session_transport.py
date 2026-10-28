"""The shared fixture protocol supports queued local transport without bypasses."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'tests/native_queue/support/QueueFixtureSession.lua'

HARNESS = r'''
createSession = ...
local create = createSession
now=0
getTimestampMs=function()return now end
print=function()end
-- Neither the transport hook nor local readiness may register global handlers.
Events=setmetatable({}, {__index=function()error('global event access')end})
sendClientCommand=function()error('custom transport must own client sends')end
sendServerCommand=function()error('custom transport must own authority sends')end
function newHarness()
 now=0
 local h={queue={},traffic={},cleanup={},starts={},pings=0,pongs=0,drained=true,replicated=true,
  localClean=true,authorityClean=true}
 h.player={getUsername=function()return 'Local Survivor'end,getOnlineID=function()return -1 end}
 getPlayer=function()return h.player end
 local function actor(player)assert(player==h.player);return 'client1'end
 local function transport(module,command,player,args,authority)
  assert(type(authority)=='boolean' and args.fixtureActor=='client1')
  assert(args.fixtureCase==({'first','second','third'})[args.fixtureEpoch])
  assert(authority and player==h.player or not authority and player==nil)
  local packet={module=module,command=command,player=player,args=args,authority=authority}
  h.queue[#h.queue+1]=packet;h.traffic[#h.traffic+1]=command
 end
 local function factories(authority)
  local result={}
  for _,name in ipairs({'first','second','third'})do
   result[name]=function(ctx)
    ctx.cleanup=function()
     h.cleanup[#h.cleanup+1]=(authority and 'authority:' or 'client:')..ctx.case
     return authority and h.authorityClean or not authority and h.localClean,'refused'
    end
    if authority then
     ctx.receipt={proof=ctx.case..':'..ctx.epoch}
     ctx.events.OnClientCommand.Add(function(module,command,player,args)
      assert(module=='LocalFixture' and command=='Ping' and player==h.player and args.value==ctx.case)
      h.pings=h.pings+1;ctx.reply(player,'Pong',{value=ctx.case})
     end)
    else
     ctx.readyToClean=function()return h.drained end
     ctx.clean=function(receipt)
      assert(receipt.proof==ctx.case..':'..ctx.epoch and receipt.fixtureActor=='client1')
      return h.replicated,'not yet visible'
     end
     ctx.events.OnGameStart.Add(function()
      h.starts[#h.starts+1]=ctx.case;ctx.send('Ping',{value=ctx.case})
     end)
     ctx.events.OnServerCommand.Add(function(module,command,args)
      assert(module=='LocalFixture' and command=='Pong' and args.value==ctx.case)
      h.pongs=h.pongs+1
     end)
    end
   end
  end
  return result
 end
 local function config()
  return {actors={'client1'},cases={'first','second','third'},user='client1',module='LocalFixture',
   actor=actor,transport=transport,localPlayerReady=function(player)assert(player==h.player);return true end}
 end
 h.authority=create(config(),factories(true),true)
 h.client=create(config(),factories(false),false)
 function h.deliver()
  local packet=table.remove(h.queue,1);assert(packet,'missing queued packet')
  local target=packet.authority and h.client or h.authority
  target.command(packet.module,packet.command,packet.authority and nil or h.player,packet.args)
  return packet.command
 end
 function h.flush()
  local count=0
  while #h.queue>0 do h.deliver();count=count+1;assert(count<100,'unbounded protocol recursion')end
 end
 function h.start()
  h.authority.prepare();h.client.prepare();h.client.tick()
  assert(h.authority.phase=='prepare' and h.client.phase=='prepare','loopback must stay queued')
  h.flush();assert(h.authority.phase=='running' and h.client.phase=='running')
 end
 function h.args(epoch,actor)
  return {fixtureCase=({'first','second','third'})[epoch],fixtureEpoch=epoch,fixtureActor=actor or 'client1'}
 end
 return h
end
'''


class FixtureSessionTransportTests(unittest.TestCase):
    def execute(self, code):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(HARNESS, lua.execute(SOURCE.read_text()))
        lua.execute(code)

    def test_three_local_cases_share_ordered_receipts_and_cleanup_barriers(self):
        self.execute(r'''
local h=newHarness();h.start()
for index,name in ipairs({'first','second','third'})do
 assert(h.client.current().case==name and h.authority.current().case==name)
 assert(h.pings==index and h.pongs==index and #h.starts==index)
 h.drained=false;h.replicated=false
 h.client.current().finish(true)
 assert(h.client.phase=='drain' and #h.queue==0 and #h.cleanup==(index-1)*2)
 h.client.tick();assert(h.client.phase=='drain' and #h.queue==0)
 h.drained=true;h.client.tick()
 assert(h.client.phase=='finish' and #h.cleanup==(index-1)*2+1)
 assert(h.authority.phase=='running','authority cleanup must wait for Finish delivery')
 assert(h.deliver()=='Finish' and h.authority.phase=='clean')
 assert(#h.cleanup==index*2 and h.cleanup[index*2-1]=='client:'..name and h.cleanup[index*2]=='authority:'..name)
 assert(h.deliver()=='Clean' and h.client.phase=='clean')
 h.client.tick();assert(h.client.phase=='clean' and #h.queue==0 and h.authority.index==index)
 h.replicated=true;h.client.tick()
 assert(h.client.phase=='cleaned' and h.authority.index==index)
 assert(h.deliver()=='Cleaned')
 assert(h.deliver()=='JointClean' and h.client.phase=='between')
 if index<3 then
  assert(h.deliver()=='Next' and h.client.phase=='prepare' and h.client.epoch==index+1)
  assert(h.authority.phase=='prepare' and #h.queue==0)
  h.client.tick();h.flush()
 else assert(h.deliver()=='Complete' and h.client.phase=='done' and h.authority.phase=='done')end
end
assert(table.concat(h.traffic,',')==
 'Prepare,Start,Ping,Pong,Finish,Clean,Cleaned,JointClean,Next,'..
 'Prepare,Start,Ping,Pong,Finish,Clean,Cleaned,JointClean,Next,'..
 'Prepare,Start,Ping,Pong,Finish,Clean,Cleaned,JointClean,Complete')
''')

    def test_stale_or_misaddressed_lifecycle_and_fixture_packets_are_rejected(self):
        self.execute(r'''
local h=newHarness();h.start()
for _,args in ipairs({h.args(2),h.args(1,'client2'),{}})do
 h.authority.command('QueueFixtureSession','Finish',h.player,args)
 h.client.command('QueueFixtureSession','Clean',nil,args)
 h.authority.command('LocalFixture','Ping',h.player,args)
 h.client.command('LocalFixture','Pong',nil,args)
end
assert(h.authority.phase=='running' and h.client.phase=='running')
assert(h.pings==1 and h.pongs==1 and #h.queue==0 and #h.cleanup==0)
-- Old phase packets remain stale after a successful transition to the next epoch.
h.client.current().finish(true);h.client.tick();h.flush();h.client.tick();h.flush()
assert(h.client.epoch==2 and h.authority.epoch==2)
h.authority.command('QueueFixtureSession','Prepare',h.player,h.args(1))
h.client.command('LocalFixture','Pong',nil,h.args(1))
assert(h.authority.phase=='prepare' and h.client.phase=='prepare' and h.pongs==1)
''')

    def test_bounded_drain_cleanup_and_session_deadlines_quarantine_both_peers(self):
        self.execute(r'''
for _,mode in ipairs({'drain','replication','session'})do
 local h=newHarness();h.start()
 if mode=='drain' then
  h.drained=false;h.client.current().finish(true);now=15001;h.client.tick()
  assert(#h.cleanup==0 and h.client.reason:find('pending product RPC deadline',1,true))
 elseif mode=='replication' then
  h.replicated=false;h.client.current().finish(true);h.client.tick();h.flush()
  assert(h.client.phase=='clean');now=15001;h.client.tick()
  assert(h.client.reason:find('replicated cleanup deadline',1,true))
 else now=720001;h.client.tick();assert(h.client.reason:find('session deadline',1,true))end
 h.flush();assert(h.client.phase=='quarantined' and h.authority.phase=='quarantined')
 assert(h.client.index==1 and h.authority.index==1)
 h.client.tick();h.authority.tick();assert(#h.queue==0)
end
''')

    def test_failed_cleanup_and_out_of_phase_packets_cannot_advance(self):
        self.execute(r'''
for _,mode in ipairs({'client','authority','duplicate'})do
 local h=newHarness();h.start()
 if mode=='duplicate' then h.authority.command('QueueFixtureSession','Prepare',h.player,h.args(1))
 else
  if mode=='client' then h.localClean=false else h.authorityClean=false end
  h.client.current().finish(true);h.client.tick()
 end
 h.flush();assert(h.client.phase=='quarantined' and h.authority.phase=='quarantined')
 assert(h.client.index==1 and h.authority.index==1)
 for _,command in ipairs(h.traffic)do assert(command~='Next' and command~='JointClean' and command~='Cleaned')end
end
''')

    def test_local_readiness_predicate_must_admit_an_existing_player(self):
        self.execute(r'''
local h=newHarness();local player=h.player;local calls=0;local ready=false
h.client.config.localPlayerReady=function(actual)assert(actual==player);calls=calls+1;return ready end
h.authority.prepare();h.client.prepare()
getPlayer=function()return nil end
h.client.tick();assert(calls==0 and #h.queue==0)
getPlayer=function()return player end
h.client.tick();assert(calls==1 and #h.queue==0 and h.client.pendingPrepare)
ready=true;h.client.tick();assert(calls==2 and #h.queue==1 and not h.client.pendingPrepare)
h.client.tick();assert(calls==2 and #h.queue==1,'local Prepare must remain one-shot')
h.flush();assert(h.authority.phase=='running' and h.client.phase=='running')
''')

    def test_default_game_transport_signatures_and_online_id_admission_are_unchanged(self):
        self.execute(r'''
local create=createSession
local sends={};local id=-1
local player={getUsername=function()return 'client1'end,getOnlineID=function()return id end}
getPlayer=function()return player end
sendClientCommand=function(...)sends[#sends+1]={side='client',n=select('#',...),...}end
sendServerCommand=function(...)sends[#sends+1]={side='server',n=select('#',...),...}end
local factory=function(ctx)ctx.cleanup=function()return true end end
local cfg={cases={'only'},user='client1'}
local client=create(cfg,{only=factory},false);local authority=create(cfg,{only=factory},true)
client.prepare();authority.prepare();client.tick();assert(#sends==0,'default MP admission must still reject onlineID -1')
id=0;client.tick();assert(#sends==1)
local prepare=sends[1]
assert(prepare.side=='client' and prepare.n==3 and prepare[1]=='QueueFixtureSession' and prepare[2]=='Prepare')
assert(prepare[3].fixtureActor=='client1' and prepare[3].fixtureEpoch==1 and prepare[3].fixtureCase=='only')
authority.command(prepare[1],prepare[2],player,prepare[3])
assert(authority.phase=='prepare' and #sends==1,'default participant list still requires client2')
client.current().send('Ping',{value=7})
assert(sends[2].side=='client' and sends[2].n==3 and sends[2][1]=='CraftChainTest' and sends[2][2]=='Ping' and sends[2][3].value==7)
authority.current().reply(player,'Pong',{value=8})
assert(sends[3].side=='server' and sends[3].n==4 and sends[3][1]==player and sends[3][2]=='CraftChainTest' and sends[3][3]=='Pong' and sends[3][4].value==8)
local other={getUsername=function()return 'client2'end}
authority.command('QueueFixtureSession','Prepare',other,{fixtureActor='client2',fixtureEpoch=1,fixtureCase='only'})
assert(authority.phase=='running' and #sends==5)
for i=4,5 do
 assert(sends[i].side=='server' and sends[i].n==4 and sends[i][2]=='QueueFixtureSession' and sends[i][3]=='Start')
 assert(sends[i][4].fixtureActor==sends[i][1]:getUsername())
end
''')


if __name__ == '__main__':
    unittest.main()
