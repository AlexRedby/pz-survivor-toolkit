require 'PZSurvivorToolkit/ActionQueueDefinitions'
require 'TimedActions/ISDeviceBatteryAction'
require 'TimedActions/ISDeviceMediaAction'
local Toolkit=PZSurvivorToolkit
local Media={}
Toolkit.ActionQueueMedia=Media
local Proof=require 'PZSurvivorToolkit/SourceProof'
local lifecycle={'new','begin','create','adjustMaxTime','isValid','isValidStart','waitToStart','start','update','stop','perform','complete',
 'getDuration','serverStart','serverStop','animEvent','forceComplete','forceStop','forceCancel','invoke'}
local snapshot
local captureMarker={}
local active=setmetatable({},{__mode='k'})
local source='native.device-media-insert'
local ejectSource='native.device-media-eject'
local ejectMarker={}
local function from(callback,file)return type(callback)=='function'and Proof.closure(callback,file)end
local function unchanged()
 local saved=snapshot
 if not saved or not saved.trusted or ISDeviceMediaAction~=saved.class or ISDeviceBatteryAction~=saved.helper
  or ISBaseTimedAction~=saved.base or PZSurvivorToolkit~=Toolkit
  or saved.binding and Toolkit.TVMediaActionBinding~=saved.binding then return false end
 for name,callback in pairs(saved.methods)do if (saved.class[name]or false)~=callback then return false end end
 for name,callback in pairs(saved.helperMethods)do if saved.helper[name]~=callback then return false end end
 for name,callback in pairs(saved.baseMethods)do if saved.base[name]~=callback then return false end end
 for name,callback in pairs(saved.class)do
  if type(callback)=='function'and saved.methods[name]~=callback then return false end
 end
 return true
end
local function callbacksTrusted(action,completing,removing)
 if not unchanged()or getmetatable(action)~=snapshot.class or action.Type~=snapshot.class.Type
  or action.isRemove~=(removing==true) or (not completing and action.maxTime~=30)or action.stopOnWalk~=false or action.stopOnRun~=true
  or action.ignoreHandsWounds~=true or not instanceof(action.character,'IsoPlayer')
  or action.onStartFunc or action.onCompleteFunc or action.onCancelFunc or action.retriggerLastAction
  or action.onFailFunc or action.additionalTest then return false end
 for name,callback in pairs(snapshot.methods)do if (action[name]or false)~=callback then return false end end
 for name,callback in pairs(action)do
  if type(callback)=='function'and callback~=snapshot.methods[name]then return false end
 end
 return true
end
local function describe(action)
 if not callbacksTrusted(action)then return end
 local tape,data=action.secondaryItem,action.deviceData
 if not instanceof(tape,'InventoryItem')or not tape:isRecordedMedia()or tape:getMediaType()~=1
  or not instanceof(tape:getContainer(),'ItemContainer')or not instanceof(data,'DeviceData')then return end
 local television=data:getParent()
 -- World TV insertion resolves DeviceData through a square in the native constructor.
 -- Preserve that exact binding and share its object target with native radio controls.
 if not instanceof(television,'IsoTelevision')or television:getObjectIndex()<0
  or not television:getSquare()or action.parameter~=television:getSquare()
  or action.parameter:getDeviceData()~=data or television:getDeviceData()~=data or data:getMediaType()~=1 then return end
 return {items={[tape:getID()]=true},itemTypes={[tape:getFullType()]=true},targets={[television]=true},
  cancelWaiting=true,interrupt='finish-step',capacityNonIncreasing=true}
end
function Media.matches(action)return describe(action)~=nil end
function Media.inspect(action)return describe(action)end
function Media.isInstalled()return unchanged()end
-- Ejection creates a new item ID; it does not restore the original inserted item.
-- Keep insertion's public receipt separate: reading promotion consumes that API.
local function ejectTarget(action,completing)
 if not callbacksTrusted(action,completing,true)or action.secondaryItem~=nil then return end
 local data=action.deviceData
 if not instanceof(data,'DeviceData')or data:getMediaType()~=1 then return end
 local television=data:getParent()
 if not instanceof(television,'IsoTelevision')or television:getObjectIndex()<0
  or not television:getSquare()or action.parameter~=television:getSquare()
  or action.parameter:getDeviceData()~=data or television:getDeviceData()~=data then return end
 return television,data
