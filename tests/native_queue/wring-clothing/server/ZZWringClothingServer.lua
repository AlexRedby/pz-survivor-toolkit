if not isServer()then return end
local P=require 'QueueEnergyPlacement'
local F=require 'QueueWringClothing'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local state,pending,previous;local index=1
local function raw(event,value)print('[WRING_CLOTHING] '..event..' '..JSON.encode(value))end
local function fail(player,error)
 pending=nil;print('[QUEUE_TEST] FAIL wring-clothing server '..tostring(error))
 sendServerCommand(player,'WringClothingTest','Failed',{error=tostring(error)})
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='WringClothingTest'then return end
 local ok,error=pcall(function()
  assert(player:getUsername()=='client1'and args.case==config.cases[index],'unexpected wring actor/case order')
  if command=='Prepare'then
   assert(not state and not pending,'duplicate wring prepare')
   local target=P.target(args.placement)
   assert(type(args.clientPlacement)=='table'and args.clientPlacement.mode=='local'and args.clientPlacement.centered==true and args.clientPlacement.centers==1,'wring local placement proof missing')
   pending={command=command,player=player,target=target,case=args.case,arrival=P.observeCentered(player,target),since=getTimestampMs()}
  else
   assert((command=='Verify'or command=='WearBaseline'and state and state.ids.nativeWearSetup)
    and state and state.player==player and not pending,'unexpected wring authority request')
   pending={command=command,since=getTimestampMs()}
  end
 end)
 if not ok then fail(player,error)end
end)
Events.OnTick.Add(function()
 if not pending then return end
 if pending.command=='Prepare'then
  local player=pending.player
  local ok,error=pcall(function()
   local proof=P.poll(pending.arrival);if not proof then return end
   assert(P.atCentered(player,pending.target),'wring replica left settled placement')
   state=F.prepare(player,pending.case,config.mode,pending.target,proof,previous);previous=nil
   raw('PREPARED',state.ids);sendServerCommand(player,'WringClothingTest','Prepared',state.ids);pending=nil
  end)
  if not ok then fail(player,error)end
 else
  local baseline=pending.command=='WearBaseline'
  local ok,receipt=pcall(baseline and F.wearBaseline or F.verify,state)
  if ok and receipt then
   raw(baseline and'WEAR_BASELINE'or'VERIFIED',receipt)
   sendServerCommand(state.player,'WringClothingTest',baseline and'WearBaselined'or'Verified',receipt)
   pending=nil
   if not baseline then previous=state;state=nil;index=index+1 end
  elseif not ok or getTimestampMs()-pending.since>20000 then
   fail(state.player,ok and JSON.encode(F.preparedDiagnostic(state.player,state.ids))or receipt)
  elseif not pending.diagnosed and getTimestampMs()-pending.since>2000 then
   pending.diagnosed=true;raw('AUTHORITY_WAIT',{command=pending.command,state=F.preparedDiagnostic(state.player,state.ids)})
  end
 end
end)
