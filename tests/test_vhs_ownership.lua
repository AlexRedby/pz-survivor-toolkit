local source = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/TVMediaAction.lua"
local active = false
getActivatedMods = function() return {contains = function() return active end} end
require = function() end
local original = function(action) return action.nativeValid end
ISDeviceMediaAction = {isValid = original}
dofile(source)
assert(ISDeviceMediaAction.isValid == original, "disabled TV mod must not patch actions")
active = true
dofile(source)
local inventory, bag = {}, {}
local tape = {container = inventory, getContainer = function(self) return self.container end}
local action = setmetatable({secondaryItem = tape, nativeValid = true,
    character = {getInventory = function() return inventory end}}, {__index = ISDeviceMediaAction})
assert(action:isValid(), "owned tape must insert")
tape.container = bag
assert(not action:isValid(), "transfer must finish before insertion")
tape.container = inventory
assert(action:isValid())
tape.container = nil
assert(not action:isValid(), "tape taken while queued must not insert")
action.secondaryItem = nil
assert(not action:isValid())
action.isRemove = true
assert(action:isValid(), "ejection must retain native validity")
action.nativeValid = false
assert(not action:isValid(), "native device validity must remain enforced")
print("VHS ownership regression passed.")
