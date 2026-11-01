local config=require 'QueueTestSelection'
if config.suite~='loot-demand' or config.kind~='mp' or not isServer() then return end
require 'LootDemandBank'
require 'LootDemandFurniture'
local pending,requested,waiting=nil,false,false
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='LootDemandTest' then return end
 local ok,problem=pcall(function()
  if command=='Observe' then
   assert(waiting and player and player:getUsername()=='client1','unrequested observation')
   assert(LootDemandBank.verifyNetwork(player,args));waiting=false
   sendServerCommand(player,'LootDemandTest','Complete',{ok=true});return
  end
  assert(not requested and command=='Run' and player and player:getUsername()=='client1','foreign/duplicate request')
  requested=true;pending=player
 end)
 if not ok then print('[LOOT_DEMAND_TEST] FAIL '..tostring(problem)) end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local player=pending;pending=nil
 local ok,problem=pcall(LootDemandBank.run,player)
 if not ok then print('[LOOT_DEMAND_TEST] FAIL '..tostring(problem)) end
 if ok then
  local prepared,args=pcall(LootDemandBank.prepareNetwork,player)
  if not prepared then print('[LOOT_DEMAND_TEST] FAIL '..tostring(args));return end
  waiting=true;sendServerCommand(player,'LootDemandTest','NativeProbe',args)
 else sendServerCommand(player,'LootDemandTest','Complete',{ok=false}) end
end)
