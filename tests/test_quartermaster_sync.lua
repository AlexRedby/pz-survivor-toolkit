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
LootSorter = {DBG = function() end, SYNC_RETRY_MS = 4000, RPC_TIMEOUT_MS = 15000, RPC_SWEEP_MS = 5000,
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
local Presets = require 'PZSurvivorToolkit/QuartermasterPresets'
local Groups = require 'PZSurvivorToolkit/ContainerGroups'
dofile(root .. 'client/PZSurvivorToolkit/ContainerGroupSync.lua')
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
    assert(Groups.receive({schema=1,revision=0,nextId=0,groups={}}))
    requests, objectTransmits, removals = {}, 0, 0
end
local function snapshot(revision, cats, tagRule, generation)
    return {schema = 1, revision = revision, presets = {Pantry = {
        cats = cats or {}, items = {}, gen = generation or 100, rev = revision + 1}},
        rules = {Pantry = {gen = generation or 100, rule = tagRule or rule}}}
end
local function receive(value)
    fire('OnReceiveGlobalModData', Presets.STORE, value)
end
local function requested()
    assert((requests[Presets.STORE] or 0) > 0 and requests.PZSTQuartermasterTagRules == nil,
        'retry must request only the complete preset snapshot')
end
local function waiting()
    local boxes, synced = LootSorter.gatherBoxes(player)
    assert(#boxes == 0 and synced == false, 'incomplete presets reported fully synced')
    assert(LootSorter.gatherBoxesOrWarn(player) == nil, 'private gather bypassed readiness')
    assert(object.md.LSBoxPresets['0'].Pantry == 100 and objectTransmits == 0 and removals == 0,
        'waiting for presets changed a designation')
    requested()
end
for _, nativeFirst in ipairs({true, false}) do
    begin()
    -- Old independent messages in either order cannot become the new authoritative snapshot.
    local function native() receive({presets = snapshot(0).presets}) end
    local function sidecar() fire('OnReceiveGlobalModData', 'PZSTQuartermasterTagRules', {presets = snapshot(0).rules}) end
    if nativeFirst then native(); sidecar() else sidecar(); native() end
    waiting()
    requests = {}; clock = clock + LootSorter.SYNC_RETRY_MS; fire('OnTick'); requested()
    receive(snapshot(0))
    local boxes, synced = LootSorter.gatherBoxes(player)
    assert(synced and #boxes == 1 and Rules.matches(boxes[1], {cat='Food', ref={getDisplayCategory=function() return 'Food' end}})
        and boxes[1].container == container, 'complete snapshot lost tag-only preset destination')
end

-- Replacing a snapshot cannot mix a new category with the old tag rule, nor alter an open draft.
local draftRule = rule
LootSorter._presetEditor = {presetName='Pantry', presetRev=1, presetGen=100,
    selectedCats={Original=true}, toolkitTagRule=draftRule}
LootSorter._picker = {}
local medical = {mode='all',include={'medical'},exclude={}}
local oldPresets, oldRules = LootSorter.getPresetStore(), Rules.presetStore()
receive(snapshot(1, {Electrical=true}, medical))
assert(LootSorter.arePresetsSynced() and LootSorter.getPresetStore().Pantry.rev == 2
    and LootSorter.getPresetStore().Pantry.cats.Electrical
    and Rules.getPreset('Pantry', LootSorter.getPresetStore().Pantry).include[1] == 'medical', 'mixed updated preset')
assert(oldPresets.Pantry.rev == 1 and oldRules.Pantry.rule.include[1] == 'food', 'new receipt mutated old snapshot')
assert(LootSorter._picker.needRebuild and LootSorter._presetEditor.toolkitTagRule == draftRule
    and LootSorter._presetEditor.selectedCats.Original and LootSorter._presetEditor.presetRev == 1,
    'receipt mixed an open editor draft with newer fields')
fire('OnReceiveGlobalModData', 'PZSTQuartermasterTagRules', {presets = snapshot(0).rules})
receive(snapshot(0)); receive(snapshot(1, {Stale=true}))
assert(LootSorter.getPresetStore().Pantry.cats.Electrical and Rules.presetStore().Pantry.rule.include[1] == 'medical',
    'old/duplicate/sidecar receipt changed a committed snapshot')
receive({schema=1,revision=2,presets={}})
assert(LootSorter.getPresetStore().Pantry.rev == 2, 'partial snapshot replaced coherent data')

-- Delete/recreate keeps old generation links inert without writing objects during discovery.
receive({schema=1,revision=2,presets={},rules={}})
local boxes, synced = LootSorter.gatherBoxes(player)
assert(synced and #boxes == 0 and object.md.LSBoxPresets['0'].Pantry == 100 and objectTransmits == 0,
    'deleted preset remained effective or scanning changed its links')
receive(snapshot(3, {}, rule, 200))
boxes, synced = LootSorter.gatherBoxes(player)
assert(synced and #boxes == 0 and object.md.LSBoxPresets['0'].Pantry == 100 and objectTransmits == 0,
    'recreated preset retargeted or pruned the old generation')

-- Empty snapshots are ready, object rules remain independent, and tags opt-out needs no sidecar.
receive({schema=1,revision=4,presets={},rules={}})
object.md = {[Rules.FIELD] = {['0'] = rule}}
boxes, synced = LootSorter.gatherBoxes(player)
assert(synced and #boxes == 1 and Rules.matches(boxes[1], {cat='Food', ref={getDisplayCategory=function() return 'Food' end}})
    and LootSorter.squareHasDesignation(square), 'empty presets lost a local rule')
begin(); enabled = false; waiting(); receive(snapshot(0))
object.md.LSBox = {['0'] = {Manual=true}}
boxes, synced = LootSorter.gatherBoxes(player)
assert(synced and #boxes == 1 and boxes[1].cats.Manual and Rules.presetsSynced(), 'disabled tags lost native selections')
begin(); waiting(); receive(snapshot(0))
assert(LootSorter.arePresetsSynced(), 'new world could not restart its revision sequence')
-- Registry and presets may precede the world group snapshot at login.
Groups.resetReceived(); requests = {}
boxes, synced = LootSorter.gatherBoxes(player)
assert(not synced and #boxes == 0 and requests[Groups.STORE] == 1 and objectTransmits == 0 and removals == 0,
    'sort planned before receiving the complete group snapshot')
assert(Groups.receive({schema=1,revision=0,nextId=0,groups={}}))
object.md[Groups.FIELD] = {['0']='1'}
object.md[Groups.REVISIONS] = {['0']=1}
boxes, synced = LootSorter.gatherBoxes(player)
assert(not synced and #boxes == 0 and requests[Groups.STORE] == 2 and objectTransmits == 0 and removals == 0,
    'a membership arriving before its group snapshot routed as an independent container')
assert(Groups.receive({schema=1,revision=1,nextId=1,groups={['1']={id='1',rev=1,createdBy='owner',rule=rule,
    configuration={cats={},items={},presets={},priority=7,noDuplicates=true,appearance={name='Group'}}}}}))
boxes, synced = LootSorter.gatherBoxes(player)
assert(synced and #boxes == 1 and boxes[1].groupId == '1' and boxes[1].noDuplicates and boxes[1].priority == 7,
    'group receipt did not unblock the exact shared destination')
object.md[Groups.FIELD]['0'] = 'missing'
boxes, synced = LootSorter.gatherBoxes(player)
assert(synced and #boxes == 1 and boxes[1].groupId == nil,
    'a broken link covered by the complete snapshot permanently blocked legacy fallback')
client = false
assert(LootSorter.arePresetsSynced(), 'single-player acquired a network prerequisite')
print('Quartermaster sync passed: complete snapshots, obsolete/out-of-order replies, draft isolation, empty stores, generations and read-only discovery.')
