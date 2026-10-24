local F = require 'VehicleDiagnosticsFixture'
local observed = {}
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= 'VehicleDiagnosticsTest' then return end
    local ok, err = pcall(function()
        assert(player:getUsername() == 'client1')
        if command == 'prepare' then
            sendServerCommand(player, module, 'vehicle', {id=F.prepare(player)})
        elseif command == 'observe' then
            local v = assert(F.vehicle)
            assert(v:getId() == args.id)
            local occupied = player:getVehicle() == v and v:getSeat(player) == 0
            local status = toolkitVehicleTraceStatus()
            if occupied and status == args.state then
                if not observed[status] then
                    observed[status] = true
                    print('[VEHICLE_DIAGNOSTICS] AUTHORITY state=' .. status .. ' id=' .. args.id .. ' driver=' .. player:getOnlineID())
                end
                sendServerCommand(player, module, 'observed', {id=args.id, state=status})
            end
        end
    end)
    if not ok then print('[VEHICLE_DIAGNOSTICS] FAIL server ' .. tostring(err)) end
end)
