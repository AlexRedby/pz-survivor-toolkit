assert(NativeActionRoot,'spatial edit lease requires --game or --native-action-root')
local sourceRead=NativeReadText or function(path)
    local file=assert(io.open(path));local text=file:read('*a');file:close();return text
end
local function fresh(corrupt,missing)
    local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
    local sourceHook
    getFilenameOfClosure=function(callback)
        if sourceHook then sourceHook()end
        if NativeFilenameOfClosure then return NativeFilenameOfClosure(callback)end
        return debug.getinfo(callback,'S').source:gsub('^@','')
    end
    getGameFilesInput=function(path)
        local text=sourceRead(NativeActionRoot..'/'..path:gsub('^media/lua/','')):gsub('\r','')
        if corrupt and path==corrupt then text=text..'-- changed native source\n'end
        local position=1
        return {close=function()end,readLine=function()
            if position>#text then return end
            local boundary=text:find('\n',position,true)or #text+1
            local line=text:sub(position,boundary-1);position=boundary+1;return line
        end}
    end
    local actor=f.player;actor.class='IsoPlayer'
    actor.isLocalPlayer=function()return true end;actor.isDraggingCorpse=function()return false end
    local function noGetter()error('spatial inspection invoked a Lua engine getter')end
    actor.getX,actor.getY,actor.getSquare,actor.getCurrentSquare=noGetter,noGetter,noGetter,noGetter
    local target={class='IsoGridSquare',getX=noGetter,getY=noGetter,getZ=noGetter,has=noGetter,canReachTo=noGetter}
    local state={near=true,localPlayer=true,dead=false,loaded=true,reachable=true,server=false}
    local nativeCalls,bridgeHook=0
    local helper,checker
    -- Explicit Java-bridge seam only. Actual native geometry, exact reflected
    -- Method/frame certificates and no-callback guarantees run in QueueSpatialFactsChecks.
    helper=function(who,square,excluded,bound)
        nativeCalls=nativeCalls+1
        if bridgeHook then bridgeHook()end
        if who~=actor or square~=target or actor.class~='IsoPlayer'or target.class~='IsoGridSquare'
            or not state.near or not state.localPlayer or state.dead or not state.loaded or not state.reachable or state.server then return false end
        for _,value in ipairs(excluded or{})do if rawequal(value,target)then return false end end
        if bound and (bound.square~=target or bound.gone)then return false end
        return true
    end
    checker=function(callback)return rawequal(callback,helper)and rawequal(toolkitQueueSpatialNoMovement,helper)
        and rawequal(toolkitQueueSpatialApiMatches,checker)end
    toolkitQueueSpatialNoMovement,toolkitQueueSpatialApiMatches=helper,checker
    getClassSimpleName=function(callback)
        if rawequal(callback,helper)or rawequal(callback,checker)then return 'LuaJavaInvoker'end
        return 'LuaClosure'
    end
    if missing then _G[missing]=nil end
    isServer=function()return false end
    local operations=f.project('ActionQueueOperations')
    luautils={}
    local text=sourceRead(NativeActionRoot..'/shared/luautils.lua'):gsub('\r','')
    local helpers={assert(text:match('(function luautils.walkAdj%(.-\nend)')),
        assert(text:match('(luautils.getCorrectSquareForWall = function.-\nend)'))}
    assert(loadstring(table.concat(helpers,'\n'),'@'..NativeActionRoot..'/shared/luautils.lua'))()
    local nativeWalk,nativeCorrection=luautils.walkAdj,luautils.getCorrectSquareForWall
    local approach=f.project('ActionQueueApproach');assert(approach.install())
    local queue=f.queue(f.action(ISReadABook,{}))
    local function command(keep,exclusions)
        local count=#queue.queue
        operations.run(function()assert(luautils.walkAdj(actor,target,keep,exclusions))end)
        assert(#queue.queue==count+1,'fixture must enqueue the source-owned dispatcher')
        return queue.queue[count+1]
    end
    return {f=f,approach=approach,actor=actor,target=target,state=state,queue=queue,command=command,
        nativeWalk=nativeWalk,nativeCorrection=nativeCorrection,helper=helper,checker=checker,
        nativeCalls=function()return nativeCalls end,setBridgeHook=function(value)bridgeHook=value end,
        setSourceHook=function(value)sourceHook=value end}
end
local function request(action)return action.toolkitQueueCommand.snapshot end
local function forbiddenExecution(f,action,callback)
    local forbidden={[f.nativeWalk]=true,[f.nativeCorrection]=true,[action.toolkitQueueCommand.callback]=true,
        [ISQueueActionsAction.new]=true,[ISQueueActionsAction.isValid]=true,[ISBaseTimedAction.new]=true}
    local calls=0
    debug.sethook(function(event)
        if event=='call'and forbidden[debug.getinfo(2,'f').func]then calls=calls+1;error('edit lease executed native routing/action')end
    end,'c')
    local ok,result=pcall(callback)
    debug.sethook()
    assert(ok,result);assert(calls==0,'native routing/action was invoked and swallowed')
    return result
end
local f=fresh();local action=f.command(true)
local check,edit=f.approach.prepareSpatialEditLease(action)
assert(check and edit.version==1 and edit.complete==true and edit.capacity=='unchanged'and next(edit.resources)==nil)
assert(f.nativeCalls()==1,'preparation must establish initial native no-movement eligibility')
assert(forbiddenExecution(f,action,check)and not check(),'certified native no-movement branch must grant a one-use empty edit')
assert(f.nativeCalls()==2 and #f.queue.queue==2 and f.queue.current~=action and not action.started and not action.action)
do
    local g=fresh();local value=g.command(true);g.state.near=false
    assert(not g.approach.prepareSpatialEditLease(value),'initially distant requests must retain the ordinary legacy policy')
    assert(g.nativeCalls()==1,'initial eligibility must use the certified callback-free native observation')
    g.state.near=true
    local final=assert(g.approach.prepareSpatialEditLease(value));g.state.near=false
    assert(not final(),'initial eligibility must never replace the fresh final geometry gate')
end
for _,field in ipairs({'near','localPlayer','loaded','reachable'})do
    local g=fresh();local value=g.command(true);local check=assert(g.approach.prepareSpatialEditLease(value))
    g.state[field]=false;assert(not check(),'fresh '..field..' fact was not consulted at final consumption')
end
for _,field in ipairs({'dead','server'})do
    local g=fresh();local value=g.command(true);local check=assert(g.approach.prepareSpatialEditLease(value))
    g.state[field]=true;assert(not check(),'fresh '..field..' fact was not consulted at final consumption')
end
for _,keep in ipairs({false,'true',1})do
    local g=fresh();assert(not g.approach.prepareSpatialEditLease(g.command(keep)))
end
for _,name in ipairs({'toolkitQueueSpatialNoMovement','toolkitQueueSpatialApiMatches','getClassSimpleName'})do
    local g=fresh(nil,name)
    assert(not g.approach.prepareSpatialEditLease(g.command(true)),'missing native primitive granted edit authority')
end
do
    local g=fresh();assert(not g.approach.prepareSpatialEditLease(g.command(nil)))
    assert(not g.approach.prepareSpatialEditLease(g.command(true,{g.target})))
    local value=g.command(true);local bound={square=g.target}
    assert(assert(g.approach.prepareSpatialEditLease(value,bound))())
    local check=assert(g.approach.prepareSpatialEditLease(value,bound));bound.square={}
    assert(not check(),'moved effect target retained native-bound authority')
end
for _,mutate in ipairs({
    function(g,a,e)request(a).args[2]={}end,
    function(g,a,e)request(a).args[3]=false end,
    function(g,a,e)request(a).args[4][1]=g.target end,
    function(g,a,e)a.toolkitQueueOperation.toolkitStarted=true end,
    function(g,a,e)a.toolkitQueueCommand.ready=function()error('ready executed')end end,
    function(g,a,e)e.resources[1]={}end,
    function(g,a,e)toolkitQueueSpatialNoMovement=function()error('foreign helper executed')end end,
    function(g,a,e)toolkitQueueSpatialApiMatches=function()error('foreign checker executed')end end,
    function(g,a,e)getClassSimpleName=function()error('foreign class accessor executed')end end,
})do
    local g=fresh();local value=g.command(true,{{}})
    assert(assert(g.approach.prepareSpatialEditLease(value))())
    local lease,descriptor=g.approach.prepareSpatialEditLease(value)
    mutate(g,value,descriptor);assert(not forbiddenExecution(g,value,lease),'late dependency mutation escaped the lease')
end
do
    local g=fresh();local value=g.command(true)
    g.setSourceHook(function()request(value).args[2]={}end)
    assert(not g.approach.prepareSpatialEditLease(value),'metadata mutation escaped source/request capture')
end
do
    local g=fresh();local value=g.command(true);local lease=assert(g.approach.prepareSpatialEditLease(value))
    g.setBridgeHook(function()request(value).args[2]={}end)
    assert(not lease(),'even a modeled native bridge reentry must fail the final immutable-intent check')
end
do
    local g=fresh();local value=g.command(true);local calls=0
    toolkitQueueSpatialApiMatches=function()calls=calls+1;return true end
    assert(not g.approach.prepareSpatialEditLease(value)and calls==0,'replaced bootstrap checker was invoked')
end
for _,path in ipairs({'media/lua/shared/luautils.lua',
    'media/lua/client/TimedActions/ISQueueActionsAction.lua','media/lua/shared/TimedActions/ISBaseTimedAction.lua'})do
    local g=fresh(path)
    assert(not g.approach.prepareSpatialEditLease(g.command(true)),'changed native source borrowed no-movement authority')
end
print('Spatial edit lease: immutable one-use source intent, certified callback-free final native observation, unavailable bridges and reentrant revocation passed.')
if TestCoverage then TestCoverage('source-contract','passed')end
