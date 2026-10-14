if not NativeActionRoot then print('Set stove state native checks skipped (pass --native-action-root media/lua).'); return end
require = function() end
local function derive(self, name)
    local class = {Type = name, derive = derive}; class.__index = class
    return setmetatable(class, {__index = self})
end
ISBaseObject = {derive = derive}
assert(loadfile(NativeActionRoot .. '/shared/TimedActions/ISBaseTimedAction.lua'))()
assert(loadfile(NativeActionRoot .. '/shared/TimedActions/ISToggleStoveAction.lua'))()
local path = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SetStoveStateAction.lua'
assert(loadfile(path))()
local state = PZSurvivorToolkitSetStoveState
instanceof = function(value, name) return value and value.class == name end
local function square(x, y, z)
    return {getX = function() return x end, getY = function() return y end, getZ = function() return z end,
        canReachTo = function(self) return self.reachable ~= false end}
end
local current = square(10, 10, 0)
local player = {isDead = function(self) return self.dead == true end,
    getCurrentSquare = function(self) return self.square end,
    isTimedActionInstant = function() return false end, square = current}
local stove = {class = 'IsoStove', square = square(11, 11, 0), active = false, toggles = 0,
    container = {isPowered = function(self) return self.powered ~= false end}}
function stove:getSquare() return self.square end
function stove:getObjectIndex() return self.removed and -1 or 0 end
function stove:getContainer() return self.container end
function stove:Activated() return self.active end
function stove:Toggle() self.active = not self.active; self.toggles = self.toggles + 1 end
local action = state:new(player, stove, true)
assert(getmetatable(action) == state and action.character == player and action.object == stove and action.desired == true)
assert(action.maxTime == ISToggleStoveAction.getDuration(action) and action.perform == ISToggleStoveAction.perform,
    'native duration/perform ordering remains inherited')
assert(action:isValid() and action:complete() and stove.active and stove.toggles == 1)
assert(action:complete() and stove.toggles == 1, 'duplicate server completion is a no-op')
local off = state:new(player, stove, false)
assert(off.desired == false and off:isValid() and off:complete() and not stove.active and stove.toggles == 2)
off:complete(); assert(stove.toggles == 2)
-- Another player's intervening update already reaching the requested state must not toggle it away.
stove.active = true; action:complete(); assert(stove.active and stove.toggles == 2)
local function reject(change, restore, desired)
    change()
    local invalid = state:new(player, stove, desired == nil and true or desired)
    local count = stove.toggles
    assert(not invalid:isValid() and invalid:complete() and stove.toggles == count, 'invalid state must not change authority')
    restore()
end
reject(function() stove.container.powered = false end, function() stove.container.powered = true end)
stove.container.powered = false
assert(off:isValid() and off:complete() and not stove.active, 'switching off stays valid when power is unavailable')
stove.container.powered = true
reject(function() stove.removed = true end, function() stove.removed = false end)
reject(function() stove.class = 'IsoObject' end, function() stove.class = 'IsoStove' end)
reject(function() player.dead = true end, function() player.dead = false end)
reject(function() player.square = nil end, function() player.square = current end)
reject(function() stove.square = nil end, function() stove.square = square(11, 11, 0) end)
reject(function() stove.square = square(10, 10, 1) end, function() stove.square = square(11, 11, 0) end)
reject(function() stove.square = square(12, 10, 0) end, function() stove.square = square(11, 11, 0) end)
reject(function() current.reachable = false end, function() current.reachable = true end)
local invalid = state:new(player, stove, 'true')
assert(not invalid:isValid() and invalid:complete())
local source
if NativeReadText then source = NativeReadText(path)
else local file = assert(io.open(path)); source = file:read('*a'); file:close() end
assert(source:match('function PZSurvivorToolkitSetStoveState:new%(character, object, desired%)'),
    'NetTimedAction constructor keeps formal parameter names for native serialization')
assert(state:new(player, stove, false).desired == false, 'false constructor argument is retained for native serialization')
print('Set stove state native contract: formal arguments, inherited perform/duration, server no-op, target, range, reachability, life and power passed.')
