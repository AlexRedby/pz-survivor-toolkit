require 'TimedActions/WalkToTimedAction'
require 'TimedActions/ISTimedActionQueue'
require 'ISUI/ISInventoryPaneContextMenu'
local config=require 'QueueTestSelection'
assert(config.disposable and config.world=='QueueBasementHall' and config.kind=='sp','Disposable SP fixture required')
local entered,starting,started,done=false,false,false,false
local phase,since,requested=0,0,false
local lastTerrain,lastSearch,walkAction,destination
local lastPathLog=0
local videoSince,videoStopped
local lantern
local function log(text) print('[BASEMENT_HALL] '..text) end
local function describe(square)
 if not square then return 'loaded=false' end
 local sprites={}
 for i=0,square:getObjects():size()-1 do
  local sprite=square:getObjects():get(i):getSprite()
  sprites[#sprites+1]=sprite and tostring(sprite:getName()) or 'no-sprite'
 end
 return 'loaded=true floor='..tostring(square:getFloor()~=nil)..' solidFloor='..tostring(square:TreatAsSolidFloor())
  ..' stairs='..tostring(square:HasStairs())..' stairsBelow='..tostring(square:HasStairsBelow())
  ..' free='..tostring(square:isFree(false))..' objects='..square:getObjects():size()..' sprites='..table.concat(sprites,',')
end
local function walk(x,y,z)
 local square=getCell():getGridSquare(x,y,z)
 local terrain=x..','..y..','..z..' '..describe(square)
 if terrain~=lastTerrain then log('TARGET '..terrain);lastTerrain=terrain end
 if not square or not (square:TreatAsSolidFloor() or square:HasStairs() or square:HasStairsBelow()) then return end
 walkAction=ISWalkToTimedAction:new(getPlayer(),square)
 ISTimedActionQueue.add(walkAction)
 requested=true;since=getTimestampMs();lastPathLog=0
end
local function selectBasementTarget()
 local building
 local anchors={}
 for y=9485,9487 do
  local square=getCell():getGridSquare(10707,y,-1)
  anchors[#anchors+1]=y..':'..describe(square)
  if square and square:HasStairs() and square:getRoomDef() then
   building=square:getRoomDef():getBuilding()
   if building then break end
  end
 end
 local search=table.concat(anchors,';')
 if search~=lastSearch then log('BASEMENT_SEARCH '..search);lastSearch=search end
 if not building then return end
 local best,dist
 for x=building:getX(),building:getX2()-1 do for y=building:getY(),building:getY2()-1 do
  local square=getCell():getGridSquare(x,y,-1)
  local room=square and square:getRoomDef()
  if room and room:getBuilding()==building and square:TreatAsSolidFloor() and not square:HasStairs() and square:isFree(false) then
   local d=(x-10707)^2+(y-9488)^2
   if not dist or d<dist then best={x=x,y=y,z=-1};dist=d end
  end
 end end
 if best then log('DESTINATION '..best.x..','..best.y..',-1 owner='..building:getIDString()) end
 return best
end
local function at(x,y,z)
 local p=getPlayer()
 return math.floor(p:getX())==x and math.floor(p:getY())==y and math.floor(p:getZ())==z
end
local function capture(name)
 local player=getPlayer()
 local held=player:getPrimaryHandItem()==lantern or player:getSecondaryHandItem()==lantern
 log('LIGHT_ACTUAL phase='..name..' held='..tostring(held)..' active='..tostring(lantern and lantern:isActivated())
  ..' charge='..tostring(lantern and lantern:getCurrentUsesFloat()))
 assert(lantern and lantern:getFullType()=='Base.Lantern_Propane' and held and lantern:isActivated()
  and lantern:getCurrentUsesFloat()>0 and lantern:getCurrentUsesFloat()<=1,'Native held lantern is missing, inactive or depleted')
 assert(lantern:getLightDistance()==15 and lantern:getLightStrength()==2 and not lantern:isTorchCone(),'Unexpected native lantern light properties')
 log('LIGHT phase='..name..' held=true active=true charge='..lantern:getCurrentUsesFloat()..' distance=15 strength=2 cone=false')
 log('PROBE '..basementHallProbe(name,config.cases[1]=='native-control'))
 log('VIDEO_PHASE phase='..name..' elapsedMs='..(getTimestampMs()-videoSince))
 getCore():TakeFullScreenshot('basement-hall-'..name..'.png')
end
Events.OnMainMenuEnter.Add(function() entered=true end)
Events.OnPreUIDraw.Add(function()
 if started and isIngameState() and isGamePaused() then setGameSpeed(1) end
 if not entered or starting or isIngameState() then return end
 starting=true;getCore():setOptionPauseOnFocusloss(false)
 if config.cases[1]=='reload' then
  assert(config.options.world_template,'Reload requires a sealed template')
  MainScreen.continueLatestSave('Sandbox',config.world)
  return
 end
 getWorld():setGameMode('Sandbox');getWorld():setWorld(config.world);getWorld():setMap('Muldraugh, KY')
 MainScreen.instance:setDefaultSandboxVars()
 getSandboxOptions():getOptionByName('Zombies'):setValue(6);getSandboxOptions():toLua()
 local current,active=ActiveMods.getById('currentGame'),getActivatedMods()
 current:getMods():clear();for i=0,active:size()-1 do current:getMods():add(active:get(i)) end
 MainScreen.instance.createWorld=true
 MapSpawnSelect.instance.selectedRegion={points={unemployed={{posX=10707,posY=9484,posZ=0}}}}
 MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'})
 MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
end)
Events.OnGameStart.Add(function() started=true;since=getTimestampMs() end)
Events.OnTick.Add(function()
 if not started or done or not isIngameState() then return end
 local ok,problem=pcall(function()
  local player=getPlayer()
  if not player or not player:getSquare() then return end
  assert(not isClient() and not isServer() and getWorld():getWorld()==config.world,'Unexpected world or network mode')
  assert(not player:isDead(),'Fixture player died')
  assert(getTimestampMs()-since<45000,'Native traversal timed out at phase '..phase)
  if requested and getTimestampMs()-lastPathLog>5000 then
   local queue=ISTimedActionQueue.getTimedActionQueue(player).queue
   log('PATH phase='..phase..' actor='..player:getX()..','..player:getY()..','..player:getZ()
    ..' result='..tostring(walkAction and walkAction.result)..' queue='..#queue..' head='..tostring(queue[1] and queue[1].Type))
   lastPathLog=getTimestampMs()
  end
  assert(not requested or not walkAction or walkAction.result~=BehaviorResult.Failed,'Native pathfinder returned Failed at phase '..phase)
  if phase==0 and getTimestampMs()-since>2000 then
   player:setGodMod(true)
   local inventory=player:getInventory()
   lantern=inventory:getFirstType('Base.Lantern_Propane') or inventory:AddItem('Base.Lantern_Propane')
   assert(lantern,'Native propane lantern could not be created')
   lantern:setCurrentUses(lantern:getMaxUses())
   player:setPrimaryHandItem(lantern)
   if not lantern:isActivated() then ISInventoryPaneContextMenu.onActivateItem(lantern,player:getPlayerNum()) end
   if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
   log('ORIGIN '..player:getX()..','..player:getY()..','..player:getZ())
   log('NEIGHBOR 10707,9483,0 '..describe(getCell():getGridSquare(10707,9483,0)))
   log('NEIGHBOR 10707,9484,0 '..describe(getCell():getGridSquare(10707,9484,0)))
   assert(toolkitVideoStatus().state=='idle','Recorder is already in use')
   assert(toolkitVideoStart(config.video.directory,config.video.ffmpeg),'Presented video did not start')
   videoSince=getTimestampMs()
   log('READY');phase=1;requested=false
  elseif phase==1 then
   if at(10707,9484,0) then phase=2;since=getTimestampMs() end
  elseif phase==2 and getTimestampMs()-since>1500 then
   capture('surface');log('SURFACE');phase=3;requested=false;walkAction=nil
  elseif phase==3 then
   destination=destination or selectBasementTarget()
   if destination then
    if not requested then walk(destination.x,destination.y,destination.z) end
    if at(destination.x,destination.y,destination.z) then phase=4;since=getTimestampMs() end
   end
  elseif phase==4 and getTimestampMs()-since>1500 then
   capture('basement');log('BASEMENT');phase=5;requested=false;walkAction=nil
  elseif phase==5 then
   if not requested then walk(10707,9484,0) end
   if at(10707,9484,0) then phase=6;since=getTimestampMs() end
  elseif phase==6 and getTimestampMs()-since>1500 then
   capture('returned');log('RETURNED')
   assert(toolkitVideoStop(),'Presented video did not stop')
   videoStopped=getTimestampMs()-videoSince;log('VIDEO_STOP elapsedMs='..videoStopped)
   basementHallSave();log('SAVED')
   phase=7;since=getTimestampMs()
  elseif phase==7 then
   local status=toolkitVideoStatus()
   if status.state=='completed' or status.state=='failed' then
    log('VIDEO_RESULT state='..status.state..' file='..status.file..' frames='..status.frames..' seconds='..status.seconds
     ..' captured='..status.captured..' dropped='..status.dropped..' width='..status.width..' height='..status.height..' error='..status.error)
    assert(status.state=='completed',status.error)
    done=true;log('COMPLETE case='..config.cases[1])
   end
  end
 end)
 if not ok then
  done=true
  local kept,saveProblem=pcall(function()
   if videoSince and not videoStopped then toolkitVideoStop() end
   local p=getPlayer()
   if p then log('FAILURE_POSITION '..p:getX()..','..p:getY()..','..p:getZ()) end
   getCore():TakeFullScreenshot('basement-hall-failure.png');basementHallSave()
  end)
  if not kept then log('FAILURE_CAPTURE '..tostring(saveProblem)) end
  log('FAIL '..tostring(problem))
 end
end)
