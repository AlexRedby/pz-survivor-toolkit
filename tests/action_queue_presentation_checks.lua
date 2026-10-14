-- Loaded by the labels suite with actual EN/RU translation dictionaries.
local definitions = PZSurvivorToolkit.ActionQueueDefinitions
local labels = PZSurvivorToolkit.ActionQueueLabels
local nativeCount = 0
for id, entry in pairs(definitions.entries) do
    if id:sub(1, 7) == 'native.' then
        nativeCount = nativeCount + 1
        assert(entry.presentation and not entry.behavior, 'presentation must not grant behavior')
        for _, kind in ipairs(entry.types) do
            local action = {Type = kind}
            local title = labels.title(action)
            assert(title ~= '' and not title:find(kind, 1, true), 'native technical title: ' .. kind)
            assert(not title:find('%%[1-9]'), 'native unresolved title arguments: ' .. kind)
            if NativeActionRoot then
                for _, language in ipairs({'EN', 'RU'}) do
                    local translations = ActionQueueTranslations[language]
                    assert(translations[entry.presentation.key], language .. ': missing ' .. entry.presentation.key)
                    for _, key in pairs(entry.presentation.modes or {}) do
                        assert(translations[key], language .. ': missing mode ' .. key)
                    end
                end
            end
            assert(definitions.inspect(action) == nil)
        end
    end
end
assert(nativeCount == 278, 'explicit native presentation count must match audited catalog')

local descriptor = {key = 'UI_PZSurvivorToolkit_queue_action_walk'}
definitions.register('test.late', {types = {'LateAction'}, presentation = descriptor})
assert(definitions.resolve({Type = 'LateAction'}) == descriptor)
assert(definitions.behavior({Type = 'LateAction'}) == nil)
local safe = {Type = 'LateAction', verified = true}
local behavior = {matches = function(action) return action == safe end,
    inspect = function() return {resources = {}} end}
definitions.registerBehavior('test.late.behavior', behavior)
assert(definitions.inspect(safe).resources)
assert(definitions.inspect({Type = 'LateAction'}) == nil, 'Type match must not grant a contract')
definitions.registerBehavior('test.ambiguous', {matches = function(action) return action == safe end,
    inspect = function() error('ambiguous inspector must not run') end})
assert(definitions.inspect(safe) == nil, 'ambiguous behavior must fail closed')
assert(not pcall(definitions.register, 'test.duplicate', {types = {'LateAction'}, presentation = {key = 'x'}}))
assert(not pcall(definitions.register, 'test.late', {types = {'LateAction'}, presentation = {key = 'x'}}))
assert(not pcall(definitions.registerBehavior, 'test.invalid', {matches = function() return true end}))

getTexture = function(path) return path end
local function item(text)
    return {class = 'InventoryItem', getDisplayName = function() return text end,
        getTex = function() return text .. ' icon' end}
end
local vehicle = {class = 'BaseVehicle', getScript = function()
    return {getName = function() return 'Car' end, getCarModelName = function() return 'Car' end}
end}
local part = {class = 'VehiclePart', getId = function() return 'Engine' end,
    getVehicle = function() return vehicle end}
local wreck = {Type = 'ISRemoveBurntVehicle', vehicle = vehicle, item = item('Blowtorch')}
assert(not labels.label(wreck):find('Blowtorch', 1, true), 'tool must not replace vehicle target')
assert(not labels.icon(wreck):find('Blowtorch', 1, true), 'tool must not replace vehicle icon')
assert(labels.icon({Type = 'ISWalkToTimedActionF'}):find('Walking', 1, true))
assert(labels.icon({Type = 'ISRadioAction', device = item('Radio')}) == 'Radio icon')
local repair = labels.label({Type = 'ISFixVehiclePartAction', vehiclePart = part, item = item('Donor')})
assert(repair:find(getText('IGUI_VehiclePartEngine'), 1, true) and repair:find(getText('IGUI_VehicleNameCar'), 1, true) and not repair:find('Donor', 1, true))
assert(labels.title({Type = 'ISApplyBandage', doIt = true}) ~= labels.title({Type = 'ISApplyBandage', doIt = false}))
assert(labels.title({Type = 'ISStitch', doIt = true}) ~= labels.title({Type = 'ISStitch', doIt = false}))
assert(labels.title({Type = 'ISSplint', doIt = true}) ~= labels.title({Type = 'ISSplint', doIt = false}))
assert(labels.title({Type = 'ISActivateGenerator', activate = true}) ~= labels.title({Type = 'ISActivateGenerator', activate = false}))
assert(labels.title({Type = 'ISLightActions', mode = 'AddLightBulb'}) ~= labels.title({Type = 'ISLightActions', mode = 'RemoveLightBulb'}))
assert(labels.preparation({Type = 'PJCK_SequenceWaitAction'}))
assert(labels.preparation({Type = 'P4RestoreFloorAction'}))
assert(definitions.inspect({Type = 'P4RestoreFloorAction'}) == nil)
local token = {}
local craft = {Type = 'ISHandcraftAction', toolkitQueueOperation = token}
local transfer = {Type = 'ISInventoryTransferAction', toolkitQueueOperation = token}
local queue = {queue = {craft, transfer}}
local title = definitions.taskTitle(queue, 1, 2, true)
queue.queue = {transfer}
assert(definitions.taskTitle(queue, 1, 1, true) == title, 'return keeps original operation identity')
queue.queue = {craft, {Type = 'ISReadABook', toolkitQueueOperation = token}, transfer}
assert(definitions.taskTitle(queue, 1, 3, true) ~= title, 'adding main work updates mixed title')
local errorItem = {class = 'InventoryItem', getDisplayName = function() error('deleted item') end,
    getTex = function() error('removed texture') end}
assert(labels.label({Type = 'ISInventoryTransferAction', item = errorItem}))
assert(labels.icon({Type = 'ISInventoryTransferAction', item = errorItem}):find('Icon_Tools', 1, true))
local callbackDescriptor = {key = 'UI_PZSurvivorToolkit_queue_action_walk',
    title = function() return 'Custom title', 'custom' end,
    target = function() return 'Custom target' end,
    icon = function() return 'custom-icon' end,
    details = function() return 'Custom detail' end}
definitions.register('test.callbacks', {types = {'CustomPresentation'}, presentation = callbackDescriptor})
assert(labels.label({Type = 'CustomPresentation'}) == 'Custom title: Custom target')
assert(labels.icon({Type = 'CustomPresentation'}) == 'custom-icon')
assert(labels.describe({Type = 'CustomPresentation'}).details == 'Custom detail')
assert(definitions.inspect({Type = 'CustomPresentation'}) == nil)
definitions.registerBehavior('test.matchError', {matches = function() error('removed object') end,
    inspect = function() error('must not run') end})
assert(definitions.inspect({Type = 'CustomPresentation'}) == nil)
local explanation = labels.decisionDetails({allowed = false,
    blocker = {Type = 'ISReadABook'}, resource = item('Shared item')})
assert(explanation:find('Shared item', 1, true))
assert(labels.decisionDetails({allowed = true, blocker = {Type = 'ISReadABook'}}) == nil)
assert(labels.decisionDetails({allowed = false, resource = 'private-resource-id'}) == nil)
assert(not labels.priorityWaiting('private-developer-state'):find('private-developer-state', 1, true))
assert(labels.title({Type = 'PZSurvivorToolkitSetStoveState', desired = true})
    ~= labels.title({Type = 'PZSurvivorToolkitSetStoveState', desired = false}))
print('Action queue presentation registry/278 native labels checks passed.')
