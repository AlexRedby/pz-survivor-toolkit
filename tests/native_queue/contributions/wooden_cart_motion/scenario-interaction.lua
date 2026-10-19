local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true,'CartMotionConfig.disposable must be true')
local function absolutePath(name)
 local value=config[name]
 assert(type(value)=='string' and value~='' and (value:sub(1,1)=='/' or value:match('^%a:[/\\]') or value:sub(1,2)=='\\\\'),'Absolute '..name..' required')
 return value
end
local videoRoot,ffmpeg=absolutePath('videoRoot'),absolutePath('ffmpeg')
assert(getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer(),'Disposable single-player CartTestArea save required')
local p=assert(getPlayer(),'Live actor required')
assert(not p:isDead() and CartTestArea and CartTestArea.ready,'Wait for BOOTSTRAP_READY')
assert(CartLabKey and CartLabHUD and cartLabDrive and cartLabGait and cartLabPoseHeading and toolkitVideoStart and toolkitVideoStatus and toolkitVideoStop,'CartLab/video bridge missing')
require 'SaucedCarts/TimedActions/ISCartPickupAction'
require 'TimedActions/ISUnequipAction'
require 'ISUI/ISInventoryPaneContextMenu'
require 'TimedActions/ISTimedActionQueue'
if WoodPrototypeTick then Events.OnTick.Remove(WoodPrototypeTick) end
cartLabDrive(0);cartLabGait(0);setGameSpeed(1)
p:clearWornItems();p:getHumanVisual():setHairModel('CrewCut');p:getHumanVisual():setBeardModel('')
for _,name in ipairs({'Base.Tshirt_DefaultTEXTURE_TINT','Base.Trousers_JeanBaggy','Base.Shoes_TrainerTINT'}) do
 local item=assert(p:getInventory():AddItem(name),name)
 p:setWornItem(item:getBodyLocation(),item)
end
p:resetModel()
CartTestArea.check(p)
local climate=getClimateManager()
for _,index in ipairs({ClimateManager.FLOAT_FOG_INTENSITY,ClimateManager.FLOAT_PRECIPITATION_INTENSITY,ClimateManager.FLOAT_CLOUD_INTENSITY}) do
 local value=climate:getClimateFloat(index);value:setEnableAdmin(true);value:setAdminValue(0)
end
local cases={
 {name='male-empty-yaw0',female=false,full=false,yaw=0,nearStance=true},
 {name='male-empty-yaw135',female=false,full=false,yaw=135},
 {name='female-full-yaw90',female=true,full=true,yaw=90},
 {name='male-full-yaw270',female=false,full=true,yaw=270},
}
if config.wheelCycle then cases={{name='wood-wheel-cycle',female=false,full=true,yaw=135}} end
if config.interruptions then
 cases={}
 local variants=config.interruptionMatrix and {{name='male-full-',female=false,full=true},{name='male-empty-',female=false,full=false},
  {name='female-full-',female=true,full=true},{name='female-empty-',female=true,full=false}} or {{name='',female=false,full=true}}
 for _,variant in ipairs(variants) do
  for _,phase in ipairs({{name='late',progress=.88},{name='contact',progress=.55},{name='early',progress=.15}}) do
   for _,action in ipairs({'drop','pickup'}) do
    for _,route in ipairs({'cancel','walk'}) do
     cases[#cases+1]={name=variant.name..action..'-'..phase.name..'-'..route,female=variant.female,full=variant.full,yaw=135,
      interrupt=action,threshold=phase.progress,route=route}
    end
   end
  end
 end
