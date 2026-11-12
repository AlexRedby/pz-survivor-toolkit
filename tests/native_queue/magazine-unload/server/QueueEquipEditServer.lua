local config=require 'QueueTestSelection'
if config.suite~='magazine-unload'or config.cases[1]~='equip-edit'or not isServer()then return end
if PZ_QUEUE_EQUIP_EDIT_SERVER_RUNNING then return end;PZ_QUEUE_EQUIP_EDIT_SERVER_RUNNING=true
local P=require 'QueueEnergyPlacement'
local F=require 'QueueEquipEdit'
require 'QueueEquipHostPoint'
local JSON=require 'QueueHealthEvents'
local state,pending,previous;local index=1
local function segment()return F.segments[index]end
local function raw(event,value)print('[EQUIP_EDIT] '..event..' '..JSON.encode(value))end
local function fail(player,error)
 pending=nil;print('[QUEUE_TEST] FAIL magazine-unload equip-edit server '..tostring(error))
 sendServerCommand(player,'EquipEditTest','Failed',{error=tostring(error)})
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='EquipEditTest'then return end
 local ok,error=pcall(function()
  assert(player:getUsername()=='client1'and args.case=='equip-edit'and args.segment==segment(),'unexpected equip actor/segment order')
  if command=='Prepare'then
   assert(not state and not pending,'duplicate equip preparation')
   local target=P.target(args.placement)
   assert(args.clientPlacement and args.clientPlacement.mode=='local'and args.clientPlacement.centered==true and args.clientPlacement.centers==1,'local centered placement proof missing')
   pending={command=command,player=player,target=target,arrival=P.observeCentered(player,target),since=getTimestampMs()}
  else assert(command=='Verify'and state and state.player==player and not pending,'unexpected equip authority request')
   pending={command=command,since=getTimestampMs()}end
 end)
 if not ok then fail(player,error)end
end)
Events.OnTick.Add(function()
 if not pending then return end
 if pending.command=='Prepare'then
  local player=pending.player;local ok,error=pcall(function()
   local proof=P.poll(pending.arrival);if not proof then return end
   assert(P.atCentered(player,pending.target),'replica left centered placement')
   state=F.prepare(player,segment(),config.mode,config.kind,pending.target,proof,previous,config.options and config.options.equip_workload);previous=nil
   raw('PREPARED',state.ids);sendServerCommand(player,'EquipEditTest','Prepared',state.ids);pending=nil
  end)
  if not ok then fail(player,error)end
 else
  local ok,receipt=pcall(F.verify,state)
  if ok and receipt then
   raw('VERIFIED',receipt);sendServerCommand(state.player,'EquipEditTest','Verified',receipt)
   previous=state;state=nil;pending=nil;index=index+1
  elseif not ok or getTimestampMs()-pending.since>20000 then fail(state.player,ok and JSON.encode(F.snapshot(state))or receipt)end
 end
end)