end
function Media.inspectEject(action)
 local tv=ejectTarget(action)
 if not tv then return end
 -- Returning a VHS increases carried weight. Never call this capacity-neutral.
 return {items={},targets={[tv]=true},cancelWaiting=true,interrupt='finish-step'}
end
function Media.matchesEject(action)return Media.inspectEject(action)~=nil end
function Media.captureEject(action)
 local television,data=ejectTarget(action)
 if not television then return end
 local root=action.character:getInventory()
 if not instanceof(root,'ItemContainer')or not data:hasMedia()then return end
 local index=data:getMediaIndex()
 if type(index)~='number'or index<0 or index%1~=0 then return end
 local ids,seen={},{}
 local function capture(container)
  if not instanceof(container,'ItemContainer')or seen[container]then return false end
  seen[container]=true
  local items=container:getItems()
  for i=0,items:size()-1 do
   local item=items:get(i);local id=item:getID()
   if ids[id]then return false end
   ids[id]=true
   if instanceof(item,'InventoryContainer')and not capture(item:getInventory())then return false end
  end
  return true
 end
 -- A pre-existing tape moved out of a worn bag is not the native new output.
 if not capture(root)then return end
 return {marker=ejectMarker,action=action,character=action.character,root=root,
  television=television,data=data,parameter=action.parameter,mediaIndex=index,mediaType=data:getMediaType(),ids=ids}
end
local function ejectState(action,saved)
 if type(saved)~='table'or saved.marker~=ejectMarker or saved.action~=action
  or not callbacksTrusted(action,true,true)or action.secondaryItem~=nil
  or action.character~=saved.character or action.character:getInventory()~=saved.root
  or action.deviceData~=saved.data or action.parameter~=saved.parameter then return end
 local tv,data=saved.television,saved.data
 if tv:getObjectIndex()<0 or tv:getSquare()~=saved.parameter or data:getParent()~=tv
  or tv:getDeviceData()~=data or saved.parameter:getDeviceData()~=data
  or data:getMediaType()~=saved.mediaType
  or data:hasMedia()and data:getMediaIndex()~=saved.mediaIndex
  or not data:hasMedia()and data:getMediaIndex()~=-1 then return 'unavailable' end
 local output,count,items=nil,0,saved.root:getItems()
 for i=0,items:size()-1 do
  local item=items:get(i)
  if not saved.ids[item:getID()]and item:getContainer()==saved.root and item:isRecordedMedia()
   and item:getRecordedMediaIndex()==saved.mediaIndex and item:getMediaType()==saved.mediaType then
   output,count=item,count+1
  end
 end
 if count>1 or saved.outputID and(not output or output:getID()~=saved.outputID
  or output:getFullType()~=saved.outputType)then return 'unavailable' end
 if output then saved.outputID,saved.outputType=output:getID(),output:getFullType()end
 if output and not data:hasMedia()then return 'matched',true end
 return 'waiting',output~=nil or not data:hasMedia()
end
function Media.ejectCompletionState(action,record)return ejectState(action,record)end
-- An unavailable, audited TV command has no effect to replay. Native stop may
-- discard that operation, but must not erase unrelated work when queue editing is on.
function Media.canSkipUnavailable(action)
 if not Toolkit.Settings.actionQueue()then return false end
 local tv,data=ejectTarget(action,true)
 if tv then return not data:hasMedia()end
 local adapters=Toolkit.ActionQueueEditAdapters
 if not adapters or not adapters.radioCallbacksTrusted(action)then return false end
 tv,data=action.device,action.deviceData
 if not instanceof(tv,'IsoTelevision')or not instanceof(data,'DeviceData')
  or data:getParent()~=tv or tv:getDeviceData()~=data then return false end
 if tv:getObjectIndex()<0 or not tv:getSquare()then return true end
 return not action:isValid()
