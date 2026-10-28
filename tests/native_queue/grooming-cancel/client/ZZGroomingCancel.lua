require 'PZSurvivorToolkit/ActionQueuePanel'
require 'XpSystem/ISUI/ISCharacterScreen'
require 'TimedActions/ISReadABook'
require 'TimedActions/ISTrimBeard'
require 'TimedActions/ISDyeHair'
local F=require 'QueueGroomingCancel';local JSON=require 'QueueHealthEvents';local config=require 'QueueTestSelection'
local T=PZSurvivorToolkit;local native=config.mode=='native'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local producers={
 ISCutHair={owner=ISCharacterScreen,key='onCutHair',callback=ISCharacterScreen.onCutHair,class=ISCutHair,source='ISCharacterScreen.lua'},
 ISTrimBeard={owner=ISCharacterScreen,key='onTrimBeard',callback=ISCharacterScreen.onTrimBeard,class=ISTrimBeard,source='ISCharacterScreen.lua'},
 ISDyeHair={owner=ISInventoryPaneContextMenu,key='onDyeHair',callback=ISInventoryPaneContextMenu.onDyeHair,class=ISDyeHair,source='ISInventoryPaneContextMenu.lua'}}
-- ZZGroomingCancel loads before ZZStartup; choose gender through the ordinary creation UI before its NEXT callback.
Events.OnPreUIDraw.Add(function()
 if isIngameState()then return end
 local main=MainScreen and MainScreen.instance;local panel=main and main.charCreationMain
 if not panel or not panel.genderCombo or not main.desc or not main.avatar then return end
 if panel.genderCombo.selected~=2 or main.desc:isFemale()then
  assert(Proof.closure(panel.onGenderSelected,'CharacterCreationMain.lua'),'native gender creation callback unavailable')
  panel.genderCombo.selected=2;panel:onGenderSelected(panel.genderCombo)
 end
end)
local entered,ready,done=false,false,false
local phase,index,since='prepare',1,0
local state,ids,previous,baseline,authorityBaseline,checkpoint,authorityFinal,baselineRequested,setupActual
local front,tail,body,pickup,boundary,beforeTail,idle,quiet,records,actions,classes,ackRecords,observedTerminal
local bodyStarts,bodyCompletes=0,0
local outcomes,startedReceipt,nativeEpisodes={}
local serial=0
local function case()return config.cases[index]end
local function baseCase()return F.baseCase(case())end
local function active()return F.active(case())end
local function moving()return F.moving(case())end
local function now()return getTimestampMs()end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function empty()return #queue().queue==0 and not getPlayer():hasTimedActions()end
local function raw(marker,row)print('[GROOMING_TEST] '..marker..' '..JSON.encode(row))end
local function emit(row)row.suite,row.kind,row.mode,row.actor='grooming-cancel',config.kind,config.mode,'client1';JSON.emit(row)end
local function snapshot()return F.snapshot(state)end
local function itemID(action)local item=action.item or action.hairDye;return item and item:getID()or false end
local function role(action)
 if not state or action.character~=state.player then return end
 if action==front then return 'front'end
 if action==tail then return 'tail'end
 if action==body then return 'body'end
 local held=F.held(case())
 if held and(action.Type=='ISEquipWeaponAction'or action.Type=='P4RestoreAction')then
  local item=itemID(action)
  if item==ids.items[held.primary]or item==ids.items[held.secondary]then return 'restore'end
 end
 local borrowed=F.borrowed(state)
 if borrowed and action.Type=='ISInventoryTransferAction'and itemID(action)==borrowed:getID()then
  if F.source(state,action.srcContainer)and action.destContainer==state.player:getInventory()then pickup=action;return 'prepare'end
  if action.srcContainer==state.player:getInventory()and F.source(state,action.destContainer)then return 'return'end
 end
 if action.toolkitQueueOperation and body and action.toolkitQueueOperation==body.toolkitQueueOperation then return 'prepare'end
