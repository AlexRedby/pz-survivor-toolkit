require = function() end
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
ISInventoryPaneContextMenu = {getContainers = function() end}
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
print('Quartermaster crafting UI: owned injection and real native table layout, both windows, resize, bottom/collapse and toggles passed.')
