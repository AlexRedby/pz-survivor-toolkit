local Fixture={}
local function count(container,kind)
 local total=0
 for i=0,container:getItems():size()-1 do
  if container:getItems():get(i):getFullType()==kind then total=total+1 end
 end
 return total
end
local function identityCount(container,id)
 local total=0
 for i=0,container:getItems():size()-1 do
  local item=container:getItems():get(i)
  if item:getID()==id then total=total+1 end
  if instanceof(item,'InventoryContainer') then total=total+identityCount(item:getItemContainer(),id) end
 end
 return total
end
function Fixture.prepare(player)
 local inventory=player:getInventory()
 local state={player=player,root=inventory,bags={},tools={}}
 for i,kind in ipairs({'Base.Hammer','Base.Saw'}) do
  local bag=assert(inventory:AddItem('Base.Bag_Schoolbag'))
  state.bags[i]=bag
  state.tools[i]=assert(bag:getItemContainer():AddItem(kind))
  if isServer() then sendAddItemToContainer(inventory,bag) end
 end
 state.material=assert(inventory:AddItem('Base.Plank'))
 state.book=assert(inventory:AddItem('Base.BookCarpentry1'))
 state.book:setAlreadyReadPages(state.book:getNumberOfPages()-1)
 player:setAlreadyReadPages(state.book:getFullType(),state.book:getNumberOfPages()-1)
 state.outputs=count(inventory,'Base.WoodenStick2')
 if isServer() then
  sendAddItemToContainer(inventory,state.material)
  sendAddItemToContainer(inventory,state.book)
 end
 return state
end
function Fixture.descriptor(state)
 local result={bags={},tools={},material=state.material:getID(),book=state.book:getID(),outputs=state.outputs}
 for i=1,2 do result.bags[i]=state.bags[i]:getID();result.tools[i]=state.tools[i]:getID() end
 return result
end
function Fixture.resolve(player,ids)
 local inventory=player:getInventory()
 local state={player=player,root=inventory,bags={},tools={},outputs=ids.outputs}
 for i=1,2 do
  state.bags[i]=inventory:getItemById(ids.bags[i])
  if not state.bags[i] then return end
  state.tools[i]=state.bags[i]:getItemContainer():getItemById(ids.tools[i]) or inventory:getItemById(ids.tools[i])
  if not state.tools[i] then return end
 end
 state.material=inventory:getItemById(ids.material)
 state.book=inventory:getItemById(ids.book)
 if not state.material or not state.book then return end
 return state
end
function Fixture.verify(state)
 local player,inventory=state.player,state.player:getInventory()
 if inventory:getItemById(state.material:getID()) then return nil,'consumed plank still exists' end
 if count(inventory,'Base.WoodenStick2')~=state.outputs+1 then return nil,'craft output differs' end
 for i=1,2 do
  local bag=inventory:getItemById(state.bags[i]:getID())
  if not bag then return nil,'borrow source lost' end
  local tool=bag:getItemContainer():getItemById(state.tools[i]:getID())
  if not tool or tool:getContainer()~=bag:getItemContainer() then return nil,'exact borrowed tool not returned' end
  if identityCount(inventory,tool:getID())~=1 then return nil,'borrowed tool identity duplicated' end
 end
 local book=inventory:getItemById(state.book:getID())
 if not book then return nil,'reading tail lost' end
 if book:getAlreadyReadPages()~=book:getNumberOfPages() then return nil,'reading tail unfinished' end
 return {consumed=1,outputs=1,toolsReturned=2,tailRead=true}
end
return Fixture
