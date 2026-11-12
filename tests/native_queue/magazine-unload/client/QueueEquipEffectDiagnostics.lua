-- Explicit fixture observation only. No callbacks, setters or eligibility
-- overrides; source/capture negatives remain negatives for production Policy.
local D={}
function D.observe(player,item)
 local P=require 'PZSurvivorToolkit/SourceProof'
 local R=require 'PZSurvivorToolkit/ActionQueueHandEventRecipes'
 local E=require 'PZSurvivorToolkit/ActionQueueHandEvents'
 local result={sources={},facts={},state={},callbacks={}}
 local function fact(name,callback,recipe)
  local value=toolkitLuaCaptureFactsMatch(callback,recipe)
  if type(value)=='boolean'then result.facts[name]=value else result.facts[name]='unknown'end
 end
 for _,name in ipairs({'snow','neat','neatState','carts','cartsCore','cartsForceDrop','equipWeapon','fishing','radio','bowPresentation','bowDurability','archeryContract','archeryState','bowReload'})do
  local source=R.source(name);result.sources[name]=P.matches(source.path,source.adler,source.mod,true)
 end
 local function plain(name,value)result.state[name]=toolkitLuaMetatableMatches(value,nil)==true end
 for name,value in pairs({Fishing=Fishing,handler=Fishing.Handler,NEQ_State=NEQ_State,NEQ_HideEquipped=NEQ_HideEquipped,
  SaucedCarts=SaucedCarts,cartTypes=SaucedCarts.CartTypes,WPANC=WPANC,presentation=WPANC.BowPresentation,
  durability=WPANC.BowDurability,contract=WPANC.ArcheryContract,bowReload=WPANC.BowReload,radio=ISRadioWindow})do plain(name,value)end
 result.state.hideEquipped=NEQ_State.hideEquipped
 local managers=0;for _ in pairs(Fishing.ManagerInstances)do managers=managers+1 end;result.state.managers=managers
 result.state.trackingAbsent=E.archeryTrackingAbsent(player)
 fact('heavy',isForceDropHeavyItem,R.isForceDropHeavyItem())
 fact('forceDrop',forceDropHeavyItems,R.forceDropGuard(SaucedCarts.isCart))
 fact('cartClassifier',SaucedCarts.isCart,R.cartsIsCart(type))
 fact('cartSafe',SaucedCarts.safeIsCart,R.cartsSafeIsCart(tostring))
 fact('neatRefresh',NEQ_HideEquipped.refreshFor,R.neatRefresh(NEQ_State))
 fact('neatPlayer',NEQ_State.localPlayerNum,R.neatLocalPlayerNum())
 fact('fishingHandle',Fishing.Handler.handleFishing,R.fishingHandle())
 fact('fishingValid',Fishing.Handler.isFishingValid,R.fishingValid())
 fact('playerCharacter',WPANC.ArcheryContract.isPlayerCharacter,R.archeryPlayerCharacter())
 fact('primitiveBow',WPANC.ArcheryContract.isPrimitiveBow,R.archeryPrimitiveBow(WPANC.ArcheryContract))
 fact('reloadBow',WPANC.BowReload.isPrimitiveBow,R.bowReloadPrimitiveBow(WPANC.ArcheryContract))
 fact('durabilityBow',WPANC.BowDurability.isBow,R.bowDurabilityIsBow(WPANC.ArcheryContract))
 local snapshot=E.registeredCallbacks()
 for _,phase in ipairs({'primary','secondary'})do
  for index,callback in ipairs(snapshot and snapshot[phase]or{})do
   local name=phase..index;local file=getFilenameOfClosure(callback):gsub('\\','/'):match('([^/]+)$')
   result.callbacks[name]=file
   if file=='ISnow_CharSnow.lua'then fact(name,callback,R.snow())
   elseif file=='NEQ_HideEquipped.lua'then fact(name,callback,R.neat(NEQ_State,NEQ_HideEquipped))
   elseif file=='HolderRegistry.lua'then fact(name,callback,R.cartsOrdinary())
   elseif file=='FishingHandler.lua'then fact(name,callback,R.fishing())
   elseif file=='ISRadioWindow.lua'then fact(name,callback,R.radio())
   elseif file=='R5_AimState.lua'then fact(name,callback,phase=='primary'and R.archeryPrimary(WPANC.ArcheryContract,WPANC.BowReload)or R.archerySecondary(WPANC.ArcheryContract,WPANC.BowReload))
   elseif file=='WPANC_BowPresentation.lua'then fact(name,callback,R.bowPresentation(WPANC.BowPresentation,WPANC.BowDurability))
   else result.facts[name]='unreviewed'end
  end
 end
 local check=PZSurvivorToolkit.ActionQueueHandEffects.certify(player,{item})
 result.certified=type(check)=='function'and check()==true
 return result
end
return D
