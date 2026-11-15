local selectedEquipEdit=require 'QueueTestSelection'
if selectedEquipEdit.cases[1]=='equip-edit'then require 'QueueEquipEditServer';return end
if not isServer()then return end
local P=require 'QueueEnergyPlacement'
local F=require 'QueueMagazineUnload'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local state,pending,previous;local index=1
local function raw(event,value)print('[MAGAZINE_UNLOAD] '..event..' '..JSON.encode(value))end
local function fail(player,error)
 pending=nil;print('[QUEUE_TEST] FAIL magazine-unload server '..tostring(error))
 sendServerCommand(player,'MagazineUnloadTest','Failed',{error=tostring(error)})
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='MagazineUnloadTest'then return end
 local ok,error=pcall(function()
  assert(player:getUsername()=='client1'and args.case==config.cases[index],'unexpected magazine actor/case order')
  if command=='Prepare'then
   assert(not state and not pending,'duplicate magazine preparation')
   local target=P.target(args.placement)
   assert(args.clientPlacement and args.clientPlacement.mode=='local'and args.clientPlacement.centered==true and args.clientPlacement.centers==1,'local centered placement proof missing')
   pending={command=command,player=player,case=args.case,target=target,arrival=P.observeCentered(player,target),since=getTimestampMs()}
  else assert(command=='Verify'and state and state.player==player and not pending,'unexpected magazine authority request')
   pending={command=command,since=getTimestampMs()}end
 end)
 if not ok then fail(player,error)end
end)
Events.OnTick.Add(function()
 if not pending then return end
 if pending.command=='Prepare'then
  local player=pending.player
  local ok,error=pcall(function()
   local proof=P.poll(pending.arrival);if not proof then return end
   assert(P.atCentered(player,pending.target),'replica left centered placement')
   state=F.prepare(player,pending.case,config.mode,pending.target,proof,previous);previous=nil
   raw('PREPARED',state.ids);sendServerCommand(player,'MagazineUnloadTest','Prepared',state.ids);pending=nil
  end)
  if not ok then fail(player,error)end
 else
  local ok,receipt=pcall(F.verify,state)
  if ok and receipt then
   raw('VERIFIED',receipt);sendServerCommand(state.player,'MagazineUnloadTest','Verified',receipt)
   previous=state;state=nil;pending=nil;index=index+1
  elseif not ok or getTimestampMs()-pending.since>20000 then fail(state.player,ok and JSON.encode(F.snapshot(state))or receipt)
  elseif not pending.diagnosed and getTimestampMs()-pending.since>2000 then pending.diagnosed=true;raw('AUTHORITY_WAIT',F.snapshot(state))end
 end
end)