end
local function completionState(action,record)
 if record.marker==ejectMarker then return ejectState(action,record)end
 return Media.completionState(action,record)
end
local function replicatedEffect(action,record)
 if record.marker==ejectMarker then local state,effect=ejectState(action,record);return state~=nil and state~='unavailable'and effect==true end
 return Media.hasReplicatedEffect(action,record)
end
-- Only a previously audited insertion may use this lifecycle escape.
-- Opaque records retain the original identities even after their resources vanish.
function Media.capture(action)
 if not describe(action)then return end
 local root=action.character:getInventory()
 if not instanceof(root,'ItemContainer')then return end
 return {marker=captureMarker,action=action,tape=action.secondaryItem,data=action.deviceData,
  television=action.deviceData:getParent(),parameter=action.parameter,character=action.character,root=root,
  mediaIndex=action.secondaryItem:getRecordedMediaIndex(),mediaType=action.secondaryItem:getMediaType(),
  tapeID=action.secondaryItem:getID(),fullType=action.secondaryItem:getFullType(),container=action.secondaryItem:getContainer()}
end
-- A completed native Host pickup replaces the client item, then rebinds direct
-- queued-action fields by ID. Nested receipts are not part of that engine step.
-- Reading supplies the confirmed, captured pickup; never refresh a begun insert.
function Media.afterPickup(action,saved,pickup)
 if not isClient()or action.action or type(saved)~='table'or saved.marker~=captureMarker
  or saved.action~=action or saved.container==saved.root or saved.tape:getContainer()~=nil
  or pickup.srcContainer~=saved.container or pickup.destContainer~=saved.root then return end
 local nextRecord=Media.capture(action)
 -- Native perform may restore its old item from the nested transfer queueList.
 if not nextRecord or nextRecord.tape==saved.tape or pickup.item~=saved.tape and pickup.item~=nextRecord.tape
  or nextRecord.character~=saved.character or nextRecord.root~=saved.root or nextRecord.data~=saved.data
  or nextRecord.television~=saved.television or nextRecord.parameter~=saved.parameter
  or nextRecord.tapeID~=saved.tapeID or nextRecord.fullType~=saved.fullType
  or nextRecord.mediaIndex~=saved.mediaIndex or nextRecord.mediaType~=saved.mediaType
  or nextRecord.container~=saved.root or saved.root:getItemById(saved.tapeID)~=nextRecord.tape
  or saved.container:getItemById(saved.tapeID)or saved.data:hasMedia()then return end
 local items,count=saved.root:getItems(),0
 for i=0,items:size()-1 do if items:get(i):getID()==saved.tapeID then count=count+1 end end
 if count==1 then return nextRecord end
end
-- Native create adjusts duration for moodles. Completion only observes the exact
-- previously captured insertion; it grants no new permission to execute an action.
function Media.completionState(action,record)
 local saved=record
 if type(saved)~='table'or saved.marker~=captureMarker or saved.action~=action or not callbacksTrusted(action,true)
  or action.character~=saved.character or action.secondaryItem~=saved.tape
  or action.deviceData~=saved.data or action.parameter~=saved.parameter
  or action.character:getInventory()~=saved.root then return end
 local tv,data=saved.television,saved.data
 if tv:getObjectIndex()<0 or tv:getSquare()~=saved.parameter or data:getParent()~=tv
  or tv:getDeviceData()~=data or saved.parameter:getDeviceData()~=data then return 'unavailable' end
 if data:hasMedia()then
  if data:getMediaIndex()~=saved.mediaIndex or data:getMediaType()~=saved.mediaType then return 'unavailable' end
  if not saved.root:getItemById(saved.tape:getID())then return 'matched' end
 end
 return 'waiting'
