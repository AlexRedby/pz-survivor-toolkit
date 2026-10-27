require 'TimedActions/ISCutHair'
require 'TimedActions/ISTrimBeard'
require 'TimedActions/ISDyeHair'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Pending=require 'PZSurvivorToolkit/ActionQueueGroomingPending'
local applyPending=Pending and Pending.apply
local adoptPending=Pending and Pending.adoptBase
local Grooming={}
local base=ISBaseTimedAction
local toolkit=PZSurvivorToolkit
local lifecycle,stopBridge,acknowledgements,captureReceipt,receiptState
local installedPolicy,installedResources
local profiles={
 {name='ISCutHair',pin=1007133567,field='item',sound=true},
 {name='ISTrimBeard',pin=1652611680,field='item',sound=true},
 {name='ISDyeHair',pin=1341745692,field='hairDye'},
}
for _,profile in ipairs(profiles)do profile.class=_G[profile.name]end

local function capture(profile)
 local class=profile.class
 if ISBaseTimedAction~=base or not Proof.closure(base.new,'ISBaseTimedAction.lua')
  or type(class)~='table'or _G[profile.name]~=class or class.Type~=profile.name
  or not Proof.matches('media/lua/shared/TimedActions/'..profile.name..'.lua',profile.pin,nil,true)
  or Proof.own(class,'forceCancel')~=nil or class.forceCancel~=ISBaseTimedAction.forceCancel
  or not Proof.closure(class.forceCancel,'ISBaseTimedAction.lua')then return end
 local methods={}
 for name,callback in pairs(class)do
  if type(callback)=='function'then
   if not (name=='derive'and callback==ISBaseTimedAction.derive)and not Proof.closure(callback,profile.name..'.lua')then return end
   methods[name]=callback
  end
 end
 if type(methods.new)~='function'or type(methods.complete)~='function'
  or profile.sound and type(methods.stopSound)~='function'then return end
 return {methods=methods,forceCancel=class.forceCancel,baseNew=base.new,baseForceStop=base.forceStop,
  activeStop=Proof.own(class,'forceStop')==nil and class.forceStop==base.forceStop
   and Proof.closure(base.forceStop,'ISBaseTimedAction.lua')}
end
local function unchanged(profile,snapshot,action)
 local class=profile.class
 if ISBaseTimedAction~=base or base.new~=snapshot.baseNew
  or _G[profile.name]~=class or class.Type~=profile.name or getmetatable(action)~=class or action.Type~=profile.name
  or not action.character or Proof.own(class,'forceCancel')~=nil
  or ISBaseTimedAction.forceCancel~=snapshot.forceCancel or action.forceCancel~=snapshot.forceCancel
  or action.onStartFunc or action.onCancelFunc or action.onCompleteFunc or action.onFailFunc
  or action.retriggerLastAction or action.additionalTest then return false end
 for name,callback in pairs(snapshot.methods)do
  if Proof.own(class,name)~=callback or action[name]~=callback then return false end
 end
 for name,callback in pairs(class)do
  if type(callback)=='function'and snapshot.methods[name]~=callback then return false end
 end
 return true
end
-- These three source-pinned stop callbacks only release local sound/job/animation
-- state. Cosmetic mutations and styling/fluid costs belong to complete. Require
-- the real current episode (not a stale started pointer) and the shared proven
-- stop bridge; a Host action also needs its exact still-started server receipt.
local function active(action,snapshot)
 local actor,native=action.character,action.action
 if not snapshot.activeStop or base.forceStop~=snapshot.baseForceStop or action.forceStop~=snapshot.baseForceStop then return false,'native_stop_changed'end
 if not lifecycle or toolkit~=PZSurvivorToolkit or toolkit.ActionQueueLifecycle~=lifecycle
  or type(stopBridge)~='function' or lifecycle.hasNativeStopBridge~=stopBridge or not stopBridge()then return false,'stop_bridge_missing'end
 if not instanceof(actor,'IsoPlayer') or not actor:isLocalPlayer()
  or getSpecificPlayer(actor:getPlayerNum())~=actor or actor:isDead() or actor:isAsleep()then return false,'foreign_actor'end
 if not native or not native:isStarted() or native:finished() or native:isForceComplete()then return false,'native_episode_terminal'end
 if native:getTable()~=action or not actor:getCharacterActions():contains(native)then return false,'native_episode_owner'end
 local queue=ISTimedActionQueue.queues[actor]
 if not queue or queue.character~=actor or queue.current~=action or queue.queue[1]~=action then return false,'queue_head'end
 if isClient()then
  if not acknowledgements or toolkit.ActionQueueAcknowledgements~=acknowledgements
   or acknowledgements.capture~=captureReceipt or acknowledgements.state~=receiptState
   or type(captureReceipt)~='function' or type(receiptState)~='function'then return false,'native_receipt_binding'end
  local receipt=captureReceipt(action)
  if not receipt then return false,'native_receipt_missing'end
  if receiptState(action,receipt)~='started'then return false,'native_receipt_terminal'end
 end
 return true
