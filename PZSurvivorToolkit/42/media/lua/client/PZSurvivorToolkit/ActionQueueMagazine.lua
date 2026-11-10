require 'TimedActions/ISUnloadBulletsFromMagazine'
require 'TimedActions/ISReloadWeaponAction'
require 'PZSurvivorToolkit/ActionQueueDefinitions'
require 'PZSurvivorToolkit/BulkFirearms'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Firearms=require 'PZSurvivorToolkit/ActionQueueFirearms'
local Toolkit=PZSurvivorToolkit
local Magazine={}
Toolkit.ActionQueueMagazine=Magazine
local class,base,object,reload=ISUnloadBulletsFromMagazine,ISBaseTimedAction,ISBaseObject,ISReloadWeaponAction
local actualMeta,equal,kind=toolkitLuaMetatableMatches,rawequal,type
local classChain=Proof.nativeActionClassChain
local ammoOutput=Firearms and Firearms.ammoOutput
local bulk=Toolkit.BulkFirearms
local bulkBinding=bulk and bulk.magazineUnloadBinding
local source='native.ISUnloadBulletsFromMagazine'
local snapshot,registered
local matches,inspect,install
local ownNames={'isValid','start','update','isLocal','updateLoadingTime','initVars','serverStop',
 'serverStart','getDuration','complete','animEvent','stop','perform','new'}
local directBaseNames={'new','stop','perform'}
local inheritedNames={'begin','create','adjustMaxTime','isUsingTimeout','waitToStart','interruptWaitToStart',
 'isStarted','forceComplete','forceStop','forceCancel','getDeltaModifiers','getJobDelta',
 'setActionAnim','setOverrideHandModels'}
local optionalNames={'failedPathfind','succeededPathfind','timedActionPathfind'}
local globals={instanceof=instanceof,getSpecificPlayer=getSpecificPlayer,getClassSimpleName=getClassSimpleName,
 instanceItem=instanceItem,sendAddItemToContainer=sendAddItemToContainer,syncItemFields=syncItemFields,
 emulateAnimEvent=emulateAnimEvent,isClient=isClient,isServer=isServer,isMultiplayer=isMultiplayer,
 AmmoType=AmmoType,ItemTag=ItemTag,ItemBodyLocation=ItemBodyLocation,Perks=Perks,MoodleType=MoodleType}
local function from(callback,file)return type(callback)=='function'and Proof.closure(callback,file)end
local function invoker(callback)
 if type(callback)~='function'or type(globals.getClassSimpleName)~='function'then return false end
 local ok,kind=pcall(globals.getClassSimpleName,callback)
 return ok and(kind=='LuaJavaInvoker'or kind=='MultiLuaJavaInvoker')
end
local function chain(constructing)
 return type(actualMeta)=='function'and actualMeta(Proof,nil)
  and type(classChain)=='function'and Proof.nativeActionClassChain==classChain
  and classChain(object,base,class,constructing)and classChain(object,base,reload,true)
  and actualMeta(Toolkit,nil)and actualMeta(Magazine,nil)
end
local function unchanged(constructing)
 if not chain(constructing)or not snapshot or not snapshot.trusted
  or PZSurvivorToolkit~=Toolkit or Toolkit.ActionQueueMagazine~=Magazine
  or Magazine.matches~=matches or Magazine.inspect~=inspect or Magazine.install~=install
  or ISUnloadBulletsFromMagazine~=class or ISReloadWeaponAction~=reload
  or Toolkit.ActionQueueFirearms~=Firearms or not actualMeta(Firearms,nil)
  or Firearms.ammoOutput~=ammoOutput or not from(ammoOutput,'ActionQueueFirearms.lua')then return false end
 for name,value in pairs(globals)do if _G[name]~=value then return false end end
 for _,slot in ipairs(snapshot.enumSlots)do if slot.owner[slot.name]~=slot.value then return false end end
 for name,callback in pairs(snapshot.classMethods)do if Proof.own(class,name)~=callback then return false end end
 for name,callback in pairs(class)do
  if type(callback)=='function'and snapshot.classMethods[name]~=callback then return false end
 end
 for name,callback in pairs(snapshot.baseMethods)do if base[name]~=callback then return false end end
 for name,callback in pairs(snapshot.inherited)do if (class[name]or false)~=callback then return false end end
 for name,callback in pairs(snapshot.reload)do if reload[name]~=callback then return false end end
 return true
