assert(NativeActionRoot,'spatial execution requires --game or --native-action-root')
-- Execute stock routing/walking and the real common queue/settlement bridges.
-- Java scheduling, grid identity and path results are explicit test doubles;
-- this is not a live SP/Host qualification or a native return-earning proof.
local function read(path)
    if NativeReadText then return NativeReadText(NativeActionRoot..'/'..path):gsub('\r','')end
    local file=assert(io.open(NativeActionRoot..'/'..path));local value=file:read('*a');file:close()
    return value:gsub('\r','')
end
local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
local noop=function()end
getFilenameOfClosure=NativeFilenameOfClosure or function(callback)
    return debug.getinfo(callback,'S').source:gsub('^@','')
end
getGameFilesInput=function(path)
    local value=read(path:gsub('^media/lua/',''));local position=1
    return {close=noop,readLine=function()
        if position>#value then return end
        local boundary=value:find('\n',position,true)or #value+1
        local line=value:sub(position,boundary-1);position=boundary+1;return line
    end}
end
isServer,isClient=function()return false end,function()return false end
BehaviorResult={Failed='failed',Succeeded='succeeded',Working='working'}
IsoFlagType={collideW='west',collideN='north'}
DebugType={Action={warn=noop}}
ISLogSystem={logAction=noop}
getGameSpeed=function()return 1 end
local player=f.player
getSpecificPlayer=function()return player end
player.class='IsoPlayer'
instanceof=function(value,name)
    return type(value)=='table'and(value.class==name or name=='IsoGameCharacter'and value.class=='IsoPlayer')
end
local squares,routeCalls={},0
local function key(x,y,z)return x..':'..y..':'..z end
local function square(x,y)
    local value={x=x,y=y,z=0,getX=function(self)return self.x end,getY=function(self)return self.y end,
        getZ=function(self)return self.z end,has=function()return false end,
        canReachTo=function(self)return self.reachable~=false end}
    squares[key(x,y,0)]=value;return value
end
local origin,target=square(0,0),square(10,0)
getCell=function()return {getGridSquare=function(_,x,y,z)return squares[key(x,y,z)]end}end
AdjacentFreeTileFinder={Find=function(value)
    routeCalls=routeCalls+1
    if not value.blocked then return value end
end}
local path={cancel=noop,pathToLocation=noop,update=function()return player.pathResult end}
player.getPathFindBehavior2=function()return path end
player.setPath2,player.setTimedActionToRetrigger,player.setIsFarming=noop,noop,noop
player.isLocalPlayer=function()return true end
player.isDraggingCorpse,player.isFarming=function()return false end,function()return false end
player.getVehicle=function()end
player.pressedCancelAction=function()return player.cancel==true end
player.getCurrentSquare=function()return player.square end
player.getSquare=player.getCurrentSquare
player.getX=function()return player.square.x+.5 end
player.getY=function()return player.square.y+.5 end
player.inventory.getItemById=function()end
local active={}
player.getCharacterActions=function()return {contains=function(_,value)return active[value]==true end}end
player.StartAction=function(_,value)active[value]=true end
player.StopAllActionQueue=function()active={}end
LuaTimedActionNew={new=function(action)
    return {owner=action,started=false,isStarted=function(self)return self.started end,
        forceComplete=function(self)self.completing=true end,forceStop=function(self)self.stopping=true end,
        isForceComplete=function(self)return self.completing==true end,finished=function(self)return self.done==true end,
        hasStalled=function(self)return self.stalled==true end,setPathfinding=noop,setAllowedWhileDraggingCorpses=noop,
        setCurrentTime=noop,getJobDelta=function()return 0 end}
end}
f.native('client/TimedActions/WalkToTimedAction.lua')
luautils={}
local utilities=read('shared/luautils.lua')
for _,pattern in ipairs({'(function luautils.walkAdj%(.-\nend)','(function luautils.walk%(.-\nend)',
    '(luautils.getCorrectSquareForWall = function.-\nend)'})do
    assert(loadstring(assert(utilities:match(pattern)),'@'..NativeActionRoot..'/shared/luautils.lua'))()