end
-- Device media and the exact tape debit may arrive separately, before native
-- Done. A moved tape or a different cassette is not an expected server effect.
function Media.hasReplicatedEffect(action,record)
 local state=Media.completionState(action,record)
 if not state or state=='unavailable'then return false end
 local container=record.tape:getContainer()
 if container and container~=record.root then return false end
 return record.data:hasMedia()or not container and not record.root:getItemById(record.tape:getID())
end
function Media.canSkip(action,record)
 local saved=record
 if type(saved)~='table'or saved.marker~=captureMarker or saved.action~=action or not callbacksTrusted(action)or action.action
  or action.character~=saved.character or action.secondaryItem~=saved.tape
  or action.deviceData~=saved.data or action.parameter~=saved.parameter
  or action.character:getInventory()~=saved.root then return false end
 local tv,data=saved.television,saved.data
 if tv:getObjectIndex()<0 or tv:getSquare()~=saved.parameter or data:getParent()~=tv
  or tv:getDeviceData()~=data or saved.parameter:getDeviceData()~=data then return true end
 return saved.tape:getContainer()~=saved.root or data:hasMedia()
end

-- Ordinary media actions also race with device/item replication. Capture only at
-- native begin, after pickups, while the exact input or inserted media still exists.
-- Promoted reading retains its separate dependency cleanup and failure policy.
function Media.start(action)
 active[action]=nil
 if not isClient()or action.Type~='ISDeviceMediaAction'or action.action or action.toolkitReadingMove then return end
 local record=action.isRemove and Media.captureEject(action)or Media.capture(action)
 local queue=ISTimedActionQueue.queues[action.character]
 if not record or not queue or queue.current~=action or queue.queue[1]~=action
  or not Toolkit.ActionQueuePolicy.live(queue)then return end
 if record.marker~=ejectMarker and(record.tape:getContainer()~=record.root
  or record.root:getItemById(record.tape:getID())~=record.tape or record.data:hasMedia())then return end
 active[action]={receipt=record,queue=queue,generation=queue.toolkitOperationGeneration or 0,
  enabled=Toolkit.Settings.actionQueue()}
end
function Media.bind(action)
 local record=active[action]
 if record then
  if action.action then record.native=action.action else active[action]=nil end
 end
end
function Media.stop(action)active[action]=nil end
function Media.reset(queue)
 for action,record in pairs(active)do if record.queue==queue then active[action]=nil end end
end
function Media.tracks(action)return action~=nil and active[action]~=nil end
local function currentRecord(action)
 local record=active[action]
 local queue=record and record.queue
 if not record or not isClient()or not record.native or record.native~=action.action
  or ISTimedActionQueue.queues[action.character]~=queue or queue.current~=action or queue.queue[1]~=action
  or not Toolkit.ActionQueuePolicy.live(queue)or queue.toolkitCancel
  or record.generation~=(queue.toolkitOperationGeneration or 0)
  or record.enabled~=Toolkit.Settings.actionQueue()then return end
 return record
end
local function acknowledgement(action,record)
 local acknowledgements=Toolkit.ActionQueueAcknowledgements
 if not record.acknowledgement then
  record.acknowledgement=acknowledgements and acknowledgements.capture(action)
  if record.acknowledgement then record.deadline=getTimestampMs()+30000 end
 end
 return record.acknowledgement and acknowledgements.state(action,record.acknowledgement)
end
function Media.keepPending(action)
 local record=currentRecord(action)
 if not record or not action.action:isStarted()
  or not replicatedEffect(action,record.receipt)then return false end
 local state=acknowledgement(action,record)
 return (state=='started'or state=='completed')and getTimestampMs()<record.deadline
end
function Media.canCancelWait(action)
 local record=currentRecord(action)
 return record~=nil and completionState(action,record.receipt)~=nil
