if not isServer()then return end
local P=require 'QueueEnergyPlacement'
local F=require 'QueueDeviceBatteryBinding'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local state,pending,previous;local index=1
local function raw(event,value)print('[DEVICE_BATTERY_BINDING] '..event..' '..JSON.encode(value))end
local function fail(player,error)
 pending=nil;print('[QUEUE_TEST] FAIL device-battery-binding server '..tostring(error))
 sendServerCommand(player,'DeviceBatteryBindingTest','Failed',{error=tostring(error)})
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='DeviceBatteryBindingTest'then return end
 local ok,error=pcall(function()
  assert(player:getUsername()=='client1'and args.case==config.cases[index],'unexpected TV actor/case order')
  if command=='Prepare'then
   assert(not state and not pending,'duplicate TV prepare')
   local target=P.target(args.placement)
   assert(type(args.clientPlacement)=='table'and args.clientPlacement.mode=='local','TV owning-client placement proof missing')
   pending={command='Prepare',player=player,case=args.case,since=getTimestampMs(),target=target,arrival=P.observe(player,target)}
  else
   assert((command=='Baseline'or command=='Verify')
    and state and state.player==player and not pending,'unexpected TV authority request')
   pending={command=command,since=getTimestampMs()}
  end
 end)
 if not ok then fail(player,error)end
end)
Events.OnTick.Add(function()
 if not pending then return end
 if pending.command=='Prepare'then
  local player=pending.player
  local ok,problem=pcall(function()
   local proof=P.poll(pending.arrival);if not proof then return end
   assert(P.at(player,pending.target),'TV replica left settled placement before preparation')
   state=F.prepare(player,pending.case,config.mode,pending.target,proof,previous);previous=nil
   raw('PREPARED',state.ids);sendServerCommand(player,'DeviceBatteryBindingTest','Prepared',state.ids);pending=nil
  end)
  if not ok then fail(player,problem)end
  return
 end
 local command=pending.command
 local inspect=command=='Baseline'and F.baseline or F.verify
 local ok,receipt,actual=pcall(inspect,state)
 if ok and receipt then
  local marker=command=='Baseline'and'BASELINE'or'VERIFIED'
  local reply=command=='Baseline'and'Baselined'or'Verified'
  raw(marker,receipt);sendServerCommand(state.player,'DeviceBatteryBindingTest',reply,receipt)
  pending=nil
  if command=='Verify'then previous=state;state=nil;index=index+1 end
 elseif not ok or getTimestampMs()-pending.since>20000 then
  fail(state.player,ok and JSON.encode(actual or F.snapshot(state))or receipt)
 elseif not pending.diagnosed and getTimestampMs()-pending.since>2000 then
  pending.diagnosed=true;raw('AUTHORITY_WAIT',{command=pending.command,actual=actual or F.snapshot(state)})
 end
end)
