if not isServer() then return end
local Fixture=require 'QueueCraftFixture'
local session,waiting,pending
local function reply(player,command,value) sendServerCommand(player,'CraftQueueTest',command,value) end
local function prepare(player)
 assert(not session,'duplicate craft preparation')
 player:setGhostMode(true)
 session=Fixture.prepare(player)
 reply(player,'Prepared',Fixture.descriptor(session))
 print('[CRAFT_QUEUE_TEST] PREPARED tools=2 material=1')
end
Events.OnClientCommand.Add(function(module,command,player)
 if module~='CraftQueueTest' then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1','unexpected craft actor')
  if command=='Prepare' then
   if not player:getSquare() then assert(not waiting,'duplicate craft wait');waiting=player else prepare(player) end
  else
   assert(command=='Verify' and session and session.player==player and not pending,'unexpected craft verification')
   pending={player=player,since=getTimestampMs()}
  end
 end)
 if not ok then reply(player,'Failed',{ok=false,error=tostring(problem)});print('[QUEUE_TEST] FAIL craft server '..tostring(problem)) end
end)
Events.OnTick.Add(function()
 if waiting and waiting:getSquare() then
  local player=waiting;waiting=nil
  local ok,problem=pcall(prepare,player)
  if not ok then reply(player,'Failed',{ok=false,error=tostring(problem)});print('[QUEUE_TEST] FAIL craft prepare '..tostring(problem)) end
 end
 if not pending then return end
 local result,problem=Fixture.verify(session)
 if result then
  print('[CRAFT_QUEUE_TEST] AUTHORITY consumed=1 outputs=1 toolsReturned=2 tailRead=true')
  reply(pending.player,'Verified',result);pending=nil
 elseif getTimestampMs()-pending.since>20000 then
  reply(pending.player,'Failed',{ok=false,error=tostring(problem)})
  print('[QUEUE_TEST] FAIL craft authority '..tostring(problem));pending=nil
 end
end)