end
function Media.continuationState(action)
 if not Media.tracks(action)then return end
 local record=currentRecord(action)
 if not record then return 'failed' end
 local result=completionState(action,record.receipt)
 local player=action.character
 local container=record.receipt.tape and record.receipt.tape:getContainer()
 if not result or result=='unavailable'
  or container and container~=record.receipt.root
  or (action.stopOnRun and (player:isRunning()or player:isSprinting())and player:isPlayerMoving())
  or (action.stopOnWalk and player:isPlayerMoving())or (action.stopOnAim and player:isAiming())then return 'failed' end
 local state=acknowledgement(action,record)
 -- Without the supported started receipt there is no permission to replace
 -- native completion. Never fabricate an outcome or replay the server effect.
 if not record.acknowledgement then active[action]=nil;return end
 if state=='completed'and result=='matched'then active[action]=nil;return end
 if not state or state=='canceled'or state=='rejected'or getTimestampMs()>=record.deadline then return 'failed' end
 return 'waiting'
end
-- Install after ActionQueue's inherited native stop/begin hooks are in place. No
-- producer is wrapped: existing UI scopes retain native pickup/walk/insert order.
function Media.install()
 if snapshot then return unchanged()end
 local class,helper,base=ISDeviceMediaAction,ISDeviceBatteryAction,ISBaseTimedAction
 local trusted=Proof.matches('media/lua/shared/TimedActions/ISDeviceMediaAction.lua',553760800,nil,true)
  and Proof.matches('media/lua/shared/TimedActions/ISDeviceBatteryAction.lua',1917423720,nil,true)
  and Proof.matches('media/lua/shared/TimedActions/ISBaseTimedAction.lua',3104185167,nil,true)
 local methods,binding={}
 for name,callback in pairs(class)do
  if type(callback)=='function'then
   methods[name]=callback
   if name~='derive'then
    local approved=false
    if name=='isValid'and from(callback,'TVMediaAction.lua')
     and Proof.matches('media/lua/shared/PZSurvivorToolkit/TVMediaAction.lua',1224616399,'PZSurvivorToolkit',true)
     and from(Toolkit.TVMediaActionBinding,'TVMediaAction.lua')then
     local ok,owner,previous,replacement=pcall(Toolkit.TVMediaActionBinding)
     approved=ok and owner==class and replacement==callback and from(previous,'ISDeviceMediaAction.lua')
     if approved then binding=Toolkit.TVMediaActionBinding end
    end
    trusted=trusted and (from(callback,'ISDeviceMediaAction.lua')or approved)
   end
  end
 end
 for _,name in ipairs(lifecycle)do
  local callback=class[name];methods[name]=callback or false
  if callback and not rawget(class,name)then
   trusted=trusted and (from(callback,'ISBaseTimedAction.lua')
    or (name=='begin'or name=='stop')and from(callback,'ActionQueue.lua'))
  end
 end
 local helperMethods={getDeviceDataParameter=helper.getDeviceDataParameter,getDeviceDataFromParameter=helper.getDeviceDataFromParameter}
 for _,callback in pairs(helperMethods)do trusted=trusted and from(callback,'ISDeviceBatteryAction.lua')end
 local baseMethods={new=base.new,perform=base.perform}
 for _,callback in pairs(baseMethods)do trusted=trusted and from(callback,'ISBaseTimedAction.lua')end
 snapshot={class=class,helper=helper,base=base,methods=methods,helperMethods=helperMethods,baseMethods=baseMethods,
  binding=binding,trusted=trusted}
 if trusted then
  local nativeValid=class.isValid
  class.isValid=function(action)
   if nativeValid(action)then return true end
   if Media.keepPending(action)then return true end
   local reading=Toolkit.ActionQueueReading
   return reading and reading.keepPendingMedia and reading.keepPendingMedia(action)or false
  end
  methods.isValid=class.isValid
 end
 Toolkit.ActionQueueDefinitions.registerBehavior(source,{types={'ISDeviceMediaAction'},matches=Media.matches,inspect=Media.inspect})
 Toolkit.ActionQueueDefinitions.registerBehavior(ejectSource,{types={'ISDeviceMediaAction'},matches=Media.matchesEject,inspect=Media.inspectEject})
 return unchanged()
end
return Media
