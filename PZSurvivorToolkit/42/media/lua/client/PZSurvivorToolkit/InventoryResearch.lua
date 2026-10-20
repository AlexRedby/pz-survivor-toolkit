-- Research eligibility belongs to the native recipe API, including player knowledge and skills.
-- InventoryPresentation owns row layout and decides where to draw the returned marker.
local Research = {}
local CACHE_TTL_MS, MAX_CACHE_ENTRIES = 500, 256
local caches, texture = {}, nil

function Research.texture()
    texture = texture or getTexture("media/ui/Properties/InventoryProperty_Research_16.png")
    return texture
end

function Research.shouldShow(pane, item)
    if not pane or not item then return false end
    local player = getSpecificPlayer(pane.player or 0)
    local script = item:getScriptItem()
    if not player or not script then return false end

    local now = getTimestampMs()
    local recipes = player:getKnownRecipes()
    local knownCount = recipes and recipes:size() or -1
    local index = player:getPlayerNum()
    local cache = caches[index]
    if not cache or cache.player ~= player or cache.knownCount ~= knownCount or now >= cache.expiresAt then
        cache = {player = player, knownCount = knownCount, expiresAt = now + CACHE_TTL_MS,
            entries = {}, count = 0}
        caches[index] = cache
    end
    local cached = cache.entries[script]
    if cached ~= nil then return cached end
    if cache.count >= MAX_CACHE_ENTRIES then
        cache.entries, cache.count, cache.expiresAt = {}, 0, now + CACHE_TTL_MS
    end

    -- true excludes recipes already known by this player; native canResearch also checks skill gates.
    local available = script:getResearchableRecipes(player, true)
    local result = available ~= nil and available:size() > 0
    cache.entries[script], cache.count = result, cache.count + 1
    return result
end

Events.LevelPerk.Add(function(character)
    if not character or not instanceof(character, "IsoPlayer") or not character:isLocalPlayer() then return end
    local index = character:getPlayerNum()
    local cache = caches[index]
    if cache and cache.player == character then caches[index] = nil end
end)

return Research
