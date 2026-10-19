local config=require 'QueueTestSelection'
if config.kind~='mp' then return end
local F=require 'ContainerConfigurationFixture'
local JSON=require 'QueueHealthEvents'
local players,ready,arriving={},{},{}
local obj,packet,pending,started,verified,finished
local function emit(event,value) print('[CONTAINER_CONFIG] '..event..' '..JSON.encode(value)) end
local function begin()
 if started or not ready.client1 or not ready.client2 then return end
 started=true
 assert(players.client1:getOnlineID()~=players.client2:getOnlineID(),'Fixture clients share identity')
 sendServerCommand(players.client1,F.module,'Start',{})
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~=F.module then return end
 local ok,err=pcall(function()
  local actor=player:getUsername();assert(actor=='client1' or actor=='client2','Unexpected fixture actor')
  if command=='Prepare' then
   assert(not players[actor],'Duplicate fixture preparation');players[actor]=player
   if actor=='client1' then
    assert(not obj,'Duplicate crate');obj,packet=F.prepare(player)
    emit('PREPARED',packet)
   end
  elseif command=='Ready' then
   assert(players[actor] and obj and not ready[actor],'Invalid ready')
   assert(not arriving[actor],'Duplicate arrival');arriving[actor]=getTimestampMs()
  elseif command=='Verify' then
   assert(actor=='client1' and started and not pending and not verified,'Invalid verification');pending=getTimestampMs()
  elseif command=='Observed' then
   assert(actor=='client2' and verified and not finished,'Invalid observer confirmation')
   local result=F.receipt(obj,players.client1,packet.category);assert(F.matches(result),'Authority changed after Cancel')
   emit('AUTHORITY',result);finished=true
   F.cleanup(obj)
   for _,peer in pairs(players)do sendServerCommand(peer,F.module,'Done',{})end
  else error('Unknown command '..tostring(command))end
 end)
 if not ok then print('[CONTAINER_CONFIG] FAIL server '..tostring(err))end
end)
Events.OnTick.Add(function()
 local ok,err=pcall(function()
  if obj and packet then
   for actor,player in pairs(players)do
    if not ready[actor] and not player:getModData().PZSTConfigFixtureSent then
     player:getModData().PZSTConfigFixtureSent=true
     sendServerCommand(player,F.module,'Prepared',{target=packet,role=actor})
    end
   end
  end
  for actor,sent in pairs(arriving)do
   local player=players[actor]
   if math.abs(player:getX()-packet.x)<4 and math.abs(player:getY()-packet.y)<4 then
    ready[actor]=true;arriving[actor]=nil;begin()
   else assert(getTimestampMs()-sent<30000,'Native arrival timeout '..actor)end
  end
  if pending then
   local result=F.receipt(obj,players.client1,packet.category)
   if F.matches(result) then
    verified=true;pending=nil;sendServerCommand(players.client2,F.module,'Observe',{})
   else assert(getTimestampMs()-pending<30000,'Authority never received complete single save')end
  end
 end)
 if not ok then pending=nil;print('[CONTAINER_CONFIG] FAIL server tick '..tostring(err))end
end)
