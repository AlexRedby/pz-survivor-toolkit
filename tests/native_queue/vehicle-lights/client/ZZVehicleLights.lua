local config=require 'QueueTestSelection'
local video=require 'QueueLightsConfig'
local F=require 'VehicleLightsFixture'
local phase,since,started,done,requested=0,0,false,false,false
local vehicle,vehicleId,recordSince,stopSince,nextAt,label,origin
local originDebug=false
local variantIndex,variantStep,variantSince=1,0,0
local rotaryScale,rotaryStep=1,0
local variants={{script="Base.PickUpTruck",family="heavy"},{script="Base.SportsCar",family="sport"}}
local function log(text) print('[VEHICLE_LIGHTS] '..text) end
local function clock() return getTimestampMs() end
local function hideUI()
 -- Hide only this disposable profile's overlays; lighting mods remain active.
 local options=PZAPI.ModOptions:getOptions('MiniHealthPlus')
 local option=options and options:getOption('DisableMod')
 if option and not option:getValue() then
  option:setValue(true)
  if TwisTonFire_MHP_RefreshModOptions then TwisTonFire_MHP_RefreshModOptions() end
 end
 if video.dashboard then
  if not ISUIHandler.allUIVisible then ISUIHandler.toggleUI() end
  local dash=getPlayerVehicleDashboard(0)
  if dash and getPlayer() and getPlayer():getVehicle() then dash:setVisible(true) end
 else
  if ISUIHandler.allUIVisible then ISUIHandler.toggleUI() end
 end
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
 for _,fn in ipairs({getPlayerInventory,getPlayerLoot,getPlayerInfoPanel}) do
  if fn and fn(0) then fn(0):setVisible(false) end
 end
end
local function climate()
 getGameTime():setTimeOfDay(originDebug and 12 or 2)
 local manager=getClimateManager()
 for _,spec in ipairs({{ClimateManager.FLOAT_AMBIENT,1},{ClimateManager.FLOAT_DAYLIGHT_STRENGTH,1},{ClimateManager.FLOAT_NIGHT_STRENGTH,0}}) do
  local value=manager:getClimateFloat(spec[1]);value:setEnableAdmin(originDebug);value:setAdminValue(spec[2])
 end
 local c=getClimateManager()
 for _,index in ipairs({ClimateManager.FLOAT_FOG_INTENSITY,ClimateManager.FLOAT_PRECIPITATION_INTENSITY,ClimateManager.FLOAT_CLOUD_INTENSITY}) do
  local v=c:getClimateFloat(index);v:setEnableAdmin(true);v:setAdminValue(index==ClimateManager.FLOAT_CLOUD_INTENSITY and 1 or 0)
 end
end
local function verifyOrigins(name)
 if not video.origins or not PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('VehicleBeamShape'):getValue() then return end
 local module=PZSurvivorToolkit.VehicleLighting
 local ids={'HeadlightLeft','HeadlightRight'}
 if ReverseDriveLights.Client.players[0] then ids={'HeadlightLeft','HeadlightRight','HeadlightRearLeft','HeadlightRearRight'} end
 for _,id in ipairs(ids) do
  local x,y,z=module.lampOrigin(vehicle,id)
  assert(x,'model has no actual mesh lamp origin: '..vehicle:getScript():getModel():getFile())
  local error=lightsFixtureOriginError(id,x,z)
  assert(error<.002,'native cone origin differs from mesh lamp: '..id..' error='..error)
  log('ORIGIN '..name..' part='..id..' model='..vehicle:getScript():getModel():getFile()..' local='..x..','..y..','..z..' nativeError='..error)
 end
