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
    value.indexReads, value.knownReads = 0, 0
    value.getPlayerNum = function(self)
        self.indexReads = self.indexReads + 1
        return self.index
    end
    value.isLocalPlayer = function(self) return self.localPlayer end
    -- Native getKnownRecipes returns one final List; its contents remain mutable.
    local recipes = {size = function() return value.known end}
    value.getKnownRecipes = function(self)
        self.knownReads = self.knownReads + 1
        if self.noKnownList then return nil end
        return recipes
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

-- A render context only amortizes stable list/index getters. Clock, list size
-- and cache identity remain live for every physical icon sharing a script item.
local contextPlayer = player(0)
contextPlayer.eligible = true
players[0] = contextPlayer
local context, contextScript = {}, scriptItem()
local beforeContext = calls
for index = 1, 8 do
    assert(Research.shouldShow(paneA, item(contextScript), context))
end
assert(calls == beforeContext + 1, 'physical duplicates missed the existing script cache')
assert(contextPlayer.indexReads == 1 and contextPlayer.knownReads == 1,
    'one render repeated the stable player index/list getters')

-- Learning must hide the badge immediately, including within one render.
contextPlayer.eligible, contextPlayer.known = false, 1
assert(not Research.shouldShow(paneA, item(contextScript), context) and calls == beforeContext + 2)
assert(contextPlayer.indexReads == 1 and contextPlayer.knownReads == 1,
    'learning replaced the stable native list rather than observing its live size')

-- Same-size changes keep the original TTL, even if it expires during a render.
contextPlayer.eligible = true
now = now + 499
assert(not Research.shouldShow(paneA, item(contextScript), context) and calls == beforeContext + 2)
now = now + 1
assert(Research.shouldShow(paneA, item(contextScript), context) and calls == beforeContext + 3)
contextPlayer.eligible = false
levelPerk(contextPlayer)
assert(not Research.shouldShow(paneA, item(contextScript), context) and calls == beforeContext + 4,
    'render context retained a cache invalidated by LevelPerk')

-- Nested render contexts cannot hide mutations from an outer context or retain
-- the cache record another callback has invalidated/replaced.
local nested = {}
assert(not Research.shouldShow(paneA, item(contextScript), nested))
local outerIndex, outerList = context.index, context.recipes
contextPlayer.eligible, contextPlayer.known = true, 2
assert(Research.shouldShow(paneA, item(contextScript), nested) and calls == beforeContext + 5)
contextPlayer.eligible = false
levelPerk(contextPlayer)
assert(not Research.shouldShow(paneA, item(contextScript), context) and calls == beforeContext + 6)
assert(context.index == outerIndex and context.recipes == outerList,
    'nested context overwrote the outer list/index snapshot')
contextPlayer.eligible, contextPlayer.known = true, 3
assert(Research.shouldShow(paneA, item(contextScript), context) and calls == beforeContext + 7)
assert(Research.shouldShow(paneA, item(contextScript), nested) and calls == beforeContext + 7)

-- A context follows replacement of the native player at the same local slot.
local nextPlayer = player(0)
players[0] = nextPlayer
assert(not Research.shouldShow(paneA, item(contextScript), context) and calls == beforeContext + 8)
assert(nextPlayer.indexReads == 1 and nextPlayer.knownReads == 1 and context.player == nextPlayer)
nextPlayer.eligible, nextPlayer.known = true, 1
assert(Research.shouldShow(paneA, item(contextScript), context) and calls == beforeContext + 9)
assert(nextPlayer.indexReads == 1 and nextPlayer.knownReads == 1)
players[0] = contextPlayer
assert(Research.shouldShow(paneA, item(contextScript), context) and calls == beforeContext + 10)
assert(context.player == contextPlayer)

-- Missing players/scripts do not prepare a context or poison later valid calls.
local untouched = {}
assert(not Research.shouldShow(nil, first, untouched))
assert(not Research.shouldShow(paneA, nil, untouched))
assert(not Research.shouldShow({player = 3}, first, untouched))
assert(not Research.shouldShow(paneA, item(nil), untouched))
assert(next(untouched) == nil)
assert(Research.shouldShow(paneA, item(contextScript), untouched))

-- A missing native list is not retained, allowing a temporarily unavailable
-- custom/native-like getter to recover without waiting for another render.
local recovered = player(1)
recovered.noKnownList = true
players[1] = recovered
local recovering = {}
assert(not Research.shouldShow(paneB, item(contextScript), recovering))
recovered.noKnownList, recovered.eligible = false, true
assert(Research.shouldShow(paneB, item(contextScript), recovering))

-- Contexts preserve the same bounded script cache as direct callers.
local capacityContext, capacityPlayer = {}, player(0)
capacityPlayer.eligible = true
players[0] = capacityPlayer
local firstScript = scriptItem()
assert(Research.shouldShow(paneA, item(firstScript), capacityContext))
local beforeCapacity = calls
for index = 1, 256 do
    assert(Research.shouldShow(paneA, item(scriptItem()), capacityContext))
end
assert(calls == beforeCapacity + 256)
assert(Research.shouldShow(paneA, item(firstScript), capacityContext) and calls == beforeCapacity + 257,
    'render context bypassed bounded-cache eviction')
assert(capacityPlayer.indexReads == 1 and capacityPlayer.knownReads == 1)

-- Passing no context retains per-call reads for existing API callers.
local directPlayer, directScript = player(2), scriptItem()
directPlayer.eligible = true
players[2] = directPlayer
assert(Research.shouldShow({player = 2}, item(directScript)))
assert(Research.shouldShow({player = 2}, item(directScript)))
assert(directPlayer.indexReads == 2 and directPlayer.knownReads == 2,
    'direct callers unexpectedly retained render context')

local function outcomes(index, renderContext)
    local character, definition = player(index), scriptItem()
    local pane, result = {player = index}, {}
    players[index], now = character, 10000
    local function check() result[#result + 1] = Research.shouldShow(pane, item(definition), renderContext) end
    check()
    character.eligible, character.known = true, 1
    check()
    character.eligible = false
    check()
    levelPerk(character)
    check()
    character.eligible = true
    now = now + 499
    check()
    now = now + 1
    check()
    local changed = player(index)
    players[index] = changed
    check()
    changed.eligible, changed.known = true, 1
    check()
    return result
end
local directOutcomes, contextOutcomes = outcomes(3), outcomes(4, {})
local expected = {false, true, true, false, false, true, false, true}
for index, value in ipairs(expected) do
    assert(directOutcomes[index] == value and contextOutcomes[index] == value,
        'direct/context behavior differs at transition ' .. index)
end
print('inventory research render context: stable getters amortized; live learning, perks, TTL, nested renders, player replacement and bounds passed')
