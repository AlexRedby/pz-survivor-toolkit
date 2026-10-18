if not NativeQuartermasterLuaRoot then print('SKIP Quartermaster preset transactions: actual upstream Lua required.'); return end
local shared = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/'
local cache, disk = {}, {}
require = function(name)
    if name:sub(1, 13) == 'TimedActions/' then return {} end
    if not cache[name] then cache[name] = assert(loadfile(shared .. name .. '.lua'))() end
    return cache[name]
end
local client, server, clock = false, false, 1000
isClient, isServer = function() return client end, function() return server end
getTimestampMs = function() clock = clock + 1; return clock end
PZSurvivorToolkit = {Settings = {itemTags = function() return true end}}
Events = setmetatable({}, {__index = function(self, key)
    local event = {Add = function() end, Remove = function() end}; rawset(self, key, event); return event
end})
local data, writes, short, readback, readFailure = {}, 0, false, false, nil
ModData = {getOrCreate = function(key) data[key] = data[key] or {}; return data[key] end,
    transmit = function() end, request = function() end}
getFileReader = function(path, create)
    if path == readFailure then error('readback unavailable') end
    if not disk[path] and create then disk[path] = '' end
    if not disk[path] then return end
    local text, index = disk[path], 1
    return {readLine = function()
        if index > #text then return end
        local stop = text:find('\n', index, true)
        local line = text:sub(index, stop and stop - 1 or #text)
        index = stop and stop + 1 or #text + 1; return line
    end, close = function() end}
end
getFileWriter = function(path)
    writes = writes + 1; disk[path] = ''
    return {write = function(_, text) disk[path] = short and text:sub(1, #text / 2) or text end,
        close = function() if readback then readFailure = path end end}
end
local player = {getUsername = function() return 'native-user' end}
LootSorter = {serverFns = {}, DBG = function() end, SYNC_RETRY_MS = 4000, isAuthority = function() return not client end}
LootSorter.serverFn = function(name, callback)
    LootSorter.serverFns[name] = callback
    return function(args, done)
        local verdict, detail = LootSorter.serverFns[name](player, args)
        if done then done(verdict, detail) end
        return verdict, detail
    end
end
for _, path in ipairs({'shared/LootSorter_Util.lua', 'shared/LootSorter_Presets.lua',
    'client/LootSorter_PresetSync.lua', 'client/LootSorter_Core.lua', 'server/LootSorter_Presets.lua'}) do
    dofile(NativeQuartermasterLuaRoot .. '/' .. path)
end
local label = 'Original label'
LootSorter.getItemNames = function() end
LootSorter.getItemFullType = function(name) return name == label and 'Base.TinOpener' end
LootSorter.getDisplayNameForFullType = function(fullType) return fullType == 'Base.TinOpener' and label end
getCell = function() return {} end
local Codec = require 'PZSurvivorToolkit/QuartermasterPresetCodec'
local Storage = require 'PZSurvivorToolkit/QuartermasterPresetStorage'
local Presets = require 'PZSurvivorToolkit/QuartermasterPresets'
disk['QuartermasterPresets.txt'] = 'return {Pantry={cats={Food=true},items={["Original label"]=true},gen=41,rev=7,createdBy="original-owner"}}'
disk['PZSTQuartermasterTagRules.txt'] = Codec.encode({Pantry={cats={food=true},items={},gen=41}})
local oldNative, oldRules = disk['QuartermasterPresets.txt'], disk['PZSTQuartermasterTagRules.txt']
local Rules = require 'PZSurvivorToolkit/QuartermasterTagRules'
dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/server/PZSurvivorToolkit/QuartermasterTagRuleAuthority.lua')
Rules.installAuthority()
assert(LootSorter.getPresetStore().Pantry.rev == 7, 'SP storage was not installed before the first native read')
assert(Rules.presetStore().Pantry.rule.include[1] == 'food')
local function reload()
    LootSorter.pzstPresetStorage = nil
    Presets.install(Rules)
    return LootSorter.getPresetStore()
end
local function put(baseRev, rule)
    return LootSorter.putPreset({name='Pantry', cats={Food=true}, items={[label]=true},
        expectExisting=true, baseRev=baseRev, baseGen=41, pzstTagRule=rule})
end
local any = {mode='any', include={'food','electrical'}, exclude={'perishable'}}
local all = {mode='all', include={'food'}, exclude={}}
assert(put(7, any) == 'ok' and writes == 1, 'native and rule Save were separate commits')
local saved = LootSorter.getPresetStore().Pantry
assert(saved.gen == 41 and saved.rev == 8 and saved.createdBy == 'original-owner')
local snapshot = Storage.load()
assert(snapshot.native.Pantry.items['Base.TinOpener'] and snapshot.native.Pantry.rev == 8)
assert(snapshot.rules.Pantry.items.__PZST_ANY__ and snapshot.rules.Pantry.gen == 41)
assert(disk['QuartermasterPresets.txt'] == oldNative and disk['PZSTQuartermasterTagRules.txt'] == oldRules)
label = 'Translated label'
assert(reload().Pantry.items[label] and not LootSorter.getPresetStore().Pantry.items['Original label'], 'fullType translation was lost')
assert(Rules.getPreset('Pantry', LootSorter.getPresetStore().Pantry).mode == 'any')
local before, oldCache = writes, LootSorter.getPresetStore()
assert(put(7, all) == 'stale' and writes == before and LootSorter.getPresetStore() == oldCache, 'native conflict wrote a snapshot')
short = true
assert(not pcall(put, 8, all) and LootSorter._presets == nil and Rules.localPresets == nil, 'failed commit published staged caches')
short = false
assert(LootSorter.getPresetStore().Pantry.rev == 8 and Rules.getPreset('Pantry', LootSorter.getPresetStore().Pantry).mode == 'any')
readback = true
assert(not pcall(put, 8, all) and LootSorter._presets == nil and Rules.localPresets == nil, 'ambiguous commit retained stale caches')
readback, readFailure = false, nil
assert(LootSorter.getPresetStore().Pantry.rev == 9 and Rules.getPreset('Pantry', LootSorter.getPresetStore().Pantry).mode == 'all', 'reload mixed old/new pair after readback failure')
before = writes
assert(LootSorter.removePreset({name='Pantry',baseGen=40}) == 'stale' and writes == before)
assert(LootSorter.removePreset({name='Pantry',baseGen=41}) == 'ok' and writes == before + 1)
assert(not reload().Pantry and not Rules.presetStore().Pantry, 'delete lost pair coherence on restart')
before = writes
server = true
assert(LootSorter.serverFns.putPreset(player, {name='Server',cats={},items={},pzstTagRule=all}) == 'ok')
assert(data.LootSorter_Presets.presets.Server and Rules.presetStore().Server and writes == before, 'MP authority accessed SP files')
client, server = true, false
Rules.received = {Client={gen=1,rule=all}}
assert(Rules.presetStore().Client and writes == before)
print('Quartermaster preset transactions passed: actual native put/remove, one pair commit, fullType translation, generations/revisions/owner, conflicts, partial/ambiguous failure recovery and MP isolation.')
