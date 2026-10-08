-- Run with --cci-source to exercise the real third-party renderer too.
local function run(initialEnhanced, lateVanilla)
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
local lastAlpha
ISInventoryItem = {renderItemIcon=function(_, _, _, _, alpha) lastAlpha = alpha end}
local buttonCalls, detailsCalls, iconsCalls = 0, 0, 0
ISInventoryPage = {addContainerButton=function(page, inventory)
    buttonCalls = buttonCalls + 1
    local button = page.pooledButton or {render=function() end, getWidth=function() return 32 end,
        getHeight=function() return 32 end, drawRect=function(self, x,y,w,h,alpha)
            self.fill = h == 2 and w or self.fill
            if h == 4 and alpha == 0.88 then self.bars = (self.bars or 0) + 1 end
        end, drawRectBorder=function() end}
    button.inventory = inventory
    return button
end}
ISInventoryPane = {MAX_ITEMS_IN_STACK_TO_RENDER=50}
function ISInventoryPane:renderdetails(dragged)
    detailsCalls = detailsCalls + 1
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
ISInventoryPane.rendericons = function() iconsCalls = iconsCalls + 1; return 'icons result' end
CleanUI_Clean_ISInventoryPane, CleanUI_Clean_ISInventoryPage = ISInventoryPane, ISInventoryPage
CleanUI_Vanilla_ISInventoryPane = {MAX_ITEMS_IN_STACK_TO_RENDER=50, renderdetails=function()
    detailsCalls = detailsCalls + 1
    return 'vanilla result'
end, rendericons=ISInventoryPane.rendericons}
CleanUI_Vanilla_ISInventoryPage = {addContainerButton=ISInventoryPage.addContainerButton}
local vanillaPaneClass, vanillaPageClass = CleanUI_Vanilla_ISInventoryPane, CleanUI_Vanilla_ISInventoryPage
if lateVanilla then CleanUI_Vanilla_ISInventoryPane, CleanUI_Vanilla_ISInventoryPage = nil, nil end
local callbacks = {}
local function toggle(enhanced)
    if not enhanced then
        CleanUI_Vanilla_ISInventoryPane, CleanUI_Vanilla_ISInventoryPage = vanillaPaneClass, vanillaPageClass
    end
    ISInventoryPane = enhanced and CleanUI_Clean_ISInventoryPane or CleanUI_Vanilla_ISInventoryPane
    ISInventoryPage = enhanced and CleanUI_Clean_ISInventoryPage or CleanUI_Vanilla_ISInventoryPage
    for _, callback in ipairs(callbacks) do callback(enhanced) end
