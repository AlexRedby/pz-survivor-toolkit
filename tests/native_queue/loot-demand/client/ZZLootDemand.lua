local config=require 'QueueTestSelection'
if config.suite~='loot-demand' then return end
require 'LootDemandBank'
require 'LootDemandFurniture'
local started,sent,done=false,false,false
local at,probe,requests,observed
requests=0
local function fail(problem) done=true;print('[LOOT_DEMAND_TEST] FAIL '..tostring(problem)) end
Events.OnGameStart.Add(function() started=true end)
Events.OnServerCommand.Add(function(module,command,args)
 if module~='LootDemandTest' or done then return end
 if command=='NativeProbe' then
  if not sent or probe or type(args)~='table' then fail('unexpected native probe');return end
  probe=args;return
 end
 if not sent or command~='Complete' or type(args)~='table' or args.ok~=true or not observed then fail('authority response failed');return end
 done=true;print('[LOOT_DEMAND_TEST] COMPLETE lifecycle')
end)
Events.OnTick.Add(function()
 if done or not started or not isIngameState() then return end
 local player=getPlayer();if not player or player:isDead() or not player:getSquare() then return end
 local ok,problem=pcall(function()
  assert(lootDemandInstalled(),'demand hooks inactive')
  if config.kind=='mp' then
   if not isClient() or player:getOnlineID()<0 then return end
   if sent then
    assert(getTimestampMs()-at<120000,'authority response timeout')
    if probe and not observed then
     local square=getCell():getGridSquare(probe.x,probe.y,probe.z)
     if not square or square:getObjects():size()<=probe.index then return end
     local object=square:getObjects():get(probe.index)
     if object:getName()~=probe.name then return end
     local container=assert(object:getContainer())
     if requests==0 then
      container:requestServerItemsForContainer();container:requestServerItemsForContainer();requests=2
     elseif not container:isEmpty() then
      observed=true
      sendClientCommand('LootDemandTest','Observe',{fingerprint=lootDemandFingerprint(container),requests=requests})
     end
    end
    return
   end
   sent=true;at=getTimestampMs();sendClientCommand('LootDemandTest','Run',{})
  else
   assert(not sent,'duplicate bank');sent=true
   assert(LootDemandBank.run(player));done=true;print('[LOOT_DEMAND_TEST] COMPLETE lifecycle')
  end
 end)
 if not ok then fail(problem) end
end)
