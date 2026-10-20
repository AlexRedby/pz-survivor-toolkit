local module = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/000ToolkitVVACompatibility.lua"
local shared = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/"
local report = print
local typo, decor = "VVA_StepVan_Decor_Trunk", "VVA_StepVan_Trunk_Decor"
local modernTypo, modernDecor = "VVA_Modern_DecorBars", "VVA_ModernBars_Decor"
local function read(path)
    local file = assert(io.open(path, "r"), path)
    local text = file:read("*a"); file:close()
    return text
end

local function setup(options)
    options = options or {}
    local w = {loaded = {}, scripts = {}, loads = {}, events = {}, messages = {}, required = {}, readers = 0, closed = 0}
    PZSurvivorToolkit = nil
    getActivatedMods = function() return {contains = function(_, id)
        return options.active ~= false and id == (options.prefixed and "\\VanillaVehiclesAnimated" or "VanillaVehiclesAnimated")
    end} end
    print = function(message) w.messages[#w.messages + 1] = message end
    getFilenameOfClosure = function(fn) return debug.getinfo(fn, "S").source:gsub("^@", "") end
    getModFileReader = function(id, path, create)
        assert(id == (options.prefixed and "\\VanillaVehiclesAnimated" or "VanillaVehiclesAnimated") and create == false)
        if not NativeVVASourceRoot or options.noReader then return nil end
        local text = read(NativeVVASourceRoot .. "/" .. path):gsub("\r\n", "\n")
        if options.changed == path then text = text .. "\n-- unknown upstream revision\n" end
        if options.fixed and path:find("VVA_applyAnimations.lua", 1, true) then text = text:gsub(typo, decor) end
        local at = 1
        w.readers = w.readers + 1
        return {readLine = function()
            if at > #text then return nil end
            local last = text:find("\n", at, true)
            local line = text:sub(at, last and last - 1 or #text)
            at = last and last + 1 or #text + 1
            return line
        end, close = function() w.closed = w.closed + 1 end}
    end
    ScriptManager = {instance = {
        getVehicleTemplate = function(_, name)
            if name == "Base." .. decor and not options.noDecor then return {} end
            if name == "Base." .. typo and options.realAlias then return {} end
            if name == "Base." .. modernDecor and options.modern then return {} end
            if name == "Base." .. modernTypo and options.realModernAlias then return {} end
        end,
        getVehicle = function(_, name)
            -- VVA_* names are inheritance-only profiles, not native vehicle scripts.
            if name:find("Base.VVA_", 1, true) == 1 then return nil end
            return {Load = function(_, _, text)
                w.loads[name] = (w.loads[name] or 0) + 1
                w.scripts[name] = text
            end}
        end,
    }}
    Events = {OnInitGlobalModData = {Add = function(fn) w.events[#w.events + 1] = fn end}}
    require = function(name)
        w.required[name] = (w.required[name] or 0) + 1
        if w.loaded[name] then return w.loaded[name] end
        local value
        if name == "PZSurvivorToolkit" or name == "PZSurvivorToolkit/SourceProof" then value = dofile(shared .. name .. ".lua")
        else
            assert(NativeVVASourceRoot, "upstream source required")
            local text = read(NativeVVASourceRoot .. "/media/lua/shared/" .. name .. ".lua")
            if options.fixed and name == "VVA_applyAnimations" then text = text:gsub(typo, decor) end
            value = assert(loadstring(text, "@" .. name .. ".lua"))()
        end
        w.loaded[name] = value or true
        return w.loaded[name]
    end
    function w.boot()
        require("VVA_applyAnimations")
        assert(#w.events == 1, "compatibility must not register another applicator")
        w.events[1]()
    end
    function w.active() return PZSurvivorToolkit and PZSurvivorToolkit.VVACompatibility end
    return w
end

local w = setup({active = false}); dofile(module)
assert(not next(w.required) and not w.active(), "inactive VVA must do nothing")
w = setup({noReader = true}); dofile(module)
assert(not w.required.VVA_core and not w.active(), "missing source must fail closed")
report("PASS VVA absent/missing source leaves upstream untouched")
if not NativeVVASourceRoot then
    report("SKIP VVA profile generation checks require --vva-source effective content root")
    return
end

local trunkSource = read(NativeVVASourceRoot .. "/media/scripts/vehicles/VVA2/StepVan/TrunkFill.txt")
assert(trunkSource:find("template vehicle " .. decor, 1, true) and not trunkSource:find(typo, 1, true))
local baseline = setup(); baseline.boot()
local function tokens(text)
    local result = {}
    for token in text:gmatch("[^,{}]+") do
        token = token:gsub("%s+", ""):gsub(";", "")
        if token ~= "" then result[#result + 1] = token end
    end
    table.sort(result)
    return table.concat(result, ",")
end
local function compare(actual, removeTypo, fixModern)
    local affected, modernAffected, total = 0, 0, 0
    for name, text in pairs(baseline.scripts) do
        local expected, count = text:gsub("template! = " .. typo .. ",", "")
        assert(count <= 1)
        if count == 1 then
            affected = affected + 1
            local _, properCount = actual.scripts[name]:gsub("template! = " .. decor .. ",", "")
            assert(properCount == 1, name .. " lost or duplicated trunk decor")
        end
        expected = removeTypo and expected or text
        if fixModern then
            local modernCount
            expected, modernCount = expected:gsub("template! = " .. modernTypo .. ",", "template! = " .. modernDecor .. ",")
            if modernCount > 0 then
                assert(modernCount == 1)
                modernAffected = modernAffected + 1
                local _, properCount = actual.scripts[name]:gsub("template! = " .. modernDecor .. ",", "")
                assert(properCount == 1, name .. " lost or duplicated Modern bars")
            end
        end
        assert(tokens(actual.scripts[name]) == tokens(expected), name .. " changed other vehicle data")
        assert(actual.loads[name] == 1, "vehicle script loaded more than once: " .. name)
        total = total + 1
    end
    for name in pairs(actual.scripts) do assert(baseline.scripts[name], "extra script: " .. name) end
    assert(affected == 29, "reviewed upstream changed its affected native vehicle set: " .. affected)
    if fixModern then assert(modernAffected == 3, "reviewed Modern police vehicle set changed") end
    return total
end
w = setup(); dofile(module); assert(w.active()); dofile(module); w.boot()
local total = compare(w, true)
assert(w.readers == w.closed and w.required.VVA_core == 3, "proof readers leaked or repeated install reloaded VVA")
local markers = 0
for _, message in ipairs(w.messages) do if message == "[PZSurvivorToolkit] VVA StepVan template compatibility active" then markers = markers + 1 end end
assert(markers == 1, "activation marker must be emitted once")
report("PASS real VVA generator: 29 typo leaves removed; one correct decor per StepVan; " .. total .. " scripts retain all other data and load once")

for _, path in ipairs({"media/lua/shared/VVA_core.lua", "media/lua/shared/VVA_applyAnimations.lua", "media/scripts/vehicles/VVA2/StepVan/TrunkFill.txt"}) do
    w = setup({changed = path}); dofile(module)
    assert(not w.active() and w.readers == w.closed, "unknown source was accepted: " .. path)
    w.boot(); compare(w, false)
end
w = setup({fixed = true}); dofile(module); assert(not w.active() and not w.required.VVA_core)
w.boot(); compare(w, true)
report("PASS changed sources fail closed; fixed upstream keeps its own single decor with no compatibility activation")

for _, options in ipairs({{noDecor = true}, {realAlias = true}}) do
    w = setup(options); dofile(module)
    assert(not w.active(), "native template guard failed")
end
w = setup(); local vva = require("VVA_core"); vva.addToProfile(typo, {"OtherModTemplate"})
dofile(module); assert(not w.active(), "another mod's existing profile was replaced")
w = setup(); vva = require("VVA_core"); vva.addToProfile = function() error("modified API called") end
dofile(module); assert(not w.active(), "modified VVA function was accepted")
w = setup({prefixed = true}); dofile(module); assert(w.active()); w.boot(); compare(w, true)
w = setup(); require("VVA_applyAnimations"); dofile(module); assert(w.active()); w.events[1](); compare(w, true)
report("PASS native template/profile/function guards, B42 prefixed ID and already-loaded upstream")

local barsPath = "media/scripts/vehicles/VVA2/Modern/Bars.txt"
local barsSource = read(NativeVVASourceRoot .. "/" .. barsPath)
assert(barsSource:find("template vehicle " .. modernDecor, 1, true)
    and barsSource:find("model DecorBars", 1, true) and barsSource:find("file = VVA_Vehicles_ModernBars_decor", 1, true))
w = setup({modern = true}); dofile(module); assert(w.active()); dofile(module); w.boot(); compare(w, true, true)
local separators = 0
for _, text in pairs(w.scripts) do
    local _, count = text:gsub("template! = VVA_[%w]+_PoliceSeparator,", "")
    separators = separators + count
end
assert(separators == 4, "unresolved PoliceSeparator leaves must remain visible")
local modernMarkers = 0
for _, message in ipairs(w.messages) do if message == "[PZSurvivorToolkit] VVA Modern bars template compatibility active" then modernMarkers = modernMarkers + 1 end end
assert(modernMarkers == 1)
for _, options in ipairs({{modern = true, changed = barsPath}, {modern = true, realModernAlias = true}}) do
    w = setup(options); dofile(module); w.boot(); compare(w, true, false)
end
w = setup({modern = true}); vva = require("VVA_core"); vva.addToProfile(modernTypo, {modernDecor})
dofile(module); w.boot(); compare(w, true, true)
w = setup({modern = true, changed = "media/scripts/vehicles/VVA2/StepVan/TrunkFill.txt"})
dofile(module); assert(w.active()); w.boot(); compare(w, false, true)
report("PASS real VVA Modern bars: three exact alias replacements, one decor each; unknown/existing target guards and independence from StepVan")
print = report