end
CleanUI_RegisterInventoryUiToggleCallback = function(callback)
    callbacks[#callbacks+1] = callback
    callback(initialEnhanced)
end
toggle(initialEnhanced)
baseDetails = ISInventoryPane.renderdetails
local baseIcons, baseButton, baseItemIcon = ISInventoryPane.rendericons, ISInventoryPage.addContainerButton, ISInventoryItem.renderItemIcon
local source = CCISource or [[
local base = ISInventoryPane.renderdetails
PZAPI.ModOptions:create('ContainerCapacityIndicator')
function ISInventoryPane:renderdetails(dragged)
    local result = base(self, dragged)
    if not dragged then
        local row = 0
        for _, stack in ipairs(self.itemslist) do
            for index, item in ipairs(stack.items or {}) do
                if index == 1 or not self.collapsed[stack.name] then
                    if item.IsInventoryContainer then
                        local size = math.min(self.itemHgt-2,32)
                        local x = index > 1 and 26 or self.column2-size-(self.itemHgt-size)/2
                        self:drawRect(x+1,self.headerHgt+row*self.itemHgt+(self.itemHgt-size)/2+size-4,size-2,4,0.88)
                    end
                    row = row + 1
                end
            end
        end
    end
    return result
end
]]
local cciLoads = 0
require = function(name)
    if name == 'ContainerCapacityIndicator' then
        cciLoads = cciLoads + 1
        assert(loadstring(source))()
    end
end
-- No dependencies: unchanged native rendering; wrong order: unchanged CCI hook.
for _, selection in ipairs({{}, {CleanUI=true}, {ContainerCapacityIndicator=true}}) do
    active = selection
    dofile(adapter)
    assert(ISInventoryPane.renderdetails == baseDetails and ISInventoryPane.rendericons == baseIcons)
    assert(ISInventoryPage.addContainerButton == baseButton and ISInventoryItem.renderItemIcon == baseItemIcon)
    assert(cciLoads == 0 and #callbacks == 0)
end
active.CleanUI, active.ContainerCapacityIndicator = true, true
options.ContainerCapacityIndicator = {}
dofile(adapter)
assert(ISInventoryPane.renderdetails == baseDetails and ISInventoryPane.rendericons == baseIcons)
assert(ISInventoryPage.addContainerButton == baseButton and ISInventoryItem.renderItemIcon == baseItemIcon)
assert(cciLoads == 0 and #callbacks == 0)
options.ContainerCapacityIndicator = nil
dofile(adapter)
assert(#callbacks == 1, 'toggle callback missing or duplicated')
ISInventoryItem.renderItemIcon({}, a, 14, 14)
assert(lastAlpha == 1, 'native icon view received nil alpha')
ISInventoryItem.renderItemIcon({}, a, 14, 14, 0)
assert(lastAlpha == 0, 'explicit transparent icon alpha changed')
toggle(true)
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
    local before = detailsCalls
    assert(pane:renderdetails(false)=='native result')
    assert(detailsCalls == before + 1, 'native details called more than once')
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
end
-- Both initial modes, late class loading and repeated switches retain every upstream hook.
toggle(false)
toggle(true)
local enhancedDetails, vanillaDetails = CleanUI_Clean_ISInventoryPane.renderdetails, CleanUI_Vanilla_ISInventoryPane.renderdetails
for _, enhanced in ipairs({false,true,false,true,false,true}) do
    toggle(enhanced)
    assert(CleanUI_Clean_ISInventoryPane.renderdetails == enhancedDetails)
    assert(CleanUI_Vanilla_ISInventoryPane.renderdetails == vanillaDetails)
    if enhanced then
        check({{items={a}},a,{type='separator'},{items={b}},b},4)
    else
        local vanilla = setmetatable({itemslist={{name='a',items={a,a}}, {name='b',items={b,b}}},
            collapsed={}, column2=45,headerHgt=20,itemHgt=34,height=500,
            getYScroll=function() return 0 end,drawRect=rect,drawRectBorder=border}, {__index=ISInventoryPane})
        drawn={}
        local before=detailsCalls
        assert(vanilla:renderdetails(false)=='vanilla result' and detailsCalls==before+1)
        assert(#drawn==4, 'vanilla overlays missing or duplicated')
        vanilla.collapsed.a=true
        drawn={}
        vanilla:renderdetails(false)
        assert(#drawn==3, 'vanilla collapsed rows ignored')
        drawn={}
        vanilla:renderdetails(true)
        assert(#drawn==0, 'dragged details received overlays')
        if CCISource then
            vanilla.itemslist={{items={magazine}}}
            magazineEnabled=true
            vanilla:renderdetails(false)
            assert(#drawn==1, 'vanilla magazine indicator missing')
            magazineEnabled=false
            drawn={}
            vanilla:renderdetails(false)
            assert(#drawn==0, 'vanilla magazine option ignored')
        end
    end
    if CCISource then
        local items={a,magazine,b}
        local iconPane=setmetatable({width=100,inventory={getItems=function() return {
            size=function() return #items end,get=function(_, index) return items[index+1] end} end},
            drawRect=rect,drawRectBorder=border}, {__index=ISInventoryPane})
        local before=iconsCalls
        magazineEnabled=true
        drawn={}
        assert(iconPane:rendericons()=='icons result' and iconsCalls==before+1)
        assert(#drawn==3, 'icon overlays missing or duplicated')
        assert(drawn[1].x==15 and drawn[1].y==42 and drawn[1].w==30)
        assert(drawn[2].x==55 and drawn[2].y==42 and drawn[3].x==15 and drawn[3].y==82)
        magazineEnabled=false
        drawn={}
        iconPane:rendericons()
        assert(#drawn==2, 'icon magazine option ignored')
        local page=setmetatable({player=1}, {__index=ISInventoryPage})
        before=buttonCalls
        local button=page:addContainerButton(inventoryA)
        assert(buttonCalls==before+1 and button.cciPlayer==1)
        button:render()
        assert(button.fill==5 and button.bars==1)
        page.pooledButton=button
        page:addContainerButton(inventoryB)
        button.x,button.y=80,120
        button:render()
        assert(button.fill==23 and button.bars==2, 'pooled button stale or double decorated')
    end
end
assert(cciLoads == 1, 'CCI was reloaded during mode switches')
magazineEnabled=true
toggle(true)
rows,drawn={{items={a}}},{}
assert(pane:renderdetails(true)=='native result' and #drawn==0)
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

end
run(true)
run(false)
run(true, true)
