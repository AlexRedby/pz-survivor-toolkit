local craftContainers
require = function(name)
    if name == 'PZSurvivorToolkit/QuartermasterCraftContainers' then
        craftContainers = craftContainers or dofile(NativeQuartermasterLuaRoot .. '/client/' .. name .. '.lua')
        return craftContainers
    end
end
local function derive(self, name)
    local class = {Type = name, derive = derive}
    class.__index = class
    return setmetatable(class, {__index = self})
end
ISBaseObject = {derive = derive, new = function() return {} end}
ISUIElement = ISBaseObject:derive('ISUIElement')
function ISUIElement:addChild(child) self.children[child] = child; child.parent = self end
function ISUIElement:removeChild(child) self.children[child] = nil; child.parent = nil end
for _, field in ipairs({'X', 'Y', 'Width', 'Height'}) do
    local key = field:lower()
    ISUIElement['get' .. field] = function(self) return self[key] end
    ISUIElement['set' .. field] = function(self, value) self[key] = value end
end
function ISUIElement:setVisible(value) self.visible = value end
ISPanel = ISUIElement:derive('ISPanel')
function ISPanel:new(x, y, w, h)
    return setmetatable({x=x,y=y,width=w,height=h,children={}}, self)
end
ISPanel.initialise = function() end
ISXuiSkin = {build = function(_, _, class, ...) return class:new(...) end}
dofile(NativePZLuaRoot .. '/client/Entity/ISUI/Controls/ISTableLayout.lua')
local function panel(w, h) return ISPanel:new(0, 0, w, h) end
ISTickBox = ISPanel:derive('ISTickBox')
function ISTickBox:new(x, y, w, h, _, target, callback)
    local tick = ISPanel.new(self, x, y, w, h)
    tick.target, tick.callback = target, callback
    return tick
