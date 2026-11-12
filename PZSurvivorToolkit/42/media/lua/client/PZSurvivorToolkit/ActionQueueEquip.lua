-- Pending ordinary native Equip only. The pure hand projection has no
-- authority until every non-hand transition has a source-owned certificate.
require 'TimedActions/ISEquipWeaponAction'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Hands=require 'PZSurvivorToolkit/ActionQueueHands'
local Effects=require 'PZSurvivorToolkit/ActionQueueHandEffects'
local Toolkit=PZSurvivorToolkit
local Equip={}
Toolkit.ActionQueueEquip=Equip
local kind,equal,each,array,call=type,rawequal,pairs,ipairs,pcall
local meta=toolkitLuaMetatableMatches
local class,base,object=ISEquipWeaponAction,ISBaseTimedAction,ISBaseObject
local chain,closure,matches,own=Proof.nativeActionClassChain,Proof.closure,Proof.matches,Proof.own
local handResource=Hands and Hands.equipResource
local certify=Effects and Effects.certify
local inspect,bindingsTrusted,adoptBase
local function plain(value)return kind(value)=='table'and kind(meta)=='function'and meta(value,nil)end
local watch=Proof.captureBindings({{owner=_G,keys={'PZSurvivorToolkit','toolkitLuaMetatableMatches','type','rawequal','pairs','ipairs','pcall','select','math',
 'instanceof','getSpecificPlayer','getClassSimpleName','getFirstLineOfClosure','isClient','isServer','isMultiplayer','getPlayerHotbar',
 'getPlayerInventory','sendEquip','triggerEvent','syncItemActivated','ItemTag','ItemType'}},
 {owner=Proof,keys={'nativeActionClassChain','closure','matches','own','captureBindings'}},
 {owner=Toolkit,keys={'ActionQueueHands','ActionQueueHandEffects','ActionQueueEquip'}}})
local line=getFirstLineOfClosure
local roles={isValid=6,update=16,start=20,animEvent=49,stop=63,isAlreadyEquipped=102,perform=114,complete=140,new=254}
local methods,baseMethods,inherited={},{},{}
local directBaseNames={'new','stop','perform'}
local inheritedNames={'begin','create','adjustMaxTime','isValidStart','isUsingTimeout','waitToStart','interruptWaitToStart',
 'isStarted','forceComplete','forceStop','forceCancel','getDeltaModifiers','getJobDelta','setJobDelta','resetJobDelta',
 'setActionAnim','setAnimVariable','setOverrideHandModels','setOverrideHandModelsString','overrideWeaponType','restoreWeaponType','getDuration'}
-- Native metadata reports the first compiled instruction, including an end
-- instruction for empty methods; it is not the declaration line.
local baseRoles={new=174,stop=64,perform=69,begin=84,create=79,adjustMaxTime=100,isValidStart=9,isUsingTimeout=17,waitToStart=49,interruptWaitToStart=53,
 isStarted=60,forceComplete=25,forceStop=29,forceCancel=34,getDeltaModifiers=171,getJobDelta=37,setJobDelta=41,resetJobDelta=45,
 setActionAnim=126,setAnimVariable=150,setOverrideHandModels=134,setOverrideHandModelsString=138,overrideWeaponType=142,restoreWeaponType=146,getDuration=75}
local optionalNames={'serverStart','serverStop','failedPathfind','succeededPathfind','timedActionPathfind'}
local initial=kind(chain)=='function'and chain(object,base,class,true)
if initial then
 for name in each(roles)do methods[name]=own(class,name)end
 for _,name in array(directBaseNames)do baseMethods[name]=base[name]or false end
 for _,name in array(inheritedNames)do inherited[name]=class[name]or false end
 for _,name in array(optionalNames)do inherited[name]=false;if class[name]~=nil then initial=false end end