end
local function callbacksTrusted(action)
 -- Other bulk families have their own owner. Reject by actual identity before
 -- scanning magazine callbacks/helpers or reading any inherited action field.
 if kind(action)~='table'or kind(actualMeta)~='function'or not actualMeta(action,class)then return false end
 if not unchanged(false)or action.Type~=class.Type
  or action.onStartFunc or action.onCompleteFunc or action.onCancelFunc or action.onFailFunc
  or action.additionalTest or action.additionalContext or action.retriggerLastAction then return false end
 for name,callback in pairs(snapshot.classMethods)do if action[name]~=callback then return false end end
 for name,callback in pairs(snapshot.inherited)do if (action[name]or false)~=callback then return false end end
 local ownGuard=Proof.own(action,'isValidStart')
 local owned,savedID=false,nil
 if ownGuard~=nil then
  if not bulk or not actualMeta(bulk,nil)or Toolkit.BulkFirearms~=bulk or bulk.magazineUnloadBinding~=bulkBinding
   or not from(bulkBinding,'BulkFirearms.lua')or not snapshot.bulkTrusted then return false end
  owned,savedID=bulkBinding(action,ownGuard)
  if owned~=true then return false end
 elseif action.isValidStart~=snapshot.validStart then return false end
 for name,callback in pairs(action)do
  if type(callback)=='function'and callback~=snapshot.classMethods[name]and callback~=snapshot.inherited[name]
   and not(name=='isValidStart'and owned)then return false end
 end
 return true,owned,savedID
end
local function pending(action)
 return not action.action and not action.started and action.toolkitNativeTransaction==nil and action.toolkitNativeKind==nil
  and not(type(action.toolkitQueueOperation)=='table'and action.toolkitQueueOperation.toolkitStarted)
  and action.ammoCountStart==nil and action.unloadFinished==nil
  and action.unloadedThisLoop==false and action.updateLoadBulletsTime==0
end
local function shape(action)
 local trusted,owned,savedID=callbacksTrusted(action)
 if not(trusted and not action._isAddingActions and action.maxTime==-1
  and action.stopOnWalk==false and action.stopOnRun==true and action.stopOnAim==true
  and action.useProgressBar==false and action.caloriesModifier==1
  and instanceof(action.character,'IsoPlayer')and instanceof(action.magazine,'InventoryItem')
  and(action.action~=nil or pending(action)))then return false end
 return true,owned,savedID
end
matches=function(action)local valid=shape(action);return valid end
local function finite(value)return type(value)=='number'and value==value and value>-math.huge and value<math.huge end
inspect=function(action)
 local valid,owned,savedID=shape(action)
 if not valid then return end
 local actor,item=action.character,action.magazine
 if getSpecificPlayer(actor:getPlayerNum())~=actor or actor:isDead()or actor:isAsleep()
  or getClassSimpleName(item)~='ComboItem'then return end
 local root=actor:getInventory()
 local id,kind=item:getID(),item:getFullType()
 if not finite(id)or id%1~=0 or id==-1 or type(kind)~='string'or kind==''
  or not instanceof(root,'ItemContainer')or item:getContainer()~=root or root:getItemWithID(id)~=item then return end
 local output=ammoOutput(item)
 if not output then return end
 if owned and savedID~=id then return end
 -- Reload speed reads equipped/worn gear. equipment is a read dependency on
 -- hand/equipment writers, not a blanket shared actor/root output or gear IDs.
 local result={items={[id]=true},itemTypes={[kind]=true},targets={},equipment=actor,
  outputTypes={[output]=true},freshOutputTypes={[output]=true},interrupt='finish-step',bulk=action.toolkitIndependentBulk==true}
 if action.action then
  -- Native events may have paid any prefix. Do not read/project live ammo count.
  result.cancelWaiting,result.cancelOperation=false,false
  return result
 end
 local count,maximum=item:getCurrentAmmoCount(),item:getMaxAmmo()
 if not finite(count)or count%1~=0 or not finite(maximum)or maximum%1~=0
  or maximum<1 or count<0 or count>maximum then return end
 if owned and(item:isFavorite()or actor:isEquippedClothing(item)
  or actor:getPrimaryHandItem()==item or actor:getSecondaryHandItem()==item)then return end
 local requires={{field='location',equal=root}}
 -- Both direct and owned starts accept native empty-magazine completion.
 -- No output quantity/ID or capacity is credited from this forecast.
 result.cancelWaiting,result.cancelOperation=true,true
 result.moveRequiresProjection=true
 result.edit={version=1,complete=true,capacity='external',resources={{domain='item',key=id,
  facts={item=item,location=root,ammoCount=count},requires=requires,
  effects={{field='ammoCount',set=0}},bounds={ammoCount={min=0,max=maximum}}}}}
 return result
