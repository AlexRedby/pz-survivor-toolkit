local config=require 'QueueTestSelection'
local video=require 'QueueLightsConfig'
local F=require 'VehicleLightsFixture'
local phase,since,started,done,requested=0,0,false,false,false
local vehicle,vehicleId,recordSince,stopSince,nextAt,label,origin
local originDebug=false
local variantIndex,variantStep,variantSince=1,0,0
local rotaryScale,rotaryStep=1,0
local pushHeld
local baseline,pendingAcks,request,replacement,removed,cleanupId=nil,{},0
local ownedCount=0
local baselineAck=false
local initialSettlement,initialSince,beforeSettlement,afterSettlement
local variants={{script="Base.PickUpTruck",family="heavy"},{script="Base.SportsCar",family="sport"}}
if config.kind=='mp' then variants=video.push and video.rocker and {{script='Base.PickUpTruck',family='heavy'}} or {} end
local function log(text) print('[VEHICLE_LIGHTS] '..text) end
local function clock() return getTimestampMs() end
local function owned() ownedCount=ownedCount+1;log('OWNED index='..ownedCount..' id='..vehicle:getId()) end
local function cleaned() log('CLEANUP index='..ownedCount..' id='..cleanupId..' queueDrained=true removed=true') end
local function drained()
 local p=getPlayer()
 if #ISTimedActionQueue.getTimedActionQueue(p).queue~=0 or p:hasTimedActions() then return false end
 -- Stock B42 Kahlua exposes pairs(), but no global next().
 for _ in pairs(pendingAcks) do return false end
 return true
