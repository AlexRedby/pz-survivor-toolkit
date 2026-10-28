-- Held-bank fixture only. Observe the reviewed cart guard's normal factory;
-- never unwrap its predecessor or replace its installed gameplay wrapper.
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Binding={}
local started,ready,active,native=false,false,false,nil
local core,guard,factory,installer,predicate,persistent,debugLog,cartTypes,observed,wrapped
local calls=0
local function pack(...)return {n=select('#',...),...}end
local function stable()
 return type(core)=='table'and getmetatable(core)==nil and SaucedCarts==core
  and type(guard)=='table'and getmetatable(guard)==nil and core.ForceDropGuard==guard
  and guard.makeGuardedForceDrop==observed and guard.install==installer
  and Proof.closure(factory,'ForceDropGuard.lua')and Proof.closure(installer,'ForceDropGuard.lua')
  and core.isCart==predicate and Proof.closure(predicate,'Core.lua')
  and core.markDropPersistent==persistent and Proof.closure(persistent,'Core.lua')
  and core.debug==debugLog and Proof.closure(debugLog,'Core.lua')
  and core.CartTypes==cartTypes and type(cartTypes)=='table'and getmetatable(cartTypes)==nil
  and cartTypes['Base.MakeupEyeshadow']==nil and cartTypes['Base.Hammer']==nil
end
function Binding.start()
 if started then return Binding.matches(forceDropHeavyItems)end
 started=true;native=forceDropHeavyItems
 if type(native)~='function'or not Proof.closure(native,'ISEquipWeaponAction.lua')
  or not Proof.matches('media/lua/shared/TimedActions/ISEquipWeaponAction.lua',4117952124,nil,true)then return false end
 active=getActivatedMods and getActivatedMods():contains('SaucedCarts')or false
 if not active then ready=true;return true end
 if not Proof.matches('media/lua/shared/SaucedCarts/Core.lua',2570266575,'SaucedCarts',true)
  or not Proof.matches('media/lua/shared/SaucedCarts/ForceDropGuard.lua',538857615,'SaucedCarts',true)then return false end
 require 'SaucedCarts/Core'
 local supplied=require 'SaucedCarts/ForceDropGuard'
 core=SaucedCarts;guard=type(core)=='table'and core.ForceDropGuard
 if type(core)~='table'or getmetatable(core)~=nil or type(guard)~='table'or getmetatable(guard)~=nil
  or supplied~=guard or core._forceDropGuardInstalled then return false end
 factory,installer,predicate,persistent,debugLog,cartTypes=guard.makeGuardedForceDrop,guard.install,core.isCart,core.markDropPersistent,core.debug,core.CartTypes
 if type(factory)~='function'or not Proof.closure(factory,'ForceDropGuard.lua')
  or type(installer)~='function'or not Proof.closure(installer,'ForceDropGuard.lua')
  or type(predicate)~='function'or not Proof.closure(predicate,'Core.lua')
  or type(persistent)~='function'or not Proof.closure(persistent,'Core.lua')
  or type(debugLog)~='function'or not Proof.closure(debugLog,'Core.lua')
  or type(cartTypes)~='table'or getmetatable(cartTypes)~=nil
  or cartTypes['Base.MakeupEyeshadow']~=nil or cartTypes['Base.Hammer']~=nil then return false end
 observed=function(...)
  local original,isCart=...
  local admitting=calls==0 and stable()and core._forceDropGuardInstalled==true
   and forceDropHeavyItems==native and select('#',...)==2 and original==native and isCart==predicate
  calls=calls+1
  local result=pack(pcall(factory,...))
  if admitting and result[1]and result.n==2 and type(result[2])=='function'
   and Proof.closure(result[2],'ForceDropGuard.lua')and stable()and forceDropHeavyItems==native then wrapped=result[2]end
  if not result[1]then error(result[2],0)end
  return unpack(result,2,result.n)
 end
 guard.makeGuardedForceDrop=observed;ready=true
 return true
end
function Binding.matches(callback)
 if not ready or type(native)~='function'or not Proof.closure(native,'ISEquipWeaponAction.lua')then return false end
 if not active then return callback==native and forceDropHeavyItems==native end
 if not stable()then return false end
 if callback==native then return forceDropHeavyItems==native and not core._forceDropGuardInstalled and calls==0 end
 return wrapped~=nil and callback==wrapped and forceDropHeavyItems==wrapped and core._forceDropGuardInstalled==true and calls==1
end
return Binding
