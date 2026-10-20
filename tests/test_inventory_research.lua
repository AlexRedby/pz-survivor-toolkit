-- Keep native eligibility authoritative and its short display cache isolated by player and script item.
local now, players, levelPerk, textureCalls = 1000, {}, nil, 0
getTimestampMs = function() return now end
getSpecificPlayer = function(index) return players[index] end
instanceof = function(value, class) return class == 'IsoPlayer' and value.player end
Events = {LevelPerk = {Add = function(callback) assert(not levelPerk); levelPerk = callback end}}
local loadedTexture
getTexture = function(path)
    assert(path == 'media/ui/Properties/InventoryProperty_Research_16.png')
    textureCalls = textureCalls + 1
    return loadedTexture
end
local function player(index)
    local value = {player = true, localPlayer = true, index = index, known = 0, eligible = false}
    value.getPlayerNum = function(self) return self.index end
    value.isLocalPlayer = function(self) return self.localPlayer end
    value.getKnownRecipes = function(self)
        if self.noKnownList then return nil end
        return {size = function() return self.known end}
    end
    return value
end
local calls = 0
local function scriptItem()
    return {getResearchableRecipes = function(_, character, unknownOnly)
        assert(unknownOnly == true, 'native API must exclude known recipes')
        calls = calls + 1
        if character.nilRecipes then return nil end
        return {size = function() return character.eligible and 1 or 0 end}
    end}
end
local function item(script) return {getScriptItem = function() return script end} end
local a, b = player(0), player(1)
players[0], players[1] = a, b
local paneA, paneB = {player = 0}, {player = 1}
local script = scriptItem()
local first, duplicate = item(script), item(script)
local Research = dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/InventoryResearch.lua')
assert(not Research.shouldShow(nil, first) and not Research.shouldShow(paneA, nil))
assert(not Research.shouldShow({player = 3}, first) and not Research.shouldShow(paneA, item(nil)))
assert(calls == 0)

-- Native denial (known recipe or unmet skills) is cached as false, including duplicate physical items.
assert(not Research.shouldShow(paneA, first))
assert(not Research.shouldShow(paneA, duplicate) and calls == 1)
b.eligible = true
assert(Research.shouldShow(paneB, first) and calls == 2, 'split-screen player knowledge leaked')
assert(not Research.shouldShow(paneA, first) and calls == 2)

-- Learning a recipe updates without waiting for the TTL; another player's cached value survives.
b.eligible, b.known = false, 1
assert(not Research.shouldShow(paneB, first) and calls == 3)
assert(not Research.shouldShow(paneA, first) and calls == 3)
a.eligible = true
levelPerk(a)
assert(Research.shouldShow(paneA, duplicate) and calls == 4, 'local skill change remained cached')
assert(not Research.shouldShow(paneB, duplicate) and calls == 4)

-- Remote players, unrelated characters and an old player object cannot invalidate a local cache.
a.localPlayer = false
levelPerk(a)
a.localPlayer = true
levelPerk(nil)
levelPerk({player = false})
levelPerk(player(0))
assert(Research.shouldShow(paneA, first) and calls == 4)

-- Same-size recipe edits and changes without events become visible at the original 500 ms bound.
a.eligible = false
now = 1499
assert(Research.shouldShow(paneA, first) and calls == 4)
now = 1500
assert(not Research.shouldShow(paneA, first) and calls == 5)
local replacement = player(0)
replacement.eligible = true
players[0] = replacement
assert(Research.shouldShow({}, first) and calls == 6, 'replacement player inherited old cache')
replacement.noKnownList, replacement.nilRecipes = true, true
assert(not Research.shouldShow(paneA, first) and calls == 7)
assert(not Research.shouldShow(paneA, first) and calls == 7)

-- Bound the retained script-item set even in a huge inventory within the same cache window.
replacement.nilRecipes = false
local before = calls
for index = 1, 256 do assert(Research.shouldShow(paneA, item(scriptItem()))) end
assert(calls == before + 256)
assert(Research.shouldShow(paneA, first) and calls == before + 257, 'bounded cache retained its oldest item')

-- A temporarily missing native texture is retried, then reused; no external asset is required.
assert(Research.texture() == nil and textureCalls == 1)
loadedTexture = {}
assert(Research.texture() == loadedTexture and textureCalls == 2)
assert(Research.texture() == loadedTexture and textureCalls == 2)
print('inventory research: native eligibility, split-screen isolation, learning/perk invalidation and bounded cache passed')
