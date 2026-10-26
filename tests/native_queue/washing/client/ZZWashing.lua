require 'PZSurvivorToolkit/ActionQueuePanel'
require 'TimedActions/ISReadABook'
require 'ISUI/WMI_WashingSubmenus'
local F=require 'QueueWashingFixture'
local function bodyCase(name)return name=='body-full'or name=='body-water-limited'or name=='body-cancel'end
local Body
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local replayMetadata,replaySourceProof
local needsReplay=false;for _,name in ipairs(config.cases)do if not bodyCase(name)then needsReplay=true end end
if config.kind=='mp'and needsReplay then
 replayMetadata=require 'QueueWashingReplayProof'
 replaySourceProof=require 'PZSurvivorToolkit/SourceProof'
end
local T=PZSurvivorToolkit
local enabled=config.mode=='toolkit'
local phase,step,since,idle='prepare',1,0,0
local started,done=false,false
local ids,state,authorityState,authority,previousAuthority,previousBag,run
local methods={'new','start','perform','complete','stop','getDuration','isValid','onCompleteFunc','onCompleteArgs'}
local function case()return config.cases[step]end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function emit(row)row.suite='washing';row.kind=config.kind;row.mode=config.mode;row.actor='client1';JSON.emit(row)end
local function request(command)
 if isClient()then sendClientCommand('WashingTest',command,{case=case()});return end
 if command=='Prepare'then
  authorityState=F.prepare(getPlayer(),case(),previousAuthority);previousAuthority=nil;ids=authorityState.ids
  print('[WASHING_TEST] PREPARED '..JSON.encode(ids))
 else authority=assert(F.verify(authorityState));print('[WASHING_TEST] VERIFIED '..JSON.encode(authority))end
