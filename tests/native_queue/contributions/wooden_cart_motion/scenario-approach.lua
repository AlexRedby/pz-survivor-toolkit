-- Public-menu pickup edges. Fixture setup alone relocates actors/items; every measured move is native.
local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true and getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer(),'Disposable SP CartTestArea required')
require 'SaucedCarts/ContextMenu'
require 'ISUI/ISContextMenu'
require 'TimedActions/ISTimedActionQueue'
require 'TimedActions/WalkToTimedActionF'
local area,p=assert(CartTestArea),assert(getPlayer())
assert(area.ready and area.setObstacles and CartLabSelectScenes and cartLabDrive and cartLabGait and cartLabPoseHeading,'CartLab/obstacles required')
assert(not p:isTimedActionInstant(),'Native durations required')
assert(type(config.videoRoot)=='string' and config.videoRoot:sub(1,1)=='/' and type(config.ffmpeg)=='string' and config.ffmpeg:sub(1,1)=='/','Absolute video paths required')
assert(config.entryContactRepro==nil or type(config.entryContactRepro)=='boolean','entryContactRepro must be boolean')
local entryContactRepro=config.entryContactRepro==true
if WoodPrototypeTick then Events.OnTick.Remove(WoodPrototypeTick) end
local cases={{name='container-equip'},{name='wrong-side'},{name='wall-detour'},
 {name='precise-blocked'},{name='approach-cancel'},{name='approach-target-loss'},{name='approach-tail-success'}}
cases=CartLabSelectScenes(cases)
if entryContactRepro then
 for _,case in ipairs(cases) do
  assert(case.name=='container-equip' or case.name=='wrong-side','entryContactRepro supports container-equip and wrong-side only')
 end
end
local index,since,sampled,mode=0,0,0,'prepare'
local item,bag,cargoID,cargoWeight,approach,tail,stance,queuedAt,terminalAt,changed
local wallX,wallY=math.floor(area.x),math.floor(area.y)
local cartX,cartY=area.x,area.y
local vehicleLayout,collisionX
local tailX,tailY,startX,startY,removed=nil,nil,0,0,false
local entryPants,entryPantsModel,preWalkStartedAt,preWalkReleasedAt,preWalkX,preWalkY,preWalkSeen
-- This opt-in fixture changes presentation/load only, never the public action producer.
if entryContactRepro then
 p:setFemale(false);p:getDescriptor():setFemale(false);p:clearWornItems()
 p:getHumanVisual():setHairModel('CrewCut');p:getHumanVisual():setBeardModel('')
 for _,name in ipairs({'Base.Tshirt_DefaultTEXTURE_TINT','Base.Trousers_JeanBaggy','Base.Shoes_TrainerTINT'}) do
  local clothing=assert(p:getInventory():AddItem(name),name);p:setWornItem(clothing:getBodyLocation(),clothing)
  if name=='Base.Trousers_JeanBaggy' then entryPants=clothing end
 end
 local definition=assert(entryPants:getClothingItem(),'Baggy jeans clothing definition missing')
 entryPantsModel=assert(definition:getMaleModel(),'Baggy jeans male model missing')
 assert(entryPantsModel:lower():gsub('\\','/'):gsub('%.x$','')=='skinned/clothes/bob_trousers','Baggy jeans no longer use native Bob_Trousers')
 p:resetModel()
