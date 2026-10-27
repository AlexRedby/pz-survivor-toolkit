local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/'
local loaded, originalRequire = {}, require
require = function(name)
    if loaded[name] then return loaded[name] end
    local file = loadfile(root .. 'shared/' .. name .. '.lua')
    if not file then return originalRequire(name) end
    loaded[name] = file() or true
    return loaded[name]
end
local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}; for key, item in pairs(value) do out[key] = copy(item) end; return out
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function list(values)
    return {size = function() return #values end, get = function(_, i) return values[i + 1] end}
end
local mode, stores, publications = 'sp', {}, {}
isClient = function() return mode == 'client' end
isServer = function() return mode == 'server' end
getTimestampMs = function() return 100 end
PZSurvivorToolkit, LootSorter = {}, {}
Events = {}
for _, name in ipairs({'OnClientCommand', 'OnServerCommand', 'OnTick', 'OnReceiveGlobalModData', 'OnGameStart', 'OnInitGlobalModData'}) do
    local handlers = {}
    Events[name] = {handlers = handlers, Add = function(fn) handlers[#handlers + 1] = fn end,
        Remove = function(fn) for i = #handlers, 1, -1 do if handlers[i] == fn then table.remove(handlers, i) end end end}
end
local function fire(name, ...)
    for _, fn in ipairs(copy(Events[name].handlers)) do fn(...) end
end
ModData = {getOrCreate = function(name) stores[name] = stores[name] or {}; return stores[name] end,
    get = function(name) return stores[name] end,
    transmit = function(name) publications[#publications + 1] = name end}
local square = {getX = function() return 10 end, getY = function() return 20 end, getZ = function() return 0 end,
    isBlockedTo = function() return false end}
local player = {username = 'owner', getUsername = function(self) return self.username end,
    getCurrentSquare = function() return square end, getAccessLevel = function(self) return self.access or '' end}
getSpecificPlayer = function() return player end
local objects = {}
for index = 0, 1 do
    local obj = {md = {}, kind = 'IsoObject'}
    obj.getModData = function(self) return self.md end
    obj.hasModData = function() return true end
    obj.getSquare = function() return square end
    obj.getObjectIndex = function() return index end
    obj.getContainerCount = function() return 1 end
    obj.transmitModData = function() end
    local container = {getType = function() return 'crate' end, getParent = function() return obj end,
        isLockedToCharacter = function(self) return self.locked end}
    obj.getContainerByIndex = function() return container end
    objects[index + 1] = obj
end
square.getObjects = function() return list(objects) end
getCell = function() return {getGridSquare = function() return square end} end
instanceof = function(obj, kind) return obj.kind == kind end
local allowed = true
SafeHouse = {isSafehouseAllowLoot = function() return allowed end, isSafehouseAllowInteract = function() return allowed end}
local Rules = require 'PZSurvivorToolkit/QuartermasterTagRules'
local Config = require 'PZSurvivorToolkit/QuartermasterContainerConfig'
local Groups = require 'PZSurvivorToolkit/ContainerGroups'
dofile(root .. 'server/PZSurvivorToolkit/QuartermasterTagRuleAuthority.lua')
local a, b = objects[1], objects[2]
local rule = {mode = 'all', include = {'food'}, exclude = {}}
local function config(mode, id, revision, name)
    return {cats = {Food = true}, items = {['Base.Beans'] = true}, presets = {Legacy = 41}, priority = 7,
        noDuplicates = true, appearance = {name = name or 'Pantry', icon = {kind = 'item', value = 'Base.Beans'},
            color = {r = 0.2, g = 0.3, b = 0.4, a = 1}},
        groupOperation = mode and {mode = mode, id = id, baseRevision = revision} or nil}
end
local function save(obj, value, base, tagRule)
    return Rules.applyBox(player, {x = 10, y = 20, z = 0, object = obj:getObjectIndex(), ci = 0,
        baseRevision = base or Rules.getBoxRevision(obj, 0), configuration = value, rule = tagRule or rule})
end
local notifications = 0
local listener = function() notifications = notifications + 1 end
Groups.onChanged(listener); Groups.onChanged(listener)
assert(Groups.synced() and #Groups.list() == 0)
assert(stores[Groups.STORE] == nil, 'reading groups allocated world state')
local untouched = {hasModData = function() return false end, getModData = function() error('pure group read allocated ModData') end}
assert(not Groups.link(untouched, 0) and not Groups.resolve(untouched, 0) and Groups.ready(untouched, 0))
local invalid = config('create'); invalid.appearance.name = ' '
assert(save(a, invalid) == 'invalid' and Groups.link(a, 0) == nil)
local submitted = config('create')
local verdict, revision, detail = save(a, submitted)
assert(verdict == 'ok' and revision == 1 and notifications == 1)
local id = Groups.link(a, 0)
assert(type(id) == 'string' and Groups.resolve(a, 0).createdBy == 'owner' and Groups.resolve(a, 0).rev == 1)
assert(a.md[Groups.REVISIONS]['0'] == Groups.snapshot().revision and Groups.ready(a, 0), 'create lost group snapshot marker')
assert(detail.groupLink == id and detail.groups.groups[id] and detail.configuration.groupOperation == nil)
submitted.appearance.name, submitted.cats.Food = 'changed', nil
local record = Groups.resolve(a, 0); record.configuration.appearance.name = 'changed'
local records = Groups.list(); records[1].configuration.noDuplicates = false
assert(Groups.resolve(a, 0).configuration.appearance.name == 'Pantry' and Groups.resolve(a, 0).configuration.cats.Food
    and Groups.resolve(a, 0).configuration.noDuplicates, 'group leaked editor/list drafts')
local join = config('join', id); join.appearance.name = 'Host must ignore this draft'; join.noDuplicates = false
verdict, revision, detail = save(b, join)
assert(verdict == 'ok' and Groups.link(b, 0) == id and Config.read(b, 0, player).noDuplicates
    and Config.read(b, 0, player).appearance.name == 'Pantry' and detail.rule.include[1] == 'food')
assert(b.md[Groups.REVISIONS]['0'] == Groups.snapshot().revision, 'join lost group snapshot marker')
local update = config('update', id, 1, 'Shared renamed'); update.noDuplicates = false
assert(save(a, update) == 'ok' and Groups.resolve(b, 0).configuration.appearance.name == 'Shared renamed'
    and Groups.resolve(b, 0).configuration.noDuplicates == false and Groups.resolve(a, 0).rev == 2)
assert(a.md[Groups.REVISIONS]['0'] == Groups.snapshot().revision and b.md[Groups.REVISIONS]['0'] < a.md[Groups.REVISIONS]['0'],
    'group update did not stamp its authoring compartment independently')
assert(b.md.crate_customContainerName == 'Pantry', 'fixture did not retain an old materialized group appearance')
local detachedVerdict, _, detachedDetail = save(b, {cats = {Clipboard = true}})
assert(detachedVerdict == 'ok' and not Groups.link(b, 0)
    and b.md.crate_customContainerName == 'Shared renamed' and detachedDetail.configuration.appearance.icon.value == 'Base.Beans'
    and detachedDetail.configuration.appearance.color.g == 0.3 and Groups.resolve(a, 0).rev == 2,
    'sorting-only local save lost the current shared appearance while detaching')
assert(b.md[Groups.REVISIONS]['0'] == nil, 'local sorting save retained a group snapshot marker')
assert(save(b, config('join', id)) == 'ok')
local before, beforeA = Groups.snapshot(), copy(a.md)
assert(save(a, config('update', id, 1)) == 'staleGroup' and same(before, Groups.snapshot()) and same(beforeA, a.md))
assert(save(a, config('update', id, 2), 0) == 'stale' and same(before, Groups.snapshot()) and same(beforeA, a.md))
player.username = 'other'
assert(not Groups.canEdit(Groups.resolve(a, 0), player))
assert(save(a, config('update', id, 2)) == 'deniedGroup' and same(before, Groups.snapshot()) and same(beforeA, a.md))
player.access = 'admin'
assert(Groups.canEdit(Groups.resolve(a, 0), player) and save(a, config('update', id, 2)) == 'ok')
assert(Groups.resolve(a, 0).createdBy == 'owner', 'admin edit changed group ownership')
player.access, player.username = nil, 'owner'
local detached = config('detach'); detached.appearance.name, detached.noDuplicates = 'Only here', false
assert(save(b, detached) == 'ok' and Groups.link(b, 0) == nil
    and Config.read(b, 0, player).appearance.name == 'Only here' and Config.read(b, 0, player).noDuplicates == false
    and Groups.resolve(a, 0).configuration.appearance.name == 'Pantry')
assert(b.md[Groups.REVISIONS]['0'] == nil, 'explicit detach retained a group snapshot marker')
-- Full legacy configuration saves detach; tag-only saves preserve the live group configuration before detaching.
assert(save(b, config('join', id)) == 'ok')
assert(save(b, {cats = {Local = true}}) == 'ok' and not Groups.link(b, 0) and b.md.LSBox['0'].Local)
assert(save(b, config('join', id)) == 'ok')
local empty = {mode = 'all', include = {}, exclude = {}}
assert(save(b, nil, nil, empty) == 'ok' and not Groups.link(b, 0) and Config.read(b, 0, player).priority == 7
    and Config.read(b, 0, player).appearance.name == 'Pantry' and not b.md[Rules.FIELD]['0'])
mode = 'server'; allowed = false
before, beforeA = Groups.snapshot(), copy(a.md)
assert(save(a, config('create')) == 'denied' and same(before, Groups.snapshot()) and same(beforeA, a.md))
allowed = true; a:getContainerByIndex(0).locked = true
assert(save(a, config('create')) == 'denied' and same(before, Groups.snapshot()))
a:getContainerByIndex(0).locked = false
assert(save(b, config('join', 'missing')) == 'missingGroup')
assert(save(b, config('create', nil, nil, 'Second')) == 'ok' and Groups.link(b, 0) ~= id)
assert(publications[#publications] == 'LootSorter_Registry', 'Host omitted registry publication')
local groupStore = stores[Groups.STORE]
local nextId = groupStore.nextId
groupStore.nextId = 0
before, beforeA = Groups.snapshot(), copy(b.md)
assert(save(b, config('create')) == 'invalid' and same(before, Groups.snapshot()) and same(beforeA, b.md),
    'inconsistent group sequence overwrote an existing identity')
groupStore.nextId = nextId
groupStore.nextId = 99999999999999
assert(save(b, config('create', nil, nil, 'Second')) == 'ok' and Groups.link(b, 0) == '100000000000000')
assert(save(b, config('create', nil, nil, 'Second')) == 'ok' and Groups.link(b, 0) == '100000000000001',
    'large group sequences reused a formatted identity')
mode = 'sp'
local restarted = assert(loadfile(root .. 'shared/PZSurvivorToolkit/ContainerGroups.lua'))()
assert(restarted.resolve(a, 0).id == id and restarted.resolve(a, 0).rev == 3, 'SP groups did not survive module reload')
local savedSnapshot = Groups.snapshot()
Groups.applyLink(b, 0, 'broken')
assert(Groups.link(b, 0) == 'broken' and not Groups.resolve(b, 0) and Config.read(b, 0, player).appearance.name == 'Second')
assert(Groups.link(b, 0) == 'broken', 'resolving a broken link mutated it')
for _, badLink in ipairs({true, 1, {}, '', string.rep('x', 129)}) do
    b.md[Groups.FIELD]['0'] = badLink
    beforeA = copy(b.md)
    assert(not Groups.link(b, 0) and not Groups.resolve(b, 0) and same(beforeA, b.md),
        'malformed group link resolved or changed during a read')
end
b.md[Groups.FIELD]['0'] = 'broken'
-- Complete client snapshots are monotonic, validated and detached from network-owned tables.
mode = 'client'; Groups.resetReceived()
assert(not Groups.synced() and #Groups.list() == 0)
assert(not Groups.ready(a, 0) and Groups.ready(untouched, 0), 'unreceived groups were marked ready or plain read allocated data')
assert(Groups.receive(savedSnapshot) and Groups.synced())
assert(Groups.ready(a, 0), 'covered group marker was not ready')
savedSnapshot.groups[id].configuration.appearance.name = 'mutated network table'
assert(Groups.resolve(a, 0).configuration.appearance.name == 'Pantry')
assert(not Groups.receive(savedSnapshot), 'duplicate snapshot replaced the current state')
local malformed = Groups.snapshot(); malformed.revision = malformed.revision + 1; malformed.groups[id].configuration.noDuplicates = 'false'
local accepted, reason = Groups.receive(malformed)
assert(not accepted and reason == 'invalid' and Groups.resolve(a, 0).configuration.noDuplicates == true)
assert(not pcall(Groups.commit, a, 0, {}), 'client mutated authoritative groups')
local membership = {md = {[Groups.FIELD] = {['0'] = 'future'},
    [Groups.REVISIONS] = {['0'] = Groups.snapshot().revision + 1}}}
membership.getModData = function(self) return self.md end
beforeA = copy(membership.md)
assert(not Groups.ready(membership, 0) and same(beforeA, membership.md), 'new membership outran its group snapshot or readiness mutated it')
local newerGroups = Groups.snapshot(); newerGroups.revision = newerGroups.revision + 1
assert(Groups.receive(newerGroups) and Groups.ready(membership, 0), 'covered broken membership did not retain raw fallback')
membership.md[Groups.REVISIONS] = nil
assert(Groups.ready(membership, 0) and membership.md[Groups.REVISIONS] == nil,
    'legacy broken link was blocked or allocated a marker while reading')
-- Join ACK applies the authority payload even when the submitted draft is different.
dofile(root .. 'client/PZSurvivorToolkit/QuartermasterTagRuleClient.lua')
local pending, packet, clientVerdict
LootSorter.callServer = function(_, args, done) packet, pending = args, done end
b.md[Rules.REVISIONS]['0'] = 10
Rules.saveBox(b, 0, empty, player, function(value) clientVerdict = value end, 10, config('join', id, nil, 'Wrong draft'))
local authorityConfig = copy(Groups.resolve(a, 0).configuration)
authorityConfig.noDuplicates = false
local authorityGroups = Groups.snapshot()
authorityGroups.revision = authorityGroups.revision + 1
authorityGroups.groups[id].rev = authorityGroups.groups[id].rev + 1
authorityGroups.groups[id].configuration = copy(authorityConfig)
pending('ok', {revision = 11, configuration = authorityConfig, rule = rule, groupLink = id, groups = authorityGroups})
assert(clientVerdict == 'ok' and Groups.link(b, 0) == id and Config.read(b, 0, player).appearance.name == 'Pantry'
    and Config.read(b, 0, player).noDuplicates == false and b.md[Rules.FIELD]['0'].include[1] == 'food')
assert(b.md[Groups.REVISIONS]['0'] == authorityGroups.revision and Groups.ready(b, 0), 'accepted group ACK lost its authoritative marker')
local latestGroups = Groups.snapshot(); latestGroups.revision = latestGroups.revision + 1
assert(Groups.receive(latestGroups))
Groups.applyLink(b, 0, id, latestGroups.revision)
Rules.saveBox(b, 0, empty, player, function(value) clientVerdict = value end, 11, config('join', id))
pending('ok', {revision = 12, configuration = authorityConfig, rule = rule, groupLink = id, groups = authorityGroups})
assert(clientVerdict == 'ok' and b.md[Groups.REVISIONS]['0'] == latestGroups.revision
    and Groups.snapshot().revision == latestGroups.revision and Groups.ready(b, 0),
    'late group ACK regressed a newer complete snapshot or same-link marker')
Rules.saveBox(b, 0, empty, player, function(value) clientVerdict = value end, 12, config('join', id))
beforeA = copy(b.md)
pending('ok', {revision = 13})
assert(clientVerdict == 'invalid' and same(beforeA, b.md), 'join ACK used an unaccepted client draft')
Rules.saveBox(b, 0, empty, player, function(value) clientVerdict = value end, 12, config('join', id))
before = Groups.snapshot()
local partial = Groups.snapshot(); partial.revision = partial.revision + 1; partial.groups[id].configuration.noDuplicates = 'false'
pending('ok', {revision = 13, configuration = authorityConfig, rule = rule, groupLink = id, groups = partial})
assert(clientVerdict == 'invalid' and same(beforeA, b.md) and same(before, Groups.snapshot()),
    'invalid ACK snapshot partially changed a group or container')
Rules.saveBox(b, 0, empty, player, function(value) clientVerdict = value end, 12, config('join', id))
pending('ok', {revision = 13, rule = rule, groupLink = id, groups = Groups.snapshot()})
assert(clientVerdict == 'invalid' and same(beforeA, b.md) and same(before, Groups.snapshot()),
    'partial join ACK omitted the authority configuration')
Groups.offChanged(listener)
-- Login requests fresh world state and retries once; receipt marks an open picker for rebuild.
local requests = 0
ModData.request = function(name) assert(name == Groups.STORE); requests = requests + 1 end
dofile(root .. 'client/PZSurvivorToolkit/ContainerGroupSync.lua')
LootSorter._picker = {}
fire('OnGameStart')
assert(requests == 1 and not Groups.synced())
getTimestampMs = function() return 10000 end
fire('OnTick')
assert(requests == 2)
fire('OnReceiveGlobalModData', Groups.STORE, Groups.snapshot() or before)
assert(Groups.synced() and LootSorter._picker.needRebuild)
print('Container groups passed: authority ownership/CAS, shared/local saves, detached drafts, join ACKs, SP persistence and client sync.')
