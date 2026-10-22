local Fixture={}
local Slots=require 'QueueEquipmentSlots'
local Floor=require 'QueueEquipmentFloor'
local Bulk=require 'QueueEquipmentBulk'
local Clothing=require 'QueueEquipmentClothing'
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
function Fixture.refresh(state)
 if not isClient() and not isServer() then return end
 local actual=inventory(state.player)
 for name,item in pairs(state.items or {}) do
  local live=actual[item:getID()]
  if live then
   assert(live:getFullType()==item:getFullType(),'network fixture ID changed type '..item:getID())
   if live~=item then print('[EQUIPMENT_TEST] REBOUND case='..state.id..' item='..name..' id='..item:getID()) end
   state.items[name],state[name]=live,live
  end
 end
 if state.bag then state.source=state.bag:getItemContainer() end
 if state.pickupBag then state.pickupSource=state.pickupBag:getItemContainer() end
 for _,map in ipairs({state.original or {},state.originalWorn or {},state.expectedWorn or {},state.originalAttached or {}}) do
  for key,item in pairs(map) do if actual[item:getID()] then map[key]=actual[item:getID()] end end
 end
 for i,item in ipairs(state.planks or {}) do state.planks[i]=actual[item:getID()] or item end
 for i,item in ipairs(state.owned or {}) do state.owned[i]=actual[item:getID()] or item end
 for _,key in ipairs({'originalPrimary','originalSecondary'}) do
  if state[key] then state[key]=actual[state[key]:getID()] or state[key] end
 end
end
local function worn(player)
 local result={};local values=player:getWornItems()
 for i=0,values:size()-1 do local item=values:getItemByIndex(i);result[values:getLocation(item)]=item end
 return result
