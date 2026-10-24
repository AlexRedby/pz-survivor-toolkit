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
    local character = {getCharacterActions = function() return {contains = function(_, action) return present[action] end} end}
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
local expanded = 0
local command = {args = {}, beginAddingActions = function() end, endAddingActions = function() return false end,
    addActionsFunction = function() expanded = expanded + 1 end, forceComplete = function(self) self.completed = true end}
ISQueueActionsAction.start(command)
assert(expanded == 1 and command.completed and not command.nativeStopped, "empty expansion cleared independent work")
command.completed = false
command.addActionsFunction = function() error("command failure") end
assert(not pcall(ISQueueActionsAction.start, command) and not command.completed, "command failure became successful completion")
enabled = false
ISQueueActionsAction.start(command)
assert(command.nativeStopped, "disabled queue changed native empty-command semantics")
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
assert(not permitted(),'missing receipt became a completed native transaction')
for _,terminal in ipairs({'canceled','rejected'})do
    ack.reset(queue);serial=serial+1;deliver('started');deliver(terminal)
    assert(not permitted(),terminal..' receipt became completion')
end
ack.reset(queue);serial=serial+1;deliver('started')
assert(not permitted(),'a started transaction became completion')
deliver('completed');assert(permitted(),'owned sealed completed transaction was refused')
assert(not Lifecycle.allowNativeCompletion(action,{}),'another native object acquired completion')
for _,name in ipairs({'toolkitCancel','toolkitStopIntent','toolkitOutcomeWait','toolkitGroupCancel',
    'toolkitResume','toolkitOperationsInvalid'})do
    queue[name]={};assert(not permitted(),name..' was overridden');queue[name]=nil
end
action.toolkitQueueOperation.toolkitCancelled=true;assert(not permitted());action.toolkitQueueOperation.toolkitCancelled=nil
for _,name in ipairs({'dead','cancel'})do actor[name]=true;assert(not permitted(),name..' was overridden');actor[name]=nil end
actor.localPlayer=false;assert(not permitted());actor.localPlayer=nil
for _,entry in ipairs({{'stopOnWalk','moving'},{'stopOnWalk','input'},{'stopOnRun','running'},
    {'stopOnRun','sprinting'},{'stopOnAim','aiming'}})do
    action[entry[1]],actor[entry[2]]=true,true;assert(not permitted(),'native input cancellation was overridden')
    action[entry[1]]=false;assert(permitted(),'a non-stopping input blocked paid completion')
    action[entry[1]],actor[entry[2]]=nil,nil
end
enabled=false;assert(not permitted());enabled=true
client=false;assert(not permitted());client=true
queue.current={};assert(not permitted());queue.current=action
queue.queue[1]={};assert(not permitted());queue.queue[1]=action
assert(permitted())
queue.toolkitOperationGeneration=(queue.toolkitOperationGeneration or 0)+1
assert(not permitted(),'a stale queue generation acquired completion')
queue.toolkitOperationGeneration=queue.toolkitOperationGeneration-1
assert(permitted())
ack.reset(queue);assert(not permitted(),'queue reset revived a retained completed receipt')
print("Action queue lifecycle checks passed (SP effects, MP callback tail, sealed completion, explicit stops, native removal, failures, reset, ownership, disabled).")
