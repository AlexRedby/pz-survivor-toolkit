local config=require 'QueueTestSelection'
if config.suite~='loot-demand' or config.cases[1]=='natural' or config.kind~='mp' or not isServer() then return end
require 'LootDemandBank'
require 'LootDemandPersistence'
local case=config.cases[1]
require 'LootDemandFurniture'
local pending,requested,waiting=nil,false,false
local startedAt, furnitureRequester
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='LootDemandTest' then return end
 local ok,problem=pcall(function()
  if case=='furniture' and command=='FurnitureObserve' then
   assert(waiting and furnitureRequester and player==furnitureRequester, 'unrequested furniture observation')
   LootDemandBank.verifyFurniture(args)
   return
  end
  if command=='Observe' then
   if case=='furniture' then
    assert(player==furnitureRequester and LootDemandBank.furnitureReplicated.seen, 'moved furniture not observed by requester')
   end
   assert(waiting and player and player:getUsername()=='client1','unrequested observation')
   assert(LootDemandBank.verifyNetwork(player,args));waiting=false
   sendServerCommand(player,'LootDemandTest','Complete',{ok=true,case=case});return
  end
  assert(not requested and command=='Run' and player and player:getUsername()=='client1','foreign/duplicate request')
  if case=='furniture' then furnitureRequester = player end
  requested=true;pending=player;startedAt=getTimestampMs()
 end)
 if not ok then print('[LOOT_DEMAND_TEST] FAIL '..tostring(problem)) end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local player=pending;pending=nil
 local ok,problem=pcall(function()
  if case=='persist-reload' then
   assert(getTimestampMs()-startedAt<120000,'persisted squares did not load')
   return LootDemandBank.reloadPersistence(player)
  end
  if case=='furniture' then
   require 'LootDemandFurnitureNative'
   assert(LootDemandBank.runFurniture(player))
  else
   assert(LootDemandBank.run(player))
  end
  if case=='persist-seed' then assert(LootDemandBank.seedPersistence(player)) end
 end)
 if not ok then print('[LOOT_DEMAND_TEST] FAIL '..tostring(problem)) end
 if ok and problem==false then pending=player;return end
 if ok and case=='persist-reload' then
  sendServerCommand(player,'LootDemandTest','Complete',{ok=true,case=case});return
 end
 if ok then
  local prepared,args=pcall(LootDemandBank.prepareNetwork,player)
  if not prepared then print('[LOOT_DEMAND_TEST] FAIL '..tostring(args));return end
  waiting=true
  if case=='furniture' then
   sendServerCommand(player,'LootDemandTest','FurnitureProbe',LootDemandBank.furnitureProbeInfo())
  end
  sendServerCommand(player,'LootDemandTest','NativeProbe',args)
 else sendServerCommand(player,'LootDemandTest','Complete',{ok=false}) end
end)
