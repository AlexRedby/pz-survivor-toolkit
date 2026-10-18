local Fixture={}
local function active(case)return case=='cancel-craft' or case=='late-input'end
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
local function uses(item)return instanceof(item,'DrainableComboItem') and item:getCurrentUses() or 0 end
function Fixture.prepare(player,case)
 local inventory=player:getInventory()
 local state={case=case or 'borrowed-tools',player=player,root=inventory,bags={},tools={},toolMeta={}}
 for i,kind in ipairs({'Base.Hammer','Base.Saw'}) do
  local bag=assert(inventory:AddItem('Base.Bag_Schoolbag'))
  state.bags[i]=bag
  state.tools[i]=assert(bag:getItemContainer():AddItem(kind))
  state.toolMeta[i]={id=state.tools[i]:getID(),kind=kind,condition=state.tools[i]:getCondition(),uses=uses(state.tools[i])}
  if isServer() then sendAddItemToContainer(inventory,bag) end
 end
 state.material=assert(inventory:AddItem('Base.Plank'))
 state.materialCondition,state.materialUses=state.material:getCondition(),uses(state.material)
 state.book=assert(inventory:AddItem('Base.BookCarpentry1'))
 state.book:setAlreadyReadPages(state.book:getNumberOfPages()-1)
 player:setAlreadyReadPages(state.book:getFullType(),state.book:getNumberOfPages()-1)
 state.outputs=count(inventory,'Base.WoodenStick2')
 if active(state.case)then
  state.outputBaseline={};state.sparePlanks={}
  for i=0,inventory:getItems():size()-1 do
   local item=inventory:getItems():get(i)
   if item:getFullType()=='Base.WoodenStick2' then state.outputBaseline[item:getID()]=true end
   if item:getFullType()=='Base.Plank'and item:getID()~=state.material:getID()then
    state.sparePlanks[#state.sparePlanks+1]={id=item:getID(),condition=item:getCondition(),uses=uses(item)}
   end
  end
  table.sort(state.sparePlanks,function(a,b)return a.id<b.id end)
 end
 if case=='missing-input' then
  state.blocker=assert(inventory:AddItem('Base.BookCooking1'))
  state.blocker:setAlreadyReadPages(state.blocker:getNumberOfPages()-1)
  player:setAlreadyReadPages(state.blocker:getFullType(),state.blocker:getNumberOfPages()-1)
 end
 if isServer() then
  sendAddItemToContainer(inventory,state.material)
  sendAddItemToContainer(inventory,state.book)
  if state.blocker then sendAddItemToContainer(inventory,state.blocker) end
 end
 return state
end
function Fixture.descriptor(state)
 local result={case=state.case,bags={},tools={},material=state.material:getID(),book=state.book:getID(),outputs=state.outputs,
  toolMeta=state.toolMeta,materialCondition=state.materialCondition,materialUses=state.materialUses,
  blocker=state.blocker and state.blocker:getID()}
 if active(state.case)then
  result.sparePlanks=state.sparePlanks
  result.outputBaseline={};for id in pairs(state.outputBaseline)do result.outputBaseline[#result.outputBaseline+1]=id end
  table.sort(result.outputBaseline);result.playerId=isServer()and state.player:getOnlineID()or -1
 end
 for i=1,2 do result.bags[i]=state.bags[i]:getID();result.tools[i]=state.tools[i]:getID() end
 return result
end
function Fixture.resolve(player,ids)
 local inventory=player:getInventory()
 local state={case=ids.case,player=player,root=inventory,bags={},tools={},outputs=ids.outputs,toolMeta=ids.toolMeta,
  materialCondition=ids.materialCondition,materialUses=ids.materialUses}
 if active(ids.case)then
  state.sparePlanks=ids.sparePlanks
  state.outputBaseline={};for _,id in ipairs(ids.outputBaseline)do state.outputBaseline[id]=true end
 end
 for i=1,2 do
  state.bags[i]=inventory:getItemById(ids.bags[i])
  if not state.bags[i] then return end
  state.tools[i]=state.bags[i]:getItemContainer():getItemById(ids.tools[i]) or inventory:getItemById(ids.tools[i])
  if not state.tools[i] then return end
 end
 state.material=inventory:getItemById(ids.material)
 state.book=inventory:getItemById(ids.book)
 state.blocker=ids.blocker and inventory:getItemById(ids.blocker)
 if not state.material or not state.book or ids.blocker and not state.blocker then return end
 return state
end
function Fixture.removeInput(state)
 assert((state.case=='missing-input'or state.case=='late-input')and not state.removed,'unexpected craft input removal')
 local item=assert(state.root:getItemById(state.material:getID()),'craft input already missing')
 assert(item:getContainer()==state.root and item:getFullType()=='Base.Plank'
  and item:getCondition()==state.materialCondition and uses(item)==state.materialUses,'craft input changed before removal')
 state.root:Remove(item)
 if isServer() then sendRemoveItemFromContainer(state.root,item) end
 state.removed=true
 return {case=state.case,materialId=item:getID(),removed=1,condition=item:getCondition(),uses=uses(item)}
end
function Fixture.verify(state,enabled)
 local player,inventory=state.player,state.player:getInventory()
 if state.case and state.case~='borrowed-tools' then
  local missing=state.case=='missing-input'or state.case=='late-input'
  local material=inventory:getItemById(state.material:getID())
  local materialCount=identityCount(inventory,state.material:getID())
  if missing and (not state.removed or materialCount~=0) or not missing and (materialCount~=1 or not material
   or material:getFullType()~='Base.Plank' or material:getContainer()~=inventory
   or material:getCondition()~=state.materialCondition or uses(material)~=state.materialUses) then return nil,'abort material state differs' end
  local outputIds,outputPlankCounts,accounted={},{},0
  if active(state.case)then
   for id in pairs(state.outputBaseline)do
    local item=inventory:getItemById(id)
    if not item or item:getContainer()~=inventory or item:getFullType()~='Base.WoodenStick2'
     or identityCount(inventory,id)~=1 then return nil,'active craft baseline output lost or duplicated' end
   end
   for _,expected in ipairs(state.sparePlanks)do
    local item=inventory:getItemById(expected.id)
    if not item or item:getContainer()~=inventory or item:getFullType()~='Base.Plank'
     or identityCount(inventory,expected.id)~=1 or item:getCondition()~=expected.condition
     or uses(item)~=expected.uses then return nil,'active craft substituted or changed a spare input' end
   end
   for i=0,inventory:getItems():size()-1 do
    local item=inventory:getItems():get(i)
    if item:getFullType()=='Base.WoodenStick2'and not state.outputBaseline[item:getID()]then outputIds[#outputIds+1]=item:getID()end
   end
   table.sort(outputIds)
   if count(inventory,'Base.WoodenStick2')~=state.outputs+#outputIds then return nil,'active craft baseline output changed' end
   for _,id in ipairs(outputIds)do
    local item=inventory:getItemById(id)
    local amount=item:getModData()['Base.Plank']or 0
    outputPlankCounts[#outputPlankCounts+1]=amount;accounted=accounted+amount
   end
  elseif count(inventory,'Base.WoodenStick2')~=state.outputs then return nil,'aborted craft produced output' end
  local resources,returned={},0
  for i,expected in ipairs(state.toolMeta) do
   local bag=inventory:getItemById(state.bags[i]:getID())
   if not bag or not instanceof(bag,'InventoryContainer') or bag:getContainer()~=inventory
    or identityCount(inventory,bag:getID())~=1 then return nil,'abort borrow source lost' end
   local source=bag:getItemContainer()
   local tool=inventory:getItemById(expected.id)
   if not tool or identityCount(inventory,expected.id)~=1 or tool:getFullType()~=expected.kind
    or tool:getCondition()~=expected.condition or uses(tool)~=expected.uses then return nil,'abort exact tool changed' end
   local sc=identityCount(source,expected.id)
   local rc=tool:getContainer()==inventory and 1 or 0
   if sc+rc~=1 or enabled and sc~=1 then return nil,'abort exact tool endpoint differs' end
   returned=returned+sc
   resources[i]={id=expected.id,kind=expected.kind,condition=expected.condition,uses=uses(tool),sourceCount=sc,rootCount=rc}
  end
  local book=inventory:getItemById(state.book:getID())
  if not book or book:getFullType()~='Base.BookCarpentry1' or book:getContainer()~=inventory
   or identityCount(inventory,book:getID())~=1 then return nil,'abort reader identity lost' end
  local read=book:getAlreadyReadPages()==book:getNumberOfPages()
  if enabled and not read then return nil,'abort independent reader unfinished' end
  local result={case=state.case,materialId=state.material:getID(),bookId=book:getID(),materialPresent=material~=nil,
   materialCondition=state.materialCondition,materialUses=state.materialUses,removed=missing and 1 or 0,consumed=0,
   outputs=0,toolsReturned=returned,resources=resources,tailRead=read}
  if active(state.case)then
   result.consumed=nil;result.outputs=#outputIds;result.outputIds=outputIds
   result.outputPlankCounts=outputPlankCounts;result.accountedPlanks=accounted;result.sparePlanks=state.sparePlanks
  end
  return result
 end
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
