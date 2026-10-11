if not isServer() or not getActivatedMods():contains("MPFastForward") then return end
require "PZSurvivorToolkit"
require "MPFastForward_Config"
if PZSurvivorToolkit.MPFastForwardCompatibility then return end

-- The upstream handler is private; wrap its registration before the module loads.
local event, add = Events.OnClientCommand, Events.OnClientCommand.Add
local installed = false
event.Add = function(handler)
    installed = true
    add(function(module, command, player, args)
        if module == MPFastForward.MODULE and command == "select" then
            local level = type(args) == "table" and args.level
            if type(level) ~= "number" or not (level >= MPFastForward.PAUSE
                and level <= MPFastForward.MAX_LEVEL and level == math.floor(level)) then return end
        end
        return handler(module, command, player, args)
    end)
end
local ok, err = pcall(require, "MPFastForward_Server")
event.Add = add
if not ok then error(err) end
PZSurvivorToolkit.MPFastForwardCompatibility = installed
if not installed then
    print("[PZSurvivorToolkit] MP Fast Forward validation needs Toolkit before MPFastForward")
end
