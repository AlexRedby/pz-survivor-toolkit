require 'PZSurvivorToolkit/ActionQueuePanel'
require 'ISUI/ISMakeUpUI'
require 'TimedActions/ISReadABook'
require 'TimedActions/ISApplyMakeUp'
require 'TimedActions/ISWearClothing'
require 'TimedActions/ISEquipWeaponAction'
require 'TimedActions/WalkToTimedAction'
local F=require 'QueueMakeup';local JSON=require 'QueueHealthEvents';local config=require 'QueueTestSelection'
local moves=config.options and(config.options.makeup_moves==true or config.options.makeup_carried_moves==true or config.options.makeup_world_moves==true or config.options.makeup_depletion_moves==true or config.options.makeup_held_moves==true)
local Proof=require 'PZSurvivorToolkit/SourceProof';local T=PZSurvivorToolkit;local native=config.mode=='native'
local entered,ready,done=false,false,false
local phase,index,since='prepare',1,0
local state,ids,previous,ui,front,tail,body,submitted,second,beforeTail,edit,verified,pending,authority
local checkpoints,sequence,outcomes,renderWitness,renderLabel,renderNext,bodyQuiet,finalQuiet
local bodyRecord,applyQueues,transferStarts,submitting,placement
local M={}
if config.options and config.options.makeup_held_moves==true then
 M.dropBinding=require 'QueueMakeupDropBinding';M.dropMatches=M.dropBinding.matches
 assert(M.dropBinding.start(),'reviewed force-drop factory was unavailable before installation')
end
function M.forceDropMatches(callback)
 if M.dropBinding then return M.dropBinding.matches==M.dropMatches and M.dropMatches(callback)end
 return Proof.closure(callback,'ISEquipWeaponAction.lua')
end
function M.kind()return F.moveKind(config.cases[index])end
function M.name(action)
 if M.walkActions then for name,walk in pairs(M.walkActions)do if action==walk then return 'walk-'..name end end end
 if action==body then return 'body'end
 if action==M.writer then return 'writer'end
 if action and action.Type=='ISReadABook'and ids then
  for _,name in ipairs({'front','middle','tail'})do if action.item and action.item:getID()==ids.items[name]then return name end end
 end
 return action and action.Type or false
