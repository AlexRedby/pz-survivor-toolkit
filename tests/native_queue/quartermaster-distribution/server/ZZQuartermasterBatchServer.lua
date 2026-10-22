local config=require 'QueueTestSelection'
if config.cases[1]~='batch' or not isServer()then return end
local F=require 'QuartermasterDepositFixture'
local JSON=require 'QueueHealthEvents'
local MODULE='QuartermasterBatchTest'
local state,preparing,pending,done
local function emit(event,value)print('[QM_BATCH] '..event..' '..JSON.encode(value))end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~=MODULE or done then return end
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1','unexpected batch actor')
  if command=='Prepare'then
   assert(not state and not preparing,'duplicate batch preparation')
   preparing={player=player,point=args,since=getTimestampMs()}
  elseif command=='Verify'then
   assert(state and player==state.player and not pending,'invalid batch verification')
   assert(args.stage==(state.verified and 'accepted' or 'rejected'),'batch authority stage order')
   pending={stage=args.stage,since=getTimestampMs()}
  else
   assert(command=='Cleanup'and state and state.verified=='accepted','batch cleanup before verification')
   F.cleanup(state);emit('CLEANUP',{objects=3});sendServerCommand(player,MODULE,'Cleaned',{});done=true
  end
 end)
 if not ok then done=true;print('[QUEUE_TEST] FAIL batch server '..tostring(problem))end
end)
Events.OnTick.Add(function()
 if done then return end
 local ok,problem=pcall(function()
  if preparing then
   local request=preparing;local player,point=request.player,request.point
   assert(getTimestampMs()-request.since<20000,'batch server positioning timeout')
   if player:getCurrentSquare()and math.abs(player:getX()-point.x)<2 and math.abs(player:getY()-point.y)<2 then
    state=F.prepare(player,point,'batch');preparing=nil
    local packet=F.descriptor(state);emit('PREPARED',packet);sendServerCommand(player,MODULE,'Prepared',packet)
   end
  end
  if pending then
   assert(getTimestampMs()-pending.since<20000,'batch authority convergence timeout')
   local result=F.receipt(state.player,state.boxes,F.descriptor(state),pending.stage)
   if result then
    state.verified=pending.stage;emit(pending.stage=='rejected'and 'REJECTED'or 'ACCEPTED',result)
    sendServerCommand(state.player,MODULE,'Verified',result);pending=nil
   end
  end
 end)
 if not ok then done=true;print('[QUEUE_TEST] FAIL batch server '..tostring(problem))end
end)
