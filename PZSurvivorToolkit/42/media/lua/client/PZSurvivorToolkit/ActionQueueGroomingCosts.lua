-- Native ISCutHair keeps its selectors late. This records every possible
-- input, never a winner or a reservation. Replacement creation is unaudited.
local Costs={}
if PZSurvivorToolkit then PZSurvivorToolkit.ActionQueueGroomingCosts=Costs end
local classifier,instance,getManager=getClassSimpleName,instanceof,getScriptManager
local tagOwner=ItemTag
local hairTag=tagOwner and tagOwner.DO_HAIRDO
local manager
local function invoker(callback)
 if type(callback)~='function'or type(classifier)~='function'then return false end
 local ok,kind=pcall(classifier,callback)
 return ok and (kind=='LuaJavaInvoker'or kind=='MultiLuaJavaInvoker')
end
if invoker(getManager)and invoker(instance)and invoker(classifier)then
 local ok,value=pcall(getManager)
 if ok then manager=value end
end
local function finite(value)return type(value)=='number'and value==value and value>-math.huge and value<math.huge end
local function count(list)
 local kind=list and classifier(list)
 if kind~='ArrayList'then return nil,'list-class:'..tostring(kind)end
 local n=list:size()
 if not finite(n)or n<0 or n%1~=0 then return nil,'list-size'end
 return n
end
local function plain(value)return type(value)=='table'and getmetatable(value)==nil end
local function fullType(value)return type(value)=='string'and value:match('^[^.]+%.[^.]+$')~=nil end
local function selectors(name)
 if type(name)~='string'then return end
 local tags=(name:find('Mohawk',1,true)or name:find('Spike',1,true)or name:find('GreasedBack',1,true))and name~='MohawkFlat'
 return {Hairgel=tags or name:find('Greased',1,true)~=nil,
  Hairspray2=tags or name:find('Buffont',1,true)~=nil},not not tags
