require 'PZSurvivorToolkit/ActionQueuePanel'
require 'XpSystem/ISUI/ISCharacterScreen'
require 'ISUI/ISInventoryPaneContextMenu'
require 'TimedActions/ISTakeGenerator'
local config=require 'QueueTestSelection'
local A=require 'QueueGeneratorRecoveryAuthority'
local P=require 'QueueEnergyPlacement'
local JSON=require 'QueueHealthEvents'
local Razor=require 'PZSurvivorToolkit/ActionQueueRazorRestoration'
local T=PZSurvivorToolkit
local Proof=require 'PZSurvivorToolkit/SourceProof'
local RECOVERY='PZSurvivorToolkitGeneratorRecovery'
-- Use the real character-creation callback before the ordinary startup fixture.
Events.OnPreUIDraw.Add(function()
 if isIngameState()then return end
 local main=MainScreen and MainScreen.instance;local panel=main and main.charCreationMain
 if not panel or not panel.genderCombo or not main.desc or not main.avatar then return end
 if main.desc:isFemale()or panel.genderCombo.selected~=2 then
  assert(Proof.closure(panel.onGenderSelected,'CharacterCreationMain.lua'),'native character gender callback unavailable')
  panel.genderCombo.selected=2;panel:onGenderSelected(panel.genderCombo)
 end
end)
local started,done,ready=false,false,false
local index,phase,since=1,'layout',0
local layout,placing,ids,go,result,target,peerGo,advance
local trim,tail,recovery,explicit,peerAction
local evidence,tracks,ordered,methods,menu,primaryMenu
local preparedAt,verifyAt,trimAnnounced,peerRequested,peerAnnounced,peerFinished,peerDuration,peerDelta
local traceInstalled
local lastStage
local function stage(value,extra)
 if lastStage==value then return end;lastStage=value
 print('[GENERATOR_RECOVERY] STAGE '..tostring(config.cases[index])..' '..value..(extra and' '..extra or''))
end
local function case()return config.cases[index]end
local function name()return config.kind=='sp'and'client1'or getPlayer():getUsername()end
local function q()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function empty()return #q().queue==0 and not getPlayer():hasTimedActions()end
local function emit(marker,row)print('[GENERATOR_RECOVERY] '..marker..' '..JSON.encode(row))end
local function fail(problem)done=true;print('[QUEUE_TEST] FAIL generator-recovery '..tostring(problem))end
local function find(wanted)
 local function scan(container)
  local items=container:getItems()
  for i=0,items:size()-1 do local item=items:get(i)
   if item:getID()==wanted then return item end
   if instanceof(item,'InventoryContainer')then local found=scan(item:getItemContainer());if found then return found end end
  end
 end
 return scan(getPlayer():getInventory())
