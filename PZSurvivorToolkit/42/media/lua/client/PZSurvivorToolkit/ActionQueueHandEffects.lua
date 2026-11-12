-- A decision-local SP effect certificate for ordinary native hand items.
-- Native events still run. Their exact source branches may update derived
-- presentation state; this contract never suppresses or simulates callbacks.
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Recipes=require 'PZSurvivorToolkit/ActionQueueHandEventRecipes'
local Events=require 'PZSurvivorToolkit/ActionQueueHandEvents'
local Toolkit=PZSurvivorToolkit
local Effects={}
Toolkit.ActionQueueHandEffects=Effects
local kind,equal,call,each,array=type,rawequal,pcall,pairs,ipairs
local meta=toolkitLuaMetatableMatches
local facts,factsAPI=toolkitLuaCaptureFactsMatch,toolkitLuaCaptureFactsApiMatches
local idle,globals,dispatchAPI=toolkitEquipEventDispatchIdle,toolkitEquipGlobalsTrusted,toolkitEquipEventDispatchApiMatches
local quiet=toolkitEquipNativeQuiet
local capture,closure,matches=Proof.captureBindings,Proof.closure,Proof.matches
local registered,revalidate,archery=Events.registeredCallbacks,Events.registeredCallbacksMatch,Events.archeryTrackingAbsent
local certify
local trusted={}
local names={'snow','neat','neatState','carts','cartsCore','cartsForceDrop','equipWeapon','fishing','radio','bowPresentation','bowDurability','archeryContract','archeryState','bowReload','radioSelected'}
local sources={};for _,name in array(names)do sources[name]=Recipes.source(name)end
local factories={};for name,callback in each(Recipes)do factories[name]=callback end
local function recipesUnchanged()
 for name,callback in each(factories)do if Recipes[name]~=callback then return false end end
 for name in each(Recipes)do if factories[name]==nil then return false end end
 return true
end
local function plain(value)return kind(value)=='table'and kind(meta)=='function'and meta(value,nil)end
local function shape(callback,recipe)return kind(callback)=='function'and facts(callback,recipe)==true end
local function empty(value)
 if not plain(value)then return false end
 for _ in each(value)do return false end
 return true
end
local function bootstrap()
 if not plain(_G)or not plain(Toolkit)or not plain(Effects)or not plain(Proof)or not plain(Recipes)or not plain(Events)
  or PZSurvivorToolkit~=Toolkit or Toolkit.ActionQueueHandEffects~=Effects or Effects.certify~=certify
  or not recipesUnchanged()or Toolkit.ActionQueueHandEvents~=Events or Events.registeredCallbacks~=registered or Events.registeredCallbacksMatch~=revalidate
  or Events.archeryTrackingAbsent~=archery or Proof.captureBindings~=capture or Proof.closure~=closure or Proof.matches~=matches
  or toolkitLuaMetatableMatches~=meta or toolkitLuaCaptureFactsMatch~=facts or toolkitLuaCaptureFactsApiMatches~=factsAPI
  or toolkitEquipEventDispatchIdle~=idle or toolkitEquipGlobalsTrusted~=globals or toolkitEquipEventDispatchApiMatches~=dispatchAPI
  or toolkitEquipNativeQuiet~=quiet or kind(factsAPI)~='function'or not factsAPI(facts)
  or kind(dispatchAPI)~='function'or not dispatchAPI(idle)or not dispatchAPI(globals)or not dispatchAPI(quiet)
  or globals()~=true or idle()~=true then return end
 return capture({{owner=_G,keys={'PZSurvivorToolkit','type','rawequal','pcall','pairs','ipairs','select','tostring','instanceof','getPlayer',
  'isClient','isServer','isMultiplayer','toolkitLuaMetatableMatches','toolkitLuaCaptureFactsMatch','toolkitLuaCaptureFactsApiMatches',
  'toolkitEquipEventDispatchIdle','toolkitEquipGlobalsTrusted','toolkitEquipEventDispatchApiMatches','toolkitEquipNativeQuiet',
  'SaucedCarts','Fishing','NEQ_State','NEQ_HideEquipped','WPANC','ISRadioWindow','ItemTag','isForceDropHeavyItem','forceDropHeavyItems'}},
  {owner=Toolkit,keys={'ActionQueueHandEffects','ActionQueueHandEvents'}},{owner=Effects,exact=true},{owner=Recipes,exact=true},
  {owner=Proof,keys={'captureBindings','closure','matches'}},{owner=Events,keys={'registeredCallbacks','registeredCallbacksMatch','archeryTrackingAbsent'}}})