end
local operations=f.project('ActionQueueOperations')
local spatialTick,spatialGameStart,spatialMenu
Events.OnTick.Add=function(callback)spatialTick=callback end
Events.OnGameStart.Add=function(callback)spatialGameStart=callback end
Events.OnMainMenuEnter={Add=function(callback)spatialMenu=callback end}
local approach=f.project('ActionQueueApproach');assert(approach.install())
assert(spatialTick and spatialGameStart and spatialMenu,'spatial maintenance lifecycle hooks missing')
Events.OnTick.Add,Events.OnGameStart.Add,Events.OnMainMenuEnter.Add=noop,noop,noop
PZSurvivorToolkit.ActionQueuePolicy={isCraftAction=function()return false end,
    live=function(queue)return queue.character==player and not player:isDead()end,
    stoppable=function()return false end,resumableWorld=function()return false end,
    adoptBegin=noop,replaceStop=noop,skipUnavailableHygiene=noop,hygieneUnavailable=function()return false end}
PZSurvivorToolkit.ActionQueueLabels={label=function(action)return action.Type end}
ISInventoryPaneContextMenu.getContainers=function()return {contains=function()return false end}end
f.project('ActionQueue')
local settlement=PZSurvivorToolkit.ActionQueueSettlement
local cleanup
settlement.register('spatial-execution-fixture-cleanup',{retain=function(action)return action==cleanup end})
local function leaf()
    local action=ISBaseTimedAction.new(ISBaseTimedAction,player);action.maxTime=1;return action
end
local function begin(action)
    assert(action.action,'shared begin must allocate native action')
    action.action.started=true;action:start()
end
local function complete(action)
    local java=action.action;java.completing=true
    local queue=ISTimedActionQueue.queues[player]
    local lifecycle=PZSurvivorToolkit.ActionQueueLifecycle
    assert(lifecycle.begin(action,'perform'))
    action:perform()
    lifecycle.finish(action,'perform',true)
    assert(queue.current==action,'native perform advanced before Java removal')
    assert(lifecycle.begin(action,'complete'));lifecycle.finish(action,'complete',true)
    assert(lifecycle.flush(queue)=='waiting','Java-active completion must remain deferred')
    active[java]=nil
    assert(lifecycle.flush(queue)=='completed','drained native completion did not advance')
    assert(lifecycle.flush(queue)==nil,'drained native completion replayed')
end
local function contains(queue,action)return queue:indexOf(action)~=-1 end
local function pending(near,withCleanup)
    active={};player.square=near and target or origin;player.pathResult=BehaviorResult.Working;player.cancel=false
    squares[key(target.x,target.y,0)]=target;target.blocked=nil;target.reachable=nil;cleanup=nil
    local predecessor,body,tail=leaf(),leaf(),leaf()
    local queue=ISTimedActionQueue:new(player);ISTimedActionQueue.add(predecessor)
    operations.run(function()
        assert(luautils.walkAdj(player,target,false))
        ISTimedActionQueue.add(body)
        if withCleanup then cleanup=leaf();ISTimedActionQueue.add(cleanup)end
    end)
    operations.run(function()ISTimedActionQueue.add(tail)end)
    local command=queue.queue[2]
    assert(approach.isAction(command)and command.toolkitQueueOperation==body.toolkitQueueOperation)
    begin(predecessor);complete(predecessor)
    assert(queue.current==command)
    return queue,command,body,tail
end
local function expand(command)begin(command);complete(command)end
local function rejected(queue,body,tail)
    assert(not contains(queue,body),'failed spatial phase admitted its dependent body')
    assert(contains(queue,tail),'failed spatial phase erased the independent tail')
    assert(not body.action,'rejected dependent body acquired native execution')
end

do
    local queue,command,body,tail=pending(true)
    local calls=routeCalls;expand(command)
    assert(queue.current==body and routeCalls==calls,'accepted nearby route must create no walking child')
    assert(contains(queue,tail),'no-movement route erased independent work')
end
do
    local queue,command,body,tail=pending(false)
    expand(command)
    local walking=queue.current
    assert(getmetatable(walking)==ISWalkToTimedAction and walking.location==target)
    assert(walking.toolkitQueueOperation==body.toolkitQueueOperation and not body.action)
    begin(walking);player.pathResult=BehaviorResult.Succeeded;player.square=target;walking:update()
    assert(walking.result==BehaviorResult.Succeeded and walking.action.completing)
    complete(walking)
    assert(queue.current==body and contains(queue,tail),'native successful child did not release its body')
end
do
    local queue,command,body,tail=pending(false)
    local calls=routeCalls;target.blocked=true;expand(command)
    rejected(queue,body,tail)
    assert(routeCalls==calls+1,'unavailable route was not resolved by the native helper')
