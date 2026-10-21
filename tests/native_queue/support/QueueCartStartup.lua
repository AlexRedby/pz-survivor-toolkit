local config=require 'QueueTestSelection'
local entered,starting,started,requested,launched=false,false,false,false,false
Events.OnMainMenuEnter.Add(function() entered=true end)
Events.OnPreUIDraw.Add(function()
 if not entered or starting or isIngameState() then return end
 starting=true
 getCore():setOptionPauseOnFocusloss(false)
 getWorld():setGameMode('Sandbox');getWorld():setWorld('CartTestArea');getWorld():setMap('Muldraugh, KY')
 MainScreen.instance:setDefaultSandboxVars()
 for name,value in pairs({Zombies=6,EnableVehicles=false,VehicleStoryChance=1,ZoneStoryChance=1,SurvivorHouseChance=1}) do
  getSandboxOptions():getOptionByName(name):setValue(value)
 end
 getSandboxOptions():toLua()
 local current,active=ActiveMods.getById('currentGame'),getActivatedMods()
 current:getMods():clear();for i=0,active:size()-1 do current:getMods():add(active:get(i)) end
 MainScreen.instance.createWorld=true
 MapSpawnSelect.instance.selectedRegion={points={unemployed={{posX=10825,posY=10142,posZ=0}}}}
 MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'})
 MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
end)
Events.OnGameStart.Add(function()
 started=true
 cartLabReload()
end)
Events.OnTick.Add(function()
 if not started or launched then return end
 local ok,problem=pcall(function()
  if not CartTestArea or not CartTestArea.ready then return end
  if config.cases[1]=='manual' then
   local player=assert(getPlayer())
   player:setPerkLevelDebug(Perks.Sprinting,10);player:getXp():setXPToLevel(Perks.Sprinting,10)
   player:getStats():reset(CharacterStat.ENDURANCE)
   launched=true;print('[CART_ADAPTER] MANUAL_CONTROL_READY');return
  end
  local p=assert(getPlayer());local cart=p:getPrimaryHandItem()
  local variants={['shopping-cart']='SaucedCarts.ShoppingCart',['metal-wheelbarrow']='SaucedWheelbarrow.WheelbarrowMetal'}
  local expected=variants[config.options and config.options.cart_variant] or 'SaucedWheelbarrow.WheelbarrowWood'
  if not cart or cart:getFullType()~=expected or p:getZ()~=CartTestArea.z then return end
  CartTestArea.check(p)
  if not requested then requested=true;print('[CART_ADAPTER] PROBE_ATTACH_READY') end
  local reader=getFileReader('queue-probes-ready.txt',false)
  if not reader then return end
  local ready=reader:readLine();reader:close()
  assert(ready=='ready','Runner probe gate is invalid')
  launched=true;cartLabReload()
 end)
 if not ok then launched=true;print('[QUEUE_TEST] FAIL CART_ADAPTER '..tostring(problem)) end
end)