end
local function item(key)return ids and find(ids.items[key].id)end
local function physical()
 local player=getPlayer();local root=player:getInventory();local razor=item('razor');local bag=ids and find(ids.bag.id)
 local source=bag and bag:getItemContainer();local world,outputs={},{}
 local square=ids and getCell():getGridSquare(ids.x,ids.y,ids.z)
 if square then local objects=square:getObjects()
  for i=0,objects:size()-1 do local object=objects:get(i)
   if instanceof(object,'IsoGenerator')then world[#world+1]={index=object:getObjectIndex(),type=object:getGeneratorItemType(),condition=object:getCondition(),fuel=object:getFuel()}end
  end
 end
 local values=root:getItems()
 for i=0,values:size()-1 do local value=values:get(i)
  if value:getFullType()=='Base.Generator'then outputs[#outputs+1]={id=value:getID(),type=value:getFullType(),condition=value:getCondition(),fuel=value:getModData().fuel or 0,favorite=value:isFavorite(),canonical=value:getContainer()==root}end
 end
 local primary,secondary=player:getPrimaryHandItem(),player:getSecondaryHandItem()
 return{primary=primary and primary:getID()or false,secondary=secondary and secondary:getID()or false,
  razor=razor and razor:getID()or false,razorLocation=not razor and'missing'or razor:getContainer()==root and'root'or source and razor:getContainer()==source and'origin'or'other',
  bag=bag and bag:getID()or false,bagWorn=bag and player:getWornItems():contains(bag)or false,world=world,outputs=outputs,
  beard=player:getHumanVisual():getBeardModel()or'',tailPages=ids and player:getAlreadyReadPages(ids.items.tail.type)or false,
  blockedReturns=T.ActionQueueSettlement.blockedReturns(player)}
end
local function diagnostic(boundary,action)
 if not evidence then return end
 local ok,value=pcall(function()
  return{case=case(),boundary=boundary,at=getTimestampMs(),type=action and action.Type or false,ref=action and tostring(action)or false,
   sourceID=action and action.sourceID or nil,toolID=action and action.toolID or nil,episode=action and action.episode or nil,
   settlement=trim and T.ActionQueueSettlement.operationState(trim)or false,physical=physical()}
 end)
 if not ok then value={case=case(),boundary=boundary,error=tostring(value)}end
 emit('DIAGNOSTIC',value)
end
local function request(command,args)
 args=args or{};args.case=case()
 if isClient()then sendClientCommand('GeneratorRecoveryTest',command,args)
 elseif command=='Layout'then layout=A.layout(getPlayer(),case())
 elseif command=='Prepare'then A.prepare(getPlayer(),case(),args.target,args.clientPlacement);ids=A.seed()
 elseif command=='Ready'then go=A.ready(getPlayer(),case())
 elseif command=='TrimStarted'then A.trimStarted(getPlayer(),case())
 elseif command=='Verify'then result=A.verify(getPlayer(),case())
 else error('unexpected SP recovery command '..command)end
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~='GeneratorRecoveryTest'or done then return end
 if args.ok==false then fail(args.error);return end
 if args.case~=case()then return end
 if command=='Layout'then layout=args elseif command=='Prepared'then ids=args
 elseif command=='Begin'then go=true elseif command=='Verified'then result=args
 elseif command=='PeerGo'then peerGo=args elseif command=='Advance'then advance=true end
end)
local function callbacksSame()
 if ISCharacterScreen.onTrimBeard~=menu or ISInventoryPaneContextMenu.OnPrimaryWeapon~=primaryMenu then return false end
 for class,callbacks in pairs(methods or{})do for key,value in pairs(callbacks)do if class[key]~=value then return false end end end
 return true
end
local function track(action)
 if tracks[action]then return tracks[action]end
 local kind=action.Type
 assert(kind=='ISInventoryTransferAction'or kind=='ISEquipWeaponAction'or kind=='ISTrimBeard'or kind=='ISReadABook'or kind=='ISQueueActionsAction'or kind==RECOVERY,
  'unexpected automatic grooming action '..tostring(kind))
 local row={type=kind,ref=tostring(action),itemId=action.item and action.item:getID()or false,sourceID=action.sourceID,toolID=action.toolID,episode=action.episode,duration=action.maxTime,native=false,progress=false,started=false,operation=action.toolkitQueueOperation}
 tracks[action]=row;ordered[#ordered+1]=row
 emit('ACTION',{case=case(),type=kind,ref=row.ref,itemId=row.itemId,sourceID=row.sourceID,toolID=row.toolID,episode=row.episode,duration=row.duration})
 if kind=='ISTrimBeard'then assert(not trim or trim==action);trim=action
 elseif kind=='ISReadABook'then assert(not tail or tail==action);tail=action
 elseif kind==RECOVERY then assert(not recovery or recovery==action,'AUTO repeated generator pickup');recovery=action
 elseif kind=='ISEquipWeaponAction'and action.item and ids and action.item:getID()==ids.items.replacement.id then explicit=action end
 return row
end
local function observe(action)
 local row=track(action)
 if action.action then
  if row.nativeRef then assert(row.nativeRef==tostring(action.action),'native action allocation changed')end
  row.native=true;row.nativeRef=tostring(action.action)
  if q().current==action and action:isStarted()then
   row.started=true;row.startedAt=row.startedAt or getTimestampMs()
   local delta=action:getJobDelta();if delta>0 and delta<1 then row.progress=true;row.progressAt=row.progressAt or getTimestampMs()end
  end
 end
 return row
end
assert(T.ActionQueueLifecycle.registerObserver('fixture-generator-recovery',{
 started=function(action)
  if phase~='running'or name()~='client1'or action.character~=getPlayer()then return end
  local row=track(action);row.admittedAt=getTimestampMs();stage('admitted-'..action.Type);diagnostic('admitted',action)
  if action.Type=='ISReadABook'then
   local cleanup=true
   for _,pending in ipairs(q().queue)do if pending~=action and(pending==recovery or pending==trim)then cleanup=false end end
   local bag=assert(find(ids.bag.id));local returned=item('razor'):getContainer()==bag:getItemContainer()
   evidence.tailAfterCleanup=cleanup and returned==(case()=='auto-return'or case()=='cancel-active'or case()=='owner-pickup-first')
   evidence.tailStartedAt=getTimestampMs()
  end
 end,
 begin=function(action,boundary)
  if phase=='running'and name()=='client1'and action.character==getPlayer()then
   local row=observe(action);row.events=row.events or{};row.events[#row.events+1]={boundary='begin',phase=boundary,at=getTimestampMs()}
   diagnostic('begin-'..boundary,action)
  end
  return true
 end,
 finish=function(action,boundary,succeeded)
  if phase~='running'or name()~='client1'or action.character~=getPlayer()then return end
  local row=observe(action);row.finishedAt=getTimestampMs();row.succeeded=succeeded==true
  row.events=row.events or{};row.events[#row.events+1]={boundary='finish',phase=boundary,at=getTimestampMs(),succeeded=succeeded==true}
  diagnostic('finish-'..boundary,action)
 end,
}))
local function produce()
 assert(empty()and Razor.enabled(),'normal startup did not enable own grooming restoration')
 local player=getPlayer();assert(player:getPrimaryHandItem()==item('original')and player:getSecondaryHandItem()==item('original'),'native generator seed grips differ')
 tracks,ordered={},{};trim,tail,recovery,explicit=nil,nil,nil,nil
 evidence={case=case(),producer='ISCharacterScreen.onTrimBeard',canceled=false,explicitIntent=false,
  peerPickup=case()=='peer-pickup'or case()=='owner-pickup-first',noP4=not P4TidyUpMeister and not getActivatedMods():contains('P4TidyUpMeister')}
 phase='running';stage('normal-grooming-producer')
 ISCharacterScreen.onTrimBeard(player,ids.targetBeard)
 local token
 for _,action in ipairs(q().queue)do
  track(action);if token==nil then token=action.toolkitQueueOperation else assert(token==action.toolkitQueueOperation,'grooming producer split operation')end
 end
 assert(trim and token and trim.toolkitQueueOperation==token,'real trim producer lacks owned operation')
 evidence.producerSameOperation=true
 ISInventoryPaneContextMenu.readItem(assert(item('tail')),player:getPlayerNum())
 for _,action in ipairs(q().queue)do track(action)end
 assert(tail and tail.toolkitQueueOperation~=trim.toolkitQueueOperation,'real reader tail is not independent')
 evidence.independentTail=true;diagnostic('producer-complete',trim)
end
local function cancel()
 local panel=T.ActionQueuePanel:new(80,80,460,640);panel.queue,panel.playerNum=q(),getPlayer():getPlayerNum()
 panel:initialise();panel:addToUIManager();panel:update()
 local list=panel.list;local entry
 for _,candidate in ipairs(list.items)do if candidate.header and candidate.operation==trim.toolkitQueueOperation then assert(not entry);entry=candidate end end
 assert(entry,'active native grooming operation missing from real panel')
 list:setYScroll(0);local x,y=list:cancelX()+1,list:topOfItem(entry.index)+entry.height/2
 assert(list:rowUnderMouse(x,y)==entry,'cancel panel hit test differs')
 local before=getPlayer():getHumanVisual():getBeardModel();list:onMouseDown(x,y)
 assert(list.pressedOperation and list.pressedOperation.operation==trim.toolkitQueueOperation,'real cancel press was not accepted')
 list:onMouseUp(x,y);assert(not list.cancelFeedback,'real active grooming cancel rejected')
 assert(getPlayer():getHumanVisual():getBeardModel()==before,'cancel mutated styling')
 local tailPresent=false;for _,action in ipairs(q().queue)do if action==tail then tailPresent=true end end
 assert(tailPresent,'active cancellation removed independent reader tail')
 evidence.canceled=true;evidence.cancelAt=getTimestampMs();panel:removeFromUIManager()
end
local function observeOwner()
 assert(callbacksSame(),'fixture replaced a native producer/action callback')
 for _,action in ipairs(q().queue)do observe(action)end
 for action in pairs(tracks)do observe(action)end
 local row=assert(tracks[trim])
 if row.progress and q().current==trim then
  local authorityStarted=not isClient()
  if isClient()then
   row.ack=row.ack or T.ActionQueueAcknowledgements.capture(trim)
   authorityStarted=row.ack and T.ActionQueueAcknowledgements.state(trim,row.ack)=='started'
  end
  if authorityStarted then
   if not trimAnnounced then trimAnnounced=true;stage('trim-progress-after-native-drop');diagnostic('trim-progress',trim);request('TrimStarted')end
   if case()=='cancel-active'and not evidence.canceled then cancel()end
   if case()=='new-primary-intent'and not evidence.explicitIntent then
    local before=T.ActionQueueTidyIntent.primaryRequestRevision(getPlayer())
    ISInventoryPaneContextMenu.OnPrimaryWeapon({assert(item('replacement'))},getPlayer():getPlayerNum())
    for _,action in ipairs(q().queue)do track(action)end
    local after=T.ActionQueueTidyIntent.primaryRequestRevision(getPlayer())
    assert(explicit and not explicit.action and type(after)=='number'and after>before,'normal newer primary intent not accepted')
    evidence.explicitIntent=true
   end
   if case()=='peer-pickup'and trim:getJobDelta()>=.8 and not peerRequested then
    assert(trim:getJobDelta()<.95,'peer contention missed final active trim boundary')
    peerRequested=true;stage('peer-pickup-request-at-final-trim');request('PeerGo',{delta=trim:getJobDelta()})
   end
  end
 end
 if case()=='owner-pickup-first'and recovery and q().current==recovery and tracks[recovery].progress and not peerRequested then
  assert(recovery:getJobDelta()<.5,'AUTO-first contention missed early recovery progress')
  peerRequested=true;stage('peer-pickup-request-after-AUTO-progress');request('PeerGo',{delta=recovery:getJobDelta()})
 end
end
local function finishEvidence()
 evidence.nativeCallbacksSame=callbacksSame();evidence.trimProgress=tracks[trim].progress
 evidence.tailProgress=tracks[tail].progress;evidence.recoveryProgress=recovery and tracks[recovery].progress or false
 evidence.actions={}
 for _,row in ipairs(ordered)do
  local copy={};for key,value in pairs(row)do if key~='operation'and key~='ack'then copy[key]=value end end
  evidence.actions[#evidence.actions+1]=copy
 end
 if recovery then evidence.recoveryStartedAt=tracks[recovery].startedAt;evidence.recoveryProgressAt=tracks[recovery].progressAt;evidence.recoveryFinishedAt=tracks[recovery].finishedAt end
 diagnostic('owner-drained',recovery or trim)
 emit('EVIDENCE',evidence)
 emit('END_STATE',{case=case(),trimProgress=evidence.trimProgress,tailProgress=evidence.tailProgress,
  tailAfterCleanup=evidence.tailAfterCleanup or false,recoveryProgress=evidence.recoveryProgress,
  recoveryPresent=recovery~=nil,expectedRecovery=case()~='new-primary-intent',physical=physical()})
 assert(evidence.trimProgress,'native grooming never reached positive progress')
 assert(evidence.tailProgress,'independent native reader never reached positive progress')
 assert(evidence.recoveryProgress==(case()~='new-primary-intent'),case()=='new-primary-intent'and'new explicit primary intent unexpectedly admitted AUTO generator pickup'or'AUTO generator pickup missing or never reached positive progress; see DIAGNOSTIC and END_STATE')
 assert(evidence.tailAfterCleanup,'reader admitted before exact borrowed razor return/retention boundary; see tail-admitted DIAGNOSTIC')
end
local function verifyReplica()
 local player=getPlayer();local root=player:getInventory();local recovered=case()=='auto-return'or case()=='cancel-active'or case()=='owner-pickup-first'
 if root:getItemById(ids.items.original.id)then return end
 if name()=='client1'and player:getHumanVisual():getBeardModel()~=result.beard then return end
 if name()=='client1'and player:getAlreadyReadPages(ids.items.tail.type)~=ids.total then return end
 if name()=='client1'and recovered or name()=='client2'and case()=='peer-pickup'then
  local output=root:getItemById(result.outputId)
  if not output or player:getPrimaryHandItem()~=output or player:getSecondaryHandItem()~=output then return end
  assert(output:getFullType()=='Base.Generator'and output:getCondition()==73 and not output:isFavorite()
   and math.abs((output:getModData().fuel or 0)-7.5)<.01,'client native recovery output differs')
 elseif name()=='client1'and player:getPrimaryHandItem()~=item(case()=='peer-pickup'and'razor'or'replacement')then return
 elseif name()=='client2'and(player:getPrimaryHandItem()or player:getSecondaryHandItem())then return end
 return true
end
require('QueuePreflight').onGameStart(Events,function()started=true;since=getTimestampMs()end)
require('QueuePreflight').onTick(Events,function()
 if not started or done or not isIngameState()then return end
 local ok,problem=pcall(function()
  local player=getPlayer();if not player or not player:getSquare()or player:isDead()then return end
  if isClient()~=(config.kind=='mp')or isClient()and player:getOnlineID()<0 then return end
  assert(getTimestampMs()-since<180000,'generator recovery timeout '..phase)
  if not ready then
   assert(not player:isTimedActionInstant(),'native durations required')
   assert(not P4TidyUpMeister and not getActivatedMods():contains('P4TidyUpMeister'),'P4 must be absent')
   PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(true)
   -- Normal mod startup must install this consumer; the fixture never installs it.
   assert(Razor.enabled(),'normal mod startup failed to install grooming restoration')
   player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false)
   getCore():setOptionAutoDrink(false);getCore():setOptionPauseOnFocusloss(false)
   if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
   if not traceInstalled then
    local returns=T.ActionQueueGeneratorReturn;local previous=returns and returns.trace
    if returns then
     returns.trace=function(equip,boundary,reason)
      if previous then previous(equip,boundary,reason)end
      if equip and equip.character==getPlayer()and phase=='running'then
       emit('TRACE',{case=case(),stage=tostring(boundary),reason=tostring(reason),type=equip.Type})
      end
     end
    end
    traceInstalled=true
   end
   menu,primaryMenu=ISCharacterScreen.onTrimBeard,ISInventoryPaneContextMenu.OnPrimaryWeapon;methods={}
   for _,class in ipairs({ISInventoryTransferAction,ISEquipWeaponAction,ISTrimBeard,ISReadABook,ISTakeGenerator})do
    local callbacks={};for key,value in pairs(class)do if type(value)=='function'then callbacks[key]=value end end;methods[class]=callbacks
   end
   ready=true
  end
  if not isClient()then A.observe()end
  if phase=='layout'then stage('layout');request('Layout');phase='placement';preparedAt=getTimestampMs();return end
  if phase=='placement'then
   if not layout then if getTimestampMs()-preparedAt>1000 then request('Layout');preparedAt=getTimestampMs()end;return end
   placing=placing or P.beginCentered(player,layout.target);local proof=P.poll(placing);if not proof then return end
   request('Prepare',{target=layout.target,clientPlacement=proof});phase='prepared';return
  end
  if phase=='prepared'then
   if not ids then return end
   if name()=='client1' then
    for key in pairs(ids.items)do if not item(key)then return end end
    if player:getPrimaryHandItem()~=item('original')or player:getSecondaryHandItem()~=item('original')then return end
    if player:getHumanVisual():getBeardModel()~=ids.initialBeard then return end
    item('tail'):setAlreadyReadPages(ids.initialPages);player:setAlreadyReadPages(ids.items.tail.type,ids.initialPages);player:setPerkLevelDebug(Perks.Woodwork,0)
   else
    local square=getCell():getGridSquare(ids.x,ids.y,ids.z);if not square then return end
    local objects=square:getObjects();if ids.decoyIndex>=objects:size()then return end
    local decoy=objects:get(ids.decoyIndex)
    if not instanceof(decoy,'IsoGenerator')or decoy:getCondition()~=41 then return end
    -- Both later pickups target this exact square. Finish normal turning before
    -- the race; its native waitToStart must not consume the intended overlap.
    player:faceThisObject(decoy);if player:shouldBeTurning()then return end
    stage('peer-facing-generator-square')
   end
   stage('prepared-carried-generator');request('Ready');phase='begin';return
  end
  if phase=='begin'then if not go then return end;if name()=='client1'then produce()else phase='peer-wait'end;return end
  if phase=='peer-wait'then
   if not peerGo then return end
   local square=getCell():getGridSquare(peerGo.x,peerGo.y,peerGo.z);if not square then return end
   local objects=square:getObjects();if peerGo.objectIndex>=objects:size()then return end
   target=objects:get(peerGo.objectIndex)
   assert(instanceof(target,'IsoGenerator')and target:getCondition()==73 and math.abs(target:getFuel()-7.5)<.01,'peer target identity differs')
   -- This is the ordinary stock pickup producer, never the AUTO subclass or a direct complete call.
   peerAction=ISTakeGenerator:new(player,target);peerDuration=peerAction.maxTime;assert(peerAction:getDuration()==100 and peerDuration==100,'native peer pickup duration changed')
   stage('normal-peer-ISTakeGenerator');ISTimedActionQueue.add(peerAction);phase='peer-running';return
  end
  if phase=='peer-running'then
   local delta=q().current==peerAction and peerAction:isStarted()and peerAction:getJobDelta()
   if delta and delta>0 and delta<1 and not peerAnnounced then
    peerAnnounced=getTimestampMs();peerDelta=delta
    request('PeerStarted',{at=string.format('%.0f',peerAnnounced),delta=string.format('%.15g',delta)})
   end
   if not empty()then return end
   assert(peerAnnounced,'peer native pickup had no genuine progress');peerFinished=getTimestampMs()
   emit('PEER_PICKUP',{case=case(),type=peerAction.Type,duration=peerDuration,effectiveDuration=peerAction.maxTime,progress=true,native=peerAction.action~=nil,
    normalProducer=true,startedAt=peerAnnounced,finishedAt=peerFinished,progressDelta=peerDelta,outputHeld=player:getPrimaryHandItem()~=nil and player:getPrimaryHandItem()==player:getSecondaryHandItem()})
   phase='receipt';return
  end
  if phase=='running'then
   observeOwner();if not empty()then return end
   stage('owner-drained-verifying-authority');finishEvidence();request('Verify');phase='receipt';return
  end
  if phase=='receipt'then
   if not result then
    if name()=='client1'and getTimestampMs()-(verifyAt or 0)>1000 then verifyAt=getTimestampMs();request('Verify')end
    return
   end
   if not verifyReplica()then return end;stage('authority-output-and-replica-verified')
   if index==#config.cases then done=true;emit('COMPLETE',{cases=config.cases});return end
   if config.clients==2 then request('Observed');phase='advance'else advance=true;phase='advance'end
  end
  if phase=='advance'and advance then
   index=index+1;phase='layout';since=getTimestampMs()
   layout,placing,ids,go,result,peerGo,lastStage,advance=nil,nil,nil,nil,nil,nil,nil,nil
   trimAnnounced,peerRequested,peerAnnounced,peerFinished,verifyAt=nil,nil,nil,nil,nil
   peerAction,target,peerDuration,peerDelta=nil,nil,nil,nil
  end
 end)
 if not ok then fail(problem)end
end)
