local Fixture={}
local function pool(case)return case:find('missing-batch-pool',1,true)~=nil end
local function failure(case)return case:find('cancel-active',1,true)~=nil or pool(case)end
local function list(container)
 local result={}
 for i=0,container:getItems():size()-1 do result[#result+1]=container:getItems():get(i)end
 return result
end
local function uses(item)return instanceof(item,'DrainableComboItem')and item:getCurrentUses()or 0 end
local function metadata(item)
 return {id=item:getID(),kind=item:getFullType(),condition=item:getCondition(),uses=uses(item)}
end
local function unchanged(item,meta)
 return item and item:getID()==meta.id and item:getFullType()==meta.kind
  and item:getCondition()==meta.condition and uses(item)==meta.uses
end
local function count(container,id)
 local result=0
 for _,item in ipairs(list(container))do
  if item:getID()==id then result=result+1 end
  if instanceof(item,'InventoryContainer')then result=result+count(item:getItemContainer(),id)end
 end
 return result
end
function Fixture.sparePresent(player,meta)
 local root=player:getInventory();local item=root:getItemById(meta.id)
 return unchanged(item,meta)and item:getContainer()==root and count(root,meta.id)==1
end
function Fixture.prepare(player,case,previous)
 if previous then
  assert(previous.player==player and previous.verified==true and type(previous.cleanupRootItems)=='table'
   and type(previous.cleanupBags)=='table'and #previous.cleanupBags==2,'UI previous cleanup state is not verified')
  local root=player:getInventory();local targets,seen={},{}
  local function owned(meta)
   assert(not seen[meta.id],'UI cleanup identity duplicated')
   for _,id in ipairs(previous.baselineOutputIds)do assert(meta.id~=id,'UI cleanup cannot remove a baseline output')end
   for _,spare in ipairs(previous.sparePlanks or {})do assert(meta.id~=spare.id,'UI cleanup cannot remove a pre-existing spare')end
   seen[meta.id]=true
  end
  local function validate(meta)
   owned(meta)
   local item=root:getItemById(meta.id)
   assert(Fixture.sparePresent(player,meta)and not player:isEquipped(item),
    'UI previous owned item changed or remains equipped before cleanup')
   targets[#targets+1]=item
   return item
  end
  for _,meta in ipairs(previous.cleanupRootItems)do validate(meta)end
  for _,entry in ipairs(previous.cleanupBags)do
   local bag=validate(entry.meta)
   assert(instanceof(bag,'InventoryContainer'),'UI cleanup bag type differs')
   local source=bag:getItemContainer();local contents=list(source)
   assert(#contents==(entry.tool and 1 or 0),'UI cleanup bag has unexpected contents')
   if entry.tool then
    local tool=contents[1];owned(entry.tool)
    assert(unchanged(tool,entry.tool)and tool:getContainer()==source and count(root,tool:getID())==1
     and not player:isEquipped(tool),'UI cleanup source tool changed')
   end
  end
  for _,item in ipairs(targets)do
   root:Remove(item);if isServer()then sendRemoveItemFromContainer(root,item)end
  end
 end
 local state={player=player,case=case,materials={},bags={},toolMeta={},baselineOutputIds={}}
 local root=player:getInventory();state.root=root
 if failure(case)then
  state.materialMeta={};state.sparePlanks={}
  for _,item in ipairs(list(root))do
   if item:getFullType()=='Base.Plank'then state.sparePlanks[#state.sparePlanks+1]=metadata(item)end
  end
  table.sort(state.sparePlanks,function(a,b)return a.id<b.id end)
 end
 for _,item in ipairs(list(root))do
  if item:getFullType()=='Base.WoodenStick2'then state.baselineOutputIds[#state.baselineOutputIds+1]=item:getID()end
 end
 for i,kind in ipairs({'Base.Hammer','Base.Saw'})do
  local bag=assert(root:AddItem('Base.Bag_Schoolbag'));state.bags[i]=bag:getID()
  local tool=assert(bag:getItemContainer():AddItem(kind))
  state.toolMeta[i]={id=tool:getID(),kind=kind,condition=tool:getCondition(),uses=uses(tool)}
  if isServer()then sendAddItemToContainer(root,bag)end
 end
 for i=1,case:match('^context')and 1 or 2 do
  local item=assert(root:AddItem('Base.Plank'));state.materials[i]=item:getID()
  if state.materialMeta then state.materialMeta[i]=metadata(item)end
  if isServer()then sendAddItemToContainer(root,item)end
 end
 local book=assert(root:AddItem('Base.BookCarpentry1'));state.book=book:getID()
 book:setAlreadyReadPages(book:getNumberOfPages()-1)
 player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-1)
 if isServer()then sendAddItemToContainer(root,book)end
 return state
end
function Fixture.descriptor(state)
 local value={case=state.case,materials=state.materials,bags=state.bags,toolMeta=state.toolMeta,
  book=state.book,baselineOutputIds=state.baselineOutputIds}
 if failure(state.case)then
  value.materialMeta=state.materialMeta;value.sparePlanks=state.sparePlanks;value.playerId=state.player:getOnlineID()
 end
 return value
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
function Fixture.removePool(state)
 assert(pool(state.case)and not state.poolRemoval and #state.materialMeta==2,'unexpected UI shared-pool removal')
 local items={}
 for i,meta in ipairs(state.materialMeta)do
  local item=state.root:getItemById(meta.id)
  assert(unchanged(item,meta)and item:getContainer()==state.root and count(state.root,meta.id)==1,'UI pool material changed before removal')
  items[i]=item
 end
 local spare=assert(state.root:AddItem('Base.Plank'));state.introducedSpare=metadata(spare)
 assert(Fixture.sparePresent(state.player,state.introducedSpare),'UI introduced spare is not unique at root')
 if isServer()then sendAddItemToContainer(state.root,spare)end
 for _,item in ipairs(items)do
  state.root:Remove(item)
  if isServer()then sendRemoveItemFromContainer(state.root,item)end
 end
 state.poolRemoval={case=state.case,removedMaterials=state.materialMeta,introducedSpare=state.introducedSpare}
 return state.poolRemoval
end
function Fixture.verify(state)
 local root=state.player:getInventory();local baseline={};local outputIds={}
 local materialStates,consumed={},0
 local spentMaterials,survivingMaterials,removedMaterials={},{},{}
 if failure(state.case)then
  if pool(state.case)then
   if not state.poolRemoval then return nil,'UI shared pool has no removal receipt'end
   if not Fixture.sparePresent(state.player,state.introducedSpare)then return nil,'UI introduced spare changed or was substituted'end
  end
  for _,meta in ipairs(state.materialMeta)do
   local item=root:getItemById(meta.id);local number=count(root,meta.id)
   local status=pool(state.case)and 'removed'or 'surviving'
   if status=='removed'then
    if number~=0 then return nil,'UI exact removed pool material remains'end
    removedMaterials[#removedMaterials+1]=meta
   else
    if not unchanged(item,meta)or item:getContainer()~=root or number~=1 then return nil,'UI surviving exact material changed'end
    survivingMaterials[#survivingMaterials+1]=meta
   end
   materialStates[#materialStates+1]={id=meta.id,kind=meta.kind,condition=meta.condition,uses=meta.uses,state=status}
  end
  for _,meta in ipairs(state.sparePlanks)do
   local item=root:getItemById(meta.id)
   if not unchanged(item,meta)or item:getContainer()~=root or count(root,meta.id)~=1 then return nil,'UI substituted or changed a spare Plank'end
  end
 else
  for _,id in ipairs(state.materials)do if count(root,id)~=0 then return nil,'UI craft input remains'end end
  consumed=#state.materials
 end
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
 local expected=failure(state.case)and 0 or #state.materials
 if not pool(state.case)and #outputIds~=expected then return nil,'UI craft output count differs'end
 table.sort(outputIds)
 local resources,returned,rootTools,bags={},0,{},{}
 for i,meta in ipairs(state.toolMeta)do
  local bag=root:getItemById(state.bags[i]);local tool=root:getItemById(meta.id)
  if not bag or not instanceof(bag,'InventoryContainer')or bag:getContainer()~=root or count(root,bag:getID())~=1
   or not tool or tool:getFullType()~=meta.kind or tool:getCondition()~=meta.condition
   or uses(tool)~=meta.uses or count(root,tool:getID())~=1 then return nil,'UI exact tool or source changed'end
  local sourceCount=count(bag:getItemContainer(),tool:getID());local rootCount=tool:getContainer()==root and 1 or 0
  if sourceCount+rootCount~=1 then return nil,'UI exact tool endpoint differs'end
  if rootCount==1 then rootTools[#rootTools+1]=metadata(tool)end
  bags[#bags+1]={meta=metadata(bag),tool=sourceCount==1 and metadata(tool)or nil}
  returned=returned+sourceCount
  resources[i]={id=meta.id,kind=meta.kind,condition=meta.condition,uses=meta.uses,sourceCount=sourceCount,rootCount=rootCount}
 end
 local book=root:getItemById(state.book)
 if not book or book:getFullType()~='Base.BookCarpentry1'or book:getContainer()~=root or count(root,book:getID())~=1 then return nil,'UI independent book changed'end
 local value={case=state.case,materialIds=state.materials,consumed=consumed,outputIds=outputIds,outputs=#outputIds,
  resources=resources,toolsReturned=returned,bookId=book:getID(),tailRead=book:getAlreadyReadPages()==book:getNumberOfPages()}
 if failure(state.case)then
  value.materialStates=materialStates;value.sparePlanks=state.sparePlanks
 end
 if pool(state.case)then
  value.introducedSpare=state.introducedSpare
  value.spentMaterials=spentMaterials;value.survivingMaterials=survivingMaterials;value.removedMaterials=removedMaterials
  value.outputPlankCounts={}
  for _,id in ipairs(outputIds)do
   value.outputPlankCounts[#value.outputPlankCounts+1]=root:getItemById(id):getModData()['Base.Plank']or 0
  end
 end
 local cleanup={}
 for _,meta in ipairs(materialStates)do
  if meta.state=='surviving'then cleanup[#cleanup+1]=metadata(root:getItemById(meta.id))end
 end
 if state.introducedSpare then cleanup[#cleanup+1]=metadata(root:getItemById(state.introducedSpare.id))end
 for _,id in ipairs(outputIds)do cleanup[#cleanup+1]=metadata(root:getItemById(id))end
 cleanup[#cleanup+1]=metadata(book)
 for _,meta in ipairs(rootTools)do cleanup[#cleanup+1]=meta end
 state.cleanupRootItems=cleanup;state.cleanupBags=bags
 state.verified=true
 return value
end
return Fixture