end
-- Native Kahlua tables do not implement Lua weak keys; keep one bounded
-- evaluation boundary instead of retaining every prior context.
local lastContext,lastTagTypes
local maps={'items','itemTypes','targets','containerOwners','dynamicInputs','dynamicInputsByType'}
local function inspect(action,result,policy,carried,context)
 if type(action)~='table'or not plain(result)or type(policy)~='table'or type(policy.addContainerResources)~='function'
  or type(carried)~='function'then return nil,'arguments'end
 for _,name in ipairs(maps)do if result[name]~=nil and not plain(result[name])then return nil,'result-map:'..name end end
 local short,tagged=selectors(action.hairStyle)
 if not short then return nil,'style-name'end
 if not short.Hairgel and not short.Hairspray2 then return {} end
 if getClassSimpleName~=classifier then return nil,'global-identity:getClassSimpleName'end
 if instanceof~=instance then return nil,'global-identity:instanceof'end
 if getScriptManager~=getManager then return nil,'global-identity:getScriptManager'end
 if ItemTag~=tagOwner or not tagOwner or hairTag==nil or tagOwner.DO_HAIRDO~=hairTag then return nil,'tag-identity'end
 if not invoker(classifier)then return nil,'global-class:getClassSimpleName'end
 if not invoker(instance)then return nil,'global-class:instanceof'end
 if not invoker(getManager)then return nil,'global-class:getScriptManager'end
 if not manager or getManager()~=manager then return nil,'catalog-owner'end
 if classifier(manager)~='ScriptManager'then return nil,'catalog-class:'..tostring(classifier(manager))end
 local actor=action.character
 if not instance(actor,'IsoPlayer')then return nil,'actor-class'end
 local root=actor:getInventory()
 if not root or classifier(root)~='ItemContainer'then return nil,'inventory-class:'..tostring(root and classifier(root))end
 local staged={items={},itemTypes={},targets={},containerOwners={},dynamicInputs={},dynamicInputsByType={},knownInputs=true}
 for name,needed in pairs(short)do if needed then staged.dynamicInputsByType[name]=true end end
 -- Catalog types cover future tag candidates introduced by transfers or
 -- declared outputs, including candidates absent from this inventory today.
 local tagTypes
 if tagged then
  tagTypes=plain(context)and context==lastContext and lastTagTypes or nil
  if not tagTypes then
   tagTypes={}
   local catalog=manager:getAllItems()
   local n,why=count(catalog)
   if not n then return nil,'catalog-'..why end
   local names={}
   for i=0,n-1 do
    local script=catalog:get(i)
    if not script or classifier(script)~='Item'then return nil,'script-class:'..tostring(script and classifier(script))end
    local kind=script:getFullName()
    if not fullType(kind)then return nil,'script-fullname:'..tostring(kind)end
    if names[kind]then return nil,'script-duplicate:'..kind end
    names[kind]=true
    if script:hasTag(hairTag)then tagTypes[kind]=true end
   end
  end
  for kind in pairs(tagTypes)do staged.dynamicInputs[kind]=true end
 end
 local seenContainers,seenItems={},{}
 local function walk(container)
  if not container or classifier(container)~='ItemContainer'then return false,'container-class:'..tostring(container and classifier(container))end
  if seenContainers[container]then return false,'container-cycle'end
  seenContainers[container]=true
  local list=container:getItems()
  local n,why=count(list)
  if not n then return false,'inventory-'..why end
  for i=0,n-1 do
   local item=list:get(i)
   if not instance(item,'InventoryItem')then return false,'inventory-item-class'end
   if seenItems[item]then return false,'inventory-item-duplicate'end
   seenItems[item]=true
   local kind=item:getType()
   local hasTag=tagged and item:hasTag(hairTag)
   -- The native tag selector accepts broken items; do not filter them out.
   if short[kind]and not item:isBroken()or hasTag then
    local full,id=item:getFullType(),item:getID()
    local script=tagged and item:getScriptItem()
    if classifier(item)~='DrainableComboItem'then return false,'candidate-class:'..tostring(classifier(item))end
    if not carried(item,actor)or item:getContainer()~=container then return false,'candidate-ancestry'end
    if item:getWorldItem()~=nil then return false,'candidate-world'end
    if not fullType(full)or full:match('[^.]+$')~=kind then return false,'candidate-fulltype'end
    if not finite(id)or id%1~=0 or staged.items[id]then return false,'candidate-id'end
    if item:getReplaceOnDeplete()~=nil then return false,'candidate-replacement'end
    if item:getWeightEmpty()~=0 then return false,'candidate-weight-empty'end
    if not finite(item:getActualWeight())or item:getActualWeight()<0 then return false,'candidate-weight'end
    if actor:getPrimaryHandItem()==item or actor:getSecondaryHandItem()==item then return false,'candidate-held'end
    if tagged and (not script or classifier(script)~='Item'or script:getFullName()~=full)then return false,'candidate-script'end
    staged.items[id],staged.itemTypes[full]=true,true
    if hasTag then staged.dynamicInputs[full]=true end
    policy.addContainerResources(staged,container)
    if staged.knownInputs~=true then return false,'candidate-container-callback'end
   end
   if instance(item,'InventoryContainer')then
    local ok,why=walk(item:getInventory())
    if not ok then return false,why end
   end
  end
  return true
 end
 local complete,why=walk(root)
 if not complete then return nil,why end
 -- Policy uses one fresh context per evaluation and already caches contracts
 -- within that boundary. Retain only catalog type names, never live candidates.
 if tagTypes and plain(context)then lastContext,lastTagTypes=context,tagTypes end
 return staged
end
function Costs.apply(action,result,policy,carried,context)
 -- A denied proof must not leak a partial candidate set or bag ancestry.
 local ok,staged,why=pcall(inspect,action,result,policy,carried,context)
 if not ok then return false,'inspection-error'end
 if not staged then return false,why or 'incomplete'end
 for _,name in ipairs(maps)do
  for key,value in pairs(staged[name]or{})do
   result[name]=result[name]or{}
   result[name][key]=value
  end
 end
 return true
end
return Costs
