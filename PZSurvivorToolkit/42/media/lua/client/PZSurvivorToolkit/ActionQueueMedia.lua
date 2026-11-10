require 'PZSurvivorToolkit/ActionQueueDefinitions'
require 'TimedActions/ISDeviceBatteryAction'
require 'TimedActions/ISDeviceMediaAction'
local Target=require 'PZSurvivorToolkit/DeviceActionTarget'
local Toolkit=PZSurvivorToolkit
local OutcomeWait=require "PZSurvivorToolkit/ActionQueueOutcomeWait"
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
local batteryMarker={}
local batterySource='native.device-battery'
local targetAuthorizes=Target and Target.authorizes
local targetMatches=Target and Target.matches
local targetProof
local function ownedTarget(owner,name,callback)
 if not Target or Toolkit.DeviceActionTarget~=Target or Target.authorizes~=targetAuthorizes
  or Target.matches~=targetMatches or type(targetAuthorizes)~='function'then return false end
 if targetProof==nil then targetProof=Proof.matches('media/lua/shared/PZSurvivorToolkit/DeviceActionTarget.lua',3362273693,'PZSurvivorToolkit',true)end
 return targetProof and Proof.closure(targetAuthorizes,'DeviceActionTarget.lua')and targetAuthorizes(owner,name,callback)
end
local function binding(parameter,device,data)
 if parameter==device then
  return Target and Target.matches==targetMatches and targetMatches(parameter,device,data)
 end
 return instanceof(parameter,'IsoGridSquare')and device:getSquare()==parameter
  and parameter:getDeviceData()==data and device:getDeviceData()==data and data:getParent()==device
