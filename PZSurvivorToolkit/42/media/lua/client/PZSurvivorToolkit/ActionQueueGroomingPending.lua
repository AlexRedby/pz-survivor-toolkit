-- Complete conservative footprints, not projected cosmetic results. The shared
-- policy retains ordering on the actor's appearance, equipment and exact tool.
local Proof=require 'PZSurvivorToolkit/SourceProof'
local TextBinding=require 'PZSurvivorToolkit/TextResolverProof'
local textMatches=TextBinding and TextBinding.matches
local Costs=require 'PZSurvivorToolkit/ActionQueueGroomingCosts'
local applyCosts=Costs and Costs.apply
local Pending={}
local Toolkit,base=PZSurvivorToolkit,ISBaseTimedAction
if not Toolkit or type(base)~='table'then
 function Pending.adoptBase()return false end
 function Pending.apply()return false end
 return Pending
end
Toolkit.ActionQueueGroomingPending=Pending
local methods,adopted,globals={},{},{}
for name,callback in pairs(base)do if type(callback)=='function'and name~='derive'then methods[name]=callback end end
local required={'isValidStart','isValid','isUsingTimeout','update','forceComplete','forceStop','forceCancel','getJobDelta',
 'setJobDelta','resetJobDelta','waitToStart','interruptWaitToStart','start','isStarted','stop','perform','getDuration',
 'create','begin','setCurrentTime','setTime','adjustMaxTime','setActionAnim','setOverrideHandModels','setOverrideHandModelsString',
 'overrideWeaponType','restoreWeaponType','setAnimVariable','addAfter','beginAddingActions','endAddingActions','getDeltaModifiers','new'}
local globalNames={'getClassSimpleName','getHairStylesInstance','getBeardStylesInstance','sendHumanVisual','triggerEvent',
 'getText','getCore','isClient','isServer'}
for _,name in ipairs(globalNames)do globals[name]=_G[name]end
local colorOwner,colorNew,sendStats=ImmutableColor,ImmutableColor and ImmutableColor.new,sendItemStats
local function java(callback)
 if type(callback)~='function'then return false end
 local ok,kind=pcall(globals.getClassSimpleName,callback)
 return ok and (kind=='LuaJavaInvoker'or kind=='MultiLuaJavaInvoker')
end
function Pending.adoptBase(name,previous,replacement)
 if (name~='begin'and name~='stop')or ISBaseTimedAction~=base or base[name]~=replacement or methods[name]~=previous
  or not Proof.closure(previous,'ISBaseTimedAction.lua')or not Proof.closure(replacement,'ActionQueue.lua')then return false end
 methods[name],adopted[name]=replacement,replacement
 return true
end
local function callbacks(action,snapshot)
 if Toolkit.ActionQueueGroomingPending~=Pending or ISBaseTimedAction~=base then return false,'owner'end
 for _,name in ipairs(required)do if not methods[name]then return false,'base-missing:'..name end end
 for name,callback in pairs(base)do
  if type(callback)=='function'and name~='derive'and methods[name]~=callback then return false,'base-added:'..name end
 end
 for name,callback in pairs(methods)do
  if base[name]~=callback or not (Proof.closure(callback,'ISBaseTimedAction.lua')
    or adopted[name]==callback and Proof.closure(callback,'ActionQueue.lua'))
   or action[name]~=(snapshot.methods[name]or callback)then return false,'base:'..name end
 end
 for _,name in ipairs({'serverStart','serverStop','complete','animEvent','invoke'})do
  if (action[name]or false)~=(snapshot.methods[name]or methods[name]or false)then return false,'dispatch:'..name end
 end
 for name,callback in pairs(action)do
  if type(callback)=='function'and callback~=(snapshot.methods[name]or methods[name])then return false,'instance:'..name end
 end
 local classifier=globals.getClassSimpleName
 if type(classifier)~='function'or getClassSimpleName~=classifier then return false,'classifier'end
 for _,name in ipairs(globalNames)do
  local callback=globals[name]
  if name=='getText'and _G[name]~=callback then
   if not TextBinding or TextBinding.matches~=textMatches or Toolkit.TextResolverProof~=TextBinding
    or type(textMatches)~='function'or not textMatches(_G[name],callback)then return false,'global-changed:'..name end
  else
   if type(callback)~='function'or _G[name]~=callback then return false,'global-changed:'..name end
   local ok,kind=pcall(classifier,callback)
   if not ok or kind~='LuaJavaInvoker'and kind~='MultiLuaJavaInvoker'then return false,'global-class:'..name..':'..tostring(kind)end
  end
 end
 return true
end
local function carried(item,actor)
 if not instanceof(item,'InventoryItem')or instanceof(item,'InventoryContainer')then return false end
 local id=item:getID()
 if type(id)~='number'or id%1~=0 then return false end
 local container,seen=item:getContainer(),{}
 if not instanceof(container,'ItemContainer')or not container:getItems():contains(item)or container:getItemById(id)~=item then return false end
 while instanceof(container,'ItemContainer')and not seen[container]do
  seen[container]=true
  if not container:isExistYet()or container:getAcceptItemFunction()~=nil or container:getOnlyAcceptCategory()~=nil then return false end
  if container==actor:getInventory()then return true end
  local kind=container:getType()
  if kind=='floor'or kind=='proximityInv'or kind=='twistInv_corpses'or kind=='TradeUI'then return false end
  local bag=container:getContainingItem()
  if not instanceof(bag,'InventoryContainer')then return false end
  local parent=bag:getContainer()
  if not instanceof(parent,'ItemContainer')or not parent:getItems():contains(bag)then return false end
  container=parent
 end
 return false
