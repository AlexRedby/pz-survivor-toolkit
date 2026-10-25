local F = require 'VehicleDoorsFixture'
local probe = require 'VehiclePoseProbeConfig'
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= 'VehiclePoseTest' then return end
    local ok,err=pcall(function()
        assert(player:getUsername()=='client1')
        if command=='prepare' then
            local spawned=F.prepare(player)
            if probe.newMusic then
                local resolver=assert(NMLootPlaceholderResolver,'Selected NewMusic resolver not loaded')
                local container=assert(F.vehicle:getPartById('GloveBox'):getItemContainer())
                local kind=assert(resolver.getMediaPlaceholderFullType('cassettes','standard'))
                local placeholder=assert(container:AddItem(kind))
                assert(resolver.replacePlaceholdersInContainer(container,{routeClass='vehicle_glovebox',containerType=container:getType(),shape='vehicle'})>=1,
                    'Early music conversion did not execute')
                assert(not container:getItemWithID(placeholder:getID()),'Placeholder was not removed')
                print('[STARTUP_NET] MUSIC_PROBE vehicle=' .. spawned .. ' placeholder=' .. placeholder:getID() .. ' contents=' .. vehicleStartupContents(F.vehicle))
            end
            sendServerCommand(player,module,'vehicle',{id=spawned})
        elseif command=='check' then
            local v=assert(F.vehicle)
            assert(v:getId()==args.id)
            assert(v:getSeat(player)==args.seat, 'Authoritative seat mismatch')
            assert(player:getVehicle()==(args.seat>=0 and v or nil), 'Authoritative vehicle mismatch')
            assert(vehicleStartupContents(v)==args.contents, 'Vehicle container item IDs/types differ between server and client')
            print('[VEHICLE_POSE] CONTENTS ' .. args.name .. ' ' .. args.contents)
            print('[VEHICLE_POSE] AUTHORITY ' .. args.name)
            sendServerCommand(player,module,'checked',{name=args.name})
        end
    end)
    if not ok then print('[VEHICLE_POSE] FAIL server ' .. tostring(err)) end
end)
