-- Host's native server category must use owned classification without losing explicit instance state.
PZSurvivorToolkit = {}
local script = {getDisplayCategory = function() return 'Material' end,
    getDisplayName = function() return 'Local nails' end}
local media = {getTranslatedItemDisplayName = function() return 'Local VHS title' end}
getScriptManager = function() return {FindItem = function() return script end} end
getZomboidRadio = function() return {getRecordedMedia = function() return {
    getMediaData = function(_, id) assert(id == 'stable-media'); return media end,
    getMediaDataFromIndex = function(_, index) assert(index == 42); return media end}
end} end
local providerCalls = 0
local Categories = {forScript = function(actual)
    assert(actual == script); providerCalls = providerCalls + 1; return 'craftingMaterial'
end}
local Tags = {forItem = function(proxy)
    assert(proxy:getFullType() == 'Base.Nails' and proxy:getScriptItem() == script)
    return {'tag:' .. proxy:getDisplayCategory()}
end, label = function(id) return 'Label ' .. id end}
require = function(module)
    if module == 'PZSurvivorToolkit/ItemCategories' then return Categories end
    if module == 'PZSurvivorToolkit/ItemTags' then return Tags end
    error(module)
end
local Presentation = dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ManifestPresentation.lua')
local name, label, tags = Presentation.describe({ft = 'Base.Nails', cat = 'Material'})
assert(name == 'Local nails' and label == 'Label tag:craftingMaterial' and tags[1] == 'tag:craftingMaterial')
name, label = Presentation.describe({ft = 'Base.Nails', cat = 'instance-fluid', name = 'My custom name'})
assert(name == 'My custom name' and label == 'Label tag:instance-fluid' and providerCalls == 1,
    'explicit instance category was replaced by generic script category')
OrganizedCategories = setmetatable({}, {__index=function() error('removed media provider accessed') end})
Categories.refineMediaCategory = function(proxy, cat)
    assert(proxy:getMediaData() == media and cat == 'craftingMaterial'); return 'experienceMedia'
end
name, label = Presentation.describe({ft = 'Base.Nails', cat = 'Material', mediaId = 'stable-media'})
assert(name == 'Local VHS title' and label == 'Label tag:experienceMedia')
name = Presentation.describe({ft = 'Base.Nails', cat = 'Material', mediaIndex = 42, name = 'Named VHS'})
assert(name == 'Named VHS', 'media title replaced a custom name')
print('Manifest presentation: local names/owned classification, instance categories, tag proxy and recorded-media labels passed.')
