-- Regression for the real Compat installer accepting organizedCategories' late Grab wrappers.
-- Run with --wishlist-workshop-root; unrelated cooking/equipment integrations are not loaded.
if not NativeWishlistWorkshopRoot then
    print('Grab compatibility source checks skipped (pass Workshop root).')
    return
end
local function read(path)
    if NativeReadText then return (NativeReadText(path):gsub('\r','')) end
    local input=assert(io.open(path));local text=input:read('*a');input:close();return (text:gsub('\r',''))
end
local paths={P4TidyUpMeister='2769706949/mods/P4TidyUpMeister/42.20',
    organizedCategories_core='3370707195/mods/organizedCategoriesCore/42'}
local function reader(text)
    local cursor=1
    return {close=function()end,readLine=function()
        if cursor>#text then return end
        local boundary=text:find('\n',cursor,true)or #text+1
        local line=text:sub(cursor,boundary-1);cursor=boundary+1;return line
    end}
end
getModFileReader=function(id,path)return reader(read(NativeWishlistWorkshopRoot..'/'..assert(paths[id])..'/'..path))end
getActivatedMods=function()return {contains=function(_,id)return paths[id]~=nil end}end
local handlers={}
Events=setmetatable({},{__index=function(self,name)
    local event={Add=function(callback)handlers[name]=handlers[name]or {};table.insert(handlers[name],callback)end,Remove=function()end}
    rawset(self,name,event);return event
end})
getText=function(key)return key end
getTextOrNull=getText
isClient=function()return false end
instanceof=function(value,name)return type(value)=='table'and value.class==name end
getFilenameOfClosure=function(callback)
    local info=debug.getinfo(callback,'S');return info and info.source:gsub('^@','')
end
local function derive(self,name)
    local class={Type=name,derive=derive};class.__index=class;return setmetatable(class,{__index=self})
end
ISBaseTimedAction={derive=derive}
for _,name in ipairs({'ISInventoryTransferAction','ISWashClothing','ISEquipWeaponAction','ISUnequipAction',
    'ISWearClothing','ISClothingExtraAction','ISAttachItemHotbar','ISDetachItemHotbar','ISAddItemInRecipe',
    'ISHandcraftAction','ISDumpContentsAction','P4RestoreAction','P4RestoreFloorAction'})do _G[name]=ISBaseTimedAction:derive(name)end
ISTimedActionQueue={queues={},add=function()end,addAfter=function()end,addToQueue=function()end,
    resetQueue=function()end,clearQueue=function()end}
ISTransferAction={GetDropItemOffset=function()end,transferItem=function()end}
ISInventoryTransferUtil={newInventoryTransferAction=function()end}
ISInventoryPane={getActualItems=function(items)return items end}
ISInventoryPage={}
LootSorter={}
ISXuiSkinFunctions={}
PZAPI={ModOptions={create=function()return {
    addTickBox=function()return {value=false}end,
    addComboBox=function()return {addItem=function()end}end,
}end}}
SandboxVars={}
PZSurvivorToolkit={Settings={actionQueue=function()return true end},ActionQueuePolicy={},
    ActionQueueOperations={registerProducer=function()end},ActionQueueDefinitions={registerBehavior=function()end}}
local calls={grab=0,one=0,half=0}
ISInventoryPaneContextMenu={transferIfNeeded=function()end}
for name,key in pairs({onGrabItems='grab',onGrabOneItems='one',onGrabHalfItems='half'})do
    ISInventoryPaneContextMenu[name]=function(items,player)
        assert(player==0 and #items==1,'native delegate arguments changed')
        calls[key]=calls[key]+1;return key,'forwarded'
    end
end
getSpecificPlayer=function(index)assert(index==0);return {}end
local intent,approved,valid
local loaded={}
require=function(module)
    if loaded[module]then return loaded[module]end
    local path
    if module=='PZSurvivorToolkit/SourceProof'then path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/'..module..'.lua'
    elseif module=='PZSurvivorToolkit/QuartermasterCraftContainers'then path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'..module..'.lua'
    elseif module=='PZSurvivorToolkit/ActionQueueTidyIntent'then
        intent=assert(loadstring(read(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'..module..'.lua'),'@ActionQueueTidyIntent.lua'))()
        local install=intent.install
        intent.install=function(actionGuard,wrapperGuard)
            valid,approved=actionGuard,wrapperGuard
            return install(actionGuard,wrapperGuard)
        end
        loaded[module]=intent;return intent
    elseif module=='P4TidyUpMeister'then path=NativeWishlistWorkshopRoot..'/'..paths.P4TidyUpMeister..'/media/lua/client/'..module..'.lua'
    else return end
    local value=assert(loadstring(read(path),'@'..path))()or true;loaded[module]=value;return value
end
local compat=assert(loadstring(read(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua'),'@ActionQueueCompat.lua'))()
assert(compat.isInstalled('P4TidyUpMeister'),'real pinned P4 source must install')
assert(valid and valid()and approved,'real Compat installer must supply valid late-wrapper proof')
local before={}
for _,name in ipairs({'onGrabItems','onGrabOneItems','onGrabHalfItems'})do before[name]=ISInventoryPaneContextMenu[name]end
-- Execute the complete unmodified third-party source and its actual late installer.
local stickPath=NativeWishlistWorkshopRoot..'/'..paths.organizedCategories_core..'/media/lua/client/organizedCategories_itemStick.lua'
assert(loadstring(read(stickPath),'@'..stickPath))()
assert(handlers.OnGameStart and #handlers.OnGameStart==1,'actual stick late installer missing')
handlers.OnGameStart[1]()
for name,callback in pairs(before)do
    local wrapped=ISInventoryPaneContextMenu[name]
    assert(wrapped~=callback and ISInventoryPaneContextMenu['_ocStick_'..name]==wrapped,'actual late wrapper missing: '..name)
    local first,second=wrapped({{items={}}},0)
    local key=name=='onGrabItems'and 'grab'or name=='onGrabOneItems'and 'one'or 'half'
    assert(first==key and second=='forwarded'and calls[key]==1,'late wrapper must reach native Grab delegate exactly once')
    assert(approved(ISInventoryPaneContextMenu,name),'installer must approve real source-pinned late wrapper: '..name)
    local marker=ISInventoryPaneContextMenu['_ocStick_'..name]
    ISInventoryPaneContextMenu['_ocStick_'..name]=nil
    assert(not approved(ISInventoryPaneContextMenu,name),'missing source marker must fail closed')
    ISInventoryPaneContextMenu['_ocStick_'..name]=marker
    local origin=getFilenameOfClosure
    getFilenameOfClosure=function(fn)if fn==wrapped then return 'unreviewed_wrapper.lua' end;return origin(fn)end
    assert(not approved(ISInventoryPaneContextMenu,name),'wrong source filename must fail closed')
    getFilenameOfClosure=origin
    assert(not approved({},name),'foreign menu owner must fail closed')
end
print('Source-pinned Grab / Grab One late compatibility guard checks passed.')