end
local function register(action)
 if not records or not action then return end
 local row=actions[action];if row then return row end
 local kind=role(action);if not kind then return end
 serial=serial+1
 local duration=action.maxTime
 if action.Type=='ISInventoryTransferAction'then
  local group=assert(action.queueList and action.queueList[1],'native transfer constructor members missing')
  duration=group.time
 end
 row={sequence=serial,role=kind,kind=action.Type,item=itemID(action),constructorDuration=duration,started=false,starts=0,
  finishes={},nativeRef=false,transaction=false,token=false,terminal=false}
 if kind=='restore'then
  row.restoration={primary=action.primary==true,twoHands=action.twoHands==true,activated=action.activated==true,begins=0,source=false}
 end
 records[#records+1]=row;actions[action]=row
 local class=getmetatable(action)
 if not classes[class]then
  local methods={};for _,name in ipairs({'new','isValid','isValidStart','waitToStart','start','stop','update','perform','complete','getDuration','forceCancel','forceStop','stopSound','create','begin','adjustMaxTime','interruptWaitToStart','getDeltaModifiers','getJobDelta','setActionAnim','setOverrideHandModels','setAnimVariable'})do methods[name]=class[name]or false end
  classes[class]=methods
 end
 return row
end
local function intact()
 local producer=assert(producers[ids.actionKind])
 assert(producer.owner[producer.key]==producer.callback and _G[ids.actionKind]==producer.class,'native grooming producer/class replaced')
 for class,methods in pairs(classes)do for name,callback in pairs(methods)do assert((class[name]or false)==callback,'native grooming method changed '..class.Type..'.'..name)end end
 assert(body and getmetatable(body)==producer.class and body.complete==producer.class.complete,'native body class changed')
 if ids.actionKind=='ISCutHair'then assert(body.hairStyle==ids.targetStyle,'native hair target changed')
 elseif ids.actionKind=='ISTrimBeard'then assert(body.beardStyle==ids.targetBeard,'native beard target changed')
 else assert(body.beard==(baseCase()=='dye-beard')and itemID(body)==ids.items.dye,'native dye target/identity changed')end
 local contract,adapter=T.ActionQueuePolicy.inspect(body)
 assert(contract and adapter=='native.'..ids.actionKind and (F.moveAllowed(case())or contract.knownInputs==false),'source-pinned native haircut inspector unavailable')
end
local function restorationProof(action,row)
 local class=getmetatable(action);local compat=T.ActionQueueCompat
 assert(_G[action.Type]==class and type(compat)=='table'and compat.isInstalled('P4TidyUpMeister')
  and compat.verifySources('P4TidyUpMeister'),'reviewed P4 restoration source unavailable')
 local contract,adapter=T.ActionQueuePolicy.inspect(action)
 if action.Type=='ISEquipWeaponAction'then
  assert(contract and(adapter=='native.ISEquipWeaponAction'or adapter=='compat.tidy-equipment'),'native/P4 equipment restoration inspection missing')
 else
  assert(action.Type=='P4RestoreAction'and Proof.closure(class.new,'P4RestoreAction.lua')
   and Proof.closure(class.isValid,'P4RestoreAction.lua')and Proof.closure(class.perform,'P4RestoreAction.lua'),'native P4 restoration callbacks changed')
  assert(not adapter or adapter=='compat.tidy-equipment','foreign P4 restoration inspection')
  adapter=adapter or'P4RestoreAction.source'
 end
 if adapter=='compat.tidy-equipment'then
  assert(contract.callbacksSafe==true,'P4 restoration callbacks are not source bound')
 else
  for _,name in ipairs({'onStartFunc','onCancelFunc','onCompleteFunc','onFailFunc','retriggerLastAction','additionalTest','additionalContext'})do
   assert(action[name]==nil or action[name]==false,'P4 restoration injected callback '..name)
  end
  for name,callback in pairs(action)do
   if type(callback)=='function'then assert(class[name]==callback,'P4 restoration injected function '..name)end
  end
 end
 if row.restoration.source then assert(row.restoration.source==adapter,'P4 restoration binding changed')end
 row.restoration.source=adapter
end
local function observeStarted(action)
 local row=register(action);if not row then return end
 if row.restoration then restorationProof(action,row);row.restoration.begins=row.restoration.begins+1 end
 if action==tail then
  assert(not beforeTail,'independent tail began twice')
  beforeTail={case=case(),at=now(),callback='ISBaseTimedAction.begin',snapshot=snapshot()};raw('BEFORE_TAIL',beforeTail)
  local borrowed=F.borrowed(state)
  if not native and not moving()and borrowed then
   assert(F.source(state,borrowed:getContainer()),'required exact borrowed grooming item return did not precede independent tail')
  end
 end
end
local function observeBegin(action,step)
 local row=register(action);if not row then return end
 if row.restoration and step=='perform'then restorationProof(action,row)end
 if step=='perform'and action.Type=='ISInventoryTransferAction'then
  row.transaction=action.transactionId or false
  local live=isClient()and type(action.transactionId)=='number'and action.transactionId~=0
  row.transactionDone=not isClient()or live and isItemTransactionDone(action.transactionId)==true or false
  row.transactionRejected=live and isItemTransactionRejected(action.transactionId)==true or false
 end
 return step=='perform'or step=='complete'
end
local function observeFinish(action,step,succeeded)
 local row=register(action);if not row then return end
 row.finishes[#row.finishes+1]={phase=step,succeeded=succeeded==true,at=now()}
 if action==body and step=='complete'and succeeded then
  assert(not isClient(),'Host completion must be proven by its sealed native transaction')
  bodyCompletes=bodyCompletes+1;assert(bodyCompletes==1,'native haircut complete replayed')
 end
end
local function observe()
 if not F.refresh(state)then return false end
 for _,action in ipairs(queue().queue)do register(action)end
 for action,row in pairs(actions)do
  if action.action and action:isStarted()and not row.started then
   row.started=true;row.starts=row.starts+1;row.startedAt=now();row.nativeRef=tostring(action.action);nativeEpisodes[action]=action.action
   if action==body then bodyStarts=bodyStarts+1;assert(native or active()or moving(),'canceled waiting haircut started')end
  end
  if active()and not native and action==body and boundary and not row.stoppedRemoval then
   local episode=nativeEpisodes[action]
   if episode and queue():indexOf(action)==-1 and not state.player:getCharacterActions():contains(episode)then
    assert(action.action==episode and not episode:finished()and not episode:isForceComplete(),'canceled grooming native identity/completion changed')
    row.stoppedRemoval={at=now(),nativeRef=tostring(episode),queueAbsent=true,nativeAbsent=true,
     finished=episode:finished(),forceComplete=episode:isForceComplete()}
   end
  end
  if isClient()and action==queue().current then
   local receipt=T.ActionQueueAcknowledgements.capture(action)
   if receipt then
    ackRecords[action]=receipt;row.transaction=receipt.transaction;row.token=receipt.token
   end
  end
  local receipt=ackRecords[action]
  if receipt then
   local terminal=T.ActionQueueAcknowledgements.observe(action,receipt)
   if terminal and terminal~='started'and not observedTerminal[action]then
    observedTerminal[action]=true;row.terminal=terminal
    if action==body and terminal=='completed'then bodyCompletes=bodyCompletes+1;assert(bodyCompletes==1,'sealed haircut completion replayed')end
   end
  end
 end
 intact();return true
end
local function request(name)
 if isClient()then sendClientCommand('GroomingCancelTest',name,{case=case()});return end
 if name=='Prepare'then state=F.prepare(getPlayer(),case(),previous);ids=state.ids;previous=nil;raw('PREPARED',ids);authorityBaseline=F.snapshot(state);raw('BASELINED',authorityBaseline)
 elseif name=='Checkpoint'then checkpoint=snapshot()
 elseif name=='Verify'then authorityFinal={baseline=authorityBaseline,checkpoint=checkpoint,final=snapshot(),
  bodyCompletes=bodyCompletes,bodyRecords=records,completeCountProof='shared-native-complete'};raw('VERIFIED',authorityFinal)end
end
Events.OnServerCommand.Add(function(module,name,args)
 if module=='PZSurvivorToolkitActions'and name=='State'and body and(active()or moving())
  and args.player==ids.actor and args.transaction==body.toolkitNativeTransaction and args.kind==body.toolkitNativeKind then
  local row={protocol=args.protocol,player=args.player,transaction=args.transaction,kind=args.kind,token=args.token,state=args.state}
  outcomes[#outcomes+1]=row;raw('OUTCOME',{case=case(),receipt=row});return
 end
 if module~='GroomingCancelTest'or done then return end
 if name=='Prepared'then ids=args
 elseif name=='Baselined'then authorityBaseline=args
 elseif name=='Checkpointd'then checkpoint=args
 elseif name=='Verified'then authorityFinal=args
 elseif name=='Failed'then error(args.error)end
end)
local function enqueue()
 local actual=snapshot()
 if not F.sameSetup(actual,ids.baseline)then
  raw('BASELINE_MISMATCH',{case=case(),at=now(),actual=actual,expected=ids.baseline})
  error('local grooming baseline differs from exact authority setup')
 end
 baseline=actual;records,actions,classes,ackRecords,observedTerminal={},{},{},{},{};serial=0
 bodyStarts,bodyCompletes=0,0;outcomes,startedReceipt,nativeEpisodes={},nil,{}
 assert(not state.player:isTimedActionInstant()and not getDebug(),'native haircut producer requires ordinary non-debug durations/equip')
 if moving()or baseCase()=='style-no-tool'then front=ISReadABook:new(state.player,state.front);ISTimedActionQueue.add(front)end
 if moving()then tail=ISReadABook:new(state.player,state.tail);ISTimedActionQueue.add(tail)end
 local producer=assert(producers[ids.actionKind])
 assert(producer.owner[producer.key]==producer.callback and Proof.closure(producer.callback,producer.source),'actual native grooming UI producer unavailable')
 if state.gel then
  local inventory=state.player:getInventory()
  local selected=inventory:getItemFromType('Hairgel',true,true)or inventory:getItemFromType('Hairspray2',true,true)or inventory:getFirstTagRecurse(ItemTag.DO_HAIRDO)
  assert(selected==state.gel,'native styling selector chose foreign styling item')
  if baseCase()=='greased-scissors'then assert(inventory:getItemFromType('Hairgel',true,true)==state.gel,'native GreasedBack second selector chose foreign Hairgel')end
 end
 local function produce()
  if ids.actionKind=='ISCutHair'then producer.callback(state.player,ids.targetStyle,ids.duration)
  elseif ids.actionKind=='ISTrimBeard'then producer.callback(state.player,ids.targetBeard)
  else producer.callback(state.dye,state.player,baseCase()=='dye-beard')end
 end
 -- The ordinary context-menu entrypoint scopes enqueueing in both queue modes.
 T.ActionQueueOperations.run(produce)
 for _,action in ipairs(queue().queue)do
  if action.Type==ids.actionKind then assert(not body,'duplicate haircut body');body=action end
 end
 assert(body and body.action==nil and body.maxTime==ids.duration and (ids.actionKind~='ISCutHair'or body.maxTimeInit==ids.duration),'native haircut constructor/time differs')
 assert(itemID(body)==(F.borrowed(state)and F.borrowed(state):getID()or false),'UI selected foreign grooming tool/dye')
 if not moving()then tail=ISReadABook:new(state.player,state.tail);ISTimedActionQueue.add(tail)end
 for _,action in ipairs(queue().queue)do register(action)end
 assert(moving()and queue():indexOf(front)==1 and queue():indexOf(tail)<queue():indexOf(body)or not moving()and queue():indexOf(tail)>queue():indexOf(body),'independent tail was grouped/lost')
 phase='running'
end
local function moveAtBoundary()
 if boundary then return end
 local current=queue().current
 if current~=front or not current.action or not current:isStarted()or current:getJobDelta()<=0 then return end
 assert(body.action==nil and bodyStarts==0 and bodyCompletes==0,'grooming move crossed an allocated body')
 local contract,adapter=T.ActionQueuePolicy.inspect(body)
 assert(contract and adapter=='native.'..ids.actionKind and contract.knownInputs==F.moveAllowed(case()),'pending grooming move source/resource proof differs: '..tostring(contract and contract.pendingMoveBlocker))
 local beforeOrder,group={},{}
 local token=assert(body.toolkitQueueOperation,'grooming operation token missing')
 for _,action in ipairs(queue().queue)do
  local row=assert(register(action),'unowned action in pending grooming move')
  beforeOrder[#beforeOrder+1]=row.sequence
  if action.toolkitQueueOperation==token then group[#group+1]=row.sequence end
 end
 assert(#group>0 and beforeOrder[1]==actions[front].sequence and beforeOrder[2]==actions[tail].sequence
  and #beforeOrder==#group+2,'grooming producer group was detached before move')
 if F.held(case())then assert(F.handsReady(state),'held styling input was stowed or replaced before move admission')end
 local before=snapshot();local progress=current:getJobDelta();local at=now()
 local accepted,reason=false,false
 if not native then accepted,reason=T.ActionQueue.move(queue(),body,tail,false)end
 assert(accepted==(not native and F.moveAllowed(case())),'pending grooming move permission differs: '..tostring(reason))
 local afterOrder={}
 for _,action in ipairs(queue().queue)do afterOrder[#afterOrder+1]=assert(actions[action],'move introduced foreign action').sequence end
 local expected={beforeOrder[1]}
 if accepted then
  for _,sequence in ipairs(group)do expected[#expected+1]=sequence end
  expected[#expected+1]=beforeOrder[2]
 else for i=2,#beforeOrder do expected[#expected+1]=beforeOrder[i]end end
 assert(F.same(afterOrder,expected),'pending grooming move detached preparation or changed protected order')
 assert(queue().current==front and front.action==nativeEpisodes[front]and front:isStarted()and body.action==nil,'pending move interrupted native front or allocated body')
 boundary={case=case(),at=at,mode=config.mode,kind=current.Type,item=itemID(current),progress=progress,started=true,
  bodyUnallocated=true,stage='move',startedReceipt=false,tailRetained=queue():indexOf(tail)~=-1,snapshot=before,
  accepted=accepted,reason=reason or false,beforeOrder=beforeOrder,afterOrder=afterOrder,group=group,
  front=actions[front].sequence,tail=actions[tail].sequence,body=actions[body].sequence}
 raw('EDIT',boundary);phase='checkpoint';request('Checkpoint')
end
local function cancelAtBoundary()
 if boundary then return end
 local current=queue().current
 local eligible
 if active()then
  eligible=current==body and body.action and body:isStarted()and body:getJobDelta()>0
  if not eligible then return end
  assert(bodyStarts==1 and bodyCompletes==0,'active grooming body start/effect witness differs')
  if isClient()then
   local receipt=ackRecords[body]
   if not receipt or T.ActionQueueAcknowledgements.state(body,receipt)~='started'then return end
   assert(#outcomes==1 and outcomes[1].state=='started'and outcomes[1].token==receipt.token,'active grooming started receipt differs')
   startedReceipt={transaction=receipt.transaction,kind=receipt.kind,token=receipt.token,state='started'}
  end
 else
  eligible=baseCase()=='style-no-tool'and current==front and current.action and current:isStarted()and current:getJobDelta()>0
   or baseCase()~='style-no-tool'and current==pickup and current and current.action and current:isStarted()and current:getJobDelta()>0
  if not eligible then return end
  assert(body.action==nil and bodyStarts==0 and bodyCompletes==0,'haircut body started before cancellation checkpoint')
 end
 local selected=active()and body or baseCase()=='style-no-tool'and body or current
 local before=snapshot();local progress=current:getJobDelta();local at=now();local unallocated=body.action==nil
 local accepted,reason=false,false
 if not native then
  accepted,reason=T.ActionQueue.cancelOperation(queue(),selected)
  if not accepted then
   local bindings={}
   for _,member in ipairs(queue().queue)do
    local contract,adapter=T.ActionQueuePolicy.inspect(member)
    bindings[#bindings+1]=member.Type..'='..tostring(adapter or 'unknown')..':'..tostring(contract and contract.preparation)..':'..tostring(contract and contract.interrupt)..':'..tostring(contract and contract.interruptBlocker)
   end
   error((active()and'active 'or'waiting ')..ids.actionKind..' cancellation rejected: '..tostring(reason)..' ['..table.concat(bindings,', ')..']')
  end
 end
 boundary={case=case(),at=at,mode=config.mode,kind=current.Type,item=itemID(current),progress=progress,started=true,
  bodyUnallocated=unallocated,stage=active()and'active'or'waiting',startedReceipt=startedReceipt or false,tailRetained=queue():indexOf(tail)~=-1,snapshot=before,accepted=accepted,reason=reason or false}
 assert(boundary.tailRetained,'grooming cancellation discarded independent reader')
 raw('CANCEL',boundary);phase='checkpoint';request('Checkpoint')
end
local function finish()
 local actual=snapshot();local expected=(native or moving())and 1 or 0
 assert(bodyStarts==(active()and 1 or expected)and bodyCompletes==expected,'native haircut start/complete count differs')
 assert(beforeTail and boundary and F.restored(state,actual)and F.restored(state,authorityFinal.final),'grooming cleanup/restoration proof missing')
 assert(actual.tailPages==ids.tailTotal and authorityFinal.final.tailPages==ids.tailTotal,'independent reader did not complete on both roles')
 for role,value in ipairs({actual,authorityFinal.final})do
  assert(F.effectsMatch(state,value,role==1 and baseline or authorityFinal.baseline,native or moving(),isClient()and role==1,authorityFinal.baseline),'native grooming cosmetic/fluid/gel effects differ')
 end
 local command={producer=ids.producer,duration=ids.duration,cancelled=not native and not moving(),boundary=boundary,beforeTail=beforeTail,
  records=records,bodyStarts=bodyStarts,bodyCompletes=bodyCompletes,idle=idle,frontQueued=front~=nil,
  completeCountProof=isClient()and'sealed-native-transaction'or'shared-native-complete',outcomes=outcomes}
 emit({event='case',id=case(),status='passed',ids=ids,baseline=baseline,command=command,receipt=authorityFinal,clientFinal=actual,nativeMethodsUnchanged=true})
 previous=ids;index=index+1;state,ids,baseline,authorityBaseline,checkpoint,authorityFinal=nil,nil,nil,nil,nil,nil
 front,tail,body,pickup,boundary,beforeTail,idle,quiet,records,actions,classes,ackRecords,observedTerminal=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
 baselineRequested,setupActual=nil,nil;since=now();phase='prepare'
 if not case()then emit({event='complete',cases=config.cases,performed=#config.cases,skipped=0,failed=0});raw('COMPLETE',{cases=config.cases});done=true end
end
Events.OnGameStart.Add(function()entered=true;since=now()end)
Events.OnTick.Add(function()
 if not entered or done then return end
 local ok,problem=pcall(function()
  local player=getPlayer();if not isIngameState()or not player or not player:getCurrentSquare()then return end
  if not ready then
   if isClient()~=(config.kind=='mp')or isClient()and player:getUsername()~='client1'then return end
   assert(not player:isFemale(),'native male creation setup was not applied')
   PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(not native)
   getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false);player:setAutoDrink(false)
   assert(T.ActionQueueLifecycle.registerObserver('fixture.grooming-cancel',{started=observeStarted,begin=observeBegin,finish=observeFinish}),'grooming native observer unavailable')
   ready=true;emit({event='setup',cases=config.cases,queueEnabled=not native,nativeDurations=true})
  end
  assert(now()-since<180000,'grooming timeout '..tostring(case())..' phase='..phase)
  if records and not observe()then return end
  if phase=='prepare'then if not empty()then return end;phase='prepared';request('Prepare')
  elseif phase=='prepared'and ids then
   if not state or F.held(case())then
    local settled,actual=F.resolve(player,ids);setupActual=actual
    if not settled then return end;state=settled;setupActual=nil
   end
   if isClient()and not baselineRequested then baselineRequested=true;phase='baseline';request('Baseline');return end
   if not player:tooDarkToRead()then enqueue()end
  elseif phase=='baseline'and authorityBaseline then if not player:tooDarkToRead()then enqueue()end
  elseif phase=='running'then if moving()then moveAtBoundary()else cancelAtBoundary()end
  elseif phase=='checkpoint'and checkpoint then phase='drain'
  elseif phase=='drain'then
   if not empty()then quiet=nil;return end
   local actual=snapshot();if not F.restored(state,actual)or actual.tailPages~=ids.tailTotal then quiet=nil;return end
   quiet=quiet or now()
   if now()-quiet>=2000 then idle={case=case(),since=quiet,at=now(),empty=true,snapshot=actual};raw('IDLE',idle);phase='verify';request('Verify')end
  elseif phase=='verify'and authorityFinal then finish()end
 end)
 if not ok then
  local actual=setupActual or false;if state then local observed,value=pcall(snapshot);if observed then actual=value end end
  emit({event='case',id=case(),status='failed',phase=phase,reason=tostring(problem),actualSnapshot=actual,command={boundary=boundary or false,records=records or{},bodyStarts=bodyStarts,bodyCompletes=bodyCompletes},ids=ids or false})
  print('[QUEUE_TEST] FAIL grooming-cancel '..tostring(problem));done=true
 end
end)
