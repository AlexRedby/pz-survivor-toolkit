-- A source snapshot is useful only while the queued prefix cannot change its
-- kit, bag ancestry or worn cosmetics. Read native facts, never prototypes.
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Access=require 'PZSurvivorToolkit/ItemAccess'
local FinalUse=require 'PZSurvivorToolkit/MakeupFinalUse'
local finalSupports=FinalUse and FinalUse.supports
local closure=Proof.closure
local own=Proof.own
local Move={}
local Toolkit=PZSurvivorToolkit
Toolkit.ActionQueueMakeupMove=Move
local classifier,instance,managerOf,client=getClassSimpleName,instanceof,getScriptManager,isClient
local types,clothing,containerType=ItemType,ItemType and ItemType.CLOTHING,ItemType and ItemType.CONTAINER
local locations=ItemBodyLocation
local slots={locations and locations.MAKE_UP_FULL_FACE,locations and locations.MAKE_UP_EYES,
 locations and locations.MAKE_UP_EYES_SHADOW,locations and locations.MAKE_UP_LIPS}
local policyOwner,inspectPolicy,addContainers
local resourceMaps={'items','itemTypes','outputTypes','containers','containerOwners','targets','positions'}
local worldGlobals={getCell=getCell,getVehicleById=getVehicleById,isServer=isServer}
local safehouse,allowLoot=SafeHouse,SafeHouse and SafeHouse.isSafehouseAllowLoot
local accessMethods,worldOwner,worldContainer
local floorPage
local function finite(n)return type(n)=='number'and n==n and n>-math.huge and n<math.huge end
local function integer(n)return finite(n)and n%1==0 end
local function plain(t)return type(t)=='table'and getmetatable(t)==nil end
local function invoker(f)
 if type(f)~='function'then return false end
 local ok,kind=pcall(classifier,f)
 return ok and(kind=='LuaJavaInvoker'or kind=='MultiLuaJavaInvoker')
end
local function scriptClean(script,kind,itemType)
 return script and classifier(script)=='Item'and script:getFullName()==kind
  and script:getItemType()==(itemType or clothing)and not script:hasComponents()and not script:getObsolete()
  and script:getLuaCreate()==nil and script:getItemConfigKey()==nil and script:getItemConfig()==nil
  and script:getReplaceOnUse()==nil and script:getReplaceOnDeplete()==nil
  and finite(script:getActualWeight())and script:getActualWeight()>=0
end
local function listSize(values)
 local kind=values and classifier(values)
 if kind~='ArrayList'and kind~='PZArrayList'then return end
 local n=values:size()
 if integer(n)and n>=0 and n<=256 then return n end
end
local function unique(values,object)
 local n=listSize(values)
 if not n then return false end
 local refs=0
 for i=0,n-1 do if values:get(i)==object then refs=refs+1 end end
 return refs==1
end
local function floorView(actor,bag)
 local floor=bag:getContainer()
 if floor==nil then return true end
 local page=ISInventoryPage
 if type(page)~='table'or floorPage and page~=floorPage then return false end
 -- Native/CleanUI refresh attaches world items to this existing per-player
 -- view. Never call GetFloorContainer: it can allocate or execute UI overrides.
 local caches=own(page,'floorContainer')
 local number=actor:getPlayerNum()
 if not plain(caches)or not integer(number)or number<0 or number>3 or own(caches,number+1)~=floor
  or not instance(floor,'ItemContainer')or classifier(floor)~='ItemContainer'or floor:getType()~='floor'
  or floor:getParent()~=nil or floor:getContainingItem()~=nil or floor:getVehiclePart()~=nil
  or floor:getSourceGrid()~=nil or floor:getAcceptItemFunction()~=nil or floor:getOnlyAcceptCategory()~=nil then return false end
 local values=floor:getItems()
 local n=listSize(values)
 if not n or not unique(values,bag)or floor:getItemById(bag:getID())~=bag then return false end
 local ids=0
 for i=0,n-1 do
  local member=values:get(i)
  if not instance(member,'InventoryItem')then return false end
  if member:getID()==bag:getID()then ids=ids+1 end
 end
 if ids~=1 then return false end
 floorPage=page
 return true
