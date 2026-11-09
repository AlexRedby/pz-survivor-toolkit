if not isServer() then return end
local Authority=require 'QueueEngineAuthority'
local selection=require 'QueueTestSelection'
local P=require 'QueueEnergyPlacement'
local waiting,peers,begun,released={},{},false,false
local function execute(module,command,player,args,proof)
    local ok,result=pcall(function()
        if command=='Layout'then return Authority.plan(player,args.case)end
        if command=='Prepare' then
            local result=Authority.prepare(player,args.case,args.target,proof)
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
    if result then sendServerCommand(player,module,command=='Layout'and'Layout'or command=='Prepare' and 'Prepared' or command=='Invalidate' and 'Invalidated' or 'Verified',result) end
end
local function failure(module,player,args,problem)
    waiting[player]=nil
    local reason=tostring(problem)
    print('[QUEUE_TEST] FAIL engine server '..reason)
    sendServerCommand(player,module,'Prepared',{case=type(args)=='table'and args.case or nil,ok=false,error=reason})
end
Events.OnClientCommand.Add(function(module,command,player,args)
    if module~='EngineQueueTest'then return end
    local ok,problem=pcall(function()
        assert(type(args)=='table'and type(args.case)=='string','engine request case missing')
        if command=='Prepare'then
            assert(not waiting[player],'overlapping engine arrival request')
            local target=P.target(args.target)
            local proof=args.clientPlacement
            assert(type(proof)=='table'and proof.mode=='local','engine owning-client arrival proof missing')
            local clientTarget=P.target(proof.target)
            assert(clientTarget.x==target.x and clientTarget.y==target.y and clientTarget.z==target.z,
                'engine client arrival target differs')
            waiting[player]={module=module,command=command,args=args,arrival=P.observe(player,target),target=target}
        elseif command=='Layout'and not player:getCurrentSquare()then
            assert(not waiting[player],'overlapping engine layout request')
            waiting[player]={module=module,command=command,args=args}
        else execute(module,command,player,args)end
    end)
    if not ok then failure(module,player,args,problem)end
end)
Events.OnTick.Add(function()
    for player,request in pairs(waiting)do
        local ok,problem=pcall(function()
            if request.command=='Layout'then
                if not player:getCurrentSquare()then return end
                waiting[player]=nil;execute(request.module,request.command,player,request.args)
            else
                local proof=P.poll(request.arrival);if not proof then return end
                assert(P.at(player,request.target),'engine replica left final standing placement')
                waiting[player]=nil;execute(request.module,request.command,player,request.args,proof)
            end
        end)
        if not ok then failure(request.module,player,request.args,problem)end
    end
end)
