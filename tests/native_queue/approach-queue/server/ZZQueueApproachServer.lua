if not isServer()then return end
local F=require 'QueueApproach';local JSON=require 'QueueHealthEvents';local config=require 'QueueTestSelection'
local state,pending;local index=1
local function raw(event,value)print('[QUEUE_APPROACH] '..event..' '..JSON.encode(value))end
local function fail(player,error)pending=nil;print('[QUEUE_TEST] FAIL approach-queue server '..tostring(error));sendServerCommand(player,'QueueApproachTest','Failed',{error=tostring(error)})end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='QueueApproachTest'then return end
 local ok,error=pcall(function()
  assert(player:getUsername()=='client1'and args.case==config.cases[index])
  if command=='Prepare'then assert(not state and not pending);state=F.prepare(player,args.case,config.mode);raw('PREPARED',state.ids);sendServerCommand(player,module,'Prepared',state.ids)
  elseif command=='Snapshot'then
   assert(state,'snapshot without prepared authority');local snapshot=F.snapshot(state);raw('SNAPSHOT',snapshot);sendServerCommand(player,module,'Snapshot',snapshot)
  else assert(state and not pending and(command=='Baseline'or command=='Verify'));pending={command=command,since=getTimestampMs()}end
 end);if not ok then fail(player,error)end
end)
Events.OnTick.Add(function()
 if not state then return end
 local ok,error=pcall(function()
  F.snapshot(state)
  if not pending then return end
  local receipt,actual=(pending.command=='Baseline'and F.baseline or F.verify)(state)
  if receipt then local command=pending.command;raw(command=='Baseline'and'BASELINE'or'VERIFIED',receipt);sendServerCommand(state.player,'QueueApproachTest',command=='Baseline'and'Baselined'or'Verified',receipt);pending=nil
   if command=='Verify'then state=nil;index=index+1 end
  elseif getTimestampMs()-pending.since>20000 then error(JSON.encode(actual or F.snapshot(state)))end
 end);if not ok then fail(state.player,error)end
end)
