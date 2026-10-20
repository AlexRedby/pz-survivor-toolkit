local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/'
local modulePath = root .. 'client/PZSurvivorToolkit/ContainerTagIcons.lua'

local function setup(active, ready)
    local w = {active = active, ready = ready ~= false, helperLoads = 0, originalCalls = 0, textures = {}}
    PZSurvivorToolkit = {Settings = {itemTags = function() return false end}}
    EURY_CONTAINERS = nil
    getActivatedMods = function()
        return {contains = function(_, id) return w.active and id == '\\EURY_CONTAINERS' end}
    end
    Events = {OnGameStart = {Add = function(callback) w.onStart = callback end}}
    getTexture = function(id)
        w.textures[id] = w.textures[id] or {id = id}
        return w.textures[id]
    end
    instanceItem = function() error('tag texture resolution attempted to create an inventory item') end
    w.helpers = {getIconTexture = function(icon, extra)
        w.originalCalls = w.originalCalls + 1
        w.lastIcon, w.lastExtra = icon, extra
        return 'native-texture', nil, 'native-third'
    end}
    w.original = w.helpers.getIconTexture
    local loaded = {}
    require = function(name)
        if name == 'BetterContainers/Helpers' then
            w.helperLoads = w.helperLoads + 1
            if not w.ready then error('BC helpers have not loaded yet') end
            return w.helpers
        end
        if loaded[name] then return loaded[name] end
        local path = name == 'PZSurvivorToolkit/ContainerAppearance' and 'shared/'
            or name == 'PZSurvivorToolkit/TagVisuals' and 'client/'
        assert(path, 'unexpected require: ' .. name)
        loaded[name] = dofile(root .. path .. name .. '.lua')
        return loaded[name]
    end
    w.icons = dofile(modulePath)
    return w
end

local w = setup(true)
assert(w.helpers.getIconTexture ~= w.original and w.onStart, 'active BC adapter was not installed before game start')
local tag = {kind = 'pzst-tag', value = 'food'}
assert(w.helpers.getIconTexture(tag) == w.textures.Item_Plate, 'tag did not reuse its real TagVisuals texture')
local medical = {kind = 'pzst-tag', value = 'medical'}
assert(w.helpers.getIconTexture(medical) == w.textures['media/ui/LootableMaps/map_medcross.png'], 'tag UI-path icon was not resolved')
assert(w.originalCalls == 0, 'owned tag icon reached native item resolution')
for _, icon in ipairs({{kind = 'pzst-tag'}, {kind = 'pzst-tag', value = false},
    {kind = 'pzst-tag', value = ''}, {kind = 'pzst-tag', value = '  '},
    {kind = 'pzst-tag', value = 'unknown-tag'}}) do
    assert(w.helpers.getIconTexture(icon) == nil, 'missing tag texture acquired a fallback')
end
assert(w.originalCalls == 0, 'malformed or unknown owned tag fell through to native resolver')
for _, icon in ipairs({'Base.Hammer', {kind = 'item', value = 'Base.Hammer'},
    {kind = 'container', value = 'crate'}, {kind = 'other-mod', value = 'arbitrary'}}) do
    local first, second, third = w.helpers.getIconTexture(icon, 'extra')
    assert(first == 'native-texture' and second == nil and third == 'native-third', 'native return values changed')
    assert(w.lastIcon == icon and w.lastExtra == 'extra', 'native resolver arguments changed')
end
local wrapper = w.helpers.getIconTexture
assert(w.icons.install() and w.helpers.getIconTexture == wrapper and w.helperLoads == 1, 'repeat install added a wrapper')
assert(dofile(modulePath) == w.icons and w.helpers.getIconTexture == wrapper, 'repeat module load added a wrapper')
w.onStart()
assert(w.helpers.getIconTexture == wrapper, 'game-start retry added a wrapper')
local later = function(icon, ...) return wrapper(icon, ...) end
w.helpers.getIconTexture = later
w.icons.install()
assert(w.helpers.getIconTexture == later, 'repeat install removed a later integration wrapper')
print('PASS real tag textures, disabled tag UI, native passthrough and idempotent icon adapter')

w = setup(false)
assert(w.helperLoads == 0 and w.helpers.getIconTexture == w.original, 'inactive BC loaded or patched helpers')
w.active = true
w.onStart()
assert(w.helperLoads == 1 and w.helpers.getIconTexture({kind = 'pzst-tag', value = 'food'}) == w.textures.Item_Plate,
    'delayed BC activation did not install the adapter')
w = setup(true, false)
assert(w.helpers.getIconTexture == w.original, 'failed helper load changed its resolver')
w.ready = true
w.onStart()
assert(w.helpers.getIconTexture({kind = 'pzst-tag', value = 'food'}) == w.textures.Item_Plate,
    'game-start retry did not recover a delayed helper load')
print('PASS inactive BC isolation and delayed helper installation')
