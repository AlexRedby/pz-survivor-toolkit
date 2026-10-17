if not isServer() then return end
local Authority=require 'QueueEngineAuthority'
local waiting={}
local function execute(module,command,player,args)
    local ok,result=pcall(function()
        if command=='Prepare' then return Authority.prepare(player,args.case) end
        assert(command=='Verify','unknown engine command')
        return Authority.verify(player,args.case)
    end)
    if not ok then result={case=args.case,ok=false,error=tostring(result)};print('[QUEUE_TEST] FAIL engine server '..result.error) end
    sendServerCommand(player,module,command=='Prepare' and 'Prepared' or 'Verified',result)
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
