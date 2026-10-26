require 'TimedActions/ISCutHair'
require 'TimedActions/ISTrimBeard'
require 'TimedActions/ISDyeHair'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Grooming={}
local base=ISBaseTimedAction
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
 return {methods=methods,forceCancel=class.forceCancel,baseNew=base.new}
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
local function inspector(profile,snapshot,resources)
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
  result.cancelWaiting=waiting
  result.cancelOperation=waiting
  return result
 end
end

-- Only these reviewed constructors have no effects before native allocation.
-- Cosmetic mutations and dynamic styling/fluid costs stay unknown to move/active edits.
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
    policy.registerNative(profile.name,inspector(profile,snapshot,resources))
    profile.installed=true
   else complete=false end
  end
 end
 return complete
end
return Grooming
