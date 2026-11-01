-- Test fixture only. Source hashes are gated by the loot-demand adapter.
require "FurniturePushPull/FurniturePushPull_Core"

LootDemandFurniture = LootDemandFurniture or {}
if LootDemandFurniture.installed then return end

local furniture = FurniturePushPull
if type(furniture) ~= "table"
    or type(furniture.executeMove) ~= "function"
    or type(furniture.executeServerMove) ~= "function"
    or type(furniture.getMoveableData) ~= "function"
    or type(furniture.getFurnitureMembers) ~= "function"
    or type(lootDemandEnsure) ~= "function"
then
    error("Loot demand furniture integration requires the guarded core and ensure bridge")
end

local function wrap(original)
    return function(character, object, destination, ...)
        -- The networked action captures/rebuilds on the server. Client UI and
        -- validation must not materialize a second copy of shared contents.
        if not isClient() and character and object and destination then
            local props = furniture.getMoveableData(object)
            local members = props and furniture.getFurnitureMembers(object, props)
            if members then
                for _, member in ipairs(members) do
                    local source = member.object
                    if source then
                        for index = 0, source:getContainerCount() - 1 do
                            local container = source:getContainerByIndex(index)
                            if container and lootDemandEnsure(container, character) ~= true then
                                return false
                            end
                        end
                    end
                end
            end
        end
        -- Keep native arguments, multiple returns and exceptions. This call is
        -- deliberately after every ensure: captureFurnitureContainers is local
        -- to Core and must snapshot the newly materialized original items.
        return original(character, object, destination, ...)
    end
end

local move, serverMove = furniture.executeMove, furniture.executeServerMove
furniture.executeMove = wrap(move)
furniture.executeServerMove = wrap(serverMove)
LootDemandFurniture.installed = true