end
function M.order()local names={};for _,action in ipairs(ISTimedActionQueue.getTimedActionQueue(getPlayer()).queue)do names[#names+1]=M.name(action)end;return names end
function M.walkPart(action)
 if M.walkActions then for name,walk in pairs(M.walkActions)do if action==walk then return M.walkRecord[name]end end end
end
function M.walkWitness(label)
 local kit=assert(F.kit(state));local _,source=F.supplyState(state.player,ids.supply)
 local row={at=getTimestampMs(),placement=F.placement(state.player),source=assert(source),
  kit={id=kit:getID(),kind=kit:getFullType(),uses=kit:getCurrentUses(),maxUses=kit:getMaxUses(),root=false}}
 M.walkRecord[label]=row
 print('[MAKEUP_TEST] WALK '..JSON.encode({case=ids.case,label=label,evidence=row}))
end
function M.observeWalks()
 if not M.walkActions then return end
 for name,action in pairs(M.walkActions)do
  local row=M.walkRecord[name]
  local native=M.walkNatives[action]
  if row.starts==1 and action.action then
   assert(not native or native==action.action,'native walk allocation changed');native=action.action;M.walkNatives[action]=native
   local reference=tostring(native)
   assert(not row.nativeRef or row.nativeRef==reference,'native walk allocation changed')
   row.nativeRef=reference
  end
  if row.starts==1 and row.dequeues==0 and ISTimedActionQueue.getTimedActionQueue(state.player):indexOf(action)==-1
   and native and not state.player:getCharacterActions():contains(native)then
   assert(row.nativeRef,'native walk dequeued without allocation');row.dequeues=1;row.dequeuedAt=getTimestampMs()
  end
 end
end
-- Independent fixture seal: Policy's installed snapshots are useful instance
-- bindings, but do not establish native provenance for a preexisting replacement.
function M.captureEquip()
 assert(Proof.matches('media/lua/shared/TimedActions/ISEquipWeaponAction.lua',4117952124,nil,true)
  and Proof.matches('media/lua/shared/TimedActions/ISBaseTimedAction.lua',3104185167,nil,true)
  and Proof.matches('media/lua/shared/ISBaseObject.lua',3350606722,nil,true),'native Hammer writer source changed')
 local saved={owner=ISEquipWeaponAction,base=ISBaseTimedAction,object=ISBaseObject,queue=T.ActionQueue,dispatch={},globals={}}
 assert(type(saved.queue)=='table','native Hammer writer queue owner missing')
 local ownNames={'new','isValid','update','start','animEvent','stop','isAlreadyEquipped','perform','complete'}
 local baseNames={'isValidStart','isValid','isUsingTimeout','update','forceComplete','forceStop','forceCancel','getJobDelta','setJobDelta',
  'resetJobDelta','waitToStart','interruptWaitToStart','start','isStarted','stop','perform','getDuration','create','begin','setCurrentTime','setTime',
  'adjustMaxTime','setActionAnim','setOverrideHandModels','setOverrideHandModelsString','overrideWeaponType','restoreWeaponType','setAnimVariable',
  'addAfter','beginAddingActions','endAddingActions','getDeltaModifiers','new'}
 local objectNames={'initialise','derive','new','instanceof','addEventListener','removeEventListener','triggerEvent','clearEventListeners'}
 local function capture(owner,names,filename,queueHooks)
  assert(type(owner)=='table','native Hammer writer owner missing');local out={}
  for _,name in ipairs(names)do
   local callback=Proof.own(owner,name)
   assert(type(callback)=='function'and(Proof.closure(callback,filename)
    or queueHooks and(name=='begin'or name=='stop')and Proof.closure(callback,'ActionQueue.lua')),'native Hammer writer method source changed '..name)
   out[name]=callback;saved.dispatch[name]=saved.owner[name]
  end;return out
 end
 saved.objectMethods=capture(saved.object,objectNames,'ISBaseObject.lua',false)
 saved.baseMethods=capture(saved.base,baseNames,'ISBaseTimedAction.lua',true)
 saved.ownMethods=capture(saved.owner,ownNames,'ISEquipWeaponAction.lua',false)
 for _,name in ipairs({'forceDropHeavyItems','isForceDropHeavyItem'})do
  assert(type(_G[name])=='function'and(name=='forceDropHeavyItems'and M.forceDropMatches(_G[name])or name~='forceDropHeavyItems'and Proof.closure(_G[name],'ISEquipWeaponAction.lua')),'native Hammer writer helper source changed '..name)
  saved.globals[name]=_G[name]
 end
 M.equipSeal=saved;M.assertEquip()
end
function M.assertEquip(action)
 local saved=assert(M.equipSeal,'native Hammer writer seal missing')
 assert(ISEquipWeaponAction==saved.owner and ISBaseTimedAction==saved.base and ISBaseObject==saved.object and T.ActionQueue==saved.queue
  and saved.owner.Type=='ISEquipWeaponAction'and getmetatable(saved.owner)==saved.base and Proof.own(saved.owner,'SuperType')==saved.base
  and getmetatable(saved.base)==saved.object,'native Hammer writer class changed')
 local function unchanged(owner,methods,filename,queueHooks)
  for name,callback in pairs(methods)do
   assert(Proof.own(owner,name)==callback and(Proof.closure(callback,filename)
    or queueHooks and(name=='begin'or name=='stop')and Proof.closure(callback,'ActionQueue.lua')),'native Hammer writer method changed '..name)
  end
  for name,callback in pairs(owner)do
   if type(callback)=='function'then assert(methods[name]==callback,'native Hammer writer extra method '..name)end
  end
 end
 unchanged(saved.object,saved.objectMethods,'ISBaseObject.lua',false)
 unchanged(saved.base,saved.baseMethods,'ISBaseTimedAction.lua',true)
 unchanged(saved.owner,saved.ownMethods,'ISEquipWeaponAction.lua',false)
 for name,callback in pairs(saved.globals)do assert(_G[name]==callback and(name=='forceDropHeavyItems'and M.forceDropMatches(callback)or name~='forceDropHeavyItems'and Proof.closure(callback,'ISEquipWeaponAction.lua')),'native Hammer writer helper changed '..name)end
 for name,callback in pairs(saved.dispatch)do assert(saved.owner[name]==callback,'native Hammer writer dispatch changed '..name)end
 if not action then return end
 assert(getmetatable(action)==saved.owner and action.Type==saved.owner.Type and Proof.own(saved.owner,'__index')==saved.owner
  and action.character==state.player and action.item==state.player:getInventory():getItemById(ids.items.hammer)
  and action.primary==true and action.twoHands==false,'native Hammer writer instance changed')
 for name,callback in pairs(saved.dispatch)do assert(action[name]==callback,'native Hammer writer instance dispatch changed '..name)end
 for name,callback in pairs(action)do
  if type(callback)=='function'then assert(saved.dispatch[name]==callback,'native Hammer writer injected function '..name)end
 end
 for _,name in ipairs({'onStartFunc','onCancelFunc','onCompleteFunc','onFailFunc','retriggerLastAction','additionalTest','additionalContext'})do
  assert(action[name]==nil or action[name]==false,'native Hammer writer injected callback '..name)
 end
end
local previewShotFrames,previewShotSince,previewShotTaken=0,nil,false
local uiMethods,bodyMethods={},{}
local observerFailure
local function now()return getTimestampMs()end
local function case()return config.cases[index]end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function empty()return #queue().queue==0 and not getPlayer():hasTimedActions()end
local function snapshot(transition)return F.snapshot(state,transition)end
local function raw(marker,row)print('[MAKEUP_TEST] '..marker..' '..JSON.encode(row))end
local function emit(row)row.suite,row.kind,row.mode,row.actor='makeup',config.kind,config.mode,'client1';JSON.emit(row)end
local function preview()
 local item=ui and ui.makeUpSelected
 return item and {id=item:getID(),kind=item:getFullType(),slot=tostring(item:getBodyLocation()),root=item:getContainer()~=nil,
  previous=ui.previousMakeUp and ui.previousMakeUp:getID()or false}or false
end
local function intact()
 if M.equipSeal then M.assertEquip(M.equipWriter and M.writer or nil)end
 if M.walkMethods then
  for name,callback in pairs(M.walkMethods)do assert(ISWalkToTimedAction[name]==callback,'native walk callback replaced '..name)end
  assert(Proof.closure(ISWalkToTimedAction.new,'WalkToTimedAction.lua'),'native walk constructor source changed')
 end
 assert(not observerFailure,'native makeup observer failed '..tostring(observerFailure))
 for name,callback in pairs(uiMethods)do assert(ISMakeUpUI[name]==callback,'makeup UI callback replaced '..name)end
 for name,callback in pairs(bodyMethods)do assert(ISApplyMakeUp[name]==callback,'native makeup body callback replaced '..name)end
 assert(Proof.closure(ISApplyMakeUp.complete,'ISApplyMakeUp.lua')and Proof.closure(ISApplyMakeUp.new,'ISApplyMakeUp.lua'),'native makeup executor source changed')
end
local function observe(callback)
 return function(...)
  local ok,result=pcall(callback,...)
  if not ok then observerFailure=tostring(result);return false end
  return result
 end
end
local function command(name,args)
 args=args or{};args.case=case()
 if isClient()then sendClientCommand('MakeupTest',name,args);return end
 if name=='Prepare'then
  if config.options and (config.options.makeup_supplies==true or moves) then assert(F.same(args.placement,placement)and F.atPlacement(getPlayer(),placement),'SP makeup supply placement is not settled')end
  state=F.prepare(getPlayer(),case(),previous,args.placement);ids=state.ids;raw('PREPARED',ids)
 elseif name=='Snapshot'then
  authority={case=case(),label=args.label,sequence=args.sequence,at=now(),snapshot=snapshot()};raw('SNAPSHOT',authority)
 elseif name=='Finish'then verified={case=case(),sequence=sequence,snapshot=snapshot()};raw('VERIFIED',verified)end
end
local function checkpoint(label,nextPhase)
 sequence=sequence+1
 pending={case=case(),label=label,sequence=sequence,at=now(),snapshot=snapshot(),preview=preview(),render=renderWitness or false,
  bodyUnallocated=not body or body.action==nil,edit=edit or false}
 renderWitness=nil;authority=nil
 raw('CLIENT_SNAPSHOT',pending);phase='checkpoint';pending.nextPhase=nextPhase
 -- nextPhase is local control state and deliberately excluded from published evidence.
 command('Snapshot',{label=label,sequence=sequence})
end
local function close()
 assert(ui,'real makeup window missing');ui:close()
 assert(ISMakeUpUI.windows[state.player:getPlayerNum()+1]==nil,'makeup window close did not unregister')
end
local function chooseLocation(kind)
 local definition=F.definition(kind);local found
 for i,option in ipairs(ui.location.options)do if option.data and option.data.category==definition.category then found=i end end
 assert(found,'native makeup category not offered');ui.location.selected=found;ui:onSelectLocation()
end
local function choose(kind,locationReady)
 if not locationReady then chooseLocation(kind)end
 local found
 for i,option in ipairs(ui.comboMakeup.options)do if option.data and option.data.item==kind then found=i end end
 assert(found,'native makeup target not offered');ui.comboMakeup.selected=found;ui:onSelectMakeUp()
 local current=assert(preview(),'native selector made no preview')
 assert(current.kind==kind and not current.root and ui.character==state.player,'selected cosmetic escaped avatar ownership')
 return current
end
local function rendered(label,nextPhase)
 previewShotFrames,previewShotSince=0,nil
 renderLabel,renderNext=label,nextPhase;phase='render'
end
local function open()
 assert(not ISMakeUpUI.windows[state.player:getPlayerNum()+1],'previous native makeup window remains')
 ISInventoryPaneContextMenu.onMakeUp(assert(F.kit(state)),state.player)
 ui=assert(ISMakeUpUI.windows[state.player:getPlayerNum()+1],'native inventory producer made no real makeup UI')
 assert(ui.avatarPanel and ui.avatarPanel.javaObject and getClassSimpleName(ui.avatarPanel.javaObject)=='UI3DModel','native avatar renderer unavailable')
 submitted=choose(ids.target);rendered('preview','after-preview')
end
local function addTail()
 assert(not tail,'independent tail duplicated');tail=ISReadABook:new(state.player,state.player:getInventory():getItemById(ids.items.tail));ISTimedActionQueue.add(tail)
end
local function queueSnapshot()
 local types={};for _,action in ipairs(queue().queue)do types[#types+1]=action.Type end
 return {types=types,hasTimedActions=state.player:hasTimedActions(),nativeActions=state.player:getCharacterActions():size()}
end
local function apply()
 if ids.supply and not moves then
  applyQueues={before=queueSnapshot()}
  assert(empty()and applyQueues.before.nativeActions==0,'supply native application did not start with empty queue')
 end
 if isClient()and(moves or not ids.supply or F.cancel(case()))then
  front=ISReadABook:new(state.player,state.player:getInventory():getItemById(ids.items.front));ISTimedActionQueue.add(front)
 end
 if moves then
  M.middle=ISReadABook:new(state.player,state.player:getInventory():getItemById(ids.items.middle))
  if M.kind()~='later'and M.kind()~='deny-writer'and M.kind()~='deny-walk'and M.kind()~='deny-equip'then ISTimedActionQueue.add(M.middle)end
  if M.kind()=='deny-writer'then M.writer=ISWearClothing:new(state.player,state.player:getInventory():getItemById(ids.items.writer));ISTimedActionQueue.add(M.writer)end
  if M.kind()=='deny-equip'then
   local hammer=assert(state.player:getInventory():getItemById(ids.items.hammer))
   M.assertEquip()
   M.writer=ISEquipWeaponAction:new(state.player,hammer,50,true,false)
   M.assertEquip(M.writer)
   assert(M.writer.item==hammer and M.writer.primary==true and M.writer.twoHands==false,'native Hammer equip constructor changed')
   M.equipWriter={item=hammer:getID(),primary=true,twoHands=false,duration=M.writer.maxTime,starts=0,nativeRef=false,finishes={}}
   ISTimedActionQueue.add(M.writer)
  end
 end
 if isClient()then bodyRecord={duration=1,starts=0,finishes={},nativeRef=false}end
 submitting=true;ui:onApplyMakeUp();submitting=false
 if ids.supply and not moves then applyQueues.after=queueSnapshot();raw('APPLY_QUEUES',{case=case(),evidence=applyQueues})end
 if isClient()then
  for _,action in ipairs(queue().queue)do
   if action.Type=='ISApplyMakeUp'then assert(not body or body==action,'duplicate native makeup action');body=action end
  end
  assert(body and body.maxTime==1 and body.item:getID()==ids.items.kit and body.type==ids.target,'native makeup constructor/duration changed')
  local contract,adapter=T.ActionQueuePolicy.inspect(body)
  assert(contract and adapter=='native.ISApplyMakeUp'and contract.cancelWaiting==(not native and body.action==nil),'native makeup producer receipt/allocation differs')
  if moves and M.kind()=='deny-walk'then
   assert(ids.walk and F.atPlacement(state.player,ids.walk.origin),'world makeup walk origin changed')
   local function square(tile)
    local found=assert(getCell():getGridSquare(tile.x,tile.y,tile.z),'native makeup walk square unavailable')
    return found
   end
   M.walkActions={out=ISWalkToTimedAction:new(state.player,square(ids.walk.out)),back=ISWalkToTimedAction:new(state.player,square(ids.walk.origin))}
   M.walkNatives={};M.walkRecord={out={duration=-1,starts=0,dequeues=0,nativeRef=false,finishes={}},back={duration=-1,starts=0,dequeues=0,nativeRef=false,finishes={}}}
   for _,name in ipairs({'out','back'})do
    local action=M.walkActions[name];assert(action.maxTime==-1 and not action.onCompleteFunc and action.additionalTest==nil and action.additionalContext==nil,'native walk constructor/duration/callback changed');ISTimedActionQueue.add(action)
   end
   assert(M.walkActions.out.toolkitQueueOperation~=M.walkActions.back.toolkitQueueOperation,'native walk directions share an operation token')
  end
  if moves and(M.kind()=='later'or M.kind()=='deny-writer'or M.kind()=='deny-walk'or M.kind()=='deny-equip')then ISTimedActionQueue.add(M.middle)end
  addTail()
  if moves then close();phase='move-front';return end
  if case()=='apply-while-preview'then second=choose(ids.alternate);rendered('overlap-preview','wait-body')
  else close();phase=F.cancel(case())and'wait-front'or'wait-body'end
 else
  for _,action in ipairs(queue().queue)do assert(action.Type~='ISApplyMakeUp','SP immediate UI emitted timed makeup')end
  close();checkpoint('after-body','tail')
 end
end
local function completed()
 if not body then return false end
 for _,row in ipairs(outcomes)do if row.state=='completed'then return true end end
 return false
end
local function afterBody()
 if ids.walk and(queue():indexOf(M.walkActions.out)~=-1 or queue():indexOf(M.walkActions.back)~=-1
  or M.walkRecord.out.dequeues~=1 or M.walkRecord.back.dequeues~=1 or not M.walkRecord.returnedOrigin
  or not F.atPlacement(state.player,ids.walk.origin))then bodyQuiet=nil;return end
 if not empty()and queue():indexOf(body)~=-1 then bodyQuiet=nil;return end
 local cancelled=F.cancel(case())and not native
 if not cancelled then
  if not completed()then return end
  if ids.depletion then if not F.depletionReady(state)then return end
  elseif snapshot().kit.uses~=ids.kitUses-1 or not F.handsReady(state,true)then return end
 end
 bodyQuiet=bodyQuiet or now();if now()-bodyQuiet<750 then return end
 checkpoint('after-body',case()=='apply-while-preview'and'close-overlap'or'final-drain')
end
Events.OnPostUIDraw.Add(function()
 if done or phase~='render'or not ui then return end
 local ok,problem=pcall(function()
  assert(ui.character==state.player,'makeup preview actor changed')
  -- Production deliberately leaves Apply disabled while an async cosmetic asset loads.
  -- Keep the same render phase and existing case timeout; unsupported/failed rendering
  -- cannot become a pass just because we waited.
  if not ui.add.enable then previewShotFrames,previewShotSince=0,nil;return end
  local item=assert(ui.makeUpSelected);local before=snapshot();local accepted=true
  if not native then
   -- Observe the real bridge on the native model after its normal prerender.
   -- Reset only the UI avatar first so this observation does not stack overlays.
   ui.avatarPanel:setCharacter(state.player)
   accepted=toolkitMakeupAvatarPreview(ui.avatarPanel.javaObject,state.player,item)==true
  end
  local after=snapshot();assert(F.same(before,after),'avatar renderer changed actual actor/supply state')
  assert(accepted,'actual native avatar bridge rejected isolated preview')
  -- The probe observes the real native AnimatedModel in BOTH modes. A bridge
  -- return alone proves only overlay admission, not submitted pixels/ready textures.
  if UIManager.getFadeAlpha()>.001 or UIManager.getFadeAlpha(0)>.001
   or not makeupAvatarRendered(ui.avatarPanel.javaObject)then previewShotFrames,previewShotSince=0,nil;return end
  previewShotSince=previewShotSince or now();previewShotFrames=previewShotFrames+1
  local stableMs=now()-previewShotSince
  if previewShotFrames<3 or stableMs<500 then return end
  if case()==config.cases[1]and not previewShotTaken then
   local filename='makeup-preview-'..config.kind..'-'..config.mode..'.png'
   getCore():TakeFullScreenshot(filename);previewShotTaken=true
   raw('SCREENSHOT',{case=case(),file=filename,renderFrames=previewShotFrames,renderMs=stableMs,fadeClear=true,nativeRendered=true})
  end
  renderWitness={ok=true,actorUnchanged=true,selected=item:getID(),uiType='UI3DModel',source=native and'native-worn'or'toolkitMakeupAvatarPreview',
   nativeRendered=true,stableFrames=previewShotFrames,stableMs=stableMs}
 end)
 if not ok then raw('RENDER_FAILURE',{case=case(),error=tostring(problem)});print('[QUEUE_TEST] FAIL makeup '..tostring(problem));done=true end
end)
Events.OnServerCommand.Add(function(module,name,args)
 if module=='PZSurvivorToolkitActions'and name=='State'and body and ids and args.player==ids.actor and args.kind=='ISApplyMakeUp'then
  local row={protocol=args.protocol,player=args.player,transaction=args.transaction,kind=args.kind,token=args.token,state=args.state}
  outcomes[#outcomes+1]=row;raw('OUTCOME',{case=case(),receipt=row});return
 end
 if module~='MakeupTest'or done then return end
 if name=='Prepared'then ids=args
 elseif name=='WornPrepared'then ids=args;state=nil;M.wearReady=true;phase='prepared'
 elseif name=='Snapshot'then authority=args
 elseif name=='Verified'then verified=args
 elseif name=='Failed'then print('[QUEUE_TEST] FAIL makeup authority '..tostring(args.error));done=true end
end)
Events.OnGameStart.Add(function()entered=true;since=now()end)
Events.OnTick.Add(function()
 if not entered or done then return end
 local ok,problem=pcall(function()
  local player=getPlayer();if not isIngameState()or not player or not player:getCurrentSquare()then return end
  if not ready then
   if isClient()~=(config.kind=='mp')or isClient()and player:getUsername()~='client1'then return end
   PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(not native)
   assert(T.ActionQueueMakeup.installUI()and toolkitMakeupAvatarPreviewSupported(),'isolated makeup UI/renderer source support unavailable')
   assert(type(makeupAvatarCaptureSupported)=='function'and makeupAvatarCaptureSupported()
    and type(makeupAvatarRendered)=='function','test-only native avatar capture probe unavailable')
   for _,name in ipairs({'onSelectMakeUp','onSelectLocation','onApplyMakeUp','prerender','reinit','close'})do uiMethods[name]=ISMakeUpUI[name]end
   for _,name in ipairs({'new','isValid','start','update','stop','perform','complete','getDuration'})do bodyMethods[name]=ISApplyMakeUp[name]end
   if config.options and config.options.makeup_held_moves==true then M.captureEquip()end
   if config.options and config.options.makeup_world_moves==true then
    M.walkMethods={};for _,name in ipairs({'new','isValid','start','update','stop','perform'})do M.walkMethods[name]=ISWalkToTimedAction[name]end
   end
   assert(T.ActionQueueLifecycle.registerObserver('fixture.makeup',{
    started=observe(function(action)
     if moves then
      local name=M.name(action);M.startOrder[#M.startOrder+1]=name
      local walk=M.walkPart(action)
      if walk then walk.starts=walk.starts+1;assert(walk.starts==1,'native walk started twice')end
      if name=='walk-back'then
       assert(F.atPlacement(state.player,ids.walk.out)and queue():indexOf(M.walkActions.out)==-1,'native outbound walk did not reach its exact endpoint')
       M.walkWitness('outEndpoint')
      elseif name=='middle'and ids.walk then
       assert(F.atPlacement(state.player,ids.walk.origin)and queue():indexOf(M.walkActions.out)==-1 and queue():indexOf(M.walkActions.back)==-1,'native return walk did not restore the exact origin')
       M.walkWitness('returnedOrigin')
      end
      if name=='front'then
       local pages=state.player:getAlreadyReadPages(ids.types.front)
       if M.readerResume then assert(pages>=M.readerResume.pages,'promoted native reader lost checkpoint pages');M.readerResume.resumedPages=pages;M.resumedAction=action end
      end
     end
     if submitting and ids.supply and action.Type=='ISApplyMakeUp'then
      assert(not body and action.item==F.kit(state)and action.type==ids.target,'unexpected native supply body began');body=action
     end
     if ids and(ids.supply or moves)and action.Type=='ISInventoryTransferAction'then transferStarts=transferStarts+1 end
     if action==M.writer and M.equipWriter then M.equipWriter.starts=M.equipWriter.starts+1;assert(M.equipWriter.starts==1,'native Hammer writer started twice')end
     if action==body then bodyRecord.starts=bodyRecord.starts+1;assert(bodyRecord.starts==1,'native makeup started twice')end
     if action==tail then assert(not beforeTail,'tail began twice');beforeTail={at=now(),snapshot=snapshot(ids.depletion==true)};raw('BEFORE_TAIL',{case=case(),evidence=beforeTail})end
    end),
    begin=observe(function(action,step)
     local walk=M.walkPart(action);if walk then
      assert(action.action,'native walk completion has no allocated action');M.walkNatives[action]=action.action;walk.nativeRef=tostring(action.action);return step=='perform'
     end
     if action==M.writer and M.equipWriter then M.equipWriter.nativeRef=tostring(action.action);return step=='perform'end
     if action~=body then return false end
     bodyRecord.nativeRef=tostring(action.action);return step=='perform'or step=='complete'
    end),
    finish=observe(function(action,step,succeeded)
     local walk=M.walkPart(action);if walk then walk.finishes[#walk.finishes+1]={phase=step,succeeded=succeeded==true,at=now()}end
     if action==M.writer and M.equipWriter then M.equipWriter.finishes[#M.equipWriter.finishes+1]={phase=step,succeeded=succeeded==true,at=now()}end
     if action==body then bodyRecord.finishes[#bodyRecord.finishes+1]={phase=step,succeeded=succeeded==true,at=now()}end
    end)}),'native makeup lifecycle observer unavailable')
   getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false);player:setAutoDrink(false)
   ready=true;emit({event='setup',cases=config.cases,queueEnabled=not native,nativeDurations=true,avatarSupported=true,captureSupported=true})
  end
  assert(now()-since<180000,'makeup timeout '..tostring(case())..' phase='..phase)
  intact()
  M.observeWalks()
  if moves and M.resumedAction and M.resumedAction.action and M.resumedAction:isStarted()then
   M.readerResume.native=tostring(M.resumedAction.action)
  end
  if phase=='prepare'then
   if config.options and (config.options.makeup_supplies==true or moves) and index==1 then
    assert(type(makeupClientReady)=='function','test-only native clothing connection readiness probe unavailable')
    if not makeupClientReady()then return end
   end
   if not empty()then return end
   if config.options and (config.options.makeup_supplies==true or moves) then
    if not placement then
     local square=require('QueueEnergyPlacement')(player)
     placement={x=square:getX(),y=square:getY(),z=square:getZ()};return
    end
    if index==1 and not F.atPlacement(player,placement)then return end
    assert(F.atPlacement(player,placement),'makeup supply actor left the settled placement tile')
   end
   checkpoints,sequence,outcomes,transferStarts,M.startOrder={},0,{},0,{};phase='prepared';command('Prepare',{placement=placement})
  elseif phase=='prepared'and ids then
   if not state then state=F.resolve(player,ids);if not state then return end end
   if ids.wearPending then
    assert(not M.wearReady and ids.move and case()=='move-earlier','unexpected prepared makeup wear descriptor')
    sendClientCommand('MakeupTest','WearPrepared',{case=case(),item=ids.items.old});state=nil;phase='wear-prepared';return
   end
   if player:tooDarkToRead()then return end
   checkpoint('baseline','open')
  elseif phase=='checkpoint'and authority then
   assert(authority.case==case()and authority.label==pending.label and authority.sequence==pending.sequence,'authority checkpoint identity differs')
   local nextPhase=pending.nextPhase;pending.nextPhase=nil
   checkpoints[#checkpoints+1]={client=pending,authority=authority};pending,authority=nil,nil;phase=nextPhase
  elseif phase=='open'then open()
  elseif phase=='render'and renderWitness then checkpoint(renderLabel,renderNext)
  elseif phase=='after-preview'then
   if case()=='preview-close'then close();checkpoint('closed','tail')
   elseif case()=='preview-location'then choose(ids.alternate);rendered('same-preview','location-clear')
   else apply()end
  elseif phase=='location-clear'then chooseLocation(ids.different);checkpoint('location-cleared','different')
  elseif phase=='different'then choose(ids.different,true);rendered('different-preview','close-location')
  elseif phase=='close-location'then close();checkpoint('closed','tail')
  elseif phase=='move-front'then
   if queue().current~=front or not front.action or not front:isStarted()or front:getJobDelta()<=0
    or state.player:getAlreadyReadPages(ids.types.front)<=ids.frontInitial then return end
   assert(not body.action and bodyRecord.starts==0,'move test body allocated before edit')
   local before=M.order();local physical=snapshot();local token=body.toolkitQueueOperation
   if ids.held then assert(F.handsReady(state,false),'held makeup input was stowed or replaced before move admission')end
   assert(token and token~=front.toolkitQueueOperation and token~=M.middle.toolkitQueueOperation and token~=tail.toolkitQueueOperation
    and(not M.writer or token~=M.writer.toolkitQueueOperation)
    and(not M.walkActions or token~=M.walkActions.out.toolkitQueueOperation and token~=M.walkActions.back.toolkitQueueOperation),'native makeup shares an unrelated operation token')
   local frontNative=tostring(front.action);local pages=physical.frontPages;local delta=front:getJobDelta()
   local target=M.kind()=='promote'and front or (M.kind()=='deny-writer'or M.kind()=='deny-equip')and M.writer or M.kind()=='deny-walk'and M.walkActions.out or M.middle
   local accepted,reason=false,false
   if not native then accepted,reason=T.ActionQueue.move(queue(),body,target,M.kind()=='later'or M.kind()=='deny-walk')end
   local expected=not native and M.kind()~='deny-writer'and M.kind()~='deny-walk'and M.kind()~='deny-equip'
   if accepted~=expected then
    local kit,source=F.kit(state);local bag=source and source:getContainingItem()
    local view=bag and bag:getContainer();local world=bag and bag:getWorldItem()
    local caches=ISInventoryPage and ISInventoryPage.floorContainer
    local contract=T.ActionQueuePolicy.inspect(body)
    raw('MOVE_SOURCE',{case=case(),knownInputs=contract and contract.knownInputs or false,
     sourceClass=source and getClassSimpleName(source)or false,sourceType=source and source:getType()or false,
     sourceExists=source and source:isExistYet()or false,outerIsSource=kit and kit:getOutermostContainer()==source or false,
     viewClass=view and getClassSimpleName(view)or false,viewType=view and view:getType()or false,
     actorFloorView=view~=nil and type(caches)=='table'and caches[state.player:getPlayerNum()+1]==view or false,
     bagComponents=bag and bag:hasComponents()or false,worldComponents=world and world:hasComponents()or false,
     worldObjects=world and world:getSquare()and world:getSquare():getWorldObjects():contains(world)or false,
     objects=world and world:getSquare()and world:getSquare():getObjects():contains(world)or false})
   end
   assert(accepted==expected,'makeup move admission differs '..tostring(reason))
   assert(F.same(physical,snapshot())and token==body.toolkitQueueOperation and not body.action,'move mutated paid state or operation ownership')
   edit={at=now(),accepted=accepted,reason=reason or false,before=before,after=M.order(),bodyUnallocated=true,
    ownershipPreserved=true,frontPages=pages,frontDelta=delta,frontNativeBefore=frontNative,
    frontNativeAfter=tostring(front.action),frontRetained=queue():indexOf(front)~=-1,tailRetained=queue():indexOf(tail)~=-1,hands=ids.held and physical.hands or nil}
   if expected and M.kind()=='promote'then M.readerResume={pages=pages}end
   raw('EDIT',{case=case(),evidence=edit});phase='wait-body'
  elseif phase=='wait-front'then
   if queue().current~=front or not front.action or not front:isStarted()or front:getJobDelta()<=0 then return end
   assert(not body.action and bodyRecord.starts==0,'pending makeup body allocated before cancellation')
   local accepted,reason=false,false
   if not native then accepted,reason=T.ActionQueue.cancelOperation(queue(),body);assert(accepted,'pending makeup cancellation rejected '..tostring(reason))end
   edit={at=now(),accepted=accepted,bodyUnallocated=true,bodyAbsent=queue():indexOf(body)==-1,
    frontSame=queue().current==front,frontNative=tostring(front.action),tailRetained=queue():indexOf(tail)~=-1,reason=reason or false}
   assert(edit.frontSame and edit.tailRetained,'makeup cancellation lost independent readers')
   raw('EDIT',{case=case(),evidence=edit});checkpoint('cancelled','wait-body')
  elseif phase=='wait-body'then afterBody()
  elseif phase=='close-overlap'then close();checkpoint('closed','final-drain')
  elseif phase=='tail'then addTail();phase='final-drain'
  elseif phase=='final-drain'then
   if not empty()or snapshot().tailPages~=ids.tailTotal then finalQuiet=nil;return end
   finalQuiet=finalQuiet or now();if now()-finalQuiet<1500 then return end
   checkpoint('final','verify')
  elseif phase=='verify'then phase='verified';command('Finish')
  elseif phase=='verified'and verified then
   assert(verified.case==case()and verified.sequence==sequence,'authority final receipt identity differs')
   local final=snapshot();local output=F.output(verified.snapshot,ids)
   emit({event='case',id=case(),status='passed',ids=ids,checkpoints=checkpoints,receipt=verified,clientFinal=final,
    submitted=submitted,second=second or false,output=output,body=bodyRecord or false,outcomes=outcomes,
    edit=edit or false,beforeTail=beforeTail,nativeMethodsUnchanged=true,applyQueues=applyQueues,supplyTransferStarts=(ids.supply or moves)and transferStarts or nil,startOrder=moves and M.startOrder or nil,readerResume=M.readerResume or nil,walk=M.walkRecord or nil,equipWriter=M.equipWriter or nil})
   previous=ids;index=index+1
   state,ids,ui,front,tail,body,submitted,second,beforeTail,edit,verified,pending,authority=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
   bodyQuiet,finalQuiet,renderWitness,renderLabel,renderNext,bodyRecord,applyQueues=nil,nil,nil,nil,nil,nil,nil;M.middle,M.writer,M.readerResume,M.wearReady,M.resumedAction,M.walkActions,M.walkRecord,M.walkNatives,M.equipWriter=nil,nil,nil,nil,nil,nil,nil,nil,nil;since=now();phase='prepare'
   if not case()then emit({event='complete',cases=config.cases,performed=#config.cases,skipped=0,failed=0});raw('COMPLETE',{cases=config.cases});done=true end
  end
 end)
 if not ok then
  emit({event='case',id=case(),status='failed',phase=phase,reason=tostring(problem),ids=ids or false,
   checkpoints=checkpoints or{},clientActual=state and snapshot()or false})
  print('[QUEUE_TEST] FAIL makeup '..tostring(problem));done=true
 end
end)