end
Events.OnServerCommand.Add(function(module,command,value)
 if module~='WashingTest'then return end
 assert(command~='Failed',value.error)
 if command=='Prepared'then ids=value elseif command=='Verified'then authority=value end
end)
local function creationTrace(action)
 local item=action.item;local containing=action.destContainer:getContainingItem()
 local r={itemId=item:getID(),itemKind=item:getFullType(),actorMatches=action.character==getPlayer(),fromRoot=action.srcContainer==state.root,toDeclaredBag=action.destContainer==state.source,
  destinationBagId=containing and containing:getID(),destinationBagType=containing and containing:getFullType(),
  rootPresent=item:getContainer()==state.root and state.root:contains(item),generation=queue().toolkitOperationGeneration or 0,at=getTimestampMs(),
  noCallbacks=not action.onStartFunc and not action.onCompleteFunc and not action.onCancelFunc and not action.onFailFunc and not action.retriggerLastAction,
  onStart=tostring(action.onStartFunc),onComplete=tostring(action.onCompleteFunc),onCancel=tostring(action.onCancelFunc),
  p4SourceVerified=T.ActionQueueCompat.isInstalled('P4TidyUpMeister'),frames={},p4RestoreSite=false,stackAvailable=false}
 if getCurrentCoroutine and getCallframeTop and getCoroutineCallframeStack and getFilenameOfCallframe and getLineNumber then
  r.stackAvailable=true;local coroutine=getCurrentCoroutine();local top=getCallframeTop(coroutine)
  for i=top-1,math.max(0,top-32),-1 do
   local frame=getCoroutineCallframeStack(coroutine,i)
   if frame then
    local file=getFilenameOfCallframe(frame);local line=getLineNumber(frame)
    if file then
     file=tostring(file):gsub('\\','/');r.frames[#r.frames+1]={file=file,line=line}
    end
   end
  end
  -- Current pinned P4/42.20: add838 reports839; caller895 is the same-item branch.
  local restoreFile
  for _,frame in ipairs(r.frames)do
   if frame.file:match('([^/]+)$')=='P4TidyUpMeister.lua'and frame.line==839 then restoreFile=frame.file
   elseif restoreFile and frame.file==restoreFile and frame.line==895 then r.p4RestoreSite=true;break end
  end
  if config.kind=='mp'then
   r.replayProof=run.replayProof;r.compatReplaySite=false
   if r.replayProof and r.replayProof.verified then
    for _,frame in ipairs(r.frames)do
     if frame.file:sub(-#r.replayProof.frameSuffix)==r.replayProof.frameSuffix and frame.line==r.replayProof.replayLine then
      r.compatReplaySite=true;break
     end
    end
   end
  end
 end
 return r
end
local add=ISTimedActionQueue.add
ISTimedActionQueue.add=function(action,...)
 if run and not run.body and(run.reset or run.resetting)and action.Type=='ISInventoryTransferAction'and action.item and run.allowed[action.item:getID()]then
  if run.creationCount<16 then
   run.creationCount=run.creationCount+1
   local ok,value=pcall(creationTrace,action)
   run.creations[action]=ok and value or {error=tostring(value)}
  else run.creationOverflow=true end
 end
 return add(action,...)
end
local function ownedRestore(trace)
 local site=trace and(trace.p4RestoreSite or config.kind=='mp'and trace.compatReplaySite and trace.replayProof and trace.replayProof.verified)
 return trace and trace.stackAvailable and site and trace.p4SourceVerified and trace.actorMatches and trace.fromRoot and trace.toDeclaredBag
  and trace.destinationBagId==ids.bagId and trace.destinationBagType==ids.bagType and trace.rootPresent and trace.noCallbacks
end
local function remember(action)
 if not run or run.body or run.seen[action]then return end
 local item=action.item or action.Type=='WMI_WaitForInvUpdate'and action.wmiTransferAction and action.wmiTransferAction.item
 if not item or not run.allowed[item:getID()]then return end
 if action.Type~='ISWashClothing'and action.Type~='ISInventoryTransferAction'and action.Type~='WMI_WaitForInvUpdate'then return end
 local contract,id=T.ActionQueueDefinitions.inspect(action)
 local r={kind=action.Type,id=item:getID(),duration=action:getDuration(),progress=false,behavior=id,postReset=run.reset or run.resetting or false,
  sourceProof=contract~=nil,begin={perform=0,complete=0,stop=0},finish={perform=0,complete=0,stop=0}}
 if action.Type=='ISInventoryTransferAction'then
  r.pickup=action.destContainer==state.root;r.returned=action.srcContainer==state.root
  r.sourceType=action.srcContainer:getType();r.destinationType=action.destContainer:getType()
 elseif action.Type=='ISWashClothing'then
  r.inputRoot=action.item:getContainer()==state.root and state.root:contains(action.item)
  r.bloodAmount=action.bloodAmount;r.dirtAmount=action.dirtAmount;r.noSoap=action.noSoap
 end
 local saved={};for _,name in ipairs(methods)do saved[name]=action[name]end
 run.seen[action]={row=r,methods=saved};run.records[#run.records+1]=r
 if r.postReset then
  r.creation=run.creations[action];r.ownedRestore=action.Type=='ISInventoryTransferAction'and ownedRestore(r.creation)or false
  if r.ownedRestore then run.ownedCleanupActions=run.ownedCleanupActions+1 else run.lateSourceActions=run.lateSourceActions+1 end
 end
end
assert(T.ActionQueueLifecycle.registerObserver('native-washing-fixture',{
 begin=function(action,nativePhase)
  if not enabled then return end
  remember(action);local entry=run and run.seen[action]
  if entry and entry.row.sourceProof and entry.row.behavior=='compat.wash-clothing'and entry.row.begin[nativePhase]~=nil then
   entry.row.begin[nativePhase]=entry.row.begin[nativePhase]+1
  end
 end,
 finish=function(action,nativePhase,succeeded)
  if not enabled then return end
  local entry=run and run.seen[action]
  if entry and entry.row.sourceProof and entry.row.behavior=='compat.wash-clothing'and entry.row.finish[nativePhase]~=nil then
   entry.row.finish[nativePhase]=entry.row.finish[nativePhase]+1
   if succeeded~=true then entry.row.failedBoundary=true end
  end
 end
}),'washing lifecycle observer registration failed')
local localDefer=T.ActionQueueOperations.deferCompletion
T.ActionQueueOperations.deferCompletion=function(q,action)
 local result=localDefer(q,action)
 if result and run and run.seen[action]then run.localDeferrals=run.localDeferrals+1 end
 return result
end
local function observe()
 for _,action in ipairs(queue().queue)do
  local previous=run.seen[action]
  if run.reset and previous and not previous.row.postReset and not previous.row.revivedAfterReset then
   previous.row.revivedAfterReset=true;run.lateSourceActions=run.lateSourceActions+1
  end
  remember(action)
 end
 local current=queue().current
 for action,entry in pairs(run.seen)do
  if current==action and action:isStarted()and action:getJobDelta()>0 then
   entry.row.progress=true
   if action.Type=='ISInventoryTransferAction'and isClient()and action.transactionId and action.transactionId~=0 then
    local duration=getItemTransactionDuration(action.transactionId)
    if duration>1 then entry.row.transactionDuration=duration end
   end
  end
 end
 if run.originalTail and current==run.originalTail and run.originalTail:isStarted()then run.originalTailStarted=true end
 local tail=run.freshTail or run.originalTail
 if tail and current==tail and tail:isStarted()and tail:getJobDelta()>0 then
  run.tailProgress=true
  if not run.returnsBeforeRead and not F.isCancel(case())then
   local returned=true
   for _,meta in ipairs(ids.garments)do if state.source:getItemById(meta.id)==nil then returned=false end end
   run.returnsBeforeRead=returned
  end
 end
end
local function soapList(value)
 local entries,shape={},type(value)
 if (type(value)=='table'or type(value)=='userdata')and value.size and value.get then
  shape='java-list';for i=0,value:size()-1 do entries[#entries+1]=value:get(i)end
 elseif type(value)=='table'then shape='lua-table';for _,item in ipairs(value)do entries[#entries+1]=item end end
 local r={shape=shape,count=#entries,items={},ownOnly=#entries==1 and entries[1]==state.soap}
 for i,item in ipairs(entries)do
  if i>16 then r.truncated=true;break end
  if instanceof(item,'InventoryItem')then r.items[#r.items+1]={id=item:getID(),kind=item:getFullType(),uses=item:getCurrentUses()}
  else r.items[#r.items+1]={type=type(item)}end
 end
 return r
end
local function menuOption(root,wanted)
 local selected,selectedIndex,selectedOption,selectedSoap
 local tree={case=case(),rows={},truncated=false};local visited={}
 local function walk(menu,path,depth)
  if visited[menu]then return end;visited[menu]=true
  if depth>8 then tree.truncated=true;return end
  for index,option in ipairs(menu.options)do
   if #tree.rows>=64 then tree.truncated=true;return end
   local list=option.param3;local soaps=soapList(option.param2)
   local r={path=path..'/'..tostring(option.name),index=index,callback=tostring(option.onSelect),targetIsActor=option.target==getPlayer(),
    sinkIsDeclared=option.param1==state.sink,soapList=soaps,washListType=type(list),washItems={},arg4Nil=option.param4==nil,
    noSoapType=type(option.param5),noSoap=tostring(option.param5),available=not option.notAvailable and not option.isDisabled}
   local exact=r.targetIsActor and r.sinkIsDeclared and type(list)=='table'and #list==#ids.garments
    and r.arg4Nil and option.param5==F.noSoap(case())and r.available and soaps.ownOnly and type(option.onSelect)=='function'
   if type(list)=='table'then
    local seen={};local count=0
    for key in pairs(list)do if type(key)~='number'or key%1~=0 or key<1 or key>#list then exact=false end;count=count+1 end
    if count~=#list then exact=false end
    for _,item in ipairs(list)do
     if instanceof(item,'InventoryItem')then
      r.washItems[#r.washItems+1]={id=item:getID(),kind=item:getFullType(),inDeclaredBag=item:getContainer()==state.source}
      if not instanceof(item,'Clothing')or not wanted[item:getID()]or seen[item:getID()]or item:getContainer()~=state.source then exact=false end
      seen[item:getID()]=true
     else exact=false;r.washItems[#r.washItems+1]={type=type(item)}end
    end
   end
   r.matches=exact;tree.rows[#tree.rows+1]=r
   if exact and not selected then selected,selectedIndex,selectedOption,selectedSoap=menu,index,option,soaps end
   if option.subOption then walk(menu:getSubMenu(option.subOption),r.path,depth+1)end
  end
 end
 walk(root,'WashFix',0)
 return selected,selectedIndex,selectedOption,tree,selectedSoap
end
local function readTail(player)
 local tail=ISReadABook:new(player,state.book)
 assert(tail.minutesPerPage==2.0 and tail.maxTime>1 and not player:isTimedActionInstant(),'native reader cost changed')
 ISTimedActionQueue.add(tail);return tail
end
local function dispatch(player)
 assert(#queue().queue==0 and not player:hasTimedActions(),'washing menu did not start from native idle')
 local carts=T.ActionQueueCarts;local cartsReady,cartsReason,transferConstructor
 if carts and carts.status then cartsReady,cartsReason=carts.status()end
 if carts and carts.isTransferConstructor then transferConstructor=carts.isTransferConstructor(ISInventoryTransferAction.new)end
 print('[WASHING_TEST] PREFLIGHT '..JSON.encode({case=case(),queueEnabled=T.Settings.actionQueue(),
  washSourceVerified=T.ActionQueueCompat.isInstalled('WashFix'),p4SourceVerified=T.ActionQueueCompat.isInstalled('P4TidyUpMeister'),
  cartsPresent=carts~=nil,cartsReady=cartsReady,cartsReason=cartsReason,transferConstructor=transferConstructor}))
 assert(T.Settings.actionQueue()==enabled and T.ActionQueueCompat.isInstalled('WashFix'),'washing source/setting proof missing')
 assert(player:getClothingItem_Back()==state.bag,'washing bag is not genuinely worn')
 run={seen={},records={},allowed={},creations={},creationCount=0,creationOverflow=false,ownedCleanupActions=0,
  localDeferrals=0,lateSourceActions=0,tailProgress=false,returnsBeforeRead=false,
  originalTailStarted=false,reset=false}
 if config.kind=='mp'then
  run.replayProof={};for k,v in pairs(replayMetadata)do run.replayProof[k]=v end
  run.replayProof.verified=replaySourceProof.matches(replayMetadata.path,replayMetadata.checksum,replayMetadata.mod,true)
  assert(run.replayProof.verified,'staged washing MP replay source no longer matches selected Toolkit')
 end
 for _,meta in ipairs(ids.garments)do run.allowed[meta.id]=true end
 local menu=ISContextMenu.get(player:getPlayerNum(),20,20)
 WS.WMI_BuildWashMenu(menu,{state.sink},player,state.sink,menu)
 local selected,index,option,tree,soaps=menuOption(menu,run.allowed)
 print('[WASHING_TEST] MENU_TREE '..JSON.encode(tree))
 assert(selected,'real flat WashFix clothing menu option missing; expectedNoSoap='..tostring(F.noSoap(case()))..' tree='..JSON.encode(tree))
 run.menu={method='WS.WMI_BuildWashMenu+ISContextMenu.onMouseUp',callback=tostring(option.onSelect),
  exactArguments=true,noSoap=option.param5,requested=#ids.garments,bagWorn=true,inputIds={},soapId=state.soap:getID(),soapUses=state.soap:getCurrentUses(),soapList=soaps,
  choice=F.noSoap(case())and 'bag-aggregate'or 'bag-individual'}
 for _,item in ipairs(option.param3)do run.menu.inputIds[#run.menu.inputIds+1]=item:getID()end
 selected:setVisible(true);selected.mouseOver=index;selected:onMouseUp(0,0)
 observe();run.originalTail=readTail(player)
 local token=run.originalTail.toolkitQueueOperation
 run.tailIndependent=true
 if enabled then
  assert(type(token)=='table','original reader has no independent operation')
  for action in pairs(run.seen)do assert(action.toolkitQueueOperation~=token,'original reader grouped with washing')end
 end
end
local function cancelAfterPickup(player)
 if not F.isCancel(case())or run.reset then return end
 local current=queue().current
 if not current or current.Type~='ISWashClothing'or not current:isStarted()or current:getJobDelta()<=0 then return end
 local progress=current:getJobDelta();assert(progress<.25,'native washing cancellation missed early progress')
 local item=assert(state.root:getItemById(ids.garments[1].id));assert(item==current.item and item:getContainer()==state.root,'wash cancellation preceded real pickup')
 assert(queue():indexOf(run.originalTail)~=-1 and not run.originalTail:isStarted(),'original reader was not waiting at reset')
 local generation=queue().toolkitOperationGeneration or 0;local oldToken=current.toolkitQueueOperation;local oldTailToken=run.originalTail.toolkitQueueOperation
 run.resetting=true;ISTimedActionQueue.clear(player);run.resetting=false
 run.reset=true;run.resetAt=getTimestampMs();run.resetProof={method='ISTimedActionQueue.clear',id=item:getID(),rootObserved=true,progress=progress,
  beforeGeneration=generation,afterGeneration=queue().toolkitOperationGeneration or 0,oldTailRemoved=queue():indexOf(run.originalTail)==-1}
 assert(run.resetProof.oldTailRemoved,'native clear retained the old reader')
 run.freshTail=readTail(player)
 run.resetProof.freshGeneration=queue().toolkitOperationGeneration or 0
 local freshToken=run.freshTail.toolkitQueueOperation
 run.resetProof.freshIndependent=not enabled or type(freshToken)=='table'and freshToken~=oldToken and freshToken~=oldTailToken
end
local function advance()
 if step==#config.cases then
  emit({event='complete',cases=config.cases,expected=#config.cases,performed=#config.cases,failed=0,skipped=0})
  print('[WASHING_TEST] COMPLETE');done=true;return
 end
 previousAuthority=authorityState;previousBag=state.bag
 if previousBag then ISInventoryPaneContextMenu.onUnEquip({previousBag},getPlayer():getPlayerNum())end
 step=step+1;phase=previousBag and 'unequip'or 'prepare';since=getTimestampMs();idle=0
 ids,state,authorityState,authority,run=nil,nil,nil,nil,nil
end
local function finish()
 if run.body then emit(Body.finish(run,authority,F));advance();return end
 observe();local unchanged=true;local waits=0
 for action,entry in pairs(run.seen)do
  if entry.row.kind=='WMI_WaitForInvUpdate'then waits=waits+1 end
  if enabled and action.toolkitQueueOperation==run.originalTail.toolkitQueueOperation then run.tailIndependent=false end
  entry.row.methodsUnchanged=true
  for _,name in ipairs(methods)do if action[name]~=entry.methods[name]then unchanged=false;entry.row.methodsUnchanged=false end end
 end
 local row={event='case',id=case(),status='passed',menu=run.menu,sourceMethodsUnchanged=unchanged,records=run.records,tailIndependent=run.tailIndependent,
  localDeferrals=run.localDeferrals,tailProgress=run.tailProgress,returnsBeforeRead=run.returnsBeforeRead,
  originalTailStarted=run.originalTailStarted,reset=run.reset,resetProof=run.resetProof,lateSourceActions=run.lateSourceActions,
  lateObservedMs=run.resetAt and getTimestampMs()-run.resetAt or 0,waitsObserved=waits,ownedCleanupActions=run.ownedCleanupActions,creationOverflow=run.creationOverflow}
 if config.kind=='mp'then row.replayProof=run.replayProof end
 row.actualResources=assert(F.verify({player=getPlayer(),root=state.root,sink=state.sink,case=case(),ids=ids}))
 for k,v in pairs(authority)do if k~='case'then row[k]=v end end
 emit(row)
 advance()
end
Events.OnGameStart.Add(function()
 started=true;since=getTimestampMs();getCore():setOptionPauseOnFocusloss(false)
 if not isClient()then getPlayer():setGhostMode(true)end
end)
Events.OnPlayerUpdate.Add(function(player)
 if started and player==getPlayer()then idle=#queue().queue==0 and not player:hasTimedActions()and idle+1 or 0 end
end)
Events.OnTick.Add(function()
 if not started or done or not isIngameState()then return end
 local ok,problem=pcall(function()
  assert(getTimestampMs()-since<180000,'washing native deadline: '..phase)
  local player=getPlayer();if not player or player:isDead()or not player:getSquare()then return end
  if config.kind=='mp'and(not isClient()or player:getOnlineID()<0)then return end
  if phase=='unequip'then
   if idle<10 or #queue().queue>0 or player:hasTimedActions()then return end
   assert(not player:isEquipped(previousBag));previousBag=nil;phase='prepare';return
  elseif phase=='prepare'then
   if step==1 then emit({event='setup',cases=config.cases,expected=#config.cases,queueEnabled=enabled,nativeDurations=true})end
   request('Prepare');phase='ready';return
  elseif phase=='ready'then
   if not ids then return end;state=state or F.resolve(player,ids);if not state then return end
   if not bodyCase(case())then ISInventoryPaneContextMenu.onWearItems({state.bag},player:getPlayerNum())end
   phase='equip';return
  elseif phase=='equip'then
   if idle<10 or #queue().queue>0 or player:hasTimedActions()then return end
   if bodyCase(case())then Body=Body or require 'QueueWashingBody';run=Body.start(player,state,ids,enabled)else dispatch(player)end
   phase='running';since=getTimestampMs();idle=0;return
  elseif phase=='running'then
   if run.body then Body.tick(run)else observe();cancelAfterPickup(player)end
   if idle>=10 and #queue().queue==0 and not player:hasTimedActions()then
    assert(not(F.isCancel(case())or case()=='body-cancel')or run.reset,'washing reset was never exercised')
    if run.resetAt and getTimestampMs()-run.resetAt<3000 then return end
    request('Verify');phase='receipt';return
   end
  elseif phase=='receipt'and authority then finish()end
 end)
 if not ok then print('[QUEUE_TEST] FAIL washing '..tostring(problem));done=true end
end)
