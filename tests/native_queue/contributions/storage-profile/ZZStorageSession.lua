local selection=require 'QueueTestSelection'
local entered,starting,started,attempted=false,false,false,false
local tick
Events.OnMainMenuEnter.Add(function()entered=true end)
Events.OnGameStart.Add(function()
 started=true
end)
Events.OnTick.Add(function()
 if tick then tick()
 elseif started and not attempted and getPlayer()and getPlayer():getCurrentSquare()then
  attempted=true
  local ok,result=pcall(require('StorageProfileSession').run,selection)
  if ok then tick=result else print('[STORAGE_PROFILE] FAIL '..tostring(result))end
 end
end)
Events.OnPreUIDraw.Add(function()
 if started and isIngameState()and isGamePaused()then setGameSpeed(1)end
 if not entered or starting or isIngameState()then return end
 starting=true;getCore():setOptionPauseOnFocusloss(false)
 getWorld():setGameMode('Sandbox');getWorld():setWorld('InventoryWorkProfileNative');getWorld():setMap('Muldraugh, KY')
 MainScreen.instance:setDefaultSandboxVars()
 for name,value in pairs({Zombies=6,EnableVehicles=false,StartMonth=7,StartDay=9,StartTime=2})do getSandboxOptions():getOptionByName(name):setValue(value)end
 getSandboxOptions():toLua();MainScreen.instance.createWorld=true
 MapSpawnSelect.instance.selectedRegion={points={unemployed={{posX=10835,posY=10144,posZ=0}}}}
 MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'})
 MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
end)
