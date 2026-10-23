local config=require 'QueueTestSelection'
local entered,starting,connecting,advanced,started,done=false,false,false,false,false,false
local host=config.kind=='mp' and config.options and config.options.mp_host
local hostOwner=false
if host then
 Events.OnCoopServerMessage.Add(function(tag,cookie,payload)
  if not hostOwner then return end
  if tag=='login-attempt' and (payload=='client1' or payload=='client2') then
   CoopServer:sendMessage('approve-login-attempt',payload)
  end
  if tag~='status' or payload~='UI_ServerStatus_Started' or connecting then return end
  connecting=true
  CoopServer:sendMessage('set-host-user','client1')
  local address=CoopServer:getAddress()
  serverConnect('client1',CoopServer:getAdminPassword(),address,address,tostring(CoopServer:getPort()),'','queue-smoke',false,true,1,'')
 end)
end
Events.OnMainMenuEnter.Add(function()
 entered=true
 if config.kind~='mp' or connecting or isClient() then return end
 local reader=assert(getFileReader('smoke-user.txt',false));local user=reader:readLine();reader:close()
 -- The lifecycle fixture owns the second connection after an actual menu exit.
 if user=='client2' and config.cases and #config.cases==1 and config.cases[1]=='lease_lifecycle' then
  local reader=getFileReader('cart-lease-lifecycle-rejoin.txt',false)
  local checkpoint=reader and reader:readLine()
  if reader then reader:close() end
  if checkpoint=='pending' then return end
 end
 if host and user=='client1' then
  if hostOwner then return end
  hostOwner=true
  assert(not getSteamModeActive(),'Host fixture requires -nosteam')
  CoopConnection.servername,CoopConnection.username,CoopConnection.serverPassword='queue-smoke','client1',''
  CoopConnection.memory=config.resources.heap_mib
  print('[QUEUE_TEST] HOST_REQUEST name=queue-smoke')
  CoopServer:launch('queue-smoke','client1',config.resources.heap_mib)
  return
 end
 connecting=true
 local connection=config.options and config.options.startup_connection or {username=user,password='smoke-local-only'}
 ConnectToServer.instance:connect(MainScreen.instance,'Native startup test',connection.username,connection.password,'127.0.0.1','',tostring(config.port),'',false,true,1)
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