end
-- Generator/compatibility entrypoints may load Policy before Queue. Bind once
-- at Queue's completed bridge installation, never freeze absent early modules or
-- adopt replacement modules later while inspecting a live action.
function Grooming.bindInterruption(owner)
 if toolkit~=PZSurvivorToolkit or toolkit.ActionQueueGrooming~=Grooming
  or not owner or toolkit.ActionQueue~=owner or ISBaseTimedAction~=base then return false end
 local liveLifecycle,liveAcknowledgements=toolkit.ActionQueueLifecycle,toolkit.ActionQueueAcknowledgements
 if type(liveLifecycle)~='table' or type(liveAcknowledgements)~='table'
  or not Proof.closure(liveLifecycle.hasNativeStopBridge,'ActionQueueLifecycle.lua')
  or not liveLifecycle.hasNativeStopBridge()
  or not Proof.closure(liveAcknowledgements.capture,'ActionQueueAcknowledgements.lua')
  or not Proof.closure(liveAcknowledgements.state,'ActionQueueAcknowledgements.lua')then return false end
 if lifecycle then
  return liveLifecycle==lifecycle and liveAcknowledgements==acknowledgements
   and liveLifecycle.hasNativeStopBridge==stopBridge and liveAcknowledgements.capture==captureReceipt
   and liveAcknowledgements.state==receiptState
 end
 lifecycle,stopBridge=liveLifecycle,liveLifecycle.hasNativeStopBridge
 acknowledgements,captureReceipt,receiptState=liveAcknowledgements,liveAcknowledgements.capture,liveAcknowledgements.state
 return true
end
function Grooming.adoptBase(name,previous,replacement)
 if not Pending or Pending.adoptBase~=adoptPending or not adoptPending
  or not toolkit or toolkit.ActionQueueGroomingPending~=Pending then return false end
 return adoptPending(name,previous,replacement)
end
local function inspector(profile,snapshot,resources,policy)
 return function(action)
  if not unchanged(profile,snapshot,action)then return end
  local result=resources({item=action[profile.field]})
  if type(result)~='table'or type(result.targets)~='table'then return end
  result.targets[action.character]=true
  result.knownInputs=false
  result.preparation=false
  result.preparationFinish=false
  result.interrupt='finish-step'
  local waiting=action.action==nil and action.toolkitNativeTransaction==nil and action.toolkitNativeKind==nil
  local running,blocker=active(action,snapshot)
  if not waiting then result.interruptBlocker=blocker end
  result.cancelWaiting=waiting
  result.cancelOperation=waiting or running
  if running then result.interrupt='audited-stop'end
  if waiting and lifecycle and stopBridge and stopBridge()and applyPending and Pending.apply==applyPending
   and Pending.adoptBase==adoptPending and toolkit.ActionQueueGroomingPending==Pending
   and Proof.closure(applyPending,'ActionQueueGroomingPending.lua')then applyPending(profile,snapshot,action,result,policy)end
  return result
 end
end

-- Only these reviewed constructors have no effects before native allocation.
-- Dynamic styling/fluid and cosmetic ordering stay unknown to move edits.
-- Active cancellation uses the same audited stop lifecycle as other atomic bodies.
function Grooming.install(policy,resources)
 if type(policy)~='table'or type(policy.registerNative)~='function'or type(resources)~='function'
  or installedPolicy and (installedPolicy~=policy or installedResources~=resources)then return false end
 if not Proof.matches('media/lua/shared/TimedActions/ISBaseTimedAction.lua',3104185167,nil,true)then return false end
 installedPolicy,installedResources=policy,resources
 local complete=true
 for _,profile in ipairs(profiles)do
  if not profile.installed then
   local snapshot=capture(profile)
   if snapshot then
    policy.registerNative(profile.name,inspector(profile,snapshot,resources,policy))
    profile.installed=true
   else complete=false end
  end
 end
 return complete
end
return Grooming
