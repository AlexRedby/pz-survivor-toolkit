require 'TimedActions/ISWringClothing'
require 'PZSurvivorToolkit/ActionQueueDefinitions'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local ItemAdapters=require 'PZSurvivorToolkit/ActionQueueItemEditAdapters'
local Toolkit=PZSurvivorToolkit
local Wring={}
Toolkit.ActionQueueWring=Wring
local class,base,object=ISWringClothing,ISBaseTimedAction,ISBaseObject
local actualMeta,kind=toolkitLuaMetatableMatches,type
local classChain=Proof.nativeActionClassChain
local carriedLocation=ItemAdapters and ItemAdapters.pendingCarriedItemLocation
local carriedSourceTrusted
local function pendingCarriedLocation(item,actor)
 if type(ItemAdapters)~='table'or not actualMeta(ItemAdapters,nil)
  or PZSurvivorToolkit.ActionQueueItemEditAdapters~=ItemAdapters
  or type(carriedLocation)~='function'or ItemAdapters.pendingCarriedItemLocation~=carriedLocation
  or not Proof.closure(carriedLocation,'ActionQueueItemEditAdapters.lua')then return end
 if carriedSourceTrusted==nil then
  carriedSourceTrusted=Proof.matches('media/lua/client/PZSurvivorToolkit/ActionQueueItemEditAdapters.lua',809026424,'PZSurvivorToolkit',true)
 end
 if carriedSourceTrusted then return carriedLocation(item,actor)end
end
local function lookupShape(constructing)
 return type(actualMeta)=='function'and actualMeta(Proof,nil)
  and type(classChain)=='function'and Proof.nativeActionClassChain==classChain
  and classChain(object,base,class,constructing)
end
local snapshot,registered
local inspect,matches,callbacksTrusted,install
local source='native.ISWringClothing'
local ownNames={'isValid','update','start','stopSound','stop','perform','complete','getDuration','new'}
-- Native Wring calls these base owners directly even though its own overrides
-- shadow stop/perform. Other base callbacks are watched only at used lookup slots.
local directBaseNames={'new','stop','perform'}
local inheritedNames={'begin','create','adjustMaxTime','isValidStart','isUsingTimeout','waitToStart',
 'interruptWaitToStart','isStarted','forceComplete','forceStop','forceCancel','getDeltaModifiers',
 'getJobDelta','setActionAnim','setAnimVariable','setOverrideHandModels'}
-- The native LuaTimedActionNew/NetTimedAction dispatchers also read these
-- optional slots. Retain absence explicitly; adding a callback changes authority.
local optionalNames={'serverStart','serverStop','animEvent','failedPathfind','succeededPathfind','timedActionPathfind'}
local globals={instanceof=instanceof,getSpecificPlayer=getSpecificPlayer,getClassSimpleName=getClassSimpleName,
 syncItemFields=syncItemFields,math=math}
local minimum,ceiling=math.min,math.ceil
local function from(callback,file)return type(callback)=='function'and Proof.closure(callback,file)end
local function unchanged(constructing)
 if not lookupShape(constructing)then return false end
 if not snapshot or not snapshot.trusted or PZSurvivorToolkit~=Toolkit or Toolkit.ActionQueueWring~=Wring
  or ISWringClothing~=class or ISBaseTimedAction~=base or class.Type~='ISWringClothing'
  or Wring.inspect~=inspect or Wring.matches~=matches or Wring.callbacksTrusted~=callbacksTrusted or Wring.install~=install then return false end
 for name,callback in pairs(globals)do if _G[name]~=callback then return false end end
 if math.min~=minimum or math.ceil~=ceiling then return false end
 for name,callback in pairs(snapshot.classMethods)do if Proof.own(class,name)~=callback then return false end end
 for name,callback in pairs(class)do
  if type(callback)=='function'and snapshot.classMethods[name]~=callback then return false end
 end
 for name,callback in pairs(snapshot.baseMethods)do if base[name]~=callback then return false end end
 for name,callback in pairs(snapshot.inherited)do if (class[name]or false)~=callback then return false end end
 return true
end
callbacksTrusted=function(action)
 if not unchanged(false)or kind(action)~='table'or not actualMeta(action,class)or action.Type~=class.Type
  or action.onStartFunc or action.onCompleteFunc or action.onCancelFunc or action.onFailFunc
  or action.additionalTest or action.additionalContext or action.retriggerLastAction then return false end
 for name,callback in pairs(snapshot.classMethods)do if action[name]~=callback then return false end end
 for name,callback in pairs(snapshot.inherited)do if (action[name]or false)~=callback then return false end end
 for name,callback in pairs(action)do
  if type(callback)=='function'and callback~=snapshot.classMethods[name]and callback~=snapshot.inherited[name]then return false end
 end
 return true
end
local function finite(value)return type(value)=='number'and value==value and value>-math.huge and value<math.huge end
local function shape(action)
 return callbacksTrusted(action)and not action._isAddingActions
  and action.stopOnWalk==true and action.stopOnRun==true and action.stopOnAim==true
  and action.forceProgressBar==true and action.caloriesModifier==1
  and instanceof(action.character,'IsoPlayer')and instanceof(action.item,'Clothing')
