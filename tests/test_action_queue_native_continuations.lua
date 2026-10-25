-- Execute the B42 get-up callback and queue insertion sources; Java animation/networking is explicit.
if not NativeActionRoot then print('Native continuation contracts SKIP (requires --game).'); return end
local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r','') end
    local file=assert(io.open(path));local text=file:read('*a');file:close();return text:gsub('\r','')
end
getFilenameOfClosure=function(callback)return debug.getinfo(callback,'S').source:gsub('^@','')end
getGameFilesInput=function(path)
    local text=read(NativeActionRoot..'/'..path:gsub('^media/lua/',''));local offset=1
    return {readLine=function()
        if offset>#text then return end
        local stop=text:find('\n',offset)or #text+1
        local line=text:sub(offset,stop-1);offset=stop+1;return line
    end,close=function()end}
end
f.native('shared/TimedActions/ISWaitWhileGettingUp.lua')
local originalPerform=ISWaitWhileGettingUp.perform
local enabled=true
PZSurvivorToolkit.Settings.actionQueue=function()return enabled end
isClient=function()return false end;isServer=function()return false end
ISLogSystem={logAction=function()end}
local nativeInstanceof=instanceof
instanceof=function(value,name)
    return type(value)=='table'and value.class=='IsoPlayer'and name=='IsoGameCharacter'or nativeInstanceof(value,name)
