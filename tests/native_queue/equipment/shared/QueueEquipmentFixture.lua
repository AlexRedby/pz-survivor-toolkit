local Fixture={}
local function inventory(player)
 local result={}
 local function scan(container)
  local items=container:getItems()
  for i=0,items:size()-1 do
   local item=items:get(i);local id=item:getID()
   assert(not result[id],'duplicate inventory identity '..id);result[id]=item
   if instanceof(item,'InventoryContainer') then scan(item:getItemContainer()) end
  end
 end
 scan(player:getInventory());return result
end
local function worn(player)
 local result={};local values=player:getWornItems()
 for i=0,values:size()-1 do local item=values:getItemByIndex(i);result[values:getLocation(item)]=item end
 return result
end
local function sameWorn(player,expected)
 local actual=worn(player)
 for location,item in pairs(expected) do assert(actual[location]==item,'worn identity changed at '..tostring(location)) end
 for location,item in pairs(actual) do assert(expected[location]==item,'unexpected worn item at '..tostring(location)) end
end
function Fixture.position(player)
 local origin=player:getCurrentSquare()
 for radius=2,12 do for dx=-radius,radius do for dy=-radius,radius do
  if math.abs(dx)==radius or math.abs(dy)==radius then
   local square=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
   if square and square:isFree(false) and not square:getRoom() and square:getObjects():size()<=1 then
    local x,y,z=square:getX()+0.5,square:getY()+0.5,square:getZ()
    player:teleportTo(math.floor(x),math.floor(y),z);player:setX(x);player:setY(y);player:setZ(z)
    player:setLastX(x);player:setLastY(y);player:setLastZ(z);player:setCurrentSquareFromPosition()
    return square
   end
  end
 end end end
 error('no clear loaded outdoor equipment fixture square')
end
function Fixture.prepare(player,id)
 local root=player:getInventory()
 local state={id=id,player=player,root=root,capacity=root:getCapacity(),originalEffectiveCapacity=root:getEffectiveCapacity(player),owned={},original=inventory(player),
  originalContainers={},originalWorn=worn(player),originalPrimary=player:getPrimaryHandItem(),originalSecondary=player:getSecondaryHandItem()}
 for key,item in pairs(state.original) do state.originalContainers[key]=item:getContainer() end
 local function seed(name,kind,container)
  local item=assert((container or root):AddItem(kind),'missing native fixture item '..kind)
  state[name]=item;state.owned[#state.owned+1]=item;return item
 end
 seed('front','Base.BookCarpentry1');seed('tail','Base.BookFirstAid1')
 seed('hammer','Base.Hammer');seed('screwdriver','Base.Screwdriver');seed('bag','Base.Bag_Schoolbag')
 state.location=state.bag:canBeEquipped();assert(state.location and tostring(state.location)~='','fixture bag has no native worn slot')
 player:setWornItem(state.location,state.bag)
 player:setPrimaryHandItem(state.hammer);player:setSecondaryHandItem(state.screwdriver)
 getPlayerInventory(player:getPlayerNum()):refreshBackpacks()
 state.source=state.bag:getItemContainer()
 assert(ISInventoryPaneContextMenu.getContainers(player):contains(state.source),'native menu cannot see worn fixture bag')
 if id=='bag-capacity' then
  state.planks={}
  for i=1,3 do state.planks[i]=seed('plank'..i,'Base.Plank',state.source) end
  seed('pickupBag','Base.Bag_Schoolbag')
  player:setSecondaryHandItem(state.pickupBag)
  getPlayerInventory(player:getPlayerNum()):refreshBackpacks()
  state.pickupSource=state.pickupBag:getItemContainer()
  seed('pickup','Base.Plank',state.pickupSource)
  assert(state.pickupBag:getID()~=state.bag:getID() and state.pickupSource~=state.source and state.pickupSource~=root,
   'capacity pickup must use a distinct carried bag')
  assert(ISInventoryPaneContextMenu.getContainers(player):contains(state.pickupSource),'native menu cannot see held source bag')
  assert(state.pickup:getContainer()==state.pickupSource and state.pickupSource:contains(state.pickup),'exact carried pickup source missing')
  player:removeWornItem(state.bag,false);player:setPrimaryHandItem(state.bag)
  state.weightBefore=root:getCapacityWeight()
  root:setCapacity(math.ceil(state.weightBefore+state.pickup:getUnequippedWeight())+1)
  state.effectiveCapacity=root:getEffectiveCapacity(player)
  assert(root:hasRoomFor(player,state.pickup),'pickup must fit before native bag removal')
  player:setPrimaryHandItem(state.hammer)
  state.weightAfterRemoval=root:getCapacityWeight()
  local fitsAfterRemoval=root:hasRoomFor(player,state.pickup)
  player:setPrimaryHandItem(state.bag)
  assert(player:getPrimaryHandItem()==state.bag and not player:getWornItem(state.location) and math.abs(root:getCapacityWeight()-state.weightBefore)<0.001,
   'native owned bag probe did not restore exact hand state/weight')
  state.removalDelta=state.weightAfterRemoval-state.weightBefore
  assert(state.removalDelta>2,'native bag reduction must materially affect carried weight')
  assert(not fitsAfterRemoval,'pickup would still fit after native bag removal')
  assert(root:hasRoomFor(player,state.pickup),'pickup must fit again after native hand state restore')
 else seed('bat','Base.BaseballBat',state.source);seed('content','Base.Nails',state.source) end
 for _,perk in ipairs({Perks.Woodwork,Perks.Doctor}) do
  player:getXp():setXPToLevel(perk,0);player:setPerkLevelDebug(perk,0)
  assert(player:getPerkLevel(perk)==0,'fixture skill book is ineligible')
 end
 for _,book in ipairs({state.front,state.tail}) do
  assert(book:getNumberOfPages()>1,'fixture requires paged native books')
  book:setAlreadyReadPages(book:getNumberOfPages()-1)
  player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-1)
 end
 state.expectedWorn=worn(player);state.baseline=inventory(player)
 return state
