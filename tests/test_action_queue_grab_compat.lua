-- Regression for the real Compat installer accepting Toolkit's exact late retention Grab wrappers.
-- Run with --wishlist-workshop-root; unrelated cooking/equipment integrations are not loaded.
if not NativeWishlistWorkshopRoot then
    print('Grab compatibility source checks skipped (pass Workshop root).')
    return
end
local function read(path)
    if NativeReadText then return (NativeReadText(path):gsub('\r','')) end
    local input=assert(io.open(path));local text=input:read('*a');input:close();return (text:gsub('\r',''))
end
local function checkOrder(latePublication)
P4TidyUpMeister=nil
local paths={P4TidyUpMeister='2769706949/mods/P4TidyUpMeister/42.20'}
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
    elseif module=='PZSurvivorToolkit/ItemAccess' or module=='PZSurvivorToolkit/ItemRetention' or module=='PZSurvivorToolkit/InventoryTransferProtection'then
        path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/'..module..'.lua'
    elseif module=='PZSurvivorToolkit/ItemRetentionUI' or module=='PZSurvivorToolkit/InventoryClasses'then
        path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'..module..'.lua'
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
local retention
if not latePublication then retention=require 'PZSurvivorToolkit/ItemRetentionUI' end
local compat=assert(loadstring(read(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua'),'@ActionQueueCompat.lua'))()
assert(compat.isInstalled('P4TidyUpMeister'),'real pinned P4 source must install')
assert(valid and valid()and approved,'real Compat installer must supply valid late-wrapper proof')
local before={}
for _,name in ipairs({'onGrabItems','onGrabOneItems','onGrabHalfItems'})do before[name]=ISInventoryPaneContextMenu[name]end
if latePublication then retention=require 'PZSurvivorToolkit/ItemRetentionUI' end
-- Install the actual owned wrapper late, outside Compat's existing Tidy closure.
assert(handlers.OnGameStart and #handlers.OnGameStart==1,'owned retention late installer missing')
handlers.OnGameStart[1]()
for name,callback in pairs(before)do
    local wrapped=ISInventoryPaneContextMenu[name]
    assert(wrapped~=callback and retention.isContextWrapper(ISInventoryPaneContextMenu,name),'actual late wrapper missing: '..name)
    local first,second=wrapped({{items={}}},0)
    local key=name=='onGrabItems'and 'grab'or name=='onGrabOneItems'and 'one'or 'half'
    assert(first==key and second=='forwarded'and calls[key]==1,'late wrapper must reach native Grab delegate exactly once')
    assert(approved(ISInventoryPaneContextMenu,name),'installer must approve real owned late wrapper: '..name)
    ISInventoryPaneContextMenu[name]=function(...)return wrapped(...)end
    assert(not approved(ISInventoryPaneContextMenu,name),'foreign callback replacement must fail closed')
    retention.install()
    assert(not approved(ISInventoryPaneContextMenu,name),'reinstall must not approve a replaced delegate')
    ISInventoryPaneContextMenu[name]=wrapped
    local predicate=retention.isContextWrapper
    retention.isContextWrapper=function()return true end
    assert(not approved(ISInventoryPaneContextMenu,name),'replaced owner predicate must fail closed')
    retention.isContextWrapper=predicate
    PZSurvivorToolkit.ItemRetention={isContextWrapper=predicate}
    assert(not approved(ISInventoryPaneContextMenu,name),'replaced retention namespace must fail closed')
    PZSurvivorToolkit.ItemRetention=retention
    assert(not approved({},name),'foreign menu owner must fail closed')
end
end
checkOrder(false)
checkOrder(true)
print('Owned retention Grab late guards passed with early/late owner publication and actual P4 source.')
