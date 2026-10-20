local Boundary = require "PZSurvivorToolkit/InventoryTooltip"
local MediaTooltip = {}

function MediaTooltip.append(target, data)
    local font, manager = target:getFont(), getTextManager()
    local bottom = target.padBottom or 5
    local y, width = target:getHeight() - bottom, target:getWidth()
    local function lines(values, left, color, prefix)
        local layout = target:beginLayout()
        for _, value in ipairs(values) do
            local text = (prefix or "") .. value
            layout:addItem():setLabel(text, color[1], color[2], color[3], 1)
            width = math.max(width, left + manager:MeasureStringX(font, text) + 12)
        end
        y = layout:render(left, y, target)
        target:endLayout(layout)
    end
    local function section(title, values)
        if #values == 0 then return end
        lines({title .. ": "}, 8, {1, 1, 0})
        lines(values, 12, {1, 1, 1}, "- ")
    end
    section(getText("IGUI_XP_Skills"), data.skillTexts)
    section(getText("Tooltip_Literature_LearnedRecipes", ""):gsub("%s*:%s*$", ""), data.recipeTexts)
    target:setHeight(y + bottom)
    target:setWidth(width)
end

function MediaTooltip.install()
    if MediaTooltip.installed or not getActivatedMods():contains("VHSSkillNameInTooltip") then return end
    -- The upstream callback still builds its data, then observes this guard.
    -- Set it before OnGameStart; do not stack an extension over an active renderer.
    if ISToolTipInv._vhsHooked then
        print("[PZSurvivorToolkit] VHS tooltip compatibility must load before OnGameStart")
        return
    end
    local logic = require "SVSIT_logic"
    ISToolTipInv._vhsHooked = true
    MediaTooltip.installed = true
    Boundary.register("vhs", function(_, item)
        if not item.getFullType or not string.find(item:getFullType(), "VHS") then return nil end
        local id = logic.getMediaIdFromItemName(item)
        local data = logic.RecMedia and logic.RecMedia[id]
        if data and (#data.skillTexts > 0 or #data.recipeTexts > 0) then return data end
    end, function(target, data) MediaTooltip.append(target, data) end)
    Boundary.install()
end

return MediaTooltip