end
local began,advanced={},{}
local function actor(slot)
    local player={class='IsoPlayer',slot=slot,natives={},vars={}}
    player.getPlayerNum=function(self)return self.slot end
    player.isDead=function(self)return self.dead==true end
    player.isAsleep=function(self)return self.asleep==true end
    player.isLocalPlayer=function()return true end
    player.isDraggingCorpse=function()return false end
    player.isFarming=function()return false end
    player.isSitting=function(self)return self.sitting==true end
    player.setVariable=function(self,key,value)self.vars[key]=value end
    player.setIsFarming=function()end
    player.setTimedActionToRetrigger=function(self,value)self.retrigger=value end
    player.getTimedActionToRetrigger=function(self)return self.retrigger end
    player.getCharacterActions=function(self)return {contains=function(_,native)
        for _,value in ipairs(self.natives)do if value==native then return true end end;return false
    end,isEmpty=function()return #self.natives==0 end,size=function()return #self.natives end,get=function(_,index)return self.natives[index+1]end}end
    player.StartAction=function(self,native)
        self.natives[#self.natives+1]=native
        began[#began+1]=native.lua
        native.lua:start()
    end
    return player
end
local player,peer=actor(0),actor(1)
getSpecificPlayer=function(slot)if slot==0 then return player elseif slot==1 then return peer end end
LuaTimedActionNew={new=function(action)
    return {lua=action,forceComplete=function(self)self.completed=true end,forceStop=function(self)self.stopped=true end,
        isStarted=function()return true end,hasStalled=function()return false end,getJobDelta=function()return 0 end,
        getTable=function()return action end}
end}
f.project('ActionQueueOperations')
local operations=PZSurvivorToolkit.ActionQueueOperations
assert(type(operations.performNativeContinuation)=='function','missing shared native continuation boundary')
local nativeCompleted=ISTimedActionQueue.onCompleted
ISTimedActionQueue.onCompleted=function(queue,action)
    if operations.deferCompletion(queue,action)then return end
    advanced[#advanced+1]=action
    return nativeCompleted(queue,action)
end
local nativeCancel=ISTimedActionQueue.cancelQueue
ISTimedActionQueue.cancelQueue=function(queue)
    operations.invalidateQueue(queue)
    return nativeCancel(queue)
end
local function reset()
    ISTimedActionQueue.queues={};began,advanced={},{}
    for _,value in ipairs({player,peer})do value.natives={};value.sitting=nil;value.asleep=nil;value.dead=nil;value.vars={} end
    return ISTimedActionQueue.getTimedActionQueue(player)
end
local function child(name,owner)
    local value=ISBaseTimedAction:new(owner or player);value.Type=name
    return value
end
local function add(value)return ISTimedActionQueue.add(value)end
local function wait(callback,owner)
    local value=ISWaitWhileGettingUp:new(owner or player)
    value:setOnComplete(callback)
    add(value)
    return value
end
local function hasBegun(value)
    for _,entry in ipairs(began)do if entry==value then return true end end
    return false
end
local function finish(value)
    local results={value:perform()}
    for index,native in ipairs(value.character.natives)do if native==value.action then table.remove(value.character.natives,index);break end end
    return unpack(results)
end
-- Demonstrate the actual stock failure, without replacing its queue algorithm.
local q=reset();local body,tail=child('Workout'),child('IndependentReader')
ISTimedActionQueue.addGetUpAndThen(player,body)
local baseline=q.current;add(tail)
originalPerform(baseline)
assert(q.queue[1]==tail and q.queue[2]==body and hasBegun(tail),
    'native get-up baseline no longer reproduces child appended after already-started tail')
local continuation=assert(f.project('ActionQueueNativeContinuation'))
if continuation.install then assert(continuation.install(),'native continuation installation refused original sources')end
assert(type(continuation.matches)=='function'and type(continuation.isCallback)=='function')

for _,editing in ipairs({false,true})do
    enabled=editing
    for _,sitting in ipairs({false,true})do
        q=reset();player.sitting=sitting
        body,tail=child('Workout'),child('IndependentReader')
        ISTimedActionQueue.addGetUpAndThen(player,body)
        local parent=q.current;add(tail)
        assert(continuation.matches(parent),'source-backed native get-up was not recognized')
        if not editing then
            -- Actual queue-off begin bookkeeping may already invalidate this editor token.
            q.toolkitOperationsInvalid=true;parent.toolkitQueueOperation.toolkitCancelled=true
        end
        if sitting then
            assert(player.vars.forceGetUp==true and not parent.action.completed,'sitting native start did not wait for get-up')
            player.sitting=false;parent:update()
        end
        assert(parent.action.completed,'native standing/get-up update did not request completion')
        finish(parent)
        assert(q.current==body and q.queue[1]==body and q.queue[2]==tail and hasBegun(body)and not hasBegun(tail),
            'native continuation started independent reader before its workout')
        assert(#advanced==1 and advanced[1]==parent,'native parent did not advance exactly once')
        assert(not parent._isAddingActions and parent._numAddedActions==nil,'get-up insertion scope leaked')
        assert(body.toolkitQueueOperation==parent.toolkitQueueOperation and tail.toolkitQueueOperation~=body.toolkitQueueOperation,
            'native continuation lost exact parent membership or captured unrelated request')
        finish(body);assert(q.current==tail and hasBegun(tail),'independent reader was lost after child completion')
    end
    q=reset();local a,b=child('First'),child('Second');tail=child('IndependentReader')
    local parent=wait(function()
        assert(q.current~=tail and not hasBegun(tail))
        add(a);add(b)
    end)
    add(tail);finish(parent)
    assert(q.queue[1]==a and q.queue[2]==b and q.queue[3]==tail and not hasBegun(tail),
        'multiple callback children did not retain native insertion order')

    q=reset();local own,other=child('Own'),child('OtherActor',peer);tail=child('IndependentReader')
    parent=wait(function()add(own);add(other)end)
    add(tail);finish(parent)
    assert(own.toolkitQueueOperation==parent.toolkitQueueOperation and other.toolkitQueueOperation~=parent.toolkitQueueOperation,
        'native continuation global scope leaked parent ownership to another actor')
    assert(ISTimedActionQueue.queues[peer].current==other and q.current==own and q.queue[2]==tail)

    q=reset();local first,last=child('BeforeNested'),child('AfterNested')
    local peerChild=child('PeerNestedChild',peer)
    local peerParent=wait(function()add(peerChild)end,peer)
    parent=wait(function()
        add(first)
        finish(peerParent) -- The other actor completes synchronously inside this callback.
        add(last)
    end)
    tail=child('IndependentReader');add(tail);finish(parent)
    assert(q.current==first and q.queue[2]==last and q.queue[3]==tail and not hasBegun(tail),
        'nested native callback did not restore the outer insertion boundary')
    assert(first.toolkitQueueOperation==parent.toolkitQueueOperation and last.toolkitQueueOperation==parent.toolkitQueueOperation
        and peerChild.toolkitQueueOperation==peerParent.toolkitQueueOperation
        and peerChild.toolkitQueueOperation~=parent.toolkitQueueOperation,
        'nested native callback leaked or replaced actor ownership')

    q=reset();local grandchild=child('Grandchild');local nested
    parent=wait(function()
        nested=ISWaitWhileGettingUp:new(player)
        nested:setOnComplete(function()add(grandchild)end)
        add(nested)
    end)
    tail=child('IndependentReader');add(tail);finish(parent)
    assert(q.current==nested and not hasBegun(tail),'nested native continuation lost parent insertion')
    finish(nested)
    assert(q.current==grandchild and q.queue[2]==tail and grandchild.toolkitQueueOperation==parent.toolkitQueueOperation,
        'nested completion scope failed to restore outer ownership/order')
end

-- Execute the other native get-up producer, retaining nil holes and false values.
local source=read(NativeActionRoot..'/client/ISUI/ISContextMenu.lua')
local callbackSource=assert(source:match('(function ISContextMenu:onGetUpAndThen%(.-\nend)'))
assert(loadstring(callbackSource,'@media/lua/client/ISUI/ISContextMenu.lua'))()
for _,editing in ipairs({false,true})do
    enabled=editing;q=reset();local target=child('ContextChild');tail=child('IndependentReader')
    ISContextMenu.onGetUpAndThen({player=0},function(...)
        assert(select('#',...)==10,'native callback argument count changed')
        local args={...};assert(args[1]=='first'and args[2]==nil and args[3]==false and args[10]=='last')
        add(target)
    end,'first',nil,false,nil,nil,nil,nil,nil,nil,'last')
    local parent=q.current;add(tail);finish(parent)
    assert(q.current==target and q.queue[2]==tail and not hasBegun(tail),'context-menu producer retained the same append bug')
end

for _,mutation in ipairs({'reset','cancel','replacement-queue','new-head','native','generation','canceled-token','operations-invalid','parent-token','actor','queue-actor'})do
    q=reset();tail=child('IndependentReader');local late=child('RejectedLate');local replacement
    local parent=wait(function()
        if mutation=='reset'then q:resetQueue()
        elseif mutation=='cancel'then q:cancelQueue()
        elseif mutation=='replacement-queue'then replacement=ISTimedActionQueue:new(player)
        elseif mutation=='new-head'then replacement=child('NewHead');q.queue={replacement};q.current=replacement
        elseif mutation=='native'then q.current.action={}
        elseif mutation=='generation'then q.toolkitOperationGeneration=(q.toolkitOperationGeneration or 0)+1
        elseif mutation=='canceled-token'then q.current.toolkitQueueOperation.toolkitCancelled=true
        elseif mutation=='operations-invalid'then q.toolkitOperationsInvalid=true
        elseif mutation=='parent-token'then q.current.toolkitQueueOperation={}
        elseif mutation=='actor'then q.current.character=peer
        elseif mutation=='queue-actor'then q.character=peer end
        add(late)
    end)
    add(tail);finish(parent)
    local current=ISTimedActionQueue.queues[player]
    assert(not hasBegun(late)and #advanced==0,mutation..' allowed late work or advanced invalid parent')
    for _,value in ipairs(current.queue)do assert(value~=late,mutation..' repopulated a revoked synchronous scope')end
    if mutation=='new-head'then assert(current.current==replacement,'completion advanced a foreign new head')end
end

-- A second completion of the old parent must not escape a revoked scope and begin a new head.
for _,mutation in ipairs({'reset','new-head'})do
    q=reset();local replacement=child('ForeignNewHead');local parent
    parent=wait(function()
        if mutation=='reset'then q:resetQueue()end
        q.queue={replacement};q.current=replacement
        q:onCompleted(parent)
        q:onCompleted(parent)
    end)
    tail=child('IndependentReader');add(tail);finish(parent)
    assert(#advanced==0 and q.current==replacement and q.queue[1]==replacement and not hasBegun(replacement),
        mutation..': revoked parent completion advanced or began the foreign new head')
end

q=reset();local failure={};local surviving=child('EnqueuedBeforeError');tail=child('IndependentReader')
local parent=wait(function()add(surviving);error(failure)end)
add(tail)
local ok,problem=pcall(parent.perform,parent)
assert(not ok and problem==failure,'native callback error object was swallowed/replaced')
assert(#advanced==0 and q.current==parent and q.queue[2]==surviving and q.queue[3]==tail and not hasBegun(tail),
    'failed native callback advanced or rolled back partial child additions')
assert(not parent._isAddingActions and parent._numAddedActions==nil,'failed native callback retained insertion scope')
local following=child('IndependentAfterError');add(following)
assert(q.queue[#q.queue]==following and following.toolkitQueueOperation~=parent.toolkitQueueOperation,
    'failed synchronous completion leaked insertion/token scope into later requests')

for _,admission in ipairs({'ignored','asleep'})do
    q=reset();local rejected=child('RejectedChild');tail=child('IndependentReader')
    parent=wait(function()
        if admission=='ignored'then rejected.ignoreAction=true else player.asleep=true end
        add(rejected);player.asleep=false
    end)
    add(tail);finish(parent)
    assert(q.current==tail and #q.queue==1 and not hasBegun(rejected),admission..' bypassed native child admission')
end

q=reset();local called=0
parent=wait(function()called=called+1 end)
local function probe(self,...)
    assert(select('#',...)==3,'shared boundary lost trailing nil argument')
    local first,second,third=...;assert(first==false and second=='middle'and third==nil)
    originalPerform(self)
    return nil,false,'result',nil
end
local results={n=0}
local function capture(...)results={n=select('#',...),...}end
capture(operations.performNativeContinuation(parent,probe,false,'middle',nil))
assert(results.n==4 and results[1]==nil and results[2]==false and results[3]=='result'and results[4]==nil and called==1,
    'shared boundary changed native delegate arguments or nil/false returns')
assert(continuation.isCallback('perform',ISWaitWhileGettingUp.perform),'installed get-up callback lost narrow adoption proof')
assert(not continuation.isCallback('perform',function()end),'foreign callback acquired native continuation proof')
print('Native get-up continuations passed (queue on/off, original sitting/standing callbacks, child/tail order, other producer, cross-actor/nested scope, reset/cancel/identity revocation, errors, native admission and nil/false values).')
