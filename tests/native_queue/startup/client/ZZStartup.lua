local config=require 'QueueTestSelection'
local entered,starting,connecting,advanced,started,done=false,false,false,false,false,false
Events.OnMainMenuEnter.Add(function()
 entered=true
 if config.kind~='mp' or connecting or isClient() then return end
 connecting=true
 ConnectToServer.instance:connect(MainScreen.instance,'Native startup test','client1','smoke-local-only','127.0.0.1','',tostring(config.port),'',false,true,1)
end)
Events.OnPreUIDraw.Add(function()
 if config.kind=='sp' then
  if started and isIngameState() and isGamePaused() then setGameSpeed(1) end
  if not entered or starting or isIngameState() then return end
  starting=true
  getCore():setOptionPauseOnFocusloss(false)
  getWorld():setGameMode('Sandbox');getWorld():setWorld('QueueStartup');getWorld():setMap('Muldraugh, KY')
  MainScreen.instance:setDefaultSandboxVars()
  getSandboxOptions():getOptionByName('Zombies'):setValue(6);getSandboxOptions():toLua()
  local current,active=ActiveMods.getById('currentGame'),getActivatedMods()
  current:getMods():clear()
  for i=0,active:size()-1 do current:getMods():add(active:get(i)) end
  MainScreen.instance.createWorld=true
  MapSpawnSelect.instance.selectedRegion={points={unemployed={{posX=10835,posY=10144,posZ=0}}}}
  MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'})
  MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
 else
  if (not connecting and not isClient()) or advanced or isIngameState() then return end
  if not MainScreen.instance or not MainScreen.instance.charCreationProfession or not MapSpawnSelect.instance then return end
  if MainScreen.instance.charCreationProfession:getIsVisible() or MapSpawnSelect.instance:getIsVisible() then
   advanced=true;MapSpawnSelect.instance:useDefaultSpawnRegion();MapSpawnSelect.instance:setVisible(false)
   MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'})
   MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
  end
 end
end)
Events.OnConnectFailed.Add(function(a,b) print('[QUEUE_TEST] FAIL startup connect '..tostring(a)..' '..tostring(b)) end)
Events.OnGameStart.Add(function()
 started=true
 print('[STARTUP_TEST] GAME_START kind='..config.kind..' mode='..config.mode)
end)
Events.OnTick.Add(function()
 if not started or done or not isIngameState() then return end
 local player=getPlayer()
 if not player or player:isDead() or not player:getSquare() then return end
 if config.kind=='mp' and (not isClient() or player:getOnlineID()<0) then return end
 local square=player:getSquare()
 print('[STARTUP_TEST] PLAYER_READY square='..square:getX()..','..square:getY()..','..square:getZ()..' tick=true')
 done=true
 print('[STARTUP_TEST] COMPLETE case=loaded')
end)
