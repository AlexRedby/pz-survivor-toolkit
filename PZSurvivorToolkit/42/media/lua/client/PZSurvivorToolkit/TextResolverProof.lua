-- Observe the reviewed provider's ordinary installation. Never replace its
-- translation policy or accept an opaque predecessor captured inside a closure.
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Binding={}
local Toolkit=PZSurvivorToolkit
if not Toolkit then function Binding.matches()return false end;return Binding end
Toolkit.TextResolverProof=Binding
local native,classifier=getText,getClassSimpleName
local function java(callback)
 if type(callback)~='function'or type(classifier)~='function'or getClassSimpleName~=classifier then return false end
 local ok,kind=pcall(classifier,callback)
 return ok and (kind=='LuaJavaInvoker'or kind=='MultiLuaJavaInvoker')
end
local store,installer,owned,resolver
local function pack(...)return {n=select('#',...),...}end
if java(native)and java(classifier)and getActivatedMods and getActivatedMods():contains('EURY_CONTAINERS')
 and Proof.matches('media/lua/client/BetterContainers/Categorize/CategoryStore.lua',1639573053,'EURY_CONTAINERS',true)then
 store=require 'BetterContainers/Categorize/CategoryStore'
 installer=type(store)=='table'and getmetatable(store)==nil and store.installTextResolver
 if type(installer)=='function'and Proof.closure(installer,'CategoryStore.lua')and not store._textResolverInstalled then
  owned=function(...)
   local admitting=getmetatable(store)==nil and store.installTextResolver==owned and not store._textResolverInstalled and getText==native and java(native)
   local result=pack(pcall(installer,...))
   if admitting and result[1]and getmetatable(store)==nil and store._textResolverInstalled and getText~=native
    and Proof.closure(getText,'CategoryStore.lua')then resolver=getText end
   if not result[1]then error(result[2],0)end
   return unpack(result,2,result.n)
  end
  store.installTextResolver=owned
 end
end
function Binding.matches(callback,original)
 if Toolkit~=PZSurvivorToolkit or Toolkit.TextResolverProof~=Binding or original~=native or not java(native)then return false end
 if callback==native then return true end
 return resolver~=nil and callback==resolver and getmetatable(store)==nil and store.installTextResolver==owned and getText==resolver
end
return Binding
