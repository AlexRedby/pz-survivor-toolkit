if not isServer()then return end
local P=require 'QueueEnergyPlacement'
local F=require 'QueueClaimedReturn'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local index=1
local state,previous,pending
local function raw(event,row)print('[CLAIMED_RETURN] '..event..' '..JSON.encode(row))end
local function fail(player,reason)pending=nil;print('[QUEUE_TEST] FAIL claimed-return server '..tostring(reason));sendServerCommand(player,'ClaimedReturnTest','Failed',{error=tostring(reason)})end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='ClaimedReturnTest'then return end
 local ok,reason=pcall(function()
  assert(player:getUsername()=='client1'and args.case==config.cases[index]and not pending,'unexpected claimed-return actor/case/request')
  if command=='Prepare'then
   assert(not state and args.clientPlacement.centered==true,'claimed-return placement proof missing')
   pending={command=command,player=player,case=args.case,target=P.target(args.placement),arrival=P.observeCentered(player,P.target(args.placement)),since=getTimestampMs()}
  else assert(command=='Verify'and state and state.player==player,'unexpected claimed-return authority command');pending={command=command,player=player,since=getTimestampMs()}end
 end)
 if not ok then fail(player,reason)end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local player=pending.player
 local ok,reason=pcall(function()
  assert(getTimestampMs()-pending.since<20000,'claimed-return authority timeout '..pending.command)
  if pending.command=='Prepare'then
   local proof=P.poll(pending.arrival);if not proof then return end
   state=F.prepare(player,pending.case,pending.target,proof,previous);previous=nil
   raw('PREPARED',state.ids);sendServerCommand(player,'ClaimedReturnTest','Prepared',state.ids);pending=nil
  else
   local receipt=F.verify(state);if not receipt then return end
   raw('VERIFIED',receipt);sendServerCommand(player,'ClaimedReturnTest','Verified',receipt)
   previous=state;state=nil;pending=nil;index=index+1
  end
 end)
 if not ok then fail(player,reason)end
end)
