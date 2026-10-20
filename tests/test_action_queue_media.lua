if not NativeActionRoot then print('Media insertion native contracts SKIP (pass --native-action-root).');return end
local function read(path)
 if NativeReadText then return NativeReadText(path):gsub('\r','')end
 local file=assert(io.open(path));local text=file:read('*a');file:close();return text:gsub('\r','')
end
local function reader(text)
 local position=1
 return {close=function()end,readLine=function()
  if position>#text then return end
  local boundary=text:find('\n',position,true)or #text+1
  local line=text:sub(position,boundary-1);position=boundary+1;return line
 end}
end
local function setup(wrapped,changedSource,foreignCallback,queueHooks)
 isPlayerDoingActionThatCanBeCancelled,stopDoingActionThatCanBeCancelled,CancelAction=nil,nil,nil
 local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
 local receive
 Events.OnServerCommand.Add=function(callback)receive=callback end
 local function native(path)
  assert(loadstring(read(NativeActionRoot..'/'..path),'@'..path))()
 end
 -- Named, unmodified upstream callbacks give the same origin proofs as Kahlua.
 native('shared/TimedActions/ISBaseTimedAction.lua')
 native('shared/TimedActions/ISDeviceBatteryAction.lua')
 native('shared/TimedActions/ISDeviceMediaAction.lua')
 native('shared/RadioCom/ISRadioAction.lua')
 -- The engine supplies walk actions; only queue grouping/resources are modeled here.
 ISWalkToTimedAction=ISBaseTimedAction:derive('ISWalkToTimedAction')
 f.native('shared/Fluids/ISFluidContainer.lua');f.native('shared/Fluids/ISFluidTransferAction.lua')
 f.native('shared/Fluids/ISFluidEmptyAction.lua');f.native('shared/TimedActions/ISTransferAction.lua')
 f.native('shared/TimedActions/ISDrinkFluidAction.lua')
 isClient,isServer=function()return false end,function()return false end
 getActivatedMods=function()return {contains=function(_,id)return wrapped and id=='TVRadio_ReInvented'end}end
 getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
 getGameFilesInput=function(path)
  local text=read(NativeActionRoot..'/'..path:gsub('^media/lua/',''))
  if changedSource=='native'and path:find('ISDeviceMediaAction',1,true)
   or changedSource=='helper'and path:find('ISDeviceBatteryAction',1,true)
   or changedSource=='base'and path:find('ISBaseTimedAction',1,true)then text=text..'-- changed source\n'end
  return reader(text)
 end
 getModFileReader=function(id,path)
  assert(id=='PZSurvivorToolkit')
  local text=read(ProjectRoot..'/PZSurvivorToolkit/42/'..path)
  if changedSource=='toolkit'then text=text..'-- changed wrapper\n'end
  return reader(text)
 end
 if foreignCallback=='delegate'then ISDeviceMediaAction.isValid=function()error('foreign delegate must never execute')end end
 if wrapped then assert(loadstring(read(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/TVMediaAction.lua'),'@PZSurvivorToolkit/TVMediaAction.lua'))()end
 if foreignCallback==true then ISDeviceMediaAction.complete=function()error('foreign preinstalled callback')end end
 local originalInstance=instanceof
 instanceof=function(value,kind)
  return originalInstance(value,kind)or type(value)=='table'and
   (kind=='InventoryItem'and value.class=='InventoryContainer'or kind=='IsoObject'and value.class=='IsoTelevision')
 end
 f.player.class='IsoPlayer'
 f.player.isLocalPlayer=function()return true end
 f.player.isDraggingCorpse=function()return false end
 f.player.isRunning=function()return false end;f.player.isSprinting=function()return false end
 f.player.isAiming=function()return false end
 local function container(kind)
  return {class='ItemContainer',kind=kind or 'none',load=0,capacity=100,
   getType=function(self)return self.kind end,getParent=function(self)return self.parent end,
   getContainingItem=function(self)return self.owner end,getCapacityWeight=function(self)return self.load end,
   getEffectiveCapacity=function(self)return self.capacity end,getAcceptItemFunction=function(self)return self.accept end,
   getOnlyAcceptCategory=function()end,isExistYet=function(self)return not self.gone end,
   contains=function(self,item)return item:getContainer()==self end}
 end
 local root=container();f.player.inventory=root
 f.player.getVehicle=function()end
 local function device()
  local tv={class='IsoTelevision'}
  local data={class='DeviceData',media=false,index=-1,consumed=0,validityCalls=0}
  local square={class='IsoGridSquare',getDeviceData=function()return data end}
  tv.getSquare=function(self)return not self.gone and square or nil end
  tv.getObjectIndex=function(self)return self.gone and -1 or 0 end
  tv.getDeviceData=function()return data end
  data.getParent=function()return tv end;data.getMediaType=function()return 1 end
  data.getIsTurnedOn=function()return true end;data.getMediaIndex=function(self)return self.index end
  data.getIsBatteryPowered=function()return false end;data.canBePoweredHere=function()return true end
  data.hasMedia=function(self)self.validityCalls=self.validityCalls+1;return self.media end
  data.addMediaItem=function(self,item)self.media=true;self.index=item:getRecordedMediaIndex();self.consumed=self.consumed+1;item.container=nil end
  return tv,data,square
 end
 local tv,data,square=device()
 local function tape()
  local item=f.item('Base.VHS_Retail');item.container=root;item.recorded=true;item.mediaType=1;item.mediaIndex=7;item.weight=0.1
  item.getContainer=function(self)return self.container end
  item.isRecordedMedia=function(self)return self.recorded end;item.getMediaType=function(self)return self.mediaType end
  item.getRecordedMediaIndex=function(self)return self.mediaIndex end
  item.getType=function()return 'VHS_Retail'end;item.getUnequippedWeight=function(self)return self.weight end
  item.getIsCraftingConsumed=function()return false end;item.getWorldItem=function()end
  return item
 end
 local item=tape()
 f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
 local policy=f.project('ActionQueuePolicy')
 if queueHooks then f.project('ActionQueueLabels');f.project('ActionQueue')end
 local media=f.project('ActionQueueMedia');local installed=media.install()

 return {f=f,policy=policy,media=media,installed=installed,definitions=PZSurvivorToolkit.ActionQueueDefinitions,
  operations=PZSurvivorToolkit.ActionQueueOperations,container=container,device=device,tape=tape,
  root=root,tv=tv,data=data,square=square,item=item,receive=function(...)assert(receive)(...)end}
end
local function nativeCancelHelpers(player)
 local input={key=1,eaten=0,stops=0,visible=false,drag=false,game=true}
 MainScreen={instance={inGame=true,getIsVisible=function()return input.visible end}}
 getCell=function()return {getDrag=function()return input.drag and {}or nil end}end
 KeybindId={CANCEL_ACTION='CancelAction'}
 getCore=function()return {isKey=function(_,binding,key)return binding==KeybindId.CANCEL_ACTION and key==input.key end}end
 GameKeyboard={eatKeyPress=function(key)assert(key==input.key);input.eaten=input.eaten+1 end}
 -- Model the installed Java boundary: the removed native action leaves an empty
 -- stack, so native cancellability is false and StopAllActionQueue is a no-op.
 player.isDoingActionThatCanBeCancelled=function(self)return self.nativeBusy==true end
 player.StopAllActionQueue=function(self)input.stops=input.stops+1;self.nativeBusy=false end
 local text=read(NativeActionRoot..'/client/OptionScreens/MainScreen.lua')
 local callbacks=assert(text:match('(function isPlayerDoingActionThatCanBeCancelled.-)ToggleEscapeMenu ='))
 input.press=assert(loadstring(callbacks..'\nreturn StartPressCancelActionKey','@OptionScreens/MainScreen.lua'))()
 input.nativePredicate,input.nativeStop=isPlayerDoingActionThatCanBeCancelled,stopDoingActionThatCanBeCancelled
 assert(not input.nativePredicate(player),'empty native Java action stack must not appear cancellable')
 return input
end
for _,wrapped in ipairs({false,true})do
 local s=setup(wrapped);assert(s.installed,'actual native/owned media callbacks must install')
 local action=ISDeviceMediaAction:new(s.f.player,false,s.item,s.square)
 local contract,source=s.definitions.inspect(action)
 assert(source=='native.device-media-insert'and contract.items[s.item.id]and contract.targets[s.tv]
  and contract.capacityNonIncreasing==true and contract.cancelWaiting and contract.interrupt=='finish-step')
 assert(s.data.validityCalls==0,'contract inspection cannot execute current-state validity')
 local bag=s.container();s.item.container=bag
 assert(s.definitions.inspect(action),'future tape pickup must remain a declared input without requiring it in root yet')
 if wrapped then assert(not action:isValid(),'owned runtime guard still rejects a tape outside exact root inventory')end
 s.item.container=s.root
 assert(action:isValid()and action:complete()and s.data.consumed==1,'real native insertion completes through the retained ownership guard')
 assert(action:complete()and s.data.consumed==1,'native occupied-device guard prevents repeated effects')
 s.item.container=s.root;s.data.media=false
 local cancelled=ISDeviceMediaAction:new(s.f.player,false,s.item,s.square)
 cancelled:forceCancel();assert(s.item.container==s.root and s.data.consumed==1,'waiting native cancellation has no material effect')
 for _,field in ipairs({'onStartFunc','onCompleteFunc','onCancelFunc','onFailFunc','additionalTest','invoke','complete','customHelper'})do
  cancelled[field]=function()error('inspection must not invoke foreign callbacks')end
  assert(not s.definitions.inspect(cancelled),'changed action callback must reject '..field);cancelled[field]=nil
 end
 for _,field in ipairs({'new','complete','invoke','isValid','getDuration','stop','create','adjustMaxTime'})do
  local previous=ISDeviceMediaAction[field];ISDeviceMediaAction[field]=function()error('changed class callback')end
  assert(not s.definitions.inspect(cancelled),'changed class must reject '..field);ISDeviceMediaAction[field]=previous
 end
 local helper=ISDeviceBatteryAction.getDeviceDataFromParameter
 ISDeviceBatteryAction.getDeviceDataFromParameter=function()error('changed resolver')end
 assert(not s.definitions.inspect(cancelled));ISDeviceBatteryAction.getDeviceDataFromParameter=helper
 if wrapped then
  local binding=PZSurvivorToolkit.TVMediaActionBinding
  PZSurvivorToolkit.TVMediaActionBinding=function()error('foreign binding must never execute')end
  assert(not s.definitions.inspect(cancelled),'changed wrapper binding owner must revoke permission')
  PZSurvivorToolkit.TVMediaActionBinding=binding
 end
 for _,change in ipairs({'foreign-item','not-recorded','wrong-media-type','removed-tape','eject','wrong-square','removed-tv','wrong-device-data','duration'})do
  local current=ISDeviceMediaAction:new(s.f.player,false,s.item,s.square)
  if change=='foreign-item'then current.secondaryItem={}
  elseif change=='not-recorded'then s.item.recorded=false
  elseif change=='wrong-media-type'then s.item.mediaType=0
  elseif change=='removed-tape'then s.item.container=nil
  elseif change=='eject'then current.isRemove=true
  elseif change=='wrong-square'then current.parameter={class='IsoGridSquare'}
  elseif change=='removed-tv'then s.tv.gone=true
  elseif change=='wrong-device-data'then current.deviceData={}
  else current.maxTime=1 end
  assert(not s.definitions.inspect(current),'unsafe resource shape must reject '..change)
  s.item.recorded,s.item.mediaType,s.item.container,s.tv.gone=true,1,s.root,false
 end
 local head=s.f.action(ISReadABook,{item=s.f.item('Base.BookCarpentry1')})
 local power=ISRadioAction:new('ToggleOnOff',s.f.player,s.tv);power.toolkitQueueOperation={}
 local insert=ISDeviceMediaAction:new(s.f.player,false,s.item,s.square);insert.toolkitQueueOperation={}
 local play=ISRadioAction:new('TogglePlayMedia',s.f.player,s.tv);play.toolkitQueueOperation={}
 local q=s.f.queue(head,power,insert,play)
 assert(s.policy.moveReason(q,insert,power)=='move_dependent','media target must match native radio target')
 assert(s.policy.cancelOperationReason(q,insert)=='operation_dependent','insertion cannot be canceled beneath dependent playback')
 local other=s.device();local independent=ISRadioAction:new('ToggleOnOff',s.f.player,other);independent.toolkitQueueOperation={}
 q=s.f.queue(head,independent,insert)
 assert(not s.policy.moveReason(q,insert,independent),'independent TVs must remain independent')
 assert(not s.policy.cancelOperationReason(q,insert),'isolated pending insertion can be canceled')
end
do
 local s=setup(true,nil,nil,true)
 assert(s.installed,'adapter must install after the actual Toolkit inherited begin/stop hooks')
 assert(s.definitions.inspect(ISDeviceMediaAction:new(s.f.player,false,s.item,s.square)),
  'parent queue hook installation must retain the exact media contract')
end
-- Capture grants only this promoted, not-yet-started insertion a skip after loss.
-- Resource checks do not re-run native validity or grant control to changed code.
for _,wrapped in ipairs({false,true})do
 for _,loss in ipairs({'missing-tape','moved-tape','missing-tv','square-binding','data-parent','tv-binding','occupied'})do
  local s=setup(wrapped)
  local action=ISDeviceMediaAction:new(s.f.player,false,s.item,s.square)
  local record=assert(s.media.capture(action))
  assert(not s.media.canSkip(action,record),'available insertion must retain native execution')
  assert(not s.media.canSkip(action,{action=action,tape=s.item,data=s.data,television=s.tv}),
   'foreign records cannot acquire lifecycle permission')
  local other=ISDeviceMediaAction:new(s.f.player,false,s.item,s.square)
  assert(not s.media.canSkip(other,record),'a record belongs to one exact action')
  if loss=='missing-tape'then s.item.container=nil
  elseif loss=='moved-tape'then s.item.container=s.container()
  elseif loss=='missing-tv'then s.tv.gone=true
  elseif loss=='square-binding'then s.square.getDeviceData=function()return {}end
  elseif loss=='data-parent'then s.data.getParent=function()return {}end
  elseif loss=='tv-binding'then s.tv.getDeviceData=function()return {}end
  else s.data.media=true end
  assert(s.media.canSkip(action,record),'captured insertion may skip '..loss)
  action.action={}
  assert(not s.media.canSkip(action,record),'native allocated/started insertion cannot be skipped')
  action.action=nil
  action.secondaryItem=s.tape()
  assert(not s.media.canSkip(action,record),'a replacement action tape cannot inherit the captured identity')
  action.secondaryItem=s.item
  local callback=ISDeviceMediaAction.isValid
  ISDeviceMediaAction.isValid=function()error('changed validity must not execute')end
  assert(not s.media.canSkip(action,record),'resource loss cannot excuse changed callbacks')
  ISDeviceMediaAction.isValid=callback
  action.onCompleteFunc=function()error('foreign completion must not execute')end
  assert(not s.media.canSkip(action,record),'foreign action callback cannot be skipped')
 end
 local s=setup(wrapped);local action=ISDeviceMediaAction:new(s.f.player,false,s.item,s.square)
 local record=assert(s.media.capture(action))
 s.data.getMediaType=function()error('native isValid must not execute in lifecycle analysis')end
 assert(not s.media.canSkip(action,record),'empty target and retained tape remain native work without validity calls')
 s.item.container=nil
 assert(not s.media.capture(action),'a missing input cannot acquire a new lifecycle capture')
 assert(s.media.canSkip(action,record),'previous capture survives resource loss without re-describing')
end
-- Promoted-range cleanup links playback to the exact preceding insertion. An
-- occupied TV's replacement VHS must never be played on behalf of a lost tape.
for _,scenario in ipairs({'foreign-media','same-index','lost-tv','missing-tape','moved-tape','changed-media-callback',
 'changed-radio-callback','uncaptured','success','changed-index-after-success'})do
 local s=setup(true);local f=s.f;local reading=f.project('ActionQueueReading')
 local head=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')})
 local insert=ISDeviceMediaAction:new(f.player,false,s.item,s.square);insert.toolkitQueueOperation={}
 local play=ISRadioAction:new('TogglePlayMedia',f.player,s.tv);play.toolkitQueueOperation={}
 local tail=f.action(ISReadABook,{item=f.item('Base.BookElectrician1')})
 local q=f.queue(head,insert,play,tail)
 if scenario~='uncaptured'then reading.capture(q,2,3)end
 if scenario=='foreign-media'or scenario=='same-index'then s.data.media=true;s.data.index=scenario=='same-index'and 7 or 99
 elseif scenario=='lost-tv'then s.tv.gone=true
 elseif scenario=='moved-tape'then s.item.container=s.container()
 elseif scenario=='missing-tape'or scenario=='changed-media-callback'or scenario=='changed-radio-callback'or scenario=='uncaptured'then s.item.container=nil end
 if scenario=='changed-media-callback'then insert.complete=function()error('changed insertion cannot be suppressed')end
 elseif scenario=='changed-radio-callback'then play.performTogglePlayMedia=function()error('changed playback cannot be suppressed')end end
 reading.skipUnavailable(q)
 if scenario=='changed-media-callback'or scenario=='uncaptured'then
  assert(#q.queue==4 and q.queue[2]==insert and q.queue[3]==play,'changed/uncaptured actions retain native lifecycle '..scenario)
 elseif scenario=='changed-radio-callback'then
  assert(#q.queue==3 and q.queue[2]==play and q.queue[3]==tail,'changed radio callbacks cannot acquire captured skip permission')
 elseif scenario=='success'or scenario=='changed-index-after-success'then
  assert(#q.queue==4 and q.queue[2]==insert,'available insertion remains in native queue')
  assert(insert:complete()and s.data.consumed==1)
  q.queue={insert,play,tail};q.current=insert
  if scenario=='changed-index-after-success'then s.data.index=99 end
  reading.skipUnavailable(q)
  if scenario=='success'then
   assert(#q.queue==3 and q.queue[2]==play,'successfully inserted expected VHS retains playback')
  else assert(#q.queue==2 and q.queue[2]==tail,'a later different media index suppresses captured playback')end
 else assert(#q.queue==2 and q.queue[2]==tail,'lost insertion and its dependent playback preserve independent reader '..scenario)end
 assert(q.queue[#q.queue]==tail,'failure cleanup cannot discard the independent reader')
 assert(s.data.consumed==((scenario=='success'or scenario=='changed-index-after-success')and 1 or 0),
  'lifecycle cleanup cannot execute or replay native media effects')
end
for _,changed in ipairs({false,true})do
 local s=setup(true);local f=s.f;local reading=f.project('ActionQueueReading')
 local head=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')})
 local bag=s.container('bag');local owner=f.item('Base.Bag_Schoolbag');owner.class='InventoryContainer';bag.owner=owner
 s.item.container=bag
 local pickup=f.action(ISInventoryTransferAction,{item=s.item,srcContainer=bag,destContainer=s.root})
 local insert=ISDeviceMediaAction:new(f.player,false,s.item,s.square);insert.toolkitQueueOperation=pickup.toolkitQueueOperation
 local play=ISRadioAction:new('TogglePlayMedia',f.player,s.tv);play.toolkitQueueOperation={}
 local tail=f.action(ISReadABook,{item=f.item('Base.BookElectrician1')})
 local q=f.queue(head,pickup,insert,play,tail)
 reading.capture(q,2,4);bag.gone=true
 if changed then pickup.complete=function()error('changed transfer cannot be suppressed')end end
 reading.skipUnavailable(q)
 if changed then
  assert(#q.queue==5 and q.queue[2]==pickup,'lost source cannot excuse a changed native transfer callback')
 else
  assert(#q.queue==2 and q.queue[2]==tail,'lost pickup source skips its unavailable insert/play and preserves the reader')
 end
 assert(s.data.consumed==0 and s.item.container==bag,'source-loss cleanup cannot transfer or consume the VHS')
end
-- Host AddInventoryItemToContainer constructs a new Java item and rebinds direct
-- action fields by ID. The captured nested receipt must follow only a confirmed
-- native pickup, before queue advancement, and remain immutable afterwards.
for _,scenario in ipairs({'replica','native-perform','sp','failed','still-running','changed-pickup','changed-insert','wrong-id',
 'wrong-type','wrong-media','wrong-media-type','nested','duplicate','source-retained','old-retained',
 'wrong-source','wrong-destination','wrong-operation','wrong-generation','pending-operation','begun',
 'skipped','waiting','canceled','occupied','disabled','unrelated','stalled','canceled-operation','third-pickup-item'})do
 local s=setup(true,nil,nil,true);local f=s.f;local reading=f.project('ActionQueueReading')
 local lifecycle=PZSurvivorToolkit.ActionQueueLifecycle
 local handoff=scenario=='replica'or scenario=='native-perform'
 isClient=function()return scenario~='sp'end
 local bag=s.container('bag');s.item.container=bag
 local head=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')})
 local pickup=f.action(ISInventoryTransferAction,{item=s.item,srcContainer=bag,destContainer=s.root})
 local insert=ISDeviceMediaAction:new(f.player,false,s.item,s.square);insert.toolkitQueueOperation=pickup.toolkitQueueOperation
 local play=ISRadioAction:new('TogglePlayMedia',f.player,s.tv);play.toolkitQueueOperation={}
 local q=f.queue(head,pickup,insert,play)
 reading.capture(q,2,4)
 local record=insert.toolkitReadingMove;local original=record.receipt
 local replica=s.tape();replica.id=s.item.id
 s.item.container=nil;pickup.item=replica;insert.secondaryItem=replica
 local inventory={replica}
 s.root.getItemById=function(_,id)if id==replica.id then return replica end end
 s.root.getItems=function()return {size=function()return #inventory end,get=function(_,i)return inventory[i+1]end}end
 bag.getItemById=function(_,id)if scenario=='source-retained'and id==replica.id then return s.item end end
 q.queue={pickup,insert,play};q.current=pickup
 pickup.action={isStarted=function()return true end,hasStalled=function()return false end}
 local nativePresent=true
 f.player.getCharacterActions=function()return {contains=function()return nativePresent end}end
 assert(s.media.completionState(insert,original)==nil,'native direct-field rebinding leaves the old nested receipt stale')
 if scenario=='changed-pickup'then pickup.complete=function()error('foreign pickup must not execute')end
 elseif scenario=='changed-insert'then insert.complete=function()error('foreign insertion must not execute')end
 elseif scenario=='wrong-id'then replica.id=replica.id+99
 elseif scenario=='wrong-type'then replica.getFullType=function()return 'Base.VHS_Home'end
 elseif scenario=='wrong-media'then replica.mediaIndex=replica.mediaIndex+1
 elseif scenario=='wrong-media-type'then replica.mediaType=0
 elseif scenario=='nested'then replica.container=s.container()
 elseif scenario=='duplicate'then inventory[2]=replica
 elseif scenario=='old-retained'then s.item.container=bag
 elseif scenario=='wrong-source'then pickup.srcContainer=s.container()
 elseif scenario=='wrong-destination'then pickup.destContainer=s.container()
 elseif scenario=='wrong-operation'then pickup.toolkitQueueOperation={}
 elseif scenario=='wrong-generation'then q.toolkitOperationGeneration=1
 elseif scenario=='pending-operation'then insert.toolkitQueueOperation={}
 elseif scenario=='begun'then insert.action={}
 elseif scenario=='skipped'then record.skipped=true
 elseif scenario=='waiting'then record.completion={}
 elseif scenario=='canceled'then q.toolkitCancel=pickup
 elseif scenario=='occupied'then s.data.media=true
 elseif scenario=='stalled'then pickup.action.hasStalled=function()return true end
 elseif scenario=='canceled-operation'then pickup.toolkitQueueOperation.toolkitCancelled=true
 elseif scenario=='third-pickup-item'then pickup.item=s.tape();pickup.item.id=replica.id
 elseif scenario=='unrelated'then record.pickup=nil end
 assert(lifecycle.begin(pickup,'perform'),'native pickup boundary must be captured')
 if scenario=='native-perform'then
  -- Execute the unmodified native perform, including its actual base onCompleted
  -- call. Java transaction effects are modeled above; queueList is intentionally
  -- still the old nested reference after direct-field replica replacement.
  pickup.queueList={{items={s.item},time=30,type=s.item:getFullType()}}
  pickup.transactionId=73
  s.item.setJobDelta=function()end;replica.setJobDelta=function()end
  s.root.getPutSound=function()end
  local emitter={isPlaying=function()return false end,playSound=function()end}
  f.player.getEmitter=function()return emitter end
  f.player.setIsFarming=function()end
  ISLogSystem={logAction=function()end}
  local transactions=0
  removeItemTransaction=function(id,canceled)
   assert(id==73 and canceled==false);transactions=transactions+1
  end
  pickup.action.stopTimedActionAnim=function()end
  pickup.action.setLoopedAction=function()end
  pickup.action.setWaitForFinished=function()end
  pickup:perform()
  assert(pickup.item==s.item and #pickup.queueList==0 and transactions==1,
   'actual native perform restores the old item from nested queueList and closes its transaction')
  assert(record.receipt==original and q.current==pickup and q.queue[1]==pickup,
   'actual native onCompleted must defer advancement until the successful lifecycle boundary')
 else
  assert(lifecycle.deferCompletion(q,pickup),'native callback must request advancement')
 end
 lifecycle.finish(pickup,'perform',scenario~='failed')
 if scenario=='sp'then assert(lifecycle.begin(pickup,'complete'));lifecycle.finish(pickup,'complete',true)end
 if scenario=='disabled'then PZSurvivorToolkit.Settings.actionQueue=function()return false end end
 nativePresent=scenario=='still-running'
 local advanced=0
 q.onCompleted=function()
  advanced=advanced+1
  if handoff then assert(record.receipt.tape==replica,'rebind must precede native queue advancement')end
 end
 local status=lifecycle.flush(q)
 if handoff then
  assert(status=='completed'and advanced==1 and record.receipt~=original and record.receipt.tape==replica)
  assert(play.toolkitReadingMove.insertion==record and record.mediaIndex==original.mediaIndex,
   'playback retains the same dependency record and frozen media index')
  assert(s.media.completionState(insert,record.receipt)=='waiting'and not s.media.canSkip(insert,record.receipt))
  insert.action={};local rebound=record.receipt
  insert.secondaryItem=s.tape();insert.secondaryItem.id=replica.id
  reading.completedPickup(q,pickup)
  assert(record.receipt==rebound and s.media.completionState(insert,rebound)==nil,
   'a begun insertion cannot accept another same-ID replica')
 else assert(record.receipt==original,'unproven native pickup cannot refresh receipt: '..scenario)end
 assert(original.tape==s.item and s.data.consumed==0,'receipt repair never changes the old snapshot or executes effects')
end
print('Promoted VHS native Host pickup replica handoff and rejection checks passed.')

-- Native RWMMedia keeps one click's pickup/walk/insert group intact.
do
 local s=setup(true);local f=s.f
 RWMPanel=ISBaseObject;UIFont={Small='small'};getTextManager=function()return {getFontHeight=function()return 12 end}end
 assert(loadstring(read(NativeActionRoot..'/client/RadioCom/RadioWindowModules/RWMMedia.lua'),'@RadioCom/RadioWindowModules/RWMMedia.lua'))()
 local bag=s.container();s.item.container=bag
 local head=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')});local q=f.queue(head)
 local pickup,walk
 ISInventoryPaneContextMenu.transferIfNeeded=function(player,item)
  pickup=f.action(ISInventoryTransferAction,{item=item,srcContainer=bag,destContainer=s.root})
  pickup.toolkitQueueOperation=nil;ISTimedActionQueue.add(pickup)
 end
 local panel={player=f.player,device=s.tv,deviceType='IsoObject',doWalkTo=function()
  walk=f.action(ISWalkToTimedAction);walk.toolkitQueueOperation=nil;ISTimedActionQueue.add(walk);return true
 end}
 s.operations.run(RWMMedia.addMediaAux,panel,s.item)
 local insert=q.queue[4]
 assert(#q.queue==4 and q.queue[2]==pickup and q.queue[3]==walk and insert.Type=='ISDeviceMediaAction')
 assert(pickup.toolkitQueueOperation==walk.toolkitQueueOperation and walk.toolkitQueueOperation==insert.toolkitQueueOperation
  and insert.toolkitQueueOperation~=head.toolkitQueueOperation,'adapter must preserve native one-click grouping')
 assert(s.definitions.inspect(insert),'native produced future insertion remains recognized')
end

-- Shelf reading demotion crosses the whole TV range in its original order. The
-- capacity projection may not spend the future book return or VHS consumption.
local stockNext=next
next=nil -- B42 Kahlua exposes pairs but not the standard Lua next global.
for _,sourceKind in ipairs({'bag','world'})do
 for _,kind in ipairs({'sp','host'})do
  local s=setup(true);local f=s.f
  isClient=function()return kind=='host'end
  local function shelf()
   local container=s.container('shelves')
   local square={}
   container.parent={class='IsoObject',getSquare=function()return square end,getContainerCount=function()return 1 end,
    getContainerByIndex=function(_,index)assert(index==0);return container end}
   return container
  end
  local book=s.tape();book.getFullType=function()return 'Base.BookCarpentry1'end;book.weight=2
  local originalShelf=shelf();originalShelf.capacity=10
  local tapeSource=sourceKind=='world'and shelf()or s.container('bag')
  if sourceKind=='bag'then local owner=f.item('Base.Bag_Schoolbag');owner.class='InventoryContainer';tapeSource.owner=owner end
  s.item.container=tapeSource;s.item.weight=1;tapeSource.load=1
  s.root.load=2;s.root.capacity=10
  local active=f.action(ISReadABook,{item=book,action={isStarted=function()return true end,
   finished=function()return false end,isForceComplete=function()return false end}})
  local returned=f.action(ISInventoryTransferAction,{item=book,srcContainer=s.root,destContainer=originalShelf,allowMissingItems=true})
  returned.toolkitQueueOperation=active.toolkitQueueOperation
  local power=ISRadioAction:new('ToggleOnOff',f.player,s.tv);power.toolkitQueueOperation={}
  local pickup=f.action(ISInventoryTransferAction,{item=s.item,srcContainer=tapeSource,destContainer=s.root})
  local walk=f.action(ISWalkToTimedAction);walk.toolkitQueueOperation=pickup.toolkitQueueOperation
  local insert=ISDeviceMediaAction:new(f.player,false,s.item,s.square);insert.toolkitQueueOperation=pickup.toolkitQueueOperation
  local play=ISRadioAction:new('TogglePlayMedia',f.player,s.tv);play.toolkitQueueOperation={}
  local q=f.queue(active,returned,power,pickup,walk,insert,play)
  local reason,first,rangeFirst,rangeLast,demotion=s.policy.moveReason(q,active,play,true)
  assert(not reason and first==1 and rangeFirst==3 and rangeLast==7 and demotion,
   'bounded shelf/bag TV demotion must be permitted '..sourceKind..'/'..kind..' '..tostring(reason))
  assert(q.queue[1]==active and q.queue[2]==returned and q.queue[3]==power and q.queue[7]==play,
   'read-only demotion analysis cannot mutate original source order')
  s.root.capacity=3
  assert(s.policy.moveReason(q,active,play,true)=='container_capacity','a future book return cannot fund the tape pickup')
  s.root.capacity=10;originalShelf.load=9
  assert(s.policy.moveReason(q,active,play,true)=='container_capacity','a full source shelf cannot accept the final book return')
  originalShelf.load=0
  for _,container in ipairs({s.root,originalShelf,tapeSource})do
   container.accept=function()error('custom capacity callback must never execute during analysis')end
   assert(s.policy.moveReason(q,active,play,true),'custom container rules cannot inherit bounded capacity permission')
   container.accept=nil
  end
  originalShelf.gone=true
  assert(s.policy.moveReason(q,active,play,true)=='container_capacity','a missing original shelf cannot inherit a carried-container proof')
 end
end
next=stockNext
print('Media native producer grouping and SP/Host shelf demotion capacity bounds passed without next().')

assert(not setup(false,'native').installed,'changed native media source cannot inherit adapter permission')
assert(not setup(false,'helper').installed,'changed native device resolver source cannot inherit adapter permission')
assert(not setup(false,'base').installed,'changed inherited native lifecycle source cannot inherit adapter permission')
assert(not setup(true,'toolkit').installed,'changed owned validity wrapper source cannot inherit permission')
assert(not setup(false,nil,true).installed,'foreign preinstalled complete cannot be blessed by source files')
assert(not setup(true,nil,'delegate').installed,'owned wrapper cannot bless a foreign captured validity delegate')
print('Media actual-source callbacks, exact VHS/TV resources, native effects, cancellation and fail-closed guards passed.')

-- Native Done is ordered on channel 1; RadioDeviceDataState is reliable but
-- unordered on channel 0. Exercise Done/receipt before either replicated effect.
-- The Java lifecycle boundary is driven explicitly; all media/radio callbacks
-- and Toolkit completion/reading callbacks below are the actual saved sources.
for _,scenario in ipairs({'exact-later','effects-before-ack','adjusted-duration','wrong-cassette','lost-tv','no-effect',
 'changed-callback','changed-create','changed-adjustment',
 'native-failure','queue-reset','queue-disabled','generation-change','ack-canceled','ack-rejected','ack-lost',
 'cancel-key','cancel-direct','cancel-rules','cancel-late-install','cancel-changed','ordinary-walk','running','sprinting','aiming'})do
 local s=setup(true,nil,nil,true);local f=s.f
 local input,gameStarts=nil,{}
 if scenario=='cancel-late-install'then Events.OnGameStart.Add=function(callback)gameStarts[#gameStarts+1]=callback end
 elseif scenario:find('^cancel%-')then input=nativeCancelHelpers(f.player)end
 local reading=f.project('ActionQueueReading')
 if scenario=='cancel-late-install'then
  input=nativeCancelHelpers(f.player)
  assert(#gameStarts==1,'missing native globals must defer helper installation to OnGameStart')
  gameStarts[1]();local installed=isPlayerDoingActionThatCanBeCancelled;gameStarts[1]()
  assert(isPlayerDoingActionThatCanBeCancelled==installed,'repeated game-start installation cannot stack helper wrappers')
 end
 local lifecycle=PZSurvivorToolkit.ActionQueueLifecycle
 local now,tailStarts,expectTail,nativePresent=1000,0,false,true
 getTimestampMs=function()return now end
 f.player.getCharacterActions=function()return {contains=function()return nativePresent end}end
 f.player.setIsFarming=function()end
 MoodleType={UNHAPPY='unhappy',DRUNK='drunk'}
 f.player.getMoodles=function()return {getMoodleLevel=function()return 0 end}end
 f.player.getTimedActionTimeModifier=function()return 1 end
 ISLogSystem={logAction=function()end}
 s.root.getItemById=function(_,id)if id==s.item:getID()and s.item.container==s.root then return s.item end end
 local head=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')})
 local insert=ISDeviceMediaAction:new(f.player,false,s.item,s.square);insert.toolkitQueueOperation={}
 local play=ISRadioAction:new('TogglePlayMedia',f.player,s.tv);play.toolkitQueueOperation={}
 local tail=f.action(ISReadABook,{item=f.item('Base.BookElectrician1'),begin=function()tailStarts=tailStarts+1 end})
 local q=f.queue(head,insert,play,tail)
 if input then
  assert(not isPlayerDoingActionThatCanBeCancelled(f.player),'non-wait native false predicate must be preserved')
  f.player.nativeBusy=true
  assert(isPlayerDoingActionThatCanBeCancelled(f.player),'non-wait native true predicate must be preserved')
  stopDoingActionThatCanBeCancelled(f.player)
  assert(input.stops==1 and #q.queue==4,'non-wait native stop must delegate without clearing Lua work')
  input.stops=0
 end
 reading.capture(q,2,3)
 q.queue={insert,play,tail};q.current=insert
 insert.action={isStarted=function()return true end}
 if scenario=='adjusted-duration'then
  f.player.getMoodles=function()return {getMoodleLevel=function(_,moodle)return moodle==MoodleType.UNHAPPY and 4 or 0 end}end
  f.player.getTimedActionTimeModifier=function()return 1.5 end
  LuaTimedActionNew={new=function()return {isStarted=function()return true end}end}
  insert:create()
  assert(insert.maxTime==90,'real native create must apply moodle/temperature duration adjustments')
 end
 local receipt={state='started'}
 PZSurvivorToolkit.ActionQueueAcknowledgements={capture=function(action)if action==insert then return receipt end end,
  state=function(_,record)assert(record==receipt);return receipt.state end,reset=function()end}

 -- Server completion consumes its separate tape once; packets have not changed
 -- the client's retained tape or DeviceData yet. No client invoke/complete replay.
 local _,serverData,serverSquare=s.device();local serverTape=s.tape()
 local serverAction=ISDeviceMediaAction:new(f.player,false,serverTape,serverSquare)
 isClient,isServer=function()return false end,function()return true end
 assert(serverAction:complete()and serverData.consumed==1 and serverTape.container==nil)
 isClient,isServer=function()return true end,function()return false end
 receipt.state=scenario=='effects-before-ack'and 'started'or 'completed'
 assert(lifecycle.begin(insert,'perform'),'actual completion boundary must own current media action')
 insert:perform()
 assert(not lifecycle.deferredAction(q),'callback stack still unwinding cannot expose a removed-action continuation')
 lifecycle.finish(insert,'perform',scenario~='native-failure')
 assert(not lifecycle.deferredAction(q),'native action still present cannot expose a removed-action continuation')
 nativePresent=false
 assert(q.current==insert and q.queue[2]==play,'native perform must defer queue advancement until lifecycle flush')
 local status=lifecycle.flush(q)
 if status~='waiting'and scenario~='native-failure'then
  print('MEDIA_REPLICATION_RACE observed='..tostring(status)..' droppedPlayback='..tostring(q:indexOf(play)==-1)
   ..' independentReaderStarted='..tostring(tailStarts>0)..' clientMedia='..tostring(s.data.media))
 end
 if scenario=='native-failure'then
  assert(status=='failed'and q.current==insert and not insert.toolkitReadingMove.completion,
   'known native callback failure takes precedence over stale media replication')
  assert(lifecycle.flush(q)==nil,'failed native callback must release its lifecycle wait record')
 else
 assert(status=='waiting'and q.current==insert and q.queue[2]==play and tailStarts==0,
  'completed server receipt with stale local media/tape must wait before dependent playback')
 now=1100
 assert(lifecycle.flush(q)=='waiting','duplicate completed receipt cannot release stale local effects')
 if scenario=='exact-later'or scenario=='effects-before-ack'or scenario=='adjusted-duration'or scenario=='ordinary-walk'then
  if scenario=='ordinary-walk'then
   f.player.isPlayerMoving=function()return true end;f.player.pressedMovement=function()return true end
   assert(insert.stopOnWalk==false and lifecycle.flush(q)=='waiting','ordinary walking retains native insertion stopOnWalk=false')
  end
  s.data.media=true;s.data.index=s.item:getRecordedMediaIndex()
  assert(lifecycle.flush(q)=='waiting'and q.current==insert,'media replication without exact tape debit must still wait')
  s.item.container=nil
  if scenario=='effects-before-ack'then
   assert(lifecycle.flush(q)=='waiting'and q.current==insert,'exact local effects cannot replace correlated terminal completion')
   receipt.state='completed'
  end
  -- Observe actual queue advancement without replacing native radio callbacks.
  LuaTimedActionNew={new=function(action)return {isStarted=function()return false end}end}
  f.player.setTimedActionToRetrigger=function()end;f.player.StartAction=function()end
  assert(lifecycle.flush(q)=='completed'and q.current==play and q.queue[2]==tail,
   'both exact replicated effects release expected playback exactly once')
  assert(lifecycle.flush(q)==nil and q.current==play,'duplicate completion cannot advance or replay playback')
 elseif scenario=='wrong-cassette'then
  s.item.container=nil;s.data.media=true;s.data.index=s.item:getRecordedMediaIndex()+1
  assert(lifecycle.flush(q)=='completed'and q.current==tail and insert.toolkitReadingMove.skipped,
   'a different cassette finishes the no-effect insertion and skips only its dependent playback')
  expectTail=true
 elseif scenario=='lost-tv'then
  s.tv.gone=true
  assert(lifecycle.flush(q)=='completed'and q.current==tail and insert.toolkitReadingMove.skipped,
   'lost exact TV preserves independent reading after skipping its dependent playback')
  expectTail=true
 elseif scenario=='no-effect'then
  now=31001
  assert(lifecycle.flush(q)=='completed'and q.current==tail and insert.toolkitReadingMove.skipped,
   'completed no-effect insertion terminates at the bounded deadline without discarding the reader')
  expectTail=true
 elseif scenario=='changed-callback'then
  insert.complete=function()error('changed native callbacks cannot inherit the completion barrier')end
  assert(lifecycle.flush(q)=='failed'and q.current==insert,'changed callback must remain a generic failure without inferred success')
 elseif scenario=='changed-create'or scenario=='changed-adjustment'then
  local name=scenario=='changed-create'and 'create'or 'adjustMaxTime'
  ISBaseTimedAction[name]=function()error('changed inherited native helper must not execute')end
  assert(lifecycle.flush(q)=='failed'and q.current==insert,'changed native '..name..' cannot inherit captured completion permission')
 elseif scenario=='queue-reset'then
  q:resetQueue();s.item.container=nil;s.data.media=true;s.data.index=s.item:getRecordedMediaIndex()
  assert(lifecycle.flush(q)==nil and q.current==nil and #q.queue==0,'explicit reset revokes late exact media completion')
 elseif scenario=='queue-disabled'then
  DebugType={Action={warn=function()end}}
  PZSurvivorToolkit.Settings.actionQueue=function()return false end
  q:tick()
  assert(q.current==nil and #q.queue==0,'disabled queue releases the wait and retains native reset behavior')
  PZSurvivorToolkit.Settings.actionQueue=function()return true end
  s.item.container=nil;s.data.media=true;s.data.index=s.item:getRecordedMediaIndex()
  assert(lifecycle.flush(q)==nil and #q.queue==0,'re-enabling cannot revive a late media completion')
 elseif scenario=='generation-change'then
  q.toolkitOperationGeneration=(q.toolkitOperationGeneration or 0)+1
  assert(lifecycle.flush(q)=='failed'and q.current==insert,'a stale operation generation cannot release captured playback')
 elseif scenario=='ack-canceled'or scenario=='ack-rejected'or scenario=='ack-lost'then
  receipt.state=scenario=='ack-canceled'and 'canceled'or scenario=='ack-rejected'and 'rejected'or nil
  assert(lifecycle.flush(q)=='completed'and q.current==tail and insert.toolkitReadingMove.skipped,
   'lost or terminal unsuccessful acknowledgement skips dependent playback only '..scenario)
  expectTail=true
 elseif input then
  assert(not input.nativePredicate(f.player)and isPlayerDoingActionThatCanBeCancelled(f.player),
   'scoped wait must expose cancellability while native Java action stack is empty')
  reading.installCancelHelpers();local predicate,stopper=isPlayerDoingActionThatCanBeCancelled,stopDoingActionThatCanBeCancelled
  reading.installCancelHelpers()
  assert(isPlayerDoingActionThatCanBeCancelled==predicate and stopDoingActionThatCanBeCancelled==stopper,
   'repeated helper installation cannot stack wrappers')
  if scenario=='cancel-rules'then
   input.press(input.key+1);input.visible=true;input.press(input.key);input.visible=false
   input.drag=true;input.press(input.key);input.drag=false
   MainScreen.instance.inGame=false;input.press(input.key);MainScreen.instance.inGame=true
   assert(q.current==insert and input.stops==0 and input.eaten==0,'native key/UI/drag/menu rules still protect cancellation dispatch')
  end
  if scenario=='cancel-changed'then
   insert.complete=function()error('changed callback cannot gain cancellation permission')end
   input.press(input.key)
   assert(not isPlayerDoingActionThatCanBeCancelled(f.player)and q.current==insert and input.stops==0 and input.eaten==0,
    'changed media callbacks retain native cancellation availability')
   assert(lifecycle.flush(q)=='failed','untrusted removed-action completion remains a generic failure')
  else
  if scenario=='cancel-direct'then CancelAction(0)else input.press(input.key)end
  assert(q.current==nil and #q.queue==0 and input.stops==1,
   'native shared cancellation helper must clear owned Lua wait then delegate the empty-stack native stop')
  assert(input.eaten==(scenario=='cancel-direct'and 0 or 1),'native key callback retains key consumption')
  s.item.container=nil;s.data.media=true;s.data.index=s.item:getRecordedMediaIndex()
  assert(lifecycle.flush(q)==nil and #q.queue==0 and not isPlayerDoingActionThatCanBeCancelled(f.player),
   'late exact media after native cancel cannot resurrect playback or reader')
  end
 elseif scenario=='running'or scenario=='sprinting'or scenario=='aiming'then
  f.player.isPlayerMoving=function()return scenario~='aiming'end
  f.player.pressedMovement=function()return scenario~='aiming'end
  f.player.isRunning=function()return scenario=='running'end;f.player.isSprinting=function()return scenario=='sprinting'end
  f.player.isAiming=function()return scenario=='aiming'end
  -- Match the public queue tick: native stop input revokes completion before
  -- observing effects that arrive in the very same tick.
  s.item.container=nil;s.data.media=true;s.data.index=s.item:getRecordedMediaIndex()
  q:tick()
  assert(q.current==nil and #q.queue==0,'native '..scenario..' stop condition must revoke the deferred media queue')
  assert(lifecycle.flush(q)==nil and tailStarts==0,'late effects cannot revive a native-input cancellation')
 end
 end
 local expectedTailStarts=expectTail and 1 or 0
 assert(serverData.consumed==1 and s.data.consumed==0 and tailStarts==expectedTailStarts,
  'media barrier must neither replay effects nor discard or start the independent reader early')
end
print('Media completed-receipt/replication order barrier and bounded failures passed.')

-- The reverse channel order is also valid: applying media/tape replication can
-- invalidate the still-active native insertion before Done reaches its update.
-- IsoGameCharacter checks native valid() before LuaTimedActionNew.update(); the
-- rejected native action calls its real Lua stop without any perform boundary.
for _,scenario in ipairs({'media','tape-debit','both','wrong-media','lost-tv','uncaptured','missing-ack',
 'changed-callback','canceled-ack','expired','moved-tape','not-started','stale-generation','queue-off','explicit-stop'})do
 local s=setup(true,nil,nil,true);local f=s.f;local reading=f.project('ActionQueueReading')
 local nativePresent,tailStarts,stopped,performed,now,forcedStop=true,0,false,0,1000,false
 getTimestampMs=function()return now end
 f.player.getCharacterActions=function()return {contains=function()return nativePresent end}end
 f.player.setIsFarming=function()end
 ISLogSystem={logAction=function()end}
 MoodleType={UNHAPPY='unhappy',DRUNK='drunk'}
 f.player.getMoodles=function()return {getMoodleLevel=function()return 0 end}end
 f.player.getTimedActionTimeModifier=function()return 1 end
 s.root.getItemById=function(_,id)if id==s.item:getID()and s.item.container==s.root then return s.item end end
 local head=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')})
 local insert=ISDeviceMediaAction:new(f.player,false,s.item,s.square);insert.toolkitQueueOperation={}
 local play=ISRadioAction:new('TogglePlayMedia',f.player,s.tv);play.toolkitQueueOperation={}
 local tail=f.action(ISReadABook,{item=f.item('Base.BookElectrician1'),begin=function()tailStarts=tailStarts+1 end})
 local q=f.queue(head,insert,play,tail)
 if scenario~='uncaptured'then reading.capture(q,2,3)end
 q.queue={insert,play,tail};q.current=insert
 insert.action={isStarted=function()return true end,finished=function()return false end,
  isForceComplete=function()return false end,hasStalled=function()return false end,
  forceStop=function()forcedStop=true end}
 local receipt={state='started'}
 PZSurvivorToolkit.ActionQueueAcknowledgements={capture=function(action)if action==insert and scenario~='missing-ack'then return receipt end end,
  state=function(_,record)assert(record==receipt);return receipt.state end,reset=function()end}
 local _,serverData,serverSquare=s.device();local serverTape=s.tape()
 local serverAction=ISDeviceMediaAction:new(f.player,false,serverTape,serverSquare)
 isClient,isServer=function()return false end,function()return true end
 assert(serverAction:complete()and serverData.consumed==1)
 isClient,isServer=function()return true end,function()return false end
 local firstPacket=(scenario=='media'or scenario=='tape-debit')and scenario or 'both'
 if scenario=='expired'then firstPacket='tape-debit'end
 if firstPacket=='media'or firstPacket=='both'then s.data.media=true;s.data.index=s.item:getRecordedMediaIndex()end
 if firstPacket=='tape-debit'or firstPacket=='both'then s.item.container=nil end
 if scenario=='wrong-media'then s.data.index=s.item:getRecordedMediaIndex()+1
 elseif scenario=='lost-tv'then s.tv.gone=true
 elseif scenario=='changed-callback'then insert.complete=function()error('changed callback must not execute')end
 elseif scenario=='canceled-ack'then receipt.state='canceled'
 elseif scenario=='moved-tape'then s.item.container=s.container('foreign-bag')
 elseif scenario=='not-started'then insert.action.isStarted=function()return false end
 elseif scenario=='queue-off'then PZSurvivorToolkit.Settings.actionQueue=function()return false end end
 local lifecycle=PZSurvivorToolkit.ActionQueueLifecycle
 local function nativeFrame(done)
  -- Match the engine's order: validity decides stop before update can observe
  -- Done; only the still-valid branch can reach native perform/completion.
  if not insert:isValid()or forcedStop then
   stopped=true;insert:stop();nativePresent=false;return
  end
  insert:update()
  if done then
   assert(lifecycle.begin(insert,'perform'))
   insert:perform();performed=performed+1
   lifecycle.finish(insert,'perform',true);nativePresent=false
  end
 end
 if scenario=='explicit-stop'then
  assert(insert:isValid(),'exact early effects may temporarily preserve client validity before explicit stop')
  insert:forceStop();nativeFrame(false)
 else nativeFrame(false)end
 if scenario=='stale-generation'then
  assert(not stopped and q.current==insert,'initial acknowledged packet order establishes its owned wait')
  q.toolkitOperationGeneration=(q.toolkitOperationGeneration or 0)+1;nativeFrame(false)
 end
 if scenario=='expired'then
  assert(not stopped and q.current==insert,'debit-first insertion may initially await media and Done')
  now=31001;nativeFrame(false)
 end
 local rejected=scenario~='media'and scenario~='tape-debit'and scenario~='both'
 if rejected then
  assert(stopped and performed==0 and q.current==nil and #q.queue==0 and tailStarts==0,
   'untrusted/unconfirmed early validity must retain native stop/reset behavior '..scenario)
 else
  if stopped then print('MEDIA_EARLY_REPLICATION observedQueueSize='..#q.queue..' firstPacket='..firstPacket..' receipt='..receipt.state)end
  assert(not stopped and q.current==insert and #q.queue==3 and q.queue[2]==play and q.queue[3]==tail and performed==0,
   'captured exact early replication must preserve client native validity while awaiting Done '..firstPacket)
  q:tick()
  assert(q.current==insert and tailStarts==0,'early effects cannot finish insertion before native Done')
  -- A client-only validity escape must never change authoritative validation.
  isClient,isServer=function()return false end,function()return true end
  assert(not insert:isValid(),'server validation must retain native media/tape ownership semantics')
  isClient,isServer=function()return true end,function()return false end
  s.data.media=true;s.data.index=s.item:getRecordedMediaIndex();s.item.container=nil
  receipt.state='completed'
  nativeFrame(true)
  assert(not stopped and performed==1,'native Done must reach actual perform exactly once after early replication')
  LuaTimedActionNew={new=function()return {isStarted=function()return false end}end}
  f.player.setTimedActionToRetrigger=function()end;f.player.StartAction=function()end
  q:tick()
  assert(q.current==play and q.queue[2]==tail and tailStarts==0,
   'confirmed native insertion after early replication must preserve expected playback and independent reader')
 end
 assert(serverData.consumed==1 and s.data.consumed==0,'early invalidation recovery cannot replay native insertion')
end
print('Media replication-before-Done native validity/stop ordering passed.')

-- Ordinary insertion has no promoted-reading capture. Execute native queue add,
-- begin/create/start and real ACK delivery; Java handles/frame order, server
-- DeviceData effects and packet delivery remain explicit models, not Java/network execution.
local function ordinary(enabled,wrapped,options)
 options=options or {}
 local s=setup(wrapped,options.changedSource,nil,true);local f=s.f
 local now,present,begun,forcedStop=1000,{}, {},false
 local input=options.cancel and nativeCancelHelpers(f.player)or nil
 f.project('ActionQueueReading') -- cancellation integration only; never capture a reading range.
 PZSurvivorToolkit.Settings.actionQueue=function()return enabled end
 isClient,isServer=function()return true end,function()return false end
 getTimestampMs=function()return now end
 f.player.getOnlineID=function()return 55 end
 f.player.setIsFarming=function()end;f.player.setTimedActionToRetrigger=function()end
 f.player.getCharacterActions=function()return {contains=function(_,handle)return present[handle]==true end}end
 MoodleType={UNHAPPY='unhappy',DRUNK='drunk'}
 f.player.getMoodles=function()return {getMoodleLevel=function(_,moodle)return options.adjusted and moodle==MoodleType.UNHAPPY and 4 or 0 end}end
 f.player.getTimedActionTimeModifier=function()return options.adjusted and 1.5 or 1 end
 DebugType={Action={warn=function()end}};ISLogSystem={logAction=function()end}
 s.root.getItemById=function(_,id)if id==s.item:getID()and s.item.container==s.root then return s.item end end
 s.data.isPlayingMedia=function(self)return self.playing==true end
 s.data.StartPlayMedia=function(self)self.playing=true end
 LuaTimedActionNew={new=function(action)
  return {table=action,started=false,isStarted=function(self)return self.started end,
   finished=function()return false end,isForceComplete=function()return false end,
   hasStalled=function()return false end,getJobDelta=function()return 0 end,
   forceStop=function()forcedStop=true end}
 end}
 f.player.StartAction=function(_,handle)
  assert(handle.table:isValid(),'ordinary native begin attempted invalid work')
  begun[#begun+1]=handle.table;present[handle]=true;handle.started=true;handle.table:start()
  -- Model ActionAcknowledgements.bind after the native start boundary.
  handle.table.toolkitNativeTransaction=13;handle.table.toolkitNativeKind=handle.table.Type
 end
 local insert=ISDeviceMediaAction:new(f.player,false,s.item,s.square)
 local play=ISRadioAction:new('TogglePlayMedia',f.player,s.tv)
 local q=f.queue()
 assert(q.toolkitOperationGeneration==nil and q.toolkitOperationsInvalid==nil,'exercise a fresh queue before its first disabled tick')
 ISTimedActionQueue.add(insert);ISTimedActionQueue.add(play)
 assert(q.current==insert and #q.queue==2 and begun[1]==insert and #begun==1 and play.action==nil)
 assert(insert.toolkitReadingMove==nil and play.toolkitReadingMove==nil,'ordinary insertion must not acquire promoted reading records')
 local token='00000000-0000-0000-0000-000000000013'
 local function ack(state)
  s.receive('PZSurvivorToolkitActions','State',{protocol=1,player=55,transaction=13,
   kind='ISDeviceMediaAction',token=token,state=state})
 end
 if not options.noAck then ack(options.terminalOnly and 'completed'or 'started')end
 local receipt=PZSurvivorToolkit.ActionQueueAcknowledgements.capture(insert)
 local generation=q.toolkitOperationGeneration or 0
 q:tick()
 assert(q.current==insert and #q.queue==2 and #begun==1,'initial native queue tick must retain started insertion')
 if receipt and s.installed then
  assert(PZSurvivorToolkit.ActionQueueAcknowledgements.capture(insert)==receipt,
   'first disabled tick must not invalidate the real started ACK captured after native begin')
  assert((q.toolkitOperationGeneration or 0)==generation,'ordinary begin must settle initial queue-off invalidation before ACK capture')
 end
 local _,serverData,serverSquare=s.device();local serverTape=s.tape()
 local serverInsert=ISDeviceMediaAction:new(f.player,false,serverTape,serverSquare)
 isClient,isServer=function()return false end,function()return true end
 assert(serverInsert:complete()and serverData.consumed==1 and serverTape.container==nil)
 isClient,isServer=function()return true end,function()return false end
 local function effects(kind)
  if kind~='tape' then s.data.media=true;s.data.index=s.item:getRecordedMediaIndex()end
  if kind~='media'then s.item.container=nil end
 end
 local function frame(done)
  -- Model IsoGameCharacter validity before LuaTimedActionNew observes Done.
  if not insert:isValid()or forcedStop then
   insert:stop();present[insert.action]=nil;return 'stopped'
  end
  insert:update()
  if done then
   local lifecycle=PZSurvivorToolkit.ActionQueueLifecycle
   assert(lifecycle.begin(insert,'perform'),'ordinary tracked insertion must enter the real completion barrier')
   insert:perform();lifecycle.finish(insert,'perform',true);present[insert.action]=nil
   return 'performed'
  end
  return 'waiting'
 end
 local function resetObserved()
  assert(q.current==nil and #q.queue==0 and #begun==1 and play.action==nil,
   'native failure/cancel must discard pending ordinary play without starting it')
 end
 local function finish()
  ack('completed');effects('both')
  assert(frame(true)=='performed');q:tick()
  assert(q.current==play and #q.queue==1 and begun[2]==play and #begun==2 and play:isValid(),
   'confirmed ordinary insertion must begin exact pending play once')
  q:tick();assert(q.current==play and #begun==2,'completion cannot replay playback begin')
  play:perform()
  assert(q.current==nil and #q.queue==0 and s.data.playing,'actual native play must play installed media')
 end
 return {s=s,f=f,q=q,insert=insert,play=play,ack=ack,effects=effects,frame=frame,finish=finish,
  resetObserved=resetObserved,input=input,begun=begun,serverData=serverData,expire=function()now=31001 end,
  noReplay=function()assert(serverData.consumed==1 and s.data.consumed==0,'client recovery must never invoke/replay insertion effects')end}
end

-- 1. Fresh queue on/off and each effects-first ordering, through real begin/create.
for _,enabled in ipairs({true,false})do
 for _,wrapped in ipairs({false,true})do
  for _,first in ipairs({'media','tape','both'})do
   local o=ordinary(enabled,wrapped);o.effects(first)
   assert(o.frame(false)=='waiting'and o.q.current==o.insert and #o.begun==1,
    'acknowledged ordinary early effects must survive validity-before-Done')
   isClient,isServer=function()return false end,function()return true end
   assert(o.insert:isValid()==(first=='tape'and not wrapped),
    'server must retain native empty-device and optional exact-root ownership validation')
   isClient,isServer=function()return true end,function()return false end
   o.finish();o.noReplay()
  end
 end
end

-- 2. Done/ACK first cannot begin play until both independent effects arrive.
for _,enabled in ipairs({true,false})do
 for _,first in ipairs({'media','tape'})do
  local o=ordinary(enabled,true);o.ack('completed');assert(o.frame(true)=='performed')
  o.q:tick();assert(o.q.current==o.insert and #o.begun==1)
  o.effects(first);o.q:tick();assert(o.q.current==o.insert and #o.begun==1,'one replicated effect cannot complete ordinary insertion')
  o.effects('both');o.q:tick()
  assert(o.q.current==o.play and #o.begun==2 and o.play:isValid())
  o.q:tick();assert(#o.begun==2);o.noReplay()
 end
end

-- 3. Native adjustment occurs after capture and must not revoke trusted completion.
for _,enabled in ipairs({true,false})do
 local o=ordinary(enabled,true,{adjusted=true})
 assert(o.insert.maxTime==90,'real native begin/create must apply adjusted duration')
 o.effects('both');assert(o.frame(false)=='waiting');o.finish();o.noReplay()
end

-- 4. Real ACK correlation, unsuccessful outcomes and bounded waiting.
for _,enabled in ipairs({true,false})do
 for _,failure in ipairs({'no-start','terminal-only','canceled','rejected','expired'})do
  local o=ordinary(enabled,true,{noAck=failure=='no-start',terminalOnly=failure=='terminal-only'})
  o.effects('both')
  if failure=='canceled'or failure=='rejected'then o.ack(failure)
  elseif failure=='expired'then
   assert(o.frame(false)=='waiting');o.expire()
  end
  assert(o.frame(false)=='stopped','ordinary unconfirmed/unsuccessful early effects must use native stop '..failure)
  o.resetObserved();o.noReplay()
 end
 -- After native removal, a failed terminal ACK must reset, without promoted cleanup.
 local o=ordinary(enabled,true);assert(o.frame(true)=='performed');o.q:tick()
 o.effects('both');o.ack('rejected');o.q:tick();o.resetObserved();o.noReplay()
end

-- 5. Expected media index alone cannot excuse a changed captured resource.
for _,enabled in ipairs({true,false})do
 for _,change in ipairs({'tape-object','tape-container','root','tv','device','wrong-index'})do
  local o=ordinary(enabled,true);o.effects('both')
  if change=='tape-object'then o.insert.secondaryItem=o.s.tape()
  elseif change=='tape-container'then o.s.item.container=o.s.container('foreign-bag')
  elseif change=='root'then o.f.player.inventory=o.s.container()
  elseif change=='tv'then o.s.tv.gone=true
  elseif change=='device'then
   local _,foreign=o.s.device();foreign.media=true;foreign.index=o.s.item:getRecordedMediaIndex();o.insert.deviceData=foreign
  else o.s.data.index=o.s.item:getRecordedMediaIndex()+1 end
  assert(o.frame(false)=='stopped','ordinary captured resource must reject '..change)
  o.resetObserved();o.noReplay()
 end
end

-- 6. Actual reset, native-handle replacement and generation change revoke receipts.
for _,enabled in ipairs({true,false})do
 for _,change in ipairs({'reset','handle','generation'})do
  local o=ordinary(enabled,true);o.effects('both');assert(o.frame(false)=='waiting')
  if change=='reset'then
   o.q:resetQueue();o.ack('completed');o.q:tick();o.resetObserved()
  else
   if change=='handle'then o.insert.action={isStarted=function()return true end}
   else o.q.toolkitOperationGeneration=(o.q.toolkitOperationGeneration or 0)+1 end
   o.ack('completed');assert(o.frame(false)=='stopped');o.resetObserved()
  end
  o.noReplay()
 end
end

-- 7. Explicit native stop and actual cancel-key callback also work with queue off.
for _,enabled in ipairs({true,false})do
 local o=ordinary(enabled,true);o.effects('both');assert(o.frame(false)=='waiting')
 o.insert:forceStop();assert(o.frame(false)=='stopped');o.resetObserved();o.noReplay()
 for _,kind in ipairs({'key','direct'})do
  o=ordinary(enabled,true,{cancel=true});assert(o.frame(true)=='performed');o.q:tick()
  assert(not o.input.nativePredicate(o.f.player)and isPlayerDoingActionThatCanBeCancelled(o.f.player),
   'ordinary deferred continuation must expose cancellation after Java removal')
  if kind=='key'then o.input.press(o.input.key)else CancelAction(0)end
  o.resetObserved();assert(o.input.stops==1 and o.input.eaten==(kind=='key'and 1 or 0))
  o.ack('completed');o.effects('both');o.q:tick();o.resetObserved();o.noReplay()
 end
end

-- 8. Common recovery retains existing source and callback trust boundaries.
for _,enabled in ipairs({true,false})do
 for _,change in ipairs({'callback','source'})do
  local o=ordinary(enabled,true,{changedSource=change=='source'and 'native'or nil});o.effects('both')
  if change=='callback'then o.insert.complete=function()error('foreign callback must not execute')end end
  assert(o.frame(false)=='stopped','common guard must not bless changed '..change)
  o.resetObserved();o.noReplay()
 end
end
print('Ordinary media queue on/off: actual native begin/create and real ACK listener; modeled Java/network effects, both completion orders, cancellation and fail-closed identity checks passed.')
