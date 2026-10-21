local root=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/'
local clock,packets,inlinePages,client,Client,Model
local primary,secondary={},{}
local function fire(name,...)
    for _,fn in ipairs({unpack(Events[name].handlers)}) do fn(...) end
end
local function setup(remote)
    clock,packets,inlinePages,client=1000,{},{},remote
    PZSurvivorToolkit={}
    LootSorter={RPC_TIMEOUT_MS=15000,RPC_SWEEP_MS=5000,DBG=function()end}
    isClient=function()return client end
    getTimestampMs=function()return clock end
    getSpecificPlayer=function(n)return n==1 and secondary or primary end
    Events={}
    for _,name in ipairs({'OnTick','OnGameStart','OnServerCommand','OnClientCommand'})do
        local e={handlers={}}
        e.Add=function(fn)e.handlers[#e.handlers+1]=fn end
        e.Remove=function(fn)for i=#e.handlers,1,-1 do if e.handlers[i]==fn then table.remove(e.handlers,i)end end end
        Events[name]=e
    end
    sendClientCommand=function(player,module,command,args)
        assert(module=='Quartermaster' and command=='manifestPage')
        packets[#packets+1]={player=player,args=args}
    end
    local cache={}
    require=function(name)
        if cache[name]then return cache[name]end
        local module
        if name=='PZSurvivorToolkit/ItemTags' then module={}
        elseif name=='PZSurvivorToolkit/ManifestAuthority' then
            LootSorter.serverFn('manifestPage',function(player,args)
                assert(player==secondary)
                return 'ok',table.remove(inlinePages,1)
            end)
            module={}
        else module=dofile(root..name..'.lua')end
        cache[name]=module or true
        return module
    end
    Client=require 'PZSurvivorToolkit/ManifestClient'
    Model=require 'PZSurvivorToolkit/ManifestModel'
end
local function page(revision,cursor,n)
    return {schema=2,revision=revision,cursor=cursor,containers={{id='1,2,0/0/0',entries={
        ['entry'..n]={key='entry'..n,ft='Base.A',n=n}}}}}
end
local function reply(packet,verdict,detail)
    fire('OnServerCommand','Quartermaster','rpcResult',{rpcToken=packet.args.rpcToken,verdict=verdict,detail=detail})
end
-- Inline SP uses the same paginated API without recursion, premature callback or partial publish.
setup(false)
inlinePages={page(4,7,1),page(4,nil,2)}
local ready=0
Client.open(1,function(payload,status)
    if status=='ready'then ready=ready+1;assert(payload.containers['1,2,0/0/0'].entries.entry2.n==2)end
end)
assert(Client.getState(1).status=='loading' and not Client.getState(1).payload and ready==0)
fire('OnTick')
assert(Client.getState(1).status=='ready' and ready==1)
local old=Client.getState(1).payload
inlinePages={{schema=2,revision=4,unchanged=true}}
local completed=0
Client.refresh(1,function(payload,status)assert(payload==old and status=='ready');completed=completed+1 end)
assert(completed==1,'inline callback was not completed during SP call')
Client.close(1)
clock=clock+5000;fire('OnTick')
assert(#inlinePages==0 and Client.getState(1).status=='ready','closed UI continued polling')
-- MP uses authenticated selected player, merges pages atomically and coalesces parallel refreshes.
setup(true)
Client.open(1,function()end)
assert(#packets==1 and packets[1].player==secondary and Client.getState(1).status=='loading')
Client.refresh(1,function(payload,status)assert(status=='ready');completed=completed+1 end)
assert(#packets==1)
reply(packets[1],'ok',page(9,100,1))
assert(not Client.getState(1).payload,'first remote page leaked into UI')
fire('OnTick')
assert(#packets==2 and packets[2].args.cursor==100)
reply(packets[2],'ok',page(9,nil,2))
assert(Client.getState(1).status=='ready' and Client.getState(1).payload.revision==9)
old=Client.getState(1).payload
clock=clock+2500;fire('OnTick')
assert(#packets==3 and packets[3].args.revision==9)
reply(packets[3],'ok',{schema=2,revision=9,unchanged=true})
assert(Client.getState(1).payload==old,'unchanged reply invalidated cached UI data')
-- Timeout retains last-known ledger and makes error visible. Late replies cannot revive old refreshes.
Client.refresh(1)
local lost=packets[#packets]
clock=clock+16000;fire('OnTick')
assert(Client.getState(1).status=='error' and Client.getState(1).payload==old)
reply(lost,'ok',page(10,nil,3))
assert(Client.getState(1).payload==old)
Client.refresh(1)
local previousWorld=packets[#packets]
fire('OnGameStart')
assert(Client.getState(1).status=='idle' and not Client.getState(1).payload)
reply(previousWorld,'ok',page(11,nil,4))
assert(not Client.getState(1).payload)
Client.open(1,function()end)
reply(packets[#packets],'denied')
assert(Client.getState(1).status=='error' and Client.getState(1).error=='denied')
Client.close(1)
local before=#packets
clock=clock+5000;fire('OnTick')
assert(#packets==before)
-- Closing the last UI while a response is outstanding suppresses all further automatic pages.
Client.open(1,function()end)
local closedPacket=packets[#packets]
Client.close(1)
local closedCount=#packets
reply(closedPacket,'ok',page(12,999,5))
clock=clock+5000;fire('OnTick')
assert(#packets==closedCount and Client.getState(1).status=='idle')
-- An explicitly requested callback remains entitled to finish even after its window closes.
local manual=0
Client.open(1,function()end)
local manualPacket=packets[#packets]
Client.refresh(1,function(payload,status)if status=='ready'then manual=manual+1 end end)
Client.close(1)
reply(manualPacket,'ok',page(13,1000,6))
fire('OnTick')
assert(#packets==closedCount+2)
reply(packets[#packets],'ok',page(13,nil,7))
assert(manual==1 and Client.getState(1).payload.revision==13)
-- A bad UI listener is diagnosed without preventing other listeners from receiving the ledger.
local originalPrint,logged,healthy=print,{},0
print=function(text)logged[#logged+1]=text end
Client.open(1,function()error('fixture broken UI listener')end)
Client.open(0,function()healthy=healthy+1 end)
print=originalPrint
assert(#logged>0 and logged[1]:find('[PZSurvivorToolkit] Manifest callback:',1,true) and healthy>0)
print('Manifest client: SP inline, MP pagination, selected player, polling, timeout and world lifecycle passed.')