end
local function deviceEdit(action,device,data,battery)
 if action.action or action.started or action._isAddingActions
  or type(action.toolkitQueueOperation)=='table'and action.toolkitQueueOperation.toolkitStarted then return end
 local present=battery and data:getHasBattery()or not battery and data:hasMedia()
 if type(present)~='boolean'then return end
 local field=battery and 'battery'or 'media'
 local facts={[field]=present}
 local effects={{field=field,set=not action.isRemove}}
 if battery then
  local power=data:getPower()
  if type(power)~='number'or power~=power or power<0 or power>1 then return end
  facts.powered=power>0
  if action.isRemove then effects[#effects+1]={field='powered',set=false}
  else
   local charge=action.secondaryItem:getCurrentUsesFloat()
   if type(charge)~='number'or charge~=charge or charge<0 or charge>1 then return end
   effects[#effects+1]={field='powered',set=charge>0}
  end

 end
 local resources={{domain='device',key=device,facts=facts,requires={{field=field,equal=action.isRemove}},effects=effects}}
 if not action.isRemove then
  local item=action.secondaryItem
  local location=item:getContainer()
  if not instanceof(location,'ItemContainer')or battery and location:getItemWithID(item:getID())~=item then return end
  resources[#resources+1]={domain='item',key=item:getID(),facts={item=item,location=location},
   requires={battery and {field='location',notEqual=false}or {field='location',equal=action.character:getInventory()}},effects={{field='location',set=false}}}
 end
 -- Exact item locations are projected; native output capacity and any later
 -- transfer still require the existing conservative capacity check. No credit
 -- is granted for a future consumption or for a newly created ejected item.
 return {version=1,complete=true,capacity='external',resources=resources}
end
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
 -- Share exact native world binding with controls and constructor transport.
 if not instanceof(television,'IsoTelevision')or television:getObjectIndex()<0
  or not television:getSquare()or not binding(action.parameter,television,data) or data:getMediaType()~=1 then return end
 return {items={[tape:getID()]=true},itemTypes={[tape:getFullType()]=true},targets={[television]=true},
  cancelWaiting=true,interrupt='finish-step',capacityNonIncreasing=true,edit=deviceEdit(action,television,data)}
end
function Media.matches(action)return describe(action)~=nil end
function Media.inspect(action)return describe(action)end
function Media.isInstalled()return unchanged()end
-- Admission captures provenance before a world target can disappear. Unlike
-- inspect/describe this checks callbacks only, without dereferencing the target.
function Media.pendingDeviceSupported(action,completing)
 if not unchanged()or type(action.isRemove)~='boolean'then return false end
 if getmetatable(action)==snapshot.class then return callbacksTrusted(action,completing,action.isRemove)end
 if getmetatable(action)~=snapshot.helper or not snapshot.batteryTrusted
  or action.Type~=snapshot.helper.Type or not completing and action.maxTime~=30
  or action.stopOnWalk~=false or action.stopOnRun~=true or action.ignoreHandsWounds~=true
  or action.onStartFunc or action.onCompleteFunc or action.onCancelFunc or action.onFailFunc
  or action.additionalTest or action.retriggerLastAction then return false end
 for name,callback in pairs(snapshot.batteryMethods)do if (action[name]or false)~=callback then return false end end
 for name,callback in pairs(action)do
  if type(callback)=='function'and callback~=snapshot.batteryMethods[name]then return false end
 end
 return true
end
function Media.inspectBattery(action)
 if not Media.pendingDeviceSupported(action)or getmetatable(action)~=snapshot.helper
  or not instanceof(action.character,'IsoPlayer')or not instanceof(action.deviceData,'DeviceData')then return end
 local data=action.deviceData
 local device=data:getParent()
 if not instanceof(device,'IsoRadio')or not binding(action.parameter,device,data)
  or data:getIsBatteryPowered()~=true or not data:isIsoDevice()or data:isVehicleDevice()then return end
 local item=action.secondaryItem
 if action.isRemove then if item~=nil then return end
 elseif not instanceof(item,'DrainableComboItem')or item:getFullType()~='Base.Battery'
  or not instanceof(item:getContainer(),'ItemContainer')then return end
 return {items=item and {[item:getID()]=true}or {},itemTypes=item and {[item:getFullType()]=true}or {},
  targets={[device]=true},cancelWaiting=true,interrupt='finish-step',capacityNonIncreasing=not action.isRemove,
  edit=deviceEdit(action,device,data,true)}
end
function Media.matchesBattery(action)return Media.inspectBattery(action)~=nil end
-- Ejection creates a new item ID; it does not restore the original inserted item.
-- Keep insertion's public receipt separate: reading promotion consumes that API.
local function ejectTarget(action,completing)
 if not callbacksTrusted(action,completing,true)or action.secondaryItem~=nil then return end
 local data=action.deviceData
 if not instanceof(data,'DeviceData')or data:getMediaType()~=1 then return end
 local television=data:getParent()
 if not instanceof(television,'IsoTelevision')or television:getObjectIndex()<0
  or not television:getSquare()or not binding(action.parameter,television,data) then return end
 return television,data
end
function Media.inspectEject(action)
 local tv=ejectTarget(action)
 if not tv then return end
 -- Returning a VHS increases carried weight. Never call this capacity-neutral.
 return {items={},targets={[tv]=true},cancelWaiting=true,interrupt='finish-step',
  edit=deviceEdit(action,tv,action.deviceData)}
end
function Media.matchesEject(action)return Media.inspectEject(action)~=nil end
local function carriedIDs(root)
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
 return ids
end
function Media.captureEject(action)
 local television,data=ejectTarget(action)
 if not television then return end
 local root=action.character:getInventory()
 if not instanceof(root,'ItemContainer')or not data:hasMedia()then return end
 local index=data:getMediaIndex()
 if type(index)~='number'or index<0 or index%1~=0 then return end
 local ids=carriedIDs(root)
 if not ids then return end
 return {marker=ejectMarker,action=action,character=action.character,root=root,
  television=television,data=data,parameter=action.parameter,mediaIndex=index,mediaType=data:getMediaType(),ids=ids}
end
local function ejectState(action,saved)
 if type(saved)~='table'or saved.marker~=ejectMarker or saved.action~=action
  or not callbacksTrusted(action,true,true)or action.secondaryItem~=nil
  or action.character~=saved.character or action.character:getInventory()~=saved.root
  or action.deviceData~=saved.data or action.parameter~=saved.parameter then return end
 local tv,data=saved.television,saved.data
 if tv:getObjectIndex()<0 or not binding(saved.parameter,tv,data)
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
local function captureBattery(action)
 if not Media.inspectBattery(action)then return end
 local data,root=action.deviceData,action.character:getInventory()
 if not instanceof(root,'ItemContainer')or data:getHasBattery()~=action.isRemove then return end
 local item=action.secondaryItem
 local record={marker=batteryMarker,action=action,character=action.character,root=root,
  device=data:getParent(),data=data,parameter=action.parameter,remove=action.isRemove,power=data:getPower()}
 if type(record.power)~='number'or record.power~=record.power or record.power<0 or record.power>1 then return end
 if action.isRemove then
  record.ids=carriedIDs(root)
  if not record.ids then return end
 else
  record.container=item:getContainer()
  if not instanceof(record.container,'ItemContainer')or record.container:getItemWithID(item:getID())~=item then return end
  record.tape,record.tapeID,record.fullType=item,item:getID(),item:getFullType()
  record.charge=item:getCurrentUsesFloat()
 end
 return record
end
local function batteryState(action,saved)
 if type(saved)~='table'or saved.marker~=batteryMarker or saved.action~=action
  or not Media.pendingDeviceSupported(action,true)or getmetatable(action)~=snapshot.helper
  or action.character~=saved.character or action.character:getInventory()~=saved.root
  or action.deviceData~=saved.data or action.parameter~=saved.parameter or action.isRemove~=saved.remove
  or action.secondaryItem~=saved.tape then return end
 local data=saved.data
 if not binding(saved.parameter,saved.device,data)or data:getIsBatteryPowered()~=true then return 'unavailable'end
 local present,power=data:getHasBattery(),data:getPower()
 if type(present)~='boolean'or type(power)~='number'or power~=power or power<0 or power>1
  or not present and power~=0 then return 'unavailable'end
 if not saved.remove then
  if saved.tape:getID()~=saved.tapeID or saved.tape:getFullType()~=saved.fullType
   or present and power>saved.charge+0.000001 then return 'unavailable'end
  local container=saved.tape:getContainer()
  if container and container~=saved.container then return 'unavailable'end
  local spent=not container and not saved.container:getItemWithID(saved.tapeID)
   and not saved.root:getItemById(saved.tapeID)
  if present and spent then return 'matched',true end
  return 'waiting',present or spent
 end
 local output,count,items=nil,0,saved.root:getItems()
 for index=0,items:size()-1 do
  local item=items:get(index)
  if not saved.ids[item:getID()]and item:getContainer()==saved.root
   and instanceof(item,'DrainableComboItem')and item:getFullType()=='Base.Battery'then output,count=item,count+1 end
 end
 if count>1 or saved.outputID and(not output or output:getID()~=saved.outputID)then return 'unavailable'end
 if output then
  local uses,maximum=output:getCurrentUses(),output:getMaxUses()
  -- A powered radio can drain during the native action. The new battery may
  -- contain that lower, quantized charge. Allow the native binary32 product
  -- rounding at an integer boundary (Lua arithmetic is binary64). This is an
  -- upper bound, not a claim of the exact server output charge.
  if type(uses)~='number'or type(maximum)~='number'or maximum<=0 or maximum%1~=0
   or uses<0 or uses%1~=0 or uses>math.floor(saved.power*maximum+maximum*0.00000012)then return 'unavailable'end
  saved.outputID=output:getID()
 end
 if output and not present then return 'matched',true end
 return 'waiting',output~=nil or not present
end
local function completionState(action,record)
 if record.marker==batteryMarker then return batteryState(action,record)end
 if record.marker==ejectMarker then return ejectState(action,record)end
 return Media.completionState(action,record)
end
local function replicatedEffect(action,record)
 if record.marker==batteryMarker then local state,effect=batteryState(action,record);return state~=nil and state~='unavailable'and effect==true end
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
 if tv:getObjectIndex()<0 or not binding(saved.parameter,tv,data) then return 'unavailable' end
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
 if tv:getObjectIndex()<0 or not binding(saved.parameter,tv,data) then return true end
 return saved.tape:getContainer()~=saved.root or data:hasMedia()
end

-- Ordinary media actions also race with device/item replication. Capture only at
-- native begin, after pickups, while the exact input or inserted media still exists.
-- Promoted reading retains its separate dependency cleanup and failure policy.
function Media.start(action)
 active[action]=nil
 if not isClient()or action.Type~='ISDeviceMediaAction'and action.Type~='ISDeviceBatteryAction'
  or action.action or action.toolkitReadingMove then return end
 local record
 if action.Type=='ISDeviceBatteryAction'then record=captureBattery(action)
 else record=action.isRemove and Media.captureEject(action)or Media.capture(action)end
 local queue=ISTimedActionQueue.queues[action.character]
 if not record or not queue or queue.current~=action or queue.queue[1]~=action
  or not Toolkit.ActionQueuePolicy.live(queue)then return end
 if record.marker==captureMarker and(record.tape:getContainer()~=record.root
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
function Media.keepPending(action)
 local record=currentRecord(action)
 if not record or not action.action:isStarted()
  or not replicatedEffect(action,record.receipt)then return false end
 local wait,state=OutcomeWait.observe(record.queue,action,record.wait)
 record.wait=wait
 return wait~=nil and(state=='started'or state=='completed')and not OutcomeWait.expired(wait)
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
 local inputContainer=record.receipt.marker==batteryMarker and record.receipt.container or record.receipt.root
 if not result or result=='unavailable'
  or container and container~=inputContainer
  or (action.stopOnRun and (player:isRunning()or player:isSprinting())and player:isPlayerMoving())
  or (action.stopOnWalk and player:isPlayerMoving())or (action.stopOnAim and player:isAiming())then return 'failed' end
 local wait,state=OutcomeWait.observe(record.queue,action,record.wait)
 record.wait=wait
 -- Without the supported started receipt there is no permission to replace
 -- native completion. Never fabricate an outcome or replay the server effect.
 if not wait then active[action]=nil;return end
 if state=='completed'and result=='matched'then active[action]=nil;return end
 if not state or state=='canceled'or state=='rejected'or OutcomeWait.expired(wait)then return 'failed' end
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
 local methods,ownMethods,binding={},{}
 for name,callback in pairs(class)do
  if type(callback)=='function'then
   methods[name],ownMethods[name]=callback,true
   if name~='derive'then
    local approved=false
    if name=='isValid'and from(callback,'TVMediaAction.lua')
     and Proof.matches('media/lua/shared/PZSurvivorToolkit/TVMediaAction.lua',1822636926,'PZSurvivorToolkit',true)
     and from(Toolkit.TVMediaActionBinding,'TVMediaAction.lua')then
     local ok,owner,previous,replacement=pcall(Toolkit.TVMediaActionBinding)
     approved=ok and owner==class and replacement==callback
      and (from(previous,'ISDeviceMediaAction.lua')or ownedTarget(class,'isValid',previous))
     if approved then binding=Toolkit.TVMediaActionBinding end
    end
    trusted=trusted and (from(callback,'ISDeviceMediaAction.lua')or approved or ownedTarget(class,name,callback))
   end
  end
 end
 for _,name in ipairs(lifecycle)do
  local callback=class[name];methods[name]=callback or false
  if callback and not ownMethods[name]then
   trusted=trusted and (from(callback,'ISBaseTimedAction.lua')
    or (name=='begin'or name=='stop')and from(callback,'ActionQueue.lua'))
  end
 end
 local helperMethods={getDeviceDataParameter=helper.getDeviceDataParameter,getDeviceDataFromParameter=helper.getDeviceDataFromParameter}
 for name,callback in pairs(helperMethods)do
  trusted=trusted and (from(callback,'ISDeviceBatteryAction.lua')or ownedTarget(helper,name,callback))
 end
 local batteryMethods,batteryOwn,batteryTrusted={},{},trusted
 for name,callback in pairs(helper)do
  if type(callback)=='function'then
   batteryMethods[name],batteryOwn[name]=callback,true
   if name~='derive'then batteryTrusted=batteryTrusted and (from(callback,'ISDeviceBatteryAction.lua')or ownedTarget(helper,name,callback))end
  end
 end
 for _,name in ipairs(lifecycle)do
  local callback=helper[name];batteryMethods[name]=callback or false
  if callback and not batteryOwn[name]then
   batteryTrusted=batteryTrusted and (from(callback,'ISBaseTimedAction.lua')
    or (name=='begin'or name=='stop')and from(callback,'ActionQueue.lua'))
  end
 end
 local baseMethods={new=base.new,perform=base.perform}
 for _,callback in pairs(baseMethods)do trusted=trusted and from(callback,'ISBaseTimedAction.lua')end
 snapshot={class=class,helper=helper,base=base,methods=methods,helperMethods=helperMethods,baseMethods=baseMethods,
  binding=binding,trusted=trusted,batteryMethods=batteryMethods,batteryTrusted=batteryTrusted}
 if trusted then
  local nativeValid=class.isValid
  class.isValid=function(action)
   if nativeValid(action)then return true end
   if Media.keepPending(action)then return true end
   local reading=Toolkit.ActionQueueReading
   return reading and reading.keepPendingMedia and reading.keepPendingMedia(action)or false
  end
  methods.isValid=class.isValid
  if batteryTrusted then
   local batteryValid=helper.isValid
   helper.isValid=function(action)
    if batteryValid(action)then return true end
    return Media.keepPending(action)
   end
   batteryMethods.isValid=helper.isValid
  end
 end
 Toolkit.ActionQueueDefinitions.registerBehavior(source,{types={'ISDeviceMediaAction'},matches=Media.matches,inspect=Media.inspect})
 Toolkit.ActionQueueDefinitions.registerBehavior(batterySource,{types={'ISDeviceBatteryAction'},matches=Media.matchesBattery,inspect=Media.inspectBattery})
 Toolkit.ActionQueueDefinitions.registerBehavior(ejectSource,{types={'ISDeviceMediaAction'},matches=Media.matchesEject,inspect=Media.inspectEject})
 return unchanged()
end
return Media
