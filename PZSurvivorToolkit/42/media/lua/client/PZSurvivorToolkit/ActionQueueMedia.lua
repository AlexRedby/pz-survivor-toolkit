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
local source='native.device-media-insert'
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
local function callbacksTrusted(action,completing)
 if not unchanged()or getmetatable(action)~=snapshot.class or action.Type~=snapshot.class.Type
  or action.isRemove~=false or (not completing and action.maxTime~=30)or action.stopOnWalk~=false or action.stopOnRun~=true
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
-- Only a previously audited promoted insertion may use this lifecycle escape.
-- Opaque records retain the original identities even after their resources vanish.
function Media.capture(action)
 if not describe(action)then return end
 local root=action.character:getInventory()
 if not instanceof(root,'ItemContainer')then return end
 return {marker=captureMarker,action=action,tape=action.secondaryItem,data=action.deviceData,
  television=action.deviceData:getParent(),parameter=action.parameter,character=action.character,root=root,
  mediaIndex=action.secondaryItem:getRecordedMediaIndex(),mediaType=action.secondaryItem:getMediaType()}
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
   local reading=Toolkit.ActionQueueReading
   return reading and reading.keepPendingMedia and reading.keepPendingMedia(action)or false
  end
  methods.isValid=class.isValid
 end
 Toolkit.ActionQueueDefinitions.registerBehavior(source,{types={'ISDeviceMediaAction'},matches=Media.matches,inspect=Media.inspect})
 return unchanged()
end
return Media
