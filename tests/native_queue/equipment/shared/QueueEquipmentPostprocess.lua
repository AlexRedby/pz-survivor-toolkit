local Postprocess={}
local function same(item,expected)
 return item==nil and expected==nil or item~=nil and expected~=nil
  and item:getID()==expected:getID() and item:getFullType()==expected:getFullType()
end
local function inventory(container,result)
 local items=container:getItems()
 for i=0,items:size()-1 do
  local item=items:get(i);local id=item:getID()
  assert(not result[id],'duplicate postprocessing inventory ID '..id);result[id]=item
  if instanceof(item,'InventoryContainer') then inventory(item:getItemContainer(),result) end
 end
 return result
end
local function sameSlots(actual,expected,kind)
 for location,item in pairs(expected) do assert(same(actual[location],item),kind..' changed at '..tostring(location)) end
 for location,item in pairs(actual) do assert(same(item,expected[location]),'unexpected '..kind..' at '..tostring(location)) end
end
function Postprocess.verify(state,mode,tidy)
 assert(mode=='native' or mode=='toolkit','invalid postprocessing mode')
 assert(type(tidy)=='boolean','postprocessing pack behavior must be explicit')
 local player,root=state.player,state.root
 assert(player:getInventory()==root and state.bag:getItemContainer()==state.source,'postprocessing container identity changed')
 local actual=inventory(root,{})
 local floorItem,floorRestored=nil,false
 if state.id=='floor-pickup' then
  local square=assert(getCell():getGridSquare(state.floor.x,state.floor.y,state.floor.z),'original floor square unloaded')
  local objects=square:getWorldObjects()
  assert(not objects:contains(state.pickupWorld),'original pickup world object survived')
  for i=0,objects:size()-1 do
   local world=objects:get(i);local item=world:getItem()
   if item and item:getID()==state.floor.id then
    assert(not floorItem,'duplicate restored floor ID');floorItem=item
    assert(item:getWorldItem()==world and world:getSquare()==square,'restored floor object identity differs')
   end
  end
  if floorItem then
   assert(tidy,'floor pickup returned without pack postprocessing')
   assert(not actual[state.floor.id],'floor pickup duplicated in carried inventory')
   assert(same(floorItem,state.baseline[state.floor.id]),'restored floor ID changed type')
   floorRestored=true
   state.pickup,state.items.pickup=floorItem,floorItem
   for i,item in ipairs(state.owned or {}) do if item:getID()==state.floor.id then state.owned[i]=floorItem end end
  else
   local item=assert(actual[state.floor.id],'postprocessing lost floor pickup ID')
   assert(item:getContainer()==root and not item:getWorldItem(),'postprocessing floor pickup left root')
  end
 end
 for id,item in pairs(state.baseline) do
  assert(same(actual[id] or (floorRestored and id==state.floor.id and floorItem or nil),item),
   'postprocessing lost/replaced inventory ID '..id)
 end
 for id in pairs(actual) do assert(state.baseline[id],'unexpected postprocessing inventory ID '..id) end
 for id in pairs(state.original) do
  assert(actual[id] and actual[id]:getContainer()==state.originalContainers[id],'postprocessing moved original item '..id)
 end
 for _,book in ipairs({state.front,state.tail}) do
  local item=assert(actual[book:getID()],'postprocessing book missing')
  assert(item:getAlreadyReadPages()==item:getNumberOfPages()
   and player:getAlreadyReadPages(item:getFullType())==item:getNumberOfPages(),'postprocessing book incomplete')
 end
 local primary,secondary=state.hammer,state.screwdriver
 if state.id=='waiting-cancel' and mode=='native' then
  primary,secondary=state.bat,state.bat
  if tidy then
   assert(actual[state.bat:getID()]:getContainer()==root and same(player:getPrimaryHandItem(),state.bat)
    and same(player:getSecondaryHandItem(),state.bat),'P4 removed deliberately equipped bat after native completion')
  end
 elseif state.id=='bag-capacity' then
  secondary=state.pickupBag
  assert(actual[state.pickup:getID()]:getContainer()==root,'P4 returned deliberately picked up carried item after native completion')
 end
 assert(same(player:getPrimaryHandItem(),primary) and same(player:getSecondaryHandItem(),secondary),'postprocessing changed final hands')
 local expectedAttached={}
 for location,item in pairs(assert(state.originalAttached,'postprocessing attachment baseline missing')) do
  expectedAttached[location]=item
 end
 if state.id=='hotbar-chain' then expectedAttached[state.hotbarLocation]=state.hotbarReplacement end
 local actualAttached={};local attachments=player:getAttachedItems()
 for i=0,attachments:size()-1 do local entry=attachments:get(i);actualAttached[tostring(entry:getLocation())]=entry:getItem() end
 if tidy and state.id=='hotbar-chain' then
  assert(actual[state.hotbarReplacement:getID()]:getContainer()==root
   and same(actualAttached[state.hotbarLocation],state.hotbarReplacement),'P4 removed deliberately attached hotbar item after native completion')
 end
 sameSlots(actualAttached,expectedAttached,'attachment')
 if state.id=='hotbar-chain' then
  local item=actual[state.hotbarReplacement:getID()]
  assert(item:getAttachedSlot()==state.hotbarIndex and item:getAttachedSlotType()==state.hotbarType
   and item:getAttachedToModel()==state.hotbarLocation,'postprocessing changed hotbar metadata')
  local initial=actual[state.hotbarInitial:getID()]
  assert(initial:getAttachedSlot()==-1 and (initial:getAttachedSlotType()==nil or initial:getAttachedSlotType()=='')
   and (initial:getAttachedToModel()==nil or initial:getAttachedToModel()==''),'postprocessing changed detached metadata')
 end
 local actualWorn={};local values=player:getWornItems()
 for i=0,values:size()-1 do local item=values:getItemByIndex(i);actualWorn[values:getLocation(item)]=item end
 sameSlots(actualWorn,state.expectedWorn,'worn item')
 local rootNames={front=true,tail=true,hammer=true,screwdriver=true,bag=true,pickupBag=true,
  clothingB=true,hotbarInitial=true,hotbarReplacement=true}
 for name,seed in pairs(state.items) do
  local expected=root
  if name=='bat' then
   if state.id=='waiting-cancel' and mode=='toolkit' or tidy and state.id=='hands-chain' then expected=state.source end
  elseif name=='content' or name:match('^plank%d+$') then expected=state.source
  elseif name=='clothingA' then expected=tidy and state.source or root
  elseif name=='pickup' and state.id=='bag-capacity' then expected=root
  elseif name=='pickup' and state.id=='floor-pickup' then expected=root
  else assert(rootNames[name],'unknown postprocessing seed '..name) end
  local item=actual[seed:getID()] or floorItem
  if not (name=='pickup' and floorRestored) then
   assert(item and item:getContainer()==expected,'postprocessing seed container differs '..name)
  end
 end
 assert(not floorRestored,'P4 returned deliberately picked up floor item after native completion')
 return {postprocessingVerified=true,tidy=tidy,floorRestored=false}
end
return Postprocess
