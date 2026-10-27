local source=NativeBCCategoryStoreSource
if not source and NativeWishlistWorkshopRoot then
 local path=NativeWishlistWorkshopRoot..'/3586216562/mods/BetterContainers/42.21/media/lua/client/BetterContainers/Categorize/CategoryStore.lua'
 if NativeReadText then source=NativeReadText(path)
 else local file=io.open(path);if file then source=file:read('*a');file:close()end end
end
if not source then print('Text resolver source proof SKIP (supply --wishlist-workshop-root or BC source).');return end
source=source:gsub('\r','')
local installSource=assert(source:match('(function Store%.installTextResolver.-)\nfunction Store%.getAllCategoryIDs'))
local function scenario(options)
 options=options or{}
 local java={};local calls=0
 local native=function(key,...)calls=calls+1;return key,select('#',...)end;java[native]=true
 local classifier=function(value)return java[value]and'LuaJavaInvoker'or'LuaClosure'end;java[classifier]=true
 getText,getClassSimpleName=native,classifier
 getActivatedMods=function()return {contains=function(_,id)return id=='EURY_CONTAINERS'end}end
 PZSurvivorToolkit={}
 local store={definitions={Test={displayName='Custom category'}}}
 local loader=assert(loadstring('return function(Store)\n'..installSource..'\nend','@media/lua/client/BetterContainers/Categorize/CategoryStore.lua'))();loader(store)
 local installer=store.installTextResolver
 local proof=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))()
 getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source:gsub('^@','')end
 getModFileReader=function(mod,path)
  assert(mod=='EURY_CONTAINERS'and path=='media/lua/client/BetterContainers/Categorize/CategoryStore.lua')
  local value=source..(options.source and '\n-- changed\n'or'');local at=1
  return {close=function()end,readLine=function()
   if at>#value then return end
   local last=value:find('\n',at,true)or #value+1;local line=value:sub(at,last-1);at=last+1;return line
  end}
 end
 require=function(name)
  if name=='PZSurvivorToolkit/SourceProof'then return proof end
  assert(name=='BetterContainers/Categorize/CategoryStore');return store
 end
 if options.preinstalled then store.installTextResolver()end
 local binding=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/TextResolverProof.lua'))()
 return {binding=binding,native=native,store=store,installer=installer,calls=function()return calls end}
end
local s=scenario();assert(s.binding.matches(getText,s.native),'native translator not recognized')
assert(s.store.installTextResolver~=s.installer and not s.store._textResolverInstalled,'proof eagerly installed a provider')
s.store.installTextResolver()
assert(s.binding.matches(getText,s.native),'observed native predecessor was not retained')
local text,count=getText('ContextMenu_CutHair',1,2)
assert(text=='ContextMenu_CutHair'and count==2 and s.calls()==1,'native delegation changed values/arguments')
assert(getText('IGUI_ItemCat_Test')=='Custom category'and s.calls()==1,'provider category resolution changed')
s.store.installTextResolver();assert(s.binding.matches(getText,s.native),'idempotent installer lost binding')
local captured=getText;getText=function()end;assert(not s.binding.matches(getText,s.native),'foreign translator gained trust')
getText=captured;s.store.installTextResolver=function()end;assert(not s.binding.matches(getText,s.native),'replaced provider installer retained trust')
for _,options in ipairs({{source=true},{preinstalled=true}})do
 local value=scenario(options);value.store.installTextResolver()
 assert(not value.binding.matches(getText,value.native),'unknown source or hidden predecessor was adopted')
end
local foreign=scenario();getText=function()return 'foreign'end;foreign.store.installTextResolver()
assert(not foreign.binding.matches(getText,foreign.native),'foreign captured predecessor was admitted')
print('PASS actual BC resolver preserves native/category semantics and variadic results; changed/hidden source, predecessor and owner stay unknown')

local proxy=scenario();local reads=0;local foreignCalls=0
setmetatable(proxy.store,{__index=function(_,key)
 if key=='_textResolverInstalled'then
  reads=reads+1
  if reads==2 then getText=function()foreignCalls=foreignCalls+1;return 'foreign'end end
 end
end})
proxy.store.installTextResolver()
assert(not proxy.binding.matches(getText,proxy.native),'proxy Store laundered a hidden foreign predecessor')
print('PASS provider metatables cannot change the predecessor between admission and original capture')
