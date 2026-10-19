require "ISUI/ISInventoryPaneContextMenu"

local pending = {}
local open = ISInventoryPaneContextMenu.onInspectClothingUI

local function resolve(player, id, fullType)
    local item = player:getInventory():getItemById(id)
    if item and item:getID() == id and item:getFullType() == fullType then return item end
end

function ISInventoryPaneContextMenu.onInspectClothingUI(player, clothing)
    local playerNum = player:getPlayerNum()
    pending[playerNum] = nil
    if player:isDead() then return end
    if clothing:isInPlayerInventory() then return open(player, clothing) end

    -- Host transfers deserialize a new item; the native callback keeps the storage instance.
    local id, fullType = clothing:getID(), clothing:getFullType()
    local item = resolve(player, id, fullType)
    if item then return open(player, item) end
    if isClient() then
        -- Cart callbacks can precede delivery. Keep only the latest request for each player.
        pending[playerNum] = {player = player, id = id, fullType = fullType,
            deadline = getTimestampMs() + 30000}
    end
end

Events.OnTick.Add(function()
    for playerNum, request in pairs(pending) do
        local player = request.player
        if getSpecificPlayer(playerNum) ~= player or player:isDead() or getTimestampMs() >= request.deadline then
            pending[playerNum] = nil
        else
            local item = resolve(player, request.id, request.fullType)
            if item then
                pending[playerNum] = nil
                open(player, item)
            end
        end
    end
end)

Events.OnMainMenuEnter.Add(function() pending = {} end)
