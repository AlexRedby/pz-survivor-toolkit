require "ISUI/ISGarmentUI"
require "ISUI/ISInventoryPaneContextMenu"

local doContextMenu = ISGarmentUI.doContextMenu
function ISGarmentUI:doContextMenu(part, x, y)
    if self.clothing:getFabricType() or self.clothing:getPatchType(part) then
        return doContextMenu(self, part, x, y)
    end

    -- Native checks supplies before discovering that this garment cannot be repaired.
    local context = ISContextMenu.get(self.chr:getPlayerNum(), x, y)
    local text = getText("IGUI_garment_CantRepair")
    local option = context:addOption(text)
    option.notAvailable = true
    option.toolTip = ISInventoryPaneContextMenu.addToolTip()
    option.toolTip.description = text
    return context
end
