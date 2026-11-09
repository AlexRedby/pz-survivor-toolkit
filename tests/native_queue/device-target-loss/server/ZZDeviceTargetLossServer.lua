if not isServer()then return end
local F=require 'QueueDeviceTargetLoss'
local P=require 'QueueEnergyPlacement'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local state,pending;local index=1
local function raw(name,value)print('[DEVICE_TARGET_LOSS] '..name..' '..JSON.encode(value))end
local function reply(player,name,value)raw(name:upper(),value);sendServerCommand(player,'DeviceTargetLossTest',name,value)end
local function fail(player,error,identifier,command)
 print('[QUEUE_TEST] FAIL device-target-loss server '..tostring(error))
 sendServerCommand(player,'DeviceTargetLossTest','Failed',{case=identifier,command=command,error=tostring(error)});pending=nil
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='DeviceTargetLossTest'then return end
 local ok,error=pcall(function()
  assert(player:getUsername()=='client1'and args.case==config.cases[index],'device loss actor/case differs')
  assert(not pending,'overlapping device loss request')
  if command=='Prepare'then
   assert(not state and args.clientPlacement.mode=='local','device loss preparation order differs')
   pending={player=player,target=P.target(args.placement),arrival=P.observe(player,args.placement),command=command,case=args.case}
  else
   assert(state and state.player==player,'device loss authority state differs')
   if command=='Mutate'then reply(player,'Mutated',F.mutate(state))
   elseif command=='Verify'then assert(state.mutation and not state.cleaned);reply(player,'Verified',F.snapshot(state))
   elseif command=='Cleanup'then reply(player,'Cleaned',F.cleanup(state));state=nil;index=index+1
   else error('unknown device loss request')end
  end
 end)
 if not ok then fail(player,error,type(args)=='table'and args.case or nil,command)end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local player,identifier,command=pending.player,pending.case,pending.command
 local ok,error=pcall(function()
  local proof=P.poll(pending.arrival);if not proof then return end
  assert(P.at(player,pending.target),'device loss replica left placement')
  state=F.prepare(player,config.cases[index],config.mode,pending.target,proof)
  reply(player,'Prepared',state.ids);pending=nil
 end)
 if not ok then fail(player,error,identifier,command)end
end)
