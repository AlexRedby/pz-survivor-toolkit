-- Toolkit owns this feature policy; Workshop NewMusic remains unchanged.
require "PZSurvivorToolkit"
if PZSurvivorToolkit.NewMusicCompatibility then return PZSurvivorToolkit.NewMusicCompatibility end

local Compatibility = {}
PZSurvivorToolkit.NewMusicCompatibility = Compatibility

function Compatibility.active()
    local mods = getActivatedMods and getActivatedMods()
    return mods and (mods:contains("NewMusic") or mods:contains("\\NewMusic")) or false
end

-- Stable identities avoid stacked wrappers or new callbacks on lifecycle reloads.
function Compatibility.disabled() return false end
function Compatibility.noop() end

local function incompatible(detail)
    error("[PZSurvivorToolkit] Incompatible NewMusic conversion API: " .. detail)
end

function Compatibility.installShared()
    Compatibility.sharedInstalled = false
    if not Compatibility.active() then return false end
    require "core/NMRuntimeConfig"
    if type(NMRuntimeConfig) ~= "table"
        or type(NMRuntimeConfig.getConvertVanillaCDsAndCDPlayersEnabled) ~= "function" then
        incompatible("getConvertVanillaCDsAndCDPlayersEnabled missing")
    end
    -- NewMusic reads this getter at every repair/conversion call. Saved sandbox
    -- values and later network replacement of SandboxVars cannot enable it.
    NMRuntimeConfig.getConvertVanillaCDsAndCDPlayersEnabled = Compatibility.disabled
    Compatibility.sharedInstalled = true
    return true
end

function Compatibility.installClient()
    Compatibility.clientInstalled = false
    if not Compatibility.installShared() then return false end
    -- Require first, so removal sees the actual registered closures regardless
    -- of which mod's client bootstrap loaded first. PZ caches this same path.
    require "runtime/NMClientVanillaDiscVisibleProbe"
    local probe = NMClientVanillaDiscVisibleProbe
    if type(probe) ~= "table" or type(probe.scanVisibleLoot) ~= "function"
        or type(probe.onRefreshInventoryWindowContainers) ~= "function"
        or type(probe.onTick) ~= "function" then
        incompatible("visible-loot probe entrypoints missing")
    end
    local refresh = Events and Events.OnRefreshInventoryWindowContainers
    local tick = Events and Events.OnTick
    if not (refresh and refresh.Remove and tick and tick.Remove) then
        incompatible("visible-loot probe event removal unavailable")
    end
    refresh.Remove(probe.onRefreshInventoryWindowContainers)
    tick.Remove(probe.onTick)
    -- Debug loot_probe independently enables scans even with conversion off.
    -- Disable these feature-only public entrypoints too, keeping every other
    -- NewMusic callback, playback and normal loot route intact.
    probe.scanVisibleLoot = Compatibility.noop
    probe.onRefreshInventoryWindowContainers = Compatibility.noop
    probe.onTick = Compatibility.noop
    Compatibility.clientInstalled = true
    return true
end

return Compatibility
