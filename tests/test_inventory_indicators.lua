local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/'
package.path = root .. '?.lua;' .. package.path
local function load(name) return assert(loadfile(root .. 'PZSurvivorToolkit/' .. name .. '.lua'))() end
package.loaded['PZAPI/ModOptions'] = true
getText = function(key) return key end
local created, ticks = {}, {}
PZAPI = {ModOptions = {create = function(_, id, title)
    created[#created + 1] = {id, title}
    return {addTickBox = function(_, id, label, default)
        local value = {value = default, label = label, getValue = function(self) return self.value end}
        ticks[id] = value
        return value
    end}
end}}
local Options = load('InventoryPlantingOptions')
package.loaded['PZSurvivorToolkit/InventoryPlantingOptions'] = Options
assert(#created == 1 and created[1][1] == 'SeedSeasonIndicator')
assert(Options.enabled() and Options.tooltip() and not Options.preferBest() and not Options.badMonths())
ticks.enabled.value = false
assert(not Options.enabled() and Options.tooltip(), 'badge and tooltip settings must be independent')
ticks.tooltip.value = false; ticks.enabled.value = true
assert(Options.enabled() and not Options.tooltip())
ticks.noBestStar.value = true; ticks.badMonth.value = true
assert(Options.preferBest() and Options.badMonths())
ticks.tooltip.value, ticks.noBestStar.value, ticks.badMonth.value = true, false, false

local localPlayer, tooltipPlayer, unknownPlayer = {}, {}, {}
local state = {crop = 'Test', currentMonth = 4, status = 'best', waterLvl = 35, growDays = 7,
    sowMonth = {4,5}, bestMonth = {4}, riskMonth = {5}, badMonth = {12}, texture = 'crop'}
local describeCalls, canResearch = {}, true
local Planting = {describe = function(player, item, best)
    describeCalls[#describeCalls + 1] = {player, item, best}
    if player == unknownPlayer then return nil end
    return item and item.state or state
end}
package.loaded['PZSurvivorToolkit/InventoryPlanting'] = Planting
package.loaded['PZSurvivorToolkit/InventoryResearch'] = {
    shouldShow = function(_, item) assert(item); return canResearch end,
    texture = function() return 'research' end,
}
getSpecificPlayer = function(index) assert(index == 2); return localPlayer end
getPlayer = function() return localPlayer end
getTexture = function(name) return {name = name, getWidth = function() return 16 end, getHeight = function() return 32 end} end
local Indicators = load('InventoryIndicators')
package.loaded['PZSurvivorToolkit/InventoryIndicators'] = Indicators
local draws = {}
local pane = {player = 2, headerHgt = 20, height = 300,
    getYScroll = function() return -10 end,
    drawTextureScaled = function(_, texture, x, y, w, h, alpha, r, g, b)
        draws[#draws + 1] = {texture = texture, x = x, y = y, width = w, height = h, color = {r,g,b}}
    end}
local seed = {category = 'Gardening', state = state}
Indicators.drawIcon(pane, seed, 70, 40, 32, 32, true)
assert(#draws == 2 and draws[1].texture == 'research')
assert(draws[1].x == 70 and draws[1].y == 40 and draws[2].x == 90 and draws[2].y == 40)
assert(draws[2].texture.name == 'media/ui/MP/mp_ui_star.png' and draws[2].width == 12)
assert(describeCalls[#describeCalls][1] == localPlayer and seed.category == 'Gardening')
draws = {}; ticks.enabled.value = false
Indicators.drawIcon(pane, seed, 70, 40, 32, 32, true)
assert(#draws == 1 and draws[1].texture == 'research', 'planting setting must not suppress research')
draws = {}; ticks.enabled.value = true; canResearch = false
ticks.tooltip.value = false
Indicators.drawIcon(pane, seed, 70, 40, 32, 32, true)
assert(#draws == 1, 'tooltip setting must not suppress planting badge')
draws = {}
Indicators.drawIcon(pane, seed, 70, 40, 32, 32, false)
Indicators.drawIcon(pane, seed, 70, 20, 32, 32, true)
Indicators.drawIcon(pane, seed, 70, 310, 32, 32, true)
Indicators.drawIcon(pane, seed, 70, 40, 4, 4, true)
assert(#draws == 0, 'offscreen and grid/drag icons must not synthesize indicators')
local risk = {}; for key, value in pairs(state) do risk[key] = value end
risk.status = 'risk'
Indicators.drawIcon(pane, {state = risk}, 103, 47, 24, 20, true)
assert(#draws == 1 and draws[1].x == 117 and draws[1].y == 47)
assert(draws[1].texture.name == 'media/ui/circle.png' and draws[1].color[1] == Indicators.colors.risk[1])
print('Inventory indicators: independent options, supplied coordinates, player and visibility passed.')

local function target()
    local value = {width = 150, height = 50, padBottom = 5, layouts = {}, nativeCalls = {}, images = {}}
    for _, field in ipairs({'Width', 'Height', 'X', 'Y'}) do
        local key = string.lower(field)
        value['get' .. field] = function(self) return self[key] or 0 end
        value['set' .. field] = function(self, number) self[key] = number end
    end
    value.getFont = function() return 'Small' end
    value.setCharacter = function(self, player) self.character = player end
    value.getCharacter = function(self) return self.character end
    value.setMeasureOnly = function(self, flag) self.measureOnly = flag end
    value.beginLayout = function(self)
        local layout = {rows = {}, target = self, measureOnly = self.measureOnly}
        self.layouts[#self.layouts + 1] = layout
        layout.addItem = function(layout)
            local entry = {}
            layout.rows[#layout.rows + 1] = entry
            entry.setLabel = function(self, text) self.label = text end
            entry.setValue = function(self, text) self.value = text end
            return entry
        end
        layout.setMinLabelWidth = function(self, width) self.minLabelWidth = width end
        layout.render = function(self, x, y, destination)
            assert(destination == self.target)
            self.x, self.y = x, y
            return y + #self.rows * 14
        end
        return layout
    end
    value.endLayout = function(self, layout) assert(layout.target == self) end
    value.DrawTextureScaled = function(self, texture, x, y, width, height)
        self.images[#self.images + 1] = {measureOnly = self.measureOnly, texture = texture, x = x, y = y, width = width, height = height}
    end
    return value
end
getTextManager = function() return {MeasureStringX = function(_, _, text) return #text * 6 end} end
local methods = {}
methods.DoTooltip = function(item, destination)
    destination.nativeCalls[#destination.nativeCalls + 1] = {item = item, measureOnly = destination.measureOnly}
    destination:setWidth(150); destination:setHeight(50)
    if item.onNative then item.onNative(destination) end
    if item.throw then error('native tooltip failure') end
    return 'native-result'
end
local function tooltipItem(class)
    return setmetatable({category = 'Gardening', state = state}, {__index = class or methods})
end
ISPanel = {derive = function() return {} end}
package.loaded['ISUI/ISPanel'] = true
-- Use the installed game's complete renderer when supplied by the runner.
if NativePlantingLuaRoot then
    dofile(NativePlantingLuaRoot .. '/client/ISUI/ISToolTipInv.lua')
else
    ISToolTipInv = {
        setCharacter = function(self, player) self.tooltip:setCharacter(player) end,
        render = function(self)
            self.tooltip:setMeasureOnly(true)
            self.item:DoTooltip(self.tooltip)
            self.tooltip:setMeasureOnly(false)
            self.width, self.height = self.tooltip:getWidth(), self.tooltip:getHeight()
            self.item:DoTooltip(self.tooltip)
        end,
    }
end
package.loaded['ISUI/ISToolTipInv'] = true
ISContextMenu = {}
getMouseX = function() return 0 end
getMouseY = function() return 0 end
getCore = function() return {getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end} end
local function window(item, destination)
    return setmetatable({item = item, tooltip = destination or target(), followMouse = false, x = 100, y = 100,
        backgroundColor = {a = 1, r = 0, g = 0, b = 0}, borderColor = {a = 1, r = 1, g = 1, b = 1},
        getX = function(self) return self.x end, getY = function(self) return self.y end,
        setX = function(self, number) self.x = number end, setY = function(self, number) self.y = number end,
        setWidth = function(self, number) self.width = number end, setHeight = function(self, number) self.height = number end,
        drawRect = function() end, drawRectBorder = function() end,
    }, {__index = ISToolTipInv})
end
local Tooltip = load('InventoryPlantingTooltip')
Tooltip.install(); local render = ISToolTipInv.render; Tooltip.install()
assert(render == ISToolTipInv.render, 'install must be idempotent')
ticks.tooltip.value = true
local plantingItem = tooltipItem()
local ui = window(plantingItem)
ui:setCharacter(tooltipPlayer)
ui:render()
assert(describeCalls[#describeCalls][1] == tooltipPlayer and ui.tooltip.character == tooltipPlayer)
assert(#ui.tooltip.nativeCalls == 2 and ui.tooltip.nativeCalls[1].measureOnly == true
    and ui.tooltip.nativeCalls[2].measureOnly == false, 'must preserve native measurement and draw passes')
assert(#ui.tooltip.layouts == 2 and #ui.tooltip.layouts[1].rows == 6 and #ui.tooltip.layouts[2].rows == 6)
assert(ui.tooltip.layouts[1].measureOnly and not ui.tooltip.layouts[2].measureOnly)
assert(ui.height == ui.tooltip:getHeight() and ui.width == ui.tooltip:getWidth(), 'native background must include extension dimensions')
assert(ui.tooltip.layouts[1].y == 45 and ui.tooltip.layouts[2].y == 45, 'native item details must precede planting details')
assert(ui.tooltip.images[2].x + ui.tooltip.images[2].width <= ui.width)
assert(plantingItem.category == 'Gardening' and state.status == 'best')
local wrapped = methods.DoTooltip
ui:render(); assert(methods.DoTooltip == wrapped, 'item class must be wrapped only once')
local outside = target()
assert(plantingItem:DoTooltip(outside) == 'native-result' and #outside.layouts == 0, 'no extension outside inventory tooltip render')

-- Matching the target alone or the item alone is insufficient.
local otherItem, otherTarget = tooltipItem(), target()
plantingItem.onNative = function(destination)
    otherItem:DoTooltip(destination)
    plantingItem.onNative = nil
    plantingItem:DoTooltip(otherTarget)
end
local scoped = window(plantingItem); scoped:render()
assert(#scoped.tooltip.layouts == 2 and #otherTarget.layouts == 0)

local hidden = window(tooltipItem()); hidden:setCharacter(unknownPlayer); hidden:render()
assert(#hidden.tooltip.layouts == 0, 'explicit native character must take priority over known getPlayer fallback')
local directCharacter = window(tooltipItem()); directCharacter:setCharacter(tooltipPlayer)
directCharacter.tooltip:setCharacter(unknownPlayer)
directCharacter:render()
assert(#directCharacter.tooltip.layouts == 0, 'native target character must take priority over cached setCharacter fallback')
local fallback = window(tooltipItem()); fallback:render()
assert(describeCalls[#describeCalls][1] == localPlayer and #fallback.tooltip.layouts == 2)
ticks.enabled.value = false
local tooltipOnly = window(tooltipItem()); tooltipOnly:render()
assert(#tooltipOnly.tooltip.layouts == 2, 'badge setting must not suppress tooltip')
ticks.enabled.value = true; ticks.tooltip.value = false
local disabled = window(tooltipItem()); disabled:render()
assert(#disabled.tooltip.layouts == 0)
ticks.tooltip.value = true; ticks.badMonth.value = true
local badMonths = window(tooltipItem()); badMonths:render()
assert(#badMonths.tooltip.layouts[1].rows == 7)
ticks.badMonth.value = false

-- A nested render restores the exact outer tooltip/item context.
local outerItem, innerItem, sharedTarget = tooltipItem(), tooltipItem(), target()
innerItem.state = risk
local outer, inner = window(outerItem, sharedTarget), window(innerItem, sharedTarget)
outerItem.onNative = function()
    outerItem.onNative = nil
    inner:render()
end
outer:render()
assert(#sharedTarget.layouts == 4)
assert(sharedTarget.layouts[1].rows[1].value == 'UI_PZST_PlantingStatus_risk')
assert(sharedTarget.layouts[3].rows[1].value == 'UI_PZST_PlantingStatus_best')
local innerFailure = tooltipItem(); innerFailure.throw = true
local outerAfterFailure, failureTarget = tooltipItem(), target()
outerAfterFailure.onNative = function()
    outerAfterFailure.onNative = nil
    local failingNested = window(innerFailure, failureTarget)
    assert(not pcall(failingNested.render, failingNested))
end
window(outerAfterFailure, failureTarget):render()
assert(#failureTarget.layouts == 2, 'failed nested rendering must restore the outer context')
local brokenItem, brokenTarget = tooltipItem(), target()
brokenItem.throw = true
local broken = window(brokenItem, brokenTarget)
local ok, message = pcall(broken.render, broken)
assert(not ok and tostring(message):find('native tooltip failure', 1, true))
brokenItem.throw = false
brokenItem:DoTooltip(brokenTarget)
assert(#brokenTarget.layouts == 0, 'failed native rendering must release append context')
local recovered = window(brokenItem, brokenTarget); recovered:render()
assert(#brokenTarget.layouts == 2)
print('Inventory planting tooltip: two passes, character, independent settings, exact scope and exception cleanup passed.')

-- A subclass can inherit a forwarding wrapper installed on its parent class.
-- Appending must still happen once per DoTooltip pass.
local inherited = setmetatable({}, {__index = methods})
local inheritedWindow = window(tooltipItem(inherited))
inheritedWindow:render()
assert(#inheritedWindow.tooltip.layouts == 2, 'inherited DoTooltip wrapper appended planting details more than once per native pass')
local inheritedBroken = tooltipItem(inherited)
inheritedBroken.throw = true
local inheritedBrokenWindow = window(inheritedBroken)
assert(not pcall(inheritedBrokenWindow.render, inheritedBrokenWindow))
inheritedBroken.throw = false
inheritedBrokenWindow:render()
assert(#inheritedBrokenWindow.tooltip.layouts == 2, 'inherited native failure must restore forwarding depth')
print('Inventory planting tooltip: inherited class wrapper passed.')
