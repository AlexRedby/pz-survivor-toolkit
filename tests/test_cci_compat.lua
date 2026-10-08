-- Run with --cci-source to exercise the real third-party renderer too.
local adapter = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/000ToolkitCCICompatibility.lua'
local active, options = {}, {}
getActivatedMods = function() return {contains=function(_, id) return active[id] end} end
PZAPI = {ModOptions={getOptions=function(_, id) return options[id] end}}
function PZAPI.ModOptions:create(id)
    options[id] = self
    return self
end
local magazineEnabled = true
function PZAPI.ModOptions:addTickBox() return {getValue=function() return magazineEnabled end} end
getSpecificPlayer = function() return {} end
local inventoryA = {getEffectiveCapacity=function() return 10 end, getCapacityWeight=function() return 2 end}
local inventoryB = {getEffectiveCapacity=function() return 10 end, getCapacityWeight=function() return 9 end}
local function bag(inventory)
    return {IsInventoryContainer=function() return true end, getInventory=function() return inventory end}
end
local a, b = bag(inventoryA), bag(inventoryB)
local magazine = {IsWeapon=function() return false end, getMaxAmmo=function() return 16 end,
    getAmmoType=function() return '9mm' end, getCurrentAmmoCount=function() return 8 end}
local rows, fail, failOverlay = {}, false, false
ISInventoryItem = {renderItemIcon=function() end}
ISInventoryPage = {addContainerButton=function(_, inventory)
    return {inventory=inventory, render=function() end, getWidth=function() return 32 end,
        getHeight=function() return 32 end, drawRect=function(self, x,y,w,h,alpha)
            self.fill = h == 2 and w or self.fill
        end, drawRectBorder=function() end}
end}
ISInventoryPane = {MAX_ITEMS_IN_STACK_TO_RENDER=50}
function ISInventoryPane:renderdetails(dragged)
    if fail then error('native failure') end
    self.items = rows
    for index, row in ipairs(rows) do
        if row.type ~= 'separator' then
            local item = row.items and row.items[1] or row
            local size = self.cleanUIItemIconSize
            local x = row.items and self.column2-size-(self.itemHgt-size)/2 or 26
            ISInventoryItem.renderItemIcon(self, item, x, self.headerHgt+(index-1)*self.itemHgt+(self.itemHgt-size)/2, 1,size,size)
        end
    end
    return 'native result'
end
local baseDetails = ISInventoryPane.renderdetails
ISInventoryPane.rendericons = function() end
local source = CCISource or [[
local base = ISInventoryPane.renderdetails
PZAPI.ModOptions:create('ContainerCapacityIndicator')
function ISInventoryPane:renderdetails(dragged)
    local result = base(self, dragged)
    if not dragged then
        local row = 0
        for _, stack in ipairs(self.itemslist) do
            for index, item in ipairs(stack.items or {}) do
                if item.IsInventoryContainer then
                    local size = math.min(self.itemHgt-2,32)
                    local x = index > 1 and 26 or self.column2-size-(self.itemHgt-size)/2
                    self:drawRect(x+1,self.headerHgt+row*self.itemHgt+(self.itemHgt-size)/2+size-4,size-2,4,0.88)
                end
                row = row + 1
            end
        end
    end
    return result
end
]]
require = function(name)
    if name == 'ContainerCapacityIndicator' then assert(loadstring(source))() end
end
-- No dependencies: unchanged native rendering; wrong order: unchanged CCI hook.
dofile(adapter)
assert(ISInventoryPane.renderdetails == baseDetails)
active.CleanUI, active.ContainerCapacityIndicator = true, true
options.ContainerCapacityIndicator = {}
dofile(adapter)
assert(ISInventoryPane.renderdetails == baseDetails)
options.ContainerCapacityIndicator = nil
dofile(adapter)
local originalList = {{items={a,a}}, {type='separator'}, {equipped=true,items={b,b}}}
local drawn = {}
local pane = setmetatable({itemslist=originalList, collapsed={}, column2=45, headerHgt=20,
    itemHgt=34,cleanUIItemIconSize=32, height=500, getYScroll=function(self) return self.scroll or 0 end,
    drawRect=function(_,x,y,w,h,alpha)
        if failOverlay then error('overlay failure') end
        if h==4 and (alpha==0.88 or alpha==0.92) then drawn[#drawn+1]={x=x,y=y,w=w} end
    end, drawRectBorder=function() end}, {__index=ISInventoryPane})
local rect, border, scroll = pane.drawRect, pane.drawRectBorder, pane.getYScroll
local function check(visible, count)
    rows, drawn = visible, {}
    assert(pane:renderdetails(false)=='native result')
    assert(pane.itemslist==originalList and pane.drawRect==rect and pane.drawRectBorder==border and pane.getYScroll==scroll)
    assert(#drawn==count, 'wrong bar count: '..#drawn)
    local barIndex=0
    for index,row in ipairs(rows) do
        if row.type~='separator' then
            barIndex=barIndex+1
            local bar=drawn[barIndex]
            local size=pane.cleanUIItemIconSize
            local x=row.items and pane.column2-size-(pane.itemHgt-size)/2 or 26
            assert(bar.x==x+1 and bar.w==size-2)
            assert(bar.y==pane.headerHgt+(index-1)*pane.itemHgt+(pane.itemHgt-size)/2+size-4)
        end
    end
end
check({{items={a}},a,{type='separator'},{items={b}},b},4)
check({{items={a}},{type='separator'},{items={b}}},2)
check({{items={a}},{type='separator'}},1)
pane.itemHgt,pane.cleanUIItemIconSize=46,44
check({{items={a}},a,{type='separator'},{items={b}}},3)
if CCISource then
    -- Old CCI geometry is above the header; the scaled icon bar is still visible.
    pane.scroll=-35
    check({{items={a}}},1)
    pane.scroll=0
    check({{items={magazine}}},1)
    magazineEnabled=false
    rows,drawn={{items={magazine}}},{}
    pane:renderdetails(false)
    assert(#drawn==0, 'CCI magazine setting ignored')
    local button=ISInventoryPage:addContainerButton(inventoryA)
    button:render()
    assert(button.fill==5)
    button.x,button.y,button.inventory=80,120,inventoryB
    button:render()
    assert(button.fill==23, 'pooled/moved button retained previous fill')
end
-- Both error paths must leave the real pane reusable.
for _, overlay in ipairs({false,true}) do
    rows={{items={a}}}
    fail,failOverlay=not overlay,overlay
    assert(not pcall(pane.renderdetails,pane,false))
    assert(pane.itemslist==originalList and pane.drawRect==rect and pane.drawRectBorder==border and pane.getYScroll==scroll)
end
fail,failOverlay=false,false
check({{items={a}}},1)
print('CleanUI / CCI compatibility checks passed.')
