local selectedEquipEdit=require 'QueueTestSelection'
if selectedEquipEdit.cases[1]=='equip-edit'then require 'QueueEquipEditClient';return end
require 'PZSurvivorToolkit/ActionQueuePanel'
require 'PZSurvivorToolkit/BulkFirearms'
require 'ISUI/ISInventoryPaneContextMenu'
require 'TimedActions/ISUnloadBulletsFromMagazine'
require 'TimedActions/ISUnloadBulletsFromFirearm'
require 'TimedActions/ISEquipWeaponAction'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local F=require 'QueueMagazineUnload'
local P=require 'QueueEnergyPlacement'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local native=config.mode=='native'
local callbacks={};for _,name in ipairs({'isValid','start','update','isLocal','updateLoadingTime','initVars','serverStop','serverStart','getDuration','complete','animEvent','stop','perform','new'})do callbacks[name]=ISUnloadBulletsFromMagazine[name]end
local callbackClasses={ISUnloadBulletsFromMagazine=callbacks}
for _,class in ipairs({ISUnloadBulletsFromFirearm,ISEquipWeaponAction})do
 local methods={};for key in pairs(callbacks)do methods[key]=class[key]end;callbackClasses[class.Type]=methods
end
local phase,index='prepare',1
local state,authority,previous,ids,receipt,placement,arrival,proof,quiet
local started,ready,done=false,false,false
local tracks,commands,calls,preparations,bindings={}, {}, {}, {}, {}
local edits={cancelled=false,reordered=false,untouched=true}
local pendingBefore,pendingAfter,pendingOrder
local function inputName(name)return(name=='repeat-first'or name=='repeat-second')and'front'or name end
assert(PZSurvivorToolkit.ActionQueueLifecycle.registerObserver('magazine-unload-native-boundaries',F.lifecycleObserver(function()return tracks end,callbackClasses,bindings)))
local function now()return getTimestampMs()end
local since,waiting=now(),now();local waits={}
local function case()return config.cases[index]end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function empty()return #queue().queue==0 and not getPlayer():hasTimedActions()end
local function raw(event,value)print('[MAGAZINE_UNLOAD] '..event..' '..JSON.encode(value))end
local function emit(value)value.suite='magazine-unload';value.actor='client1';value.kind=config.kind;value.mode=config.mode;JSON.emit(value)end
local function diagnostic(reason,force)
 if not ids or not getPlayer()or not force and(waits[phase]or now()-waiting<2000)then return end
 waits[phase]=true;local ok,value=pcall(F.snapshot,{player=getPlayer(),ids=ids,items={}})
 raw(force and'FAILED_STATE'or'PREPARED_WAIT',{phase=phase,reason=reason,state=ok and value or tostring(value)})
end
local function fail(error)
 if done then return end;done=true;diagnostic(tostring(error),true)
 print('[QUEUE_TEST] FAIL magazine-unload '..tostring(error));emit({event='case',id=case(),status='failed',phase=phase,reason=tostring(error)})
end
local function request(command)
 local args={case=case()};if command=='Prepare'then args.placement=placement;args.clientPlacement=proof end
 if isClient()then sendClientCommand('MagazineUnloadTest',command,args);return end
 if command=='Prepare'then authority=F.prepare(getPlayer(),case(),config.mode,placement,proof,previous);previous=nil;ids=authority.ids;raw('PREPARED',ids)
 else receipt=assert(F.verify(authority));raw('VERIFIED',receipt)end
