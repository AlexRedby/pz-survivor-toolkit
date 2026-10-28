if not isServer()then return end
local F=require 'QueueBookControls';local JSON=require 'QueueHealthEvents';local config=require 'QueueTestSelection'
local state,previous,pending;local index=1
local function raw(marker,value)print('[BOOK_CONTROLS] '..marker..' '..JSON.encode(value))end
local function fail(player,error)
 pending=nil;print('[QUEUE_TEST] FAIL book-controls server '..tostring(error));sendServerCommand(player,'BookControlsTest','Failed',{error=tostring(error)})
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='BookControlsTest'then return end
 local ok,error=pcall(function()
  assert(player:getUsername()=='client1'and args.case==config.cases[index]and not pending,'unexpected book controls actor/case/request')
  if command=='Prepare'then
   assert(not state);state=F.prepare(player,args.case,previous);previous=nil;raw('PREPARED',state.ids);sendServerCommand(player,module,'Prepared',state.ids)
  elseif command=='CapacityLost'then
   assert(state and args.case:find('%-capacity%-lost$'),'unexpected capacity intervention')
   local value=F.capacityLost(state,args.requestedAt,args.acceptedAt);raw('CAPACITY_LOST',value);sendServerCommand(player,module,'CapacityLost',value)
  elseif command=='Baseline'then
   local value=F.snapshot(state);assert(F.same(value,state.ids.baseline),'authority baseline differs');raw('BASELINE',value);sendServerCommand(player,module,'Baselined',value)
  elseif command=='Verify'then assert(state);pending={since=getTimestampMs(),player=player,expected=args.expected}
  else error('unknown book controls command')end
 end)
 if not ok then fail(player,error)end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local player=pending.player
 if player:hasTimedActions()or not player:getCharacterActions():isEmpty()then
  if getTimestampMs()-pending.since>20000 then fail(player,'authority native drain timed out')end;return
 end
 local ok,value=pcall(F.snapshot,state)
 if not ok then fail(player,value);return end
 if not F.same(value,pending.expected)then if getTimestampMs()-pending.since>20000 then fail(player,'authority/client exact final snapshot did not converge')end;return end
 raw('VERIFIED',value);F.restoreCapacity(state);sendServerCommand(player,'BookControlsTest','Verified',value);previous=state;state,pending=nil,nil;index=index+1
end)
