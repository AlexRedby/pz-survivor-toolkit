if not isServer()then return end
local Fixture=require 'QueueCraftUIFixture'
local config=require 'QueueTestSelection'
local JSON=require 'QueueHealthEvents'
local actor=config.actor or 'client1'
local joined=actor=='client2'
local SandwichFixture=joined and require 'QueueCookSandwichFixture'or nil
local state,pending,previous;local step=1
local observer,descriptor,observerPrepared,observedBefore,verifiedValue
local function observePrepared()
 if not joined or not state or not observer or observerPrepared then return end
 assert(observer~=state.player and observer:getOnlineID()~=state.player:getOnlineID(),'joined actor and observer share identity')
 observerPrepared=true;sendServerCommand(observer,'CraftUITest','ObservePrepared',descriptor)
end
local function advance()
 previous=state;state,pending=nil,nil;step=step+1
 observer,descriptor,observerPrepared,observedBefore,verifiedValue=nil,nil,nil,nil,nil
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='CraftUITest'then return end
 local ok,problem=pcall(function()
  assert(args.case==config.cases[step],'UI craft case order differs')
  if joined and command=='ObserverReady'then
   assert(player:getUsername()=='client1'and not observer,'unexpected or duplicate host observer readiness')
   observer=player;observePrepared();return
  end
  if joined and (command=='ObservedBefore'or command=='Observed')then
   assert(player==observer and observerPrepared and state and type(args.snapshot)=='table'
    and args.snapshot.case==state.case,'unexpected independent observer receipt')
   if command=='ObservedBefore'then
    assert(not observedBefore and not pending and not verifiedValue,'duplicate or late observer before receipt')
    observedBefore=true
    print('[CRAFT_UI_TEST] OBSERVED_BEFORE '..JSON.encode({case=state.case,actor='client1',snapshot=args.snapshot}))
    sendServerCommand(state.player,module,'Start',{case=state.case})
   else
    assert(observedBefore and verifiedValue and not pending,'observer completed before authority verification')
    print('[CRAFT_UI_TEST] OBSERVED '..JSON.encode({case=state.case,actor='client1',snapshot=args.snapshot}))
    sendServerCommand(state.player,module,'Verified',verifiedValue)
    sendServerCommand(observer,module,'Done',{case=state.case});advance()
   end
   return
  end
  assert(player:getUsername()==actor,'UI craft actor identity differs')
  if command=='Prepare'then
   assert(not state,'UI craft already prepared');player:setGhostMode(true);state=Fixture.prepare(player,args.case,previous);previous=nil
   local ids=Fixture.descriptor(state);descriptor=ids;print('[CRAFT_UI_TEST] PREPARED '..JSON.encode(ids))
   sendServerCommand(player,module,'Prepared',ids)
   observePrepared()
  else
   assert(state and state.player==player and not pending and not verifiedValue,'unexpected UI craft request')
   if joined then assert(observedBefore,'actor action preceded independent observer readiness')end
   if joined and command=='ActorCheckpoint'then
    local snapshot=SandwichFixture.checkpoint(state,args.stage,args)
    local value={case=state.case,stage=args.stage,snapshot=snapshot}
    print('[CRAFT_UI_TEST] CHECKPOINT '..JSON.encode(value));sendServerCommand(player,module,'ActorCheckpoint',value)
   elseif command=='RemovePool'then
    local value=Fixture.removePool(state)
    print('[CRAFT_UI_TEST] REMOVED '..JSON.encode(value));sendServerCommand(player,module,'Removed',value)
   else assert(command=='Verify','unexpected UI craft verification');pending=getTimestampMs()end
  end
 end)
 if not ok then print('[QUEUE_TEST] FAIL craft UI server '..tostring(problem));sendServerCommand(player,module,'Failed',{error=tostring(problem)})end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local ok,value,reason=pcall(Fixture.verify,state)
 if ok and value then
  print('[CRAFT_UI_TEST] VERIFIED '..JSON.encode(value))
  if joined then
   assert(observer and observedBefore,'missing host observer after authority verification')
   verifiedValue=value;pending=nil;sendServerCommand(observer,'CraftUITest','Observe',{case=state.case})
  else sendServerCommand(state.player,'CraftUITest','Verified',value);advance()end
 elseif not ok or getTimestampMs()-pending>20000 then
  print('[QUEUE_TEST] FAIL craft UI authority '..tostring(ok and reason or value));pending=nil
 end
end)
