require = function() end
ISQueueActionsAction = {start = function(self) self.nativeStopped = true end}
getFilenameOfClosure = function() return 'TimedActions/ISQueueActionsAction.lua' end
local enabled, client = true, false
PZSurvivorToolkit = {Settings = {actionQueue = function() return enabled end}}
ISTimedActionQueue = {queues = {}}
isClient = function() return client end
local root = ProjectRoot or "."
local Lifecycle = assert(loadfile(root .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueLifecycle.lua"))()

local function fixture()
    local present = {}
    local character = {isDead = function(self)return self.dead==true end, getCharacterActions = function() return {contains = function(_, action) return present[action] end} end}
    local action = {character = character, action = {}}
    present[action.action] = true
    local queue = {character = character, current = action, queue = {action}, started = 0}
    ISTimedActionQueue.queues[character] = queue
    queue.onCompleted = function(self, completed)
        if Lifecycle.deferCompletion(self, completed) then return end
        assert(completed == self.current and completed == self.queue[1])
        table.remove(self.queue, 1)
        self.current = self.queue[1]
        self.started = self.started + 1
    end
    return queue, action, present
end

local queue, action, present = fixture()
assert(Lifecycle.begin(action, "perform"))
assert(Lifecycle.current(action.character) == action)
queue:onCompleted(action)
assert(queue.started == 0)
Lifecycle.finish(action, "perform", true)
assert(Lifecycle.current(action.character) == nil, "async child inherited finished callback")
assert(Lifecycle.flush(queue) == "waiting")
assert(Lifecycle.begin(action, "complete"))
assert(queue.queue[1] == action, "SP complete lost parent needed by addAfter")
table.insert(queue.queue, {character = action.character, child = true})
Lifecycle.finish(action, "complete", true)
assert(Lifecycle.flush(queue) == "waiting", "native action not removed")
present[action.action] = nil
assert(Lifecycle.flush(queue) == "completed")
assert(queue.started == 1 and queue.current.child)
assert(Lifecycle.flush(queue) == nil, "completion replayed")

client = true
queue, action, present = fixture()
assert(Lifecycle.begin(action, "perform"))
queue:onCompleted(action)
table.insert(queue.queue, {character = action.character, callbackReturn = true})
assert(Lifecycle.flush(queue) == "waiting", "MP callback tail not finished")
Lifecycle.finish(action, "perform", true)
present[action.action] = nil
assert(Lifecycle.flush(queue) == "completed" and queue.current.callbackReturn)

queue, action, present = fixture()
assert(Lifecycle.begin(action, "perform"))
queue:onCompleted(action)
Lifecycle.finish(action, "perform", false)
present[action.action] = nil
local status, failed = Lifecycle.flush(queue)
assert(status == "failed" and failed == action and queue.started == 0)
assert(Lifecycle.flush(queue) == nil, "failure replayed")

queue, action, present = fixture()
assert(Lifecycle.begin(action, "perform"))
queue:onCompleted(action)
Lifecycle.reset(queue)
Lifecycle.finish(action, "perform", true)
assert(Lifecycle.flush(queue) == nil and queue.started == 0)

queue, action, present = fixture()
assert(Lifecycle.begin(action, "perform"))
queue:onCompleted(action)
ISTimedActionQueue.queues[action.character] = {}
Lifecycle.finish(action, "perform", true)
assert(Lifecycle.flush(queue) == nil and queue.started == 0, "detached queue advanced")

queue, action, present = fixture()
enabled = false
assert(not Lifecycle.begin(action, "perform"))
assert(not Lifecycle.deferCompletion(queue, action))
assert(Lifecycle.flush(queue) == nil)
enabled = true
assert(not Lifecycle.begin(action, "complete"), "standalone complete acquired unrelated queue")
assert(not Lifecycle.begin({}, "perform"))
queue, action, present = fixture()
local forced = 0
function action:forceStop() forced = forced + 1 end
local receipt = {state = "started"}
PZSurvivorToolkit.ActionQueueAcknowledgements = {capture = function(candidate) if candidate == action then return receipt end end}
getTimestampMs = function() return 100 end
assert(Lifecycle.requestStop(queue, action, "cancel", "operation"))
assert(forced == 1 and queue.toolkitCancel == action and queue.toolkitStopIntent.scope == "operation")
assert(queue.toolkitOutcomeWait.generic and queue.toolkitOutcomeWait.acknowledgement == receipt)
assert(queue.toolkitOutcomeWait.deadline == 30100)
assert(not Lifecycle.requestStop({}, action, "cancel", "action"))
-- Native/Toolkit command expansion is checked against native queue methods in
-- test_action_queue_operations; this fixture isolates completion and receipts.
-- Exercise the completion gate with the real sealed receipt registry. It must
-- not turn a server cancellation, stale generation or explicit local stop into
-- completion, even when the same action/native pointers remain accessible.
enabled,client=true,true
-- Earlier cases use minimal isolated actors, not native local player slots.
ISTimedActionQueue.queues={}
local receive
Events={OnServerCommand={Add=function(callback)receive=callback end}}
local ack=assert(loadfile(root..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueAcknowledgements.lua'))()
queue,action,present=fixture()
local actor=action.character
actor.getPlayerNum=function()return 0 end
actor.getOnlineID=function()return 17 end
actor.isDead=function(self)return self.dead==true end
actor.isAsleep=function(self)return self.asleep==true end
actor.isLocalPlayer=function(self)return self.localPlayer~=false end
actor.pressedCancelAction=function(self)return self.cancel==true end
actor.isPlayerMoving=function(self)return self.moving==true end
actor.pressedMovement=function(self)return self.input==true end
actor.isRunning=function(self)return self.running==true end
actor.isSprinting=function(self)return self.sprinting==true end
actor.isAiming=function(self)return self.aiming==true end
getSpecificPlayer=function(slot)if slot==0 then return actor end end
local native=action.action
action.toolkitNativeTransaction,action.toolkitNativeKind=7,'CompletionProbe'
action.toolkitQueueOperation={}
action.forceComplete=function()error('the Lua completion gate must stay read-only')end
local serial=0
local function deliver(state)
    receive('PZSurvivorToolkitActions','State',{protocol=1,player=17,transaction=7,
        kind='CompletionProbe',token=string.format('00000000-0000-0000-0000-%012x',serial),state=state})
end
local function permitted()return Lifecycle.allowNativeCompletion(action,native)end
local function waiting()return Lifecycle.allowNativeCompletionWait(action,native)end
assert(not permitted()and not waiting(),'missing receipt acquired native completion/wait')
for _,terminal in ipairs({'canceled','rejected'})do
    ack.reset(queue);serial=serial+1;deliver('started');deliver(terminal)
    assert(not permitted()and not waiting(),terminal..' receipt acquired completion/wait')
end
ack.reset(queue);serial=serial+1;deliver('started')
assert(not permitted(),'a started transaction became completion')
assert(waiting(),'sealed Started lost waiting permission')
deliver('completed');assert(permitted()and waiting(),'owned sealed completed transaction was refused')
assert(not Lifecycle.allowNativeCompletion(action,{}),'another native object acquired completion')
for _,name in ipairs({'toolkitCancel','toolkitStopIntent','toolkitOutcomeWait','toolkitGroupCancel',
    'toolkitResume','toolkitOperationsInvalid'})do
    queue[name]={};assert(not permitted()and not waiting(),name..' was overridden');queue[name]=nil
end
action.toolkitQueueOperation.toolkitCancelled=true;assert(not permitted());action.toolkitQueueOperation.toolkitCancelled=nil
for _,name in ipairs({'dead','asleep','cancel'})do actor[name]=true;assert(not permitted()and not waiting(),name..' was overridden');actor[name]=nil end
actor.localPlayer=false;assert(not permitted());actor.localPlayer=nil
for _,entry in ipairs({{'stopOnWalk','moving'},{'stopOnWalk','input'},{'stopOnRun','running'},
    {'stopOnRun','sprinting'},{'stopOnAim','aiming'}})do
    action[entry[1]],actor[entry[2]]=true,true;assert(not permitted()and not waiting(),'native input cancellation was overridden')
    action[entry[1]]=false;assert(permitted(),'a non-stopping input blocked paid completion')
    action[entry[1]],actor[entry[2]]=nil,nil
end
enabled=false;assert(not permitted());enabled=true
client=false;assert(not permitted());client=true
queue.current={};assert(not permitted());queue.current=action
queue.queue[1]={};assert(not permitted());queue.queue[1]=action
assert(permitted())
actor.asleep=true;assert(not permitted(),'sleeping actor acquired paid completion while queue enabled');actor.asleep=nil
queue.toolkitOperationGeneration=(queue.toolkitOperationGeneration or 0)+1
assert(not permitted(),'a stale queue generation acquired completion')
queue.toolkitOperationGeneration=queue.toolkitOperationGeneration-1
assert(permitted())
ack.reset(queue);assert(not permitted(),'queue reset revived a retained completed receipt')
-- Queue-off completion uses the real disabled bookkeeping boundary and sealed
-- Started/Completed receipt. It cannot acquire the optional scheduler or forgive
-- a later native stop, reset, changed UI token or ownership change.
do
    local toolkit=PZSurvivorToolkit
    local methods={}
    for _,name in ipairs({'getPlayerNum','getOnlineID','isDead','isAsleep','isLocalPlayer','pressedCancelAction','isPlayerMoving',
        'pressedMovement','isRunning','isSprinting','isAiming'})do methods[name]=actor[name]end
    local function read(path)
        if NativeReadText then return NativeReadText(path)end
        local file=assert(io.open(path));local text=file:read('*a');file:close();return text
    end
    local queueSource=read(root..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueue.lua')
    local operationSource=read(root..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueOperations.lua')
    local operations=assert(loadstring('local Operations={};\n'
        ..assert(operationSource:match('(function Operations.invalidate%(token%).-\nend)'))..'\n'
        ..assert(operationSource:match('(function Operations.invalidateQueue%(queue%).-\nend)'))
        ..'\nreturn Operations','@PZSurvivorToolkit/ActionQueueOperations.lua'))()
    local previousBase=ISBaseTimedAction
    ISBaseTimedAction={begin=function(value)
        value.action={};value.toolkitNativeTransaction,value.toolkitNativeKind=7,'CompletionProbe'
        return 'native-began'
    end}
    local source=assert(queueSource:match('(local function updateOperationState%(queue%).-Queue.updateOperationState = updateOperationState)'))
        ..'\n'..assert(queueSource:match('(local begin = ISBaseTimedAction.begin.-\nend)\nPolicy.adoptBegin'))
    local api=assert(loadstring('local Queue,Toolkit,Operations,live=...\n'..source..'\nreturn Queue',
        '@PZSurvivorToolkit/ActionQueue.lua'))({},toolkit,operations,function(value)return not value.character:isDead()end)
    local function prepare(terminal,options)
        enabled,client=false,true
        queue,action,present=fixture();actor=action.character
        for name,method in pairs(methods)do actor[name]=method end
        action.toolkitQueueOperation={}
        action.forceComplete=function()error('disabled permission must not execute native completion')end
        assert(ISBaseTimedAction.begin(action)=='native-began')
        native=action.action
        assert(queue.toolkitOperationsInvalid==true and action.toolkitQueueOperation.toolkitCancelled==true
            and queue.toolkitOperationGeneration==1,'actual disabled begin did not invalidate UI state before native allocation')
        if options then options()end
        ack.reset(queue);serial=serial+1
        if terminal then deliver('started');if terminal~='started'then deliver(terminal)end end
        return ack.capture(action)
    end
    prepare('completed');assert(permitted()and waiting(),'genuine disabled Started/Completed lost native completion after actual begin bookkeeping')
    assert(not Lifecycle.allowNativeCompletion(nil,native) and not Lifecycle.allowNativeCompletion({character={}},native),
        'unowned malformed action reached disabled acknowledgement capture')
    for _,terminal in ipairs({'started','canceled','rejected','completed'})do
        local receipt=prepare(terminal)
        assert(ack.allowsDisabledNativeCompletion(action,receipt)==(terminal=='completed'))
        assert(permitted()==(terminal=='completed'),'disabled boundary lost exact terminal proof: '..terminal)
        assert(waiting()==(terminal=='started'or terminal=='completed'),'disabled waiting lost exact receipt state: '..terminal)
        assert(ack.allowsDisabledNativeCompletionWait(action,receipt)==waiting())
    end
    prepare('completed',function()action.toolkitQueueOperation.toolkitCancelled=false end)
    assert(permitted(),'actual native queue-off uncanceled token baseline was refused')
    prepare('completed',function()action.toolkitQueueOperation=true end)
    assert(not permitted(),'malformed operation token acquired disabled native completion')
    prepare(nil);assert(not permitted(),'disabled boundary invented missing Started receipt')
    deliver('completed');assert(not permitted(),'terminal-only receipt became disabled completion')
    local receipt=prepare('completed')
    local copied={};for key,value in pairs(receipt)do copied[key]=value end
    assert(not ack.allowsDisabledNativeCompletion(action,copied),'copied receipt acquired private disabled baseline')
    assert(not Lifecycle.begin(action,'perform') and not Lifecycle.deferCompletion(queue,action)
        and Lifecycle.current(actor)==nil and Lifecycle.flush(queue)==nil and queue.started==0,
        'paid disabled completion acquired optional queue scheduling')
    queue.queue[2]={character=actor,independent=true}
    assert(permitted(),'native callback permission was lost before original perform')
    queue:onCompleted(action) -- Original native perform owns this advancement.
    assert(queue.started==1 and queue.current.independent and not permitted(),
        'native completion replayed or failed to preserve the independent tail')
    assert(Lifecycle.flush(queue)==nil and queue.started==1,'disabled observer replayed native advancement')
    for _,mutate in ipairs({
        function()action.toolkitQueueOperation={}end,
        function()action.toolkitQueueOperation.toolkitCancelled=false end,
        function()action.toolkitQueueOperation.toolkitCancelled=nil end,
        function()queue.toolkitOperationsInvalid=false end,
        function()queue.toolkitOperationsInvalid=nil end,
        function()action.action={}end,
        function()queue.toolkitOperationGeneration=queue.toolkitOperationGeneration+1 end,
        function()queue.current={}end,
        function()queue.queue[1]={}end,
        function()ISTimedActionQueue.queues[actor]={}end,
        function()action.toolkitNativeTransaction=8 end,
        function()action.toolkitNativeKind='OtherProbe'end,
        function()getSpecificPlayer=function()return {}end end,
    })do
        for _,state in ipairs({'started','completed'})do
            prepare(state);mutate();assert(not permitted()and not waiting(),'changed disabled baseline/ownership retained completion/wait')
            getSpecificPlayer=function(slot)if slot==0 then return actor end end
        end
        getSpecificPlayer=function(slot)if slot==0 then return actor end end
    end
    for _,field in ipairs({'toolkitCancelled','toolkitOperationsInvalid'})do
        local function absent()
            if field=='toolkitCancelled'then action.toolkitQueueOperation.toolkitCancelled=nil else queue[field]=nil end
        end
        prepare('completed',absent);assert(permitted(),'unchanged nil disabled baseline was refused')
        if field=='toolkitCancelled'then action.toolkitQueueOperation.toolkitCancelled=false else queue[field]=false end
        assert(not permitted(),'nil and false disabled baseline were conflated')
    end
    for _,name in ipairs({'toolkitCancel','toolkitStopIntent','toolkitOutcomeWait','toolkitGroupCancel',
        'toolkitResume'})do
        for _,state in ipairs({'started','completed'})do
            prepare(state);queue[name]={};assert(not permitted()and not waiting(),'disabled completion/wait overrode '..name)
        end
    end
    for _,name in ipairs({'dead','asleep','cancel'})do
        for _,state in ipairs({'started','completed'})do
            prepare(state);actor[name]=true;assert(not permitted()and not waiting(),'disabled completion/wait overrode '..name)
        end
    end
    prepare('completed');actor.localPlayer=false;assert(not permitted(),'remote actor acquired disabled completion')
    for _,entry in ipairs({{'stopOnWalk','moving'},{'stopOnWalk','input'},{'stopOnRun','running'},
        {'stopOnRun','sprinting'},{'stopOnAim','aiming'}})do
        prepare('completed');action[entry[1]],actor[entry[2]]=true,true
        assert(not permitted(),'disabled completion overrode native input')
        action[entry[1]]=false;assert(permitted(),'non-stopping input blocked disabled paid completion')
    end
    prepare('completed');client=false;assert(not permitted(),'SP acquired remote completion');client=true
    prepare('completed');ack.reset(queue);assert(not permitted()and not waiting(),'reset revived a disabled receipt')
    -- Observe each transition through the real bookkeeping helper. Turning off
    -- invalidates old enabled receipts; a fresh disabled start can earn its own.
    prepare('completed');enabled=true;api.updateOperationState(queue);assert(not permitted())
    enabled=false;api.updateOperationState(queue);assert(not permitted(),'observed off/on/off revived an old receipt')
    prepare('completed');enabled=true;api.updateOperationState(queue)
    action.toolkitQueueOperation={};ack.reset(queue);serial=serial+1;deliver('started');deliver('completed')
    assert(permitted(),'ordinary enabled baseline lost paid completion')
    enabled=false;api.updateOperationState(queue);assert(not permitted(),'enabled receipt survived disabled generation invalidation')
    prepare('completed');assert(permitted(),'fresh start after disabled boundary did not earn completion')
    prepare('started');local pending=ack.capture(action)
    local copy={};for k,v in pairs(pending)do copy[k]=v end
    assert(not ack.allowsDisabledNativeCompletionWait(action,copy),'copied Started acquired disabled wait')
    action.toolkitQueueOperation.toolkitCancelled=false;assert(not waiting(),'changed raw canceled baseline retained Started wait')
    prepare('started');enabled=true;api.updateOperationState(queue);assert(not waiting(),'off/on retained Started wait')
    enabled=false;api.updateOperationState(queue);assert(not waiting(),'off/on/off revived Started wait')
    prepare('started');assert(waiting()and not permitted(),'fresh disabled Started did not acquire waiting alone')
    ISBaseTimedAction=previousBase
    enabled=true
end
print('Queue-disabled paid native completion: real begin/invalidation, sealed ACK, unchanged private baseline, native stop/reset/input guards and no scheduler ownership passed.')

-- Exercise the real public cancellation function with controlled Policy resource
-- decisions and the real sealed ACK registry. No callback/effect is executed by
-- the completion permission, including an accepted cancellation of a later row.
do
    local toolkit=PZSurvivorToolkit
    local previousPolicy=toolkit.ActionQueuePolicy
    local methods={}
    for _,name in ipairs({'getPlayerNum','getOnlineID','isDead','isAsleep','isLocalPlayer','pressedCancelAction','isPlayerMoving',
        'pressedMovement','isRunning','isSprinting','isAiming'})do methods[name]=actor[name]end
    local descriptor={}
    local callback=function()end
    local policy={}
    function policy.inspect(value)
        if value.perform~=callback or value.complete~=callback or value.foreign then return end
        return {interrupt=value.auditedStop and 'audited-stop' or 'finish-step',preparationFinish=true},'fixture.preparation',descriptor
    end
    function policy.stoppable(value)return value.auditedStop==true end
    function policy.preparationCanFinish(value)return policy.inspect(value)~=nil and not value.unsafe end
    function policy.editUnchanged(value,snapshot)
        return snapshot and snapshot.queue==value and snapshot.current==value.current and snapshot.list==value.queue
            and snapshot.native==value.current.action and snapshot.token==value.current.toolkitQueueOperation
            and snapshot.cancelled==value.current.toolkitQueueOperation.toolkitCancelled
            and snapshot.generation==(value.toolkitOperationGeneration or 0) and snapshot.group==value.toolkitGroupCancel
    end
    function policy.evaluateCancel(value,target)
        local accepted=not value.toolkitGroupCancel and policy.inspect(value.current)~=nil and not target.denied
        return {allowed=accepted,reason=not accepted and 'operation_dependent' or nil,first=1,last=#value.queue,
            mode=target==value.current and 'active'or 'pending',snapshot={queue=value,current=value.current,list=value.queue,
                native=value.current.action,token=value.current.toolkitQueueOperation,
                cancelled=value.current.toolkitQueueOperation.toolkitCancelled,generation=value.toolkitOperationGeneration or 0,
                group=value.toolkitGroupCancel}}
    end
    function policy.record()end
    toolkit.ActionQueuePolicy=policy
    local function read(path)
        if NativeReadText then return NativeReadText(path)end
        local file=assert(io.open(path));local text=file:read('*a');file:close();return text
    end
    local cancelSource=assert(read(root..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueue.lua')
        :match('(function Queue.cancelOperation%(queue, action, expected%).-\nend)'))
    local api=assert(loadstring('local Queue,Toolkit,Policy,Operations=...;local Batch;local Settlement={admitCancellation=function()return true end};local stoppable=Policy.stoppable\n'
        ..cancelSource..'\nreturn Queue','@PZSurvivorToolkit/ActionQueue.lua'))({},toolkit,policy,
            {invalidate=function(token)token.toolkitCancelled=true end})
    local stopped=0
    local function prepare(terminal,later)
        queue,action,present=fixture();actor=action.character
        for name,method in pairs(methods)do actor[name]=method end
        native=action.action
        action.toolkitNativeTransaction,action.toolkitNativeKind=7,'CompletionProbe'
        action.toolkitQueueOperation={};action.perform,action.complete=callback,callback
        action.forceStop=function()stopped=stopped+1 end
        local target=action
        if later then
            target={character=actor,toolkitQueueOperation=action.toolkitQueueOperation}
            queue.queue[2]=target
        end
        ack.reset(queue);serial=serial+1
        if terminal then deliver('started');if terminal~='started'then deliver(terminal)end end
        assert(api.cancelOperation(queue,target),'actual accepted preparation cancellation was rejected')
        assert(queue.toolkitGroupCancel.action==action and action.toolkitQueueOperation.toolkitCancelled,
            'public cancellation did not bind its actual current native step')
        return target
    end
    for _,terminal in ipairs({'started','rejected','canceled','completed'})do
        prepare(terminal)
        assert(permitted()==(terminal=='completed'),'finish-step cancellation bypassed the exact terminal ACK: '..terminal)
    end
    assert(stopped==0,'finish-step cancellation invoked native forceStop')
    prepare(nil);assert(not permitted(),'finish-step cancellation invented a receipt')
    deliver('started');assert(not permitted(),'started ACK became completed finish-step work')
    deliver('completed');assert(permitted(),'late exact completed ACK lost its accepted finish-step capability')
    prepare('completed',true);assert(permitted(),'canceling a later same-operation row lost the current finish-step capability')
    local request=queue.toolkitGroupCancel
    queue.toolkitGroupCancel={action=action,token=action.toolkitQueueOperation}
    assert(not permitted(),'copied public request fields acquired private finish-step completion')
    queue.toolkitGroupCancel=request;assert(not permitted(),'a replaced request revived revoked finish-step completion')
    for _,mutate in ipairs({
        function()action.toolkitQueueOperation={}end,
        function()queue.toolkitGroupCancel.token={}end,
        function()action.action={}end,
        function()queue.toolkitOperationGeneration=(queue.toolkitOperationGeneration or 0)+1 end,
        function()queue.current={}end,
        function()queue.queue[1]={}end,
        function()ISTimedActionQueue.queues[actor]={}end,
        function()action.perform=function()end end,
        function()action.complete=function()end end,
        function()action.unsafe=true end,
        function()action.auditedStop=true end,
        function()toolkit.ActionQueuePolicy={}end,
    })do
        toolkit.ActionQueuePolicy=policy;prepare('completed');mutate()
        assert(not permitted(),'changed finish-step ownership/proof retained completion')
    end
    toolkit.ActionQueuePolicy=policy
    for _,name in ipairs({'toolkitCancel','toolkitStopIntent','toolkitOutcomeWait','toolkitResume','toolkitOperationsInvalid'})do
        prepare('completed');queue[name]={};assert(not permitted(),'private finish-step capability overrode '..name)
    end
    for _,name in ipairs({'dead','asleep','cancel','moving','input','running','sprinting','aiming'})do
        prepare('completed');action.stopOnWalk,action.stopOnRun,action.stopOnAim=true,true,true
        actor[name]=true;assert(not permitted(),'private finish-step capability overrode native '..name)
    end
    prepare('completed');actor.localPlayer=false;assert(not permitted(),'foreign actor retained finish-step completion')
    prepare('completed');enabled=false;assert(not permitted());enabled=true
    assert(not permitted(),'feature re-enable revived a revoked finish-step capability')
    prepare('completed');Lifecycle.reset(queue);assert(not permitted(),'lifecycle reset retained canceled finish-step completion')
    prepare('completed');Lifecycle.finish(action,'perform',true)
    assert(not permitted(),'native callback finish retained a reusable cancellation capability')
    prepare('completed');Lifecycle.started({character=actor,action={}})
    assert(not permitted(),'a different native start retained an older cancellation capability')
    prepare('completed');Lifecycle.requestStop(queue,action,'cancel','operation')
    assert(not permitted(),'explicit stop retained finish-step completion')
    assert(stopped==1,'explicit stop lost its native forceStop')
    toolkit.ActionQueuePolicy=previousPolicy
end
print("Action queue lifecycle checks passed (SP effects, MP callback tail, sealed completion, explicit stops, native removal, failures, reset, ownership, disabled).")

-- A broken read-only integration cannot replay or abort the native callback.
local calls, nativeEffects = 0, 0
local callbacks = {begin = function() calls = calls + 1; error('observer failure') end}
assert(Lifecycle.registerObserver('failure-isolation', callbacks))
callbacks.begin = function() error('registration must snapshot callbacks') end
assert(not Lifecycle.registerObserver('failure-isolation', {}))
queue, action, present = fixture()
assert(Lifecycle.begin(action, 'perform'))
nativeEffects = nativeEffects + 1
queue:onCompleted(action)
Lifecycle.finish(action, 'perform', true)
assert(Lifecycle.begin(action, 'complete'))
Lifecycle.finish(action, 'complete', true)
present[action.action] = nil
assert(Lifecycle.flush(queue) == 'completed' and calls == 1 and nativeEffects == 1,
    'a failed observer is quarantined while native execution continues exactly once')

-- Native callback pairing stays observable in queue-off controls. Accepting an
-- observation never creates a pending completion owner or advances native work.
local observed = {}
assert(Lifecycle.registerObserver('native-control-observer', {
    begin = function(value, phase)
        if value.observeControl then observed[#observed + 1] = 'begin:' .. phase; return true end
    end,
    finish = function(value, phase, succeeded)
        if value.observeControl then observed[#observed + 1] = 'finish:' .. phase .. ':' .. tostring(succeeded) end
    end,
}))
enabled = false
queue, action, present = fixture(); action.observeControl = true
for _, phase in ipairs({'perform', 'complete'}) do
    assert(Lifecycle.begin(action, phase), 'accepted observation must receive its matching native finish callback')
    assert(not Lifecycle.deferCompletion(queue, action) and not Lifecycle.current(action.character),
        'queue-off observation cannot claim native scheduler completion')
    Lifecycle.finish(action, phase, true)
end
assert(#observed == 4 and observed[1] == 'begin:perform' and observed[4] == 'finish:complete:true')
assert(Lifecycle.flush(queue) == nil and queue.started == 0)
queue, action, present = fixture()
assert(not Lifecycle.begin(action, 'perform'), 'unobserved queue-off work must retain the native boundary')
enabled = true


-- Turning off the editor cannot discard a native completion already admitted
-- while it was on. It does not grant disabled work a new completion owner.
do
    local function paid(when)
        enabled,client=true,false
        local q,a,exists=fixture()
        assert(Lifecycle.begin(a,'perform'))
        q:onCompleted(a)
        if when=='during-perform'then enabled=false end
        Lifecycle.finish(a,'perform',true)
        if when=='after-perform'then enabled=false end
        assert(Lifecycle.begin(a,'complete'),'admitted SP complete lost its matching phase after disabling')
        Lifecycle.finish(a,'complete',true)
        if when=='after-complete'then enabled=false end
        assert(not Lifecycle.begin({character=a.character,action={}},'perform'),'foreign callback acquired the disabled queue')
        exists[a.action]=nil
        assert(Lifecycle.deferredAction(q)==nil,'disabled editor acquired deferred edit rights')
        assert(Lifecycle.flush(q)=='completed'and q.started==1,'disabling discarded an already-paid completion')
        assert(Lifecycle.flush(q)==nil and q.started==1,'paid completion replayed')
    end
    for _,when in ipairs({'during-perform','after-perform','after-complete'})do paid(when)end
    enabled=false
    local q,a=fixture()
    assert(not Lifecycle.begin(a,'perform')and not Lifecycle.deferCompletion(q,a),'fresh disabled work acquired an episode')
    q:onCompleted(a)
    assert(q.started==1 and Lifecycle.flush(q)==nil,'fresh disabled work lost native advancement')
    enabled=true
end

-- A native/reset boundary during a callback revokes that exact episode. Even
-- a nested new episode on the same Lua table cannot consume the old finish.
do
    enabled,client=true,true
    for _,change in ipairs({'native','generation','reset','death'})do
        local q,a,exists=fixture()
        a.character.isDead=function(self)return self.dead==true end
        assert(Lifecycle.begin(a,'perform'));q:onCompleted(a)
        enabled=false
        if change=='native'then a.action={}
        elseif change=='generation'then q.toolkitOperationGeneration=1
        elseif change=='reset'then Lifecycle.reset(q)
        else a.character.dead=true end
        assert(not Lifecycle.completionEntered(q,a),change..' transferred completion classification')
        Lifecycle.finish(a,'perform',true)
        exists[a.action]=nil
        assert(Lifecycle.flush(q)~='completed'and q.started==0,change..' transferred an old episode')
        assert(not Lifecycle.deferCompletion(q,a),change..' retained an old completion owner')
        Lifecycle.reset(q);enabled=true
    end
    local q,a,exists=fixture()
    assert(Lifecycle.begin(a,'perform'));q:onCompleted(a)
    enabled=false;Lifecycle.reset(q);a.action={};exists[a.action]=true
    assert(not Lifecycle.begin(a,'complete'),'reset transferred SP complete into a disabled new native action')
    enabled=true
    assert(Lifecycle.begin(a,'perform'));q:onCompleted(a)
    -- Complete the nested replacement before the failed old callback returns.
    Lifecycle.finish(a,'perform',true)
    Lifecycle.finish(a,'perform',false)
    exists[a.action]=nil
    assert(Lifecycle.flush(q)=='completed'and q.started==1,'old failure poisoned the independent new episode')
    Lifecycle.reset(q)
end

-- Exercise the unchanged native Base.perform/onCompleted/tick algorithms and
-- current Toolkit wrappers. Java removal and paid effects are explicit doubles.
if NativeActionRoot then
    local f=assert(loadfile(root..'/tests/support/action_queue_native.lua'))()
    local settings,remote=true,false
    isClient=function()return remote end
    PZSurvivorToolkit.Settings.actionQueue=function()return settings end
    ISLogSystem={logAction=function()end}
    DebugType={Action={warn=function()end}}
    local toolkit=PZSurvivorToolkit
    local lifecycle=f.project('ActionQueueLifecycle')
    local function read(path)
        if NativeReadText then return NativeReadText(path)end
        local file=assert(io.open(path));local source=file:read('*a');file:close();return source
    end
    local source=read(root..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueue.lua')
    local update=assert(source:match('(local function updateOperationState%(queue%).-Queue.updateOperationState = updateOperationState)'))
    local completed=assert(source:match('(local completed = ISTimedActionQueue.onCompleted.-\nend)\n\nfunction Queue.move'))
    local tick=assert(source:match('(local tick = ISTimedActionQueue.tick.-\nend)\n\nQueue.label'))
    assert(loadstring('local Toolkit=...;local Queue,Operations,Policy={},{},{skipUnavailableHygiene=function()end};local Batch;'
        ..'local function live(q)return not q.character:isDead()end;local function processPriority()end;'
        ..'local function clearStop()end;local function craft()return false end;'
        ..update..'\n'..completed..'\n'..tick))(toolkit)
    for _,mode in ipairs({'sp','host'})do
        for _,when in ipairs(mode=='sp'and {'control','disabled-start','during-perform','after-perform','after-complete'}or {'control','disabled-start','during-perform','after-perform'})do
            settings,remote=when~='disabled-start',mode=='host'
            local player=f.player;player.present={};player.setIsFarming=function()end
            player.getCharacterActions=function()return {contains=function(_,native)return player.present[native]end}end
            local parent=f.action(ISBaseTimedAction,{maxTime=1,Type='PaidParent'})
            local tail=f.action(ISBaseTimedAction,{maxTime=1,Type='IndependentTail'})
            local effects,starts,cancels=0,0,0
            tail.begin=function(self)
                starts=starts+1;self.action={isStarted=function()return true end,hasStalled=function()return false end}
                player.present[self.action]=true
            end
            tail.forceCancel=function()cancels=cancels+1 end
            parent.action={isStarted=function()return true end};player.present[parent.action]=true
            parent.perform=function(self)
                effects=effects+1
                if when=='during-perform'then settings=false end
                ISBaseTimedAction.perform(self)
            end
            parent.complete=function()effects=effects+10;return true end
            local q=f.queue(parent,tail)
            local admitted=lifecycle.begin(parent,'perform')
            assert(admitted==(when~='disabled-start'),'fresh disabled native callback acquired an episode')
            parent:perform();if admitted then lifecycle.finish(parent,'perform',true)end
            assert(when=='disabled-start'and q.current==tail and starts==1 or q.current==parent and starts==0,
                'native paid callback did not follow its admitted/native path')
            if when=='after-perform'then settings=false end
            if mode=='sp'then
                local paired=lifecycle.begin(parent,'complete')
                assert(paired==(when~='disabled-start'),'native complete did not follow its admitted/native path')
                parent:complete();if paired then lifecycle.finish(parent,'complete',true)end
            end
            if when=='after-complete'then settings=false end
            player.present[parent.action]=nil
            q:tick();q:tick()
            assert(effects==(mode=='sp'and 11 or 1)and starts==1 and cancels==0 and #q.queue==1 and q.current==tail,
                mode..' '..when..': disabling lost/replayed paid effects or discarded the independent native tail')
        end
    end
    print('Admitted lifecycle toggle checks passed with native perform/onCompleted/tick (SP and Host callback topology).')
else
    print('Admitted lifecycle native toggle checks SKIP (requires --game).')
end
