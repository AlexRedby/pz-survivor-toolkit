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
inlinePages[1].containers[1].entries.entry1.ingredient=false
inlinePages[1].containers[1].entries.entry1.fluidState='none'
inlinePages[1].containers[1].entries.entry1.tagDelta={ingredient='add'}
inlinePages[2].containers[1].entries.entry2.ingredient=true
inlinePages[2].containers[1].entries.entry2.fluidState='alcoholic'
local ready=0
Client.open(1,function(payload,status)
    if status=='ready'then
        ready=ready+1
        local entries=payload.containers['1,2,0/0/0'].entries
        assert(entries.entry2.n==2 and entries.entry2.ingredient==true)
        assert(entries.entry1.ingredient==false and entries.entry1.tagDelta.ingredient=='add',
            'client page merge lost captured false ingredient state or manual assignments')
        assert(entries.entry1.fluidState=='none' and entries.entry2.fluidState=='alcoholic',
            'client page merge lost captured fluid contents')
    end
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
-- Real View aggregation/sorts and location references survive multi-page freshness updates.
setup(true)
local View = dofile(root .. 'PZSurvivorToolkit/ManifestView.lua')
local described, rebuilt = 0, 0
local view = View.new(function(entry)
    described = described + 1; return entry.ft, '', {}
end, {label=function(id)return id end})
Client.open(0,function(payload,status)
    if status == 'ready' then
        if view:setPayload(payload) then rebuilt = rebuilt + 1 end
        view:select('',nil,'count',false)
    end
end)
reply(packets[#packets],'ok',{schema=2,revision=20,containers={
    {id='a',sampledAt=100,entries={key={key='key',ft='Base.A',n=1}}},
    {id='b',sampledAt=110,entries={key={key='key',ft='Base.A',n=2}}}}})
local cached = Client.getState(0).payload
local rows, order, origin = view.rows, view.sorts['count:desc'], cached.containers.a
assert(rebuilt==1 and described==1)
Client.refresh(0)
reply(packets[#packets],'ok',{schema=2,revision=20,unchanged=true,cursor=77,samples={a=120}})
assert(cached.containers.a.sampledAt==100 and Client.getState(0).status=='loading', 'partial freshness leaked')
fire('OnTick')
assert(packets[#packets].args.cursor==77)
reply(packets[#packets],'ok',{schema=2,revision=20,unchanged=true,samples={b=130}})
assert(Client.getState(0).payload==cached and cached.containers.a==origin)
assert(origin.sampledAt==120 and cached.containers.b.sampledAt==130)
assert(view.rows==rows and view.sorts['count:desc']==order and rebuilt==1 and described==1,
    'freshness invalidated aggregation, localization or sort caches')
local retainedOrigin
for _, loc in ipairs(rows[1].locations) do if loc.id=='a' then retainedOrigin=loc.container end end
assert(retainedOrigin==origin and retainedOrigin.sampledAt==120, 'visible location kept a stale sample')
-- A mutation between freshness pages retries full data on the next tick without a false error.
Client.refresh(0)
reply(packets[#packets],'ok',{schema=2,revision=20,unchanged=true,cursor=88,samples={a=200}})
fire('OnTick'); reply(packets[#packets],'stale')
assert(Client.getState(0).status=='loading' and origin.sampledAt==120)
fire('OnTick')
assert(not packets[#packets].args.revision and not packets[#packets].args.cursor, 'stale freshness did not request full data')
reply(packets[#packets],'ok',{schema=2,revision=21,containers={
    {id='a',sampledAt=230,entries={key={key='key',ft='Base.A',n=5}}}}})
assert(Client.getState(0).status=='ready' and Client.getState(0).payload~=cached)
assert(rebuilt==2 and described==2 and view.rows[1].n==5 and #view.rows[1].locations==1)
cached=Client.getState(0).payload
-- Timeout and closure discard staged timestamps and preserve the last complete cached sample.
Client.refresh(0)
reply(packets[#packets],'ok',{schema=2,revision=21,unchanged=true,cursor=99,samples={a=300}})
fire('OnTick'); clock=clock+16000; fire('OnTick')
assert(Client.getState(0).status=='error' and cached.containers.a.sampledAt==230)
Client.refresh(0)
reply(packets[#packets],'ok',{schema=2,revision=21,unchanged=true,cursor=101,samples={a=400}})
local count=#packets
Client.close(0); fire('OnTick')
assert(#packets==count and cached.containers.a.sampledAt==230)
Client.open(0)
reply(packets[#packets],'ok',{schema=2,revision=21,unchanged=true,samples={a=500}})
assert(cached.containers.a.sampledAt==500 and Client.getState(0).payload==cached)
Client.refresh(0)
reply(packets[#packets],'ok',{schema=2,revision=999,unchanged=true,samples={a=600}})
assert(Client.getState(0).status=='error' and cached.containers.a.sampledAt==500)
Client.refresh(0)
reply(packets[#packets],'ok',{schema=2,revision=21,unchanged=true,samples={a='bad'}})
assert(Client.getState(0).status=='error' and cached.containers.a.sampledAt==500)
setup(true)
Client.open(0)
reply(packets[#packets],'ok',{schema=2,revision=0,unchanged=true,samples={}})
assert(Client.getState(0).status=='error' and not Client.getState(0).payload, 'freshness without cached data was accepted')
print('Manifest client: SP/MP pagination, freshness cache identity, stale restart, timeout, close/reopen and world lifecycle passed.')
