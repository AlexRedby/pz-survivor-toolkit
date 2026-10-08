local layout = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/InventoryLayout.lua'
local start = {}
Events = {OnGameStart={Add=function(fn) start[#start+1] = fn end}}
require = function() end
local fontSize = 3.5
getCore = function() return {getOptionFontSizeReal=function() return fontSize end,
    getGameMode=function() return 'Sandbox' end} end

-- This is the shared vanilla/CleanUI tree-arrow block; an optional real source
-- exercises the game's exact draw calls instead of this fixture.
local source = CleanUIInventoryPaneSource or [[
                if count == 1 and v.count > 2 then
                    if not doDragged then
                        local texWH = self.cleanUIItemIconSize or math.min(self.itemHgt-2,32)
                        local texOffsetX = self.column2-texWH-(self.itemHgt-texWH)/2+xoff
                        local size = math.min(15, 8+getCore():getOptionFontSizeReal()*2)
                        local xPos = math.max(2, (2+texOffsetX-size)/2)
                        if not self.collapsed[v.name] then
                            self:drawTextureScaled(self.treeexpicon, xPos, (y*self.itemHgt)+self.headerHgt+(self.itemHgt-15)/2+yoff, size, size, 1, 1, 1, 0.8)
                        else
                            self:drawTextureScaled(self.treecolicon, xPos, (y*self.itemHgt)+self.headerHgt+(self.itemHgt-15)/2+yoff, size, size, 1, 1, 1, 0.8)
                        end
                    end
                end

                if self.selected[y+1] ~= nil
]]
local arrow = assert(source:match('(if count == 1 and v.count > 2 then.-)\n%s*if self.selected%[y%+1%]'))
local drawArrow = assert(loadstring('return function(self, doDragged) local count,y,xoff,yoff=1,0,0,0; local v={count=3,name="stack"}; '..arrow..' end'))()
local native = {renderdetails=function() return 'vanilla' end}
local enhanced = {}
function enhanced:renderdetails(doDragged, token)
    self.iconX = self.column2-self.cleanUIItemIconSize-(self.itemHgt-self.cleanUIItemIconSize)/2
    drawArrow(self, doDragged)
    return token
end
CleanUI_Clean_ISInventoryPane, ISInventoryPane = enhanced, native
dofile(layout)
start[1]()
local wrapped = enhanced.renderdetails
start[1]()
assert(enhanced.renderdetails == wrapped, 'installed twice')
assert(native:renderdetails() == 'vanilla', 'vanilla class changed')

local pane = setmetatable({column2=35,column3=235,itemHgt=34,cleanUIItemIconSize=32,
    headerHgt=20,treeexpicon='expanded',treecolicon='collapsed',collapsed={stack=true},resizeCount=0}, {__index=enhanced})
function pane:onResize()
    self.resizeCount = self.resizeCount + 1
    self.nameHeaderX, self.nameHeaderWidth = 0, self.column3
end
function pane:drawTextureScaled(texture, x, y, width)
    self.arrowTexture, self.arrowX, self.arrowWidth = texture, x, width
end
local function check(rowHeight, iconSize, baseColumn, headerHeight)
    local width = pane.column3-pane.column2
    pane.itemHgt,pane.cleanUIItemIconSize,pane.headerHgt=rowHeight,iconSize,headerHeight
    pane.column2,pane.column3=baseColumn,baseColumn+width
    assert(pane:renderdetails(false, 'render result') == 'render result')
    assert(pane.iconX-pane.arrowX-pane.arrowWidth >= 2, 'arrow overlaps item icon')
    assert(pane.column3-pane.column2 == width, 'Name column width changed')
    assert(pane.nameHeaderX == 0 and pane.nameHeaderWidth == pane.column3, 'header geometry stale')
    -- All native group mouse checks use the same column2 (single/down, double,
    -- and mouse-up's >= test). The arrow remains in that original hit area.
    assert(pane.arrowX >= 0 and pane.arrowX+pane.arrowWidth < pane.column2)
    local resizeCount = pane.resizeCount
    pane:renderdetails(false)
    assert(pane.resizeCount == resizeCount, 'reflows every frame')
end
check(34,32,35,20)
assert(pane.arrowTexture == 'collapsed')
pane.collapsed.stack=false
check(46,44,47,28)
assert(pane.arrowTexture == 'expanded')
check(66,64,67,0)
fontSize=1
check(24,22,36,20)
check(25,22,36,20)

-- Run the real mouse handlers when source is available, without copying their
-- hit tests. Arrow clicks must toggle once, while mouse-up must not select.
for _, mouseSource in ipairs({CleanUIInventoryPaneSource or false, NativeInventoryPaneSource or false}) do
    if mouseSource then
        ISInventoryPane = enhanced
        for _, name in ipairs({'onMouseDown','onMouseDoubleClick','onMouseUp'}) do
            local method = assert(mouseSource:match('(function ISInventoryPane:'..name..'%(.-)\nfunction ISInventoryPane:'))
            assert(loadstring(method))()
        end
        getSpecificPlayer=function() return {nullifyAiming=function() end} end
        getPlayerInventory=function() return {inventory={}} end
        getPlayerLoot=getPlayerInventory
        isShiftKeyDown=function() return false end
        isCtrlKeyDown=isShiftKeyDown
        instanceof=function() return false end
        CleanUI_getColumnDividerAtPoint=function() end
        ISMouseDrag={}
        pane.items,pane.mouseOverOption,pane.player,pane.selected={{name='stack'}},1,0,{}
        pane.draggedItems={reset=function() end}
        pane.refreshContainer=function() end
        pane.selectIndex=function() error('arrow mouse-up selected the item') end
        local x,y=pane.arrowX+pane.arrowWidth/2,pane.headerHgt+pane.itemHgt/2
        local collapsed=pane.collapsed.stack
        pane:onMouseDown(x,y)
        assert(pane.collapsed.stack ~= collapsed, 'arrow mouse-down missed group')
        pane:onMouseUp(x,y)
        pane:onMouseDoubleClick(x,y)
        assert(pane.collapsed.stack == collapsed, 'arrow double-click missed group')
    end
end

-- Live CleanUI -> vanilla -> CleanUI swaps globals and recreates panes;
-- the stored enhanced class keeps its wrapper and vanilla keeps its renderer.
ISInventoryPane = native
assert(ISInventoryPane:renderdetails() == 'vanilla')
start[1]()
ISInventoryPane = enhanced
assert(ISInventoryPane.renderdetails == wrapped)
check(34,32,35,20)
-- A class without CleanUI metrics receives the original call unchanged.
CleanUI_Clean_ISInventoryPane=nil
ISInventoryPane={renderdetails=function(_,dragged,value) return dragged,value end}
start[1]()
local dragged,value=ISInventoryPane:renderdetails(true,'unchanged')
assert(dragged == true and value == 'unchanged')
print('Inventory layout checks passed.')