end
local function dashboardCapture(name)
 if not video.dashboard then return end
 verifyOrigins(name)
 local dash=assert(getPlayerVehicleDashboard(0),'dashboard missing')
 local image=assert(dash.warnLightTex,'Realistic Dashboard lamp missing')
 local module=assert(PZSurvivorToolkit.VehicleLightDashboard,'beam indicator module missing')
 local expected=not vehicle:getHeadlightsOn() and 'off' or (NepHBO7.getModData(vehicle).highBeamsOn and 'high' or 'low')
 local before=video.dashboardCompare and not module.installed
 if before then
  assert(not image.__toolkitBeamWrapped,'baseline already modified')
 else
  assert(image.__toolkitBeamMode==expected,'dashboard does not match actual beam state')
  assert(image.__toolkitBeamWrapped,'native lamp not integrated')
 end
 if video.rotary and dash.__YourDashFamily=='standard' then
  local selected=module.switchMode(dash)
  assert(dash.__lightKnobAngle==({off=0,low=45,high=90})[selected],'rotary detent does not match selected beam')
 end
 local box=dash.backgroundTex
 log('DASHBOARD '..name..' elapsedMs='..(clock()-recordSince)..' mode='..expected..' family='..tostring(dash.__YourDashFamily)
  ..' integration='..tostring(module.installed==true)..' scale='..require('YourDash/DashboardCore').GetScaleKey()..' alpha='..tostring(image.backgroundColor.a)..' visible='..tostring(image:getIsVisible())
  ..' box='..math.floor(box:getAbsoluteX())..','..math.floor(box:getAbsoluteY())..','..math.ceil(box:getWidth())..','..math.ceil(box:getHeight())
  ..' lamp='..math.floor(image:getAbsoluteX())..','..math.floor(image:getAbsoluteY())..','..math.ceil(image:getWidth())..','..math.ceil(image:getHeight())
  ..' angle='..tostring(dash.__lightKnobAngle))
 if video.rocker and isClient() then
  sendClientCommand('VehicleLightsTest','rockerPower',{mode=expected,on=expected~='off'})
 end
end
local function capture(name)
 local total=0
 for _,state in pairs(PZSurvivorToolkit.VehicleLighting.states) do
  for _,entry in pairs(state.lights) do total=total+1 end
 end
 assert((name=='off' or name=='off_after' or name=='close_no_spill') and total==0 or
  (name~='off' and name~='off_after' and name~='close_no_spill' and total>0), 'spill lifecycle at '..name..' count='..total)
 log('SPILL '..name..' count='..total)
 dashboardCapture(name)
 label=name
 log('PHASE '..name..' elapsedMs='..(clock()-recordSince)..' probe='..lightsFixtureProbe())
end
local function rotaryClick(expected)
 local dash=assert(getPlayerVehicleDashboard(0))
 assert(dash.__YourDashFamily=='standard','rotary fixture requires standard')
 local control=assert(dash.lightsTex)
 assert(control.__toolkitBeamRotaryClick==control.onclick,'rotary click not bound')
 local before=PZSurvivorToolkit.VehicleLightDashboard.switchMode(dash)
 if control.onMouseDown then control:onMouseDown(control.width*.5,control.height*.5) end
 control:onMouseUp(control.width*.5,control.height*.5)
 assert(PZSurvivorToolkit.VehicleLightDashboard.switchMode(dash)==expected,'wrong rotary click result')
 log('ROTARY_CLICK '..before..' '..expected)
end
local function rockerClick(expected, upper)
 local dash=assert(getPlayerVehicleDashboard(0))
 assert(dash.__YourDashFamily=='heavy','rocker fixture requires truck')
 local control=assert(dash.lightsTex)
 assert(control.__toolkitBeamRockerClick==control.onclick,'rocker click not bound')
 local before=PZSurvivorToolkit.VehicleLightDashboard.switchMode(dash)
 local x,y=control.width*.5,control.height*(upper and .25 or .75)
 if control.onMouseDown then control:onMouseDown(x,y) end
 control:onMouseUp(x,y)
 assert(PZSurvivorToolkit.VehicleLightDashboard.switchMode(dash)==expected,'wrong rocker click result')
 log('ROCKER_CLICK '..before..' '..expected)
