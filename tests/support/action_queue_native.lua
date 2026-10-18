-- Shared setup for new native-source policy fixtures; native execution/Java state remains explicit per test.
require = function(module)
    if module == 'PZSurvivorToolkit/SourceProof' then return assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/SourceProof.lua'))() end
end
local function derive(self, name)
    local class = {Type=name, derive=derive}; class.__index=class
    return setmetatable(class,{__index=self})
end
ISBaseObject={derive=derive,new=function() return {} end}
PZSurvivorToolkit={Settings={actionQueue=function() return true end},BulkActions={isGuardedTransfer=function() return false end}}
Events={OnTick={Add=function() end},OnGameStart={Add=function() end}}
Events.OnServerCommand = {Add = function() end}
for _,name in ipairs({'ClimbThroughWindowState','ClimbOverFenceState','ClimbOverWallState','ClimbSheetRopeState','ClimbDownSheetRopeState','CloseWindowState','OpenWindowState'}) do
    _G[name]={instance=function() return {} end}
end
getText=function(key) return key end
instanceof=function(value,name) return type(value)=='table' and value.class==name end
table.wipe=function(t) for k in pairs(t) do t[k]=nil end end
local function native(path)
    local source
    if NativeReadText then source=NativeReadText(NativeActionRoot..'/'..path)
    else local f=assert(io.open(NativeActionRoot..'/'..path));source=f:read('*a');f:close() end
    -- Stock Kahlua accepts this native suffix; Lua 5.1 used by the fixture does not.
    assert(loadstring((source:gsub('(%d+%.%d+)f','%1'))))()
end
local function project(name)
    if name == 'ActionQueue' then project('ActionQueueLifecycle'); project('ActionQueueAcknowledgements') end
 return assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/'..name..'.lua'))() end
native('shared/TimedActions/ISBaseTimedAction.lua')
native('client/TimedActions/ISTimedActionQueue.lua')
native('client/TimedActions/ISQueueActionsAction.lua')
native('shared/TimedActions/ISReadABook.lua')
ISInventoryPage,ISInventoryPaneContextMenu,ISContextMenu,ISButton,ISInventoryPane={},{},{},{},{}
native('client/TimedActions/ISInventoryTransferAction.lua')
local player={getPlayerNum=function() return 0 end,isDead=function() return false end,isAsleep=function() return false end,
    isTimedActionInstant=function() return false end,isPlayerMoving=function() return false end,pressedMovement=function() return false end}
player.inventory={};player.getInventory=function() return player.inventory end
getSpecificPlayer=function() return player end
local nextID=0
local function item(kind)
    nextID=nextID+1
    return {class='InventoryItem',id=nextID,getID=function(self) return self.id end,getFullType=function() return kind end,
        getContainer=function() return player.inventory end}
end
local function action(class,fields)
    local value=ISBaseTimedAction.new(class,player);value.toolkitQueueOperation={}
    for k,v in pairs(fields or {}) do value[k]=v end
    return value
end
local function queue(...)
    local values={...};local q=setmetatable({character=player,queue=values,current=values[1]},ISTimedActionQueue)
    ISTimedActionQueue.queues[player]=q;return q
end
return {native=native,project=project,player=player,item=item,action=action,queue=queue}