end
-- Source-owned intent must remain available when native routing and its child
-- finish; source validation alone is not evidence that the target still exists.
for _,stage in ipairs({'before-route','after-route','replaced-square','unreachable','no-child'})do
    local queue,command,body,tail=pending(stage=='no-child',true)
    if stage=='before-route'then
        squares[key(target.x,target.y,0)]=nil;expand(command)
    elseif stage=='no-child'then
        begin(command);squares[key(target.x,target.y,0)]=nil;complete(command)
    else
        expand(command);local walking=queue.current;begin(walking)
        player.pathResult=BehaviorResult.Succeeded;player.square=target;walking:update()
        if stage=='replaced-square'then square(target.x,target.y)
        elseif stage=='unreachable'then target.reachable=false
        else squares[key(target.x,target.y,0)]=nil end
        complete(walking)
    end
    rejected(queue,body,tail)
    assert(contains(queue,cleanup)and queue.current==cleanup,'spatial failure lost registered required cleanup')
    assert(cleanup.toolkitQueueOperation~=body.toolkitQueueOperation and settlement.requiredStep(cleanup),
        'retained cleanup must acquire its independent required settlement ownership')
end
-- An admission observer can add stock walking's supported early-completion
-- predicate. That custom child is outside the exact outcome contract, so keep
-- its ordinary native continuation rather than canceling or granting a result.
do
    local queue,command,body,tail=pending(false)
    local add=ISTimedActionQueue.add;local calls=0
    ISTimedActionQueue.add=function(action)
        if action.Type=='ISWalkToTimedAction'then
            action.additionalTest=function()calls=calls+1;return true end
        end
        return add(action)
    end
    expand(command);ISTimedActionQueue.add=add
    local walking=queue.current
    assert(walking.Type=='ISWalkToTimedAction'and contains(queue,body)and contains(queue,tail)and not body.action,
        'unsupported native child canceled its existing dependent body')
    assert(approach.beforeComplete(queue,walking)==nil,'custom native child acquired a qualified spatial outcome')
    begin(walking);walking:update()
    assert(calls==1 and walking.result==BehaviorResult.Working and walking.action.completing,
        'custom early-completion predicate lost native execution')
    complete(walking)
    assert(queue.current==body and contains(queue,tail),'custom walking fallback lost its native continuation')
end
-- A stalled native walk and a child that disappears without any completion
-- result are explicit failures; absence never substitutes for arrival.
for _,cause in ipairs({'failed','stalled','missing','early-complete'})do
    local queue,command,body,tail=pending(false)
    expand(command);local walking=queue.current;begin(walking)
    if cause=='failed'then
        player.pathResult=BehaviorResult.Failed;walking:update();walking:stop()
        active[walking.action]=nil;queue:tick()
    elseif cause=='missing'then
        active[walking.action]=nil;queue:tick()
    elseif cause=='stalled'then
        walking.action.stalled=true;queue:tick()
        assert(queue.current==walking and not body.action,'still-active stalled action released dependent work')
        active[walking.action]=nil;queue:tick()
    else
        queue:onCompleted(walking)
        assert(queue.current==walking and not body.action,'early completion without native result released body')
        active[walking.action]=nil;queue:tick()
    end
    rejected(queue,body,tail)
end
-- Completion notifications for an old action must never advance a replacement
-- queue head, including replacement of the list inside the same queue object.
for _,replacement in ipairs({'queue','list'})do
    local queue,command,body,tail=pending(false);expand(command)
    local walking=queue.current;begin(walking)
    local other=leaf()
    local replacementQueue
    if replacement=='queue'then replacementQueue=f.queue(other)
    else queue.queue={other};queue.current=other;replacementQueue=queue end
    local list=replacementQueue.queue
    queue:onCompleted(walking)
    assert(replacementQueue.queue==list and replacementQueue.current==other and list[1]==other,
        'stale completion advanced replacement work')
    assert(not body.action and not other.action)
