package.preload.QueueEquipmentBulk=function() return assert(loadfile(ProjectRoot..'/tests/native_queue/equipment/shared/QueueEquipmentBulk.lua'))() end
local Postprocess=assert(loadfile(ProjectRoot..'/tests/native_queue/equipment/shared/QueueEquipmentPostprocess.lua'))()
local function list(items)
 return {size=function() return #items end,get=function(_,i) return items[i+1] end,
  contains=function(_,item) for _,value in ipairs(items) do if value==item then return true end end return false end}
end
local function container()
 return {items={},getItems=function(self) return list(self.items) end}
end
local nextID=0
local function item(kind,dest)
 nextID=nextID+1
 local value={id=nextID,kind=kind,container=dest,pages=220}
 function value:getID() return self.id end
 function value:getFullType() return self.kind end
 function value:getContainer() return self.container end
 function value:getItemContainer() return self.inside end
 function value:getAlreadyReadPages() return self.pages end
 function value:getNumberOfPages() return 220 end
 function value:getWorldItem() return self.world end
 function value:getAttachedSlot() return self.slot or -1 end
 function value:getAttachedSlotType() return self.slotType end
 function value:getAttachedToModel() return self.model end
 dest.items[#dest.items+1]=value;return value
end
function instanceof(value,kind) return kind=='InventoryContainer' and value.inside~=nil end
local function move(value,dest)
 if value.container then
  for i,entry in ipairs(value.container.items) do if entry==value then table.remove(value.container.items,i);break end end
 end
 value.container=dest;if dest then dest.items[#dest.items+1]=value end
end
local function fixture(id,mode)
 local state={id=id,root=container(),items={},baseline={},original={},originalContainers={},expectedWorn={},originalAttached={}}
 local function seed(name,kind,dest)
  local value=item(kind or name,dest or state.root)
  state[name]=value;state.items[name]=value;state.baseline[value.id]=value;return value
 end
 for _,name in ipairs({'front','tail','hammer','screwdriver','bag'}) do seed(name) end
 state.bag.inside=container();state.source=state.bag.inside;state.expectedWorn.Back=state.bag
 local player={primary=state.hammer,secondary=state.screwdriver,worn=state.expectedWorn,attached={}}
 function player:getInventory() return state.root end
 function player:getPrimaryHandItem() return self.primary end
 function player:getSecondaryHandItem() return self.secondary end
 function player:getAlreadyReadPages() return 220 end
 function player:getWornItems()
  local values={};for _,value in pairs(self.worn) do values[#values+1]=value end
  local result=list(values);result.getItemByIndex=result.get
  function result:getLocation(value) for location,entry in pairs(player.worn) do if entry==value then return location end end end
  return result
 end
 function player:getAttachedItems()
  local values={}
  for location,value in pairs(self.attached) do
   local slot,entry=location,value
   values[#values+1]={getLocation=function() return slot end,getItem=function() return entry end}
  end
  return list(values)
 end
 state.player=player
 local original=item('original',state.root);state.original[original.id]=original;state.originalContainers[original.id]=state.root
 state.baseline[original.id]=original
 player.attached.Unrelated=original;state.originalAttached.Unrelated=original
 if id=='hands-chain' or id=='waiting-cancel' then
  seed('bat',nil,id=='waiting-cancel' and mode=='toolkit' and state.source or state.root);seed('content',nil,state.source)
  if id=='waiting-cancel' and mode=='native' then player.primary,player.secondary=state.bat,state.bat end
 elseif id=='bag-capacity' then
  for i=1,3 do seed('plank'..i,nil,state.source) end
  seed('pickupBag');state.pickupBag.inside=container();state.pickupSource=state.pickupBag.inside
  seed('pickup');player.secondary=state.pickupBag;state.expectedWorn.Back=nil
 elseif id=='clothing-chain' then
  seed('clothingA');seed('clothingB');state.expectedWorn.Socks=state.clothingB
 elseif id=='hotbar-chain' then
  seed('hotbarInitial');seed('hotbarReplacement');state.hotbarLocation='Shovel Back with Bag'
  state.hotbarIndex,state.hotbarType=1,'Back'
  state.hotbarReplacement.slot,state.hotbarReplacement.slotType,state.hotbarReplacement.model=1,'Back',state.hotbarLocation
  player.attached[state.hotbarLocation]=state.hotbarReplacement
 elseif id:match('^bulk') then
  seed('bulkHeavyA',nil,id=='bulk-waiting-cancel' and state.source or state.root)
  for i=1,3 do seed('bulkLight'..i,nil,id=='bulk-waiting-cancel' and state.source or state.root) end
  seed('bulkHeavyB',nil,id=='bulk-waiting-cancel' and state.source or state.root)
  if id=='bulk-mixed' then seed('bulkBorrowed') end
  if id=='bulk-waiting-cancel' then seed('bulkSurvivor') end
 elseif id=='floor-pickup' then
  seed('pickup');state.floor={id=state.pickup.id,x=1,y=2,z=0}
  local square={objects={}};function square:getWorldObjects() return list(self.objects) end
  function getCell() return {getGridSquare=function() return square end} end
  state.pickupWorld={getItem=function() return state.pickup end};state.square=square
 end
 return state
end
local function rejected(state,mode,tidy,reason)
 local ok,problem=pcall(Postprocess.verify,state,mode,tidy)
 assert(not ok and tostring(problem):find(reason,1,true),'missing expected failure '..reason..': '..tostring(problem))
end
for _,id in ipairs({'hands-chain','waiting-cancel','bag-capacity','clothing-chain','hotbar-chain','floor-pickup','bulk-pickup','bulk-waiting-cancel','bulk-mixed'}) do
 local state=fixture(id,'native');assert(Postprocess.verify(state,'native',false).postprocessingVerified)
end
for _,id in ipairs({'hands-chain','clothing-chain'}) do
 local state=fixture(id,'native')
 local value,dest=state.bat or state.pickup or state.clothingA,state.pickupSource or state.source
 move(value,dest);assert(Postprocess.verify(state,'native',true).postprocessingVerified)
 rejected(state,'native',false,'container differs')
end
local capacity=fixture('bag-capacity','native');move(capacity.pickup,capacity.pickupSource)
rejected(capacity,'native',true,'P4 returned deliberately picked up carried item')
local cancelled=fixture('waiting-cancel','toolkit');assert(Postprocess.verify(cancelled,'toolkit',true).postprocessingVerified)
local waiting=fixture('waiting-cancel','native');move(waiting.bat,waiting.source);waiting.player.primary,waiting.player.secondary=nil,nil
rejected(waiting,'native',true,'P4 removed deliberately equipped bat')
local hotbar=fixture('hotbar-chain','native');move(hotbar.hotbarReplacement,hotbar.source);hotbar.player.attached={}
rejected(hotbar,'native',true,'P4 removed deliberately attached hotbar item')
local floor=fixture('floor-pickup','native');local oldPickup=floor.pickup;move(oldPickup,nil)
local restored=item(oldPickup.kind,container());restored.id=oldPickup.id;move(restored,nil)
local world={getItem=function() return restored end,getSquare=function() return floor.square end}
restored.world=world;floor.square.objects={world};floor.owned={oldPickup}
rejected(floor,'native',true,'P4 returned deliberately picked up floor item')
assert(floor.pickup==restored and floor.items.pickup==restored and floor.owned[1]==restored,'restored floor identity was not rebound')
rejected(floor,'native',false,'floor pickup returned without pack')
floor.square.objects={world,world};rejected(floor,'native',true,'duplicate restored floor ID')
floor.square.objects={world};move(floor.pickup,floor.root);rejected(floor,'native',true,'floor pickup duplicated')
local lost=fixture('hands-chain','native');move(lost.content,nil);rejected(lost,'native',false,'lost/replaced inventory ID')
local duplicate=fixture('hands-chain','native');duplicate.source.items[#duplicate.source.items+1]=duplicate.front
rejected(duplicate,'native',false,'duplicate postprocessing inventory ID')
local extra=fixture('hands-chain','native');item('unexpected',extra.root);rejected(extra,'native',false,'unexpected postprocessing inventory ID')
local wrongType=fixture('hands-chain','native');local original=wrongType.content;local replacement=item('wrong',wrongType.source)
move(original,nil);replacement.id=original.id;rejected(wrongType,'native',false,'lost/replaced inventory ID')
local changed=fixture('hands-chain','native');local old=next(changed.original);move(changed.original[old],changed.source)
rejected(changed,'native',false,'postprocessing moved original item')
local book=fixture('hands-chain','native');book.tail.pages=219;rejected(book,'native',false,'book incomplete')
local slots=fixture('hands-chain','native');slots.player.worn={};rejected(slots,'native',false,'worn item changed')
local attachment=fixture('hands-chain','native');attachment.player.attached.Unexpected=attachment.hammer
rejected(attachment,'native',false,'unexpected attachment')
local metadata=fixture('hotbar-chain','native');metadata.hotbarReplacement.slotType=nil
rejected(metadata,'native',false,'postprocessing changed hotbar metadata')
print('Equipment postprocessing: exact identities, deterministic returns, floor restoration and deliberate equipment protection passed.')

local mixed=fixture('bulk-mixed','toolkit');move(mixed.bulkBorrowed,mixed.source)
assert(Postprocess.verify(mixed,'toolkit',true).postprocessingVerified,'borrowed bulk item must return after idle')
move(mixed.bulkLight2,mixed.source)
rejected(mixed,'toolkit',true,'bulk exact source/destination differs bulkLight2')
local bulk=fixture('bulk-pickup','toolkit');move(bulk.bulkHeavyB,bulk.source)
rejected(bulk,'toolkit',true,'bulk exact source/destination differs bulkHeavyB')
local bulkCancel=fixture('bulk-waiting-cancel','toolkit');move(bulkCancel.bulkSurvivor,bulkCancel.source)
rejected(bulkCancel,'toolkit',true,'bulk exact source/destination differs bulkSurvivor')
