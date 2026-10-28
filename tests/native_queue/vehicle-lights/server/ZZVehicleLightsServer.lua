local F=require 'VehicleLightsFixture'
local video=require 'QueueLightsConfig'
local pending,awaitingReplacement,request,generation=nil,nil,0,1
local restorePending,finalRemoval,restored
local quarantined=false
local function quarantine(reason)
 if quarantined then return end
 quarantined=true;restorePending=nil
 print('[VEHICLE_LIGHTS] FAIL '..tostring(reason))
end
local function family(v)
 local script=v:getScript():getFullName()
 return script=='Base.SportsCar' and 'sport' or script=='Base.PickUpTruck' and 'heavy' or 'standard'
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='VehicleLightsTest' then return end
 if quarantined then return end
 assert(player:getUsername()=='client1')
 if command=='prepare' then
  local v=F.prepare(player,args.x,args.y,args.dir,video.push and 'Base.SportsCar' or video.rocker and 'Base.PickUpTruck' or nil)
  sendServerCommand(player,module,'vehicle',{id=v:getId(),generation=generation})
 elseif command=='start' then
  local v=assert(F.vehicle);assert(v:isDriver(player),'server driver missing')
  v:tryStartEngine(true);v:setHeadlightsOn(true)
  print('[VEHICLE_LIGHTS] AUTHORITY driver=true engine-request=true')
 elseif command=='power' then
  local v=assert(F.vehicle);assert(v:isDriver(player),'server driver missing at rocker check')
  assert(args.id==v:getId() and args.generation==generation and args.family==family(v),'power request vehicle/family differs')
  assert(args.request==request+1 and args.on==(args.mode~='off'),'duplicate/out-of-order power request')
  assert(v:getHeadlightsOn()==args.on,'server headlight power differs from settled rocker position')
  request=args.request
  print('[VEHICLE_LIGHTS] POWER_ACK family='..args.family..' mode='..args.mode..' on='..tostring(args.on)..' id='..args.id..' generation='..generation..' request='..request)
  sendServerCommand(player,module,'power',args)
 elseif command=='replace' or command=='remove' then
  assert(not pending and not awaitingReplacement and F.vehicle and args.id==F.vehicle:getId() and args.generation==generation,'duplicate/unowned vehicle cleanup')
  if command=='replace' then
   assert(video.push and video.rocker and args.script=='Base.PickUpTruck','unsupported Host vehicle replacement')
  end
  pending={player=player,args=args,replace=command=='replace',since=getTimestampMs()}
 elseif command=='removeObserved' then
  local waiting=assert(awaitingReplacement,'unsolicited removal observation')
  assert(player==waiting.player and args.id==waiting.args.id and args.generation==generation and not F.vehicle,'wrong removal observation')
  generation=generation+1
  local spec=waiting.args
  local v=F.prepare(player,spec.x,spec.y,spec.dir,spec.script)
  sendServerCommand(player,module,'replacement',{old=args.id,id=v:getId(),generation=generation})
  awaitingReplacement=nil
 elseif command=='restoreBaseline' then
  assert(finalRemoval==generation and args.generation==generation and not restored and not restorePending
   and not F.vehicle and not pending and not awaitingReplacement,'unexpected authority restoration')
  for _,key in ipairs({'x','y','z','primaryID','secondaryID'}) do assert(type(args[key])=='number' and args[key]==args[key] and math.abs(args[key])<math.huge,'invalid baseline field '..key) end
  restorePending={player=player,args=args,since=getTimestampMs(),settlement=F.newPositionSettlement(args)}
  print('[VEHICLE_LIGHTS] POSITION_AUTHORITY generation='..generation..' '..F.positionText(player,args))
 end
end)
Events.OnTick.Add(function()
 if quarantined then return end
 if awaitingReplacement then assert(getTimestampMs()-awaitingReplacement.since<15000,'client removal observation timeout') end
 if restorePending then
  local p,args=restorePending.player,restorePending.args
  local primary,secondary=p:getPrimaryHandItem(),p:getSecondaryHandItem()
  local idle=not p:getVehicle() and not p:hasTimedActions() and not p:isPlayerMoving()
   and (primary and primary:getID() or -1)==args.primaryID and (secondary and secondary:getID() or -1)==args.secondaryID
  if F.observePositionSettlement(restorePending.settlement,p,getTimestampMs(),idle) then
   print('[VEHICLE_LIGHTS] POSITION_SETTLED stage=authority generation='..generation..' '..F.settlementText(restorePending.settlement,getTimestampMs()))
   print('[VEHICLE_LIGHTS] BASELINE_RESTORED generation='..generation..' primaryID='..args.primaryID..' secondaryID='..args.secondaryID..' position=true')
   sendServerCommand(p,'VehicleLightsTest','baselineRestored',{generation=generation,primaryID=args.primaryID,secondaryID=args.secondaryID,
    stableMs=getTimestampMs()-restorePending.settlement.since,samples=restorePending.settlement.samples,x=p:getX(),y=p:getY(),z=p:getZ()})
   restored=true;restorePending=nil
  elseif getTimestampMs()-restorePending.since>=15000 then
   if not restorePending.diagnosed then
    print('[VEHICLE_LIGHTS] POSITION_AUTHORITY_TIMEOUT generation='..generation..' '..F.positionText(p,args))
    restorePending.diagnosed=true
   end
   quarantine('authority baseline restoration timeout '..F.positionText(p,args));return
  end
 end
 if not pending then return end
 local v=assert(F.vehicle)
 for index=0,v:getMaxPassengers()-1 do
  if v:getCharacter(index) then assert(getTimestampMs()-pending.since<15000,'authority exit did not settle');return end
 end
 local old=F.remove(v);local p,args=pending.player,pending.args
 print('[VEHICLE_LIGHTS] REMOVED index='..generation..' id='..old)
 if pending.replace then awaitingReplacement=pending;awaitingReplacement.since=getTimestampMs() else finalRemoval=generation end
 sendServerCommand(p,'VehicleLightsTest','removed',{id=old,generation=generation})
 pending=nil
end)
