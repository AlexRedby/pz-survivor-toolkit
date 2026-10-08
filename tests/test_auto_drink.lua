-- Regression: options must reach local player packets; server Core must not veto them.
local function event()
    local callbacks = {}
    return { Add = function(fn) callbacks[#callbacks + 1] = fn end,
        fire = function(...) for _, fn in ipairs(callbacks) do fn(...) end end }
end
Events = { OnGameStart = event(), OnCreatePlayer = event(),
    OnServerStarted = event(), OnTick = event() }
local core = { enabled = false, writes = 0 }
function core:getOptionAutoDrink() return self.enabled end
function core:setOptionAutoDrink(value) self.enabled = value; self.writes = self.writes + 1 end
function core:saveOptions() error("Server must not overwrite the host's options.ini") end
getCore = function() return core end
local client = true
isClient = function() return client end
local players = { { enabled = true }, { enabled = true } }
for _, player in ipairs(players) do
    function player:setAutoDrink(value) self.enabled = value end
end
getMaxActivePlayers = function() return 4 end
getSpecificPlayer = function(i) return players[i + 1] end
require = function(name) assert(name == "OptionScreens/MainOptions") end
local calls = 0
MainOptions = { apply = function(self, value)
    assert(self == MainOptions)
    calls = calls + 1
    core.enabled = value
    return false
end }
dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/AutoDrink.lua")
Events.OnGameStart.fire()
assert(not players[1].enabled and not players[2].enabled, "Join must respect disabled preference")
assert(MainOptions:apply(true) == false and calls == 1, "Preserve native apply and return")
assert(players[1].enabled and players[2].enabled, "Enable must update all local player flags")
MainOptions:apply(false)
assert(not players[1].enabled and not players[2].enabled, "Disable must update local flags")
players[1].enabled = true
Events.OnCreatePlayer.fire(0, players[1])
assert(not players[1].enabled, "Respawn must respect the saved preference")
players[3], players[2] = players[2], nil
players[3].enabled = true
Events.OnCreatePlayer.fire(2, players[3])
assert(not players[3].enabled, "Sparse local player slots must also synchronize")
client = false
MainOptions:apply(true)
assert(not players[1].enabled, "Single-player must keep its native Core handling")

isServer = function() return false end
local serverFile = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/server/PZSurvivorToolkit/AutoDrink.lua"
dofile(serverFile)
core.enabled = false
Events.OnTick.fire()
assert(not core.enabled, "Server Lua loaded in single-player must leave Core alone")
isServer = function() return true end
dofile(serverFile)
core.enabled = false
Events.OnServerStarted.fire()
assert(core.enabled, "The host's disabled Core must not block every player")
local writes = core.writes
for _ = 1, 10 do Events.OnTick.fire() end
assert(core.writes == writes, "Do not rewrite an already enabled server gate")
core.enabled = false -- reloadoptions reads the host's file again.
Events.OnTick.fire()
assert(core.enabled and core.writes == writes + 1, "Restore the gate after reloadoptions")
assert(not players[1].enabled and not players[3].enabled, "Do not enable disabled players")
print("Auto-drink preference regression passed.")
