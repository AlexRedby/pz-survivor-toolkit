if not isServer() then return end
local Authority=require 'QueueEngineAuthority'
local selection=require 'QueueTestSelection'
local waiting,peers,begun,released={},{},false,false
local function execute(module,command,player,args)
    local ok,result=pcall(function()
        if command=='Prepare' then
            local result=Authority.prepare(player,args.case)
            if selection.suite=='engine-peers' then
                assert(player:getUsername()=='client1' or player:getUsername()=='client2','unexpected peer')
                peers[player:getUsername()]={player=player}
            end
            return result
        end
        if command=='Ready' or command=='Started' then
            assert(selection.suite=='engine-peers' and args.case=='peer-cancel','unexpected peer barrier')
            local peer=assert(peers[player:getUsername()],'unprepared peer')
            assert(peer.player==player,'peer identity changed')
            if command=='Ready' then peer.ready=true
            else
                assert(begun and not peer.started,'unexpected peer start')
                assert(type(args.transaction)=='number' and args.transaction%1==0 and args.transaction~=0
                    and args.transaction>=-128 and args.transaction<=127,'invalid peer transaction')
                assert(type(args.token)=='string' and #args.token==36 and args.token:match('^[%x%-]+$'),'invalid peer token')
                peer.started={id=args.transaction,token=args.token}
            end
            local first,second=peers.client1,peers.client2
            if first and second and first.ready and second.ready and not begun then
                begun=true
                for _,entry in pairs(peers) do sendServerCommand(entry.player,module,'Begin',{case=args.case}) end
            end
            if first and second and first.started and second.started and not released then
                assert(first.started.id==second.started.id,'native peer IDs did not collide')
                assert(first.player:getOnlineID()~=second.player:getOnlineID() and first.started.token~=second.started.token,
                    'peer receipt owners or tokens overlap')
                released=true
                print('[ENGINE_TEST] COLLISION case=peer-cancel transaction='..first.started.id
                    ..' firstPlayer='..first.player:getOnlineID()..' secondPlayer='..second.player:getOnlineID()
                    ..' firstToken='..first.started.token..' secondToken='..second.started.token)
                for _,entry in pairs(peers) do sendServerCommand(entry.player,module,'Release',{case=args.case}) end
            end
            return
        end
        if command=='Invalidate' then return Authority.invalidate(player,args.case) end
        assert(command=='Verify','unknown engine command')
        if selection.suite=='engine-peers' then assert(released,'peer verification preceded collision') end
        return Authority.verify(player,args.case)
    end)
    if not ok then result={case=args.case,ok=false,error=tostring(result)};print('[QUEUE_TEST] FAIL engine server '..result.error) end
    if result then sendServerCommand(player,module,command=='Prepare' and 'Prepared' or command=='Invalidate' and 'Invalidated' or 'Verified',result) end
end
Events.OnClientCommand.Add(function(module,command,player,args)
    if module~='EngineQueueTest' then return end
    if command=='Prepare' and not player:getCurrentSquare() then
        waiting[player]={module=module,command=command,args=args};return
    end
    execute(module,command,player,args)
end)
Events.OnTick.Add(function()
    for player,request in pairs(waiting) do
        if player:getCurrentSquare() then
            waiting[player]=nil
            execute(request.module,request.command,player,request.args)
        end
    end
end)
