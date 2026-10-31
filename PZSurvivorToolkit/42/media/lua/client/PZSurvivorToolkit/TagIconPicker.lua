local Tags = require "PZSurvivorToolkit/ItemTags"
local Visuals = require "PZSurvivorToolkit/TagVisuals"
local Picker = require "PZSurvivorToolkit/ContainerIconPicker"
local Icons = {}

function Icons.entries()
    local entries, seen = {}, {}
    local function add(key, label, texture)
        if type(key) ~= "string" or key == "" then return end
        if seen[key] then seen[key].search=seen[key].search .. " " .. label:lower(); return end
        entries[#entries + 1] = {icon=key, label=label, texture=texture,
            search=(label .. " " .. key):lower()}
        seen[key]=entries[#entries]
    end
    for _, id in ipairs(Tags.cachedIds()) do
        local style = Visuals.get(id)
        add(style.icon, Tags.label(id), style.texture)
        local original = Visuals.defaults(id)
        add(original.icon, Tags.label(id), original.texture)
    end
    local scripts = getScriptManager():getAllItems()
    for index = 0, scripts:size() - 1 do
        local script = scripts:get(index)
        local icon = script:getIcon()
        if icon and icon ~= "" then
            local key = "Item_" .. icon
            add(key, script:getDisplayName() or script:getFullName(), getTexture(key))
        end
    end
    table.sort(entries, function(a, b) return a.label < b.label end)
    return entries
end

function Icons.open(owner, onPick)
    if owner.toolkitTagCatalogPending then return end
    return Picker.openEntries(owner, onPick, Icons.entries(), {
        title=getText("UI_PZST_TagEdit_Icon"), search=getText("UI_PZST_TagEdit_SearchIcons"),
        default=getText("UI_PZST_TagEdit_Default"), select=getText("UI_PZST_TagEdit_Select")})
end

return Icons
