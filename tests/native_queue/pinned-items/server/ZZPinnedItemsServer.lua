local config=require 'QueueTestSelection'
if config.kind~='mp' then return end
local F=require 'PinnedItemsFixture'
local module='PinnedItemsTest'
local vehicle,container,initial,pending
local players,ready,finished,probed={},{},{},{client1={},client2={}}
local turn='client1'

local function audit(phase)
    local signature=F.signature(container)
    assert(signature==initial and container:getItems():size()==6,'Server trunk contents changed')
    print('[PIN_ITEMS] AUTHORITY {"phase":'..F.quote(phase)..',"truckId":'..F.quote(vehicle:getId())..
        ',"itemCount":6,"itemSignature":'..F.quote(signature)..'}')
end

local function handle(command,player,args)
    local actor=player:getUsername()
    assert(actor=='client1' or actor=='client2','Unexpected fixture client')
    if command=='prepare' then
        players[actor]=player
        if not vehicle then vehicle,container=F.spawn(player);initial=F.signature(container) end
        local area=assert(vehicle:getAreaCenter(vehicle:getPartById('TruckBed'):getArea()))
        sendServerCommand(player,module,'fixture',{truckId=vehicle:getId(),x=area:getX(),y=area:getY(),itemSignature=initial})
    elseif command=='ready' then
        assert(players[actor] and not ready[actor] and args.itemSignature==initial)
        assert(player:getOnlineID()>=0)
        ready[actor]=true
        if ready.client1 and ready.client2 then
            assert(players.client1:getOnlineID()~=players.client2:getOnlineID(),'Clients share an online ID')
            audit('initial')
            sendServerCommand(players.client1,module,'start',{})
        end
    elseif command=='probe' then
        assert(actor==turn and not pending and ready.client1 and ready.client2)
        assert((args.provider=='BetterContainers' or args.provider=='organizedCategories_core') and not probed[actor][args.provider])
        pending={pinner=actor,provider=args.provider,target=args.target}
        local peer=actor=='client1' and 'client2' or 'client1'
        sendServerCommand(players[peer],module,'probe',{pinner=actor,provider=args.provider,target=args.target,truckId=vehicle:getId(),itemSignature=initial})
    elseif command=='peer-checked' then
        assert(pending and actor~=pending.pinner and args.pinner==pending.pinner and args.target==pending.target and args.provider==pending.provider)
        assert(args.pinAbsent==true and args.itemSignature==initial,'Peer pin isolation failed')
        probed[pending.pinner][pending.provider]=true
        sendServerCommand(players[pending.pinner],module,'peer-checked',{})
        pending=nil
    elseif command=='done' then
        assert(actor==turn and not pending and not finished[actor] and args.itemSignature==initial)
        assert(probed[actor].BetterContainers and probed[actor].organizedCategories_core,'Both pin providers must pass peer isolation')
        audit(actor..'-done')
        finished[actor]=true
        sendServerCommand(player,module,'complete',{})
        if actor=='client1' then turn='client2';sendServerCommand(players.client2,module,'start',{}) end
    else error('Unknown pinned item fixture command '..tostring(command)) end
end

Events.OnClientCommand.Add(function(name,command,player,args)
    if name~=module then return end
    local ok,err=pcall(handle,command,player,args)
    if not ok then print('[PIN_ITEMS] FAIL server '..tostring(err)) end
end)
