local Protocol = require "PZSurvivorToolkit/VehicleDiagnosticsProtocol"
local Client = {server={status="unknown", path=""}}
local serial, nextQuery = 0, 0
local function now() return getTimestampMs() end
function Client.localStatus()
    if type(toolkitVehicleTraceStatus) ~= "function" or type(toolkitVehicleTraceSet) ~= "function" then
        return "unavailable"
    end
    local ok, status = pcall(toolkitVehicleTraceStatus)
    return ok and Protocol.status(status) and status or "error"
end
function Client.localPath()
    if type(toolkitVehicleTracePath) ~= "function" then return "" end
    local ok, path = pcall(toolkitVehicleTracePath)
    return ok and type(path) == "string" and path or ""
end
function Client.setLocal(enabled)
    if type(toolkitVehicleTraceSet) ~= "function" then return false end
    return pcall(toolkitVehicleTraceSet, enabled == true)
end
function Client.canControlServer()
    return isClient() and type(isCoopHost) == "function" and isCoopHost() == true
        and getSpecificPlayer(0) ~= nil
end
local function request(command, enabled)
    if not Client.canControlServer() or Client.server.pending then return false end
    serial = serial % 2147483647 + 1
    local args = {request=serial}
    if command == "Set" then args.enabled = enabled end
    Client.server.pending = {id=serial, deadline=now()+5000}
    local ok = pcall(sendClientCommand, getSpecificPlayer(0), Protocol.MODULE, command, args)
    if not ok then
        Client.server.pending, Client.server.status = nil, "error"
        nextQuery = now()+2000
    end
    return ok
end
function Client.queryServer() return request("Status") end
function Client.setServer(enabled)
    if type(enabled) ~= "boolean" then return false end
    return request("Set", enabled)
end
function Client.pollServer()
    local server = Client.server
    if not Client.canControlServer() then
        server.status, server.path, server.pending = isClient() and "denied" or "noServer", "", nil
        return server
    end
    local time = now()
    if server.pending and time >= server.pending.deadline then
        server.pending, server.status, server.path = nil, "timeout", ""
        nextQuery = time+2000
    end
    if not server.pending and time >= nextQuery then
        nextQuery = time+2000
        Client.queryServer()
    end
    return server
end
function Client.receive(module, command, args)
    if module ~= Protocol.MODULE or command ~= "State" or not Client.canControlServer()
        or not Protocol.request(args) or not Client.server.pending
        or args.request ~= Client.server.pending.id or not Protocol.status(args.status)
        or type(args.path) ~= "string" or #args.path > 4096 then return end
    Client.server.status, Client.server.path, Client.server.pending = args.status, args.path, nil
    nextQuery = now()+2000
end
Events.OnServerCommand.Add(Client.receive)
Events.OnDisconnect.Add(function()
    Client.server.status, Client.server.path, Client.server.pending = "unknown", "", nil
    nextQuery = 0
end)
return Client
