local Boundary = require "PZSurvivorToolkit/InventoryTooltip"
local Planting = require "PZSurvivorToolkit/InventoryPlanting"
local Options = require "PZSurvivorToolkit/InventoryPlantingOptions"
local Indicators = require "PZSurvivorToolkit/InventoryIndicators"
local Tooltip = {}

local function months(values)
    if not values or #values == 0 then return getText("Farming_Tooltip_None") end
    local labels = {}
    for _, month in ipairs(values) do labels[#labels + 1] = getText("Farming_Month_" .. month) end
    return table.concat(labels, ", ")
end

function Tooltip.append(target, state)
    local layout, labelWidth, valueWidth = target:beginLayout(), 0, 0
    local manager, font = getTextManager(), target:getFont()
    local function row(label, value, color)
        value = tostring(value)
        local entry = layout:addItem()
        color = color or {1, 1, 1}
        entry:setLabel(label, 1, 1, 1, 1)
        entry:setValue(value, color[1], color[2], color[3], 1)
        labelWidth = math.max(labelWidth, manager:MeasureStringX(font, label))
        valueWidth = math.max(valueWidth, manager:MeasureStringX(font, value))
    end
    row(getText("Farming_Month_" .. state.currentMonth) .. ":",
        getText("UI_PZST_PlantingStatus_" .. state.status), Indicators.colors[state.status])
    row(getText("Farming_Tooltip_MinWater"), state.waterLvl)
    row(getText("Farming_Tooltip_TimeOfGrow"), state.growDays .. " " .. getText("IGUI_Gametime_days"))
    row(getText("Farming_Tooltip_InSeason") .. ":", months(state.sowMonth), Indicators.colors.inseason)
    row(getText("Farming_Tooltip_BestMonth2") .. ":", months(state.bestMonth), Indicators.colors.best)
    row(getText("Farming_Tooltip_RiskMonth2") .. ":", months(state.riskMonth), Indicators.colors.risk)
    if Options.badMonths() then
        row(getText("UI_PZST_PlantingBadMonthsLabel"), months(state.badMonth), Indicators.colors.outofseason)
    end
    local left, right, gap, bottom = 14, 12, 20, target.padBottom or 5
    local top = target:getHeight() - bottom
    layout:setMinLabelWidth(labelWidth + gap)
    local finish = layout:render(left, top, target)
    target:endLayout(layout)
    target:setHeight(finish + bottom)
    local texture = state.texture and getTexture(state.texture)
    local height, width = finish - top, 0
    if texture and texture:getHeight() > 0 then width = height * texture:getWidth() / texture:getHeight() end
    target:setWidth(math.max(target:getWidth(), left + labelWidth + gap + valueWidth + right
        + (width > 0 and gap + math.ceil(width) or 0)))
    if width > 0 then target:DrawTextureScaled(texture, target:getWidth() - right - width, top, width, height, 1) end
end

function Tooltip.install()
    if Tooltip.installed then return end
    Tooltip.installed = true
    Boundary.register("planting", function(player, item)
        return Options.tooltip() and Planting.describe(player, item, Options.preferBest())
    end, function(target, state) Tooltip.append(target, state) end)
    Boundary.install()
end
return Tooltip
