require 'TimedActions/ISCutHair'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Grooming={}
local class=ISCutHair
local installedPolicy,installedResources,inspector

local function capture()
 if type(class)~='table'or ISCutHair~=class or class.Type~='ISCutHair'
  or not Proof.matches('media/lua/shared/TimedActions/ISCutHair.lua',1007133567,nil,true)
  or not Proof.matches('media/lua/shared/TimedActions/ISBaseTimedAction.lua',3104185167,nil,true)
  or Proof.own(class,'forceCancel')~=nil or class.forceCancel~=ISBaseTimedAction.forceCancel
  or not Proof.closure(class.forceCancel,'ISBaseTimedAction.lua')then return end
 local methods={}
 for name,callback in pairs(class)do
  if type(callback)=='function'then
   if not (name=='derive'and callback==ISBaseTimedAction.derive)and not Proof.closure(callback,'ISCutHair.lua')then return end
   methods[name]=callback
  end
 end
 if type(methods.new)~='function'or type(methods.complete)~='function'or type(methods.stopSound)~='function'then return end
 return {methods=methods,forceCancel=class.forceCancel}
end
local function unchanged(snapshot,action)
 if ISCutHair~=class or class.Type~='ISCutHair'or getmetatable(action)~=class or action.Type~='ISCutHair'
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

-- This describes deletion of a body which has never allocated a native episode.
-- Dynamic styling costs and cosmetic mutations remain unknown to move/active edits.
function Grooming.install(policy,resources)
 if installedPolicy then return installedPolicy==policy and installedResources==resources end
 if type(policy)~='table'or type(policy.registerNative)~='function'or type(resources)~='function'then return false end
 local snapshot=capture();if not snapshot then return false end
 inspector=function(action)
  if not unchanged(snapshot,action)then return end
  local result=resources(action)
  if type(result)~='table'or type(result.targets)~='table'then return end
  result.targets[action.character]=true
  result.knownInputs=false
  result.preparation=false
  result.preparationFinish=false
  result.interrupt='finish-step'
  local waiting=action.action==nil and action.toolkitNativeTransaction==nil and action.toolkitNativeKind==nil
  result.cancelWaiting=waiting
  result.cancelOperation=waiting
  return result
 end
 policy.registerNative('ISCutHair',inspector)
 installedPolicy,installedResources=policy,resources
 return true
end
return Grooming
