if not NativeQuartermasterLuaRoot then
    print('SKIP Quartermaster sync: actual upstream Lua sources required.')
    return
end

local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/'
local loaded = {}
require = function(name)
    if name:sub(1, 13) == 'TimedActions/' then return {} end
    if not loaded[name] then loaded[name] = assert(loadfile(root .. 'shared/' .. name .. '.lua'))() end
    return loaded[name]
end
local clock, enabled, client = 0, true, true
isClient = function() return client end
isServer = function() return false end
getTimestampMs = function() return clock end
PZSurvivorToolkit = {Settings = {itemTags = function() return enabled end}}
Events = {}
for _, name in ipairs({'OnGameStart', 'OnCreatePlayer', 'OnObjectAdded', 'OnServerCommand',
    'OnTick', 'OnReceiveGlobalModData'}) do
    local event = {handlers = {}}
    event.Add = function(fn) event.handlers[#event.handlers + 1] = fn end
    event.Remove = function(fn)
        for index = #event.handlers, 1, -1 do
            if event.handlers[index] == fn then table.remove(event.handlers, index) end
        end
    end
    Events[name] = event
end
local function fire(name, ...)
    local handlers = {unpack(Events[name].handlers)}
    for _, fn in ipairs(handlers) do fn(...) end
end
local requests, moddata = {}, {}
ModData = {
    request = function(key) requests[key] = (requests[key] or 0) + 1 end,
    getOrCreate = function(key) moddata[key] = moddata[key] or {}; return moddata[key] end,
}
local function list(values)
    return {size = function() return #values end, get = function(_, index) return values[index + 1] end}
end
local square = {getX = function() return 10 end, getY = function() return 20 end, getZ = function() return 0 end}
local player = {getCurrentSquare = function() return square end}
getSpecificPlayer = function() return player end
local container = {}
local object = {md = {}, hasModData = function() return true end, getSquare = function() return square end,
    getContainerCount = function() return 1 end, getContainerByIndex = function() return container end}
object.getModData = function(self) return self.md end
local objectTransmits, removals = 0, 0
object.transmitModData = function() objectTransmits = objectTransmits + 1 end
square.getObjects = function() return list({object}) end
getCell = function() return {getGridSquare = function(_, x, y, z)
    if x == 10 and y == 20 and z == 0 then return square end
end} end
LootSorter = {DBG = function() end, SYNC_RETRY_MS = 4000,
    getCategories = function() return {'Food'} end,
    canLootSquare = function() return true end,
    removeCoords = function() removals = removals + 1 end,
    parseCoordKey = function(key)
        local x, y, z = key:match('^(%d+),(%d+),(%d+)$')
        return tonumber(x), tonumber(y), tonumber(z)
    end}
for _, file in ipairs({'shared/LootSorter_Util.lua', 'shared/LootSorter_Presets.lua',
    'client/LootSorter_PresetSync.lua', 'client/LootSorter_Core.lua'}) do
    dofile(NativeQuartermasterLuaRoot .. '/' .. file)
end
local Rules = require 'PZSurvivorToolkit/QuartermasterTagRules'
local synced, request = LootSorter.arePresetsSynced, LootSorter.requestPresets
dofile(root .. 'client/PZSurvivorToolkit/QuartermasterTagRuleClient.lua')
assert(LootSorter.arePresetsSynced == synced and LootSorter.requestPresets == request,
    'tag client replaced owned preset synchronization')
local rule = {mode = 'all', include = {'food'}, exclude = {}}
local function begin()
    client, enabled, clock = true, true, clock + 10000
    object.md = {LSBoxPresets = {['0'] = {Pantry = 100}}}
    fire('OnGameStart')
    fire('OnReceiveGlobalModData', 'LootSorter_Registry', {boxes = {['10,20,0'] = true}})
    requests, objectTransmits, removals = {}, 0, 0
end
local function native()
    fire('OnReceiveGlobalModData', 'LootSorter_Presets',
        {presets = {Pantry = {cats = {}, items = {}, gen = 100, rev = 1}}})
end
local function toolkit(presets)
    fire('OnReceiveGlobalModData', Rules.STORE, {presets = presets or {Pantry = {gen = 100, rule = rule}}})
end
local function bothRequested()
    assert((requests.LootSorter_Presets or 0) > 0 and (requests[Rules.STORE] or 0) > 0,
        'native retry did not request both preset stores')
end
local function waiting()
    local boxes, synced = LootSorter.gatherBoxes(player)
    assert(#boxes == 0 and synced == false, 'partially received presets reported fully synced')
    assert(LootSorter.gatherBoxesOrWarn(player) == nil, 'native private gather bypassed readiness')
    assert(object.md.LSBoxPresets['0'].Pantry == 100 and objectTransmits == 0 and removals == 0,
        'waiting for rules pruned a designation')
    bothRequested()
end
for _, nativeFirst in ipairs({true, false}) do
    begin()
    if nativeFirst then native() else toolkit() end
    waiting()
    -- The existing native gather retry must keep requesting both stores while either is missing.
    requests = {}
    waiting()
    requests = {}
    clock = clock + LootSorter.SYNC_RETRY_MS
    fire('OnTick')
    bothRequested()
    if nativeFirst then toolkit() else native() end
    local boxes, synced = LootSorter.gatherBoxes(player)
    assert(synced and #boxes == 1 and Rules.matches(boxes[1], {cat="Food", ref={getDisplayCategory=function() return "Food" end}}) and boxes[1].container == container,
        'both arrival orders must restore the tag-only preset destination')
end

begin(); native(); toolkit({})
object.md.LSBox = {['0'] = {Manual = true}}
local boxes, synced = LootSorter.gatherBoxes(player)
assert(synced and #boxes == 1 and boxes[1].cats.Manual, 'empty valid Toolkit reply blocked native selections')

-- Object-local rules do not depend on having an entry in the preset sidecar.
object.md = {[Rules.FIELD] = {['0'] = rule}}
boxes, synced = LootSorter.gatherBoxes(player)
assert(synced and #boxes == 1 and Rules.matches(boxes[1], {cat="Food", ref={getDisplayCategory=function() return "Food" end}}) and LootSorter.squareHasDesignation(square),
    'readiness gating lost a rule-only container designation')

begin(); native(); enabled = false
object.md.LSBox = {['0'] = {Manual = true}}
boxes, synced = LootSorter.gatherBoxes(player)
assert(synced and #boxes == 1 and boxes[1].cats.Manual and not Rules.presetsSynced(),
    'disabled tags must retain native readiness without a Toolkit reply')
LootSorter._receivedPresets = nil
boxes, synced = LootSorter.gatherBoxes(player)
assert(not synced and #boxes == 0, 'disabled tags bypassed native readiness')
client = false
assert(LootSorter.arePresetsSynced(), 'single-player acquired a network prerequisite')
print('Quartermaster sync passed: real Core/PresetSync, both arrival orders, native retry, empty reply, local rules and opt-out.')