end
Events.OnServerCommand.Add(function(module,command,args)
 if done or module~='MagazineUnloadTest'then return end
 if command=='Failed'then fail(args.error)
 elseif args and args.case==case()then if command=='Prepared'then ids=args elseif command=='Verified'then receipt=args end end
end)
local function producer(names)
 local emitted={};local player=getPlayer();local add=ISTimedActionQueue.add
 local byID={};local rows={}
 for _,name in ipairs(names)do local item=state.items[inputName(name)];byID[item:getID()]=name;rows[#rows+1]=item end
 ISTimedActionQueue.add=function(action)
  assert(action.Type=='ISUnloadBulletsFromMagazine','unexpected root magazine producer action')
  local item=assert(action.magazine);local name=assert(byID[item:getID()],'producer retargeted magazine')
  assert(item==state.items[inputName(name)]and item:getContainer()==player:getInventory()and action.maxTime==-1,'native magazine constructor differs')
  for key,callback in pairs(callbacks)do assert(action[key]==callback and ISUnloadBulletsFromMagazine[key]==callback,'native unload callback changed '..key)end
  local guard=F.ownStartGuard(action);local owned=false
  if case()=='bulk'then
   local bound,id=PZSurvivorToolkit.BulkFirearms.magazineUnloadBinding(action,guard)
   assert(type(guard)=='function'and bound and id==item:getID(),'owned bulk magazine guard differs');owned=true
  else assert(guard==nil and not action.toolkitIndependentBulk,'direct native magazine has an extra start guard')end
  local row={name=name,type=action.Type,item=item:getID(),producer=case()=='bulk'and'BulkFirearms.unloadEntries + queueUnload'or'native ISInventoryPaneContextMenu.onUnloadBulletsFromMagazine',
   duration=action.maxTime,constructorAmmo=item:getCurrentAmmoCount(),callbacksUntouched=true,ownedBulkGuard=owned,started=false,progress=false,partialCounts={},lifecycle={},constructorStartUnset=action.ammoCountStart==nil}
  assert(row.constructorStartUnset,'native constructor unexpectedly ran start')
  local expected=inputName(name)=='front'and name~='front'and pendingBefore.magazines.front.loaded or ids.magazines[name].loaded
  assert(row.constructorAmmo==expected and row.constructorAmmo>0,'producer changed loaded input')
  bindings[action]={};for key,callback in pairs(callbacks)do bindings[action][key]=action[key]end
  if guard then bindings[action].isValidStart=guard end
  tracks[action]=row;commands[#commands+1]=row;emitted[#emitted+1]=action
  return add(action)
 end
 local ok,error=pcall(function()
  if case()=='bulk'then
   local entries=PZSurvivorToolkit.BulkFirearms.unloadEntries(player,rows)
   assert(#entries==#names,'public bulk selection changed')
   for i,entry in ipairs(entries)do assert(entry.item==rows[i]and entry.kind=='magazine','bulk entry identity differs')end
   assert(PZSurvivorToolkit.BulkFirearms.queueUnload(player,entries)==#names,'public bulk queue count differs')
   calls[#calls+1]={names=names,entries=#entries,queued=#emitted}
  else
   for i,item in ipairs(rows)do
    local before=#emitted
    ISInventoryPaneContextMenu.onUnloadBulletsFromMagazine(player,item)
    calls[#calls+1]={names={names[i]},entries=1,queued=#emitted-before}
   end
  end
 end)
 ISTimedActionQueue.add=add;assert(ok,error);assert(#emitted==#names,'native magazine producer shape differs')
 for i,action in ipairs(emitted)do assert(tracks[action].name==names[i],'native producer order differs')end
 return emitted
end
local function gunProducer(names)
 local player=getPlayer();local add=ISTimedActionQueue.add;local emitted,rows,byID={}, {}, {}
 for _,name in ipairs(names)do
  local source=name=='gun-repeat-a'and'gun-a'or name=='gun-repeat-b'and'gun-b'or name
  local item=state.items[source];rows[#rows+1]=item;byID[item:getID()]=name
  assert(item:getCurrentAmmoCount()==1 and not player:isEquipped(item),'gun selection must still be loaded and unheld')
 end
 ISTimedActionQueue.add=function(action)
  local equip=action.Type=='ISEquipWeaponAction'
  assert(equip or action.Type=='ISUnloadBulletsFromFirearm','unexpected integral producer preparation')
  local item=equip and action.item or action.gun;local name=assert(byID[item:getID()],'integral producer retargeted input')
  assert(item:getContainer()==player:getInventory()and item==rows[#emitted+1],'integral producer input/order differs')
  local guard=F.ownStartGuard(action);local owned=case()=='bulk'
  if owned then
   assert(type(guard)=='function'and Proof.closure(guard,'BulkFirearms.lua'),'owned integral guard source differs')
   if equip then assert(Proof.closure(action.start,'BulkFirearms.lua'),'owned equip start source differs')
   else assert(action.toolkitIndependentBulk,'owned unload marker missing')end
  else assert(not guard and not action.toolkitIndependentBulk,'direct integral action has owned guard')end
  for key,callback in pairs(callbackClasses[action.Type])do
   assert(equip and owned and key=='start'or action[key]==callback and _G[action.Type][key]==callback,'integral native callback changed '..key)
  end
  local row={name=equip and'equip-'..name or name,type=action.Type,item=item:getID(),duration=action.maxTime,
   callbacksUntouched=true,ownedBulkGuard=owned,lifecycle={}}
  bindings[action]={};for key in pairs(callbackClasses[action.Type])do bindings[action][key]=action[key]end
  if guard then bindings[action].isValidStart=guard end
  if equip then
   assert(action.maxTime==50 and action.maxTimeInit==50 and action.primary and action.twoHands,'native integral equip duration/hands differ')
   row.preparation=true;row.target=name;row.primary=action.primary;row.twoHands=action.twoHands;row.constructorHands=F.hands(player)
   preparations[#preparations+1]=row
  else
   assert(action.maxTime==-1 and action.ammoCountStart==nil,'native integral constructor differs')
   row.producer=case()=='bulk'and'BulkFirearms.unloadEntries + queueUnload'or'native ISInventoryPaneContextMenu.onUnloadBulletsFromFirearm'
   row.constructorAmmo=item:getCurrentAmmoCount();row.constructorStartUnset=true;row.started=false;row.progress=false;row.partialCounts={}
   commands[#commands+1]=row;emitted[#emitted+1]=action
  end
  tracks[action]=row;return add(action)
 end
 local ok,error=pcall(function()
  if case()=='bulk'then
   local entries=PZSurvivorToolkit.BulkFirearms.unloadEntries(player,rows)
   assert(#entries==#names,'public integral bulk selection changed')
   for i,entry in ipairs(entries)do assert(entry.item==rows[i]and entry.kind=='gun','public integral entry differs')end
   assert(PZSurvivorToolkit.BulkFirearms.queueUnload(player,entries)==#names,'public integral bulk queue count differs')
   calls[#calls+1]={names=names,entries=#entries,queued=#emitted}
  else
   for i,item in ipairs(rows)do
    local before=#emitted;ISInventoryPaneContextMenu.onUnloadBulletsFromFirearm(player,item)
    calls[#calls+1]={names={names[i]},entries=1,queued=#emitted-before}
   end
  end
 end)
 ISTimedActionQueue.add=add;assert(ok,error);assert(#emitted==#names,'native integral producer shape differs')
 for i,action in ipairs(emitted)do assert(tracks[action].name==names[i],'native integral unload order differs')end
end
local function observe()
 for action,row in pairs(tracks)do
  if not row.preparation and queue().current==action and action:isStarted()then
   if not row.started then row.started=true;row.startedAt=now()end
   local magazine=getPlayer():getInventory():getItemById(row.item)
   assert(magazine and magazine:getFullType()==(action.gun and'Base.Shotgun'or'Base.9mmClip')and magazine:getContainer()==getPlayer():getInventory(),'active native magazine identity lost')
   local loaded=magazine:getCurrentAmmoCount()
   if loaded>0 and loaded<row.constructorAmmo then
    row.progress=true
    if row.partialCounts[#row.partialCounts]~=loaded then row.partialCounts[#row.partialCounts+1]=loaded end
   end
  end
 end
end
require('QueuePreflight').onGameStart(Events,function()started=true;since=now()end)
require('QueuePreflight').onTick(Events,function()
 if not started or done then return end
 local ok,error=pcall(function()
  local player=getPlayer();if not isIngameState()or not player or not player:getSquare()then return end
  if not ready then
   if isClient()~=(config.kind=='mp')or isClient()and(player:getOnlineID()<0 or player:getUsername()~='client1')then return end
   local options=PZAPI.ModOptions:getOptions('PZSurvivorToolkit');options:getOption('ActionQueue'):setValue(not native);options:getOption('BulkUnload'):setValue(true)
   assert(PZSurvivorToolkit.Settings.actionQueue()==not native and PZSurvivorToolkit.Settings.bulkUnload()and not player:isTimedActionInstant())
   local installed=assert(PZSurvivorToolkit.ActionQueueMagazine,'magazine adapter missing').install()
   raw('ADAPTER',{installed=installed,queueEnabled=not native});if not native then assert(installed,'full-pack magazine adapter binding differs')end
   getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false);player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false)
   if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
   ready=true;since=now();emit({event='setup',cases=config.cases,queueEnabled=not native,nativeDurations=true,adapterInstalled=installed})
  end
  assert(now()-since<120000,'magazine fixture timeout '..phase);observe()
  if phase=='prepare'then
   assert(empty());if not arrival then placement=P.choose(player);arrival=P.beginCentered(player,placement)end
   proof=P.poll(arrival);if not proof then return end
   raw('CLIENT_PLACEMENT',{case=case(),proof=proof});phase='prepared';waiting=now();request('Prepare')
  elseif phase=='prepared'and ids then
   state=F.resolve(player,ids);if not state then diagnostic('exact root inputs/baseline not ready');return end
   state.input=assert(F.baseline(state));state.front=producer({'front'})[1];phase='front'
  elseif phase=='front'and tracks[state.front].progress then
   assert(queue().current==state.front and player:getInventory():getItemById(ids.magazines.front.id):getCurrentAmmoCount()>0,'front unload must still be active')
   pendingBefore=F.snapshot(state)
   producer({'repeat-first'});producer({'repeat-second'})
   local actions=producer({'target','cancelled','tail'})
   if not native then
    assert(PZSurvivorToolkit.ActionQueue.cancelOperation(queue(),actions[2]),'pending magazine cancellation denied')
    tracks[actions[2]].cancelled=true;edits.cancelled=true
    assert(PZSurvivorToolkit.ActionQueue.move(queue(),actions[3],actions[1]),'independent pending magazine reorder denied')
    local first,last
    for i,action in ipairs(queue().queue)do if action==actions[3]then first=i elseif action==actions[1]then last=i end end
    assert(first and last and first<last,'magazine edit did not commit');edits.reordered=true
   end
   gunProducer({'gun-a','gun-b'});gunProducer({'gun-repeat-a','gun-repeat-b'});producer({'gun-tail'})
   pendingOrder={};for _,action in ipairs(queue().queue)do pendingOrder[#pendingOrder+1]=assert(tracks[action],'untracked pending producer action').name end
   pendingAfter=F.snapshot(state);edits.untouched=F.equal(pendingBefore,pendingAfter)
   assert(edits.untouched,'pending edits changed physical magazine/ammo state');phase='running'
  elseif phase=='running'and empty()then
   if not F.verify(state)then quiet=nil;diagnostic('native counts/output conservation not settled');return end
   quiet=quiet or now();if now()-quiet>=1000 then phase='verified';request('Verify')end
  elseif phase=='verified'and receipt then
   local client=assert(F.verify(state))
   for _,row in ipairs(commands)do assert(row.cancelled and not row.started and not row.progress and #row.partialCounts==0
    or not row.cancelled and(row.type=='ISUnloadBulletsFromFirearm'and row.started or inputName(row.name)=='front'and row.name~='front'or row.started and row.progress and #row.partialCounts>0),'native start/partial/cancellation evidence missing')end
   for _,row in ipairs(commands)do
    if not row.cancelled then
     local finished=false
     for _,event in ipairs(row.lifecycle)do
      if event.event=='finish'and event.phase=='perform'and event.succeeded and event.nativeEpisode and event.nativeClass=='LuaTimedActionNew'
       and(row.name~='repeat-first'and row.name~='repeat-second'and row.name~='gun-repeat-a'and row.name~='gun-repeat-b'or event.startAmmo==0 and event.loaded==0)then finished=true end
     end
     assert(finished,'native perform/empty-start evidence missing '..row.name)
    end
   end
   emit({event='case',id=case(),status='passed',ids=ids,clientPlacement=proof,input=state.input,client=client,server=receipt,
    commands=commands,preparations=preparations,producerCalls=calls,pendingBefore=pendingBefore,pendingAfter=pendingAfter,pendingOrder=pendingOrder,edit=edits,queueIdle=true,settleMilliseconds=now()-quiet})
   if not isClient()then previous=authority end
   index=index+1
   if not case()then emit({event='complete',cases=config.cases,performed=index-1,failed=0,skipped=0});raw('COMPLETE',{cases=config.cases});done=true;return end
   state,authority,ids,receipt,placement,arrival,proof,quiet=nil,nil,nil,nil,nil,nil,nil,nil
   tracks,commands,calls,preparations={}, {}, {}, {};for action in pairs(bindings)do bindings[action]=nil end;edits={cancelled=false,reordered=false,untouched=true};pendingBefore,pendingAfter=nil,nil
   phase='prepare';since=now();waiting=now();waits={}
  end
 end)
 if not ok then fail(error)end
end)
