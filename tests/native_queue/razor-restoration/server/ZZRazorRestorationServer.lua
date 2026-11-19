if not isServer()then return end
local P=require 'QueueEnergyPlacement'
local F=require 'QueueRazorRestoration'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local index=1
local state,previous,pending
local function raw(event,row)print('[RAZOR_RESTORATION] '..event..' '..JSON.encode(row))end
local function fail(player,reason)state=nil;pending=nil;print('[QUEUE_TEST] FAIL razor-restoration server '..tostring(reason));sendServerCommand(player,'RazorRestorationTest','Failed',{error=tostring(reason)})end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='RazorRestorationTest'then return end
 local ok,reason=pcall(function()
  assert(player:getUsername()=='client1'and args.case==config.cases[index]and not pending,'unexpected razor-restoration actor/case/request')
  if command=='Prepare'then
   assert(not state and args.clientPlacement.centered==true,'razor-restoration placement proof missing')
   pending={command=command,player=player,case=args.case,target=P.target(args.placement),arrival=P.observeCentered(player,P.target(args.placement)),since=getTimestampMs()}
  elseif command=='ChangeHeavy'then
   assert(state and state.player==player,'heavy intervention without exact authority seed')
   -- The client's intervention can arrive before the server's next observation tick.
   local dropped=F.observeHeavyAuthority(state)
   if dropped then raw('HEAVY_AUTHORITY',dropped)end
   local receipt=F.removeHeavy(state,args.requestedAt);raw('HEAVY_REMOVED',receipt);sendServerCommand(player,'RazorRestorationTest','HeavyChanged',receipt)
  elseif command=='ChangeOrigin'then
   assert(state and state.player==player,'origin intervention without authority seed')
   local receipt=F.changeOrigin(state,args.requestedAt);raw('ORIGIN',receipt);sendServerCommand(player,'RazorRestorationTest','OriginChanged',receipt)
  else assert(command=='Verify'and state and state.player==player,'unexpected razor-restoration authority command');pending={command=command,player=player,since=getTimestampMs()}end
 end)
 if not ok then fail(player,reason)end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local player=pending.player
 local ok,reason=pcall(function()
  assert(getTimestampMs()-pending.since<20000,'razor-restoration authority timeout '..pending.command)
  if pending.command=='Prepare'then
   local proof=P.poll(pending.arrival);if not proof then return end
   state=F.prepare(player,pending.case,pending.target,proof,previous);previous=nil
   raw('PREPARED',state.ids);sendServerCommand(player,'RazorRestorationTest','Prepared',state.ids);pending=nil
  else
   local receipt=F.verify(state);if not receipt then return end
   local transfer=F.observeTransferAuthority(state);if transfer then raw('TRANSFER_AUTHORITY',transfer)end
   local heavy=F.observeHeavyAuthority(state);if heavy then raw('HEAVY_AUTHORITY',heavy)end
   receipt.transfers=state.transfers or{};receipt.heavyTransitions=state.heavy or{}
   raw('VERIFIED',receipt);sendServerCommand(player,'RazorRestorationTest','Verified',receipt)
   previous=state;state=nil;pending=nil;index=index+1
  end
 end)
 if not ok then fail(player,reason)end
end)

Events.OnTick.Add(function()
 if not state then return end
 local player=state.player
 local ok,reason=pcall(function()
  local transfer=F.observeTransferAuthority(state);if transfer then raw('TRANSFER_AUTHORITY',transfer)end
  local heavy=F.observeHeavyAuthority(state);if heavy then raw('HEAVY_AUTHORITY',heavy)end
 end)
 if not ok then fail(player,'transfer authority observation: '..tostring(reason))end
end)