end
local function inspect(actor,items)
 if trusted.helpers==nil then
  if not matches('media/lua/client/PZSurvivorToolkit/ActionQueueHandEventRecipes.lua',587897789,'PZSurvivorToolkit',true)then return end
  if not matches('media/lua/client/PZSurvivorToolkit/ActionQueueHandEvents.lua',2531317592,'PZSurvivorToolkit',true)then return end
  trusted.helpers=true
 end
 local watch=bootstrap()
 if kind(watch)~='function'or not watch()or not plain(items)or isClient()or isServer()or isMultiplayer()then return end
 local count,maximum=0,0
 for index in each(items)do
  if kind(index)~='number'or index%1~=0 or index<1 or index>3 then return end
  count=count+1;if index>maximum then maximum=index end
 end
 if count==0 or count~=maximum then return end
 local input=capture({{owner=items,exact=true}})
 local snapshot=registered()
 if not snapshot then return end
 local selected,needed={}, {equipWeapon=true}
 for _,phase in array({'primary','secondary'})do
  for _,callback in array(snapshot[phase])do
   local profile
   for _,name in array({'snow','neat','carts','fishing','radio','bowPresentation'})do
    if closure(callback,sources[name].filename)then profile=name;break end
   end
   if closure(callback,'R5_AimState.lua')then profile='archery'end
   if not profile then return end
   selected[#selected+1]={callback=callback,profile=profile,phase=phase}
   if sources[profile]then needed[profile]=true end
   if profile=='neat'then needed.neatState=true end
   if profile=='carts'then needed.cartsCore=true end
   if profile=='bowPresentation'then needed.bowDurability=true;needed.archeryContract=true end
   if profile=='archery'then needed.archeryContract=true;needed.archeryState=true;needed.bowReload=true end
  end
 end
 local carts=SaucedCarts
 if carts~=nil then needed.cartsCore=true;needed.cartsForceDrop=true end
 -- Source input may reenter through file readers. Discard all observations
 -- made before this boundary and revalidate every public/private input below.
 for name in each(needed)do
  local source=sources[name]
  if trusted[name]==nil then
   trusted[name]=matches(source.path,source.adler,source.mod,true)
   if name=='radio'and not trusted[name]then
    -- Base input follows active overlays. The selected override has the same
    -- verified non-Radio callback body and no private captures.
    local selectedSource=sources.radioSelected
    trusted[name]=matches(selectedSource.path,selectedSource.adler,selectedSource.mod,true)
   end
  end
  if not trusted[name]then return end
 end
 local needsArchery=false
 for _,entry in array(selected)do if entry.profile=='archery'then needsArchery=true end end
 if needsArchery then archery(actor)end
 local public={}
 local function own(owner,keys)
  if not plain(owner)then return false end
  public[#public+1]={owner=owner,keys=keys};return true
 end
 local fishing,neat,hide,wp=Fishing,NEQ_State,NEQ_HideEquipped,WPANC
 local handler,presentation,durability,contract,bowReload
 if fishing~=nil then if not own(fishing,{'Handler','ManagerInstances'})then return end;handler=fishing.Handler
  if not own(handler,{'onEquipPrimary','handleFishing','isFishingValid'})then return end end
 if neat~=nil and not own(neat,{'hideEquipped','localPlayerNum'})then return end
 if hide~=nil and not own(hide,{'refreshFor'})then return end
 if carts~=nil and(not own(carts,{'CartTypes','isCart','safeIsCart'})or not plain(carts.CartTypes))then return end
 if wp~=nil then
  if not own(wp,{'BowPresentation','BowDurability','ArcheryContract','BowState','BowReload'})then return end
  presentation,durability,contract,bowReload=wp.BowPresentation,wp.BowDurability,wp.ArcheryContract,wp.BowReload
  if presentation~=nil and not own(presentation,{'onEquipPrimary','onPlayerUpdate'})then return end
  if durability~=nil and not own(durability,{'isBow'})then return end
  if contract~=nil and not own(contract,{'isPrimitiveBow','isPlayerCharacter','BowFullType'})then return end
  if bowReload~=nil and not own(bowReload,{'isPrimitiveBow'})then return end
 end
 local publicWatch=capture(public)
 if kind(input)~='function'or kind(publicWatch)~='function'then return end
 -- Recipes are private decision inputs. Build their DAGs once after source
 -- readers and public capture, but observe every live fact again in check().
 if not recipesUnchanged()or not watch()or not input()or not publicWatch()then return end
 local recipes={isForceDropHeavyItem=factories.isForceDropHeavyItem()}
 if carts~=nil then
  recipes.cartsIsCart=factories.cartsIsCart(type)
  recipes.cartsSafeIsCart=factories.cartsSafeIsCart(tostring)
  recipes.forceDropGuard=factories.forceDropGuard(carts.isCart)
 else recipes.forceDropNative=factories.forceDropNative()end
 local prepared={}
 for _,entry in array(selected)do
  local profile=entry.profile
  if not prepared[profile]then
   if profile=='snow'then recipes.snow=factories.snow()
   elseif profile=='neat'then
    recipes.neat=factories.neat(neat,hide);recipes.neatRefresh=factories.neatRefresh(neat)
    recipes.neatLocalPlayerNum=factories.neatLocalPlayerNum()
   elseif profile=='carts'then recipes.cartsOrdinary=factories.cartsOrdinary()
   elseif profile=='fishing'then
    recipes.fishing=factories.fishing();recipes.fishingHandle=factories.fishingHandle();recipes.fishingValid=factories.fishingValid()
   elseif profile=='radio'then recipes.radio=factories.radio()
   elseif profile=='bowPresentation'then
    recipes.bowPresentation=factories.bowPresentation(presentation,durability)
    recipes.bowDurabilityIsBow=factories.bowDurabilityIsBow(contract)
   elseif profile=='archery'then
    recipes.archeryPlayerCharacter=factories.archeryPlayerCharacter()
    recipes.bowReloadPrimitiveBow=factories.bowReloadPrimitiveBow(contract)
   end
   if(profile=='bowPresentation'or profile=='archery')and not recipes.archeryPrimitiveBow then
    recipes.archeryPrimitiveBow=factories.archeryPrimitiveBow(contract)
   end
   prepared[profile]=true
  end
  if profile=='archery'then
   local name=entry.phase=='primary'and'archeryPrimary'or'archerySecondary'
   if not recipes[name]then recipes[name]=factories[name](contract,bowReload)end
  end
 end
 local function check()
  if not recipesUnchanged()or not watch()or not input()or not publicWatch()or globals()~=true or idle()~=true
   or revalidate(snapshot)~=true or isClient()or isServer()or isMultiplayer()or quiet(actor,items)~=true then return false end
  if not shape(isForceDropHeavyItem,recipes.isForceDropHeavyItem)then return false end
  if carts~=nil then
   if not plain(carts.CartTypes)or not shape(carts.isCart,recipes.cartsIsCart)
    or not shape(carts.safeIsCart,recipes.cartsSafeIsCart)
    or not shape(forceDropHeavyItems,recipes.forceDropGuard)then return false end
  elseif not shape(forceDropHeavyItems,recipes.forceDropNative)then return false end
  for _,item in array(items)do
   if not instanceof(item,'InventoryItem')
    or instanceof(item,'Radio')or item:getFullType()=='Base.Primitive_Bow'
    or carts and carts.CartTypes[item:getFullType()]~=nil then return false end
  end
  local checked={}
  for _,entry in array(selected)do
   local cb,profile=entry.callback,entry.profile
   if not checked[cb]then
    if profile=='snow'then if not shape(cb,recipes.snow)then return false end
    elseif profile=='neat'then
     if not neat or not hide or neat.hideEquipped~=false or not shape(cb,recipes.neat)
      or not shape(hide.refreshFor,recipes.neatRefresh)or not shape(neat.localPlayerNum,recipes.neatLocalPlayerNum)then return false end
    elseif profile=='carts'then
     if not carts or not shape(cb,recipes.cartsOrdinary)then return false end
    elseif profile=='fishing'then
     if not handler or cb~=handler.onEquipPrimary or not empty(fishing.ManagerInstances)
      or not shape(cb,recipes.fishing)or not shape(handler.handleFishing,recipes.fishingHandle)
      or not shape(handler.isFishingValid,recipes.fishingValid)then return false end
    elseif profile=='radio'then
     -- For these exact non-Radio items, native instanceof is false before
     -- any ISRadioWindow lookup. Its normal inherited UI class is not a
     -- state input on this branch; no UI method is invoked or certified.
     if not shape(cb,recipes.radio)then return false end
    elseif profile=='bowPresentation'then
     if not presentation or not durability or not contract or contract.BowFullType~='Base.Primitive_Bow'
      or cb~=presentation.onEquipPrimary or not shape(cb,recipes.bowPresentation)
      or not shape(durability.isBow,recipes.bowDurabilityIsBow)
      or not shape(contract.isPrimitiveBow,recipes.archeryPrimitiveBow)then return false end
    elseif profile~='archery'then return false end
    checked[cb]=true
   end
   if profile=='archery'then
    local state=wp and wp.BowState
    if not plain(state)or cb~=state[entry.phase=='primary'and'onEquipPrimary'or'onEquipSecondary']or archery(actor)~=true
     or not contract or not bowReload or contract.BowFullType~='Base.Primitive_Bow'
     or not shape(contract.isPlayerCharacter,recipes.archeryPlayerCharacter)
     or not shape(bowReload.isPrimitiveBow,recipes.bowReloadPrimitiveBow)
     or not shape(contract.isPrimitiveBow,recipes.archeryPrimitiveBow)
     or not shape(cb,entry.phase=='primary'and recipes.archeryPrimary or recipes.archerySecondary)then return false end
   end
  end
  return watch()and input()and publicWatch()and revalidate(snapshot)==true and idle()==true
 end
 if check()then return check end
end
certify=function(...)
 if select('#',...)~=2 then return end
 local ok,value=call(inspect,...)
 if ok then return value end
end
Effects.certify=certify
return Effects