end
-- Final world facts can reenter Lua. Losing the exact queue/list/head while
-- observing reachability must not begin the replacement action or old body.
for _,replacement in ipairs({'queue','list'})do
    local queue,command,body,tail=pending(false);expand(command)
    local walking=queue.current;begin(walking)
    player.pathResult=BehaviorResult.Succeeded;player.square=target;walking:update()
    local reach=target.canReachTo
    local other=leaf();local replacementQueue
    target.canReachTo=function()
        if replacement=='queue'then replacementQueue=f.queue(other)
        else queue.queue={other};queue.current=other;replacementQueue=queue end
        return true
    end
    complete(walking)
    target.canReachTo=reach
    assert(replacementQueue and replacementQueue.current==other and replacementQueue.queue[1]==other,
        'reentrant final observation advanced replacement queue work')
    assert(not other.action and not body.action,'reentrant final observation began unowned work')
end
-- A checksum of stock Base source does not pin inherited methods on a live
-- child. Replacements must revoke qualification without invoking the callback.
for _,name in ipairs({'forceComplete','isValidStart'})do
    local queue,command,body,tail=pending(false);expand(command)
    local walking=queue.current;begin(walking)
    player.pathResult=BehaviorResult.Succeeded;player.square=target;walking:update()
    local original=ISBaseTimedAction[name];local calls=0
    ISBaseTimedAction[name]=function(self,...)
        if self==walking then calls=calls+1;error('foreign inherited child lifecycle executed')end
        return original(self,...)
    end
    complete(walking)
    ISBaseTimedAction[name]=original
    assert(calls==0,'changed inherited lifecycle was invoked by spatial qualification')
    rejected(queue,body,tail)
end
-- Invoke captured command callbacks directly with a wrong request/head/actor.
-- These must reject before native routing, not redirect another command.
for _,cause in ipairs({'request','actor','head'})do
    local queue,command,body,tail=pending(false)
    local callback=command.toolkitQueueCommand.callback
    local request=command.toolkitQueueCommand.snapshot
    local calls=routeCalls
    if cause=='request'then callback(player,{})
    elseif cause=='actor'then
        local actor=request.args[1];request.args[1]={};callback(player,request);request.args[1]=actor
    else
        local other=leaf();queue.current=other;callback(player,request);queue.current=command
    end
    assert(routeCalls==calls,'unowned request reached native route selection')
    assert(not body.action and contains(queue,tail))
end
do
    local queue,command,body,tail=pending(false)
    local calls=routeCalls;command.toolkitQueueOperation.toolkitCancelled=true
    expand(command)
    assert(routeCalls==calls,'pre-invalidated spatial command reached native routing')
    rejected(queue,body,tail)
end
do
    local queue,command,body,tail=pending(false)
    local spec=command.toolkitQueueCommand.snapshot.binding.spec
    local actor=spec.actor;local calls=0;local routes=routeCalls
    spec.actor=function()calls=calls+1;error('foreign actor resolver executed')end
    expand(command)
    spec.actor=actor
    assert(calls==0 and routeCalls==routes,'changed source binding executed a foreign actor resolver')
    rejected(queue,body,tail)
end
-- An idle replacement must retire the old operation without waiting for an
-- old callback. Token revocation and rejected command re-admission are the
-- observable contract; Kahlua weak-table collection is deliberately not assumed.
for _,replacement in ipairs({'queue','list'})do
    local queue,command,body,tail=pending(false)
    begin(command)
    local oldList=queue.queue
    local token=command.toolkitQueueOperation
    local replacementQueue
    if replacement=='queue'then replacementQueue=f.queue()
    else queue.queue={};queue.current=nil;replacementQueue=queue end
    local newList=replacementQueue.queue
    replacementQueue:tick()
    assert(replacementQueue.queue==newList and #newList==0 and replacementQueue.current==nil,
        'idle stale-episode pruning changed replacement work')
    assert(token.toolkitCancelled,'idle replacement did not revoke the detached operation')
    local other=leaf();ISTimedActionQueue.add(other)
    replacementQueue:tick()
    assert(replacementQueue.current==other and replacementQueue.queue[1]==other,
        'stale-episode pruning advanced an independent replacement head')
    -- Restoring old data does not make its cancelled captured command eligible
    -- to call the router again. No claim is made about arbitrary native walks
    -- resurrected outside the qualified phase contract.
    ISTimedActionQueue.queues[player]=queue;queue.queue=oldList;queue.current=command
    local calls=routeCalls
    command.toolkitQueueCommand.callback(player,command.toolkitQueueCommand.snapshot)
    assert(routeCalls==calls and not body.action,'retired command reacquired native routing authority')
