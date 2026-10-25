if not isServer()then return end
local F=require'QueueCleanupCancel';local JSON=require'QueueHealthEvents';local config=require'QueueTestSelection'
local state,index=nil,1
local baselinePending,baselineSeen
local function raw(event,value)print('[QUEUE_CLEANUP] '..event..' '..JSON.encode(value))end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='QueueCleanupCancelTest'then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1'and args.case==config.cases[index],'unexpected cleanup actor/case')
  if command=='Prepare'then
   assert(not state);state=F.prepare(player,args.case);raw('PREPARED',state.ids);sendServerCommand(player,module,'Prepared',state.ids)
  elseif command=='Baseline'then
   assert(state and not baselinePending,'unexpected baseline request');baselinePending=getTimestampMs();baselineSeen={}
  else
   assert(state and not baselinePending and(command=='Checkpoint'or command=='Verify'),'unexpected cleanup request')
   local snapshot=F.snapshot(state);raw(command:upper(),snapshot);sendServerCommand(player,module,command..'d',snapshot)
   if command=='Verify'then state=nil;index=index+1 end
  end
 end)
 if not ok then print('[QUEUE_TEST] FAIL cleanup-cancel server '..tostring(problem));sendServerCommand(player,module,'Failed',{error=tostring(problem)})end
end)

-- Read-only authority ACK after exact local equipment setup has replicated.
Events.OnTick.Add(function()
 if not baselinePending then return end
 local ok,problem=pcall(function()
  local snapshot=F.snapshot(state);local difference=F.baselineDifference(state,snapshot)
  if not difference then
   raw('BASELINE_CONFIRMED',snapshot);sendServerCommand(state.player,'QueueCleanupCancelTest','Baselined',snapshot);baselinePending=nil
  else
   local encoded=JSON.encode(difference)
   if not baselineSeen[encoded]then baselineSeen[encoded]=true;raw('BASELINE_WAIT',difference);sendServerCommand(state.player,'QueueCleanupCancelTest','BaselineWaiting',difference)end
   assert(getTimestampMs()-baselinePending<20000,'authority baseline timeout '..encoded)
  end
 end)
 if not ok then baselinePending=nil;print('[QUEUE_TEST] FAIL cleanup-cancel server '..tostring(problem));sendServerCommand(state.player,'QueueCleanupCancelTest','Failed',{error=tostring(problem)})end
end)
