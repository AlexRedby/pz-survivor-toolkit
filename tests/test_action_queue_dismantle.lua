if not NativeActionRoot then print('Native dismantle lifecycle SKIP (pass --native-action-root).'); return end
local f = assert(loadfile(ProjectRoot .. '/tests/support/action_queue_native.lua'))()
f.native('shared/Moveables/ISMoveablesAction.lua')
local callbacks = {}
Events.OnGameStart.Add = function(callback) callbacks[#callbacks + 1] = callback end
Events.OnServerCommand = {Add = function() end}
isClient, isServer = function() return false end, function() return false end
ISBuildingObject, ISMoveableCursor = {tryBuild = function() end}, {create = function() end}
ISDisassembleMenu, ISWorldObjectContextMenu = {disassemble = function() end}, {}
ISMoveableDefinitions = {cheat = true}
ISMoveableSpriteProps = {fromObject = function(object) return object.moveProps end}
ISInventoryPage.OnObjectHighlighted = function() end
ISLogSystem, DebugType = {logAction = function() end}, {Action = {warn = function() end}}
LuaTimedActionNew = {new = function() return {isStarted = function() return true end,
    finished = function() return false end, isForceComplete = function() return false end,
    hasStalled = function() return false end} end}
f.player.isMovablesCheat = function() return false end
f.player.setIsFarming, f.player.setTimedActionToRetrigger = function() end, function() end
f.player.StartAction = function(self, action) self.actions[action] = true end
f.player.getCharacterActions = function(self) return {contains = function(_, action) return self.actions[action] end} end
f.player.stopOrTriggerSound = function(self, sound) self.stoppedSound = sound end
f.project('ActionQueueOperations'); f.project('ActionQueueDefinitions'); f.project('ActionQueueLabels')
local policy = f.project('ActionQueuePolicy')
local nativeNew = ISMoveablesAction.new
f.project('ActionQueue'); f.project('ActionQueueWorld')
for _, callback in ipairs(callbacks) do callback() end
local world = PZSurvivorToolkit.ActionQueueWorld
assert(ISMoveablesAction.new ~= nativeNew, 'exercise the installed world constructor wrapper')

local function queueScrap()
    local object = {class = 'IsoObject', setHighlighted = function(self, _, highlighted) self.highlighted = highlighted end}
    object.moveProps = {object = object, spriteName = 'fixture'}
    local square = {getZ = function() return 0 end, getObjects = function() return {
        size = function() return object.gone and 0 or 1 end, get = function() return object end} end}
    f.player.getSquare = function() return square end
    local action = ISMoveablesAction:new(f.player, square, 'scrap', 'fixture', object, 'N', nil, nil)
    action.sound, action.action = 123, LuaTimedActionNew.new()
    local tail = ISBaseTimedAction.new(ISBaseTimedAction, f.player); tail.maxTime = 1
    local q = f.queue(action, tail)
    f.player.actions = {[action.action] = true}
    return q, action, tail, object
end

local q, action, tail, object = queueScrap()
assert(policy.inspect(action).interrupt == 'audited-stop', 'owned constructor wrapper must retain native contract')
object.gone = true
assert(world.targetGone(action) and not world.canResume(action))
assert(not policy.cancelReason(q, action), 'missing owned target still has an audited stop')
assert(not action:isValid() and q.toolkitCancel == action and #q.queue == 2)
assert(not object.highlighted and f.player.stoppedSound == 123, 'native scrap cleanup still runs')
action:stop(); q:tick()
assert(q.current == action and q.queue[2] == tail, 'duplicate stop waits for Java removal')
f.player.actions[action.action] = nil; q:tick()
assert(q.current == tail and #q.queue == 1 and f.player.actions[tail.action] and not q.toolkitCancel,
    'real policy and world lifecycle must retain and start unrelated tail')

for _, changed in ipairs({'new', 'update', 'complete', 'callback', 'moving', 'disabled', 'target'}) do
    q, action, tail, object = queueScrap(); object.gone = true
    local original
    if changed == 'new' or changed == 'update' or changed == 'complete' then
        original = ISMoveablesAction[changed]; ISMoveablesAction[changed] = function() end
    elseif changed == 'callback' then action.onCompleteFunc = function() end
    elseif changed == 'moving' then f.player.isPlayerMoving = function() return true end
    elseif changed == 'disabled' then PZSurvivorToolkit.Settings.actionQueue = function() return false end
    elseif changed == 'target' then action.object = {} end
    action:stop()
    assert(#q.queue == 0 and not q.toolkitCancel, changed .. ' must retain native abort boundaries')
    if original then ISMoveablesAction[changed] = original end
    f.player.isPlayerMoving = function() return false end
    PZSurvivorToolkit.Settings.actionQueue = function() return true end
end
assert(not policy.adoptMoveablesConstructor(function() end, ISMoveablesAction.new), 'foreign delegate cannot be adopted')
print('Native dismantle lifecycle: installed constructor, removed target, delayed Java removal and abort guards passed.')
