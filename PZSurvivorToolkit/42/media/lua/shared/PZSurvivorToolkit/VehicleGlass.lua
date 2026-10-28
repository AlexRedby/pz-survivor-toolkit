local Glass = {}

local recipes = {
    ["Fix Window Welding"] = true,
    ["Fix Window"] = true,
    ["Fix Window 1"] = true,
    ["Fix Military Windows Welding"] = true,
}

-- VRO also places ballistic glass in its military hood repair group.
-- Keep the separate metal window armor, bars and frames repairable.
local mixedGlass = {
    ["Base.BallisticGlassWindshieldSC2"] = true,
    ["Base.BallisticGlassWindowSC2"] = true,
}

function Glass.active()
    local mods = getActivatedMods()
    return mods:contains("VehicleRepairOverhaul") or mods:contains("\\VehicleRepairOverhaul")
end

local function removeMixedGlass(items)
    for index = #items, 1, -1 do
        if mixedGlass[items[index]] then table.remove(items, index) end
    end
end

function Glass.removeLuaRecipes(list, partLists)
    for _, items in pairs(partLists or {}) do removeMixedGlass(items) end
    for index = #(list or {}), 1, -1 do
        local recipe = list[index]
        if recipes[recipe.name] then
            table.remove(list, index)
        elseif type(recipe.require) == "table" then
            removeMixedGlass(recipe.require)
        elseif mixedGlass[recipe.require] then
            recipe.require = {}
        end
    end
end

function Glass.removeScriptRecipes()
    local manager = ScriptManager.instance
    for name in pairs(recipes) do
        local fixing = manager:getFixing("VRO " .. name)
        if fixing then
            local required = fixing:getRequiredItem()
            if required then required:clear() end
            fixing:getFixers():clear()
        end
    end
    for _, name in ipairs({"VRO Fix Military Hood Welding", "VRO Fix Military Hood"}) do
        local fixing = manager:getFixing(name)
        local required = fixing and fixing:getRequiredItem()
        if required then
            for index = required:size() - 1, 0, -1 do
                if mixedGlass[required:get(index)] then required:remove(index) end
            end
        end
    end
end

return Glass
