local F = require 'VehicleDoorsFixture'
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= 'VehiclePoseTest' then return end
    local ok,err=pcall(function()
        assert(player:getUsername()=='client1')
        if command=='prepare' then
            sendServerCommand(player,module,'vehicle',{id=F.prepare(player)})
        elseif command=='check' then
            local v=assert(F.vehicle)
            assert(v:getId()==args.id)
            assert(v:getSeat(player)==args.seat, 'Authoritative seat mismatch')
            assert(player:getVehicle()==(args.seat>=0 and v or nil), 'Authoritative vehicle mismatch')
            print('[VEHICLE_POSE] AUTHORITY ' .. args.name)
            sendServerCommand(player,module,'checked',{name=args.name})
        end
    end)
    if not ok then print('[VEHICLE_POSE] FAIL server ' .. tostring(err)) end
end)
