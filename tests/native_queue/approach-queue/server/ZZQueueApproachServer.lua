if not isServer()then return end
local F=require 'QueueApproach';local JSON=require 'QueueHealthEvents';local config=require 'QueueTestSelection'
local P=require 'QueueEnergyPlacement'
local state,pending,layout;local index=1
local function raw(event,value)print('[QUEUE_APPROACH] '..event..' '..JSON.encode(value))end
local function fail(player,error)pending=nil;print('[QUEUE_TEST] FAIL approach-queue server '..tostring(error));sendServerCommand(player,'QueueApproachTest','Failed',{error=tostring(error)})end
local function plan(player,case)
 local ids=F.plan(player,case);layout={player=player,ids=ids}
 raw('LAYOUT',{case=case,actor='client1',target=ids.target})
 sendServerCommand(player,'QueueApproachTest','Layout',ids)
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='QueueApproachTest'then return end
 local ok,error=pcall(function()
  assert(type(args)=='table'and player:getUsername()=='client1'and args.case==config.cases[index],'unexpected approach actor/case')
  assert(not pending or pending.command=='Baseline'or pending.command=='Verify','approach placement request pending')
  if command=='Layout'then
   assert(not state and not pending and not layout,'previous approach layout unsettled')
   if player:getCurrentSquare()then plan(player,args.case)
   else pending={command='Layout',player=player,case=args.case,since=getTimestampMs()}end
  elseif command=='Prepare'then
   assert(not state and not pending and layout and layout.player==player and layout.ids.case==args.case,'approach layout was not reserved')
   local target=P.target(args.target);local expected=layout.ids.target;local proof=args.clientPlacement
   assert(target.x==expected.x and target.y==expected.y and target.z==expected.z,'approach preparation target differs from layout')
   assert(type(proof)=='table'and proof.mode=='local'and proof.centered==true and proof.teleports==1 and proof.centers==1,'approach owning-client centered proof missing')
   local observed=P.target(proof.target)
   assert(observed.x==target.x and observed.y==target.y and observed.z==target.z,'approach client arrival target differs')
   pending={command='Prepare',player=player,case=args.case,target=target,arrival=P.observeCentered(player,target)}
  elseif command=='Snapshot'then
   assert(state and state.player==player,'snapshot without prepared authority');local snapshot=F.snapshot(state);raw('SNAPSHOT',snapshot);sendServerCommand(player,module,'Snapshot',snapshot)
  else assert(state and state.player==player and not pending and(command=='Baseline'or command=='Verify'));pending={command=command,since=getTimestampMs()}end
 end);if not ok then fail(player,error)end
end)
Events.OnTick.Add(function()
 if pending and(pending.command=='Layout'or pending.command=='Prepare')then
  local request=pending
  local ok,error=pcall(function()
   if request.command=='Layout'then
    assert(getTimestampMs()-request.since<30000,'approach layout loading timed out')
    if not request.player:getCurrentSquare()then return end
    pending=nil;plan(request.player,request.case)
   else
    local proof=P.poll(request.arrival);if not proof then return end
    assert(P.atCentered(request.player,request.target),'approach authority left final centered placement')
    state=F.prepare(request.player,request.case,config.mode,request.target,proof);pending=nil
    raw('PREPARED',state.ids);sendServerCommand(request.player,'QueueApproachTest','Prepared',state.ids)
   end
  end)
  if not ok then fail(request.player,error)end
  return
 end
 if not state then return end
 local ok,error=pcall(function()
  F.snapshot(state)
  if not pending then return end
  local receipt,actual=(pending.command=='Baseline'and F.baseline or F.verify)(state)
  if receipt then local command=pending.command;raw(command=='Baseline'and'BASELINE'or'VERIFIED',receipt);sendServerCommand(state.player,'QueueApproachTest',command=='Baseline'and'Baselined'or'Verified',receipt);pending=nil
   if command=='Verify'then state,layout=nil,nil;index=index+1 end
  elseif getTimestampMs()-pending.since>20000 then error(JSON.encode(actual or F.snapshot(state)))end
 end);if not ok then fail(state.player,error)end
end)