end
local function worldProof(actor,kit,outer,world,staged)
 for name,callback in pairs(worldGlobals)do
  if _G[name]~=callback or not invoker(callback)then return false end
 end
 if not worldGlobals.getCell or not worldGlobals.getVehicleById or not worldGlobals.isServer
  or not safehouse or SafeHouse~=safehouse or safehouse.isSafehouseAllowLoot~=allowLoot or not invoker(allowLoot)
  or not plain(Access)then return false end
 if not accessMethods then
  local saved={}
  for _,name in ipairs({'locate','admit','resolve','integer','validLocator','sameLocation'})do
   local callback=Access[name]
   if type(callback)~='function'or not closure(callback,'ItemAccess.lua')then return false end
   saved[name]=callback
  end
  accessMethods=saved
 end
 for name,callback in pairs(accessMethods)do if Access[name]~=callback then return false end end
 local adapters=Toolkit.ActionQueueItemEditAdapters
 if not worldOwner then
  if not plain(adapters)or type(adapters.worldContainer)~='function'
   or not closure(adapters.worldContainer,'ActionQueueItemEditAdapters.lua')then return false end
  worldOwner,worldContainer=adapters,adapters.worldContainer
 end
 if adapters~=worldOwner or adapters.worldContainer~=worldContainer then return false end
 local object,square
 if world then
  if classifier(world)~='IsoWorldInventoryObject'or not instance(world,'IsoWorldInventoryObject')or world:hasComponents()then return false end
  local bag=outer:getContainingItem()
  if not bag or world:getItem()~=bag or bag:getWorldItem()~=world or not floorView(actor,bag)then return false end
  square=world:getSquare();object=world
  if not square or not unique(square:getObjects(),world)or not unique(square:getWorldObjects(),world)then return false end
  local wi=world:getWorldObjectIndex()
  if not integer(wi)or wi<0 or square:getWorldObjects():get(wi)~=world then return false end
 else
  local chain=worldContainer(outer,actor)
  if not plain(chain)or #chain~=1 or chain[1]~=outer then return false end
  object=outer:getParent();square=object and object:getSquare()
  if not object or object:hasComponents()or not square or not unique(square:getObjects(),object)then return false end
  local count,refs=object:getContainerCount(),0
  if not integer(count)or count<1 or count>32 then return false end
  for i=0,count-1 do if object:getContainerByIndex(i)==outer then refs=refs+1 end end
  if refs~=1 then return false end
 end
 for container in pairs(staged.containers)do
  if container:getVehiclePart()~=nil or not container:isExistYet()then return false end
 end
 local cell=worldGlobals.getCell()
 if not cell or classifier(cell)~='IsoCell'then return false end
 local function anchored(s)
  if not s or classifier(s)~='IsoGridSquare'then return false end
  local x,y,z=s:getX(),s:getY(),s:getZ()
  return integer(x)and integer(y)and integer(z)and math.abs(x)<=10000000 and math.abs(y)<=10000000 and math.abs(z)<=32
   and cell:getGridSquare(x,y,z)==s
 end
 local origin=actor:getCurrentSquare()
 if not anchored(origin)or not anchored(square)or origin:getZ()~=square:getZ()
  or math.abs(origin:getX()-square:getX())+math.abs(origin:getY()-square:getY())>1
  or origin~=square and(origin:isBlockedTo(square)or square:isBlockedTo(origin))
  or allowLoot(square,actor)~=true then return false end
 local locator=accessMethods.locate(kit,actor)
 if not plain(locator)or locator.inv~=nil or locator.vehicle~=nil or not accessMethods.validLocator(locator)
  or locator.x~=square:getX()or locator.y~=square:getY()or locator.z~=square:getZ()then return false end
 local found,resolved,where,part=accessMethods.resolve(actor,locator)
 if found~=kit or resolved~=outer or where~=square or part~=nil or accessMethods.admit(actor,locator)~=kit then return false end
 -- Cardinal native edges use endpoint walls/doors/windows; opposite barricades
 -- and multi-tile door parts can live nearby. Include every existing object in
 -- this bounded neighborhood as public targets, not only private prefix facts.
 for _,endpoint in ipairs({origin,square})do
  for dx=-1,1 do for dy=-1,1 do
   local nearby=cell:getGridSquare(endpoint:getX()+dx,endpoint:getY()+dy,endpoint:getZ())
   if nearby and not staged.targets[nearby]then
    if not anchored(nearby)then return false end
    staged.targets[nearby]=true
    for _,values in ipairs({nearby:getObjects(),nearby:getSpecialObjects()})do
     local n=listSize(values)
     if not n then return false end
     for i=0,n-1 do
      local value=values:get(i)
      if not instance(value,'IsoObject')or value:getSquare()~=nearby then return false end
      staged.targets[value]=true
     end
    end
   end
  end end
 end
 staged.targets[object],staged.targets[origin],staged.targets[square]=true,true,true
 staged.positions[actor]=true
 return true
