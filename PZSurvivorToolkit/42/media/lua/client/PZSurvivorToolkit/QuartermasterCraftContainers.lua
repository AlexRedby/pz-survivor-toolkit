-- Availability belongs to the crafting refresh that requested it, not to a rendered window.
local Containers = {}
local character, suppressed = nil, 0
local function pack(...) return {n = select("#", ...), ...} end

function Containers.withContext(player, fn, ...)
    local previous = character
    character = player
    local result = pack(pcall(fn, ...))
    character = previous
    if not result[1] then error(result[2]) end
    return unpack(result, 2, result.n)
end

local function withoutContext(fn, ...)
    suppressed = suppressed + 1
    local result = pack(pcall(fn, ...))
    suppressed = suppressed - 1
    if not result[1] then error(result[2]) end
    return unpack(result, 2, result.n)
end
Containers.withoutContext = withoutContext

-- With no player, report any active context so forwarding proofs fail closed.
function Containers.active(player)
    return suppressed == 0 and character ~= nil and (player == nil or player == character)
end

-- Keep the live getter chain (including other mods), but never add our distant boxes.
function Containers.inventory(player)
    return withoutContext(ISInventoryPaneContextMenu.getContainers, player)
end

return Containers
