require 'TimedActions/Animals/ISPetAnimal'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Toolkit=PZSurvivorToolkit
local Lifecycle=Toolkit.ActionQueueLifecycle
local base,class=ISBaseTimedAction,ISPetAnimal
local AnimalStops={}
Toolkit.ActionQueueAnimalStops=AnimalStops
local native,installed={},{}
local baseNew,baseStop=base.new,base.stop
local scope
local function pack(...)return {n=select('#',...),...}end

-- A native success can use stop rather than perform. Only the reviewed trigger
-- may admit the existing guarded lifecycle; this grants no move/cancel rights.
local trusted=Proof.matches('media/lua/shared/TimedActions/ISBaseTimedAction.lua',3104185167,nil,true)
 and Proof.matches('media/lua/shared/TimedActions/Animals/ISPetAnimal.lua',1009180100,nil,true)
 and Proof.closure(baseNew,'ISBaseTimedAction.lua') and Proof.closure(baseStop,'ActionQueue.lua')
 and type(class)=='table' and class.Type=='ISPetAnimal'
if trusted then
 for name,callback in pairs(class)do
  if type(callback)=='function'then
   if not (name=='derive' and callback==base.derive) and not Proof.closure(callback,'ISPetAnimal.lua')then trusted=false end
   native[name]=callback
  end
 end
 for _,name in ipairs({'new','isValid','start','stop','forceStop','perform','complete','animEvent','getDuration'})do
  if type(native[name])~='function'then trusted=false end
 end
end
local function unchanged(action)
 if not trusted or ISBaseTimedAction~=base or base.new~=baseNew or base.stop~=baseStop
  or ISPetAnimal~=class or class.Type~='ISPetAnimal' or getmetatable(action)~=class or action.Type~='ISPetAnimal'
  or action.onStartFunc or action.onCancelFunc or action.onCompleteFunc or action.onFailFunc
  or action.additionalTest or action.retriggerLastAction or action._isAddingActions then return false end
 for name,callback in pairs(native)do
  local expected=installed[name] or callback
  if Proof.own(class,name)~=expected or action[name]~=expected then return false end
 end
 for name,callback in pairs(class)do
  if type(callback)=='function' and not native[name]then return false end
 end
 return true
end
local function candidate(action)
 if not Toolkit.Settings.actionQueue() or not unchanged(action) or isServer()then return end
 local actor,animal=action.character,action.animal
 local queue=actor and ISTimedActionQueue.queues[actor]
 local nativeAction=action.action
 if not instanceof(actor,'IsoPlayer') or not instanceof(animal,'IsoAnimal')
  or not queue or queue.character~=actor or queue.current~=action or queue.queue[1]~=action or not nativeAction
  or not actor:isLocalPlayer() or getSpecificPlayer(actor:getPlayerNum())~=actor
  or actor:isDead() or actor:isAsleep() or actor:pressedCancelAction() or actor:isPlayerMoving() or actor:pressedMovement(false)
  or queue.toolkitCancel or queue.toolkitStopIntent or queue.toolkitOutcomeWait or queue.toolkitGroupCancel or queue.toolkitResume
  or not actor:getCharacterActions():contains(nativeAction) or nativeAction:getTable()~=action
  or not nativeAction:isStarted() or nativeAction:finished() or nativeAction:isForceComplete()
  or not actor:getSquare() or not animal:getSquare() or animal:getHealth()<=0 or not native.isValid(action)then return end
 return queue,actor,animal,nativeAction
end
if trusted then
 installed.animEvent=function(action,event,parameter)
  local previous=scope
  local queue,actor,animal,nativeAction
  if event=='pettingFinished'then queue,actor,animal,nativeAction=candidate(action)end
  scope=queue and {action=action,queue=queue,actor=actor,animal=animal,native=nativeAction} or nil
  local results=pack(pcall(native.animEvent,action,event,parameter))
  scope=previous
  if not results[1]then
   if queue then Lifecycle.invalidateStop(queue,action)end
   error(results[2],0)
  end
  return unpack(results,2,results.n)
 end
 installed.forceStop=function(action,...)
  local trigger=scope
  if trigger and trigger.action==action and not trigger.admitted then
   local queue,actor,animal,nativeAction=candidate(action)
   if queue==trigger.queue and actor==trigger.actor and animal==trigger.animal and nativeAction==trigger.native then
    trigger.admitted=Lifecycle.prepareStop(queue,action,'native-animal-ended','action',{guarded=true,pendingStart=true,
     validate=function()
      return unchanged(action) and action.character==actor and action.animal==animal
     end})
   end
  end
  return native.forceStop(action,...)
 end
 installed.stop=function(action,...)
  return Lifecycle.runStop(action,native.stop,...)
 end
 for name,callback in pairs(installed)do class[name]=callback end
end
return AnimalStops
