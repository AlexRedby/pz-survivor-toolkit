-- Composition/lifetime checks with explicit native idle/globals/quiet and
-- capture-fact doubles. These do not prove actual mod bodies, native bytecode,
-- dispatch weaving or in-world effects; the native source suite covers recipes.
local root=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/'
local function setup(sourceOverrides)
 local env={PZSurvivorToolkit={}}
 for key,value in pairs(_G)do if key~='PZSurvivorToolkit'then env[key]=value end end;env._G=env
 env.toolkitLuaMetatableMatches=function(value,expected)return type(value)=='table'and getmetatable(value)==expected end
 local origins={};local factsByCallback={};local predicates=0;local readers=0
 local sourceOK,registryOK,idleOK,globalsOK,quietOK,tracking=true,true,true,true,true,true
 local readerHook,predicateHook,quietHook,recipeHook
 local factoryCalls={}
 local function callback(filename)
  local value=function()error('gameplay callback executed by certification')end
  origins[value]=filename;factsByCallback[value]=true;return value
 end
 env.getFilenameOfClosure=function(value)return origins[value]end
 local proof=assert(setfenv(assert(loadfile(root..'shared/PZSurvivorToolkit/SourceProof.lua')),env))()
 proof.matches=function(path,checksum,mod,adler)
  assert(type(path)=='string'and type(checksum)=='number'and adler==true)
  readers=readers+1;if readerHook then readerHook()end
  local selected=sourceOverrides and sourceOverrides[(mod or 'native')..':'..path]
  if selected~=nil then return selected end
  return sourceOK
 end
 local recipes=assert(setfenv(assert(loadfile(root..'client/PZSurvivorToolkit/ActionQueueHandEventRecipes.lua')),env))()
 for name,value in pairs(recipes)do
  if name~='source'then
   recipes[name]=function(...)
    factoryCalls[name]=(factoryCalls[name]or 0)+1
    if recipeHook then recipeHook(name)end
    return value(...)
   end
  end
  origins[recipes[name]]='ActionQueueHandEventRecipes.lua'
 end
 local snow,neat,carts,fishing,radio,presentation,primary,secondary=callback('ISnow_CharSnow.lua'),callback('NEQ_HideEquipped.lua'),callback('HolderRegistry.lua'),
  callback('FishingHandler.lua'),callback('ISRadioWindow.lua'),callback('WPANC_BowPresentation.lua'),callback('R5_AimState.lua'),callback('R5_AimState.lua')
 env.NEQ_State={hideEquipped=false,localPlayerNum=callback('NEQ_State.lua')}
 env.NEQ_HideEquipped={refreshFor=callback('NEQ_HideEquipped.lua')}
 env.SaucedCarts={CartTypes={},isCart=callback('Core.lua'),safeIsCart=callback('Core.lua')}
 env.Fishing={Handler={onEquipPrimary=fishing,handleFishing=callback('FishingHandler.lua'),isFishingValid=callback('FishingHandler.lua')},ManagerInstances={}}
 env.ISRadioWindow={onEquip=radio}
 env.WPANC={BowPresentation={onEquipPrimary=presentation,onPlayerUpdate=callback('WPANC_BowPresentation.lua')},
  BowDurability={isBow=callback('WPANC_BowDurability.lua')},ArcheryContract={BowFullType='Base.Primitive_Bow',isPrimitiveBow=callback('WPANC_ArcheryContract.lua'),isPlayerCharacter=callback('WPANC_ArcheryContract.lua')},
  BowReload={isPrimitiveBow=callback('WPANC_BowReload.lua')},BowState={onEquipPrimary=primary,onEquipSecondary=secondary}}
 env.isForceDropHeavyItem=callback('ISEquipWeaponAction.lua');env.forceDropHeavyItems=callback('ForceDropGuard.lua')
 local snapshot={primary={snow,neat,carts,fishing,radio,presentation,primary},secondary={snow,neat,radio,secondary}}
 local events={registeredCallbacks=function()return snapshot end,
  registeredCallbacksMatch=function(value)return registryOK and value==snapshot end,
  archeryTrackingAbsent=function()return tracking end}
 local native=function(value,recipe)
  assert(type(recipe)=='table'and #recipe.fingerprint==64)
  predicates=predicates+1;if predicateHook then predicateHook(value,recipe)end;return factsByCallback[value]
 end
 local idle=function()return idleOK end;local globals=function()return globalsOK end
 local quiet=function()if quietHook then quietHook()end;return quietOK end
 env.toolkitLuaCaptureFactsMatch=native;env.toolkitLuaCaptureFactsApiMatches=function(value)return value==native end
 env.toolkitEquipEventDispatchIdle=idle;env.toolkitEquipGlobalsTrusted=globals;env.toolkitEquipNativeQuiet=quiet
 env.toolkitEquipEventDispatchApiMatches=function(value)return value==idle or value==globals or value==quiet end
 env.isClient=function()return false end;env.isServer=function()return false end;env.isMultiplayer=function()return false end
 env.instanceof=function(value,class)return type(value)=='table'and(class=='InventoryItem'and value.item==true or value.class==class)end
 env.PZSurvivorToolkit.ActionQueueHandEvents=events
 env.require=function(name)
  if name=='PZSurvivorToolkit/SourceProof'then return proof end
  if name=='PZSurvivorToolkit/ActionQueueHandEventRecipes'then return recipes end
  assert(name=='PZSurvivorToolkit/ActionQueueHandEvents');return events
 end
 local effects=assert(setfenv(assert(loadfile(root..'client/PZSurvivorToolkit/ActionQueueHandEffects.lua')),env))()
 local item={item=true,getFullType=function()return 'Base.Hammer'end,hasTag=function()return false end}
 local actor={};local items={item}
 return{env=env,proof=proof,recipes=recipes,effects=effects,events=events,snapshot=snapshot,actor=actor,items=items,
  facts=factsByCallback,snow=snow,neat=neat,carts=carts,fishing=fishing,presentation=presentation,primary=primary,secondary=secondary,
  callback=callback,source=function(value)sourceOK=value end,registry=function(value)registryOK=value end,
  idle=function(value)idleOK=value end,globals=function(value)globalsOK=value end,quiet=function(value)quietOK=value end,
  tracking=function(value)tracking=value end,readerHook=function(value)readerHook=value end,predicateHook=function(value)predicateHook=value end,
  quietHook=function(value)quietHook=value end,recipeHook=function(value)recipeHook=value end,factoryCalls=factoryCalls,counts=function()return predicates,readers end}
end
local function certify(case)return case.effects.certify(case.actor,case.items)end
local function rejected(change,index)
 local case=setup();change(case);assert(certify(case)==nil,'unknown or changed source/state granted a complete certificate '..tostring(index))
end
local f=setup();local check=assert(certify(f));assert(type(check)=='function'and check())
assert(f.env.PZSurvivorToolkit.ActionQueueHandEffects==f.effects,'wrong public effect owner')
assert(f.effects.certify(f.actor)==nil and f.effects.certify(f.actor,f.items,true)==nil)
local predicates,readers=f.counts();assert(predicates>0 and readers>0,'composition did not qualify inputs')
-- A certificate is decision-local and must re-read the current state.
f.env.SaucedCarts.CartTypes['Base.Hammer']={};assert(not check(),'live cart classification was cached')
f.env.SaucedCarts.CartTypes['Base.Hammer']=nil;assert(check())
f.facts[f.snow]=false;assert(not check(),'nonempty Snow capture retained quiet effects')
f.facts[f.snow]=true;assert(check())
f.tracking(false);assert(not check(),'live prior bow tracking retained authority')
f.tracking(true);assert(check())
f.env.Fishing.ManagerInstances[0]={};assert(not check(),'live fishing manager effects were ignored')
f.env.Fishing.ManagerInstances[0]=nil;assert(check())
f.idle(false);assert(not check(),'active/queued hand dispatch retained authority')
f.idle(true);assert(check())
for index,change in ipairs({
 function(c)c.registry(false)end,
 function(c)c.idle(false)end,
 function(c)c.globals(false)end,
 function(c)c.quiet(false)end,
 function(c)c.tracking(false)end,
 function(c)c.source(false)end,
 function(c)c.facts[c.snow]=nil end,
 function(c)c.facts[c.primary]=false end,
 function(c)c.facts[c.secondary]=false end,
 function(c)c.env.WPANC.BowReload.isPrimitiveBow=c.callback('Foreign.lua');c.facts[c.env.WPANC.BowReload.isPrimitiveBow]=false end,
 function(c)c.env.WPANC.ArcheryContract.isPlayerCharacter=c.callback('Foreign.lua');c.facts[c.env.WPANC.ArcheryContract.isPlayerCharacter]=false end,
 function(c)c.env.NEQ_State.hideEquipped=true end,
 function(c)c.env.NEQ_State.localPlayerNum=c.callback('Foreign.lua');c.facts[c.env.NEQ_State.localPlayerNum]=false end,
 function(c)c.env.SaucedCarts.CartTypes['Base.Hammer']=false end,
 function(c)c.env.SaucedCarts.CartTypes=setmetatable({},{})end,
 function(c)c.env.WPANC.ArcheryContract.BowFullType='Base.Hammer'end,
 function(c)c.env.WPANC.BowDurability.isBow=c.callback('Foreign.lua');c.facts[c.env.WPANC.BowDurability.isBow]=false end,
 function(c)c.env.forceDropHeavyItems=c.callback('Foreign.lua');c.facts[c.env.forceDropHeavyItems]=false end,
 function(c)c.snapshot.primary[#c.snapshot.primary+1]=c.callback('Foreign.lua')end,
 function(c)c.recipes.snow=function()return {}end end,
 function(c)c.events.registeredCallbacksMatch=function()return true end end,
 function(c)c.env.toolkitEquipNativeQuiet=function()return true end end,
 function(c)c.env.isClient=function()return true end end,
 function(c)c.items[2]=c.items[1];c.items[1]=nil end,
 function(c)c.readerHook(function()c.registry(false)end)end,
 function(c)c.readerHook(function()c.env.NEQ_State={}end)end,
 function(c)c.predicateHook(function()c.env.SaucedCarts={}end)end,
 function(c)c.predicateHook(function()c.items[1]={}end)end,
 function(c)c.quietHook(function()c.env.Fishing={}end)end,
})do rejected(change,index)end
-- Qualification reads finish before state predicates. A rebind at the reader
-- boundary must affect this decision rather than a cached earlier observation.
do local c=setup();c.readerHook(function()c.facts[c.snow]=false end);assert(certify(c)==nil)end
print('Hand effects composition: explicit native doubles, full known selection, current inputs, helper/recipe binding and source reentry guards passed.')

do
 local c=setup();setmetatable(c.env.ISRadioWindow,{__index=function()error('unreached radio UI lookup')end})
 assert(certify(c),'normal inherited UI class blocked non-Radio callback branch')
end

-- Native file lookup follows selected overlays. Require a reviewed alternative
-- when the installed base lookup no longer returns the reviewed native bytes.
do
 local path=':media/lua/client/RadioCom/ISRadioWindow.lua'
 local c=setup({['native'..path]=false,['TVRadio_ReInvented'..path]=true})
 assert(certify(c),'reviewed selected radio overlay was not qualified')
 c=setup({['native'..path]=false,['TVRadio_ReInvented'..path]=false})
 assert(not certify(c),'unknown native and selected radio sources gained authority')
end

-- Repeated checks reuse only private recipe descriptions. Native observations
-- still run, and a subsequent decision must create its own recipe DAG.
do
 local c=setup();local seen={}
 c.predicateHook(function(callback,recipe)
  if seen[callback]then assert(seen[callback]==recipe,'one certificate rebuilt its recipe DAG')else seen[callback]=recipe end
 end)
 local check=assert(certify(c));local calls={}
 for name,count in pairs(c.factoryCalls)do calls[name]=count end
 local predicates=c.counts();assert(check())
 assert(c.counts()>predicates,'reused recipes skipped fresh native observations')
 for name,count in pairs(c.factoryCalls)do assert(calls[name]==count,'certificate check reran a recipe factory: '..name)end
 c.facts[c.snow]=false;assert(not check(),'reused recipe retained a previous capture result')
 c.facts[c.snow]=true;local previous=seen[c.snow];seen={}
 assert(certify(c));assert(seen[c.snow]~=previous,'recipe DAG escaped into another decision')
 c.recipes.snow=function()error('changed recipe factory executed')end
 assert(not check(),'old certificate ignored a changed public recipe factory')
end
-- Source readers can reenter before recipe construction. Factory identity must
-- be guarded again at that boundary, and final checks must reject a mutation
-- made during construction without invoking the replacement factory.
for _,during in ipairs({'reader','factory'})do
 local c=setup();local foreignCalls=0
 local function replace()c.recipes.radio=function()foreignCalls=foreignCalls+1;return{}end end
 if during=='reader'then c.readerHook(replace)else c.recipeHook(function(name)if name=='isForceDropHeavyItem'then replace()end end)end
 assert(not certify(c),'recipe mutation at '..during..' boundary gained authority')
 assert(foreignCalls==0,'changed recipe factory executed across '..during..' boundary')
end