end
function Fixture.verify(state,mode)
 local player,root=state.player,state.root
 assert(player:getInventory()==root and state.bag:getItemContainer()==state.source,'fixture source/target container identity changed')
 local actual=inventory(player)
 for id,item in pairs(state.baseline) do assert(actual[id]==item,'inventory identity lost/replaced '..id) end
 for id in pairs(actual) do assert(state.baseline[id],'unexpected inventory identity '..id) end
 for id,item in pairs(state.original) do assert(item:getContainer()==state.originalContainers[id],'original inventory item moved '..id) end
 for _,book in ipairs({state.front,state.tail}) do
  assert(book:getAlreadyReadPages()==book:getNumberOfPages(),'native book did not complete '..book:getFullType())
  assert(player:getAlreadyReadPages(book:getFullType())==book:getNumberOfPages(),'character book progress incomplete')
 end
 local cancelled=state.id=='waiting-cancel' and mode=='toolkit'
 local primary,secondary=state.hammer,state.screwdriver
 if state.id=='waiting-cancel' and not cancelled then primary,secondary=state.bat,state.bat end
 if state.id=='bag-capacity' then secondary=state.pickupBag end
 assert(player:getPrimaryHandItem()==primary and player:getSecondaryHandItem()==secondary,'native final hand identities differ')
 if state.id=='bag-capacity' then
  state.expectedWorn[state.location]=nil
  assert(state.pickup:getContainer()==root and not state.pickup:getWorldItem(),'carried pickup did not reach exact root inventory')
  assert(state.pickupBag:getContainer()==root and state.pickupBag:getItemContainer()==state.pickupSource
   and state.pickupSource:getItems():isEmpty(),'exact held source bag must remain carried and empty')
  for _,item in ipairs(state.planks) do assert(item:getContainer()==state.source,'bag content identity/container changed') end
  assert(root:getCapacityWeight()>state.weightBefore+state.pickup:getUnequippedWeight(),'bag removal did not increase root encumbrance')
  assert(root:getCapacityWeight()>state.effectiveCapacity,'native safe original order must finish above pickup capacity')
 else
  assert(state.bat:getContainer()==(cancelled and state.source or root),'bat reached wrong native container')
  assert(state.content:getContainer()==state.source,'unrelated bag content moved')
  assert(state.source:getItems():size()==(cancelled and 2 or 1),'bag content count differs')
 end
 assert(state.bag:getContainer()==root,'carried source bag changed container');sameWorn(player,state.expectedWorn)
 return {inventoryPreserved=true,frontCompleted=true,tailCompleted=true,equipmentMatches=true,nativeDurations=true,
  policyChecked=mode=='toolkit',cancelled=cancelled,capacityBarrier=state.id=='bag-capacity' and mode=='toolkit',
  primary=primary:getID(),secondary=secondary:getID(),bag=state.bag:getID(),front=state.front:getID(),tail=state.tail:getID(),
  capacity=state.effectiveCapacity,weightBefore=state.weightBefore,weightAfterReplacement=state.weightAfterRemoval}
end
function Fixture.cleanup(state)
 local player=state.player
 for _,item in ipairs(state.owned) do player:removeFromHands(item);player:removeWornItem(item) end
 for i=#state.owned,1,-1 do
  local item=state.owned[i]
  local container=item:getContainer();if container then container:Remove(item) end
 end
 for location,item in pairs(state.originalWorn) do player:setWornItem(location,item) end
 player:setPrimaryHandItem(state.originalPrimary);player:setSecondaryHandItem(state.originalSecondary)
 state.root:setCapacity(state.capacity)
 assert(state.root:getEffectiveCapacity(player)==state.originalEffectiveCapacity,'native root capacity restore failed')
 getPlayerInventory(player:getPlayerNum()):refreshBackpacks()
 local actual=inventory(player)
 for id,item in pairs(state.original) do assert(actual[id]==item,'original inventory lost during fixture cleanup') end
 for id in pairs(actual) do assert(state.original[id],'fixture item survived exact cleanup') end
 sameWorn(player,state.originalWorn)
end
return Fixture
