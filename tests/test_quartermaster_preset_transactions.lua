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
local publications = {}
ModData = {getOrCreate = function(key) data[key] = data[key] or {}; return data[key] end,
    transmit = function(key)
        assert(key == 'LootSorter_Presets', 'Host published an independent rule sidecar')
        local store = data[key]
        assert(store.schema == 1 and store.presets and store.rules and store.revision >= 0)
        publications[#publications + 1] = {presets=store.presets,rules=store.rules,revision=store.revision}
    end, request = function() end}
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
    'server/LootSorter_Presets.lua'}) do
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
assert(Presets.native().Pantry.rev == 7, 'SP store required a client or game-start installer')
assert(Rules.presetStore().Pantry.rule.include[1] == 'food')
for _, path in ipairs({'client/LootSorter_PresetSync.lua', 'client/LootSorter_Core.lua'}) do
    dofile(NativeQuartermasterLuaRoot .. '/' .. path)
end
local function reload() return Presets.load() end
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
local oldRules = Presets.rules()
assert(not pcall(Presets.transaction, function(native, rules)
    native.Pantry.rev, rules.Pantry.gen = 999, 999
    assert(Presets.native() == oldCache and Presets.rules() == oldRules, 'drafts leaked while callback ran')
    error('callback failed')
end))
assert(Presets.native() == oldCache and Presets.rules() == oldRules and writes == before,
    'callback error published drafts or wrote a snapshot')
assert(Presets.transaction(function(native, rules)
    native.Pantry.rev, rules.Pantry.gen = 999, 999
    return 'stale', 'unchanged'
end) == 'stale')
assert(Presets.native() == oldCache and Presets.rules() == oldRules and writes == before,
    'refused transaction published drafts or wrote a snapshot')
short = true
assert(not pcall(put, 8, all), 'failed commit was acknowledged')
assert(oldCache.Pantry.rev == 8 and oldRules.Pantry.rule.mode == 'any', 'failed commit mutated committed tables')
short = false
assert(LootSorter.getPresetStore().Pantry.rev == 8 and Rules.getPreset('Pantry', LootSorter.getPresetStore().Pantry).mode == 'any')
readback = true
assert(not pcall(put, 8, all), 'ambiguous commit was acknowledged')
readback, readFailure = false, nil
assert(LootSorter.getPresetStore().Pantry.rev == 9 and Rules.getPreset('Pantry', LootSorter.getPresetStore().Pantry).mode == 'all', 'reload mixed old/new pair after readback failure')
before = writes
assert(LootSorter.removePreset({name='Pantry',baseGen=40}) == 'stale' and writes == before)
assert(LootSorter.removePreset({name='Pantry',baseGen=41}) == 'ok' and writes == before + 1)
assert(not reload().Pantry and not Rules.presetStore().Pantry, 'delete lost pair coherence on restart')
before = writes
server = true
-- Existing Host worlds migrate once without changing preset identity or touching SP files.
data.LootSorter_Presets = {presets={Legacy={cats={Food=true},items={['Tin opener']=true},gen=41,rev=7,createdBy='owner'},
    Recreated={cats={},items={},gen=42,rev=1}}}
data.PZSTQuartermasterTagRules = {presets={Legacy={gen=41,rule=any},Recreated={gen=40,rule=all},Gone={gen=99,rule=all}}}
assert(Presets.native().Legacy.gen == 41 and Presets.native().Legacy.rev == 7
    and Presets.native().Legacy.createdBy == 'owner' and Presets.native().Legacy.items['Tin opener'])
assert(Rules.getPreset('Legacy', Presets.native().Legacy).mode == 'any'
    and not Rules.presetStore().Recreated and not Rules.presetStore().Gone and writes == before)
assert(data.LootSorter_Presets.schema == 1 and data.LootSorter_Presets.revision == 0 and #publications == 0)
assert(LootSorter.serverFns.putPreset(player, {name='Server',cats={},items={},pzstTagRule=all}) == 'ok')
assert(data.LootSorter_Presets.presets.Server and Rules.presetStore().Server and writes == before, 'MP authority accessed SP files')
assert(#publications == 1 and publications[1].presets.Server and publications[1].rules.Server,
    'Host save did not publish a complete pair exactly once')
local serverPreset = data.LootSorter_Presets.presets.Server
local hostNative, hostRules, hostRevision = Presets.native(), Presets.rules(), data.LootSorter_Presets.revision
assert(Presets.transaction(function(native, rules)
    native.Server.rev, rules.Server.gen = 999, 999
    return 'stale'
end) == 'stale')
assert(not pcall(Presets.transaction, function(native, rules)
    native.Server.rev, rules.Server.gen = 999, 999
    error('failed Host draft')
end))
assert(Presets.native() == hostNative and Presets.rules() == hostRules
    and data.LootSorter_Presets.revision == hostRevision and #publications == 1,
    'refused/failed Host mutation leaked partial drafts')
for _, malformed in ipairs({true, {gen=serverPreset.gen}, {gen=serverPreset.gen, rule={mode='invalid'}}}) do
    Rules.presetStore().Server = malformed
    assert(LootSorter.serverFns.putPreset(player, {name='Server', cats={}, items={},
        expectExisting=true, baseRev=serverPreset.rev, baseGen=serverPreset.gen}) == 'ok')
    assert(not Rules.presetStore().Server and writes == before, 'native edit retained a malformed rule sidecar')
    serverPreset = data.LootSorter_Presets.presets.Server
end
-- An explicit clear/delete stays cleared on a fresh service load despite retained legacy data.
assert(LootSorter.serverFns.putPreset(player, {name='Legacy',cats={},items={},expectExisting=true,
    baseRev=7,baseGen=41,pzstTagRule={mode='all',include={},exclude={}}}) == 'ok')
assert(not Rules.presetStore().Legacy and data.PZSTQuartermasterTagRules.presets.Legacy)
local Restarted = assert(loadfile(shared .. 'PZSurvivorToolkit/QuartermasterPresets.lua'))()
assert(Restarted.native().Legacy.rev == 8 and not Restarted.rules().Legacy, 'restart remigrated an old rule')
assert(LootSorter.serverFns.removePreset(player,{name='Legacy',baseGen=41}) == 'ok')
assert(not Restarted.native().Legacy and not Restarted.rules().Legacy)
assert(LootSorter.serverFns.putPreset(player,{name='Legacy',cats={Electrical=true},items={},pzstTagRule=all}) == 'ok')
assert(Restarted.native().Legacy.gen ~= 41 and not LootSorter.linkResolves(Restarted.native().Legacy,41))
assert(data.PZSTQuartermasterTagRules.presets.Legacy.gen == 41 and writes == before, 'legacy/SP storage was modified')
for index, publication in ipairs(publications) do
    assert(publication.revision == index, 'successful Host publications skipped or repeated a revision')
end
client, server = true, false
assert(Presets.receive({schema=1,revision=0,presets={Client={gen=1,cats={},items={}}},rules={Client={gen=1,rule=all}}}))
assert(Rules.presetStore().Client and LootSorter.getPresetStore().Client and writes == before)
assert(not pcall(Presets.transaction, function() return 'ok' end), 'client could mutate authoritative store')
print('Quartermaster preset transactions passed: direct owned put/remove, private drafts, one pair commit, fullType translation, generations/revisions/owner, conflicts, partial/ambiguous failure recovery and MP isolation.')
