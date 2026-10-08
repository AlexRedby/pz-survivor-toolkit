local adapter = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ManageContainers.lua'
local active, starts, callbacks = {}, {}, {}
getActivatedMods = function() return {contains=function(_, id) return active[id] end} end
Events = {OnGameStart={Add=function(callback) starts[#starts+1] = callback end}}
local function registry()
    local list = {}
    return {list=list, AddHandler=function(handler)
        for index, existing in ipairs(list) do
            if existing.Type == handler.Type then list[index] = handler; return end
        end
        list[#list+1] = handler
    end}
end
local original = {Type='ISInventoryWindowControlHandler_TransferAssignedContainers',
    getControl=function() return 'original image' end,
    shouldBeVisible=function() return 'original visibility' end,
    perform=function() return 'original transfer' end}
ISInventoryWindowControlHandler_TransferAssignedContainers = original
local enhanced = registry()
ISInventoryWindowContainerControls = enhanced
for _, selection in ipairs({{}, {CleanUI=true}, {manageContainers=true}}) do
    active = selection
    dofile(adapter)
    assert(#starts == 0 and #enhanced.list == 0)
end
active = {CleanUI=true, manageContainers=true}
require = function(name)
    assert(name == 'CleanUI/Vanilla/CleanUI_Vanilla_ISInventoryWindowContainerControls')
    CleanUI_Vanilla_ISInventoryWindowContainerControls = registry()
end
CleanUI_RegisterInventoryUiToggleCallback = function(callback)
    callbacks[#callbacks+1] = callback
    callback(true)
end
dofile(adapter)
assert(#starts == 1 and #enhanced.list == 0)
starts[1]()
local vanilla = CleanUI_Vanilla_ISInventoryWindowContainerControls
assert(#enhanced.list == 1 and enhanced.list[1] == original)
assert(#vanilla.list == 1 and vanilla.list[1] == original)
CleanUI_Clean_ISInventoryWindowContainerControls = enhanced
ISInventoryWindowContainerControls = vanilla
callbacks[1](false)
callbacks[1](true)
assert(#enhanced.list == 1 and #vanilla.list == 1)
assert(original:getControl() == 'original image')
assert(original:shouldBeVisible() == 'original visibility')
assert(original:perform() == 'original transfer')
print('Manage Containers registry compatibility checks passed')
