require "ISUI/ISToolTipInv"
local Planting = require "PZSurvivorToolkit/InventoryPlanting"
local Options = require "PZSurvivorToolkit/InventoryPlantingOptions"
local Indicators = require "PZSurvivorToolkit/InventoryIndicators"
local Tooltip = {}
local contexts, installed = {}, {}

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

-- Native ISToolTipInv measures and draws through DoTooltip. Install one forwarding
-- wrapper per native item class and scope the extension to this exact tooltip/item.
-- This preserves both native passes and positioning without replacing the renderer.
local function observeItem(item)
    local meta = getmetatable(item)
    local methods = meta and meta.__index
    if not methods or installed[methods] or not methods.DoTooltip then return end
    local native = methods.DoTooltip
    methods.DoTooltip = function(value, target, ...)
        local context = contexts[target]
        if not context or context.item ~= value then return native(value, target, ...) end
        -- A subclass may inherit an already wrapped parent method. Both wrappers
        -- forward the native call, but only the outermost one appends its section.
        context.depth = (context.depth or 0) + 1
        local ok, result = pcall(native, value, target, ...)
        context.depth = context.depth - 1
        if not ok then error(result) end
        if context.depth == 0 then Tooltip.append(target, context.state) end
        return result
    end
    installed[methods] = true
end

function Tooltip.install()
    if Tooltip.installed then return end
    Tooltip.installed = true
    local setCharacter, render = ISToolTipInv.setCharacter, ISToolTipInv.render
    ISToolTipInv.setCharacter = function(self, character)
        self.toolkitPlantingCharacter = character
        return setCharacter(self, character)
    end
    ISToolTipInv.render = function(self, ...)
        local player = (self.tooltip.getCharacter and self.tooltip:getCharacter())
            or self.toolkitPlantingCharacter or self.chr or getPlayer()
        local state = Options.tooltip() and self.item and Planting.describe(player, self.item, Options.preferBest())
        if not state then return render(self, ...) end
        observeItem(self.item)
        local previous = contexts[self.tooltip]
        contexts[self.tooltip] = {item = self.item, state = state}
        local ok, result = pcall(render, self, ...)
        contexts[self.tooltip] = previous
        if not ok then error(result) end
        return result
    end
end
return Tooltip
