local Fixture={}
local function list(container)
 local result={}
 for i=0,container:getItems():size()-1 do result[#result+1]=container:getItems():get(i)end
 return result
end
local function uses(item)return instanceof(item,'DrainableComboItem')and item:getCurrentUses()or 0 end
local function count(container,id)
 local result=0
 for _,item in ipairs(list(container))do
  if item:getID()==id then result=result+1 end
  if instanceof(item,'InventoryContainer')then result=result+count(item:getItemContainer(),id)end
 end
 return result
end
function Fixture.prepare(player,case)
 local state={player=player,case=case,materials={},bags={},toolMeta={},baselineOutputIds={}}
 local root=player:getInventory();state.root=root
 for _,item in ipairs(list(root))do
  if item:getFullType()=='Base.WoodenStick2'then state.baselineOutputIds[#state.baselineOutputIds+1]=item:getID()end
 end
 for i,kind in ipairs({'Base.Hammer','Base.Saw'})do
  local bag=assert(root:AddItem('Base.Bag_Schoolbag'));state.bags[i]=bag:getID()
  local tool=assert(bag:getItemContainer():AddItem(kind))
  state.toolMeta[i]={id=tool:getID(),kind=kind,condition=tool:getCondition(),uses=uses(tool)}
  if isServer()then sendAddItemToContainer(root,bag)end
 end
 for i=1,case=='context'and 1 or 2 do
  local item=assert(root:AddItem('Base.Plank'));state.materials[i]=item:getID()
  if isServer()then sendAddItemToContainer(root,item)end
 end
 local book=assert(root:AddItem('Base.BookCarpentry1'));state.book=book:getID()
 book:setAlreadyReadPages(book:getNumberOfPages()-1)
 player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-1)
 if isServer()then sendAddItemToContainer(root,book)end
 return state
end
function Fixture.descriptor(state)
 return {case=state.case,materials=state.materials,bags=state.bags,toolMeta=state.toolMeta,
  book=state.book,baselineOutputIds=state.baselineOutputIds}
end
function Fixture.resolve(player,ids)
 local root=player:getInventory();local containers=ArrayList.new();containers:add(root)
 for _,id in ipairs(ids.bags)do
  local bag=root:getItemById(id);if not bag then return end
  containers:add(bag:getItemContainer())
 end
 for _,id in ipairs(ids.materials)do if not root:getItemById(id)then return end end
 for _,meta in ipairs(ids.toolMeta)do if not root:getItemById(meta.id)then return end end
 local book=root:getItemById(ids.book);if not book then return end
 return {root=root,containers=containers,book=book}
end
function Fixture.verify(state)
 local root=state.player:getInventory();local baseline={};local outputIds={}
 for _,id in ipairs(state.materials)do if count(root,id)~=0 then return nil,'UI craft input remains'end end
 for _,id in ipairs(state.baselineOutputIds)do
  local item=root:getItemById(id)
  if not item or item:getFullType()~='Base.WoodenStick2'or item:getContainer()~=root or count(root,id)~=1 then return nil,'UI baseline output changed'end
  baseline[id]=true
 end
 for _,item in ipairs(list(root))do
  if item:getFullType()=='Base.WoodenStick2'and not baseline[item:getID()]then
   if item:getContainer()~=root or count(root,item:getID())~=1 then return nil,'UI output identity/endpoint differs'end
   outputIds[#outputIds+1]=item:getID()
  end
 end
 if #outputIds~=#state.materials then return nil,'UI craft output count differs'end
 table.sort(outputIds)
 local resources,returned={},0
 for i,meta in ipairs(state.toolMeta)do
  local bag=root:getItemById(state.bags[i]);local tool=root:getItemById(meta.id)
  if not bag or not instanceof(bag,'InventoryContainer')or bag:getContainer()~=root or count(root,bag:getID())~=1
   or not tool or tool:getFullType()~=meta.kind or tool:getCondition()~=meta.condition
   or uses(tool)~=meta.uses or count(root,tool:getID())~=1 then return nil,'UI exact tool or source changed'end
  local sourceCount=count(bag:getItemContainer(),tool:getID());local rootCount=tool:getContainer()==root and 1 or 0
  if sourceCount+rootCount~=1 then return nil,'UI exact tool endpoint differs'end
  returned=returned+sourceCount
  resources[i]={id=meta.id,kind=meta.kind,condition=meta.condition,uses=meta.uses,sourceCount=sourceCount,rootCount=rootCount}
 end
 local book=root:getItemById(state.book)
 if not book or book:getFullType()~='Base.BookCarpentry1'or book:getContainer()~=root or count(root,book:getID())~=1 then return nil,'UI independent book changed'end
 return {case=state.case,materialIds=state.materials,consumed=#state.materials,outputIds=outputIds,outputs=#outputIds,
  resources=resources,toolsReturned=returned,bookId=book:getID(),tailRead=book:getAlreadyReadPages()==book:getNumberOfPages()}
end
return Fixture