end
local function inspect(action,result,policy,context)
 if not plain(result)or not plain(context)or not plain(context.contracts)or not plain(policy)
  or PZSurvivorToolkit~=Toolkit or Toolkit.ActionQueueMakeupMove~=Move or Toolkit.ActionQueuePolicy~=policy
  or getClassSimpleName~=classifier or instanceof~=instance or getScriptManager~=managerOf or isClient~=client
  or ItemType~=types or not clothing or types.CLOTHING~=clothing or types.CONTAINER~=containerType or ItemBodyLocation~=locations
  or #slots~=4 or not invoker(classifier)or not invoker(instance)or not invoker(managerOf)or not invoker(client)
  or not client()then return nil end
 if Proof.closure~=closure or Proof.own~=own or type(own)~='function'or not closure(own,'SourceProof.lua')then return nil end
 for _,name in ipairs(resourceMaps)do
  if result[name]~=nil and not plain(result[name])then return nil end
 end
 if locations.MAKE_UP_FULL_FACE~=slots[1]or locations.MAKE_UP_EYES~=slots[2]
  or locations.MAKE_UP_EYES_SHADOW~=slots[3]or locations.MAKE_UP_LIPS~=slots[4]then return nil end
 if not policyOwner then
  if type(policy.inspect)~='function'or not closure(policy.inspect,'ActionQueuePolicy.lua')
   or type(policy.addContainerResources)~='function'or not closure(policy.addContainerResources,'ActionQueuePolicy.lua')then return nil end
  policyOwner,inspectPolicy,addContainers=policy,policy.inspect,policy.addContainerResources
 end
 if policy~=policyOwner or policy.inspect~=inspectPolicy or policy.addContainerResources~=addContainers then return nil end
 local actor,kit=action.character,action.item
 if not instance(actor,'IsoPlayer')or not instance(kit,'InventoryItem')or classifier(kit)~='DrainableComboItem'then return nil end
 local root=actor:getInventory()
 if classifier(root)~='ItemContainer'or root:getParent()~=actor or root:getContainingItem()~=nil
  or root:getAcceptItemFunction()~=nil or root:getOnlyAcceptCategory()~=nil then return nil end
 local q=ISTimedActionQueue.queues[actor]
 if not q or q.character~=actor or type(q.queue)~='table'then return nil end
 local index=q:indexOf(action)
 if not integer(index)or index<1 or q.queue[index]~=action then return nil end
 local parent=context.makeupMovePrefix
 if parent and(not plain(parent)or parent.queue~=q or not integer(parent.index)or index>=parent.index)then return nil end
 local staged={items={},itemTypes={},outputTypes={},containers={},containerOwners={},targets={},positions={},knownInputs=true}
 local function containerClean(container)
  if not instance(container,'ItemContainer')or classifier(container)~='ItemContainer'
   or container:getAcceptItemFunction()~=nil or container:getOnlyAcceptCategory()~=nil then return false end
  local kind=container:getType()
  return kind~='floor'and kind~='proximityInv'and kind~='twistInv_corpses'and kind~='TradeUI'
 end
 local function leaf(item,container,world)
  if (not world and not containerClean(container))or item:getContainer()~=container or item:getWorldItem()~=world or item:hasComponents()
   or actor:getPrimaryHandItem()==item or actor:getSecondaryHandItem()==item then return false end
  local id,kind=item:getID(),item:getFullType()
  if not integer(id)or id<1 or id>2147483647 or type(kind)~='string'or not kind:match('^[^.]+%.[^.]+$')
   or staged.items[id]then return false end
  if world then
   staged.items[id],staged.itemTypes[kind]=true,true
   return true
  end
  local values=container:getItems()
  if classifier(values)~='ArrayList'then return false end
  local count=values:size()
  if not integer(count)or count<0 then return false end
  local refs,ids=0,0
  for i=0,count-1 do
   local value=values:get(i)
   if value==item then refs=refs+1 end
   if value:getID()==id then ids=ids+1 end
  end
  if refs~=1 or ids~=1 or container:getItemById(id)~=item then return false end
  staged.items[id],staged.itemTypes[kind]=true,true
  return true
 end
 local source=kit:getContainer()
 local uses=kit:getCurrentUses()
 if not leaf(kit,source)or not integer(uses)or uses<1
  or kit:getReplaceOnDeplete()~=nil or kit:getWeightEmpty()~=0
  or not finite(kit:getActualWeight())or kit:getActualWeight()<0 then return nil end
 local manager=managerOf()
 if classifier(manager)~='ScriptManager'then return nil end
 -- Follow the same carried shape as Policy, but prove every native backref and
 -- direct membership before asking the shared footprint helper to traverse it.
 local container,reached,world=source,false,nil
 for depth=1,32 do
  if not containerClean(container)or staged.containers[container]then return nil end
  staged.containers[container]=true
  if container==root then reached=true;break end
  local bag=container:getContainingItem()
  if not bag then
   if container:getParent()==nil then return nil end
   reached=worldProof(actor,kit,container,nil,staged);break
  end
  if container:getParent()~=nil then return nil end
  if not containerType or not instance(bag,'InventoryContainer')or classifier(bag)~='InventoryContainer'
   or bag:getInventory()~=container or bag:hasComponents()then return nil end
  local script=bag:getScriptItem()
  if manager:FindItem(bag:getFullType())~=script or not scriptClean(script,bag:getFullType(),containerType)
   then return nil end
  world=bag:getWorldItem()
  if not leaf(bag,bag:getContainer(),world)then return nil end
  staged.containerOwners[bag:getID()]=true
  if world then reached=worldProof(actor,kit,container,world,staged);break end
  container=bag:getContainer()
 end
 if not reached then return nil end
 -- B42 getUses aliases this charge counter; there is no separate stack split.
 -- The last charge additionally needs the shared native removal/sender proof.
 if uses==1 and(not plain(FinalUse)or FinalUse.supports~=finalSupports
  or type(finalSupports)~='function'or not closure(finalSupports,'MakeupFinalUse.lua')
  or not finalSupports(actor,kit))then return nil end
 addContainers(staged,source)
 if staged.knownInputs~=true then return nil end
 local output=manager:FindItem(action.type)
 if not scriptClean(output,action.type)then return nil end
 local selected=false
 for _,slot in ipairs(slots)do
  if slot==output:getBodyLocation()then selected=true end
  local old=actor:getWornItem(slot)
  if old and(not instance(old,'InventoryItem')or classifier(old)~='Clothing'or not leaf(old,root)or old:getBodyLocation()~=slot
   or manager:FindItem(old:getFullType())~=old:getScriptItem()
   or not scriptClean(old:getScriptItem(),old:getFullType()))then return nil end
 end
 if not selected or not plain(MakeUpDefinitions)or not plain(MakeUpDefinitions.makeup)then return nil end
 local allowed=false
 for _,definition in ipairs(MakeUpDefinitions.makeup)do
  if not plain(definition)or not plain(definition.makeuptypes)then return nil end
  if definition.item==action.type and definition.makeuptypes[kit:getMakeUpType()]then allowed=true end
 end
 if not allowed then return nil end
 staged.outputTypes[action.type]=true
 -- Containers bound this snapshot/prefix. Public crossings use ancestor
 -- IDs/types from the shared helper and the existing transfer-capacity guard.
 local function conflict(c)
  if not plain(c)or c.knownInputs==false or c.unknownOutputs or c.hands==actor or c.equipment==actor then return true end
  for _,name in ipairs({'items','containerOwners','containers','targets','positions','itemTypes','dynamicInputs','dynamicInputsByType','outputTypes'})do
   if c[name]~=nil and not plain(c[name])then return true end
  end
  if c.targets and c.targets[actor]~=nil then return true end
  for position in pairs(staged.positions)do if c.positions and c.positions[position]~=nil then return true end end
  for target in pairs(staged.targets)do if c.targets and c.targets[target]~=nil then return true end end
  for container in pairs(staged.containers)do
   if c.containers and c.containers[container]~=nil then return true end
  end
  for id in pairs(staged.items)do
   if c.items and c.items[id]~=nil or c.containerOwners and c.containerOwners[id]~=nil then return true end
  end
  for _,map in ipairs({staged.itemTypes,staged.outputTypes})do for kind in pairs(map)do
   if c.itemTypes and c.itemTypes[kind]~=nil or c.dynamicInputs and c.dynamicInputs[kind]~=nil
    or c.outputTypes and c.outputTypes[kind]~=nil
    or c.dynamicInputsByType and c.dynamicInputsByType[kind:match('[^.]+$')]~=nil then return true end
  end end
  return false
 end
 local members={}
 for i=1,index do members[i]=q.queue[i]end
 context.makeupMovePrefix={queue=q,index=index}
 local ok,blocker=pcall(function()
  for i=index-1,1,-1 do
   local previous=members[i]
   if not previous or previous==action or q.queue[i]~=previous or q:indexOf(previous)~=i
    or conflict(inspectPolicy(previous,context))then return previous or action end
  end
  for i=1,index do if q.queue[i]~=members[i]then return members[i]or action end end
 end)
 context.makeupMovePrefix=parent
 if not ok then return nil end
 if blocker then return nil,blocker end
 return staged
end
function Move.apply(action,result,policy,context)
 local ok,staged,blocker=pcall(inspect,action,result,policy,context)
 if not ok or not staged then result.pendingMoveBlocker=blocker or action;return false end
 -- Do not leak partial resources, or alter cancellation, when proof fails.
 for _,name in ipairs(resourceMaps)do
  result[name]=result[name]or{}
  for key,value in pairs(staged[name])do result[name][key]=value end
 end
 result.knownInputs,result.unknownOutputs=true,false
 result.pendingMoveBlocker=nil
 return true
end
return Move
