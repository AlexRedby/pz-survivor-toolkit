local Fixture = {}
-- Native ISWoodenContainer and entity_carpentry_crate_lvl2 use this crate sprite.
Fixture.crateSprite='carpentry_01_16'
function Fixture.startFree(square,player)
 if not square or not square:canStand() or not square:isFree(false) then return false end
 local moving=square:getMovingObjects()
 for i=0,moving:size()-1 do if moving:get(i)~=player then return false end end
 return true
end
function Fixture.crateSquare(player,start)
 start=start or player:getCurrentSquare()
 if not Fixture.startFree(start,player) then return end
 for _,direction in ipairs({IsoDirections.W,IsoDirections.E,IsoDirections.N,IsoDirections.S}) do
  local square=start:getAdjacentSquare(direction)
  if square and square:getZ()==start:getZ() and square:canStand() and square:isFree(true)
   and AdjacentFreeTileFinder.privTrySquare(start,square)
   and start:canReachTo(square) and square:canReachTo(start) then return square end
 end
end
function Fixture.stagePair(player,target,reserved,owner)
 -- Search only already loaded tiles near the intended slot; never alter the map.
 for radius=0,4 do
  for dx=-radius,radius do for dy=-radius,radius do
   if math.max(math.abs(dx),math.abs(dy))==radius then
    local start=getCell():getGridSquare(target.x+dx,target.y+dy,target.z)
    local separate=true
    for name,pair in pairs(reserved) do
     if name~=owner and start and math.max(math.abs(start:getX()-pair.start:getX()),math.abs(start:getY()-pair.start:getY()))<8 then
      separate=false;break
     end
    end
    if separate and start then
     local crate=Fixture.crateSquare(player,start)
     if crate then return {start=start,crate=crate} end
    end
   end
  end end
 end
end
local function location(value)
 return value and {x=value:getX(),y=value:getY(),z=value:getZ()} or nil
end
function Fixture.traceWalk(action,emit)
 local start,update,stop,forceStop=action.start,action.update,action.stop,action.forceStop
 local origin=location(action.character)
 local originCanStand=action.character:getCurrentSquare() and action.character:getCurrentSquare():canStand()
 local function trace(event,branch)
  local player=action.character
  emit({event=event,branch=branch,result=tostring(action.result),origin=origin,
   current=location(player),destination=location(action.location),
   originCanStand=originCanStand,currentCanStand=player:getCurrentSquare() and player:getCurrentSquare():canStand(),
   destinationCanStand=action.location and action.location:canStand(),
   movement=player:pressedMovement(false),cancel=player:pressedCancelAction()})
 end
 action.start=function(self,...)
  trace('start');return start(self,...)
 end
 action.update=function(self,...)
  self.tagFixtureUpdating=true
  local result=update(self,...)
  self.tagFixtureUpdating=nil
  return result
 end
 action.forceStop=function(self,...)
  local branch='external'
  if self.tagFixtureUpdating then
   if self.character:pressedMovement(false) or self.character:pressedCancelAction() then branch='input'
   elseif self.result==BehaviorResult.Failed then branch='path-failed' end
  end
  self.tagFixtureStopBranch=branch;trace('forceStop',branch)
  return forceStop(self,...)
 end
 action.stop=function(self,...)
  trace('stop',self.tagFixtureStopBranch or 'engine-stop');return stop(self,...)
 end
 return action
end
function Fixture.position(player,x,y,z)
 player:teleportTo(math.floor(x),math.floor(y),z);player:setX(x);player:setY(y);player:setZ(z)
 player:setLastX(x);player:setLastY(y);player:setLastZ(z);player:setCurrentSquareFromPosition()
end
function Fixture.sameRule(rule)
 if type(rule)~='table' or rule.mode~='all' then return false end
 local include,exclude={},{}
 for _,id in ipairs(rule.include or {}) do include[id]=true end
 for _,id in ipairs(rule.exclude or {}) do exclude[id]=true end
 return #rule.include==2 and include.food and include.perishable and #rule.exclude==1 and exclude.meat
end
function Fixture.rule() return {mode='all',include={'food','perishable'},exclude={'meat'}} end
function Fixture.placementLoaded(packet)
 if type(packet)~='table' or type(packet.signature)~='string' or packet.signature==''
  or type(packet.squares)~='table' or #packet.squares~=4 then return false end
 for _,point in ipairs(packet.squares) do
  if not getCell():getGridSquare(point.x,point.y,point.z) then return false end
 end
 return true
end
function Fixture.object(packet,owner)
 local square=getCell():getGridSquare(packet.x,packet.y,packet.z)
 if not square then return end
 local objects=square:getObjects()
 if type(packet.index)~='number' or packet.index<0 or packet.index>=objects:size() then return end
 local object=objects:get(packet.index)
 if not object or not object:hasModData() or object:getModData().PZSTTagFixtureOwner~=owner then return end
 if object:getContainerCount()<1 or not object:getContainerByIndex(0) then return end
 return object
end
function Fixture.find(container,id)
 local items=container:getItems()
 for index=0,items:size()-1 do local item=items:get(index);if item:getID()==id then return item end end
end
function Fixture.counts(container,result)
 result=result or {}
 local items=container:getItems()
 for index=0,items:size()-1 do
  local item=items:get(index);local id=item:getID();result[id]=(result[id] or 0)+1
  if instanceof(item,'InventoryContainer') then Fixture.counts(item:getInventory(),result) end
 end
 return result
end
function Fixture.sortTarget(player,object)
 if not LootSorter.isRegistrySynced() then return nil,'registry not synchronized' end
 if not LootSorter.arePresetsSynced() then return nil,'presets not synchronized' end
 local boxes,synced=LootSorter.gatherBoxes(player)
 if synced==false then return nil,'native gather not synchronized' end
 for _,entry in ipairs(boxes or {}) do
  if entry.obj==object and entry.container==object:getContainerByIndex(0) then return entry end
 end
 return nil,'owned object absent from native gather'
end
function Fixture.receipt(sourceContainer,destContainer,ids,phase)
 local source,destination=Fixture.counts(sourceContainer),Fixture.counts(destContainer)
 local status,reason,facts='ready',nil,{}
 for _,key in ipairs({'battery','apple','beans','steak'}) do
  local id=ids[key]
  if id then
   local expected=(key=='battery' or key=='apple' and phase=='enabled') and 'destination' or 'source'
   local a,b=source[id] or 0,destination[id] or 0
   facts[tostring(id)]={item=key,source=a,destination=b,expected=expected}
   if a+b>1 then return 'invalid','duplicate fixture ID '..key,facts,source,destination end
   if expected=='source' and b>0 then return 'invalid','nonmatching item moved '..key,facts,source,destination end
   if a+b~=1 or (expected=='destination' and b~=1) then status,reason='pending','awaiting exact location '..key end
  end
 end
 return status,reason,facts,source,destination
end
return Fixture
