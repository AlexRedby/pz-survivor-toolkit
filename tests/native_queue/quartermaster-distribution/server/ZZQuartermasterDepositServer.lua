local config=require 'QueueTestSelection'
if config.cases[1]~='deposit' or not isServer() then return end
local F=require 'QuartermasterDepositFixture'
local JSON=require 'QueueHealthEvents'
local state,preparing,pending,done
local function emit(event,value) print('[QM_DEPOSIT] '..event..' '..JSON.encode(value)) end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~=F.module or done then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1','unexpected deposit actor')
  if command=='Prepare' then
   assert(not state and not preparing,'duplicate deposit preparation')
   preparing={player=player,point=args,since=getTimestampMs()}
  elseif command=='Verify' then
   assert(state and player==state.player and not pending and not state.verified,'invalid deposit verification')
   pending=getTimestampMs()
  elseif command=='Cleanup' then
   assert(state and player==state.player and state.verified,'deposit cleanup before authority verification')
   F.cleanup(state); emit('CLEANUP',{objects=3})
   sendServerCommand(player,F.module,'Cleaned',{}); done=true
  else error('unknown deposit command '..tostring(command)) end
 end)
 if not ok then done=true; print('[QUEUE_TEST] FAIL deposit server '..tostring(problem)) end
end)
Events.OnTick.Add(function()
 if done then return end
 local ok,problem=pcall(function()
  if preparing then
   local request=preparing; local player,point=request.player,request.point
   assert(getTimestampMs()-request.since<20000,'deposit server positioning timeout')
   if player:getCurrentSquare() and math.abs(player:getX()-point.x)<2 and math.abs(player:getY()-point.y)<2 then
    state=F.prepare(player,point,'mp'); preparing=nil
    local packet=F.descriptor(state); emit('PREPARED',packet)
    sendServerCommand(player,F.module,'Prepared',packet)
   end
  end
  if pending then
   assert(getTimestampMs()-pending<20000,'deposit authority convergence timeout')
   local result=F.receipt(state.player,state.boxes,F.descriptor(state))
   if result then
    emit('AUTHORITY',result); state.verified=true; pending=nil
    sendServerCommand(state.player,F.module,'Verified',result)
   end
  end
 end)
 if not ok then done=true; print('[QUEUE_TEST] FAIL deposit server '..tostring(problem)) end
end)
