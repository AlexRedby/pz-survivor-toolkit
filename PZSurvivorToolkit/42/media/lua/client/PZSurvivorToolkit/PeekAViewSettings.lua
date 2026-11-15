local Storage = require "PZSurvivorToolkit/ModOptionsStorage"
local Settings = {}
local markerPath = "PZSurvivorToolkitPeekAView.ini"
local markerVersion = "NativeVisibility42.22=1"

-- A one-time client preset, not a server option or a permanent override.
local preset = {
    treeFadeActiveInVehicle = false,
    fixB42Adjacency = false,
}

-- Upstream's OnGameBoot handler must load saved options before this runs.
function Settings.apply()
    local complete = Storage.matches(markerPath, markerVersion)
    if complete == nil then return false, "marker_read" end
    if complete then return true, "already_applied" end
    local options = PZAPI and PZAPI.ModOptions and PZAPI.ModOptions:getOptions("PeekAView")
    if not options then return false, "options_missing" end
    local handles, expected = {}, {}
    for id, value in pairs(preset) do
        local option = options:getOption(id)
        if not option or option.type ~= "tickbox"
            or type(option.getValue) ~= "function" or type(option.setValue) ~= "function"
            or type(option.onChangeApply) ~= "function" or type(option:getValue()) ~= "boolean" then
            return false, "option_incompatible:" .. id
        end
        handles[id] = option
        expected["tickbox|PeekAView|" .. id .. "|"] = tostring(value)
    end
    for id, value in pairs(preset) do
        handles[id]:setValue(value)
        -- setValue updates the option/UI only; the upstream callback updates Java.
        handles[id]:onChangeApply(value)
    end
    -- Upstream catches Java setter errors internally instead of throwing them.
    -- A declined JAR has no lastJavaError and can still receive saved defaults.
    if PeekAView and PeekAView.lastJavaError then return false, "java_apply:" .. tostring(PeekAView.lastJavaError) end
    -- Keep the safe runtime values if persistence fails, but leave the marker
    -- unset so a later boot retries. Verify both values and unrelated entries.
    if not Storage.save(expected) then return false, "options_save" end
    if not Storage.mark(markerPath, markerVersion) then return false, "marker_write" end
    return true, "applied"
end

function Settings.onBoot()
    local ok, applied, reason = pcall(Settings.apply)
    if not ok or not applied then
        print("[PZSurvivorToolkit] Peek a View preset not persisted; retry on next boot: "
            .. tostring(ok and reason or applied))
    end
end

return Settings
