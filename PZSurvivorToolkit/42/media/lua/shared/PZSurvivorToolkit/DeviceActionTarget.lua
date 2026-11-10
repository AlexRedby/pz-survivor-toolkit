-- Preserve world-device identity through native timed-action construction and
-- NetTimedAction serialization. Inventory and vehicle parameters stay native.
require 'TimedActions/ISDeviceBatteryAction'
require 'TimedActions/ISDeviceMediaAction'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local proofMatches,proofClosure,proofOwn=Proof.matches,Proof.closure,Proof.own
PZSurvivorToolkit=PZSurvivorToolkit or {}
local Toolkit=PZSurvivorToolkit
local helper,media=ISDeviceBatteryAction,ISDeviceMediaAction
local file='DeviceActionTarget.lua'
local names={'binding','validityBinding','authorizes','world','matches','isInstalled'}
local previous=Toolkit.DeviceActionTarget
-- Game auto-loading and explicit require can meet the same shared chunk. Only
-- recognize an existing owned implementation; never invoke a foreign export.
if type(previous)=='table'and getmetatable(previous)==nil then
 local owned=true
 for _,name in ipairs(names)do
  owned=owned and proofClosure(proofOwn(previous,name),file)
 end
 if owned and proofClosure(helper.getDeviceDataParameter,file)
  and proofClosure(helper.getDeviceDataFromParameter,file)
  and previous.authorizes(helper,'getDeviceDataParameter',helper.getDeviceDataParameter)
  and previous.authorizes(helper,'getDeviceDataFromParameter',helper.getDeviceDataFromParameter)then return previous end
end
local Target={}
local nativeParameter,nativeResolve=helper.getDeviceDataParameter,helper.getDeviceDataFromParameter
local nativeMediaValid,nativeBatteryValid=media.isValid,helper.isValid
local replacementParameter,replacementResolve,guardedMediaValid,guardedBatteryValid
local installed,exports=false,{}
local function nativeSources()
 return proofMatches('media/lua/shared/TimedActions/ISDeviceBatteryAction.lua',1917423720,nil,true)
  and proofMatches('media/lua/shared/TimedActions/ISDeviceMediaAction.lua',553760800,nil,true)
  and proofClosure(nativeParameter,'ISDeviceBatteryAction.lua')
  and proofClosure(nativeResolve,'ISDeviceBatteryAction.lua')
  and proofClosure(nativeBatteryValid,'ISDeviceBatteryAction.lua')
  and proofClosure(nativeMediaValid,'ISDeviceMediaAction.lua')
end
local function foundation()
 if not installed or Proof.matches~=proofMatches or Proof.closure~=proofClosure or Proof.own~=proofOwn
  or PZSurvivorToolkit~=Toolkit or Toolkit.DeviceActionTarget~=Target
  or ISDeviceBatteryAction~=helper or ISDeviceMediaAction~=media
  or helper.getDeviceDataParameter~=replacementParameter or helper.getDeviceDataFromParameter~=replacementResolve
  or getmetatable(Target)~=nil then return false end
 for name,callback in pairs(exports)do if Target[name]~=callback then return false end end
 return true
end
local function liveWorld(device)
 if not instanceof(device,'IsoWaveSignal')then return end
 local square=device:getSquare()
 local index=device:getObjectIndex()
 if not square or index<0 then return end
 local objects=square:getObjects()
 if not objects or index>=objects:size()or objects:get(index)~=device then return end
 local data=device:getDeviceData()
 if data and data:getParent()==device then return data,square end
end
local function observedWorld(device)
 local ok,data,square=pcall(liveWorld,device)
 if ok then return data,square end
end
function Target.isInstalled()return foundation()end
function Target.binding()
 return helper,nativeParameter,nativeResolve,replacementParameter,replacementResolve
end
function Target.validityBinding()
 return media,nativeMediaValid,guardedMediaValid,helper,nativeBatteryValid,guardedBatteryValid
end
function Target.authorizes(owner,name,callback)
 if not foundation()or not nativeSources()then return false end
 return owner==helper and(name=='getDeviceDataParameter'and callback==replacementParameter
  or name=='getDeviceDataFromParameter'and callback==replacementResolve
  or name=='isValid'and callback==guardedBatteryValid)
  or owner==media and name=='isValid'and callback==guardedMediaValid
end
local function world(parameter,data)
 if not foundation()or not data then return end
 if instanceof(parameter,'IsoWaveSignal')then
  local current,square=observedWorld(parameter)
  if current==data then return parameter,square end
 elseif instanceof(parameter,'IsoGridSquare')then
  -- Legacy queued/recovery parameters retain native square resolution. Never
  -- turn their original binding into permission for a different device.
  local ok,device=pcall(function()
   if parameter:getDeviceData()==data then return data:getParent()end
  end)
  if ok then
   local current,square=observedWorld(device)
   if current==data and square==parameter then return device,square end
  end
 end
end
Target.world=world
function Target.matches(parameter,device,data)
 local current=world(parameter,data)
 return current~=nil and current==device
end
replacementParameter=function(self,character,device,deviceType)
 if character and device and deviceType=='IsoObject'and instanceof(device,'IsoWaveSignal')then
  -- Keep even a removed identity: the resolver and validity guard must reject
  -- it rather than silently selecting another device on its former square.
  return device
 end
 return nativeParameter(self,character,device,deviceType)
end
replacementResolve=function(self,character,parameter)
 if instanceof(parameter,'IsoWaveSignal')then local data=observedWorld(parameter);return data end
 return nativeResolve(self,character,parameter)
end
local function validWorld(action)
 -- Native world-object decoding may return nil after removal in transit.
 if not action.deviceData then return false end
 if not instanceof(action.parameter,'IsoWaveSignal')then return true end
 if not foundation()then return false end
 local data=observedWorld(action.parameter)
 return data~=nil and data==action.deviceData
end
guardedMediaValid=function(action)
 if not validWorld(action)then return false end
 return nativeMediaValid(action)
end
guardedBatteryValid=function(action)
 if not validWorld(action)then return false end
 local item=action.secondaryItem
 if action.isRemove then
  if item~=nil then return false end
 else
  -- Native addBattery still sets charge when its item has lost its container.
  -- Reject vanished/proxy inputs before native invoke can manufacture charge.
  if not instanceof(item,'DrainableComboItem')or item:getFullType()~='Base.Battery'then return false end
  local container=item:getContainer()
  -- Native argument decoding uses this direct ID lookup too. Its exact
  -- returned reference proves membership without recursion or a Lua list scan.
  if not instanceof(container,'ItemContainer')or container:getItemWithID(item:getID())~=item then return false end
 end
 return nativeBatteryValid(action)
end
for _,name in ipairs(names)do exports[name]=Target[name]end
-- A changed native helper is unsupported. Leave its delegates untouched and
-- publish an inert module so consumers can refuse adoption explicitly.
if previous==nil and nativeSources()then
 helper.getDeviceDataParameter=replacementParameter
 helper.getDeviceDataFromParameter=replacementResolve
 media.isValid,helper.isValid=guardedMediaValid,guardedBatteryValid
 installed=true
end
if previous==nil then Toolkit.DeviceActionTarget=Target end
return Target