end
ISTickBox.instantiate = function() end
function ISTickBox:addOption(label) self.label = label end
function ISTickBox:setWidthToFit() self.width = 180 end
function ISTickBox:setSelected(_, selected) self.selected = selected end
local starts, ticks = {}, {}
Events = {OnGameStart = {Add = function(fn) starts[#starts+1] = fn end},
    OnTick = {Add = function(fn) ticks[#ticks+1] = fn end, Remove = function(fn) assert(ticks[1] == fn) end}}
LootSorter = {DBG = function() end}
local player, otherPlayer, storage, carried = {}, {}, {}, {}
local busy = false
ISTimedActionQueue = {isPlayerDoingAction = function() return busy end}
local ordinaryContainers = {carried}
local function containerList()
    local values = {}
    for _, value in ipairs(ordinaryContainers) do values[#values + 1] = value end
    return {add=function(_,value) values[#values+1]=value end,
        contains=function(_,value) for _,entry in ipairs(values) do if entry==value then return true end end;return false end,
        size=function() return #values end, get=function(_,i) return values[i+1] end}
end
ISInventoryPaneContextMenu = {getContainers = containerList}
LootSorter.gatherBoxes = function(who) assert(who==player);return {{container=storage}} end
local function refresh(self, callback)
    self.containers = ISInventoryPaneContextMenu.getContainers(self.player)
    if callback then callback() end
    return true, nil, 'upstream-result'
end
ISHandCraftPanel = {updateContainers=refresh}
NC_HandCraftPanel = {updateContainers=refresh, update=refresh}
NC_CraftLogicPanel = {updateContainers=refresh}
NC_CraftActionPanel = {prerender=function(self) self.rendered=true end}
local function windowClass()
    local class = ISPanel:derive('CraftWindow')
    function class:createChildren()
        self.headerHeight = 32
        local header = ISTableLayout:new(0, 0, self.width, 32)
        header.padding = 6
        header:addRowFill(nil)
        for _, width in ipairs({50, 120, 70, 200, 90}) do
            local column = header:addColumn(nil, false)
            column.minimumWidth = width
            header:setElement(header:columnCount()-1, 0, panel(width, 18))
        end
        header:column(3).isAutoFill = true
        header.buttonPanel = header:cell(4, 0).element
        header.searchComponent = header:cell(3, 0).element
        header.buttonColumn = header:column(4)
        self.header = header; self:addChild(header)
        self:calculateLayout(self.width, self.height)
    end
    function class:calculateLayout(w, h)
        self.header:calculateLayout(w, self.headerHeight)
        self.width, self.height = self.header:getWidth(), h
        self.header:setY(self.bottom and h-self.headerHeight or 0)
    end
    function class:prerender() self.rendered = true end
    return class
end
NC_HandcraftWindow, NC_EntityWindow = windowClass(), windowClass()
dofile(NativeQuartermasterLuaRoot .. '/client/LootSorter_CraftMenu.lua')
for _, fn in ipairs(starts) do fn() end
local wrapped = NC_HandcraftWindow.prerender
for _, fn in ipairs(starts) do fn() end
assert(wrapped == NC_HandcraftWindow.prerender, 'installation duplicated')
for _, class in ipairs({NC_HandcraftWindow, NC_EntityWindow}) do
    for _, bottom in ipairs({false, true}) do
        local window = class:new(20, 40, 900, 600)
        window.bottom = bottom; window:createChildren()
        local tick, header = window.qmTick, window.header
        local callback, tooltip = tick.callback, tick.tooltip
        for _, size in ipairs({{900,600,32},{500,450,40},{900,40,40},{1100,700,24}}) do
            window.headerHeight = size[3]
            header.buttonColumn.minimumWidth = 120 -- mirrors Neat's applyHeaderMetrics
            window:calculateLayout(size[1], size[2])
            for _ = 1, 3 do window:prerender() end
            assert(header:columnCount() == 6, 'repeated rendering grows header')
            assert(tick.parent == header and not window.children[tick])
            assert(tick:getX() >= header.searchComponent:getX()+header.searchComponent:getWidth())
            assert(tick:getX()+tick:getWidth() <= header.buttonPanel:getX())
            assert(tick:getY() >= 0 and tick:getY()+tick:getHeight() <= header:getHeight())
            assert(header:getY() == (bottom and window:getHeight()-window.headerHeight or 0))
            assert(header.buttonColumn == header:column(5), 'metrics resize wrong column')
            assert(window.rendered and tick.callback == callback and tick.tooltip == tooltip)
        end
        callback(tick.target, 1, true); window:prerender()
        assert(LootSorter.craftFromBoxes and LootSorter._craftDirty and tick.selected)
        callback(tick.target, 1, false); window:prerender()
        assert(not LootSorter.craftFromBoxes and not tick.selected)
    end
end
NC_HandcraftWindow, NC_EntityWindow = nil, nil
for _, fn in ipairs(starts) do fn() end -- repeated optional-mod setup is harmless

-- Only the actual refresh call may expose storage, and only for its player.
LootSorter.craftFromBoxes = true
local function ordinary()
    assert(ISInventoryPaneContextMenu.getContainers(player):size()==1, 'storage leaked outside craft refresh')
end
local actionPanel={player=player}
NC_CraftActionPanel.prerender(actionPanel)
assert(actionPanel.rendered, 'upstream crafting render was skipped')
ordinary()
for _,entry in ipairs({{ISHandCraftPanel,'updateContainers'},{NC_HandCraftPanel,'updateContainers'},
    {NC_HandCraftPanel,'update'},{NC_CraftLogicPanel,'updateContainers'}}) do
    local instance={player=player}
    local a,b,c=entry[1][entry[2]](instance,function()
        assert(craftContainers.active() and craftContainers.active(player), 'refresh lacks player scope')
        assert(ISInventoryPaneContextMenu.getContainers(otherPlayer):size()==1, 'scope leaked to another player')
    end)
    assert(a==true and b==nil and c=='upstream-result','upstream return values changed')
    assert(instance.containers:size()==2 and instance.containers:get(1)==storage,'refresh missed designated storage')
    ordinary()
end
-- A designated box can already be in ordinary reach; repeated registry entries
-- must not expose its physical items a second time to native crafting logic.
ordinaryContainers = {carried, storage}
local originalGather = LootSorter.gatherBoxes
LootSorter.gatherBoxes = function() return {{container=storage},{container=storage}} end
local overlapping = {player=player}
ISHandCraftPanel.updateContainers(overlapping)
assert(overlapping.containers:size()==2 and overlapping.containers:get(0)==carried
    and overlapping.containers:get(1)==storage, 'availability duplicated an already accessible storage container')
ordinaryContainers = {carried}
ISHandCraftPanel.updateContainers(overlapping)
assert(overlapping.containers:size()==2, 'availability duplicated a repeated remote storage container')
LootSorter.gatherBoxes = originalGather
craftContainers.withContext(player,function()
    craftContainers.withContext(otherPlayer,function()
        assert(not craftContainers.active(player) and craftContainers.active(otherPlayer), 'nested player scope is wrong')
    end)
    assert(craftContainers.active(player), 'nested scope did not restore its caller')
    assert(craftContainers.inventory(player):size()==1, 'inventory-only read retained storage context')
    assert(craftContainers.active(player), 'inventory read destroyed outer context')
end)
local ok,problem=pcall(function() NC_HandCraftPanel.update({player=player},function() error('refresh failure') end) end)
assert(not ok and tostring(problem):find('refresh failure',1,true), 'upstream error was swallowed')
assert(not craftContainers.active(), 'failed refresh retained player scope');ordinary()
for _,guard in ipairs({'busy','hauling','disabled'}) do
    busy=guard=='busy';LootSorter._activelyCrafting=guard=='hauling';LootSorter.craftFromBoxes=guard~='disabled'
    local instance={player=player};ISHandCraftPanel.updateContainers(instance)
    assert(instance.containers:size()==1,'storage exposed while '..guard)
end
busy=false;LootSorter._activelyCrafting=false;LootSorter.craftFromBoxes=true
-- The error fallback must discard cached storage even if invoked inside a refresh.
ISBaseTimedAction=ISBaseObject
dofile(NativeQuartermasterLuaRoot .. '/client/LootSorter_Craft.lua')
local logic={setContainers=function(self,values) self.containers=values end,
    autoPopulateInputs=function(self)
        self.populated=true
        local nested={player=player};ISHandCraftPanel.updateContainers(nested)
        assert(nested.containers:size()==1,'fallback callback re-enabled distant storage')
    end}
craftContainers.withContext(player,function() LootSorter.craft.repinInventoryOnly(logic,player) end)
assert(logic.containers:size()==1 and logic.populated, 'fallback craft retained distant ingredients')
ordinary()
print('Quartermaster crafting UI: header layout, toggles, scoped refreshes, player isolation, nested/error cleanup and inventory fallback passed.')
