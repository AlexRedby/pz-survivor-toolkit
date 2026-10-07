require "ISUI/ISInventoryPaneContextMenu"

local original = ISInventoryPaneContextMenu.doWearClothingTooltip
ISInventoryPaneContextMenu.doWearClothingTooltip = function(player, item, currentItem, option)
    local replaced = original(player, item, currentItem, option)
    local tooltip = option.toolTip
    if tooltip and tooltip.description then
        -- Colour the displayed delta: native integer formatting can turn small changes into zero.
        tooltip.description = tooltip.description:gsub(
            "<RGB:[^>]+>([^<]*<SETX:%d+> %-?%d+ %([+-]?0%)%s*<LINE>)",
            "<RGB:0.8,0.8,0.8>%1")
    end
    return replaced
end
