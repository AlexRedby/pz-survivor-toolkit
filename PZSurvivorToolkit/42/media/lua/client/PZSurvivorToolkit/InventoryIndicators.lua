local Research = require "PZSurvivorToolkit/InventoryResearch"
local Planting = require "PZSurvivorToolkit/InventoryPlanting"
local Options = require "PZSurvivorToolkit/InventoryPlantingOptions"
local Pins = getActivatedMods():contains("EURY_CONTAINERS") and require "BetterContainers/Upgrades/PinnedItems"
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
function Indicators.drawIcon(pane, item, x, y, width, height, details, group, researchContext)
    -- Like the original indicators, decorate details rows, not drag previews or the icon grid.
    if not details then return end
    local size = math.min(12, width / 2, height / 2)
    local visibleY = y + pane:getYScroll()
    if size < 4 or visibleY < pane.headerHgt or visibleY + size > pane.height then return end
    local research = Research.shouldShow(pane, item, researchContext)
    local state = Options.enabled() and Planting.describe(getSpecificPlayer(pane.player or 0), item, Options.preferBest())
    -- Native rendering already excludes hidden and dragged rows. Only the group
    -- icon gets a type-pin marker; physical children keep their normal badges.
    local pinned = group and Pins and PZSurvivorToolkit.BCPinCompatibility
        and Pins.displayPinnedItem(pane.inventoryPage) and Pins.isFavourite(item:getFullType())
    local pinTexture = pinned and getTexture("media/ui/BetterContainers/PinnedItemMarker.png")
    local secondRow = pinTexture and research and state and (width - 2) / 3 < 8
    if secondRow then size = math.min(size, (height - 1) / 2)
    elseif pinTexture and research and state then size = math.min(size, (width - 2) / 3) end
    if research then
        badge(pane, Research.texture(), x, y, size, {1, 1, 1})
    end
    if state then
        local texture = state.status == "best" and "media/ui/MP/mp_ui_star.png" or "media/ui/circle.png"
        badge(pane, getTexture(texture), x + width - size, y, size, Indicators.colors[state.status])
    end
    if pinTexture then
        local pinSize = math.min(11, size)
        local pinY = secondRow and y + height - pinSize or y
        if pinSize >= 8 and pinY + pane:getYScroll() + pinSize <= pane.height then
            local pinX = x
            if research then pinX = state and x + (width - pinSize) / 2 or x + width - pinSize end
            badge(pane, pinTexture, pinX, pinY, pinSize, {1, 1, 1})
        end
    end
end
return Indicators
