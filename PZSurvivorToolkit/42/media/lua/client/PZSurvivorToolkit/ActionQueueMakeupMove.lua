-- A current root snapshot is useful only while the queued prefix cannot change
-- its kit or worn cosmetics. Inspection reads native facts, never prototypes.
local Proof=require 'PZSurvivorToolkit/SourceProof'
local closure=Proof.closure
local Move={}
local Toolkit=PZSurvivorToolkit
Toolkit.ActionQueueMakeupMove=Move
local classifier,instance,managerOf,client=getClassSimpleName,instanceof,getScriptManager,isClient
local types,clothing=ItemType,ItemType and ItemType.CLOTHING
local locations=ItemBodyLocation
local slots={locations and locations.MAKE_UP_FULL_FACE,locations and locations.MAKE_UP_EYES,
 locations and locations.MAKE_UP_EYES_SHADOW,locations and locations.MAKE_UP_LIPS}
local policyOwner,inspectPolicy
local function finite(n)return type(n)=='number'and n==n and n>-math.huge and n<math.huge end
local function integer(n)return finite(n)and n%1==0 end
local function plain(t)return type(t)=='table'and getmetatable(t)==nil end
local function invoker(f)
 if type(f)~='function'then return false end
 local ok,kind=pcall(classifier,f)
 return ok and(kind=='LuaJavaInvoker'or kind=='MultiLuaJavaInvoker')
end
local function scriptClean(script,kind)
 return script and classifier(script)=='Item'and script:getFullName()==kind
  and script:getItemType()==clothing and not script:hasComponents()and not script:getObsolete()
  and script:getLuaCreate()==nil and script:getItemConfigKey()==nil and script:getItemConfig()==nil
  and script:getReplaceOnUse()==nil and script:getReplaceOnDeplete()==nil
  and finite(script:getActualWeight())and script:getActualWeight()>=0
end
local function inspect(action,result,policy,context)
 if not plain(result)or not plain(context)or not plain(context.contracts)or not plain(policy)
  or PZSurvivorToolkit~=Toolkit or Toolkit.ActionQueueMakeupMove~=Move or Toolkit.ActionQueuePolicy~=policy
  or getClassSimpleName~=classifier or instanceof~=instance or getScriptManager~=managerOf or isClient~=client
  or ItemType~=types or not clothing or types.CLOTHING~=clothing or ItemBodyLocation~=locations
  or #slots~=4 or not invoker(classifier)or not invoker(instance)or not invoker(managerOf)or not invoker(client)
  or not client()then return nil end
 if Proof.closure~=closure then return nil end
 for _,name in ipairs({'items','itemTypes','outputTypes'})do
  if result[name]~=nil and not plain(result[name])then return nil end
 end
 if locations.MAKE_UP_FULL_FACE~=slots[1]or locations.MAKE_UP_EYES~=slots[2]
  or locations.MAKE_UP_EYES_SHADOW~=slots[3]or locations.MAKE_UP_LIPS~=slots[4]then return nil end
 if not policyOwner then
  if type(policy.inspect)~='function'or not closure(policy.inspect,'ActionQueuePolicy.lua')then return nil end
  policyOwner,inspectPolicy=policy,policy.inspect
 end
 if policy~=policyOwner or policy.inspect~=inspectPolicy then return nil end
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
 local staged={items={},itemTypes={},outputTypes={}}
 local function leaf(item)
  if item:getContainer()~=root or item:getWorldItem()~=nil or item:hasComponents()
   or actor:getPrimaryHandItem()==item or actor:getSecondaryHandItem()==item then return false end
  local id,kind=item:getID(),item:getFullType()
  if not integer(id)or id<1 or id>2147483647 or type(kind)~='string'or not kind:match('^[^.]+%.[^.]+$')
   or staged.items[id]then return false end
  local values=root:getItems()
  if classifier(values)~='ArrayList'then return false end
  local count=values:size()
  if not integer(count)or count<0 then return false end
  local refs,ids=0,0
  for i=0,count-1 do
   local value=values:get(i)
   if value==item then refs=refs+1 end
   if value:getID()==id then ids=ids+1 end
  end
  if refs~=1 or ids~=1 or root:getItemById(id)~=item then return false end
  staged.items[id],staged.itemTypes[kind]=true,true
  return true
 end
 if not leaf(kit)or not integer(kit:getCurrentUses())or kit:getCurrentUses()<2
  or kit:getReplaceOnDeplete()~=nil or kit:getWeightEmpty()~=0
  or not finite(kit:getActualWeight())or kit:getActualWeight()<0 then return nil end
 local manager=managerOf()
 if classifier(manager)~='ScriptManager'then return nil end
 local output=manager:FindItem(action.type)
 if not scriptClean(output,action.type)then return nil end
 local selected=false
 for _,slot in ipairs(slots)do
  if slot==output:getBodyLocation()then selected=true end
  local old=actor:getWornItem(slot)
  if old and(not instance(old,'InventoryItem')or classifier(old)~='Clothing'or not leaf(old)or old:getBodyLocation()~=slot
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
 local function conflict(c)
  if not plain(c)or c.knownInputs==false or c.unknownOutputs or c.hands==actor or c.equipment==actor then return true end
  for _,name in ipairs({'items','containerOwners','targets','itemTypes','dynamicInputs','dynamicInputsByType','outputTypes'})do
   if c[name]~=nil and not plain(c[name])then return true end
  end
  if c.targets and c.targets[actor]~=nil then return true end
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
 for _,name in ipairs({'items','itemTypes','outputTypes'})do
  result[name]=result[name]or{}
  for key,value in pairs(staged[name])do result[name][key]=value end
 end
 result.knownInputs,result.unknownOutputs=true,false
 result.pendingMoveBlocker=nil
 return true
end
return Move
