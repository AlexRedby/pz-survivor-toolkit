require "PZSurvivorWishlist/Client"
require "PZSurvivorWishlist/Settings"
require "Vehicles/ISUI/ISVehicleMechanics"

local W = PZSurvivorWishlist
local Vehicles = {}
W.Vehicles = Vehicles

function Vehicles.entry(part)
    local types = part and part:getItemType()
    if not types or types:size() == 0 or types:size() > 32 then return nil end
    local variants, seen = {}, {}
    for i = 0, types:size() - 1 do
        local fullType = types:get(i)
        local script = ScriptManager.instance:FindItem(fullType)
        if not script or script:getFullName() ~= fullType then return nil end
        if not seen[fullType] then
            variants[#variants + 1], seen[fullType] = fullType, true
        end
    end
    -- Runtime slot types already include the vehicle class, even when its item is missing.
    return {fullType = variants[1], amount = 1, vehicleTypes = variants,
        vehicleClass = part:getVehicle():getScript():getMechanicType()}
end

function Vehicles.isWanted(playerNum, part)
    local item = part and part:getInventoryItem()
    return item ~= nil and W.Client.isWanted(playerNum, item:getFullType())
end

local installed = false
function Vehicles.install()
    if installed then return end
    installed = true
    local contextMenu = ISVehicleMechanics.doPartContextMenu
    function ISVehicleMechanics:doPartContextMenu(part, ...)
        local result = contextMenu(self, part, ...)
        if not self.context or UIManager.getSpeedControls():getCurrentGameSpeed() == 0 then return result end
        local player = getSpecificPlayer(self.playerNum)
        if player:getVehicle() ~= nil and not (isDebugEnabled() or
            (isClient() and (isAdmin() or getAccessLevel() == "moderator"))) then return result end
        local entry = Vehicles.entry(part)
        if entry then
            local list = W.Client.selected(self.playerNum)
            local listId, key = list and list.id, "vehicle:" .. entry.fullType
            local removing = list and list.entries[key] ~= nil
            self.context:addOption(getText(removing and "UI_PZSW_RemoveVehicleWanted" or "UI_PZSW_AddVehicleWanted"),
                self.playerNum, function(playerNum)
                    if not listId then W.Client.open(playerNum); return end
                    W.Client.edit(playerNum, removing and "remove" or "addMany",
                        removing and {listId = listId, fullType = key} or {listId = listId, entries = {entry}})
                end)
            self.context:setVisible(true)
        end
        return result
    end
    local drawItem = ISVehicleMechanics.doDrawItem
    function ISVehicleMechanics:doDrawItem(y, row, ...)
        if W.Settings.rowsEnabled() and not row.item.cat and Vehicles.isWanted(self.parent.playerNum, row.item.part) then
            local colour = W.Settings.color()
            self:drawRect(0, y, self:getWidth(), row.height, 0.12, colour.r, colour.g, colour.b)
            self:drawRectBorder(0, y, self:getWidth(), row.height, 0.7, colour.r, colour.g, colour.b)
        end
        return drawItem(self, y, row, ...)
    end
end
Events.OnGameStart.Add(Vehicles.install)
return Vehicles
