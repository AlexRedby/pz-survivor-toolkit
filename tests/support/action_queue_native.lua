-- Shared setup for new native-source policy fixtures; native execution/Java state remains explicit per test.
local native,project
local itemAdapters,capacityAdapters,weights
local function itemInspector()
    if not itemAdapters then
        if not ISTransferAction then native('shared/TimedActions/ISTransferAction.lua') end
        if not ISEatFoodAction then native('shared/TimedActions/ISEatFoodAction.lua') end
        if not ISDrinkFluidAction then native('shared/TimedActions/ISDrinkFluidAction.lua') end
        itemAdapters=project('ActionQueueItemEditAdapters')
        -- General policy fixtures intentionally provide resource contracts
        -- without projected item-edit facts. Exercise the real pure weight
        -- inspector while retaining that scope; the dedicated item adapter
        -- suite supplies complete native state and loads the whole module.
        local function absent()end
        capacityAdapters={weightInspectionSafe=itemAdapters.weightInspectionSafe,
            transfer=absent,drink=absent,food=absent,adoptMethods=absent,adoptBase=absent,
            fullnessNeutralDrink=function()return true end}
    end
    return capacityAdapters
end
require = function(module)
    if module == 'PZSurvivorToolkit/ActionQueueSettlement' then
        return PZSurvivorToolkit.ActionQueueSettlement or dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueSettlement.lua')
    end
    if module == 'PZSurvivorToolkit/InventoryClasses' then return dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/' .. module .. '.lua') end
    if module == 'PZSurvivorToolkit/SourceProof' then return assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))() end
    if module == 'PZSurvivorToolkit/ActionQueueWeights' then
        if not weights then weights=project('ActionQueueWeights') end
        return weights
    end
    if module == 'PZSurvivorToolkit/ActionQueueItemEditAdapters' then
        return itemInspector()
    end
end
local function derive(self, name)
    if NativeKahluaTableLookup then
        -- Match ISBaseObject.derive: only the parent gets __index here.
        -- Native new assigns the child's own __index on first construction.
        local class = {Type=name, SuperType=self}
        self.__index=self
        return setmetatable(class,self)
    end
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
native=function(path)
    local source
    if NativeReadText then source=NativeReadText(NativeActionRoot..'/'..path)
    else local f=assert(io.open(NativeActionRoot..'/'..path));source=f:read('*a');f:close() end
    -- Stock Kahlua accepts this native suffix; Lua 5.1 used by the fixture does not.
    assert(loadstring((source:gsub('(%d+%.%d+)f','%1')), '@'..NativeActionRoot..'/'..path))()
end
project=function(name)
    if name == 'ActionQueue' then project('ActionQueueSettlement'); project('ActionQueueLifecycle'); project('ActionQueueAcknowledgements') end
    local savedRequire=require
    if name=='ActionQueuePolicy' then
        require=function(module)
            if module=='PZSurvivorToolkit/ActionQueueItemEditAdapters' then
                return savedRequire(module) or itemInspector()
            end
            if module=='PZSurvivorToolkit/ActionQueueWeights' then
                if not weights then weights=project('ActionQueueWeights') end
                return savedRequire(module) or weights
            end
            return savedRequire(module)
        end
    end
    local root=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/'
    local path=root..'client/PZSurvivorToolkit/'..name..'.lua'
    local exists
    if NativeFileExists then exists=NativeFileExists(path)
    else local file=io.open(path,'r');exists=file~=nil;if file then file:close()end end
    if not exists then path=root..'shared/PZSurvivorToolkit/'..name..'.lua'end
    local result=assert(loadfile(path))()
    require=savedRequire
    return result
end
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
    -- This fixture constructs directly; mirror the native queue constructor.
    if NativeKahluaTableLookup then ISTimedActionQueue.__index=ISTimedActionQueue end
    local values={...};local q=setmetatable({character=player,queue=values,current=values[1]},ISTimedActionQueue)
    ISTimedActionQueue.queues[player]=q;return q
end
return {native=native,project=project,player=player,item=item,action=action,queue=queue}
