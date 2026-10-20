local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/'
local primary, selected = {}, {}
local clock, packets, replies
local function fire(name, ...)
    for _, fn in ipairs({unpack(Events[name].handlers)}) do fn(...) end
end
local function setup(client)
    clock, packets, replies = 0, {}, {}
    isClient = function() return client end
    getSpecificPlayer = function(index) assert(index == 0); return primary end
    getTimestampMs = function() return clock end
    LootSorter = {RPC_TIMEOUT_MS=15000, RPC_SWEEP_MS=5000, DBG=function() end}
    Events = {}
    for _, name in ipairs({'OnClientCommand','OnServerCommand','OnGameStart','OnTick'}) do
        local event = {handlers={}}
        event.Add = function(fn) event.handlers[#event.handlers+1]=fn end
        event.Remove = function(fn)
            for i=#event.handlers,1,-1 do if event.handlers[i]==fn then table.remove(event.handlers,i) end end
        end
        Events[name] = event
    end
    require = function(name)
        if name == 'PZSurvivorToolkit/ItemTags' then return {} end
        return dofile(root .. name .. '.lua')
    end
    sendClientCommand = function(player, module, command, args)
        packets[#packets+1] = {player=player,module=module,command=command,args=args}
    end
    sendServerCommand = function(player, module, command, args)
        replies[#replies+1] = {player=player,module=module,command=command,args=args}
    end
    dofile(root .. 'LootSorter_Rpc.lua')
end

setup(false)
local echo = LootSorter.serverFn('echo', function(player, args)
    return 'ok', {selected=player==selected, value=args.value}
end)
local calls = 0
echo({value=7},function(verdict,detail)
    assert(verdict=='ok' and detail.selected and detail.value==7); calls=calls+1
end,selected)
echo({value=8},function(verdict,detail)
    assert(verdict=='ok' and not detail.selected and detail.value==8); calls=calls+1
end)
assert(calls==2 and #packets==0, 'SP must call once inline with the selected or default player')
fire('OnClientCommand','Quartermaster','echo',selected,{value=9,rpcToken=12})
assert(#replies==1 and replies[1].player==selected and replies[1].module=='Quartermaster'
    and replies[1].command=='rpcResult' and replies[1].args.rpcToken==12
    and replies[1].args.verdict=='ok' and replies[1].args.detail.selected,
    'authority reply lost its authenticated player, token or detail')

setup(true)
local args = {value=10, nested={}, rpcToken=999}
local results = {}
LootSorter.callServer('saveBox',args,function(v,d) results[#results+1]={v,d} end,selected)
LootSorter.callServer('putPreset',args,function(v,d) results[#results+1]={v,d} end)
LootSorter.callServer('addCoord',args)
assert(packets[1].player==selected and packets[2].player==primary and #packets==3,
    'explicit player was replaced by the primary player')
assert(args.rpcToken==999 and packets[1].args~=args and packets[1].args.nested==args.nested
    and packets[1].args.rpcToken~=packets[2].args.rpcToken and not packets[3].args.rpcToken,
    'transport mutated caller arguments or reused request correlation')
local function reply(packet, verdict, detail)
    fire('OnServerCommand','Quartermaster','rpcResult',
        {rpcToken=packet.args.rpcToken,verdict=verdict,detail=detail})
end
reply(packets[2],'stale',{revision=4}); reply(packets[1],'ok',{revision=5})
reply(packets[1],'denied')
assert(#results==2 and results[1][1]=='stale' and results[1][2].revision==4
    and results[2][1]=='ok' and results[2][2].revision==5, 'callbacks were mismatched or invoked twice')

local timedOut, completed = 0, 0
LootSorter.callServer('saveBox',{},function(verdict) assert(verdict==nil); timedOut=timedOut+1 end,selected)
local expired = packets[#packets]
clock=16000; fire('OnTick')
reply(expired,'ok',{revision=1}); clock=22000; fire('OnTick')
assert(timedOut==1, 'timeout/late reply invoked a callback more than once')
LootSorter.callServer('saveBox',{},function() completed=completed+1 end)
local oldWorld = packets[#packets]
fire('OnGameStart')
LootSorter.callServer('saveBox',{},function() completed=completed+1 end)
local newWorld = packets[#packets]
reply(oldWorld,'ok'); assert(completed==0, 'reply from a previous world reached the new request')
reply(newWorld,'ok'); assert(completed==1)
sendClientCommand=function() error('fixture send failed') end
LootSorter.callServer('saveBox',{},function(verdict) assert(verdict==nil); timedOut=timedOut+1 end)
clock=40000; fire('OnTick')
assert(timedOut==2, 'failed send left its callback unresolved or retried the write')
print('Quartermaster RPC: SP/Host dispatch, selected player, payload ownership, correlation and timeout lifecycle passed.')
