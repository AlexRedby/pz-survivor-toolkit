local Retention=require 'PZSurvivorToolkit/ItemRetention'
local F={module='TorchRefillTest'}
local cases={['trunk-retained']=true,['root-retained']=true,['trunk-unmarked']=true}
local function visit(container,fn)
 local items=container:getItems()
 for index=0,items:size()-1 do
  local item=items:get(index);fn(item,container)
  if instanceof(item,'InventoryContainer')then visit(item:getInventory(),fn)end
 end
end
local function inventory(container)
 local result={};visit(container,function(item,pool)result[item:getID()]={item=item,pool=pool,retained=Retention.isRetained(item),
  uses=instanceof(item,'DrainableComboItem')and item:getCurrentUsesFloat()or nil}end);return result
end
local function vehicleContainers(vehicle)
 local pools={}
 for index=0,vehicle:getPartCount()-1 do
  local pool=vehicle:getPartByIndex(index):getItemContainer()
  if pool then pools[#pools+1]=pool end
 end
 return pools
end
local function generatedPresent(vehicle,player,ids)
 local pools={player:getInventory()}
 if vehicle then for _,pool in ipairs(vehicleContainers(vehicle))do pools[#pools+1]=pool end end
 for _,pool in ipairs(pools)do
  for _,id in ipairs(ids)do if pool:getItemWithIDRecursiv(id)then return true end end
 end
 return false
end
local function removeGenerated(vehicle)
 -- Creation grants ownership of the truck and its initial generated contents only.
 -- Snapshot every exact ID/ref before removing anything, including children before bags.
 local owned,ids={},{}
 local pools=vehicleContainers(vehicle)
 for _,pool in ipairs(pools)do
  pool:setExplored(true)
  visit(pool,function(item,parent)
   owned[#owned+1]={item=item,pool=parent,id=item:getID()};ids[#ids+1]=item:getID()
  end)
 end
 for index=#owned,1,-1 do
  local entry=owned[index]
  assert(entry.item:getID()==entry.id and entry.item:getContainer()==entry.pool and entry.pool:contains(entry.item),'generated ownership changed during preparation')
  entry.pool:Remove(entry.item)
  if isServer()then sendRemoveItemFromContainer(entry.pool,entry.item)end
  assert(not entry.pool:contains(entry.item),'generated item removal failed')
 end
 for _,entry in ipairs(owned)do assert(not entry.pool:contains(entry.item),'generated item survived preparation')end
 return ids,pools
end
local function truck(player)
 local px,py=math.floor(player:getX()),math.floor(player:getY())
 local spot
 for radius=4,48 do
  for dx=-radius,radius do for dy=-radius,radius do
   if not spot and(math.abs(dx)==radius or math.abs(dy)==radius)then
    local x,y=px+dx,py+dy;local clear=true
    for ox=-6,6 do for oy=-6,6 do
     local square=getCell():getGridSquare(x+ox,y+oy,0)
     if math.abs(ox)<=3 and math.abs(oy)<=3 and(not square or not square:isOutside()or not square:isFree(false))then clear=false end
     if square then local moving=square:getMovingObjects()
      for i=0,moving:size()-1 do if instanceof(moving:get(i),'BaseVehicle')then clear=false end end
     end
    end end
    if clear then spot=getCell():getGridSquare(x,y,0)end
   end
  end end
  if spot then break end
 end
 assert(spot,'no clear truck spawn square')
 local vehicle=assert(addVehicleDebug('Base.PickUpVan',IsoDirections.N,nil,spot))
 assert(vehicle:getSquare(),'native truck placement rejected')
 if isServer()then assert(vehicle:getId()>=0,'truck has no network ID')end
 local generated,pools=removeGenerated(vehicle)
 local source=assert(vehicle:getPartById('TruckBed'):getItemContainer())
 local door=vehicle:getPartById('TrunkDoor')
 if door and door:getDoor()then
  door:getDoor():setLocked(false);door:getDoor():setOpen(true)
  if isServer()then vehicle:transmitPartDoor(door)end
 end
 return vehicle,source,generated,pools
end
function F.prepare(player,case,epoch)
 assert(cases[case]and type(epoch)=='number','invalid fixture phase')
 local state={player=player,case=case,epoch=epoch,retained=case~='trunk-unmarked',baseline=inventory(player:getInventory()),generatedIDs={}}
 local source=player:getInventory()
 if case~='root-retained'then state.vehicle,source,state.generatedIDs,state.vehicleContainers=truck(player)end
 state.source=source;state.sourceBaseline=inventory(source)
 state.torch=assert(source:AddItem('Base.BlowTorch'));state.tank=assert(source:AddItem('Base.PropaneTank'))
 state.torch:setCurrentUses(1);state.tank:setCurrentUses(state.tank:getMaxUses())
 Retention.apply(state.torch,state.retained)
 state.sourceID,state.tankID=state.torch:getID(),state.tank:getID()
 state.torchBefore,state.tankBefore=state.torch:getCurrentUses(),state.tank:getCurrentUses()
 state.torchMax,state.tankMax=state.torch:getMaxUses(),state.tank:getMaxUses()
 -- B42.21 native refillBlowtorchPropaneAmount is 70; retain native duration/fuel logic.
 local full=state.torchMax*70;local held=state.torch:getCurrentUsesFloat()*full
 local added=math.min(full-held,state.tankBefore)
 state.expectedTorchFloat=(held+added)/full;state.expectedTankUses=math.floor(state.tankBefore-added+.5)
 local area=state.vehicle and state.vehicle:getAreaCenter(state.vehicle:getPartById('TruckBed'):getArea())
 state.packet={case=case,epoch=epoch,sourceID=state.sourceID,tankID=state.tankID,
  torchBefore=state.torchBefore,tankBefore=state.tankBefore,torchMax=state.torchMax,tankMax=state.tankMax,
  expectedTorchFloat=state.expectedTorchFloat,expectedTankUses=state.expectedTankUses,
  truckId=state.vehicle and state.vehicle:getId()or -1,generatedIDs=state.generatedIDs,
  x=area and area:getX()or player:getX(),y=area and area:getY()or player:getY()}
 if isServer()then
  if state.vehicle then
   for _,pool in ipairs(state.vehicleContainers)do sendItemsInContainer(state.vehicle,pool)end
  else sendAddItemToContainer(source,state.torch);sendAddItemToContainer(source,state.tank)end
 end
 return state
end
function F.resolve(packet,player,baseline,localState)
 local source=player:getInventory();local vehicle
 if packet.case~='root-retained'then
  vehicle=localState and localState.vehicle or getVehicleById(packet.truckId)
  local part=vehicle and vehicle:getPartById('TruckBed');source=part and part:getItemContainer()
 end
 if not source then return end
 if generatedPresent(vehicle,player,packet.generatedIDs)then return end
 local torch,tank=source:getItemById(packet.sourceID),source:getItemById(packet.tankID)
 if not torch or not tank then return end
 return {player=player,source=source,vehicle=vehicle,packet=packet,case=packet.case,epoch=packet.epoch,
  baseline=baseline,sourceBaseline={},torch=torch,tank=tank,retained=packet.case~='trunk-unmarked',sourceID=packet.sourceID,tankID=packet.tankID,
  torchBefore=packet.torchBefore,tankBefore=packet.tankBefore,torchMax=packet.torchMax,tankMax=packet.tankMax,
  expectedTorchFloat=packet.expectedTorchFloat,expectedTankUses=packet.expectedTankUses}
end
function F.receipt(state)
 local root,source=state.player:getInventory(),state.source
 if state.torch and state.torch:getWorldItem()and state.torch:getWorldItem():getSquare()then return nil,'old torch remains on ground'end
 local pools=source==root and {root}or {source,root};local outputs={};local tank
 for _,pool in ipairs(pools)do
  if pool:getItemWithIDRecursiv(state.sourceID)then return nil,'old torch still exists'end
  visit(pool,function(item)
   if item:getID()==state.tankID then tank=item end
   if item:getFullType()=='Base.BlowTorch'and not state.baseline[item:getID()]and not state.sourceBaseline[item:getID()]then outputs[#outputs+1]=item end
  end)
 end
 if #outputs~=1 or not tank then return nil,'exact torch/tank identities unresolved'end
 local output=outputs[1]
 if output:getContainer()~=source or tank:getContainer()~=source then return nil,'items not returned'end
 if output:getID()==state.sourceID then return nil,'identity mismatch'end
 if Retention.isRetained(output)~=state.retained then return nil,'retention mismatch'end
 if math.abs(output:getCurrentUsesFloat()-state.expectedTorchFloat)>.0001 or tank:getCurrentUses()~=state.expectedTankUses then return nil,'exact native fuel mismatch'end
 state.output=output;state.outputID=output:getID();state.tank=tank
 return {case=state.case,epoch=state.epoch,sourceID=state.sourceID,outputID=output:getID(),tankID=tank:getID(),
  retained=Retention.isRetained(output),sourceRemoved=true,returned=true,tankReturned=true,fuelExact=true,conserved=true,
  torchUses=output:getCurrentUses(),tankUses=tank:getCurrentUses(),torchBefore=state.torchBefore,tankBefore=state.tankBefore}
end
function F.baseline(player)return inventory(player:getInventory())end
function F.unchanged(player,baseline)
 local actual=inventory(player:getInventory())
 for id,entry in pairs(baseline)do
  local value=actual[id]
  assert(value and value.pool==entry.pool and value.retained==entry.retained and value.uses==entry.uses,'unrelated inventory changed ID='..id)
 end
 for id in pairs(actual)do assert(baseline[id],'unexpected inventory item after cleanup ID='..id)end
 return true
end
function F.remove(state)
 assert(F.receipt(state),'authority effect unavailable at cleanup')
 assert(not generatedPresent(state.vehicle,state.player,state.generatedIDs),'generated item returned after preparation')
 local receipt={case=state.case,epoch=state.epoch,generatedIDs=state.generatedIDs,items={state.sourceID,state.tankID,state.outputID},vehicle=state.packet.truckId,hasVehicle=state.vehicle~=nil}
 -- Preflight all contents before any removal; foreign items quarantine the phase intact.
 if state.vehicle then
  assert(not state.vehicle:getVehicleTowing()and not state.vehicle:getVehicleTowedBy(),'foreign towing attachment on fixture truck')
  for index=0,state.vehicle:getMaxPassengers()-1 do assert(not state.vehicle:getCharacter(index),'foreign passenger in fixture truck')end
  for index=0,state.vehicle:getPartCount()-1 do
   local pool=state.vehicle:getPartByIndex(index):getItemContainer()
   if pool then visit(pool,function(item)assert(item:getID()==state.outputID or item:getID()==state.tankID,'foreign item in fixture truck')end)end
  end
 end
 for _,item in ipairs({state.output,state.tank})do
  local pool=assert(item:getContainer(),'owned item container missing');state.player:removeFromHands(item)
  pool:Remove(item);if isServer()then sendRemoveItemFromContainer(pool,item)end
  assert(not pool:contains(item),'owned item removal failed')
 end
 if state.vehicle then
  state.vehicle:permanentlyRemove();assert(not getCell():getVehicles():contains(state.vehicle),'owned truck removal failed')
 end
 F.unchanged(state.player,state.baseline)
 return receipt
end
function F.clean(receipt,state,baseline)
 assert(receipt.case==state.case and receipt.epoch==state.epoch,'wrong cleanup phase')
 assert(type(receipt.generatedIDs)=='table'and #receipt.generatedIDs==#state.packet.generatedIDs,'missing generated ownership receipt')
 for index,id in ipairs(state.packet.generatedIDs)do assert(receipt.generatedIDs[index]==id,'generated ownership receipt differs')end
 if generatedPresent(state.vehicle,state.player,receipt.generatedIDs)then return false,'generated item still replicated'end
 if receipt.hasVehicle and((receipt.vehicle>=0 and getVehicleById(receipt.vehicle))or getCell():getVehicles():contains(state.vehicle))then return false,'owned truck still replicated'end
 for _,id in ipairs(receipt.items)do
  if state.player:getInventory():getItemWithIDRecursiv(id)or state.source:getItemWithIDRecursiv(id)then return false,'owned item still replicated'end
 end
 F.unchanged(state.player,baseline);return true
end
local function copy(values)
 local result={};for key,value in pairs(values or {})do result[key]=value end;return result
end
local function paneRows(pane)
 local rows={}
 for _,group in ipairs(pane.itemslist or {})do
  rows[#rows+1]={item=group.items[1],group=true}
  if not pane.collapsed[group.name]then
   for index=2,#group.items do rows[#rows+1]={item=group.items[index],group=false}end
  end
 end
 return rows
end
local function selection(pane)
 local result=pane:saveSelection({})
 -- Native restoreSelection uses a raw item for a selected header; preserve that header on the next refresh too.
 for row,entry in ipairs(paneRows(pane))do
  if entry.group and pane.selected[row]then result[entry.item]='group'end
 end
 return result
end
local function anchor(rows,index)
 return {index=index,row=index and rows[index]or nil}
end
local function restoreAnchor(rows,saved)
 if not saved.row then return saved.index end
 for index,row in ipairs(rows)do
  if row.item==saved.row.item and row.group==saved.row.group then return index end
 end
 error('inventory selection anchor lost')
end
local function restorePane(entry)
 local page,pane=entry.page,entry.page.inventoryPane
 -- Refresh can rebuild rows and wipe selected in place. Never reuse its mutable selection table.
 page.forceSelectedContainer=nil;page.forceSelectedContainerTime=nil
 pane.inventory=entry.inventory;pane.lastinventory=entry.last;pane.collapsed=copy(entry.collapsed)
 page:refreshBackpacks()
 pane.inventory=entry.inventory;pane.lastinventory=entry.last;page.inventory=entry.inventory
 pane:refreshContainer()
 pane.selected={};pane:restoreSelection(entry.selected)
 local actual=selection(pane)
 for item in pairs(entry.selected)do assert(actual[item],'inventory selection lost')end
 for item in pairs(actual)do assert(entry.selected[item],'unexpected inventory selection')end
 local rows=paneRows(pane)
 pane.firstSelect=restoreAnchor(rows,entry.firstSelect)
 local joy=restoreAnchor(rows,entry.joyselection);pane.joyselection=joy and joy-1 or nil
 pane:setYScroll(entry.yScroll);pane.smoothScrollTargetY=entry.smoothScrollTargetY
 page.title=entry.title;page.capacity=entry.capacity
 page.forceSelectedContainer=entry.forced;page.forceSelectedContainerTime=entry.forcedTime;page:setVisible(entry.visible)
 assert(pane.inventory==entry.inventory and pane.lastinventory==entry.last,'inventory container restore failed')
 for key,value in pairs(entry.collapsed)do assert(pane.collapsed[key]==value,'inventory collapse restore failed')end
end
function F.clientBaseline(player)
 local state={player=player,items=F.baseline(player),x=player:getX(),y=player:getY(),z=player:getZ(),
  primary=player:getPrimaryHandItem(),secondary=player:getSecondaryHandItem(),pages={}}
 for _,page in ipairs({getPlayerInventory(0),getPlayerLoot(0)})do
  local pane=page.inventoryPane;local rows=paneRows(pane)
  state.pages[#state.pages+1]={page=page,inventory=pane.inventory,last=pane.lastinventory,
   selected=selection(pane),collapsed=copy(pane.collapsed),firstSelect=anchor(rows,pane.firstSelect),
   joyselection=anchor(rows,pane.joyselection and pane.joyselection+1),yScroll=pane:getYScroll(),smoothScrollTargetY=pane.smoothScrollTargetY,
   forced=page.forceSelectedContainer,forcedTime=page.forceSelectedContainerTime,
   visible=page:getIsVisible(),title=page.title,capacity=page.capacity}
 end
 return state
end
function F.restore(state)
 local player=state.player
 local equipmentChanged=player:getPrimaryHandItem()~=state.primary or player:getSecondaryHandItem()~=state.secondary
 player:setPrimaryHandItem(state.primary);player:setSecondaryHandItem(state.secondary)
 if isClient()and equipmentChanged then player:updateHandEquips()end
 player:teleportTo(state.x,state.y,state.z);player:setX(state.x);player:setY(state.y)
 player:setNextX(state.x);player:setNextY(state.y);player:setLastX(state.x);player:setLastY(state.y)
 for _,entry in ipairs(state.pages)do restorePane(entry)end
 assert(player:getPrimaryHandItem()==state.primary and player:getSecondaryHandItem()==state.secondary,'equipment restore failed')
 assert(math.abs(player:getX()-state.x)<.001 and math.abs(player:getY()-state.y)<.001 and player:getZ()==state.z,'position restore failed')
 return true
end
return F
