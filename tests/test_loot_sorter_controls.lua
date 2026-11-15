-- The native game mode is an object in 42.22; a string comparison exposes controls in Tutorial.
require = function() end
GameMode = {TUTORIAL = {}, SANDBOX = {}}
local mode = GameMode.SANDBOX
getCore = function() return {getGameMode = function() return mode end} end
local base = {}
function base:derive(name) return setmetatable({Type = name}, {__index = self}) end
ISInventoryWindowControlHandler = base
ISLootWindowObjectControlHandler = base
ISLootWindowFloorControlHandler = base
local registered = {}
local function register(handler) registered[#registered + 1] = handler end
ISInventoryWindowContainerControls = {AddHandler = register}
ISLootWindowContainerControls = {AddHandler = register, AddFloorHandler = register}
dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/LootSorter_DistributeButton.lua')
for _, handler in ipairs(registered) do
    local empty = false
    local control = setmetatable({container = {isEmpty = function() return empty end}}, {__index = handler})
    assert(control:shouldBeVisible(), 'Sandbox inventory must offer distribution')
    mode = GameMode.TUTORIAL
    assert(not control:shouldBeVisible(), 'Tutorial must hide distribution')
    mode = GameMode.SANDBOX
    empty = true
    assert(not control:shouldBeVisible(), 'Empty container must hide distribution')
    control.container = nil
    assert(not control:shouldBeVisible(), 'Absent container must hide distribution')
end
assert(#registered == 3, 'Every inventory, object and floor control must be covered')
