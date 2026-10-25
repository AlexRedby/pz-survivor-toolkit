local Protocol = require "PZSurvivorToolkit/VehicleDiagnosticsProtocol"
local Server = {}
local function state()
    if type(toolkitVehicleTraceStatus) ~= "function" or type(toolkitVehicleTraceSet) ~= "function" then
        return "unavailable", ""
    end
    local ok, status = pcall(toolkitVehicleTraceStatus)
    if not ok or not Protocol.status(status) then return "error", "" end
    local path = ""
    if type(toolkitVehicleTracePath) == "function" then
        local success, value = pcall(toolkitVehicleTracePath)
        if success and type(value) == "string" then path = value end
    end
    return status, path
end
function Server.command(module, command, player, args)
    if module ~= Protocol.MODULE or not isServer() or not player or not Protocol.request(args) then return end
    if command ~= "Status" and command ~= "Set" then return end
    if command == "Set" and type(args.enabled) ~= "boolean" then return end
    local status, path
    if type(toolkitVehicleTraceCanControl) ~= "function" then
        status, path = "unavailable", ""
    else
        -- The Java bridge checks the real sender's live server connection.
        local ok, host = pcall(toolkitVehicleTraceCanControl, player)
        if not ok or host ~= true then
            status, path = "denied", ""
        else
            local failed = false
            if command == "Set" then
                if type(toolkitVehicleTraceSet) == "function" then
                    failed = not pcall(toolkitVehicleTraceSet, args.enabled)
                end
            end
            status, path = state()
            if failed then status = "error" end
        end
    end
    sendServerCommand(player, Protocol.MODULE, "State", {request=args.request, status=status, path=path})
end
Events.OnClientCommand.Add(Server.command)
return Server
