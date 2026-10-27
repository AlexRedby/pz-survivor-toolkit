-- Client-only localization/category projection. Server item identities stay unchanged.
local Tags = require "PZSurvivorToolkit/ItemTags"
local Categories = require "PZSurvivorToolkit/ItemCategories"
local Presentation = {}
function Presentation.describe(entry)
    local script = getScriptManager():FindItem(entry.ft)
    local name, media = entry.name
    if entry.mediaId or entry.mediaIndex then
        local radio = getZomboidRadio()
        local catalog = radio and radio:getRecordedMedia()
        media = catalog and ((entry.mediaId and catalog:getMediaData(entry.mediaId))
            or (entry.mediaIndex and catalog:getMediaDataFromIndex(entry.mediaIndex)))
        name = name or (media and media:getTranslatedItemDisplayName())
    end
    name = name or (script and script:getDisplayName()) or entry.ft
    local category = entry.cat
    if not category or (script and category == script:getDisplayCategory()) then
        category = Categories.forScript(script) or category
    end
    if media then
        category = Categories.refineMediaCategory({getMediaData = function() return media end}, category) or category
    end
    -- Captured rows have no live InventoryItem for native capability predicates.
    local tags = Tags.forSnapshot(script, entry.ft, category, media, entry.tagDelta, entry.ingredient,
        entry.cookingState, entry.fluidState, entry.usageState)
    local labels = {}
    for _, id in ipairs(tags) do labels[#labels + 1] = Tags.label(id) end
    return name, table.concat(labels, ", "), tags
end

return Presentation