end
-- Registry removal can stop every queue tick for that actor. The separate
-- maintenance hook must retire one episode per frame without sampling actors
-- or world facts, and must fairly reach later detached actors behind live ones.
do
    spatialMenu()
    local originalPlayer=player
    local function clone()
        local actor={};for name,value in pairs(originalPlayer)do actor[name]=value end;return actor
    end
    local entries={}
    for index=1,5 do
        player=clone()
        local queue,command,body,tail=pending(false);begin(command)
        entries[index]={actor=player,queue=queue,command=command,token=command.toolkitQueueOperation}
    end
    player=originalPlayer
    local getters=0
    for _,entry in ipairs(entries)do
        for _,name in ipairs({'getCurrentSquare','getSquare','getX','getY','getPlayerNum','isDead','isLocalPlayer'})do
            entry.actor[name]=function()getters=getters+1;error('maintenance sampled an actor')end
        end
    end
    local routes=routeCalls
    -- Keep the cursor's first actor live; the second actor disappears without
    -- any replacement queue and without another native completion callback.
    ISTimedActionQueue.queues[entries[2].actor]=nil
    spatialTick()
    assert(not entries[1].token.toolkitCancelled and not entries[2].token.toolkitCancelled,
        'single-frame maintenance scanned more than its one live episode')
    spatialTick()
    assert(entries[2].token.toolkitCancelled,'detached actor without queue ticks was retained')
    -- Removing a middle ring member explicitly must not strand later members.
    approach.reset(entries[4].queue)
    ISTimedActionQueue.queues[entries[3].actor]=nil
    ISTimedActionQueue.queues[entries[5].actor]=nil
    spatialTick();assert(entries[3].token.toolkitCancelled and not entries[5].token.toolkitCancelled)
    spatialTick();assert(entries[5].token.toolkitCancelled,'middle retirement broke fair cursor advancement')
    assert(not entries[1].token.toolkitCancelled,'maintenance revoked a still-owned episode')
    ISTimedActionQueue.queues[entries[1].actor]=nil
    spatialTick();assert(entries[1].token.toolkitCancelled,'cursor retirement failed at the final ring member')
    spatialTick();spatialTick()
    assert(getters==0 and routeCalls==routes,'maintenance called world facts or routing')
    -- Game/menu release must clear cursor links as well as maps. New episodes
    -- after either event must remain reachable by the independent sweep.
    for _,reset in ipairs({spatialGameStart,spatialMenu})do
        local queue,command=pending(false);begin(command)
        local token=command.toolkitQueueOperation
        reset();assert(token.toolkitCancelled,'world release did not revoke its episode')
        spatialTick()
        queue,command=pending(false);begin(command);token=command.toolkitQueueOperation
        ISTimedActionQueue.queues[player]=nil
        spatialTick();assert(token.toolkitCancelled,'world release left a disconnected maintenance cursor')
    end
    local queue,command=pending(true);begin(command)
    local token=command.toolkitQueueOperation;local list=queue.queue
    table.wipe(list);queue.current=nil
    spatialTick()
    assert(queue.queue==list and token.toolkitCancelled,
        'removed no-movement command mistook an absent child for an owned nil head')
end
-- Player cancellation retains the stock whole-queue interruption contract.
do
    local queue,command,body,tail=pending(false);expand(command)
    local walking=queue.current;begin(walking);player.cancel=true
    walking:update();walking:stop()
    assert(#queue.queue==0,'manual cancellation stopped preserving native interruption semantics')
end
-- Queue-disabled controls retain stock stale-completion/retrigger behavior.
-- The enabled editor's ownership guard must not silently fix this native path.
do
    local setting=PZSurvivorToolkit.Settings.actionQueue
    PZSurvivorToolkit.Settings.actionQueue=function()return false end
    active={};player.cancel=false
    local queue=ISTimedActionQueue:new(player)
    local current,retired=leaf(),leaf()
    ISTimedActionQueue.add(current)
    local allocation=current.action
    assert(allocation and queue.current==current)
    queue:onCompleted(retired)
    assert(queue.current==current and queue.queue[1]==current and current.action~=allocation,
        'disabled completion unexpectedly adopted enabled editor protection')
    PZSurvivorToolkit.Settings.actionQueue=setting
end
print('Native spatial execution: exact admission, no-movement/success, unavailable/stalled/missing outcomes, cleanup and independent work passed.')
if TestCoverage then TestCoverage('source-contract','passed')end
