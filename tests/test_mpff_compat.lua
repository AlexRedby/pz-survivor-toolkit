local gate = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/server/000ToolkitMPFFCompatibility.lua"

local function setup(active, server)
    local w = {handlers = {}, calls = {}, setters = {}, commands = {}, now = 1000, players = {}}
    PZSurvivorToolkit, MPFastForward = {}, nil
    getActivatedMods = function() return {contains = function(_, id) return active and id == "MPFastForward" end,
        size = function() return 0 end} end
    isServer = function() return server end
    local function event(name)
        return {Add = function(fn) w.handlers[name] = w.handlers[name] or {}; table.insert(w.handlers[name], fn) end}
    end
    Events = {OnClientCommand = event("command"), OnGameTimeLoaded = event("load"), OnTick = event("tick")}
    w.add = Events.OnClientCommand.Add
    getModInfoByID = function() return {getModVersion = function() return "fixture" end, getDir = function() return "fixture" end} end
    SandboxVars = {MPFastForward = {AllowForce = false, ForceAdminOnly = true, ControlMode = 1, Speed1 = 5, Speed2 = 10, Speed3 = 20}}
    getTimestampMs = function() return w.now end
    getOnlinePlayers = function() return {size = function() return #w.players end, get = function(_, i) return w.players[i + 1] end} end
    getGameTime = function() return {setMultiplier = function(_, value)
        assert(type(value) == "number" and value == value and value < math.huge, "invalid engine multiplier")
        w.setters[#w.setters + 1] = value
    end} end
    sendServerCommand = function(...) w.commands[#w.commands + 1] = {...} end
    w.player = {getOnlineID = function() return 7 end, isAccessLevel = function() return false end, isAsleep = function() return false end}
    w.players = {w.player}
    local loaded = {}
    require = function(name)
        w.calls[#w.calls + 1] = name
        if loaded[name] then return loaded[name] end
        if name == "PZSurvivorToolkit" then loaded[name] = true; return true end
        if name == "MPFastForward_Config" then
            assert(loadstring(assert(NativeMPFFConfigSource, "native MPFF config missing")))()
        elseif name == "MPFastForward_Server" then
            if w.fail then error("fixture load error") end
            assert(loadstring(assert(NativeMPFFServerSource, "native MPFF server missing")))()
        else error("unexpected require: " .. name) end
        loaded[name] = true
        return true
    end
    return w
end

for _, mode in ipairs({{false, true}, {true, false}}) do
    local w = setup(mode[1], mode[2])
    dofile(gate)
    assert(#w.calls == 0 and Events.OnClientCommand.Add == w.add and not PZSurvivorToolkit.MPFastForwardCompatibility)
end
print("PASS MPFF inactive mod and client leave registrations untouched")
if not NativeMPFFConfigSource or not NativeMPFFServerSource then
    print("SKIP MPFF load/handler checks require actual upstream config and server sources")
    return
end

local w = setup(true, true)
dofile(gate)
assert(Events.OnClientCommand.Add == w.add and PZSurvivorToolkit.MPFastForwardCompatibility == true)
assert(#w.handlers.command == 1 and #w.handlers.load == 1 and #w.handlers.tick == 1)
local handler = w.handlers.command[1]
local malformed = {false, "bad", {}, {level = "2"}, {level = "bad"}, {level = 0 / 0},
    {level = math.huge}, {level = -math.huge}, {level = 2.5}, {level = -1}, {level = 5}, {level = false}}
assert(pcall(handler, "MPFastForward", "select", w.player, nil))
for _, args in ipairs(malformed) do
    assert(pcall(handler, "MPFastForward", "select", w.player, args), "malformed command reached upstream")
end
assert(#w.setters == 0 and #w.commands == 0, "malformed select must not reach engine or broadcast")
handler("MPFastForward", "select", w.player, {level = 2})
assert(w.setters[#w.setters] == 5 and #w.commands > 0, "valid selection must still reach native consensus")
handler("MPFastForward", "hello", w.player, nil)
local commands = #w.commands
handler("OtherMod", "select", w.player, nil)
assert(#w.commands == commands)
local unchanged = handler
dofile(gate)
assert(#w.handlers.command == 1 and w.handlers.command[1] == unchanged and Events.OnClientCommand.Add == w.add)
local later = function() end
Events.OnClientCommand.Add(later)
assert(w.handlers.command[2] == later, "later event registrations must not remain wrapped")
print("PASS MPFF malformed NaN/infinite/fraction/string/nil args rejected; valid select, other commands and later registrations preserved")

for level = 0, 4 do
    w = setup(true, true); dofile(gate)
    w.handlers.command[1]("MPFastForward", "select", w.player, {level = level})
    w.now = w.now + 201; w.handlers.tick[1]()
    local expected = ({[0] = 0.0001, 1, 5, 10, 20})[level]
    assert((w.setters[#w.setters] or 1) == expected, "native level failed: " .. level)
end
w = setup(true, true); dofile(gate)
w.players[2] = {getOnlineID = function() return 8 end, isAccessLevel = function() return false end, isAsleep = function() return false end}
w.handlers.command[1]("MPFastForward", "select", w.player, {level = 2})
assert(#w.setters == 0, "one fast-forward vote must not bypass native consensus")
w.handlers.command[1]("MPFastForward", "select", w.players[2], {level = 2})
assert(w.setters[#w.setters] == 5)
print("PASS MPFF native pause/normal/speed levels and two-player consensus preserved")

w = setup(true, true); dofile(gate)
SandboxVars.MPFastForward.ControlMode = MPFastForward.CONTROL_ADMIN
w.players[2] = {getOnlineID=function() return 8 end, isAccessLevel=function() return true end, isAsleep=function() return false end}
w.handlers.command[1]("MPFastForward", "select", w.player, {level=4})
assert(#w.setters==0, "ordinary vote must not override admin-only control")
w.handlers.command[1]("MPFastForward", "select", w.players[2], {level=3})
assert(w.setters[#w.setters]==10, "valid admin selection must reach upstream")
local setters, commands = #w.setters, #w.commands
w.handlers.command[1]("MPFastForward", "select", w.players[2], {level=0/0,force=true,veto=true})
assert(#w.setters==setters and #w.commands==commands, "malformed admin force/veto must be rejected")
SandboxVars.MPFastForward.AllowForce = true
w.handlers.command[1]("MPFastForward", "select", w.player, {level=2,force=true})
assert(w.setters[#w.setters]==10, "upstream admin-only force permissions must remain intact")
w.handlers.command[1]("MPFastForward", "select", w.players[2], {level=4,force=true})
assert(w.setters[#w.setters]==20, "valid admin force must remain available")
print("PASS MPFF admin voting/force permissions and malformed admin requests")

w = setup(true, true); w.fail = true
local ok, err = pcall(dofile, gate)
assert(not ok and tostring(err):find("fixture load error") and Events.OnClientCommand.Add == w.add)
assert(not PZSurvivorToolkit.MPFastForwardCompatibility and not w.handlers.command)
w.fail = false; dofile(gate)
assert(PZSurvivorToolkit.MPFastForwardCompatibility and #w.handlers.command == 1)
w = setup(true, true); require("MPFastForward_Server")
local original = w.handlers.command[1]
dofile(gate)
assert(not PZSurvivorToolkit.MPFastForwardCompatibility and w.handlers.command[1] == original and #w.handlers.command == 1)
assert(Events.OnClientCommand.Add == w.add, "wrong load order must restore Add and avoid claiming success")
print("PASS MPFF load errors restore Add/rethrow/retry; wrong order is detected without extra handlers")
