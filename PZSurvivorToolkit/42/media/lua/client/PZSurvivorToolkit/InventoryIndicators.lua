local Research = require "PZSurvivorToolkit/InventoryResearch"
local Planting = require "PZSurvivorToolkit/InventoryPlanting"
local Options = require "PZSurvivorToolkit/InventoryPlantingOptions"
local Indicators = {}
Indicators.colors = {
    best = {0.25, 0.95, 0.40},
    inseason = {0.60, 1.00, 0.60},
    risk = {1.00, 0.85, 0.20},
    outofseason = {1.00, 0.30, 0.20},
}
local function badge(pane, texture, x, y, size, color)
    if not texture then return end
    pane:drawTextureScaled(texture, x, y, size, size, 1, color[1], color[2], color[3])
end
function Indicators.drawIcon(pane, item, x, y, width, height, details)
    -- Like the original indicators, decorate details rows, not drag previews or the icon grid.
    if not details then return end
    local size = math.min(12, width / 2, height / 2)
    local visibleY = y + pane:getYScroll()
    if size < 4 or visibleY < pane.headerHgt or visibleY + size > pane.height then return end
    if Research.shouldShow(pane, item) then
        badge(pane, Research.texture(), x, y, size, {1, 1, 1})
    end
    if not Options.enabled() then return end
    local state = Planting.describe(getSpecificPlayer(pane.player or 0), item, Options.preferBest())
    if state then
        local texture = state.status == "best" and "media/ui/MP/mp_ui_star.png" or "media/ui/circle.png"
        badge(pane, getTexture(texture), x + width - size, y, size, Indicators.colors[state.status])
    end
end
return Indicators
