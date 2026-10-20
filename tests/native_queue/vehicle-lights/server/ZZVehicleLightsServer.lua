local F=require 'VehicleLightsFixture'
local video=require 'QueueLightsConfig'
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='VehicleLightsTest' then return end
 assert(player:getUsername()=='client1')
 if command=='prepare' then
  local v=F.prepare(player,args.x,args.y,args.dir,video.rocker and 'Base.PickUpTruck' or nil)
  sendServerCommand(player,module,'vehicle',{id=v:getId()})
 elseif command=='start' then
  local v=assert(F.vehicle);assert(v:isDriver(player),'server driver missing')
  v:tryStartEngine(true);v:setHeadlightsOn(true)
  print('[VEHICLE_LIGHTS] AUTHORITY driver=true engine-request=true')
 elseif command=='rockerPower' then
  local v=assert(F.vehicle);assert(v:isDriver(player),'server driver missing at rocker check')
  assert(v:getHeadlightsOn()==args.on,'server headlight power differs from settled rocker position')
  sendServerCommand(player,module,'rockerPower',{mode=args.mode,on=v:getHeadlightsOn()})
 end
end)
