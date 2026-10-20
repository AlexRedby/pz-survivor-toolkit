local F = require 'VehicleDoorsFixture'
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= 'VehicleDoorsTest' then return end
    local ok, err = pcall(function()
        assert(player:getUsername() == 'client1')
        if command == 'prepare' then
            sendServerCommand(player, module, 'vehicle', {id=F.prepare(player)})
        elseif command == 'verify' then
            local vehicle = getVehicleById(args.id)
            assert(vehicle == F.vehicle)
            F.verify(vehicle, player)
            sendServerCommand(player, module, 'verified', {id=args.id})
        end
    end)
    if not ok then print('[VEHICLE_DOORS] FAIL server ' .. tostring(err)) end
end)