end
install=function()
 if snapshot then return unchanged(true)end
 if not chain(true)then snapshot={trusted=false};return false end
 local trusted=class.Type=='ISUnloadBulletsFromMagazine'
  and Proof.matches('media/lua/shared/TimedActions/ISUnloadBulletsFromMagazine.lua',590379046,nil,true)
  and Proof.matches('media/lua/shared/TimedActions/ISReloadWeaponAction.lua',1833975495,nil,true)
  and Proof.matches('media/lua/shared/TimedActions/ISBaseTimedAction.lua',3104185167,nil,true)
  and from(ammoOutput,'ActionQueueFirearms.lua')
  and Proof.matches('media/lua/client/PZSurvivorToolkit/ActionQueueFirearms.lua',823161797,'PZSurvivorToolkit',true)
 for _,name in ipairs({'getClassSimpleName','instanceItem','sendAddItemToContainer','syncItemFields','emulateAnimEvent'})do
  if not invoker(globals[name])then trusted=false end
 end
 local classMethods,baseMethods,inherited,helpers,enumSlots={},{},{},{},{}
 for name,callback in pairs(class)do
  if type(callback)=='function'then
   classMethods[name]=callback
   if name~='derive'and not from(callback,'ISUnloadBulletsFromMagazine.lua')then trusted=false end
  end
 end
 for _,name in ipairs(ownNames)do if not classMethods[name]then trusted=false end end
 local function baseOrigin(name,callback)
  return from(callback,'ISBaseTimedAction.lua')or(name=='begin'or name=='stop')and from(callback,'ActionQueue.lua')
 end
 for _,name in ipairs(directBaseNames)do
  local callback=base[name];baseMethods[name]=callback or false
  if not baseOrigin(name,callback)then trusted=false end
 end
 for _,name in ipairs(inheritedNames)do
  local callback=class[name];inherited[name]=callback or false
  if not baseOrigin(name,callback)then trusted=false end
 end
 for _,name in ipairs(optionalNames)do inherited[name]=false;if class[name]~=nil then trusted=false end end
 local validStart=class.isValidStart
 if not from(validStart,'ISBaseTimedAction.lua')then trusted=false end
 for _,name in ipairs({'setReloadSpeed','getReloadTime'})do
  helpers[name]=reload[name]or false
  if not from(helpers[name],'ISReloadWeaponAction.lua')then trusted=false end
 end
 for _,spec in ipairs({{'AmmoType','SHOTGUN_SHELLS'},{'ItemBodyLocation','AMMO_STRAP'},{'Perks','Reloading'},
  {'MoodleType','PANIC'},{'ItemTag','RELOAD_FAST_MAGAZINES'},{'ItemTag','RELOAD_FAST_SHELLS'},{'ItemTag','RELOAD_FAST_BULLETS'}})do
  local owner=globals[spec[1]]
  if not owner or owner[spec[2]]==nil then trusted=false
  else enumSlots[#enumSlots+1]={owner=owner,name=spec[2],value=owner[spec[2]]}end
 end
 local bulkTrusted=bulk and type(bulkBinding)=='function'and from(bulkBinding,'BulkFirearms.lua')
  and Proof.matches('media/lua/client/PZSurvivorToolkit/BulkFirearms.lua',4083090989,'PZSurvivorToolkit',true)
 snapshot={trusted=trusted,classMethods=classMethods,baseMethods=baseMethods,inherited=inherited,
  reload=helpers,validStart=validStart,enumSlots=enumSlots,bulkTrusted=bulkTrusted}
 if not registered then
  Toolkit.ActionQueueDefinitions.registerBehavior(source,{types={'ISUnloadBulletsFromMagazine'},
   matches=function(action)return matches(action)and not action.toolkitIndependentBulk end,inspect=inspect})
  registered=true
 end
 return unchanged(true)
end
Magazine.matches,Magazine.inspect,Magazine.install=matches,inspect,install
if Events and Events.OnGameStart then Events.OnGameStart.Add(install)end
return Magazine
