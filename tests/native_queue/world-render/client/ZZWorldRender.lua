require 'TimedActions/WalkToTimedAction'
require 'TimedActions/ISTimedActionQueue'
local config=require 'QueueTestSelection'
if config.suite~='world-render'then return end
local F=require 'WorldRenderFixture'
local started,done,go=false,false,false
local phase='prepare';local since,nextAt,beginAt=0,0,0
local packet,role,torch,torchAck,switchAck,scene,off,lit,torchDelta,origin,walkTarget,walkAction,switchOld,corridor
local sceneSteps,sceneIndex={},1
local pendingCutaway=0
local resourceMode=config.options and config.options.world_render_resources
local decalBuffer,decalPending,decalDraws
Events.RenderOpaqueObjectsInWorld.Add(function(playerIndex)
 if not resourceMode or done or not started or phase~='decal_loading'and phase~='decal_ready' then return end
 local ok,err=pcall(function()
  local player=getSpecificPlayer(playerIndex)
  if player~=getPlayer() then return end
  if not decalBuffer then
   assert(ISnow and ISnow.Decals,'ImmersiveSnow decal renderer unavailable')
   local D=ISnow.Decals
   assert(not D.toViewpoint,'Resource scenario requires the native mod render path')
   worldRenderDecalPending(player)
   local set=D.newSet(function(level)return ISnow.bloodTrackFile(1,16,level)end,ISnow.TRACK_BLOOD_LEVELS)
   decalBuffer=D.newBuffer(function()return 6 end,nil,.4,'strength',true)
   local ax,ay,az=D.anchor(ISnow.TRACK_SIZE,ISnow.TRACK_REACH)
   for i=1,6 do
    local x,y=player:getX()+corridor.dx*(1+i*.4),player:getY()+corridor.dy*(1+i*.4)
    decalBuffer:push({x=x+ax,y=y+ay,z=math.floor(player:getZ()),rz=math.floor(player:getZ())+az,
      sx=math.floor(x),sy=math.floor(y),set=set,strength=1})
   end
   decalBuffer:render(playerIndex,10)
   assert(decalBuffer.drawn==6,'Actual mod renderer did not attempt all six pending decals')
   worldRenderDecalPendingCheck(player);decalPending=true
   F.emit('RESOURCE',{role=role,stage='pending',draws=decalBuffer.drawn,dimensionsUnchanged=true})
  else
   decalBuffer:render(playerIndex,10);decalDraws=decalBuffer.drawn
  end
 end)
 if not ok then done=true;F.emit('FAIL',{role=role or 'unknown',phase='decal-render',error=tostring(err)})end
end)
-- Core.StartFrameUI/UIManager draws after IngameState's world render. Observe only requested settled scenes.
Events.OnPreUIDraw.Add(function()
 if pendingCutaway<=0 or done or not started or not isIngameState()then return end
 pendingCutaway=pendingCutaway-1
 local ok,err=pcall(function()
  assert(worldRenderCutawayObserve,'Native cutaway observer unavailable')
  worldRenderCutawayObserve(getPlayer())
 end)
 if not ok then done=true;F.emit('FAIL',{role=role or 'unknown',phase='cutaway-observer',error=tostring(err)})end
end)
local function now()return getTimestampMs()end
local function wait(name,ms)phase=name;nextAt=now()+(ms or 1500);since=now()end
local function shot(name)
 local player=getPlayer()
 local ui=getPlayerData(player:getPlayerNum())
 if ui and ui.characterInfo then ui.characterInfo:setVisible(false)end
 local samples=F.probe(player)
 assert(#samples>0,'No cached native light at '..name)
 getCore():TakeFullScreenshot('world-render-'..name..'.png')
 F.emit('PHASE',{name=name,role=role,x=player:getX(),y=player:getY(),z=player:getZ(),samples=samples,
  torch=torch:isActivated(),emitting=torch:isEmittingLight(),strength=torch:getLightStrength(),distance=torch:getLightDistance(),
  cone=torch:isTorchCone(),torchDot=torch:getTorchDot(),lookX=player:getLookDirectionX(),lookY=player:getLookDirectionY(),
  forwardX=player:getForwardDirectionX(),forwardY=player:getForwardDirectionY(),
  charge=torch:getCurrentUsesFloat(),time=getGameTime():getTimeOfDay()})
 return samples
end
local function light(active)
 torchAck=nil
 if isClient()then sendClientCommand(F.module,'Torch',{active=active})else torchAck=F.torch(getPlayer(),torch,active)end
end
local function switch(active)
 switchAck=nil
 if isClient()then sendClientCommand(F.module,'Switch',{target=scene.switch,active=active})else
  local obj=assert(F.object(scene.switch,'IsoLightSwitch'));obj:setActive(active);switchAck=obj:isActivated()
 end
end
local function move(target)
 assert(F.free(getCell():getGridSquare(target.x,target.y,target.z)),'Scene destination unavailable')
 getPlayer():teleportTo(target.x+.5,target.y+.5,target.z)
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~=F.module then return end
 if command=='Prepared'then packet=args;role=args.role elseif command=='Start'then go=true
 elseif command=='Torch'then torchAck=args.active elseif command=='Switch'then switchAck=args.active end
end)
Events.OnGameStart.Add(function()
 started=true;beginAt=now();since=beginAt
 if config.kind=='sp'then role='client1' end
 getPlayer():setGodMod(true);getPlayer():setGhostMode(true)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
end)
local function tick()
 local player=getPlayer()
 if phase=='prepare'then
  if not player:getSquare()then return end
  if isClient()then sendClientCommand(F.module,'Prepare',{})else torch=F.prepare(player);go=true end
  wait('resolve',100)
 elseif phase=='resolve'then
  if isClient()then
   if not packet then return end
   torch=player:getInventory():getItemById(packet.id)
   if not torch or player:getPrimaryHandItem()~=torch then return end
   sendClientCommand(F.module,'Ready',{})
  end
  wait('start',500)
 elseif phase=='start'then
  if not go then return end
  assert(player:getPrimaryHandItem()==torch,'Native held torch absent')
  corridor=assert(F.corridor(player),'No unblocked native torch corridor within six tiles')
  F.emit('CORRIDOR',{role=role,dx=corridor.dx,dy=corridor.dy,length=corridor.length})
  player:faceLocationF(player:getX()+corridor.dx*4,player:getY()+corridor.dy*4)
  origin={x=math.floor(player:getX()),y=math.floor(player:getY()),z=math.floor(player:getZ())}
  scene=F.discover(player)
  if resourceMode then worldRenderResourcesBegin(player) end
  wait('arrival',2500)
 elseif phase=='arrival'then
  -- TorchInfo reads the animation look vector, not only the discrete IsoDirections field.
  if player:getLookDirectionX()*corridor.dx+player:getLookDirectionY()*corridor.dy<.99 then return end
  shot('first_arrival');light(false);wait('off')
 elseif phase=='off'then
  if torchAck~=false or torch:isActivated()then return end
  off=shot('torch_off');light(true);wait('on',2500)
 elseif phase=='on'then
  if torchAck~=true or not torch:isActivated()then return end
  assert(torch:isEmittingLight(),'Activated held Torch is not emitting light')
  assert(player:getLookDirectionX()*corridor.dx+player:getLookDirectionY()*corridor.dy>.99,'Actual torch look vector left the corridor')
  lit=shot('torch_on');local delta=F.delta(lit,off)
  assert(delta>.02,'Held native torch produced no native RGB/corner response: '..delta)
  torchDelta=delta
  light(false);wait('restored',2500)
 elseif phase=='restored'then
  if torchAck~=false or torch:isActivated()then return end
  local restored=shot('torch_restored');local returnDelta=F.delta(lit,restored)
  assert(returnDelta>.02,'Native torch off did not restore native RGB/corners: '..returnDelta)
  F.emit('CHECK',{name='torch-response',role=role,delta=torchDelta,returnDelta=returnDelta})
  for _,v in ipairs({{4,0},{-4,0},{0,4},{0,-4}})do
   local clear=true
   for i=1,4 do if not F.free(getCell():getGridSquare(origin.x+v[1]*i/4,origin.y+v[2]*i/4,origin.z))then clear=false end end
   if clear and not walkTarget then walkTarget={x=origin.x+v[1],y=origin.y+v[2],z=origin.z}end
  end
  assert(walkTarget,'No bounded native walking corridor at spawn')
  walkAction=ISWalkToTimedAction:new(player,getCell():getGridSquare(walkTarget.x,walkTarget.y,walkTarget.z))
  ISTimedActionQueue.add(walkAction);wait('walking',100)
 elseif phase=='walking'then
  assert(not walkAction.result or walkAction.result~=BehaviorResult.Failed,'Native walking failed')
  if math.abs(player:getX()-(walkTarget.x+.5))>1 or math.abs(player:getY()-(walkTarget.y+.5))>1
   or #ISTimedActionQueue.getTimedActionQueue(player).queue>0 then return end
  wait('walk_settled',1800)
 elseif phase=='walk_settled'then
  shot('walk_arrived');pendingCutaway=8
  local distance=math.sqrt((player:getX()-origin.x-.5)^2+(player:getY()-origin.y-.5)^2)
  assert(distance>=2,'Native walk did not move actor')
  F.emit('CHECK',{name='native-walk',role=role,distance=distance})
  if scene.window then
   sceneSteps[#sceneSteps+1]={name='window_outside',target=scene.window.outside}
   sceneSteps[#sceneSteps+1]={name='window_inside',target=scene.window.inside}
  else F.emit('LIMIT',{role=role,scope='window/cutaway',reason='No standable interior/exterior window pair within bounded discovery'})end
  if scene.tree then sceneSteps[#sceneSteps+1]={name='tree_edge',target=scene.tree}
  else F.emit('LIMIT',{role=role,scope='tree',reason='No natural tree with standable adjacent square within bounded discovery'})end
  if resourceMode then
   assert(scene.window,'Resource visual check requires a discovered interior floor')
   move(scene.window.inside)
   corridor=assert(F.corridor(player),'No clear interior decal corridor')
   player:faceLocationF(player:getX()+corridor.dx*4,player:getY()+corridor.dy*4)
   light(true);wait('decal_light',2500)
  else wait('scene',100)end
 elseif phase=='decal_light'then
  if torchAck~=true or not torch:isActivated() then return end
  shot('decal_control');wait('decal_loading',100)
 elseif phase=='decal_loading'then
  if not decalPending or not worldRenderDecalReady(player) then return end
  wait('decal_ready',1500)
 elseif phase=='decal_ready'then
  assert(decalDraws==6,'Actual ready decal render incomplete')
  shot('decal_ready');decalBuffer:clear();wait('decal_restored',1500)
 elseif phase=='decal_restored'then
  shot('decal_restored');worldRenderResourcesFinish(player)
  F.emit('RESOURCE',{role=role,stage='ready',draws=decalDraws,width=64,height=64,outlinePrograms=3,outlineIdentityStable=true})
  light(false);wait('decal_off',1500)
 elseif phase=='decal_off'then
  if torchAck~=false or torch:isActivated() then return end
  wait('scene',100)
 elseif phase=='scene'then
  local entry=sceneSteps[sceneIndex]
  if entry then move(entry.target);wait('scene_settled',2500)else wait('switch_prepare',100)end
 elseif phase=='scene_settled'then
  shot(sceneSteps[sceneIndex].name);pendingCutaway=8;sceneIndex=sceneIndex+1;wait('scene',100)
 elseif phase=='switch_prepare'then
  if role~='client1'or not scene.switch then
   F.emit('LIMIT',{role=role,scope='room-switch',reason=role~='client1'and 'Owner controls room switch; joining peer tests its own torch and native movement' or 'No powered native switch with bulb within bounded discovery'})
   wait('complete',100);return
  end
  local obj=assert(F.object(scene.switch,'IsoLightSwitch'));switchOld=obj:isActivated()
  local square=obj:getSquare();local target
  for _,v in ipairs({{0,0},{1,0},{-1,0},{0,1},{0,-1}})do
   local sq=getCell():getGridSquare(square:getX()+v[1],square:getY()+v[2],square:getZ())
   if F.free(sq)and sq:getRoom()==square:getRoom()and not target then target={x=sq:getX(),y=sq:getY(),z=sq:getZ()}end
  end
  if not target then F.emit('LIMIT',{role=role,scope='room-switch',reason='No adjacent standable room square'});wait('complete',100);return end
  move(target);switch(false);wait('switch_off',2500)
 elseif phase=='switch_off'then
  if switchAck~=false then return end
  shot('switch_off');switch(true);wait('switch_on',2500)
 elseif phase=='switch_on'then
  if switchAck~=true then return end
  shot('switch_on');F.emit('CHECK',{name='native-switch',role=role,active=true})
  switch(switchOld);wait('switch_restored',2500)
 elseif phase=='switch_restored'then
  if switchAck~=switchOld then return end
  shot('switch_restored');wait('complete',100)
 elseif phase=='complete'then
  if pendingCutaway>0 then return end
  assert(worldRenderCutawayReport,'Native cutaway report unavailable')
  print('[WORLD_RENDER] CUTAWAY '..worldRenderCutawayReport(player))
  F.emit('LIMIT',{role=role,scope='visual/high-speed',reason='Discrete screenshots need visual review; local walking/relocation does not exercise high-speed driving or distant chunk streaming'})
  F.emit('COMPLETE',{case='lighting',role=role});done=true
 end
end
Events.OnTick.Add(function()
 if not started or done or not isIngameState()or now()<nextAt then return end
 local ok,err=pcall(function()
  local joining=config.kind=='mp'and (phase=='prepare'or phase=='resolve'or phase=='start')
  -- The first Host player may be ready before the runner finishes admitting the second window.
  assert(now()-beginAt<(config.kind=='mp'and 300000 or 180000),'Fixture overall timeout')
  assert(now()-since<(joining and 180000 or 45000),'Fixture phase timeout '..phase)
  assert(not getPlayer():isDead(),'Fixture actor died')
  tick()
 end)
 if not ok then done=true;F.emit('FAIL',{role=role or 'unknown',phase=phase,error=tostring(err)})end
end)
