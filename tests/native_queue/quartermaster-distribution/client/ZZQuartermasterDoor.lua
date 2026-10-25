local config=require 'QueueTestSelection'
if config.cases[1]~='barricaded-door' then return end
local JSON=require 'QueueHealthEvents'
local started,done,since,phase=false,false,0,'prepare'
local point,boxes,doors,barricade,owned,items,ids,designatedAt
local updates,walked,detour=0,false,false
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function square(x,y)return assert(getCell():getGridSquare(point.x+x,point.y+y,point.z))end
local function place(player)
 local origin=player:getCurrentSquare()
 for radius=2,25 do for dx=-radius,radius do for dy=-radius,radius do
  if math.abs(dx)==radius or math.abs(dy)==radius then
   local x,y,z=origin:getX()+dx,origin:getY()+dy,origin:getZ()
   local clear=true
   for a=-2,7 do for b=-7,7 do
    local sq=getCell():getGridSquare(x+a,y+b,z)
    if not sq or not sq:canStand() or not sq:isFree(false) or sq:getRoom() or sq:getObjects():size()>1 then clear=false end
   end end
   if clear then
    player:teleportTo(x,y,z);player:setX(x+0.5);player:setY(y+0.5)
    player:setLastX(x+0.5);player:setLastY(y+0.5);player:setCurrentSquareFromPosition()
    return {x=x,y=y,z=z}
   end
  end
 end end end
 error('No clear loaded pad for barricaded-door fixture')
end
local function prepare(player)
 assert(not isClient() and not isServer(),'door fixture requires isolated SP')
 point=place(player);boxes={};owned={};doors={};items={};ids={}
 for _,dx in ipairs({-1,3,5})do
  local sq=square(dx,0)
  local box=IsoThumpable.new(getCell(),sq,'carpentry_01_16',false,{})
  box:setBlockAllTheSquare(true);box:setIsContainer(true)
  box:getContainer():setType('crate');box:getContainer():setCapacity(100);box:getContainer():setExplored(true)
  sq:AddSpecialObject(box);owned[#owned+1]=box;boxes[#boxes+1]=box
 end
 for index,kind in ipairs({'Base.Nails','Base.Apple'})do
  local item=assert(boxes[1]:getContainer():AddItem(kind));items[index]=item;ids[index]=item:getID()
  LootSorter.setBoxItems(boxes[index+1],0,{[item:getDisplayName()]=true})
 end
 designatedAt=getTimestampMs()
 -- A short blocked route, with a longer ordinary door in the same wall.
 for y=-5,5 do
  local sq=square(1,y)
  local door=y==0 or y==3
  local object=door and IsoDoor.new(getCell(),sq,getSprite('fixtures_doors_01_0'),false)
   or IsoObject.new(getCell(),sq,getSprite('walls_exterior_wooden_01_0'))
  if door then
   object:setLocked(false);object:setLockedByKey(false);sq:AddSpecialObject(object);doors[y]=object
  else sq:AddTileObject(object)end
  owned[#owned+1]=object
 end
 barricade=assert(IsoBarricade.AddBarricadeToObject(doors[0],false));barricade:addPlank(player)
 owned[#owned+1]=barricade
 assert(doors[0]:isBarricaded() and not doors[0]:IsOpen() and barricade:getNumPlanks()==1,'native barricade missing')
 print('[QM_DOOR] PREPARED '..JSON.encode({ids=ids}))
end
local function dispatch()
 local loot=assert(getPlayerLoot(0));loot:refreshBackpacks();loot.inventoryPane:refreshContainer()
 local controls=assert(loot.controlsUI)
 local handler=controls:checkHandler(ISLootWindowObjectControlHandler_LootSorterDistribute,boxes[1],boxes[1]:getContainer())
 assert(handler:shouldBeVisible(),'distribution control hidden')
 local button=handler:getControl();local before=LootSorter._sortRunSeq or 0
 LootSorter.DEBUG=true;button.onclick(button.target,button)
 assert((LootSorter._sortRunSeq or 0)>before and #queue().queue>0,'distribution did not start')
end
Events.OnGameStart.Add(function()
 started=true;since=getTimestampMs();getPlayer():setGodMod(true);getPlayer():setGhostMode(true)
 getCore():setOptionAutoDrink(false);getPlayer():setAutoDrink(false)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
end)
Events.OnPlayerUpdate.Add(function(player)
 if started and player==getPlayer()then updates=updates+1 end
end)
local function tick()
 local player=getPlayer()
 if phase=='prepare'then
  if updates<30 then return end
  prepare(player);phase='settle';updates=0
 elseif phase=='settle'then
  -- Let native path-map tasks consume the real walls, doors and barricade.
  if updates<60 or not LootSorter.isRegistrySynced() or not LootSorter.arePresetsSynced()then return end
  dispatch();phase='sorting'
 elseif phase=='sorting'then
  local current=queue().current
  if current and current.Type=='LootSorterWalkAction' and current:isStarted()then walked=true end
  if player:getY()>point.y+2 and player:getY()<point.y+4 then detour=true end
  assert(not doors[0]:IsOpen() and doors[0]:isBarricaded() and barricade:getNumPlanks()==1,
   'routing opened/damaged the barricaded door')
  if #queue().queue>0 or player:hasTimedActions()then return end
  assert(walked and detour and doors[3]:IsOpen(),'native walk did not take the ordinary-door detour')
  for index,item in ipairs(items)do
   assert(item:getContainer()==boxes[index+1]:getContainer(),'distribution stopped before item '..index)
   local count=0
   for _,box in ipairs(boxes)do if box:getContainer():contains(item)then count=count+1 end end
   if player:getInventory():contains(item)then count=count+1 end
   assert(count==1 and boxes[index+1]:getContainer():getItemById(ids[index])==item,'item identity/conservation failed')
  end
  print('[QM_DOOR] RESULT '..JSON.encode({ids=ids,moved=2,nativeWalking=true,detour=true,
   normalDoorOpened=true,barricadedDoorClosed=true,barricadeIntact=true,conserved=true}))
  phase='cleanup'
 elseif phase=='cleanup'then
  if getTimestampMs()-designatedAt<LootSorter.ADD_GRACE_MS+1000 then return end
  for index=2,3 do LootSorter.setBoxItems(boxes[index],0,{})end
  for index=#owned,1,-1 do
   local object=owned[index];local sq=object:getSquare()
   if sq and object:getObjectIndex()>=0 then sq:transmitRemoveItemFromSquare(object)end
  end
  print('[QM_DOOR] COMPLETE');done=true
 end
end
Events.OnTick.Add(function()
 if not started or done then return end
 local ok,problem=pcall(function()assert(getTimestampMs()-since<180000,'door distribution timeout phase='..phase);tick()end)
 if not ok then done=true;print('[QM_DOOR] FAIL '..tostring(problem))end
end)
