require 'PZSurvivorToolkit/ActionQueuePanel'
local Authority=require 'QueueHealthAuthority'
local Selection=require 'QueueHealthSelection'
local config=require 'QueueTestSelection'
local EventsJSON=require 'QueueHealthEvents'
local kind,mode=Selection.kind,Selection.mode
local queueOption=assert(PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'))
queueOption:setValue(mode=='toolkit')
assert(PZSurvivorToolkit.Settings.actionQueue()==(mode=='toolkit'),'medical queue mode bootstrap failed')
local reader
reader=assert(getFileReader('smoke-user.txt',false));local user=reader:readLine();reader:close()
reader=assert(getFileReader('queue-health-language.txt',false));local language=reader:readLine();reader:close()
local ids,session,stages,receipts,preparations,mutations,baselines,skips=nil,nil,{},{},{},{},{},{}
local performed,skipped,failures=0,0,0
local caseIDs={};for _,spec in ipairs(Selection.cases) do caseIDs[#caseIDs+1]=spec.id end
local function emit(event) event.suite='health';event.kind=kind;event.mode=mode;event.actor=user;EventsJSON.emit(event) end
local function complete() emit({event='complete',cases=caseIDs,expected=#caseIDs,performed=performed,skipped=skipped,failed=failures}) end
local connecting,advanced,entered,starting,started,done=false,false,false,false,nil,false
local step,since,lastReady=1,0,0
local function queue() return ISTimedActionQueue.getTimedActionQueue(getPlayer()) end
local function empty() return #queue().queue==0 and not getPlayer():hasTimedActions() end
local function stage(name,fn,ready,id) stages[#stages+1]={name=name,fn=fn,ready=ready,id=id} end
local function send(command,args)
 args=args or {}
 if kind=='mp' then sendClientCommand('HealthQueueTest',command,args)
 elseif command=='Verify' then receipts[args.phase]=Authority.verify(getPlayer(),args.phase)
 elseif command=='Prepare' then preparations[args.phase]=Authority.prepare(getPlayer(),args.phase)
 elseif command=='Mutate' then mutations[args.phase]=Authority.mutate(getPlayer(),args.phase,args.mode)
 elseif command=='Baseline' then baselines[args.phase]=Authority.baseline(getPlayer(),args.phase)
 elseif command=='Skip' then skips[args.phase]=Authority.skip(getPlayer(),args.phase,args.reason) end
end
require('QueueHealthScenarios')(stage,queue,empty,{kind=kind,language=language,skips=skips,ids=function() return ids end,receipts=receipts,preparations=preparations,mutations=mutations,baselines=baselines,send=send})
assert(#stages==#caseIDs+2,'HEALTH selected stage count changed')
Events.OnServerCommand.Add(function(module,command,args)
 if module~='HealthQueueTest' then return end
 if command=='Setup' then if not ids then ids=args;since=getTimestampMs() end
 elseif command=='Session' then
  if args.active and (not session or not session.active) then since=getTimestampMs() end
  session=args
 elseif command=='Verified' then receipts[args.phase]=args
 elseif command=='Prepared' then preparations[args.phase]=args
 elseif command=='Mutated' then mutations[args.phase]=args
 elseif command=='Baselined' then baselines[args.phase]=args
 elseif command=='Skipped' then skips[args.phase]=args
 elseif command=='Position' then Authority.position(getPlayer(),args.x,args.y,args.z) end
end)
Events.OnMainMenuEnter.Add(function()
 entered=true
 if kind~='mp' or connecting or isClient() then return end;connecting=true
 ConnectToServer.instance:connect(MainScreen.instance,'Native HEALTH isolated test',user,'smoke-local-only','127.0.0.1','',tostring(assert(config.port,'medical connection port missing')),'',false,true,1)
end)
Events.OnPreUIDraw.Add(function()
 if kind=='sp' then
  if started and isIngameState() and isGamePaused() then setGameSpeed(1) end
  if not entered or starting or isIngameState() then return end;starting=true
  getCore():setOptionPauseOnFocusloss(false)
  getWorld():setGameMode('Sandbox');getWorld():setWorld('QueueHealthSP');getWorld():setMap('Muldraugh, KY')
  MainScreen.instance:setDefaultSandboxVars()
  for name,value in pairs({Zombies=6,StartMonth=7,StartDay=9,StartTime=2,MinutesPerPage=2.0}) do getSandboxOptions():getOptionByName(name):setValue(value) end
  getSandboxOptions():toLua();MainScreen.instance.createWorld=true
  MapSpawnSelect.instance.selectedRegion={points={unemployed={{posX=10835,posY=10144,posZ=0}}}}
  MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'});MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
 else
  if (not connecting and not isClient()) or advanced or isIngameState() then return end
  if not MainScreen.instance or not MainScreen.instance.charCreationProfession or not MapSpawnSelect.instance then return end
  if MainScreen.instance.charCreationProfession:getIsVisible() or MapSpawnSelect.instance:getIsVisible() then
   advanced=true;MapSpawnSelect.instance:useDefaultSpawnRegion();MapSpawnSelect.instance:setVisible(false)
   MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'});MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
  end
 end
end)
Events.OnConnectFailed.Add(function(a,b) print('[QUEUE_TEST] FAIL HEALTH connect '..tostring(a)..' '..tostring(b));emit({event='error',reason='connect '..tostring(a)..' '..tostring(b)}) end)
Events.OnGameStart.Add(function()
 started=getTimestampMs();since=started
 getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false);getPlayer():setAutoDrink(false)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
 if kind=='sp' then
  getPlayer():setGhostMode(true);ids=Authority.setup(getPlayer());session={active=true,turn=1}
  print('[QUEUE_TEST] TRUE_SP world='..getWorld():getWorld()..' nativeDurations=true')
 else print('[QUEUE_TEST] NATIVE_CONNECTED '..user..' actualPeer=true nativeDurations=true') end
 emit({event='setup',cases=caseIDs,expected=#caseIDs,language=language,nativeDurations=true,queueEnabled=PZSurvivorToolkit.Settings.actionQueue()})
end)
Events.OnTick.Add(function()
 if not started or done then return end
 local now=getTimestampMs()
 if not ids or not session or (not session.active and not done) then
  if now-started>2000 and now-lastReady>1000 then lastReady=now;send('Ready') end
  if now-started>=1800000 then emit({event='error',reason='medical session/peer deadline'});failures=failures+1;complete();done=true end;return
 end
 if not session.active then return end
 local spec=stages[step];if not spec or now-since<50 then return end
 local ok,result=pcall(function()
  assert(now-since<180000,'native medical stage deadline '..spec.name)
  if spec.ready and not spec.ready() then return false end
  return spec.fn()
 end)
 if not ok then
  for className,class in pairs({HealthPanelAction=HealthPanelAction,ISHealthPanel=ISHealthPanel,ISSplint=ISSplint,ISInventoryPaneContextMenu=ISInventoryPaneContextMenu}) do
   for name,callback in pairs(class) do
    if type(callback)=='function' and (className~='ISHealthPanel' and className~='ISInventoryPaneContextMenu'
     or name=='checkItems' or name=='dropItemsOnBodyPart' or name=='doBodyPartContextMenu' or name=='getContainers'
     or name=='applyBandage' or name=='transferIfNeeded') then
     local known,filename=pcall(getFilenameOfClosure,callback)
     print('[QUEUE_TEST] HEALTH_BINDING '..className..'.'..name..' source='..tostring(known and filename))
    end
   end
  end
  for owner,methods in pairs({ISInventoryTransferAction={'new','perform','transferItem'},ISInventoryTransferUtil={'newInventoryTransferAction','isPlayerCharacter','isCharacterGrabbingCorpseItem','isPlayerGrabbingCorpseItem'},luautils={'haveToBeTransfered','walkToContainer'}}) do
   for _,name in ipairs(methods) do
    local ok,source=pcall(getFilenameOfClosure,_G[owner][name])
    print('[QUEUE_TEST] HEALTH_INVENTORY_BINDING '..owner..'.'..name..' source='..tostring(ok and source))
   end
  end
  local carts=PZSurvivorToolkit.ActionQueueCarts
  local compat=PZSurvivorToolkit.ActionQueueCompat
  print('[QUEUE_TEST] HEALTH_INVENTORY_CART startupReady='..tostring(compat.isInstalled('SaucedCartsTransfers'))
   ..' trusted='..tostring(carts and carts.install())..' containers='..tostring(compat.isInstalled('EURY_CONTAINERS'))
   ..' currentApproved='..tostring(carts and carts.isTransferConstructor(ISInventoryTransferAction.new)))
  for i=0,getLoadedLuaCount()-1 do
   local path=getLoadedLua(i)
   for _,name in ipairs({'ActionQueueCarts.lua','TransferRestrictions.lua','VisualUpdateQueue.lua','CartStateHandler.lua','/SaucedCarts/ContextMenu.lua'}) do
    if path:find(name,1,true) then print('[QUEUE_TEST] HEALTH_LOAD '..i..' '..path);break end
   end
  end
  for _,path in ipairs({'client/ISUI/ISInventoryPaneContextMenu.lua','shared/luautils.lua','shared/TimedActions/ISInventoryTransferUtil.lua'}) do
   local reader=getGameFilesInput('media/lua/'..path);local hash,bytes=5381,0
   if reader then
    while bytes<=300000 do local line=reader:readLine();if not line then break end
     bytes=bytes+#line+1;for i=1,#line do hash=(hash*33+string.byte(line,i))%4294967296 end;hash=(hash*33+10)%4294967296
    end
    reader:close()
   end
   print('[QUEUE_TEST] HEALTH_INVENTORY_SOURCE '..path..' hash='..hash..' bytes='..bytes)
  end
  print('[QUEUE_TEST] HEALTH_CONTAINER_GUARD '..tostring(PZSurvivorToolkit.ActionQueueFire.matchesContainerGetter(ISInventoryPaneContextMenu.getContainers)))
  if LootSorter then
   for _,entry in ipairs({{'client/LootSorter_CraftMenu.lua',2721161845},{'shared/LootSorter_Debug.lua',948729780}}) do
    print('[QUEUE_TEST] HEALTH_QM_SOURCE '..entry[1]..' verified='..tostring(PZSurvivorToolkit.ActionQueueCompat.verifySources('Quartermaster',{entry})))
   end
   print('[QUEUE_TEST] HEALTH_QM_STATE hooks='..tostring(LootSorter._craftHooksAdded)..' wrapped='..tostring(LootSorter._getContainersWrapped)
    ..' availability='..tostring(LootSorter.craftFromBoxes)..' crafting='..tostring(LootSorter._activelyCrafting)..' context='..tostring(LootSorter._craftContextUntil)..' now='..getTimestampMs())
  end
  print('[QUEUE_TEST] HEALTH_DIAG current='..tostring(queue().current and queue().current.Type)..' native='..tostring(getPlayer():hasTimedActions()))
  for i,action in ipairs(queue().queue) do print('[QUEUE_TEST] HEALTH_QUEUE '..i..' '..action.Type..' started='..tostring(action:isStarted())) end
  print('[QUEUE_TEST] FAIL '..spec.name..' '..tostring(result));failures=failures+1
  if spec.id then performed=performed+1;emit({event='case',id=spec.id,status='failed',reason=tostring(result),outcome=receipts[spec.id] and receipts[spec.id].outcome})
  else emit({event='error',reason=spec.name..' '..tostring(result)}) end
  complete();done=true;return
 end
 if result~=false then
  if spec.id then
   local status=type(result)=='table' and result.status or 'passed'
   if status=='skipped' then skipped=skipped+1 else performed=performed+1 end
   emit({event='case',id=spec.id,status=status,reason=type(result)=='table' and result.reason or nil,outcome=type(result)=='table' and result.outcome or nil})
   print('[QUEUE_TEST] '..(status=='skipped' and 'SKIP ' or 'PASS ')..spec.name)
  else print('[QUEUE_TEST] PASS '..spec.name) end
  step=step+1;since=now
  if step>#stages then
   print('[QUEUE_TEST] COMPLETE checks='..performed..' skipped='..skipped..' failures=0');complete();done=true
   if kind=='mp' then send('Finish') end
  end
 end
end)
