local Catalog = dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ItemRecipeCatalog.lua')
local epoch, revisionReads = 0, 0
local bridge = function() revisionReads = revisionReads + 1; return epoch end
toolkitRecipeCatalogRevision = bridge
local craftReads, legacyReads = 0, 0
local craft, legacy = {}, {}
local manager = {
    getAllCraftRecipes = function() craftReads = craftReads + 1; return craft end,
    getAllRecipes = function() legacyReads = legacyReads + 1; return legacy end,
}
local context = Catalog.newContext()
assert(revisionReads == 0 and craftReads == 0, 'creating a context eagerly read metadata')
for _ = 1, 200 do
    assert(context:recipes(manager, 'getAllCraftRecipes') == craft)
    assert(context:recipes(manager, 'getAllRecipes') == legacy)
    local value, source = context:revision()
    assert(value == 0 and source == bridge)
end
assert(craftReads == 1 and legacyReads == 1 and revisionReads == 1,
    'metadata or lifecycle revision was read per item instead of per operation')
epoch = 1
assert(context:revision() == 0, 'context lifetime changed during the synchronous operation')
local fresh = Catalog.newContext()
assert(fresh:revision() == 1 and revisionReads == 2, 'new operation missed the native lifecycle revision')
assert(fresh:recipes(manager, 'getAllCraftRecipes') == craft and craftReads == 2)
local other = {getAllCraftRecipes = function() return legacy end}
assert(fresh:recipes(other, 'getAllCraftRecipes') == legacy, 'manager metadata leaked across identities')

-- Both a missing bridge and a bridge reporting unsupported/partial native state
-- permit operation-local reuse only. Invalid numeric epochs cannot certify it.
for _, mode in ipairs({'missing', 'nil', 'negative', 'infinite', 'nan'}) do
    if mode == 'missing' then toolkitRecipeCatalogRevision = nil
    else toolkitRecipeCatalogRevision = function()
        if mode == 'negative' then return -1 end
        if mode == 'infinite' then return math.huge end
        if mode == 'nan' then return 0 / 0 end
    end end
    local first, second = Catalog.newContext(), Catalog.newContext()
    local token = first:revision()
    assert(type(token) == 'table' and first:revision() == token,
        'untrusted native revision lost operation-local batching')
    assert(second:revision() ~= token, 'untrusted native revision certified cross-operation reuse')
end

-- A replaced bridge returning the same number still has a distinct identity.
toolkitRecipeCatalogRevision = function() return 1 end
local value, source = Catalog.newContext():revision()
assert(value == 1 and source ~= bridge, 'bridge identity was not part of the cache contract')
local attempts = 0
toolkitRecipeCatalogRevision = function()
    attempts = attempts + 1
    if attempts == 1 then error('native revision probe failed') end
    return 2
end
context = Catalog.newContext()
assert(not pcall(context.revision), 'revision probe failure was hidden')
assert(context:revision() == 2 and attempts == 2, 'failed revision probe poisoned the context')

print('recipe catalog: bounded reads, native revisions, bridge replacement and operation-local fallback passed')
