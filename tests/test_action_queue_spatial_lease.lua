assert(NativeActionRoot,'spatial lease requires --game or --native-action-root')
local sourceRead=NativeReadText or function(path)
    local file=assert(io.open(path));local text=file:read('*a');file:close();return text
end
local function fresh(corrupt)
    local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
    local sourceHook
    getFilenameOfClosure=function(callback)
        if sourceHook then sourceHook()end
        if NativeFilenameOfClosure then return NativeFilenameOfClosure(callback)end
        return debug.getinfo(callback,'S').source:gsub('^@','')
    end
    local reads=0
    getGameFilesInput=function(path)
        reads=reads+1
        local text=sourceRead(NativeActionRoot..'/'..path:gsub('^media/lua/','')):gsub('\r','')
        if corrupt and path==corrupt then text=text..'-- changed native source\n'end
        local position=1
        return {close=function()end,readLine=function()
            if position>#text then return end
            local boundary=text:find('\n',position,true)or #text+1
            local line=text:sub(position,boundary-1);position=boundary+1;return line
        end}
    end
    isServer=function()return false end
    local operations=f.project('ActionQueueOperations')
    luautils={}
    local text=sourceRead(NativeActionRoot..'/shared/luautils.lua'):gsub('\r','')
    local helpers={assert(text:match('(function luautils.walkAdj%(.-\nend)')),
        assert(text:match('(luautils.getCorrectSquareForWall = function.-\nend)'))}
    assert(loadstring(table.concat(helpers,'\n'),'@'..NativeActionRoot..'/shared/luautils.lua'))()
    local approach=f.project('ActionQueueApproach');assert(approach.install())
    local actor=f.player;actor.class='IsoPlayer';actor.isLocalPlayer=function()return true end
    actor.isDraggingCorpse=function()return false end
    local function forbidden()error('spatial observation executed a world/route callback')end
    actor.getX,actor.getY,actor.getSquare,actor.getCurrentSquare=forbidden,forbidden,forbidden,forbidden
    local queue=f.queue(f.action(ISReadABook,{}))
    local target={getX=forbidden,getY=forbidden,getZ=forbidden}
    local function command(exclusions,keep)
        local n=#queue.queue
        operations.run(function()assert(luautils.walkAdj(actor,target,keep or false,exclusions))end)
        assert(#queue.queue==n+1,'fixture must create a genuine deferred command')
        return queue.queue[n+1]
    end
    return {f=f,approach=approach,operations=operations,actor=actor,target=target,queue=queue,command=command,
        reads=function()return reads end,setHook=function(callback)sourceHook=callback end}
end
local function record(action)return action.toolkitQueueCommand end
local function request(action)return record(action).snapshot end
local f=fresh()
-- Modules can add unrelated library helpers after Toolkit loads. They must
-- neither revoke future queries nor run during source preparation.
local helperCalls=0
local function unrelated()helperCalls=helperCalls+1;error('unrelated library helper executed')end
math.SpatialLeaseUnrelated,table.SpatialLeaseUnrelated,string.SpatialLeaseUnrelated=unrelated,unrelated,unrelated
local action=f.command()
local watch,description=f.approach.prepareSpatialLease(action)
assert(type(watch)=='function'and description.version==1 and description.kind=='deferred-spatial')
assert(description.actor==f.actor and description.targetSquare==f.target and description.invalidates=='all-resources')
assert(description.routing=='native'and description.expansion=='native'and description.outcome=='native')
local count=0;for _ in pairs(description)do count=count+1 end
assert(count==8 and description.complete==nil and description.resources==nil and description.capacity==nil)
local reads=f.reads();assert(reads==3,'first lease must pin all three real native files')
f.setHook(function()error('final watcher called the source metadata accessor')end)
assert(watch()and not watch(),'lease must be callback-free and one-use')
assert(helperCalls==0,'unrelated helpers ran during source preparation or final watch')
f.setHook(nil)
assert(f.reads()==reads,'watcher performed source IO')
assert(f.approach.prepareSpatialLease(action),'fresh queries must not reuse spent leases')
assert(f.reads()==reads,'loaded native source pins should be reused')
-- Every mutation is tested against a successful control from that exact source
-- preparation; denied preparation alone cannot establish final-read revocation.
local mutations={
    function(a,d)a.started=true end,
    function(a,d)a.action={}end,
    function(a,d)a.toolkitQueueOperation.toolkitStarted=true end,
    function(a,d)request(a).args[2]={}end,
    function(a,d)request(a).args[4][1]={}end,
    function(a,d)request(a).guards[1].callback=function()error('changed guard executed')end end,
    function(a,d)record(a).ready=function()error('ready executed')end end,
    function(a,d)d.invalidates='position-only'end,
    function(a,d)setmetatable(record(a),{__index=function()error('changed request metatable executed')end})end,
}
for _,mutate in ipairs(mutations)do
    local value=f.command({f.target})
    local control=assert(f.approach.prepareSpatialLease(value));assert(control())
    local lease,descriptor=f.approach.prepareSpatialLease(value);assert(lease)
    mutate(value,descriptor)
    assert(not lease(),'changed captured intent must revoke the final lease')
end
for _,name in ipairs({'getCorrectSquareForWall','walkAdj'})do
    local value=f.command();local lease=assert(f.approach.prepareSpatialLease(value))
    local original=luautils[name];luautils[name]=function()error('changed helper executed')end
    assert(not lease(),'changed routing helper must revoke without executing it');luautils[name]=original
end
for _,name in ipairs({'getFilenameOfClosure','pairs','toolkitLuaMetatableMatches'})do
    local value=f.command();local lease=assert(f.approach.prepareSpatialLease(value))
    local original=_G[name];_G[name]=function()error('changed primitive executed')end
    local valid=lease();_G[name]=original
    assert(not valid,'changed primitive/source dependency must revoke without executing it')
end
-- Required library primitives stay pinned from module load. Reject their
-- replacements before calling metadata/source readers or the foreign helper.
for _,name in ipairs({'byte','sub'})do
    local value=f.command();local calls=0;local original=string[name]
    string[name]=function()calls=calls+1;error('changed source primitive executed')end
    local lease=f.approach.prepareSpatialLease(value)
    string[name]=original
    assert(not lease and calls==0,'changed source primitive ran before rejection')
end
-- Unsupported requests remain unknown; never turn them into an empty effect.
for _,mutate in ipairs({
    function(a)record(a).ready=function()error('ready executed')end end,
    function(a)a.onFailFunc=function()error('onFail executed')end end,
    function(a)a.started=true end,
    function(a)a.isValid=function()error('native validity executed')end end,
    function(a)request(a).args.n=5;request(a).args[5]=true end,
    function(a)request(a).cursorKind='FishingNet'end,
    function(a)request(a).args[4]={[2]=f.target}end,
    function(a)request(a).args[4]={};for i=1,33 do request(a).args[4][i]=f.target end end,
    function(a)request(a).guards[3]=request(a).guards[2]end,
})do
    local value=f.command();mutate(value)
    assert(not f.approach.prepareSpatialLease(value),'unsupported shape acquired deferred source authority')
end
-- Opaque identity never invokes __eq, including before the final watcher.
-- These callbacks return true to catch both execution and falsely accepted
-- identity; target objects remain opaque and are never compared by behavior.
do
    local calls=0
    local function hostileEquality()calls=calls+1;return true end
    local value=f.command();local actorMeta=getmetatable(f.actor)
    local hostile={__eq=hostileEquality}
    setmetatable(f.actor,hostile)
    request(value).args[1]=setmetatable({},hostile)
    assert(not f.approach.prepareSpatialLease(value)and calls==0,'actor comparison invoked __eq')
    setmetatable(f.actor,actorMeta)
    value=f.command();local target=setmetatable({},hostile)
    request(value).args[2]=target
    local lease,descriptor=f.approach.prepareSpatialLease(value)
    assert(lease and rawequal(descriptor.targetSquare,target)and calls==0)
    assert(lease()and calls==0,'opaque target invoked __eq')
    lease=assert(f.approach.prepareSpatialLease(value))
    request(value).args[2]=setmetatable({},hostile)
    assert(not lease()and calls==0,'target revocation invoked __eq')
    value=f.command()
    local class=ISQueueActionsAction;local parent=getmetatable(class)
    local previous=parent.__eq;parent.__eq=hostileEquality
    setmetatable(value,setmetatable({},parent))
    assert(not f.approach.prepareSpatialLease(value)and calls==0,'class-parent identity invoked __eq')
    setmetatable(value,class);parent.__eq=previous
    local classEquality=class.__eq;class.__eq=hostileEquality
    record(value).owner=setmetatable({},class)
    assert(not f.approach.prepareSpatialLease(value)and calls==0,'record owner invoked __eq')
    class.__eq=classEquality
    value=f.command();record(value).marker=setmetatable({},hostile)
    assert(not f.approach.prepareSpatialLease(value)and calls==0,'private marker invoked __eq')
    value=f.command();local originalRequest=request(value)
    record(value).snapshot=setmetatable({}, {__metatable=nil,__index=function(_,key)
        calls=calls+1;return originalRequest[key]
    end})
    assert(not f.approach.prepareSpatialLease(value)and calls==0,'private request invoked inherited lookup')
end
-- Reject both an already changed lookup chain and a late lookup mutation,
-- without executing the foreign inherited callback in either phase.
do
    local value=f.command();local parent=getmetatable(ISQueueActionsAction)
    local original=parent.__index
    local lease=assert(f.approach.prepareSpatialLease(value))
    parent.__index=function()error('foreign inherited callback executed')end
    assert(not lease())
    assert(not f.approach.prepareSpatialLease(value))
    parent.__index=original
end
-- The maximum exclusion count is supported, and neither actor nor target is
-- sampled: native routing owns those facts when the command eventually starts.
local exclusions={};for i=1,32 do exclusions[i]=f.target end
assert(f.approach.prepareSpatialLease(f.command(exclusions)))
-- Metadata callbacks cannot publish a lease for an input changed mid-proof.
local reentrant=fresh();local value=reentrant.command()
reentrant.setHook(function()request(value).args[2]={}end)
assert(not reentrant.approach.prepareSpatialLease(value),'source-reader mutation escaped the prepare-time watcher')
reentrant.setHook(nil)
for _,path in ipairs({'media/lua/shared/luautils.lua',
    'media/lua/client/TimedActions/ISQueueActionsAction.lua','media/lua/shared/TimedActions/ISBaseTimedAction.lua'})do
    local changed=fresh(path)
    assert(not changed.approach.prepareSpatialLease(changed.command()),'changed native file borrowed source authority')
end
math.SpatialLeaseUnrelated,table.SpatialLeaseUnrelated,string.SpatialLeaseUnrelated=nil,nil,nil
assert(helperCalls==0)
-- Device ownership retains immutable route intent across allocation and paid
-- progress. Unlike the one-use edit lease, this is not a no-movement claim.
do
    local g=fresh();local a=g.command(nil,true)
    local watch,square=g.approach.prepareDevicePosition(a)
    assert(watch and square==g.target and watch()and watch())
    a.action={};a.started=true;a.toolkitQueueOperation.toolkitStarted=true
    a._isAddingActions=true;a._numAddedActions=1
    g.setHook(function()error('position watch read metadata after allocation')end)
    assert(watch(),'paid preparation lost immutable source ownership')
    g.setHook(nil)
    assert(not g.approach.prepareDevicePosition(a),'cannot mint new authority after allocation')
end
for _,mutate in ipairs({
    function(a)request(a).args[2]={}end,
    function(a)request(a).args[3]=false end,
    function(a)record(a).args[1]={}end,
    function(a)a.toolkitQueueOperation={}end,
    function(a)a.waitToStart=function()error('foreign callback executed')end end,
    function(a)a.onFailFunc=function()error('foreign failure executed')end end,
    function(a)request(a).binding.spec.arrays[1]=3 end,
})do
    local g=fresh();local a=g.command(nil,true)
    local watch=assert(g.approach.prepareDevicePosition(a));assert(watch())
    mutate(a);assert(not watch(),'device route source changed after capture')
end
do
    local g=fresh();assert(not g.approach.prepareDevicePosition(g.command()))
end
-- Execute the real captured native helper only to produce its real child.
-- Geometry is an explicit double; no child or action callback is substituted.
local function nativeChild()
    local g=fresh();g.f.native('client/TimedActions/WalkToTimedAction.lua')
    local parent=g.command(nil,true)
    local sourceWatch=assert(g.approach.prepareDevicePosition(parent))
    local square=g.target
    square.getX=function()return 8 end;square.getY=function()return 0 end;square.getZ=function()return 0 end
    square.has=function()return false end
    g.actor.getX=function()return .5 end;g.actor.getY=function()return .5 end
    g.actor.getSquare=function()return square end;g.actor.getCurrentSquare=g.actor.getSquare
    getCell=function()return{getGridSquare=function(_,x,y,z)if x==8 and y==0 and z==0 then return square end end}end
    IsoFlagType={collideW={},collideN={}}
    AdjacentFreeTileFinder={Find=function(target,actor)assert(target==square and actor==g.actor);return square end}
    local child,childWatch
    PZSurvivorToolkit.ActionQueueDeviceTargets={enqueued=function()end,positionEnqueued=function(action,owner)
        assert(owner==parent)
        child=action
        local target;childWatch,target=g.approach.prepareDevicePosition(action,owner)
        assert(childWatch and target==square,'real native child lost its source-owned parent')
    end}
    g.queue.queue={parent};g.queue.current=parent
    g.operations.runWith(parent.toolkitQueueOperation,function()
        parent:beginAddingActions()
        parent.addActionsFunction(g.actor,unpack(parent.args))
        parent:endAddingActions()
    end)
    assert(child and getmetatable(child)==ISWalkToTimedAction and g.queue.queue[2]==child)
    assert(sourceWatch()and childWatch(),'native expansion revoked immutable intent')
    return g,parent,child,childWatch
end
do
    local g,parent,child,watch=nativeChild()
    child.action={};child.started=true;child.pathIndex=8;child.result={}
    parent.toolkitQueueOperation.toolkitStarted=true
    g.setHook(function()error('paid child source watcher read metadata')end)
    assert(watch()and watch(),'paid child progress revoked immutable source intent')
    g.setHook(nil)
    assert(not g.approach.prepareDevicePosition(child,parent),'cannot mint child proof outside native expansion')
end
for _,mutate in ipairs({
    function(parent,child)child.location={}end,
    function(parent,child)child.additionalTest=function()error('test callback executed')end end,
    function(parent,child)child.perform=function()error('perform executed')end end,
    function(parent,child)record(parent).args[1]={}end,
    function(parent,child)request(parent).args[2]={}end,
})do
    local g,parent,child,watch=nativeChild();mutate(parent,child)
    assert(not watch(),'changed native child source retained device authority')
end
print('Deferred spatial lease: real owned walkAdj, bounded immutable intent, callback-free one-use watcher, source revocation and native gaps passed.')
if TestCoverage then TestCoverage('source-contract','passed')end