end
local function headlights(value)
 vehicle:setHeadlightsOn(value)
 if isClient() then sendClientCommand(getPlayer(),'vehicle','setHeadlightsOn',{vehicle=vehicle:getId(),on=value}) end
end
Events.OnServerCommand.Add(function(module,command,args)
 if module=='VehicleLightsTest' and command=='vehicle' then vehicleId=args.id end
 if module=='VehicleLightsTest' and command=='rockerPower' then
  assert(args.on==(args.mode~='off'),'server power acknowledgement mismatch')
  log('HOST_ROCKER_POWER '..args.mode..' on='..tostring(args.on))
 end
end)
Events.OnGameStart.Add(function() started=true;since=clock() end)
Events.OnPostUIDraw.Add(function()
 if label then getTextManager():DrawString(UIFont.Medium,25,30,'Vehicle lights | '..config.kind..' | '..label..(originDebug and ' | 12:00 geometry diagnostic (not night comparison)' or ' | 02:00 | 20 July 1993 | Pitch Black / new moon'),1,1,1,1) end
 if originDebug then
  for _,id in ipairs({'HeadlightLeft','HeadlightRight','HeadlightRearLeft','HeadlightRearRight'}) do
   local x,y=lightsFixtureOriginScreenX(id),lightsFixtureOriginScreenY(id)
   getTextManager():DrawString(UIFont.Small,x-4,y-8,'+',1,.2,.2,1)
  end
 end
end)
local function run()
 local p=getPlayer();if not p or not p:getSquare() then return end
 climate();hideUI()
 if phase==0 then
  if clock()-since<12000 then return end
  p:setGodMod(true);p:setGhostMode(true);p:setAutoDrink(false)
  assert(not p:hasTrait(CharacterTrait.NIGHT_VISION),'Fixture must not have night vision')
  local x,y,dir=F.position(p);origin={x=x,y=y,dir=dir}
  if isClient() then sendClientCommand('VehicleLightsTest','prepare',origin) else vehicle=F.prepare(p,x,y,dir) end
  p:teleportTo(x+2,y+2,0)
  phase=1;since=clock()
 elseif phase==1 then
  if isClient() then vehicle=vehicleId and getVehicleById(vehicleId) end
  if not vehicle or clock()-since<2000 then return end
  assert(vehicle:getSquare(),'spawned vehicle is not in world')
  vehicle:enter(0,p);vehicle:setCharacterPosition(p,0,'inside');vehicle:transmitCharacterPosition(0,'inside')
  triggerEvent('OnEnterVehicle',p)
  assert(vehicle:isDriver(p),'driver entry failed')
  lightsFixtureInput(0);lightsFixtureCamera(4.5)
  if video.dashboard then require('YourDash/DashboardCore').SetTextureSizeIndex(2) end
  assert(NepHBO7 and ReverseDriveLights and ReverseDriveLights.Client and PZSurvivorToolkit.VehicleLighting,'lighting modules required')
  local opts=PZAPI.ModOptions:getOptions('PZSurvivorToolkit')
  opts:getOption('VehicleBeamShape'):setValue(false)
  PZSurvivorToolkit.VehicleLighting.refreshBeams()
  opts:getOption('VehicleReverseLight'):setValue(2)
  opts:getOption('VehicleLightSpill'):setValue(3)
  PZSurvivorToolkit.VehicleLighting.configureReverse()
  NepHBO7.options.alwaysOn:setValue(false);NepHBO7.options.lengthMult:setValue(1.5);NepHBO7.options.intensityMult:setValue(2)
  NepHBO7.options.debugMode:setValue(false);NepHBO7.deactivateHighBeams(vehicle)
  if isClient() then sendClientCommand('VehicleLightsTest','start',{}) else vehicle:tryStartEngine(true) end
  phase=2;since=clock()
 elseif phase==2 then
  if not vehicle:isEngineRunning() then assert(clock()-since<20000,'engine failed to start');return end
  headlights(false);label='off';lightsFixtureCamera(4.5)
  assert(toolkitVideoStatus().state=='idle');assert(toolkitVideoStart(video.directory,video.ffmpeg))
  local c=getClimateManager()
  log('ENV time='..getGameTime():getTimeOfDay()..' nightDarkness='..getSandboxOptions():getOptionByName('NightDarkness'):getValue()..' ambient='..c:getAmbient()..' nightStrength='..c:getNightStrength()..' daylight='..c:getDayLightStrength()..' moon='..getClimateMoon():getMoonFloat())
  assert(getSandboxOptions():getOptionByName('NightDarkness'):getValue()==1,'Pitch Black sandbox required')
  assert(c:getNightStrength()>.95 and c:getDayLightStrength()<.01,'Climate is not deep night')
  assert(getClimateMoon():getMoonFloat()==0,'Moonless night required')
  recordSince=clock();phase=3;since=clock()
 elseif phase==3 and clock()-since>2500 then
  capture('off');if video.rotary then rotaryClick('low') elseif video.rocker and isClient() then rockerClick('low',true) else headlights(true);NepHBO7.deactivateHighBeams(vehicle) end;label='original_low';phase=20;since=clock()
 elseif phase==20 and clock()-since>3000 then
  capture('original_low');if video.rotary then rotaryClick('high') elseif video.rocker and isClient() then rockerClick('high',true) else NepHBO7.toggleHighBeam(vehicle) end;label='original_high';phase=21;since=clock()
 elseif phase==21 and clock()-since>3000 then
  capture('original_high')
  if video.dashboardCompare then assert(PZSurvivorToolkit.VehicleLightDashboard.installDeferred);PZSurvivorToolkit.VehicleLightDashboard.installDeferred() end
  PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('VehicleBeamShape'):setValue(true)
  if video.rotary then rotaryClick('off');label='rotary_off';phase=22
  elseif video.rocker and isClient() then rockerClick('low',false);label='heavy_return_low';phase=23
  else NepHBO7.deactivateHighBeams(vehicle);label='low';phase=4 end;since=clock()
 elseif phase==23 and clock()-since>2500 then
  dashboardCapture('heavy_return_low');rockerClick('off',false);label='heavy_off';phase=24;since=clock()
 elseif phase==24 and clock()-since>2500 then
  dashboardCapture('heavy_off');headlights(true);NepHBO7.deactivateHighBeams(vehicle);label='low';phase=4;since=clock()
 elseif phase==22 and clock()-since>2200 then
  dashboardCapture('rotary_off');rotaryClick('low');label='low';phase=4;since=clock()
 elseif phase==4 and clock()-since>3000 then
  capture('low');if video.rotary then rotaryClick('high') else NepHBO7.toggleHighBeam(vehicle) end;label='high';phase=5;since=clock()
 elseif phase==5 and clock()-since>3000 then
  capture('high');NepHBO7.deactivateHighBeams(vehicle);lightsFixtureInput(1);label='reverse_low';phase=6;since=clock()
 elseif phase==6 then
  if not ReverseDriveLights.isVehicleInReverse(vehicle) or not ReverseDriveLights.Client.players[0] then
   assert(clock()-since<18000,'native reverse not engaged');return
  end
  if math.abs(vehicle:getCurrentSpeedKmHour())<1 then assert(clock()-since<18000,'no reverse motion');return end
  if clock()-since<2000 then return end
  capture('reverse_low');NepHBO7.toggleHighBeam(vehicle);label='reverse_high';phase=7;since=clock()
 elseif phase==7 and clock()-since>2200 then
  assert(ReverseDriveLights.isVehicleInReverse(vehicle),'native reverse lost')
  capture('reverse_high');lightsFixtureInput(3);phase=8;since=clock()
 elseif phase==8 then
  if math.abs(vehicle:getCurrentSpeedKmHour())>.1 then assert(clock()-since<15000,'brake did not stop vehicle');return end
  lightsFixtureInput(2);phase=9;since=clock()
 elseif phase==9 then
  if ReverseDriveLights.isVehicleInReverse(vehicle) then assert(clock()-since<15000,'native gear remained R');return end
  lightsFixtureInput(3);NepHBO7.deactivateHighBeams(vehicle);label='restored';phase=10;since=clock()
 elseif phase==10 and clock()-since>2500 then
  assert(not ReverseDriveLights.Client.players[0],'reverse state not restored')
  capture('restored');lightsFixtureCamera(2.5);lightsFixtureInput(3);label='close_low';phase=12;since=clock()
 elseif phase==12 and clock()-since>2500 then
  capture('close_low');PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('VehicleLightSpill'):setValue(1)
  label='close_no_spill';phase=13;since=clock()
 elseif phase==13 and clock()-since>2500 then
  capture('close_no_spill');PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('VehicleLightSpill'):setValue(3)
  headlights(false);label='off_after';phase=14;since=clock()
 elseif phase==14 and clock()-since>2500 then
  capture('off_after');lightsFixtureInput(0)
  if video.dashboard and not isClient() then
   if video.rotary then
    require('YourDash/DashboardCore').SetTextureSizeIndex(1)
    phase=32;rotaryScale=1;rotaryStep=0;label='standard_scale_0.75x_off';since=clock()
   elseif video.origins then
    headlights(true);NepHBO7.deactivateHighBeams(vehicle);lightsFixtureCamera(1.2)
    originDebug=true;label='standard_geometry';phase=31;since=clock()
   else phase=30;variantStep=0 end
  else assert(toolkitVideoStop());stopSince=clock();phase=11 end
 elseif phase==32 and clock()-since>1800 then
  local scales={'0.75x','1x','1.4x','2x'}
  local mode=({'off','low','high'})[rotaryStep+1]
  dashboardCapture('standard_scale_'..scales[rotaryScale]..'_'..mode)
  if rotaryStep<2 then
   rotaryClick(rotaryStep==0 and 'low' or 'high');rotaryStep=rotaryStep+1
  else
   rotaryClick('off');rotaryStep=0;rotaryScale=rotaryScale+1
   if rotaryScale>4 then
    require('YourDash/DashboardCore').SetTextureSizeIndex(2);phase=30;variantStep=0
   else require('YourDash/DashboardCore').SetTextureSizeIndex(rotaryScale) end
  end
  if phase==32 then label='standard_scale_'..scales[rotaryScale]..'_'..({'off','low','high'})[rotaryStep+1] end
  since=clock()
 elseif phase==31 and clock()-since>2500 then
  dashboardCapture('standard_geometry');headlights(false);originDebug=false;phase=30;variantStep=0
 elseif phase==30 then
  local spec=variants[variantIndex]
  if not spec then assert(toolkitVideoStop());stopSince=clock();phase=11;return end
  if variantStep==0 then
   headlights(false);vehicle:exit(p)
   local x,y=origin.x,origin.y+(variantIndex-1)*10
   p:teleportTo(x+2,y+2,0)
   vehicle=F.prepare(p,x,y,origin.dir,spec.script)
   vehicle:enter(0,p);vehicle:setCharacterPosition(p,0,'inside');vehicle:transmitCharacterPosition(0,'inside')
   triggerEvent('OnEnterVehicle',p)
   getPlayerVehicleDashboard(0):setVehicle(vehicle)
   require('YourDash/DashboardCore').SetTextureSizeIndex(2)
   if video.origins then lightsFixtureCamera(1.2) end
   vehicle:tryStartEngine(true);variantSince=clock();variantStep=1
  elseif variantStep==1 then
   if not vehicle:isEngineRunning() then assert(clock()-variantSince<18000,'variant engine start');return end
   NepHBO7.deactivateHighBeams(vehicle)
   if spec.family=='heavy' and video.rocker then
    headlights(false);label='heavy_initial_off';variantSince=clock();variantStep=8
   else headlights(true);label=spec.family..'_low';variantSince=clock();variantStep=2 end
  elseif variantStep==8 and clock()-variantSince>2200 then
   dashboardCapture('heavy_initial_off');rockerClick('low',true)
   label='heavy_low';variantSince=clock();variantStep=2
  elseif variantStep==2 and clock()-variantSince>2200 then
   assert(getPlayerVehicleDashboard(0).__YourDashFamily==spec.family,'wrong actual dashboard family')
   dashboardCapture(spec.family..'_low')
   if spec.family=='heavy' and video.rocker then rockerClick('high',true) else NepHBO7.toggleHighBeam(vehicle) end
   label=spec.family..'_high';variantSince=clock();variantStep=3
  elseif variantStep==3 and clock()-variantSince>2200 then
   dashboardCapture(spec.family..'_high')
   if spec.family=='sport' then
    require('YourDash/DashboardCore').SetTextureSizeIndex(4)
    label='sport_high_2x';variantSince=clock();variantStep=4
   elseif spec.family=='heavy' and video.rocker then
    rockerClick('low',false);label='heavy_return_low';variantSince=clock();variantStep=9
   else headlights(false);label=spec.family..'_off';variantSince=clock();variantStep=6 end
  elseif variantStep==9 and clock()-variantSince>2200 then
   dashboardCapture('heavy_return_low');rockerClick('off',false)
   label='heavy_off';variantSince=clock();variantStep=10
  elseif variantStep>=10 and variantStep<=13 and clock()-variantSince>2200 then
   local scales={'0.75x','1x','1.4x','2x'}
   if variantStep>10 then dashboardCapture('heavy_scale_'..scales[variantStep-10]) end
   require('YourDash/DashboardCore').SetTextureSizeIndex(variantStep-9)
   label='heavy_scale_'..scales[variantStep-9];variantSince=clock();variantStep=variantStep+1
  elseif variantStep==14 and clock()-variantSince>2200 then
   dashboardCapture('heavy_scale_2x');require('YourDash/DashboardCore').SetTextureSizeIndex(2)
   label='heavy_off';variantSince=clock();variantStep=6
  elseif variantStep==4 and clock()-variantSince>2200 then
   dashboardCapture('sport_high_2x');require('YourDash/DashboardCore').SetTextureSizeIndex(1)
   label='sport_high_075';variantSince=clock();variantStep=5
  elseif variantStep==5 and clock()-variantSince>2200 then
   dashboardCapture('sport_high_075');require('YourDash/DashboardCore').SetTextureSizeIndex(2)
   headlights(false);label=spec.family..'_off';variantSince=clock();variantStep=6
  elseif variantStep==6 and clock()-variantSince>2200 then
   dashboardCapture(spec.family..'_off')
   if video.origins then
    headlights(true);NepHBO7.deactivateHighBeams(vehicle);originDebug=true
    label=spec.family..'_geometry';variantSince=clock();variantStep=7
   else variantIndex=variantIndex+1;variantStep=0 end
  elseif variantStep==7 and clock()-variantSince>2500 then
   dashboardCapture(spec.family..'_geometry');headlights(false);originDebug=false
   variantIndex=variantIndex+1;variantStep=0
  end
 elseif phase==11 then
  local s=toolkitVideoStatus()
  if s.state~='completed' and s.state~='failed' then assert(clock()-stopSince<20000,'recorder did not finish');return end
  log('VIDEO_RESULT '..'{"state":"'..s.state..'","file":"'..s.file..'","frames":'..s.frames..',"seconds":'..s.seconds..',"captured":'..s.captured..',"dropped":'..s.dropped..',"width":'..s.width..',"height":'..s.height..',"error":"'..s.error..'"}')
  assert(s.state=='completed',s.error);lightsFixtureInput(-1);done=true;log('COMPLETE road')
 end
end
Events.OnTick.Add(function()
 if not started or done or not isIngameState() then return end
 local ok,err=pcall(run)
 if not ok then
  done=true;if lightsFixtureInput then lightsFixtureInput(-1) end
  if recordSince and not stopSince then toolkitVideoStop() end
  log('FAIL '..tostring(err))
 end
end)