end
if config.rapidRepeats then
 cases={}
 for _,variant in ipairs({{name='male-empty',female=false,full=false},{name='male-full',female=false,full=true},
  {name='female-empty',female=true,full=false},{name='female-full',female=true,full=true}}) do
  for _,repeatKind in ipairs({'complete-chain','pickup-restart','drop-restart'}) do
   cases[#cases+1]={name=variant.name..'-'..repeatKind,female=variant.female,full=variant.full,yaw=135,repeatKind=repeatKind}
  end
 end
end
cases=CartLabSelectScenes(cases)
local phase,attempt,since,sampleSince=0,0,0,0
local mode,stage,item,initialCargo,initialCargoIDs,heldAt,droppedAt='settle','grounded'
local interrupted,cancelAt,cancelledAt,retryStage
local cycle,driveStage=1,0
local selectionWorld,selectionOn
local actionSerial,restartCount,cleanupAt=0,0,nil
local hotkeyAction,hotkeyStarted,hotkeyCode,hotkeyReleaseAt
local kind='SaucedWheelbarrow.WheelbarrowWood'
local function encode(record)
 local out={}
 for key,value in pairs(record) do
  local t=type(value)
  if t=='string' then value='"'..value:gsub('[%z\1-\31\\"]',function(char) return string.format('\\u%04x',string.byte(char)) end)..'"'
  elseif t=='number' then assert(value==value and math.abs(value)<math.huge,'Nonfinite interaction sample');value=tostring(value)
  else assert(t=='boolean','Unsupported interaction value');value=tostring(value) end
  out[#out+1]='"'..key..'":'..value
 end
 return '{'..table.concat(out,',')..'}'
end
local function cargo()
 local entries={};local contents=item:getInventory():getItems()
 for i=0,contents:size()-1 do
  local child=contents:get(i)
  entries[#entries+1]=tostring(child:getID())..':'..child:getFullType()..':'..tostring(child:getActualWeight())
 end
 table.sort(entries)
 return item:getInventory():getCapacityWeight(),table.concat(entries,'|'),contents:size()
end
local function inventoryCount()
 local count=0;local contents=p:getInventory():getItems()
 for i=0,contents:size()-1 do if contents:get(i):getID()==item:getID() then count=count+1 end end
 return count
end
local function worlds()
 local count,woodCount,found=0,0,nil
 -- The actor and owned cart stay within four tiles of this checked open pad center.
 for x=math.floor(CartTestArea.x)-6,math.floor(CartTestArea.x)+6 do
  for y=math.floor(CartTestArea.y)-6,math.floor(CartTestArea.y)+6 do
   local square=assert(getCell():getGridSquare(x,y,CartTestArea.z),'Interaction pad unloaded')
   local objects=square:getWorldObjects()
   for i=0,objects:size()-1 do
    local world=objects:get(i);local candidate=world:getItem()
    if candidate and candidate:getFullType()==kind then woodCount=woodCount+1 end
    if candidate and candidate:getID()==item:getID() then count=count+1;found=world end
   end
  end
 end
 return count,woodCount,found
end
local function handID(value) return value and value:getID() or -1 end
local function snapshot(now)
 local queue=ISTimedActionQueue.getTimedActionQueue(p)
 local action=queue.queue[1]
 local count,woodCount,world=worlds()
 local weight,ids,children=cargo()
 assert(math.abs(weight-initialCargo)<.001 and ids==initialCargoIDs,'Cargo changed during interaction')
 assert(CartTestArea.contains(p:getX(),p:getY(),p:getZ()) and math.abs(p:getX()-CartTestArea.x)<4 and math.abs(p:getY()-CartTestArea.y)<4,'Interaction left checked local pad')
 local status=toolkitWoodCartStatus and toolkitWoodCartStatus(p) or {}
 return {case=cases[phase].name,start=since,wall=now,elapsed=now-since,id=item:getID(),stage=stage,female=p:isFemale(),driveCommand=driveStage,
  cycle=cycle,driveStage=driveStage,actionSerial=actionSerial,restartCount=restartCount,heldID=handID(p:getPrimaryHandItem()),secondaryID=handID(p:getSecondaryHandItem()),
  worldID=world and world:getItem():getID() or -1,worldCount=count,woodWorldCount=woodCount,inventoryCount=inventoryCount(),
  actionType=action and action.Type or '',progress=action and action:getJobDelta() or 0,condition=item:getCondition(),
  nativeActions=p:getCharacterActions():size(),luaActions=#queue.queue,
  PerformingAction=p:getVariableString('PerformingAction') or '',
  IsPerformingAnAction=p:getVariableBoolean('IsPerformingAnAction'),
  ToolkitWoodCartAction=p:getVariableBoolean('ToolkitWoodCartAction'),
  ToolkitCartMotion=p:getVariableBoolean('ToolkitCartMotion'),worldAlpha=item:getWorldAlpha(),worldObjectAlpha=world and world:getAlpha(0) or -1,
  worldOutline=world and world:isOutlineHighlight(p:getPlayerNum()) or false,
  worldX=world and world:getSquare():getX()+world:getOffX() or -1,worldY=world and world:getSquare():getY()+world:getOffY() or -1,
  worldZ=world and world:getSquare():getZ()+world:getOffZ() or -1,worldRotation=item:getWorldZRotation(),
  cargo=weight,cargoIDs=ids,cargoCount=children,x=p:getX(),y=p:getY(),z=p:getZ(),
  statusAvailable=toolkitWoodCartStatus~=nil,active=status.active==true,recovering=status.recovering==true,rendered=status.rendered==true,
  ik=status.ik==true,presentationProgress=status.progress or 0,pickup=status.pickup==true,authored=status.authored==true}
end
local function event(name,now)
 local row=snapshot(now);row.event=name
 print('[WOOD_INTERACTION_EVENT] '..encode(row))
end
local function reclaim()
 if not item then return end
 ISTimedActionQueue.clear(p)
 local count,_,world=worlds();assert(count<=1,'Duplicate owned cart during fixture cleanup')
 if world then
  world:setHighlighted(p:getPlayerNum(),false,false)
  local square=world:getSquare()
  square:transmitRemoveItemFromSquare(world);square:removeWorldObject(world);item:setWorldItem(nil)
 end
 if not p:getInventory():contains(item) then p:getInventory():AddItem(item) end
 p:setPrimaryHandItem(item);p:setSecondaryHandItem(item);SaucedCarts.applyCartPose(p)
end
local function prepare()
 reclaim()
 if p:isFemale()~=cases[phase].female then
  p:setFemale(cases[phase].female);p:getDescriptor():setFemale(cases[phase].female);p:resetModel()
 end
 for i=1,3 do
  local held=p:getPrimaryHandItem()
  if held and held:getFullType()==kind then break end
  CartLabKey(Keyboard.KEY_F5)
 end
 item=assert(p:getPrimaryHandItem(),'Missing fixture cart');assert(item:getFullType()==kind,'Wrong fixture cart')
 if (item:getInventory():getCapacityWeight()>0)~=cases[phase].full then CartLabKey(Keyboard.KEY_F6) end
 item=p:getPrimaryHandItem();assert(item and item:getFullType()==kind,'Wrong cart after cargo setup')
 initialCargo,initialCargoIDs=cargo()
 assert(cases[phase].full and math.abs(initialCargo-item:getInventory():getEffectiveCapacity(p))<.01 or not cases[phase].full and initialCargo==0,'Wrong initial cargo')
 local x,y,z=CartTestArea.x,CartTestArea.y,CartTestArea.z
 p:setX(x);p:setY(y);p:setZ(z);p:setNextX(x);p:setNextY(y);p:setLastX(x);p:setLastY(y)
 p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow();cartLabPoseHeading(math.pi*.75)
 CartTestArea.check(p)
 p:removeFromHands(item);SaucedCarts.clearCartPose(p);p:getInventory():Remove(item)
 local square=assert(getCell():getGridSquare(math.floor(x+1),math.floor(y),z),'Ground square missing')
 assert(square:getWorldObjects():size()==0,'Ground square occupied')
 -- Shift only the hotkey fixture so the handle stance is across a tile boundary.
 local offset=config.hotkeySetdown and .75 or .5
 square:AddWorldInventoryItem(item,offset,offset,0,true);item:setWorldZRotation(cases[phase].yaw)
 assert(item:getWorldItem() and inventoryCount()==0,'Fixture ground placement failed')
 assert(SaucedCarts.markDropPersistent(item),'Fixture cart persistence marking failed');SaucedCarts.updateCartVisual(item,p,true)
 if cases[phase].nearStance then
  -- A lateral error inside native arrival tolerance must still align before pickup.
  local stance=assert(toolkitWoodCartStance(p,item:getWorldItem()),'Missing near-stance target')
  local heading=math.atan2(stance.faceY-p:getY(),stance.faceX-p:getX())
  local nearX,nearY=stance.x+.03*math.sin(heading),stance.y-.03*math.cos(heading)
  p:setX(nearX);p:setY(nearY);p:setNextX(nearX);p:setNextY(nearY);p:setLastX(nearX);p:setLastY(nearY)
  p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow()
 end
 stage,heldAt,droppedAt='grounded',nil,nil
 cycle,driveStage=1,0
 actionSerial,restartCount,cleanupAt=0,0,nil
 interrupted,cancelAt,cancelledAt,retryStage=false,nil,nil,nil
 p:getStats():reset(CharacterStat.ENDURANCE)
 mode='settle';since=getTimestampMs()+1800
end
local function nextCase()
 cartLabDrive(0);cartLabGait(0);phase=phase+1;attempt=0
 if phase>#cases then
  print('[WOOD_BANK] ALL_COMPLETE cases='..#cases)
  cartLabDrive(-1);Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
  return
 end
 prepare()
end
CartLabHUD.prerender=function(self)
 self:drawRect(0,0,self.width,self.height,.85,0,0,0)
 local c=cases[phase]
 self:drawText(c and c.name..' '..stage..' wallMs='..math.max(0,getTimestampMs()-since) or 'Complete',10,5,1,1,1,1,UIFont.Medium)
end
local function hotkeyPlacement(eventName,action,now)
 assert(action and action.Type=='ToolkitWoodCartDrop' and action.item==item,'Hotkey did not retain exact native drop action')
 local sq=assert(action.sq,'Hotkey drop square missing')
 local row={event=eventName,case=cases[phase].name,start=since,wall=now,actionSerial=actionSerial,id=item:getID(),
  key=hotkeyCode,actionType=action.Type,x=sq:getX()+action.xoffset,y=sq:getY()+action.yoffset,z=sq:getZ()+action.zoffset,
  rotation=action.rotation,actorX=p:getX(),actorY=p:getY(),actorZ=p:getZ(),route='OnKeyStartPressed'}
 print('[WOOD_HOTKEY] '..encode(row))
end
local function rapidQueue(action,now)
 actionSerial=actionSerial+1;stage=action
 if action=='pickup' then
  ISTimedActionQueue.add(ISCartPickupAction.FromWorldItem(p,assert(item:getWorldItem())))
 else
  if config.hotkeySetdown then
   assert(#ISTimedActionQueue.getTimedActionQueue(p).queue==0 and p:getCharacterActions():isEmpty(),'Hotkey requires an empty native/Lua queue')
   local options=assert(PZAPI.ModOptions:getOptions('SaucedCarts'),'SaucedCarts options missing')
   local binding=assert(options:getOption('PushCart'),'SaucedCarts PushCart key missing')
   if config.hotkeyKey then binding:setValue(config.hotkeyKey) end -- Disposable in-memory preference only; never save.
   hotkeyCode=binding:getValue();assert(not config.hotkeyKey or hotkeyCode==config.hotkeyKey,'Disposable hotkey binding did not apply')
   triggerEvent('OnKeyStartPressed',hotkeyCode);triggerEvent('OnCustomUIKeyPressed',hotkeyCode)
   hotkeyReleaseAt=now
   hotkeyAction=assert(ISTimedActionQueue.getTimedActionQueue(p).queue[1],'Hotkey did not enqueue a drop')
   hotkeyStarted=false;hotkeyPlacement('queued',hotkeyAction,now)
  else
   local queued=ISUnequipAction:new(p,item,1,'drop');ISTimedActionQueue.add(queued)
   assert(queued.Type=='ToolkitWoodCartSetdown','Native rapid drop was not dispatched')
  end
 end
 event('actionQueued',now)
end
local function rapidTick(now,elapsed,row,c)
 if config.hotkeySetdown and stage=='drop' and hotkeyAction and not hotkeyStarted and hotkeyAction:isStarted() then
  hotkeyStarted=true;hotkeyPlacement('started',hotkeyAction,now)
 end
 assert(elapsed<19000 or stage=='dropped','Rapid action sequence timed out')
 if stage=='grounded' then
  if elapsed>=700 then rapidQueue('pickup',now) end
 elseif stage=='cancelling' then
  assert(now-cancelAt<1000,'Rapid cancellation did not clear native/Lua queues')
  if row.nativeActions==0 and row.luaActions==0 then
   event('cancelCleared',now);rapidQueue(retryStage,now)
  end
 elseif stage=='pickup' or stage=='drop' then
  local expected=c.repeatKind==stage..'-restart'
  local threshold=restartCount==0 and .55 or .88
  if expected and restartCount<2 and row.active and row.progress>=threshold then
   local action=assert(ISTimedActionQueue.getTimedActionQueue(p).queue[1])
   assert(action.action and not action.action:finished() and row.progress<threshold+.1,'Rapid cancellation missed native phase')
   restartCount=restartCount+1;retryStage=stage;cancelAt=now;event('cancelRequested',now)
   stage='cancelling';assert(CancelAction,'Native cancel handler missing');CancelAction(p:getPlayerNum())
  elseif row.nativeActions==0 and row.luaActions==0 then
   local picked=stage=='pickup'
   assert(row.inventoryCount==(picked and 1 or 0) and row.worldCount==(picked and 0 or 1),'Rapid completion lost ownership')
   assert(row.heldID==(picked and item:getID() or -1) and row.secondaryID==row.heldID,'Rapid completion lost hands')
   event('actionCompleted',now)
   if picked then rapidQueue('drop',now)
   elseif c.repeatKind=='complete-chain' and cycle==1 then cycle=2;rapidQueue('pickup',now)
   else stage='dropped';droppedAt=now;event('dropped',now) end
  end
 elseif stage=='dropped' and elapsed>=19000 and not cleanupAt then
  assert(row.nativeActions==0 and row.luaActions==0 and row.actionType=='' and not row.active and not row.recovering
   and not row.rendered and not row.ToolkitWoodCartAction and not row.IsPerformingAnAction and row.PerformingAction=='',
   'Rapid final cleanup incomplete')
  cleanupAt=now;event('finalCleanup',now)
 end
end
local function tick()
 local data=getPlayerData(0)
 if data and data.characterInfo then data.characterInfo:setVisible(false) end
 if ISChat and ISChat.instance then ISChat.instance:setVisible(false) end
 getCore():setAutoZoom(0,false)
 if getCore():getZoom(0)>.251 then getCore():doZoomScroll(0,-1) end
 local now=getTimestampMs();local c=cases[phase]
 if hotkeyReleaseAt and now>hotkeyReleaseAt then
  triggerEvent('OnKeyPressed',hotkeyCode);triggerEvent('OnCustomUIKey',hotkeyCode);triggerEvent('OnCustomUIKeyReleased',hotkeyCode)
  print('[WOOD_HOTKEY_RELEASE] '..encode({case=c.name,start=since,wall=now,actionSerial=actionSerial,id=item:getID(),key=hotkeyCode}))
  hotkeyReleaseAt=nil
 end
 if mode=='settle' then
  if now<since then return end
  assert(toolkitVideoStart(videoRoot..'/'..c.name..'-'..attempt,ffmpeg),'Video start rejected')
  since=getTimestampMs();now=since;sampleSince=0;mode='record'
  print('[WOOD_BANK] CASE '..c.name..' attempt='..attempt..' wall='..since)
  event('prepared',now);return
 end
 local video=toolkitVideoStatus()
 if video.state=='failed' then
  attempt=attempt+1;assert(attempt<=3,'Repeated video failure '..tostring(video.error))
  print('[WOOD_BANK] RETRY '..c.name..' reason='..tostring(video.error));prepare();return
 end
 if mode=='finish' then
  assert(now-since<(config.wheelCycle and 40000 or 28000),'Video finalization timed out')
  if video.state=='completed' then
   print('[WOOD_BANK] COMPLETE '..c.name..' wall='..since..' file='..tostring(video.file)..' frames='..tostring(video.frames)..' seconds='..tostring(video.seconds))
   nextCase()
  end
  return
 end
 local elapsed=now-since
 if not config.interruptions and not config.rapidRepeats and not config.wheelCycle then
  local world=item:getWorldItem()
  if world then
   local age=stage=='grounded' and elapsed or stage=='dropped' and now-droppedAt or -1
   local highlighted=age>=0 and (age<200 or age>=350) and (stage=='dropped' or age<650)
   if world:isOutlineHighlight(p:getPlayerNum())~=highlighted then
    world:setHighlighted(p:getPlayerNum(),highlighted,false)
   end
   if world~=selectionWorld or highlighted~=selectionOn then
    selectionWorld,selectionOn=world,highlighted
    local highlight=snapshot(now);highlight.event=highlighted and 'highlightOn' or 'highlightOff'
    print('[WOOD_HIGHLIGHT] '..encode(highlight))
   end
  end
 end
 local row=snapshot(now)
 if now-sampleSince>=25 then sampleSince=now;print('[WOOD_INTERACTION_SAMPLE] '..encode(row)) end
 assert(row.worldCount<=1 and row.woodWorldCount==row.worldCount and row.inventoryCount<=1 and row.worldCount+row.inventoryCount==1,'Cart duplicated or disappeared')
 if config.rapidRepeats then
  rapidTick(now,elapsed,row,c)
  if elapsed>=20000 then
   assert(stage=='dropped' and cleanupAt and now-droppedAt>=1000,'Missing rapid settled cleanup tail')
   assert(toolkitVideoStop(),'Video stop rejected');mode='finish'
  end
  return
 end
 if config.interruptions and not interrupted and stage==c.interrupt and row.active and row.progress>=c.threshold then
  local action=assert(ISTimedActionQueue.getTimedActionQueue(p).queue[1],'Cancellation action missing')
  assert(action.action and not action.action:finished() and row.progress<c.threshold+.1,'Cancellation missed unfinished native window')
  interrupted=true;cancelAt=now;retryStage=stage;stage='cancelling';event('cancelRequested',now)
  if c.route=='cancel' then
   assert(CancelAction,'Native cancel handler missing');CancelAction(p:getPlayerNum())
  else driveStage=1;cartLabDrive(1) end
  return
 end
 if stage=='cancelling' then
  assert(now-cancelAt<1000,'Native cancellation did not clear the action')
  if row.nativeActions==0 and row.luaActions==0 then
   if not config.interruptionMatrix then driveStage=0;cartLabDrive(0) end
   cancelledAt=now;stage='cancelled';event('cancelled',now)
  end
  return
 elseif stage=='cancelled' then
  if config.interruptionMatrix and c.route=='walk' and driveStage~=0 and now-cancelledAt>=900 then
   driveStage=0;cartLabDrive(0);event('movementReleased',now)
  end
  if now-cancelledAt<(config.interruptionMatrix and c.route=='walk' and 1400 or 900) then return end
  event('retryQueued',now)
  if retryStage=='pickup' then
   stage='pickup';ISTimedActionQueue.add(ISCartPickupAction.FromWorldItem(p,assert(item:getWorldItem())))
  else
   stage='drop';ISTimedActionQueue.add(ISUnequipAction:new(p,item,1,'drop'))
  end
  return
 end
 if stage=='grounded' and elapsed>=700 then
  local world=assert(item:getWorldItem(),'Pickup target disappeared')
  stage='pickup';ISTimedActionQueue.add(ISCartPickupAction.FromWorldItem(p,world));event('pickupQueued',now)
 elseif stage=='pickup' then
  assert(elapsed<(config.wheelCycle and 29000 or config.interruptions and 13500 or 8500),'Pickup timed out')
  if row.heldID==item:getID() and row.secondaryID==item:getID() and row.inventoryCount==1 and row.worldCount==0 and row.actionType=='' then
   stage='held';heldAt=now;event('pickedUp',now)
  end
 elseif stage=='held' then
  local heldFor=now-heldAt
  if config.wheelCycle and cycle==1 then
   local nextDrive=heldFor<350 and 0 or heldFor<1200 and 1 or heldFor<2100 and 2 or heldFor<3100 and 4 or 0
   if nextDrive~=driveStage then
    driveStage=nextDrive;cartLabDrive(nextDrive);event('driveChanged',now)
   end
   if heldFor<3900 then return end
  elseif heldFor<1100 then return end
  cartLabDrive(0);stage='drop'
  -- The ground context menu binds DropNamedItem to onUnEquip, with no drop reason.
  ISInventoryPaneContextMenu.onUnEquip({item},p:getPlayerNum())
  local action=assert(ISTimedActionQueue.getTimedActionQueue(p).queue[1],'World-menu drop was not queued')
  assert(action.Type=='ToolkitWoodCartSetdown','Native wooden drop was not safely dispatched')
  event('dropQueued',now)
 elseif stage=='drop' then
  assert(elapsed<(config.wheelCycle and 29000 or config.interruptions and 19000 or 14500),'Setdown timed out')
  if row.heldID==-1 and row.secondaryID==-1 and row.inventoryCount==0 and row.worldCount==1 and row.actionType=='' then
   stage='dropped';droppedAt=now;event('dropped',now)
  end
 elseif config.wheelCycle and stage=='dropped' and cycle==1 and now-droppedAt>=900 then
  cycle=2;stage='pickup';ISTimedActionQueue.add(ISCartPickupAction.FromWorldItem(p,assert(item:getWorldItem())))
  event('pickupQueued',now)
 end
 if elapsed>=(config.wheelCycle and 30000 or config.interruptions and 20000 or 16000) then
  assert(stage=='dropped' and now-droppedAt>=1000,'Missing settled drop tail')
  assert(toolkitVideoStop(),'Video stop rejected');mode='finish'
 end
end
WoodPrototypeTick=function()
 local ok,err=pcall(tick)
 if not ok then
  Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
  ISTimedActionQueue.clear(p);cartLabDrive(-1);toolkitVideoStop()
  print('[WOOD_BANK] FAIL '..tostring(err))
 end
end
print('[WOOD_BANK] RUN_STARTED')
getCore():setAutoZoom(0,false)
for i=1,16 do getCore():doZoomScroll(0,-1) end
nextCase();Events.OnTick.Add(WoodPrototypeTick)
