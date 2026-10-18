local Authority,sessions={},{}
local selection=require 'QueueTestSelection'
local Ignition=require 'QueueFireIgnition'
local JSON=require 'QueueHealthEvents'
local function exact(container,id)
 local item=container:getItemById(id)
 return item and item:getContainer()==container and item or nil
end
local function count(container,id)
 local total=0
 for i=0,container:getItems():size()-1 do
  local item=container:getItems():get(i)
  if item:getID()==id then total=total+1 end
  if instanceof(item,'InventoryContainer') then total=total+count(item:getItemContainer(),id) end
 end
 return total
end
function Authority.prepare(player,case)
 if Ignition.cases[case] then return Ignition.prepare(player,case) end
 assert(not sessions[player:getUsername()],'duplicate fire preparation')
 assert(case=='fuel' or case=='missing-target-after-expansion','unknown fire case')
 require 'Camping/SCampfireSystem'
 if not ISCampingMenu then require 'Camping/ISCampingMenu' end
 local origin=require('QueueEnergyPlacement')(player)
 local square=assert(getCell():getGridSquare(origin:getX()+1,origin:getY(),origin:getZ()))
 local crateSquare=square -- Keep the borrowed source reachable after native walkToCampfire.
 local object=IsoThumpable.new(getCell(),crateSquare,'carpentry_01_16',false,{})
 object:setCanPassThrough(true);object:setIsContainer(true)
 local crate=assert(object:getContainer(),'native world crate missing')
 crate:setType('crate');crate:setCapacity(100);crate:setExplored(true)
 object:getModData().QueueFireOwner=player:getUsername()
 crateSquare:AddSpecialObject(object)
 local log=assert(crate:AddItem('Base.Log'))
 if isServer() then object:transmitCompleteItemToClients() end
 -- Removing a later campfire must not shift the MP pickup source's object index.
 local target=assert(SCampfireSystem.instance:addCampfire(square),'native campfire creation failed')
 assert(target.fuelAmt==0 and not target.isLit,'campfire must start empty and unlit')
 local book=assert(player:getInventory():AddItem('Base.BookCarpentry1'))
 book:setAlreadyReadPages(book:getNumberOfPages()-1)
 player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-1)
 if isServer() then sendAddItemToContainer(player:getInventory(),book) end
 local ids={case=case,log=log:getID(),book=book:getID(),condition=log:getCondition(),fuelAmount=ISCampingMenu.getFuelDurationForItem(log),
  x=square:getX(),y=square:getY(),z=square:getZ(),objectIndex=target:getIsoObject():getObjectIndex(),
  crateX=crateSquare:getX(),crateY=crateSquare:getY(),crateZ=crateSquare:getZ(),crateIndex=object:getObjectIndex(),
  spawn={x=origin:getX()+0.5,y=origin:getY()+0.5,z=origin:getZ()}}
 assert(ids.fuelAmount>0 and count(player:getInventory(),ids.log)==0 and count(crate,ids.log)==1,'invalid borrowed fuel fixture')
 sessions[player:getUsername()]={player=player,ids=ids,target=target,object=object,crate=crate,book=book}
 print('[FIRE_TEST] PREPARED '..JSON.encode(ids))
 return ids
end
function Authority.invalidate(player,case)
 local state=assert(sessions[player:getUsername()])
 assert(case=='missing-target-after-expansion' and state.ids.case==case and not state.removed,'unexpected campfire removal')
 assert(state.target.fuelAmt==0 and count(state.crate,state.ids.log)+count(player:getInventory(),state.ids.log)==1,
  'fuel spent before campfire removal')
 SCampfireSystem.instance:removeCampfire(state.target)
 assert(not SCampfireSystem.instance:getLuaObjectAt(state.ids.x,state.ids.y,state.ids.z),'native campfire survived removal')
 state.removed=true
 print('[FIRE_TEST] REMOVED '..JSON.encode({case=case,logId=state.ids.log,fuel=0}))
 return {case=case,ok=true}
end
function Authority.verify(player,case)
 if Ignition.cases[case] then return Ignition.verify(player,case) end
 local state=assert(sessions[player:getUsername()])
 assert(state.ids.case==case,'out-of-order fire verification')
 local missing=case=='missing-target-after-expansion'
 local enabled=selection.mode=='toolkit'
 local root=player:getInventory()
 local sourceItem,rootItem=exact(state.crate,state.ids.log),exact(root,state.ids.log)
 local sourceCount,rootCount=count(state.crate,state.ids.log),count(root,state.ids.log)
 local target=SCampfireSystem.instance:getLuaObjectAt(state.ids.x,state.ids.y,state.ids.z)
 if missing then
  if not state.removed or target then return nil,'campfire still exists' end
  if sourceCount~=(enabled and 1 or 0) or rootCount~=(enabled and 0 or 1) then return nil,'exact unspent Log location differs' end
  local item=enabled and sourceItem or rootItem
  if not item or item:getCondition()~=state.ids.condition then return nil,'exact unspent Log changed' end
 else
  if not target or target.fuelAmt~=state.ids.fuelAmount or target.isLit then return nil,'native fuel amount differs' end
  if sourceCount~=0 or rootCount~=0 then return nil,'consumed Log identity remains' end
 end
 local book=exact(root,state.ids.book)
 if not book then return nil,'independent reader identity lost' end
 local read=book:getAlreadyReadPages()==book:getNumberOfPages()
 local observedNativeMPFuel=not missing and not enabled and selection.kind=='mp'
 if not observedNativeMPFuel and read~=(not missing or enabled) then return nil,'native reading outcome differs' end
 local result={case=case,logId=state.ids.log,bookId=state.ids.book,sourceCount=sourceCount,rootCount=rootCount,
  consumed=missing and 0 or 1,fuel=missing and 0 or target.fuelAmt,removed=missing,tailRead=read,
  unspent=missing,condition=state.ids.condition,fuelAmount=state.ids.fuelAmount}
 print('[FIRE_TEST] AUTHORITY '..JSON.encode(result))
 sessions[player:getUsername()]=nil
 -- Only remove this session's exact owned world objects after taking the receipt.
 if target then SCampfireSystem.instance:removeCampfire(target) end
 assert(state.object:getContainer()==state.crate and state.object:getModData().QueueFireOwner==player:getUsername(),'foreign crate cleanup refused')
 state.object:getSquare():transmitRemoveItemFromSquare(state.object)
 return result
end
return Authority