end
local function pending(action)
 return not action.action and not action.started
  and action.toolkitNativeTransaction==nil and action.toolkitNativeKind==nil
  and not(type(action.toolkitQueueOperation)=='table'and action.toolkitQueueOperation.toolkitStarted)
  and finite(action.maxTime)and action.maxTime>=1 and action.maxTime<=500 and action.maxTime%1==0
end
inspect=function(action)
 if not shape(action)or not action.action and not pending(action)then return end
 local actor,item=action.character,action.item
 if getSpecificPlayer(actor:getPlayerNum())~=actor or actor:isDead()or actor:isAsleep()
  or getClassSimpleName(item)~='Clothing'then return end
 local root=actor:getInventory()
 local id,kind=item:getID(),item:getFullType()
 if not instanceof(root,'ItemContainer')or not finite(id)or id%1~=0 or type(kind)~='string'or kind==''then return end
 local location,owners=item:getContainer(),nil
 if location==root then
  -- Ordinary root items retain their direct cheap check, without bag metadata.
  if root:getItemWithID(id)~=item then return end
 elseif action.action then return
 else
  local facts
  facts,owners=pendingCarriedLocation(item,actor)
  if not facts then return end
  location=facts.location
 end
 -- Actor identity validates ownership. Native completion changes only this
 -- garment: animation/hand models and metabolic target are execution state,
 -- not a shared actor result consumed by another pending wring contract.
 local result={items={[id]=true},itemTypes={[kind]=true},targets={},interrupt='finish-step',capacityNonIncreasing=true}
 if owners then
  -- Newly admitted carried bodies need the complete fetch/route projection;
  -- an unknown preparation must not fall back to the old root-only policy.
  result.moveRequiresProjection=true
  result.containerOwners={}
  for ownerID,ownerType in pairs(owners)do result.containerOwners[ownerID]=true;result.itemTypes[ownerType]=true end
 end
 if action.action then
  -- An in-flight action has a known footprint, not a forecast or edit right.
  -- Do not read current wetness while the native authority may be changing it.
  result.cancelWaiting,result.cancelOperation=false,false
  return result
 end
 local wetness=item:getWetness()
 if not finite(wetness)or wetness<0 or wetness>100 then return end
 local cap=item:getBodyLocation()=='Shoes'and 60 or 10
 result.cancelWaiting,result.cancelOperation=true,true
 -- Native complete only caps wetness. Its setter and item sync do not change
 -- actualWeight/contents used by native capacity. Retain the original transfer
 -- weight bound anyway: this property grants no future drying-space credit.
 result.edit={version=1,complete=true,capacity='external',resources={{domain='item',key=id,
  facts={item=item,location=location,wetness=wetness},
  requires={{field='location',equal=root},{field='wetness',above=10}},
  effects={{field='wetness',cap=cap}},bounds={wetness={min=0,max=100}}}}}
 return result
end
matches=function(action)return shape(action)and(action.action~=nil or pending(action))end
install=function()
 if snapshot then return unchanged(true)end
 if not lookupShape(true)then snapshot={trusted=false};return false end
 local trusted=type(class)=='table'and type(base)=='table'and class.Type=='ISWringClothing'
  and Proof.matches('media/lua/shared/TimedActions/ISWringClothing.lua',461602091,nil,true)
  and Proof.matches('media/lua/shared/TimedActions/ISBaseTimedAction.lua',3104185167,nil,true)
 for _,callback in pairs(globals)do if callback~=math and type(callback)~='function'then trusted=false end end
 local classMethods,baseMethods,inherited={},{},{}
 for name,callback in pairs(class or {})do
  if type(callback)=='function'then
   classMethods[name]=callback
   if name~='derive'and not from(callback,'ISWringClothing.lua')then trusted=false end
  end
 end
 for _,name in ipairs(ownNames)do if not classMethods[name]then trusted=false end end
 local function baseOrigin(name,callback)
  return from(callback,'ISBaseTimedAction.lua')or(name=='begin'or name=='stop')and from(callback,'ActionQueue.lua')
 end
 for _,name in ipairs(directBaseNames)do
  local callback=base and base[name]
  baseMethods[name]=callback or false
  if not baseOrigin(name,callback)then trusted=false end
 end
 for _,name in ipairs(inheritedNames)do
  local callback=class and class[name]
  inherited[name]=callback or false
  if not baseOrigin(name,callback)then trusted=false end
 end
 for _,name in ipairs(optionalNames)do
  inherited[name]=false
  if class and class[name]~=nil then trusted=false end
 end
 snapshot={trusted=trusted,classMethods=classMethods,baseMethods=baseMethods,inherited=inherited}
 if not registered then
  Toolkit.ActionQueueDefinitions.registerBehavior(source,{types={'ISWringClothing'},matches=matches,inspect=inspect})
  registered=true
 end
 return unchanged(true)
end
Wring.inspect,Wring.matches,Wring.callbacksTrusted,Wring.install=inspect,matches,callbacksTrusted,install
if Events and Events.OnGameStart then Events.OnGameStart.Add(install)end
return Wring
