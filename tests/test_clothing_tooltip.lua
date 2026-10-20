-- Exercise native placement and the upstream compositor, with small content
-- providers. Real BCI contents and ObjectTooltip Layout are checked in game.
if not NativeTooltipLuaRoot or not NativeBCITooltipRoot then
    print('Clothing tooltip: native/BCI sources absent; source-backed checks skipped.')
    return
end
local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/'
package.path = root .. '?.lua;' .. package.path
ISPanel = {derive = function() return {} end}
package.loaded['ISUI/ISPanel'] = true
dofile(NativeTooltipLuaRoot .. '/client/ISUI/ISToolTipInv.lua')
package.loaded['ISUI/ISToolTipInv'] = true
local player, enabled = {}, true
getActivatedMods = function() return {contains = function(_, id) return enabled and id == 'EURY_CLOTHINGINFO' end} end
getCore = function() return {getScreenWidth = function() return 1000 end, getScreenHeight = function() return 800 end,
    getBadHighlitedColor = function() return {getR = function() return 1 end, getG = function() return 0.2 end,
        getB = function() return 0.1 end} end} end
getMouseX, getMouseY = function() return 950 end, function() return 750 end
getPlayerScreenLeft, getPlayerScreenTop = function() return 100 end, function() return 50 end
UIFont = {Small = 'Small'}
getTextManager = function() return {MeasureStringX = function(_, _, text) return #text * 6 end} end
getText = function(key) assert(key == 'Tooltip_NoRecipes_More'); return 'Excluded<br>from crafting' end
ISContextMenu = {}
dofile(NativeBCITooltipRoot .. '/EuryTooltipController.lua')
local controller = EuryTooltipController
local flagged, comparison = false, true
local clothingItem = {isNoRecipes = function(_, who) assert(who == player); return flagged end}
local function window()
    local target = {character = player, padBottom = 5, padLeft = 5, labels = {}, calls = {}, texts = {}}
    local panel = setmetatable({item = clothingItem, tooltip = target, x = 900, y = 750,
        width = 0, height = 0, followMouse = false, backgrounds = {},
        backgroundColor = {r = 0, g = 0, b = 0, a = 0.5}, borderColor = {r = 1, g = 1, b = 1, a = 1}},
        {__index = ISToolTipInv})
    for _, object in ipairs({panel, target}) do
        for _, name in ipairs({'X','Y','Width','Height'}) do
            local key = name:lower()
            object['get' .. name] = function(self) return self[key] end
            object['set' .. name] = function(self, value) self[key] = value end
        end
    end
    target.getCharacter = function(self) return self.character end
    target.getFont = function() return UIFont.Small end
    target.getLineSpacing = function() return 18 end
    target.DrawText = function(self, _, text) self.texts[#self.texts+1] = text end
    target.setMeasureOnly = function(self, value) self.measure = value end
    target.beginLayout = function(self)
        return {addItem = function()
            return {setLabel = function(_, text, r, g, b)
                assert(text == 'Excluded<br>from crafting' and r == 1 and g == 0.2 and b == 0.1)
                self.labels[#self.labels + 1] = {measure = self.measure}
            end}
        end, render = function(_, _, y, destination) assert(destination == self); return y + 36 end}
    end
    target.endLayout = function() end
    panel.drawRect = function(self, x, y, w, h, alpha)
        self.backgrounds[#self.backgrounds + 1] = {x=x,y=y,w=w,h=h,alpha=alpha}
    end
    panel.drawRectBorder = function() end
    return panel
end
local provider = {getPadX = function() return 7 end, attachedGap = 8,
    isClothing = function(_, ctx) return ctx.item == clothingItem end,
    handles = function(_, ctx) return ctx.item == clothingItem end,
    renderMain = function(_, ctx)
        local target = ctx.tooltip
        target.calls[#target.calls + 1] = {kind = 'main', measure = target.measure, x = target.x, y = target.y}
        target:setWidth(200); target:setHeight(180)
    end,
    getSidePanel = function()
        if comparison then return {render = function(target)
            target.calls[#target.calls + 1] = {kind = 'side', measure = target.measure, x = target.x, y = target.y}
            target:setWidth(140); target:setHeight(100)
        end} end
    end}
controller:registerProvider('BetterClothingInfo', provider)
-- Avoid loading BCI content into doubles: this test owns only the provider
-- interface; the native fixture forwards the real BCI main/comparison.
package.loaded['BCI/Patches/TooltipInv'] = true
local adapter = require 'PZSurvivorToolkit/InventoryClothingTooltip'
local function render(panel) controller:render(panel); return panel end

-- Actual upstream code overwrites the joypad position with the mouse clamp.
local old = window(); old.contextMenu = {joyfocus = {}, player = 0}
render(old)
assert(old.x ~= 160 or old.y ~= 110, 'upstream placement defect no longer reproduced')
enabled = false
local original = controller.renderControlled
adapter.install(); assert(controller.renderControlled == original and not adapter.installed)
enabled = true; adapter.install()
local installed = controller.renderControlled
adapter.install(); assert(installed == controller.renderControlled, 'installation must be idempotent')
local joy = window(); joy.contextMenu = {joyfocus = {}, player = 0}; render(joy)
assert(joy.x == 160 and joy.y == 110, 'joypad position was overwritten')
assert(joy.width == 362 and joy.height == 180)
assert(#joy.tooltip.calls == 4 and #joy.backgrounds == 2)
assert(joy.tooltip.calls[1].measure and joy.tooltip.calls[2].measure
    and not joy.tooltip.calls[3].measure and not joy.tooltip.calls[4].measure)
assert(joy.tooltip.calls[3].x == joy.x + 7 and joy.tooltip.calls[4].x == joy.x + 222)
assert(joy.backgrounds[1].w == 207 and joy.backgrounds[2].x == 215
    and joy.backgrounds[2].w == 147 and joy.backgrounds[1].alpha == 0.9)
local edge = render(window())
assert(edge.x == 637 and edge.y == 619, 'complete comparison must fit the screen')
local anchor = window(); anchor.anchorBottomLeft = {x=20,y=500}; render(anchor)
assert(anchor.x == 20 and anchor.y == 320, 'bottom anchor must use the measured height')
local context = window()
context.contextMenu = {currentOptionRect = {x=900,y=200,width=80,height=40}}
render(context)
assert(context.x == 530 and context.y == 200, 'first-frame context must use new dimensions')
assert(not context:overlaps({x=context.x,y=context.y,width=context.width,height=context.height},
    context.contextMenu.currentOptionRect))
local mouse = window(); mouse.followMouse = true; render(mouse)
assert(not mouse:overlaps({x=mouse.x,y=mouse.y,width=mouse.width,height=mouse.height},
    {x=926,y=726,width=48,height=48}), 'comparison must avoid the mouse')
flagged = true
local marked = render(window())
assert(marked.height == 216 and #marked.tooltip.labels == 2)
assert(marked.tooltip.labels[1].measure and not marked.tooltip.labels[2].measure)
assert(marked.backgrounds[1].h == 216 and marked.backgrounds[2].h == 100)
local noPlayer = window(); noPlayer.tooltip.character = nil; render(noPlayer)
assert(noPlayer.height == 180 and #noPlayer.tooltip.labels == 0)
flagged = false; comparison = false
local single = render(window())
assert(single.width == 207 and single.height == 180 and #single.backgrounds == 1 and #single.tooltip.labels == 0)
ISContextMenu.instance = {visibleCheck = true}
local hidden = render(window()); assert(#hidden.backgrounds == 0 and #hidden.tooltip.calls == 0)
ISContextMenu.instance = nil

-- Foreign row providers must retain the upstream path, not silently lose rows.
local boundary = require 'PZSurvivorToolkit/InventoryTooltip'
local renderBlocks = boundary.renderBlocks
boundary.renderBlocks = function() error('unexpected block compositor') end
controller:registerProvider('ForeignRows', {getRows = function() return {{text = 'Foreign metadata'}} end})
local foreign = render(window())
assert(foreign.height == 208 and foreign.tooltip.texts[1] == 'Foreign metadata',
    'unrecognized row providers must still render through upstream')
controller.providers.ForeignRows = nil
boundary.renderBlocks = renderBlocks
local broken = window()
local ok, err = pcall(boundary.renderBlocks, broken, {function() error('content failure') end}, {})
assert(not ok and tostring(err):find('content failure',1,true) and broken.tooltip.measure == false,
    'a failing provider must release native measure-only state')
-- Native avoidance falls back right -> above -> left in this crowded case.
-- Its -11 mouse offset belongs to the original renderer, not our outer frame.
getMouseX, getMouseY = function() return 600 end, function() return 300 end
local crowded = window(); crowded.followMouse = true
boundary.renderBlocks(crowded, {function(target) target:setWidth(600); target:setHeight(500) end}, {})
assert(crowded.x == 0 and crowded.y == 0, 'native mouse avoidance clipped the left edge of the complete frame')
print('Clothing tooltip: upstream placement reproduction, complete frame, native positioning, flag and error cleanup passed.')