end
local function queue() return ISTimedActionQueue.getTimedActionQueue(p).queue end
local function empty() return #queue()==0 and p:getCharacterActions():isEmpty() and not p:hasPath() end
local function encode(row)
 local out={}
 for key,value in pairs(row) do
  if type(value)=='string' then value='"'..value:gsub('[%z\1-\31\\"]',function(c) return string.format('\\u%04x',string.byte(c)) end)..'"'
  elseif type(value)=='number' then assert(value==value and math.abs(value)<math.huge,'Nonfinite approach evidence');value=tostring(value)
  else assert(type(value)=='boolean','Invalid approach evidence');value=tostring(value) end
  out[#out+1]='"'..key..'":'..value
 end
 return '{'..table.concat(out,',')..'}'
end
local function relocate(x,y)
 assert(empty(),'Cannot relocate during native action')
 p:setX(x);p:setY(y);p:setZ(area.z);p:setNextX(x);p:setNextY(y);p:setLastX(x);p:setLastY(y)
 p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow();cartLabPoseHeading(math.pi)
end
local function removeWorld(value)
 local world=value and value:getWorldItem()
 if world then local sq=assert(world:getSquare());sq:transmitRemoveItemFromSquare(world);sq:removeWorldObject(world);value:setWorldItem(nil) end
end
-- Native ground placement begin. Constructor zero offsets mean random, so restore explicit fixture placement.
local function ground(x,y)
 removeWorld(item)
 local container=item:getContainer();if container then container:Remove(item) end
 local sq=assert(getCell():getGridSquare(math.floor(x),math.floor(y),area.z))
 local offX,offY=x-math.floor(x),y-math.floor(y)
 sq:AddWorldInventoryItem(item,offX,offY,0,true)
 local world=assert(item:getWorldItem());world:setOffX(offX);world:setOffY(offY)
 cartX,cartY=world:getWorldPosX(),world:getWorldPosY()
 assert(math.abs(cartX-x)<.002 and math.abs(cartY-y)<.002,'Native world cart placement differs from request')
 item:setWorldZRotation(135)
 assert(SaucedCarts.markDropPersistent(item));SaucedCarts.updateCartVisual(item,p,true)
 stance=assert(toolkitWoodCartStance(p,world),'Missing wooden handle stance')
end
-- Native ground placement end.
local function snapshot(now)
 local contents=item:getInventory():getItems()
 assert(contents:size()==1 and contents:get(0):getID()==cargoID and contents:get(0):getFullType()=='Base.Log'
  and math.abs(contents:get(0):getActualWeight()-cargoWeight)<.001,'Exact cargo changed')
 local inv,worlds=0,0
 local items=p:getInventory():getItems();for i=0,items:size()-1 do if items:get(i):getID()==item:getID() then assert(items:get(i)==item);inv=inv+1 end end
 for x=wallX-8,wallX+8 do for y=wallY-8,wallY+8 do
  local sq=assert(getCell():getGridSquare(x,y,area.z));local values=sq:getWorldObjects()
  for i=0,values:size()-1 do local value=values:get(i):getItem();if value and value:getID()==item:getID() then assert(value==item);worlds=worlds+1 end end
 end end
 local nested=bag and item:getContainer()==bag:getInventory() and 1 or 0
 assert(inv+worlds+nested+(removed and 1 or 0)==1,'Cart ownership duplicated/lost')
 local a,b=p:getPrimaryHandItem(),p:getSecondaryHandItem();local status=toolkitWoodCartStatus(p)
 local current=queue()[1]
 local row={case=cases[index].name,start=since,wall=now,elapsed=now-since,id=item:getID(),cargoID=cargoID,cargoWeight=cargoWeight,
  inventoryCount=inv,worldCount=worlds,containerCount=nested,removed=removed,primaryID=a and a:getID() or -1,secondaryID=b and b:getID() or -1,
  x=p:getX(),y=p:getY(),z=p:getZ(),startX=startX,startY=startY,goalX=stance and stance.x or startX,goalY=stance and stance.y or startY,
  nativeTargetX=p:getPathFindBehavior2():getTargetX(),nativeTargetY=p:getPathFindBehavior2():getTargetY(),
  tailX=tailX or startX,tailY=tailY or startY,wallX=wallX,wallY=wallY,cartX=cartX,cartY=cartY,
  collisionKind=vehicleLayout and 'vehicle' or '',collisionX=collisionX or wallX,vehicleState=vehicleLayout and cartLabVehicleState() or '',
  luaActions=#queue(),nativeActions=p:getCharacterActions():size(),hasPath=p:hasPath(),actionType=current and current.Type or '',
  approachResult=approach and approach.result==BehaviorResult.Failed and 'Failed' or approach and approach.result==BehaviorResult.Succeeded and 'Succeeded' or '',
  tailResult=tail and tail.result==BehaviorResult.Succeeded and 'Succeeded' or '',
  active=status.active==true,recovering=status.recovering==true,rendered=status.rendered==true,
  ToolkitWoodCartAction=p:getVariableBoolean('ToolkitWoodCartAction'),route=bag and 'inventory-menu' or 'world-menu'}
 if entryContactRepro then
  assert(not p:isFemale() and p:getWornItem(entryPants:getBodyLocation())==entryPants,'Entry-contact actor/outfit changed')
  assert(math.abs(item:getInventory():getCapacityWeight()-item:getInventory():getEffectiveCapacity(p))<.01,'Entry-contact cargo is not full')
  row.entryContactRepro=true;row.female=false;row.pantsType=entryPants:getFullType();row.pantsID=entryPants:getID();row.pantsModel=entryPantsModel
  row.cargoCapacity=item:getInventory():getEffectiveCapacity(p)
  row.preWalkStartedAt=preWalkStartedAt or -1;row.preWalkReleasedAt=preWalkReleasedAt or -1;row.preWalkSeen=preWalkSeen==true
  row.preWalkDistance=preWalkX and math.sqrt((p:getX()-preWalkX)^2+(p:getY()-preWalkY)^2) or 0
  row.preWalkDrive=preWalkStartedAt and not preWalkReleasedAt and 1 or 0
 end
 return row
end
local function emit(event,now)
 local row=snapshot(now);row.event=event;print('[CART_APPROACH_EVENT] '..encode(row));return row
end
local function entryReceipt(event,now)
 local row=snapshot(now);row.event=event
 row.preWalkPlannedStartMs=350;row.preWalkPlannedDurationMs=350;row.heldTailMinimumMs=1000
 print('[CART_ENTRY_CONTACT] '..encode(row))
end
local function push()
 local function find(context)
  for _,option in ipairs(context.options) do
   if option.name==getText('UI_SaucedCarts_PushCart') or option.name=='Push Cart' then return option end
   if option.subOption then local found=find(context:getSubMenu(option.subOption));if found then return found end end
  end
 end
 local context=ISContextMenu.get(p:getPlayerNum(),50,50)
 if bag then triggerEvent('OnFillInventoryObjectContextMenu',p:getPlayerNum(),context,{item})
 else triggerEvent('OnFillWorldObjectContextMenu',p:getPlayerNum(),context,{assert(item:getWorldItem())},false) end
 local option=assert(find(context),'Public Push Cart option missing');assert(option.onSelect and not option.notAvailable,'Public Push Cart unavailable')
 context:hideAndChildren()
 option.onSelect(option.target,option.param1,option.param2,option.param3,option.param4,option.param5,option.param6,option.param7,option.param8,option.param9,option.param10)
 approach=assert(queue()[1],'Public menu queued nothing')
 assert(approach.Type==(bag and 'ISCartEquipAction' or 'ISWalkToTimedActionF'),'Unexpected public pickup route')
 if not bag then assert(approach.toolkitWoodCartItem==item,'Approach lost exact target') end
end
local function cleanup()
 assert(empty(),'Cleanup requires native terminal state')
 cartLabDrive(0);cartLabGait(0);p:removeFromHands(item);SaucedCarts.clearCartPose(p)
 removeWorld(item);local c=item and item:getContainer();if c then c:Remove(item) end
 if bag then removeWorld(bag);bag=nil end
 item=nil;if area.hasVehicles() then area.clearVehicles(p) end;vehicleLayout=nil;collisionX=nil;area.clearObstacles(p);area.check(p)
end
local function ready(now)
 startX,startY=p:getX(),p:getY();mode='settle';since=now+1200
end
local function prepare()
 assert(empty(),'Previous approach left native work');area.clearObstacles(p);area.check(p)
 cartLabDrive(0);cartLabGait(0);p:getStats():reset(CharacterStat.ENDURANCE)
 local held=p:getPrimaryHandItem();if held then p:removeFromHands(held);SaucedCarts.clearCartPose(p);p:getInventory():Remove(held) end
 item=assert(instanceItem('SaucedWheelbarrow.WheelbarrowWood'));local child=assert(item:getInventory():AddItem('Base.Log'))
 if entryContactRepro then SaucedCarts.applyMultipliers(item) end
 child:setActualWeight(entryContactRepro and item:getInventory():getEffectiveCapacity(p) or 1)
 child:setCustomWeight(true);cargoID,cargoWeight=child:getID(),child:getActualWeight()
 bag=nil;approach=nil;tail=nil;terminalAt=nil;queuedAt=nil;changed=false;removed=false;sampled=0;stance=nil;tailX=nil;tailY=nil
 preWalkStartedAt=nil;preWalkReleasedAt=nil;preWalkX=nil;preWalkY=nil;preWalkSeen=false
 local name=cases[index].name
 relocate(wallX+2.5,wallY+.5)
 if name=='container-equip' then
  bag=assert(instanceItem('Base.Bag_DuffelBagTINT'));bag:getInventory():AddItem(item)
  p:getCurrentSquare():AddWorldInventoryItem(bag,.6,.6,0,true)
 elseif name=='precise-blocked' then
  assert(config.vehicles==true and area.setVehicle and area.clearVehicles and cartLabVehicleState,'Native parked vehicle fixture required')
  vehicleLayout=area.setVehicle(p,0);collisionX=vehicleLayout.x+vehicleLayout.width
  relocate(collisionX+.9,vehicleLayout.y)
  ground(collisionX+1,vehicleLayout.y)
  ground(cartX+collisionX+.10-stance.x,cartY+vehicleLayout.y-stance.y)
  assert(math.abs(stance.x-(collisionX+.10))<.002 and math.abs(stance.y-vehicleLayout.y)<.002,'Blocked vehicle handle placement differs from request')
 else
  if name=='wall-detour' then
   local walls={};for y=wallY-1,wallY+1 do walls[#walls+1]={x=wallX+1,y=y,axis='W'} end
   area.setObstacles(p,walls)
  end
  ground(wallX+2.5,wallY+.5)
  if name=='wrong-side' then
   local world=item:getWorldItem();relocate(2*world:getWorldPosX()-stance.x,2*world:getWorldPosY()-stance.y)
  elseif name=='wall-detour' then
   -- Fix the handles relative to the wall; the cart's native authored offset is not the path goal.
   ground(cartX+wallX+2.5-stance.x,cartY+wallY+.5-stance.y)
   relocate(wallX-1,wallY+.5)
  else relocate(stance.x-3,stance.y) end
 end
 ready(getTimestampMs())
end
local function nextCase()
 index=index+1
 if index>#cases then
  print('[CART_APPROACH] CLEANUP_COMPLETE');print('[WOOD_BANK] ALL_COMPLETE cases='..#cases)
  cartLabDrive(-1);Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil;return
 end
 prepare()
end
local function tick()
 local now=getTimestampMs();local name=cases[index].name
 if mode=='settle' then
  if now<since then return end
  assert(toolkitVideoStart(config.videoRoot..'/'..name..'-0',config.ffmpeg),'Video start rejected')
  since=getTimestampMs();mode='record';print('[WOOD_BANK] CASE '..name..' attempt=0 wall='..since)
  emit('prepared',since)
  if entryContactRepro then entryReceipt('outfitAndFullCargo',since) end
  return
 end
 local video=toolkitVideoStatus();assert(video.state~='failed','Approach video failed: '..tostring(video.error))
 assert(now-since<23000,'Approach/video deadline')
 if mode=='finish' then
  if video.state=='completed' then
   print('[WOOD_BANK] COMPLETE '..name..' wall='..since..' file='..video.file..' frames='..video.frames..' seconds='..video.seconds)
   cleanup();nextCase()
  end
  return
 end
 area.checkPosition(p,bag or item:getWorldItem() and item or nil)
 local row=snapshot(now)
 if now-sampled>=25 then sampled=now;print('[CART_APPROACH_SAMPLE] '..encode(row)) end
 if entryContactRepro and bag and not queuedAt then
  if not preWalkStartedAt and now-since>=350 then
   assert(empty(),'Entry pre-Walk requires idle native queue')
   preWalkStartedAt=now;preWalkX=p:getX();preWalkY=p:getY()
   cartLabGait(0);cartLabDrive(1);entryReceipt('preWalkStarted',now)
   return
  elseif preWalkStartedAt and not preWalkReleasedAt then
   preWalkSeen=preWalkSeen or p:getVariableBoolean('isMoving') and not p:isRunning() and not p:isSprinting()
   if now-preWalkStartedAt>=350 then
    cartLabDrive(0);cartLabGait(0);preWalkReleasedAt=now
    entryReceipt('preWalkReleased',now)
    assert(preWalkSeen and row.preWalkDistance>=.05 and row.preWalkDistance<1.5,'Entry native pre-Walk did not execute within the reachable bag corridor')
   end
   return
  end
 end
 if not queuedAt and now-since>=700 then
  if entryContactRepro and bag then assert(preWalkReleasedAt and now>preWalkReleasedAt,'Public equip must follow native Walk release') end
  push();queuedAt=now
  if name=='approach-cancel' or name=='approach-target-loss' or name=='approach-tail-success' then
   tailX,tailY=startX,startY+1
   tail=ISWalkToTimedActionF:new(p,Vector3f.new(tailX,tailY,area.z));ISTimedActionQueue.add(tail)
  end
  emit('queued',now)
  if entryContactRepro then entryReceipt('publicMenuQueued',now) end
 elseif queuedAt and not terminalAt then
  assert(now-queuedAt<14000,'Native approach did not terminate')
  if not changed and (name=='approach-cancel' or name=='approach-target-loss') and approach:isStarted() and p:hasPath() and now-queuedAt>=250 then
   assert(queue()[1]==approach and tail and not tail:isStarted(),'Interruption missed approach window')
   changed=true;emit(name=='approach-cancel' and 'cancelRequested' or 'targetRemoved',now)
   if name=='approach-cancel' then CancelAction(p:getPlayerNum())
   else removeWorld(item);removed=true end
  end
  if empty() then
   local success=name=='container-equip' or name=='wrong-side' or name=='wall-detour' or name=='approach-tail-success'
   assert(not (name=='approach-cancel' or name=='approach-target-loss') or changed,'Interruption never occurred')
   local state=snapshot(now)
   if success then assert(state.inventoryCount==1 and state.worldCount==0 and state.primaryID==item:getID() and state.secondaryID==item:getID(),'Pickup failed exact ownership')
   else assert(state.inventoryCount==0 and state.primaryID==-1 and state.secondaryID==-1,'Failed/cancelled approach equipped cart') end
   if name=='precise-blocked' then
    local path=p:getPathFindBehavior2();local dx,dy=path:getTargetX()-stance.x,path:getTargetY()-stance.y
    assert(approach.result==BehaviorResult.Succeeded and dx*dx+dy*dy>.002*.002,'Native planner clipping was not exercised')
    assert(p:DistToSquared(stance.x,stance.y)>.002*.002 and p:DistToSquared(path:getTargetX(),path:getTargetY())<=.06*.06,'Invalid native clipped arrival')
   end
   if tail and name~='approach-cancel' then assert(tail.result==BehaviorResult.Succeeded,'Independent tail did not complete') end
   if name=='approach-cancel' then assert(not tail:isStarted() and not tail.result,'Native full-queue cancellation consumed tail') end
   terminalAt=getTimestampMs();emit('terminal',terminalAt)
   if entryContactRepro then entryReceipt('heldTailStarted',terminalAt) end
  end
 elseif terminalAt and now-terminalAt>=1000 then
  local state=snapshot(now)
  assert(empty() and not state.active and not state.recovering and not state.rendered and not state.ToolkitWoodCartAction,'Approach leaked presentation/queue')
  emit('settled',now)
  if entryContactRepro then entryReceipt('heldTailComplete',now) end
  assert(toolkitVideoStop(),'Video stop rejected');mode='finish'
 end
end
WoodPrototypeTick=function()
 local ok,why=pcall(tick)
 if not ok then
  cartLabDrive(-1);cartLabGait(0);ISTimedActionQueue.clear(p);toolkitVideoStop()
  Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil;print('[WOOD_BANK] FAIL '..tostring(why))
 end
end
cartLabDrive(0);cartLabGait(0);setGameSpeed(1)
print('[WOOD_BANK] RUN_STARTED');nextCase();Events.OnTick.Add(WoodPrototypeTick)
