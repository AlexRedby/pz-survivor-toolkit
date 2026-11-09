if not isServer()then return end
local F=require'QueueCleanupCancel';local JSON=require'QueueHealthEvents';local config=require'QueueTestSelection'
local P=require'QueueEnergyPlacement'
local state,index=nil,1
local baselinePending,baselineSeen
local arrival
local function raw(event,value)print('[QUEUE_CLEANUP] '..event..' '..JSON.encode(value))end
local function fail(player,problem)
 arrival,baselinePending=nil,nil
 print('[QUEUE_TEST] FAIL cleanup-cancel server '..tostring(problem))
 sendServerCommand(player,'QueueCleanupCancelTest','Failed',{error=tostring(problem)})
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='QueueCleanupCancelTest'then return end
 local ok,problem=pcall(function()
  assert(type(args)=='table'and player:getUsername()=='client1'and args.case==config.cases[index]and not arrival,'unexpected cleanup actor/case or pending arrival')
  if command=='Prepare'then
   assert(not state and not baselinePending,'previous cleanup case unsettled')
   local target=P.target(args.target);local proof=args.clientPlacement
   assert(type(proof)=='table'and proof.mode=='local'and proof.teleports==1,'cleanup owning-client arrival proof missing')
   local observed=P.target(proof.target)
   assert(observed.x==target.x and observed.y==target.y and observed.z==target.z,'cleanup client arrival target differs')
   arrival={player=player,case=args.case,target=target,state=P.observe(player,target)}
  elseif command=='Baseline'then
   assert(state and state.player==player and not baselinePending,'unexpected baseline request');baselinePending=getTimestampMs();baselineSeen={}
  else
   assert(state and state.player==player and not baselinePending and(command=='Checkpoint'or command=='Verify'),'unexpected cleanup request')
   local snapshot=F.snapshot(state);raw(command:upper(),snapshot);sendServerCommand(player,module,command..'d',snapshot)
   if command=='Verify'then state=nil;index=index+1 end
  end
 end)
 if not ok then fail(player,problem)end
end)

-- Read-only authority ACK after exact local equipment setup has replicated.
Events.OnTick.Add(function()
 if arrival then
  local request=arrival
  local ok,problem=pcall(function()
   local proof=P.poll(request.state);if not proof then return end
   assert(P.at(request.player,request.target),'cleanup authority left final placement')
   state=F.prepare(request.player,request.case,request.target,proof);arrival=nil
   raw('PREPARED',state.ids);sendServerCommand(request.player,'QueueCleanupCancelTest','Prepared',state.ids)
  end)
  if not ok then fail(request.player,problem)end
  return
 end
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
 if not ok then fail(state.player,problem)end
end)
