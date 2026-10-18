local F = require "VehicleWishlistFixture"
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "VehicleWishlistTest" then return end
    assert(player:getUsername() == "client1")
    if command == "prepare" then
        sendServerCommand(player, module, "vehicles", {ids=F.prepare(player)})
    elseif command == "verify" then
        local payload = PZSurvivorWishlist.Service.snapshot(player)
        local found
        for _, list in ipairs(payload.lists) do
            if list.owner == "client1" then found = list.entries['vehicle:Base.OldTire2'] end
        end
        if args.removed then
            assert(args.removed=='mechanics' or args.removed=='inventory')
            assert(not found,'removed smart vehicle group still exists on server')
        else
            assert(found and #found.vehicleTypes == 3 and found.vehicleClass == 2 and found.done == args.done)
        end
        print('[VEHICLE_WISHLIST] AUTHORITY ' .. (args.removed and ('removed-'..args.removed) or (args.done and 'done' or 'open')))
        sendServerCommand(player, module, "verified", {done=args.done,removed=args.removed})
    end
end)