end
local enums={}
for owner,names in each({[ItemTag or false]={'REPLACE_PRIMARY','WEARABLE','LIGHTER'},[ItemType or false]={'RADIO'}})do
 if kind(owner)=='table'or kind(owner)=='userdata'then
  for _,name in array(names)do enums[#enums+1]={owner=owner,name=name,value=owner[name]}end
 end
end
bindingsTrusted=function()
 return plain(_G)and plain(Toolkit)and plain(Equip)and plain(Proof)and plain(Hands)and plain(Effects)
  and equal(PZSurvivorToolkit,Toolkit)and equal(Toolkit.ActionQueueEquip,Equip)
  and equal(Equip.inspect,inspect)and equal(Equip.bindingsTrusted,bindingsTrusted)and equal(Equip.adoptBase,adoptBase)
  and equal(Toolkit.ActionQueueHands,Hands)and equal(Hands.equipResource,handResource)
  and equal(Toolkit.ActionQueueHandEffects,Effects)and equal(Effects.certify,certify)
  and kind(watch)=='function'and watch()
end
local nativeSources,queueSource
adoptBase=function(name,previous,replacement)
 if (name~='begin'and name~='stop')or not bindingsTrusted()or not initial or ISBaseTimedAction~=base
  or base[name]~=replacement or baseMethods[name]~=nil and baseMethods[name]~=previous
  or inherited[name]~=nil and inherited[name]~=previous
  or not closure(previous,'ISBaseTimedAction.lua')or not closure(replacement,'ActionQueue.lua')then return false end
 if queueSource==nil then queueSource=matches('media/lua/client/PZSurvivorToolkit/ActionQueue.lua',961891934,'PZSurvivorToolkit',true)end
 if not queueSource then return false end
 if baseMethods[name]~=nil then baseMethods[name]=replacement end
 if inherited[name]~=nil then inherited[name]=replacement end
 return true
end
local function source(action)
 -- Prove ancestry before any inherited action/class lookup on Kahlua.
 if not bindingsTrusted()or not initial or Proof.nativeActionClassChain~=chain
  or not chain(object,base,class,false)or ISEquipWeaponAction~=class or ISBaseTimedAction~=base
  or kind(action)~='table'or not meta(action,class)or action.Type~='ISEquipWeaponAction'
  or kind(line)~='function'or getFirstLineOfClosure~=line then return false end
 if nativeSources==nil then
  nativeSources=matches('media/lua/shared/TimedActions/ISEquipWeaponAction.lua',4117952124,nil,true)
   and matches('media/lua/shared/TimedActions/ISBaseTimedAction.lua',3104185167,nil,true)
   and matches('media/lua/client/PZSurvivorToolkit/ActionQueueHands.lua',430503623,'PZSurvivorToolkit',true)
   and matches('media/lua/client/PZSurvivorToolkit/ActionQueueHandEffects.lua',3027003558,'PZSurvivorToolkit',true)
   and closure(handResource,'ActionQueueHands.lua')and closure(certify,'ActionQueueHandEffects.lua')
 end
 if not nativeSources then return false end
 for name,first in each(roles)do
  local callback=methods[name]
  if kind(callback)~='function'or own(class,name)~=callback or action[name]~=callback
   or not closure(callback,'ISEquipWeaponAction.lua')or line(callback)~=first then return false end
 end
 for name,value in each(class)do if kind(value)=='function'and methods[name]~=value then return false end end
 for name,value in each(baseMethods)do
  if base[name]~=value or not(closure(value,'ISBaseTimedAction.lua')and line(value)==baseRoles[name]
   or name=='stop'and closure(value,'ActionQueue.lua')and line(value)==327)then return false end
 end
 for name,value in each(inherited)do
  if (action[name]or false)~=value then return false end
  if value~=false and not(closure(value,'ISBaseTimedAction.lua')and line(value)==baseRoles[name]
   or name=='begin'and closure(value,'ActionQueue.lua')and line(value)==62)then return false end
 end
 for _,slot in array(enums)do if slot.value==nil or slot.owner[slot.name]~=slot.value then return false end end
 if #enums~=4 then return false end
 for name,value in each(action)do if kind(value)=='function'and methods[name]~=value and inherited[name]~=value then return false end end
 return not action.onStartFunc and not action.onCompleteFunc and not action.onCancelFunc and not action.onFailFunc
  and not action.additionalTest and not action.additionalContext and not action.retriggerLastAction
end
local function finite(value)return kind(value)=='number'and value==value and value>-math.huge and value<math.huge end
local function booleanOrAbsent(value)return value==nil or kind(value)=='boolean'end
local function pending(action)
 local token=action.toolkitQueueOperation
 if token~=nil and not plain(token)then return false end
 if token and token.toolkitContinuations~=nil and token.toolkitContinuations~=0 then return false end
 return not action.action and not action.started and not action._isAddingActions
  and action.toolkitNativeTransaction==nil and action.toolkitNativeKind==nil
  and action.toolkitQueueReturn==nil and not action.toolkitQueueLinked
  and not(kind(token)=='table'and(token.toolkitStarted or token.toolkitCancelled))
  and not action.fromHotbar and action.sound==nil and action.weaponType==nil and action.animSpeed==1
  and action.ignoreHandsWounds==true and action.stopOnAim==false and action.stopOnWalk==false and action.stopOnRun==true
  and action.useProgressBar==true and action.caloriesModifier==1
  and booleanOrAbsent(action.primary)and booleanOrAbsent(action.twoHands)
  and booleanOrAbsent(action.alwaysTurnOn)and not action.alwaysTurnOn
  and finite(action.maxTimeInit)and action.maxTimeInit>=1 and finite(action.maxTime)and action.maxTime>=1
  and(action.maxTime==1 or action.maxTime==action.maxTimeInit)
end
local function itemRow(actor,root,item,items,types,resources,seen)
 if item==nil then return false end
 if not instanceof(item,'InventoryItem')then return end
 local javaClass=getClassSimpleName(item)
 if javaClass~='ComboItem'and javaClass~='HandWeapon'then return end
 local id,fullType=item:getID(),item:getFullType()
 if not finite(id)or id%1~=0 or id==-1 or kind(fullType)~='string'or fullType==''
  or item:getContainer()~=root or root:getItemWithID(id)~=item
  or item:getAttachedSlot()~=-1 or item:isForceDropHeavyItem()~=false or item:canBeActivated()~=false
  or item:getWorldItem()or item:getIsCraftingConsumed()~=false or item:hasTag(ItemTag.REPLACE_PRIMARY)~=false
  or item:hasTag(ItemTag.WEARABLE)~=false or actor:isEquippedClothing(item)~=false then return end
 local both=item:isRequiresEquippedBothHands()
 local weapon=instanceof(item,'HandWeapon')
 if kind(both)~='boolean'or kind(weapon)~='boolean'or weapon~=(javaClass=='HandWeapon')then return end
 local swing=weapon and item:getSwingAnim()or nil
 if swing~=nil and kind(swing)~='string'then return end
 local row={item=item,requiresBoth=both,handWeapon=weapon,handgun=weapon and swing=='Handgun'}
 if seen[id]then if not equal(seen[id],item)then return end
 else
  seen[id]=item;items[#items+1]=item;types[fullType]=true
  resources[#resources+1]={domain='item',key=id,facts={item=item,location=root},requires={{field='location',equal=root}}}
 end
 return row
end
local function inspectPending(action)
 if not source(action)or not pending(action)or isClient()or isServer()or isMultiplayer()then return end
 local actor=action.character
 if not instanceof(actor,'IsoPlayer')or getClassSimpleName(actor)~='IsoPlayer'
  or getSpecificPlayer(actor:getPlayerNum())~=actor or actor:isDead()or actor:isAsleep()then return end
 local root=actor:getInventory()
 if not instanceof(root,'ItemContainer')or root:getParent()~=actor or root:getContainingItem()~=nil then return end
 local items,types,resources,seen={},{},{},{}
 -- The native replacement branch short-circuits on this exact false tag.
 -- Retain the canonical back item as an equipment/location dependency; do
 -- not inspect extras, create its replacement or claim a worn-state write.
 local back=actor:getClothingItem_Back()
 if back~=nil then
  if not instanceof(back,'InventoryItem')or getClassSimpleName(back)~='InventoryContainer'
   or back:hasTag(ItemTag.REPLACE_PRIMARY)~=false then return end
  local id,fullType=back:getID(),back:getFullType()
  if not finite(id)or id%1~=0 or id==-1 or kind(fullType)~='string'or fullType==''
   or back:getContainer()~=root or root:getItemWithID(id)~=back then return end
  seen[id]=back;types[fullType]=true
  resources[#resources+1]={domain='item',key=id,facts={item=back,location=root},requires={{field='location',equal=root}}}
 end
 local incoming=itemRow(actor,root,action.item,items,types,resources,seen)
 if not incoming then return end
 local primaryItem,secondaryItem=actor:getPrimaryHandItem(),actor:getSecondaryHandItem()
 local primary=itemRow(actor,root,primaryItem,items,types,resources,seen)
 local secondary=itemRow(actor,root,secondaryItem,items,types,resources,seen)
 if primary==nil or secondary==nil then return end
 local two=action.twoHands==true
 local supportsTwo=false
 if incoming.handWeapon then supportsTwo=action.item:isTwoHandWeapon()end
 if incoming.handWeapon and kind(supportsTwo)~='boolean'or incoming.requiresBoth and not two
  or incoming.handWeapon and not supportsTwo and two and not incoming.requiresBoth then return end
 local savedPrimary,savedTwo,savedItem=action.primary,action.twoHands,action.item
 local mode=two and'both'or action.primary==true and'primary'or'secondary'
 local identityTypes={}
 for id,item in each(seen)do identityTypes[id]=item:getFullType()end
 local function stable()
  if not source(action)or not pending(action)or action.character~=actor or action.item~=savedItem
   or action.primary~=savedPrimary or action.twoHands~=savedTwo or actor:getInventory()~=root
   or root:getParent()~=actor or root:getContainingItem()~=nil or isClient()or isServer()or isMultiplayer()
   or getSpecificPlayer(actor:getPlayerNum())~=actor or actor:isDead()or actor:isAsleep()
   or actor:getPrimaryHandItem()~=primaryItem or actor:getSecondaryHandItem()~=secondaryItem
   or actor:getClothingItem_Back()~=back then return false end
  if back and back:hasTag(ItemTag.REPLACE_PRIMARY)~=false then return false end
  for id,item in each(seen)do
   if item:getID()~=id or item:getFullType()~=identityTypes[id]or item:getContainer()~=root or root:getItemWithID(id)~=item then return false end
  end
  for _,row in array({incoming,primary,secondary})do
   if row~=false then
    local current=itemRow(actor,root,row.item,{},{},{},{})
    if not current or current.requiresBoth~=row.requiresBoth or current.handWeapon~=row.handWeapon or current.handgun~=row.handgun then return false end
   end
  end
  return not incoming.handWeapon or savedItem:isTwoHandWeapon()==supportsTwo
 end
 local check=certify(actor,items)
 if kind(check)~='function'then return end
 local hand=handResource(actor,{primary=primary,secondary=secondary},incoming,mode)
 -- Projection is pure; validate once after its callback boundary. The
 -- certifier already checked fresh effects after source input, and the final
 -- check covers all native/source observations below without a third walk.
 if not hand or not bindingsTrusted()or not stable()or check()~=true then return end
 resources[#resources+1]=hand
 local ids={};for id in each(seen)do ids[id]=true end
 return {items=ids,itemTypes=types,targets={},hands=actor,equipment=actor,preparation=true,preparationFinish=true,
  cancelWaiting=true,cancelOperation=true,interrupt='finish-step',moveRequiresProjection=true,
  edit={version=1,complete=true,capacity='external',resources=resources}}
end
inspect=function(...)
 if select('#',...)~=1 then return end
 local ok,value=call(inspectPending,...)
 if ok then return value end
end
Equip.inspect,Equip.bindingsTrusted,Equip.adoptBase=inspect,bindingsTrusted,adoptBase
return Equip
