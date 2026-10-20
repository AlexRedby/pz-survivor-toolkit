-- Run the selected upstream implementation, without redistributing its source.
local compatibility = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/000ToolkitSeedSeasonCompatibility.lua'
local active = false
getActivatedMods = function() return {contains = function(_, id) return active and id == 'SeedSeasonIndicator' end} end
require = function() error('inactive Seed Season Indicator must not be required') end
dofile(compatibility)
active = true
local stub = {computeCategoryKey = function() return 'seasonal category' end, getIconForItem = function() end}
local iconFunction = stub.getIconForItem
require = function(name) assert(name == 'SeedSeasonIndicator'); return stub end
dofile(compatibility)
dofile(compatibility)
assert(stub.computeCategoryKey() == nil and stub.getIconForItem == iconFunction,
    'reloading compatibility must keep category suppression and unrelated upstream functions')
if not SeedSeasonSource then
    print('Seed Season compatibility: absent mod and repeated loading passed; actual upstream checks skipped (pass --seed-season-source).')
    return
end

local month, seasons, known = 4, true, true
local options, starts = {}, {}
PZAPI = {ModOptions = {create = function(_, id)
    assert(id == 'SeedSeasonIndicator')
    return {addTickBox = function(_, key, _, default)
        options[key] = {value = default, getValue = function(self) return self.value end}
        return options[key]
    end}
end}}
getText = function(key) return key end
getTexture = function(path) return {path = path, getWidth = function() return 32 end, getHeight = function() return 32 end} end
Events = {OnGameStart = {Add = function(callback) starts[#starts + 1] = callback end}}
getGameTime = function() return {getMonth = function() return month - 1 end} end
getSandboxOptions = function() return {getOptionByName = function(_, name)
    assert(name == 'PlantGrowingSeasons'); return {getValue = function() return seasons end}
end} end
local player = {isRecipeActuallyKnown = function(_, recipe) assert(recipe == 'Sow Test'); return known end}
getSpecificPlayer = function() return player end
getPlayer = function() return player end
getTextManager = function() return {MeasureStringX = function(_, _, text) return #text * 6 end} end
calcNextTimeFactor = function() return 1 end
instanceof = function(value, class) return value and value.inventoryItem and class == 'InventoryItem' end
farming_vegetableconf = {props = {Test = {seedName = 'Base.TestSeed', seasonRecipe = 'Sow Test',
    sowMonth = {4, 5, 6}, bestMonth = {4}, riskMonth = {6}, badMonth = {12, 1, 2},
    waterLvl = 35, timeToGrow = 24, harvestLevel = 7, texture = 'plant.png'}}}
local Item = {DoTooltip = function(_, tooltip) tooltip.baseCalls = tooltip.baseCalls + 1 end}
local function item(category, fullType)
    return setmetatable({inventoryItem = true, category = category, fullType = fullType or 'Base.TestSeed',
        getFullType = function(self) return self.fullType end,
        getType = function() return {contains = function() return false end} end,
        getDisplayCategory = function(self) return self.category end, getCategory = function() return 'Food' end}, {__index = Item})
end
local seed = item('Gardening')
ISInventoryPane = {}
function ISInventoryPane:renderdetails()
    self.items = self.itemslist
    for index, group in ipairs(self.itemslist) do
        local category = getText('IGUI_ItemCat_' .. group.items[1]:getDisplayCategory())
        local y = self.headerHgt + (index - 1) * self.itemHgt
        self:drawText(category, self.column3 + 8, y)
        self:drawTextRight(category, self.column3 + 80, y)
    end
end
local function compare(a, b, descending)
    if a.cat == b.cat then return a.name < b.name end
    if descending then return a.cat > b.cat end
    return a.cat < b.cat
end
ISInventoryPane.itemSortByCatInc = function(a, b) return compare(a, b, false) end
ISInventoryPane.itemSortByCatDesc = function(a, b) return compare(a, b, true) end
ISToolTipInv = {render = function(self) self.item:DoTooltip(self.tooltip) end}
local upstream = assert(loadstring(SeedSeasonSource, '@SeedSeasonIndicator.lua'))()
assert(upstream == SeedSeasonIndicatorShared and #starts == 1, 'upstream public export contract changed')
starts[1]()
local function pane(value)
    local p = setmetatable({player = 0, headerHgt = 20, itemHgt = 24, column2 = 80, column3 = 160,
        selected = {}, texts = {}, icons = {}, itemslist = {{items = {value}, count = 1, name = 'seed'}}}, {__index = ISInventoryPane})
    p.drawText = function(self, text) self.texts[#self.texts + 1] = text end
    p.drawTextRight = p.drawText
    p.drawTexture = function(self, texture) self.icons[#self.icons + 1] = texture end
    p.getMouseX, p.getMouseY, p.getYScroll = function() return 0 end, function() return 0 end, function() return 0 end
    p.getHeight = function() return 500 end
    return p
end
local function entry(value, category, name)
    return {items = {value}, cat = category, name = name or 'seed', invPanel = {player = 0}}
end
-- Establish that the source used by this check reproduces both reported effects.
local control = pane(seed)
control:renderdetails(false)
assert(control.texts[1] == 'IGUI_ItemCat_Gardening_01_Best' and control.texts[2] == control.texts[1],
    'upstream control no longer substitutes the seasonal category label')
local controlEntry = entry(seed, 'Gardening')
ISInventoryPane.itemSortByCatInc(controlEntry, entry(item('Tools', 'Base.Hammer'), 'Tools'))
assert(controlEntry.cat == 'Gardening_01_Best', 'upstream control no longer rewrites category sort keys')
local render, sortInc, sortDesc, tooltipRender = ISInventoryPane.renderdetails, ISInventoryPane.itemSortByCatInc,
    ISInventoryPane.itemSortByCatDesc, ISToolTipInv.render
require = function(name) assert(name == 'SeedSeasonIndicator'); return upstream end
dofile(compatibility)
dofile(compatibility)
assert(ISInventoryPane.renderdetails == render and ISInventoryPane.itemSortByCatInc == sortInc
    and ISInventoryPane.itemSortByCatDesc == sortDesc and ISToolTipInv.render == tooltipRender and #starts == 1,
    'compatibility must not replace or stack upstream UI/event wrappers')

local function tooltip(value)
    local t = {rows = {}, height = 20, width = 20, baseCalls = 0, plantIcons = 0}
    t.getFont = function() return 'Small' end
    t.getHeight, t.getWidth = function(self) return self.height end, function(self) return self.width end
    t.setHeight, t.setWidth = function(self, v) self.height = v end, function(self, v) self.width = v end
    t.DrawTextureScaled = function(self) self.plantIcons = self.plantIcons + 1 end
    t.beginLayout = function(self)
        return {addItem = function()
            local row = {}; self.rows[#self.rows + 1] = row
            row.setLabel = function(_, label) row.label = label end
            row.setValue = function(_, text) row.value = text end
            return row
        end, setMinLabelWidth = function() end, render = function(_, _, y) return y + #self.rows * 14 end}
    end
    t.endLayout = function() end
    local before = Item.DoTooltip
    ISToolTipInv.render({item = value, chr = player, tooltip = t})
    assert(Item.DoTooltip == before and t.baseCalls == 1, 'tooltip must retain and restore original item callback')
    return t
end
local statuses = {{4, 'best', 'Best'}, {5, 'inseason', 'InSeason'}, {6, 'risk', 'Risk'}, {10, 'outofseason', 'OutOfSeason'}}
local cases = 0
for _, category in ipairs({'Gardening', 'FarmSeed', 'foodCookingPerishable'}) do
    seed.category = category
    for _, status in ipairs(statuses) do
        month = status[1]
        for _, isKnown in ipairs({true, false}) do
            known = isKnown
            for _, hasSeasons in ipairs({true, false}) do
                seasons = hasSeasons
                for _, enabled in ipairs({true, false}) do
                    options.enabled.value = enabled
                    local p = pane(seed); p:renderdetails(false)
                    local expectedLabel = 'IGUI_ItemCat_' .. category
                    assert(#p.texts == 2 and p.texts[1] == expectedLabel and p.texts[2] == expectedLabel,
                        'season text leaked into an inventory category')
                    local expectedIcon = enabled and known and seasons and upstream['tex' .. status[3]] or nil
                    assert(#p.icons == (expectedIcon and 1 or 0) and p.icons[1] == expectedIcon,
                        'upstream season icon behavior changed')
                    for _, sorter in ipairs({sortInc, sortDesc}) do
                        local a, b = entry(seed, category, 'A'), entry(seed, category, 'B')
                        assert(sorter(a, b) and not sorter(b, a), 'equal-category item order changed')
                        assert(a.cat == category and b.cat == category, 'season sort key leaked into category')
                        local z = entry(item('zzCategory', 'Base.Hammer'), 'zzCategory')
                        assert(sorter(a, z) == (sorter == sortInc) and a.cat == category and z.cat == 'zzCategory',
                            'base category ordering changed')
                    end
                    for _, showTooltip in ipairs({true, false}) do
                        options.tooltip.value = showTooltip
                        local t = tooltip(seed)
                        local detailed = showTooltip and known and seasons
                        assert(#t.rows == (detailed and 6 or 0) and t.plantIcons == (detailed and 1 or 0),
                            'upstream detailed tooltip behavior changed')
                        if detailed then
                            assert(t.rows[1].value == 'IGUI_SSI_TooltipStatus_' .. status[3])
                            assert(t.rows[2].value == '35' and t.rows[3].value == '7 IGUI_Gametime_days')
                            assert(t.rows[4].value == 'Farming_Month_4, Farming_Month_5, Farming_Month_6')
                        end
                    end
                    cases = cases + 1
                end
            end
        end
    end
end
known, seasons, month = true, true, 5
options.enabled.value, options.tooltip.value, options.badMonth.value = true, true, true
local t = tooltip(seed)
assert(#t.rows == 7 and t.rows[7].value == 'Farming_Month_12, Farming_Month_1, Farming_Month_2',
    'optional bad-month tooltip detail changed')
farming_vegetableconf.props.Test.bestMonth = nil
options.noBestStar.value = true
local p = pane(seed); p:renderdetails(false)
assert(p.icons[1] == upstream.texBest and tooltip(seed).rows[1].value == 'IGUI_SSI_TooltipStatus_Best',
    'no-best-month option must retain upstream status icon and tooltip')
local unknown = item('Gardening', 'Base.UnrelatedSeed')
p = pane(unknown); p:renderdetails(false)
assert(p.texts[1] == 'IGUI_ItemCat_Gardening' and #p.icons == 0 and #tooltip(unknown).rows == 0,
    'unmapped gardening items must retain their category without fabricated season data')
assert(upstream.computeCategoryKey(player, seed) == nil and upstream.computeCategoryKey(player, unknown) == nil)
print('Seed Season compatibility: actual upstream control, ' .. cases .. ' category/status/options cases, original sorting, icons and detailed tooltips passed.')
