if not isServer()then return end
local F=require 'QueueGroomingRecovery';local JSON=require 'QueueHealthEvents';local config=require 'QueueTestSelection'
local P=require 'QueueEnergyPlacement'
local state,previous,pending;local index=1
local function raw(marker,value)print('[GROOMING_RECOVERY] '..marker..' '..JSON.encode(value))end
local function fail(player,error)
 pending=nil;print('[QUEUE_TEST] FAIL grooming-recovery server '..tostring(error));sendServerCommand(player,'GroomingRecoveryTest','Failed',{error=tostring(error)})
end
Events.OnServerStarted.Add(function()raw('SERVER_READY',{})end)
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='GroomingRecoveryTest'then return end
 local ok,error=pcall(function()
  assert(type(args)=='table'and player:getUsername()=='client1'and args.case==config.cases[index]and not pending,'unexpected grooming recovery actor/case/request')
  if command=='Prepare'then
   assert(not state,'previous grooming recovery case unsettled')
   local target=P.target(args.target);local proof=args.clientPlacement
   assert(type(proof)=='table'and proof.mode=='local'and proof.teleports==1
    and F.same(P.target(proof.target),target),'invalid grooming recovery client placement receipt')
   pending={command='Prepare',player=player,case=args.case,target=target,arrival=P.observe(player,target)}
  elseif command=='Baseline'then
   assert(state and state.player==player);local value=F.snapshot(state);assert(F.same(value,state.ids.baseline),'authority baseline differs');raw('BASELINE',value);sendServerCommand(player,module,'Baselined',value)
  elseif command=='Remove'then
   assert(state and state.player==player and args.case=='lost-tool','unexpected authority revocation');pending={since=getTimestampMs(),command='Remove'}
  elseif command=='Verify'then assert(state and state.player==player);pending={since=getTimestampMs(),command='Verify'}
  else error('unknown grooming recovery command')end
 end)
 if not ok then fail(player,error)end
end)
Events.OnTick.Add(function()
 if not pending then return end
 if pending.command=='Prepare'then
  local player=pending.player
  local ok,error=pcall(function()
   local proof=P.poll(pending.arrival);if not proof then return end
   assert(P.at(player,pending.target),'grooming recovery authority changed placement before preparation')
   state=F.prepare(player,pending.case,config.mode,previous,pending.target,proof);previous=nil
   raw('PREPARED',state.ids);sendServerCommand(player,'GroomingRecoveryTest','Prepared',state.ids);pending=nil
  end)
  if not ok then fail(player,error)end;return
 end
 if pending.command=='Remove'then
  if state.player:hasTimedActions()or not state.player:getCharacterActions():isEmpty()then
   if getTimestampMs()-pending.since>20000 then fail(state.player,'authority tool revocation native drain timed out')end;return
  end
  local ok,value=pcall(F.removeRazor,state)
  if not ok then fail(state.player,value);return end
  raw('REMOVED',value);sendServerCommand(state.player,'GroomingRecoveryTest','Removed',value);pending=nil;return
 end
 local ok,value,actual=pcall(F.verify,state)
 if ok and value and not state.player:hasTimedActions()and state.player:getCharacterActions():isEmpty()then
  raw('VERIFIED',value);sendServerCommand(state.player,'GroomingRecoveryTest','Verified',value);previous=state.ids;state,pending=nil,nil;index=index+1
 elseif not ok or getTimestampMs()-pending.since>20000 then fail(state.player,ok and JSON.encode(actual)or value)end
end)