end
-- Host clothing snapshots can replace baseline slots before Prepared reaches the
-- client. Carry the authority's pre-fixture slots instead of inferring them from
-- an already modified client worn list. Inventory IDs/types remain mandatory.
local function originalWorn(player,ids,actual)
 local records=ids.originalWorn
 assert(type(records)=='table' and getmetatable(records)==nil,'missing authoritative original worn slots')
 local count=0
 for key in pairs(records) do
  count=count+1
  assert(type(key)=='number' and key%1==0 and key>=1 and key<=#records,'invalid authoritative worn record index')
 end
 assert(count==#records,'sparse authoritative worn records')
 local owned={};for _,id in pairs(ids.items) do owned[id]=true end
 local result,locations,identities,missing={},{},{},false
 for _,record in ipairs(records) do
  assert(type(record)=='table' and getmetatable(record)==nil,'invalid authoritative worn record')
  for key in pairs(record) do assert(key=='location' or key=='id' or key=='fullType','unexpected authoritative worn field') end
  assert(type(record.location)=='string' and record.location~='' and type(record.id)=='number'
   and record.id%1==0 and type(record.fullType)=='string' and record.fullType~='','invalid authoritative worn identity')
  assert(not locations[record.location] and not identities[record.id] and not owned[record.id],
   'duplicate or fixture-owned authoritative worn identity')
  locations[record.location],identities[record.id]=true,true
  local location=ItemBodyLocation.get(ResourceLocation.of(record.location))
  assert(location and tostring(location)==record.location and player:getBodyLocationGroup():getLocation(location),
   'unknown authoritative worn location '..record.location)
  local item=actual[record.id]
  if item then
   assert(item:getFullType()==record.fullType,'authoritative original worn ID changed type '..record.id)
   result[location]=item
  else missing=true end
 end
 return not missing and result or nil
end
local function sameWorn(player,expected)
 local actual=worn(player)
 for location,item in pairs(expected) do assert(actual[location]==item,'worn identity changed at '..tostring(location)) end
 for location,item in pairs(actual) do assert(expected[location]==item,'unexpected worn item at '..tostring(location)) end
end
function Fixture.relocate(player,point)
 player:teleportTo(math.floor(point.x),math.floor(point.y),point.z)
 player:setX(point.x);player:setY(point.y);player:setZ(point.z)
 player:setLastX(point.x);player:setLastY(point.y);player:setLastZ(point.z);player:setCurrentSquareFromPosition()
end
function Fixture.position(player)
 local origin=player:getCurrentSquare()
 for radius=2,12 do for dx=-radius,radius do for dy=-radius,radius do
  if math.abs(dx)==radius or math.abs(dy)==radius then
   local square=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
   if square and square:isFree(false) and not square:getRoom() and square:getObjects():size()<=1 then
    local x,y,z=square:getX()+0.5,square:getY()+0.5,square:getZ()
    Fixture.relocate(player,{x=x,y=y,z=z})
    return square
   end
  end
 end end end
 error('no clear loaded outdoor equipment fixture square')
end
function Fixture.prepare(player,id,ids,options)
 local root=player:getInventory()
 local actual=inventory(player)
 local baselineWorn=ids and assert(originalWorn(player,ids,actual),'authoritative original worn item not replicated') or worn(player)
 local state={id=id,options=options or {},player=player,root=root,capacity=root:getCapacity(),originalEffectiveCapacity=root:getEffectiveCapacity(player),owned={},original=actual,
  originalContainers={},originalWorn=baselineWorn,originalPrimary=player:getPrimaryHandItem(),originalSecondary=player:getSecondaryHandItem(),items={},ids=ids}
 if ids then
  local owned={};for _,itemID in pairs(ids.items) do owned[itemID]=true end
  for key in pairs(state.original) do if owned[key] then state.original[key]=nil end end
  state.originalPrimary=ids.primary and state.original[ids.primary] or nil
  state.originalSecondary=ids.secondary and state.original[ids.secondary] or nil
 end
 for key,item in pairs(state.original) do state.originalContainers[key]=item:getContainer() end
 local function seed(name,kind,container)
  local item
  if ids then item=inventory(player)[ids.items[name]] else item=(container or root):AddItem(kind) end
  assert(item and item:getFullType()==kind,'missing exact native fixture item '..name)
  assert(item:getContainer()==(container or root),'fixture seed container mismatch '..name)
  if instanceof(item,'InventoryContainer') then item:getItemContainer():setExplored(true) end
  state[name]=item;state.items[name]=item;state.owned[#state.owned+1]=item;return item
 end
 seed('front','Base.BookCarpentry1');seed('tail','Base.BookFirstAid1')
 seed('hammer',id:match('^tidy%-') and 'Base.Torch' or 'Base.Hammer');seed('screwdriver','Base.Screwdriver');seed('bag',Slots.isBelt(id) and 'Base.Bag_ALICEpack_Army' or 'Base.Bag_Schoolbag')
 state.location=state.bag:canBeEquipped();assert(state.location and tostring(state.location)~='','fixture bag has no native worn slot')
 player:setWornItem(state.location,state.bag)
 player:setPrimaryHandItem(state.hammer);player:setSecondaryHandItem(state.screwdriver)
 if not isServer() then getPlayerInventory(player:getPlayerNum()):refreshBackpacks() end
 state.source=state.bag:getItemContainer()
 if not isServer() then assert(ISInventoryPaneContextMenu.getContainers(player):contains(state.source),'native menu cannot see worn fixture bag') end
 if id=='bag-capacity' then
  state.planks={}
  for i=1,3 do state.planks[i]=seed('plank'..i,'Base.Plank',state.source) end
  seed('pickupBag','Base.Bag_Schoolbag')
  player:setSecondaryHandItem(state.pickupBag)
  if not isServer() then getPlayerInventory(player:getPlayerNum()):refreshBackpacks() end
  state.pickupSource=state.pickupBag:getItemContainer()
  seed('pickup','Base.Plank',state.pickupSource)
  assert(state.pickupBag:getID()~=state.bag:getID() and state.pickupSource~=state.source and state.pickupSource~=root,
   'capacity pickup must use a distinct carried bag')
  if not isServer() then assert(ISInventoryPaneContextMenu.getContainers(player):contains(state.pickupSource),'native menu cannot see held source bag') end
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
 elseif id=='tidy-clothing' then Clothing.prepare(state,seed)
 elseif id=='tidy-group' or id=='tidy-multigroup' then
  seed('groupOne','Base.Nails',state.source);seed('groupTwo','Base.Nails',state.source)
  if id=='tidy-multigroup' then
   seed('groupHeavyOne','Base.Hammer',state.source);seed('groupHeavyTwo','Base.Hammer',state.source)
   assert(state.groupHeavyOne:getWeight()>0.1 and state.groupHeavyTwo:getWeight()>0.1,'P4 multi-group requires native heavy items')
  end
  seed('pickup','Base.Pistol',root)
  assert(state.pickup:getCurrentAmmoCount()==0 and not state.pickup:isRoundChambered(),'group rack gun must be empty')
  state.hammer:setUsedDelta(1);state.hammer:setActivated(true)
  assert(state.groupOne:getWeight()<=0.1 and state.groupTwo:getWeight()<=0.1,'P4 group requires native lightweight items')
 elseif id=='hands-chain' or id=='waiting-cancel' then seed('bat','Base.BaseballBat',state.source);seed('content','Base.Nails',state.source)
 elseif Bulk.isCase(id) then Bulk.prepare(state,seed)
 elseif id=='floor-pickup' then Floor.prepare(state,seed)
 elseif id=='tidy-hands' or id=='tidy-floor' or id=='tidy-empty-hands' then
  if id=='tidy-floor' then Floor.prepare(state,seed,'Base.Pistol') else seed('pickup','Base.Pistol',state.source) end
  assert(state.pickup:getCurrentAmmoCount()==0 and not state.pickup:isRoundChambered(),'restore fixture gun must be empty')
  if id=='tidy-empty-hands' then
   player:setPrimaryHandItem(nil);player:setSecondaryHandItem(nil)
  else
   state.hammer:setUsedDelta(1);state.hammer:setActivated(true)
   assert(state.hammer:canBeActivated() and state.hammer:isActivated(),'restore fixture torch must start on')
  end
 else Slots.prepare(state,seed) end
 for _,perk in ipairs({Perks.Woodwork,Perks.Doctor}) do
  player:getXp():setXPToLevel(perk,0);player:setPerkLevelDebug(perk,0)
  assert(player:getPerkLevel(perk)==0,'fixture skill book is ineligible')
 end
 for _,book in ipairs({state.front,state.tail}) do
  assert(book:getNumberOfPages()>1,'fixture requires paged native books')
  book:setAlreadyReadPages(book:getNumberOfPages()-1)
  player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-1)
 end
 if not state.originalAttached then
  state.originalAttached={}
  local attached=player:getAttachedItems()
  for i=0,attached:size()-1 do local entry=attached:get(i);state.originalAttached[tostring(entry:getLocation())]=entry:getItem() end
 end
 state.expectedWorn=worn(player);state.baseline=inventory(player)
 if id=='floor-pickup' or id=='tidy-floor' then state.baseline[state.pickup:getID()]=state.pickup end
 return state
end
function Fixture.verify(state,mode,checkpoint)
 Fixture.refresh(state)
 local player,root=state.player,state.root
 assert(player:getInventory()==root and state.bag:getItemContainer()==state.source,'fixture source/target container identity changed')
 if state.id=='floor-pickup' or state.id=='tidy-floor' then Floor.verify(state,mode) end
 local actual=inventory(player)
 for id,item in pairs(state.baseline) do
  assert(actual[id] and actual[id]:getFullType()==item:getFullType(),'inventory ID missing or changed type '..id)
  assert(isClient() or isServer() or actual[id]==item,'SP inventory object replaced '..id)
 end
 for id in pairs(actual) do assert(state.baseline[id],'unexpected inventory identity '..id) end
 for id,item in pairs(state.original) do assert(item:getContainer()==state.originalContainers[id],'original inventory item moved '..id) end
 for _,book in ipairs(checkpoint and {state.front} or {state.front,state.tail}) do
  assert(book:getAlreadyReadPages()==book:getNumberOfPages(),'native book did not complete '..book:getFullType())
  assert(player:getAlreadyReadPages(book:getFullType())==book:getNumberOfPages(),'character book progress incomplete')
 end
 local cancelled=state.id=='waiting-cancel' and mode=='toolkit'
 local primary,secondary=state.hammer,state.screwdriver
 if state.id=='tidy-hands' or state.id=='tidy-floor' or state.id=='tidy-empty-hands' or (state.id=='tidy-group' or state.id=='tidy-multigroup') then primary,secondary=state.pickup,nil end
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
 elseif state.id=='hands-chain' or state.id=='waiting-cancel' then
  assert(state.bat:getContainer()==(cancelled and state.source or root),'bat reached wrong native container')
  assert(state.content:getContainer()==state.source,'unrelated bag content moved')
  assert(state.source:getItems():size()==(cancelled and 2 or 1),'bag content count differs')
 end
 if (state.id=='tidy-group' or state.id=='tidy-multigroup') then
  for _,item in ipairs({state.groupOne,state.groupTwo,state.groupHeavyOne,state.groupHeavyTwo}) do
   assert(item:getContainer()==root,'borrowed group did not reach root before unrelated tail')
  end
 end
 local extra={}
 if Bulk.isCase(state.id) then extra=Bulk.verify(state,false,false) end
 if Slots.handles(state.id) then extra=Slots.verify(state,mode) end
 local expectedWorn=state.expectedWorn
 if state.id=='tidy-clothing' then
  extra.clothingCheckpoint=Clothing.verify(state,false)
  extra.clothingItem=state.clothingSocks:getID()
  expectedWorn={};for location,item in pairs(state.expectedWorn)do expectedWorn[location]=item end
  expectedWorn[state.clothingLocation]=nil
 end
 assert(state.bag:getContainer()==root,'carried source bag changed container');sameWorn(player,expectedWorn)
 local outcome={inventoryPreserved=true,frontCompleted=true,tailCompleted=not checkpoint,equipmentMatches=true,nativeDurations=true,
  policyChecked=mode=='toolkit',cancelled=cancelled,capacityBarrier=state.id=='bag-capacity' and mode=='toolkit',
  primary=primary:getID(),secondary=secondary and secondary:getID() or false,bag=state.bag:getID(),front=state.front:getID(),tail=state.tail:getID(),
  capacity=state.effectiveCapacity,weightBefore=state.weightBefore,weightAfterReplacement=state.weightAfterRemoval}
 for key,value in pairs(extra) do outcome[key]=value end
 if state.id=='floor-pickup' then outcome.floorPickup=true;outcome.pickupWorldRemoved=true end
 return outcome
end
function Fixture.release(state)
 Fixture.refresh(state)
 local player=state.player
 if Slots.handles(state.id) then Slots.cleanup(state) end
 for _,item in ipairs(state.owned) do player:removeFromHands(item);player:removeWornItem(item) end
 if state.belt then
  local location=state.belt:getBodyLocation()
  local current=player:getWornItem(location)
  -- Replication may leave a distinct worn object after its inventory identity was removed.
  if current and current:getID()==state.belt:getID() then player:setWornItem(location,nil) end
  if isServer() then sendClothing(player,location,state.originalWorn[location]) end
 end
 for location,item in pairs(state.originalWorn) do player:setWornItem(location,item) end
 player:setPrimaryHandItem(state.originalPrimary);player:setSecondaryHandItem(state.originalSecondary)
 -- Close both bag views while authoritative containers still exist.
 if not isServer() then
  local number=player:getPlayerNum()
  for _,view in ipairs({{getPlayerInventory(number),state.root},{getPlayerLoot(number),ISInventoryPage.GetFloorContainer(number)}}) do
   local page,target=view[1],view[2]
   for _,item in ipairs(state.owned) do
    if instanceof(item,'InventoryContainer') and page.forceSelectedContainer==item:getItemContainer() then page:setForceSelectedContainer(nil) end
   end
   page:setNewContainer(target);page:refreshBackpacks()
   assert(page.inventoryPane.inventory==target,'fixture UI retained a removed container')
  end
 end
end
function Fixture.removed(state)
 local actual=inventory(state.player)
 for _,item in ipairs(state.owned) do if actual[item:getID()] then return false end end
 if state.belt then
  local current=state.player:getWornItem(state.belt:getBodyLocation())
  if current and current:getID()==state.belt:getID() then return false end
 end
 if (state.id=='floor-pickup' or state.id=='tidy-floor') and Floor.resolve(state.floor) then return false end
 return true
end
function Fixture.transactionsSettled()
 if isServer() then
  assert(type(equipmentNativeTransferCount)=='function','native transfer probe unavailable')
  local pending=equipmentNativeTransferCount()
  assert(type(pending)=='number' and pending>=0,'native transfer probe unsupported')
  return pending==0
 end
 -- This isolated fixture has one player; native byte IDs cover its whole transfer manager.
 for id=-128,127 do if id~=0 and not isItemTransactionDone(id) then return false end end
 return true
end
function Fixture.cleanup(state)
 Fixture.release(state)
 local player=state.player
 if state.id=='floor-pickup' or state.id=='tidy-floor' then Floor.cleanup(state) end
 local actualBefore=inventory(player)
 for i=#state.owned,1,-1 do
  local original=state.owned[i]
  local item=actualBefore[original:getID()] or original
  local container=item:getContainer();if container then container:Remove(item);if isServer() and container==state.root then sendRemoveItemFromContainer(container,item) end end
 end
 state.root:setCapacity(state.capacity)
 assert(state.root:getEffectiveCapacity(player)==state.originalEffectiveCapacity,'native root capacity restore failed')
 if not isServer() then getPlayerInventory(player:getPlayerNum()):refreshBackpacks() end
 local actual=inventory(player)
 for id,item in pairs(state.original) do assert(actual[id]==item,'original inventory lost during fixture cleanup') end
 for id in pairs(actual) do assert(state.original[id],'fixture item survived exact cleanup') end
 sameWorn(player,state.originalWorn)
end
function Fixture.descriptor(state)
 local result={case=state.id,items={},originalWorn={},primary=state.originalPrimary and state.originalPrimary:getID(),
  secondary=state.originalSecondary and state.originalSecondary:getID(),floor=state.floor,clothingHair=state.clothingHair}
 for name,item in pairs(state.items) do result.items[name]=item:getID() end
 for location,item in pairs(state.originalWorn) do
  result.originalWorn[#result.originalWorn+1]={location=tostring(location),id=item:getID(),fullType=item:getFullType()}
 end
 table.sort(result.originalWorn,function(a,b)return a.location<b.location end)
 return result
end
function Fixture.available(player,ids)
 local actual=inventory(player)
 if not originalWorn(player,ids,actual) then return false end
 if ids.case=='tidy-clothing'and not Clothing.available(player,ids)then return false end
 for name,id in pairs(ids.items) do
  if name~='pickup' or not ids.floor then if not actual[id] then return false end end
 end
 return not ids.floor or Floor.resolve(ids.floor)~=nil
end
function Fixture.settled(state,mode,checkpoint)
 Fixture.refresh(state)
 local player=state.player
 local cancelled=state.id=='waiting-cancel' and mode=='toolkit'
 local primary,secondary=state.hammer,state.screwdriver
 if state.id=='tidy-hands' or state.id=='tidy-floor' or state.id=='tidy-empty-hands' or (state.id=='tidy-group' or state.id=='tidy-multigroup') then primary,secondary=state.pickup,nil end
 if state.id=='waiting-cancel' and not cancelled then primary,secondary=state.bat,state.bat end
 if state.id=='bag-capacity' then secondary=state.pickupBag end
 if player:getPrimaryHandItem()~=primary or player:getSecondaryHandItem()~=secondary then return false end
 for _,book in ipairs(checkpoint and {state.front} or {state.front,state.tail}) do if book:getAlreadyReadPages()~=book:getNumberOfPages() then return false end end
 if state.bat and state.bat:getContainer()~=(cancelled and state.source or state.root) then return false end
 if state.pickup and state.pickup:getContainer()~=state.root then return false end
 if state.id=='tidy-group' or state.id=='tidy-multigroup' then
  for _,item in ipairs({state.groupOne,state.groupTwo,state.groupHeavyOne,state.groupHeavyTwo}) do if item:getContainer()~=state.root then return false end end
 end
 if Bulk.isCase(state.id) then
  for name,item in pairs(state.items) do
   if name:match('^bulk') and item:getContainer()~=Bulk.container(state,name,false,false) then return false end
  end
 end
 if state.id=='clothing-chain' and player:getWornItem(state.clothingLocation)~=state.clothingB then return false end
 if state.id=='tidy-clothing' and (player:getWornItem(state.clothingLocation)~=nil
  or tostring(player:getHumanVisual():getHairModel())~=state.clothingHair)then return false end
 if state.id=='hotbar-chain' or Slots.isBelt(state.id) then
  local item,old=state.hotbarReplacement,state.hotbarInitial
  -- Native attachment and item-field packets use separate channels.
  if player:getAttachedItems():getItem(state.hotbarLocation)~=item or item:getAttachedSlot()~=state.hotbarIndex
   or item:getAttachedSlotType()~=state.hotbarType or item:getAttachedToModel()~=state.hotbarLocation
   or old and (old:getAttachedSlot()~=-1 or (old:getAttachedSlotType()~=nil and old:getAttachedSlotType()~='')
   or (old:getAttachedToModel()~=nil and old:getAttachedToModel()~='')) then return false end
 end
 return true
end
return Fixture