end
local function captureBaseline(p)
 assert(not p:getVehicle() and drained(),'fixture requires an unseated actor and empty native action queue')
 local b={x=p:getX(),y=p:getY(),z=p:getZ(),dir=p:getDir(),forwardX=p:getForwardDirectionX(),forwardY=p:getForwardDirectionY(),
  god=p:isGodMod(),ghost=p:isGhostMode(),auto=p:getAutoDrink(),primary=p:getPrimaryHandItem(),secondary=p:getSecondaryHandItem(),
  guide=SurvivalGuide and SurvivalGuide.instance,guideVisible=SurvivalGuide and SurvivalGuide.instance and SurvivalGuide.instance:getIsVisible(),
  time=getGameTime():getTimeOfDay(),ui=ISUIHandler.allUIVisible,climate={},panes={},options={},nep={}}
 for _,index in ipairs({ClimateManager.FLOAT_AMBIENT,ClimateManager.FLOAT_DAYLIGHT_STRENGTH,ClimateManager.FLOAT_NIGHT_STRENGTH,
  ClimateManager.FLOAT_FOG_INTENSITY,ClimateManager.FLOAT_PRECIPITATION_INTENSITY,ClimateManager.FLOAT_CLOUD_INTENSITY}) do
  local value=getClimateManager():getClimateFloat(index);b.climate[index]={enabled=value:isEnableAdmin(),value=value:getAdminValue()}
 end
 for _,fn in ipairs({getPlayerInventory,getPlayerLoot,getPlayerInfoPanel}) do if fn and fn(0) then b.panes[#b.panes+1]={pane=fn(0),visible=fn(0):getIsVisible()} end end
 local opts=PZAPI.ModOptions:getOptions('PZSurvivorToolkit')
 for _,key in ipairs({'VehicleBeamShape','VehicleReverseLight','VehicleLightSpill'}) do b.options[key]=opts:getOption(key):getValue() end
 for _,key in ipairs({'alwaysOn','lengthMult','intensityMult','debugMode'}) do b.nep[key]=NepHBO7.options[key]:getValue() end
 local mhp=PZAPI.ModOptions:getOptions('MiniHealthPlus');b.mhp=mhp and mhp:getOption('DisableMod')
 if b.mhp then b.mhpValue=b.mhp:getValue() end
 if video.dashboard then b.scale=require('YourDash/DashboardCore').GetScaleKey() end
 return b
end
local function restoreNonPositionBaseline(p)
 assert(drained() and not p:getVehicle(),'native requests/actions remain at restoration')
 p:setDir(baseline.dir)
 p:setForwardDirection(baseline.forwardX,baseline.forwardY)
 local equipmentChanged=p:getPrimaryHandItem()~=baseline.primary or p:getSecondaryHandItem()~=baseline.secondary
 p:setPrimaryHandItem(baseline.primary);p:setSecondaryHandItem(baseline.secondary)
 if isClient() and equipmentChanged then p:updateHandEquips() end
 p:setGodMod(baseline.god);p:setGhostMode(baseline.ghost);p:setAutoDrink(baseline.auto)
 local opts=PZAPI.ModOptions:getOptions('PZSurvivorToolkit')
 for key,value in pairs(baseline.options) do opts:getOption(key):setValue(value) end
 PZSurvivorToolkit.VehicleLighting.refreshBeams();PZSurvivorToolkit.VehicleLighting.configureReverse()
 for key,value in pairs(baseline.nep) do NepHBO7.options[key]:setValue(value) end
 for index,state in pairs(baseline.climate) do local value=getClimateManager():getClimateFloat(index);value:setAdminValue(state.value);value:setEnableAdmin(state.enabled) end
 getGameTime():setTimeOfDay(baseline.time)
 if ISUIHandler.allUIVisible~=baseline.ui then ISUIHandler.toggleUI() end
 for _,entry in ipairs(baseline.panes) do entry.pane:setVisible(entry.visible) end
 if baseline.guide then assert(SurvivalGuide.instance==baseline.guide,'survival guide replaced');baseline.guide:setVisible(baseline.guideVisible) end
 if baseline.mhp then baseline.mhp:setValue(baseline.mhpValue);if TwisTonFire_MHP_RefreshModOptions then TwisTonFire_MHP_RefreshModOptions() end end
 if baseline.scale then require('YourDash/DashboardCore').SetTextureSizeIndex(assert(({['0.75x']=1,['1x']=2,['1.4x']=3,['2x']=4})[baseline.scale])) end
 lightsFixtureRestore()
 assert(p:isGodMod()==baseline.god and p:isGhostMode()==baseline.ghost and p:getAutoDrink()==baseline.auto,'actor flags restoration failed')
 assert(p:getPrimaryHandItem()==baseline.primary and p:getSecondaryHandItem()==baseline.secondary,'equipment restoration failed')
 assert(ISUIHandler.allUIVisible==baseline.ui,'UI visibility restoration failed')
 for key,value in pairs(baseline.options) do assert(opts:getOption(key):getValue()==value,'Toolkit option restoration failed '..key) end
 for key,value in pairs(baseline.nep) do assert(NepHBO7.options[key]:getValue()==value,'high-beam option restoration failed '..key) end
 for index,state in pairs(baseline.climate) do local value=getClimateManager():getClimateFloat(index)
  assert(value:isEnableAdmin()==state.enabled and math.abs(value:getAdminValue()-state.value)<.0001,'climate override restoration failed')
 end
end
local function settled(state,p,stage)
 local now=clock()
 local idle=drained() and not p:getVehicle() and lightsFixtureMotionIdle()
 local ready=F.observePositionSettlement(state,p,now,idle)
 if state.logs<12 and (not state.loggedAt or now-state.loggedAt>=500) then
  log('POSITION_SETTLING stage='..stage..' generation='..ownedCount..' '..F.settlementText(state,now)..' '..lightsFixtureMotionProbe())
  state.logs=state.logs+1;state.loggedAt=now
 end
 return ready
end
local function powerRequest(dash,mode)
 local family=dash.__YourDashFamily
 if not isClient() or not ((video.push and family=='sport') or (video.rocker and family=='heavy')) then return end
 request=request+1
 local args={family=family,mode=mode,on=mode~='off',id=vehicle:getId(),generation=ownedCount,request=request}
 pendingAcks[request]=args
 log('POWER_REQUEST family='..family..' mode='..mode..' on='..tostring(args.on)..' id='..args.id..' generation='..ownedCount..' request='..request)
 sendClientCommand('VehicleLightsTest','power',args)
end
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
 powerRequest(dash,expected)
 if video.push and dash.__YourDashFamily=='sport' then
  local control=assert(dash.lightsTex)
  assert(control.texture==dash.__light_knob,'sport button must retain its original artwork')
  assert(control.width==dash.__light_knob:getWidthOrig() and control.height==dash.__light_knob:getHeightOrig(),'sport button bounds changed')
  log('PUSH_VIEW '..name..' pressed='..tostring(control.__pressed)
   ..' button='..math.floor(control:getAbsoluteX())..','..math.floor(control:getAbsoluteY())..','..math.ceil(control.width)..','..math.ceil(control.height))
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
local function pushDown()
 local dash=assert(getPlayerVehicleDashboard(0))
 assert(dash.__YourDashFamily=='sport','push fixture requires sport')
 local control=assert(dash.lightsTex)
 assert(control.onclick==control.__toolkitBeamPushClick,'push click not bound')
 local before=PZSurvivorToolkit.VehicleLightDashboard.switchMode(dash)
 control:onMouseDown(control.width*.5,control.height*.5)
 assert(control.__pressed,'native press effect not active')
 assert(PZSurvivorToolkit.VehicleLightDashboard.switchMode(dash)==before,'button changes mode before release')
 return control
end
local function pushUp(control,expected)
 local dash=assert(getPlayerVehicleDashboard(0))
 local before=PZSurvivorToolkit.VehicleLightDashboard.switchMode(dash)
 control:onMouseUp(control.width*.5,control.height*.5)
 assert(not control.__pressed,'native press effect did not release')
 assert(PZSurvivorToolkit.VehicleLightDashboard.switchMode(dash)==expected,'wrong push-button result')
 log('PUSH_CLICK '..before..' '..expected)
end
local function pushClick(expected) pushUp(pushDown(),expected) end
local function headlights(value)
 vehicle:setHeadlightsOn(value)
 if isClient() then sendClientCommand(getPlayer(),'vehicle','setHeadlightsOn',{vehicle=vehicle:getId(),on=value}) end
end
Events.OnServerCommand.Add(function(module,command,args)
 if module=='VehicleLightsTest' and command=='vehicle' then assert(args.generation==1,'invalid initial vehicle generation');vehicleId=args.id end
 if module=='VehicleLightsTest' and command=='replacement' then
  assert(not replacement and args.old==cleanupId and args.generation==ownedCount+1,'unexpected replacement acknowledgement');replacement=args
 end
 if module=='VehicleLightsTest' and command=='removed' then
  assert(not removed and args.id==cleanupId and args.generation==ownedCount,'unexpected removal acknowledgement');removed=args.id
 end
 if module=='VehicleLightsTest' and command=='baselineRestored' then
  assert(not baselineAck and phase==41 and args.generation==ownedCount,'unexpected baseline acknowledgement')
  assert(args.primaryID==(baseline.primary and baseline.primary:getID() or -1)
   and args.secondaryID==(baseline.secondary and baseline.secondary:getID() or -1),'authority equipment differs')
  assert(type(args.stableMs)=='number' and args.stableMs>=F.settleMilliseconds and type(args.samples)=='number' and args.samples>=F.settleSamples,
   'authority stationary observation missing')
  assert(type(args.x)=='number' and type(args.y)=='number' and math.abs(args.x-baseline.x)<.01 and math.abs(args.y-baseline.y)<.01 and args.z==baseline.z,
   'authority stationary position differs')
  baselineAck=true
  afterSettlement=F.newPositionSettlement(baseline)
  log('BASELINE_RESTORED generation='..args.generation..' primaryID='..args.primaryID..' secondaryID='..args.secondaryID..' position=true')
 end
 if module=='VehicleLightsTest' and command=='power' then
  local expected=assert(pendingAcks[args.request],'duplicate/late server power acknowledgement')
  for _,key in ipairs({'family','mode','on','id','generation','request'}) do assert(args[key]==expected[key],'server power acknowledgement mismatch '..key) end
  assert(args.request==request-(function()local n=0;for _ in pairs(pendingAcks)do n=n+1 end;return n end)()+1,'server power acknowledgement order differs')
  pendingAcks[args.request]=nil
  log('POWER_ACK family='..args.family..' mode='..args.mode..' on='..tostring(args.on)..' id='..args.id..' generation='..args.generation..' request='..args.request)
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
 if not baseline then
  if not initialSettlement then initialSettlement=F.newPositionSettlement(nil);initialSince=clock() end
  if not settled(initialSettlement,p,'initial') then
   assert(clock()-initialSince<15000,'initial native actor did not settle '..F.settlementText(initialSettlement,clock())..' '..lightsFixtureMotionProbe());return
  end
  baseline=captureBaseline(p)
  log('POSITION_SETTLED stage=initial generation=0 '..F.settlementText(initialSettlement,clock()))
 end
 if phase<40 then climate();hideUI() end
 if phase==0 then
  if clock()-since<12000 then return end
  p:setGodMod(true);p:setGhostMode(true);p:setAutoDrink(false)
  assert(not p:hasTrait(CharacterTrait.NIGHT_VISION),'Fixture must not have night vision')
  local x,y,dir=F.position(p);origin={x=x,y=y,dir=dir}
  if isClient() then sendClientCommand('VehicleLightsTest','prepare',origin) else vehicle=F.prepare(p,x,y,dir,video.push and 'Base.SportsCar' or nil) end
  p:teleportTo(x+2,y+2,0)
  phase=1;since=clock()
 elseif phase==1 then
  if isClient() then vehicle=vehicleId and getVehicleById(vehicleId) end
  if not vehicle or clock()-since<2000 then return end
  assert(vehicle:getSquare(),'spawned vehicle is not in world')
  owned()
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
  capture('off');if video.push then pushClick('low') elseif video.rotary then rotaryClick('low') elseif video.rocker and isClient() then rockerClick('low',true) else headlights(true);NepHBO7.deactivateHighBeams(vehicle) end;label='original_low';phase=20;since=clock()
 elseif phase==20 and clock()-since>3000 then
  capture('original_low');if video.push then pushClick('high') elseif video.rotary then rotaryClick('high') elseif video.rocker and isClient() then rockerClick('high',true) else NepHBO7.toggleHighBeam(vehicle) end;label='original_high';phase=21;since=clock()
 elseif phase==21 and clock()-since>3000 then
  capture('original_high')
  if video.dashboardCompare then assert(PZSurvivorToolkit.VehicleLightDashboard.installDeferred);PZSurvivorToolkit.VehicleLightDashboard.installDeferred() end
  PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('VehicleBeamShape'):setValue(true)
  if video.push then pushClick('off');label='push_off';phase=22
  elseif video.rotary then rotaryClick('off');label='rotary_off';phase=22
  elseif video.rocker and isClient() then rockerClick('low',false);label='heavy_return_low';phase=23
  else NepHBO7.deactivateHighBeams(vehicle);label='low';phase=4 end;since=clock()
 elseif phase==23 and clock()-since>2500 then
  dashboardCapture('heavy_return_low');rockerClick('off',false);label='heavy_off';phase=24;since=clock()
 elseif phase==24 and clock()-since>2500 then
  dashboardCapture('heavy_off');headlights(true);NepHBO7.deactivateHighBeams(vehicle);label='low';phase=4;since=clock()
 elseif phase==22 and clock()-since>2200 then
  if video.push then dashboardCapture('push_off');pushClick('low') else dashboardCapture('rotary_off');rotaryClick('low') end
  label='low';phase=4;since=clock()
 elseif phase==4 and clock()-since>3000 then
  capture('low');if video.push then pushClick('high') elseif video.rotary then rotaryClick('high') else NepHBO7.toggleHighBeam(vehicle) end;label='high';phase=5;since=clock()
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
   if video.rotary or video.push then
    require('YourDash/DashboardCore').SetTextureSizeIndex(1)
    phase=32;rotaryScale=1;rotaryStep=0;label=(video.push and 'sport' or 'standard')..'_scale_0.75x_off';since=clock()
   elseif video.origins then
    headlights(true);NepHBO7.deactivateHighBeams(vehicle);lightsFixtureCamera(1.2)
    originDebug=true;label='standard_geometry';phase=31;since=clock()
   else phase=30;variantStep=0 end
  elseif video.dashboard and video.push and video.rocker then phase=30;variantStep=0
  else assert(toolkitVideoStop());stopSince=clock();phase=11 end
 elseif phase==32 and clock()-since>1800 then
  local scales={'0.75x','1x','1.4x','2x'}
  local mode=({'off','low','high'})[rotaryStep+1]
  dashboardCapture((video.push and 'sport' or 'standard')..'_scale_'..scales[rotaryScale]..'_'..mode)
  if video.push then
   pushHeld=pushDown();phase=33;since=clock();return
  end
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
 elseif phase==33 and clock()-since>650 then
  local scales={'0.75x','1x','1.4x','2x'}
  local modes={'off','low','high'}
  dashboardCapture('sport_scale_'..scales[rotaryScale]..'_pressed_'..modes[rotaryStep+1])
  pushUp(pushHeld,modes[(rotaryStep+1)%3+1]);pushHeld=nil
  phase=32
  if rotaryStep<2 then rotaryStep=rotaryStep+1
  else
   rotaryStep=0;rotaryScale=rotaryScale+1
   if rotaryScale>4 then
    require('YourDash/DashboardCore').SetTextureSizeIndex(2);phase=30;variantStep=0
   else require('YourDash/DashboardCore').SetTextureSizeIndex(rotaryScale) end
  end
  if phase==32 then label='sport_scale_'..scales[rotaryScale]..'_'..modes[rotaryStep+1] end
  since=clock()
 elseif phase==31 and clock()-since>2500 then
  dashboardCapture('standard_geometry');headlights(false);originDebug=false;phase=30;variantStep=0
 elseif phase==30 then
  local spec=variants[variantIndex]
  if not spec then assert(toolkitVideoStop());stopSince=clock();phase=11;return end
  if variantStep==0 then
   if not drained() then assert(clock()-since<15000,'native queue/power acknowledgements did not drain');return end
   headlights(false);vehicle:exit(p);triggerEvent('OnExitVehicle',p)
   local x,y=origin.x,origin.y+(variantIndex-1)*10
   p:teleportTo(x+2,y+2,0)
   cleanupId=vehicle:getId()
   if isClient() then
    sendClientCommand('VehicleLightsTest','replace',{id=cleanupId,generation=ownedCount,x=x,y=y,dir=origin.dir,script=spec.script})
    variantSince=clock();variantStep=15;return
   end
   F.remove(vehicle);cleaned()
   vehicle=F.prepare(p,x,y,origin.dir,spec.script);owned()
   variantStep=16
  elseif variantStep==15 then
   if not removed or getVehicleById(cleanupId) then assert(clock()-variantSince<15000,'owned Host removal did not replicate');return end
   cleaned()
   sendClientCommand('VehicleLightsTest','removeObserved',{id=cleanupId,generation=ownedCount})
   removed=nil;variantStep=17;variantSince=clock()
  elseif variantStep==17 then
   if not replacement or not getVehicleById(replacement.id) then assert(clock()-variantSince<15000,'owned Host replacement did not replicate');return end
   vehicle=assert(getVehicleById(replacement.id));owned();replacement=nil
   variantStep=16
  elseif variantStep==16 then
   vehicle:enter(0,p);vehicle:setCharacterPosition(p,0,'inside');vehicle:transmitCharacterPosition(0,'inside')
   triggerEvent('OnEnterVehicle',p)
   getPlayerVehicleDashboard(0):setVehicle(vehicle)
   require('YourDash/DashboardCore').SetTextureSizeIndex(2)
   if video.origins then lightsFixtureCamera(1.2) end
   if isClient() then sendClientCommand('VehicleLightsTest','start',{}) else vehicle:tryStartEngine(true) end
   variantSince=clock();variantStep=1
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
  assert(s.state=='completed',s.error)
  if not drained() then assert(clock()-stopSince<20000,'final native queue/power acknowledgements did not drain');return end
  log('VIDEO_RESULT '..'{"state":"'..s.state..'","file":"'..s.file..'","frames":'..s.frames..',"seconds":'..s.seconds..',"captured":'..s.captured..',"dropped":'..s.dropped..',"width":'..s.width..',"height":'..s.height..',"error":"'..s.error..'"}')
  lightsFixtureInput(0);vehicle:exit(p);triggerEvent('OnExitVehicle',p);cleanupId=vehicle:getId()
  if isClient() then sendClientCommand('VehicleLightsTest','remove',{id=cleanupId,generation=ownedCount}) else F.remove(vehicle);removed=cleanupId end
  phase=40;since=clock()
 elseif phase==40 then
  if not removed or isClient() and getVehicleById(cleanupId) then assert(clock()-since<15000,'owned vehicle removal did not replicate');return end
  cleaned();restoreNonPositionBaseline(p)
  log('BASELINE_STATE_RESTORED generation='..ownedCount..' settings=true orientation=true equipment=true')
  beforeSettlement=F.newPositionSettlement(nil);phase=42;since=clock()
 elseif phase==42 then
  if not settled(beforeSettlement,p,'before') then
   assert(clock()-since<15000,'native exit motion did not settle '..F.settlementText(beforeSettlement,clock())..' '..lightsFixtureMotionProbe());return
  end
  log('POSITION_SETTLED stage=before generation='..ownedCount..' '..F.settlementText(beforeSettlement,clock()))
  local before,after=F.restorePosition(p,baseline)
  log('POSITION_RESTORE generation='..ownedCount..' before='..before..' after='..after)
  afterSettlement=F.newPositionSettlement(baseline)
  phase=41;since=clock()
  if isClient() then sendClientCommand('VehicleLightsTest','restoreBaseline',{generation=ownedCount,
   x=baseline.x,y=baseline.y,z=baseline.z,
   primaryID=baseline.primary and baseline.primary:getID() or -1,secondaryID=baseline.secondary and baseline.secondary:getID() or -1})
  else baselineAck=true end
 elseif phase==41 then
  local ready=settled(afterSettlement,p,'after')
  if not baselineAck or not ready then
   assert(clock()-since<15000,'baseline restoration did not settle authority='..tostring(baselineAck)..' '..F.positionText(p,baseline)..' '..F.settlementText(afterSettlement,clock())..' '..lightsFixtureMotionProbe());return
  end
  assert(drained() and not p:getVehicle(),'actions/vehicle reappeared after restoration')
  assert(p:getPrimaryHandItem()==baseline.primary and p:getSecondaryHandItem()==baseline.secondary,'equipment changed after restoration')
  assert(math.abs(p:getX()-baseline.x)<.01 and math.abs(p:getY()-baseline.y)<.01 and p:getZ()==baseline.z,
   'position changed after restoration '..F.positionText(p,baseline))
  log('POSITION_SETTLED stage=after generation='..ownedCount..' '..F.settlementText(afterSettlement,clock()))
  log('RESTORED queueDrained=true settings=true');done=true;log('COMPLETE road')
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