end
local function reject(result,reason)result.pendingMoveBlocker=reason;return false end
local function noStylingCost(name)
 return (not (name:find('Mohawk',1,true)or name:find('Spike',1,true)or name:find('GreasedBack',1,true))or name=='MohawkFlat')
  and not name:find('Buffont',1,true)and not name:find('Greased',1,true)
end
function Pending.apply(profile,snapshot,action,result,policy,context)
 local actor=action.character
 local token=action.toolkitQueueOperation
 local trusted,why=callbacks(action,snapshot)
 if not trusted then return reject(result,why)end
 if not instanceof(actor,'IsoPlayer')or not actor:isLocalPlayer()
  or getSpecificPlayer(actor:getPlayerNum())~=actor or actor:isDead()or actor:isAsleep()
  or action.action or action.started or action.toolkitNativeTransaction or action.toolkitNativeKind
  or token~=nil and type(token)~='table'
  or type(token)=='table'and (token.toolkitStarted or token.toolkitCancelled)
  or not policy or type(policy.addContainerResources)~='function'then return reject(result,'episode')end
 local tool=action.item
 if profile.name=='ISDyeHair'then tool=action.hairDye end
 if tool and not carried(tool,actor)then return reject(result,'tool')end
 if profile.name=='ISCutHair'then
  if type(action.hairStyle)~='string'or action.hairStyle==''or action.maxTime~=action.maxTimeInit
   or (action.maxTimeInit~=100 and action.maxTimeInit~=300)then return reject(result,'hair-duration')end
  local styles=globals.getHairStylesInstance()
  if globals.getClassSimpleName(styles)~='HairStyles'then return reject(result,'hair-catalog')end
  local style
  if actor:isFemale()then style=styles:FindFemaleStyle(action.hairStyle)
  else style=styles:FindMaleStyle(action.hairStyle)end
  if not style or globals.getClassSimpleName(style)~='HairStyle'or style:getName()~=action.hairStyle then return reject(result,'hair-style')end
  if action.maxTimeInit==300 then
   if not tool or style:isAttachedHair()then return reject(result,'cut-tool')end
  elseif not style:isAttachedHair()and actor:getHumanVisual():getNonAttachedHair()~=action.hairStyle then return reject(result,'untie-target')end
  if not noStylingCost(style:getName())then
   if not Costs or Costs.apply~=applyCosts or Toolkit.ActionQueueGroomingCosts~=Costs
    or not applyCosts or not Proof.closure(applyCosts,'ActionQueueGroomingCosts.lua')then return reject(result,'styling-proof')end
   local accepted,reason=applyCosts(action,result,policy,carried,context)
   if not accepted then return reject(result,'styling-costs:'..tostring(reason))end
  end
 elseif profile.name=='ISTrimBeard'then
  if not tool or action.maxTime~=300 or type(action.beardStyle)~='string'then return reject(result,'beard-input')end
  if action.beardStyle~=''then
   local styles=globals.getBeardStylesInstance()
   if globals.getClassSimpleName(styles)~='BeardStyles'then return reject(result,'beard-catalog')end
   local style=styles:FindStyle(action.beardStyle)
   if not style or globals.getClassSimpleName(style)~='BeardStyle'or style:getName()~=action.beardStyle then return reject(result,'beard-style')end
  end
 elseif profile.name=='ISDyeHair'then
  if not tool or action.maxTime~=120 or action.beard~=nil and type(action.beard)~='boolean'
   or actor:isTimedActionInstant()then return reject(result,'dye-input')end
  if not colorOwner or ImmutableColor~=colorOwner or colorOwner.new~=colorNew or sendItemStats~=sendStats
   or not java(colorNew)or not java(sendStats)then return reject(result,'dye-globals')end
  local fluid=tool:getFluidContainer()
  if not fluid or globals.getClassSimpleName(fluid)~='FluidContainer'then return reject(result,'dye-fluid')end
  local amount,capacity=fluid:getAmount(),fluid:getCapacity()
  if type(amount)~='number'or amount~=amount or amount<=0 or amount==math.huge
   or type(capacity)~='number'or capacity~=capacity or capacity<=0 or capacity==math.huge
   or amount>capacity then return reject(result,'dye-amount')end
  -- Native completion reads this exact live fluid color and only decreases its
  -- amount (clamped at zero). It creates/replaces no items or reserved output.
 else return reject(result,'unsupported-family')end
 result.knownInputs=true
 -- Native animation/appearance and P4 restore dependencies remain ordered;
 -- unrelated reading and radio controls do not use these actor resources.
 result.hands,result.equipment=actor,actor
 result.capacityNonIncreasing=true
 if tool then policy.addContainerResources(result,tool:getContainer())end
 return result.knownInputs~=false
end
return Pending
