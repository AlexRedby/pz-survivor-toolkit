local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/'
local loaded, originalRequire = {}, require
require = function(name)
    if loaded[name] then return loaded[name] end
    local fn = loadfile(root .. 'shared/' .. name .. '.lua')
    if not fn then return originalRequire(name) end
    loaded[name] = fn() or true
    return loaded[name]
end
local function list(values)
    return {size = function() return #values end, get = function(_, i) return values[i + 1] end}
end
local function clone(value)
    if type(value) ~= 'table' then return value end
    local out = {}; for key, item in pairs(value) do out[key] = clone(item) end; return out
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local mode, available, clock = 'sp', true, 100
isClient = function() return mode == 'client' end
isServer = function() return mode == 'server' end
getActivatedMods = function() return list(available and {'\\EURY_CONTAINERS'} or {}) end
getTimestampMs = function() return clock end
getText = function(key) return key end
getTextOrNull = function(key) return key == 'IGUI_ContainerTitle_crate' and 'Crate' or nil end
PZSurvivorToolkit = {}
Events = {}
for _, name in ipairs({'OnClientCommand', 'OnServerCommand', 'OnTick', 'OnReceiveGlobalModData', 'OnGameStart'}) do
    local handlers = {}; Events[name] = {handlers = handlers, Add = function(fn) handlers[#handlers + 1] = fn end}
    Events[name].Remove = function(fn)
        for i = #handlers, 1, -1 do if handlers[i] == fn then table.remove(handlers, i) end end
    end
end
instanceof = function(obj, kind) return obj.kind == kind end
local square = {getX = function() return 10 end, getY = function() return 20 end, getZ = function() return 0 end}
local current = {getX = function() return 10 end, getY = function() return 19 end, getZ = function() return 0 end,
    isBlockedTo = function(self) return self.blocked end}
local player = {getUsername = function() return 'survivor' end, getCurrentSquare = function() return current end}
getSpecificPlayer = function() return player end
local object = {kind = 'IsoObject', md = {}, getSquare = function() return square end, getObjectIndex = function() return 0 end,
    getContainerCount = function() return 2 end, getModData = function(self) return self.md end}
local containers = {}
for ci = 0, 1 do containers[ci] = {getType = function() return ci == 0 and 'crate' or 'shelf' end,
    isLockedToCharacter = function(self) return self.locked end, getParent = function() return object end} end
object.getContainerByIndex = function(_, ci) return containers[ci] end
square.getObjects = function() return list({object}) end
getCell = function() return {getGridSquare = function() return square end} end
local safe, interact = true, true
SafeHouse = {isSafehouseAllowLoot = function() return safe end, isSafehouseAllowInteract = function() return interact end}
local registry = {}
ModData = {getOrCreate = function() return registry end, transmit = function() end}
LootSorter = {RPC_TIMEOUT_MS = 15000, RPC_SWEEP_MS = 5000}
object.hasModData = function() return true end
-- BC's public API contract is injected; production must call it rather than own its storage policy.
local calls = {get = 0, user = 0, global = 0}
local function node(md, owner, ci, create)
    if create then
        md.BetterContainers = md.BetterContainers or {}; md.BetterContainers.customize = md.BetterContainers.customize or {}
        md.BetterContainers.customize[owner] = md.BetterContainers.customize[owner] or {}
    end
    local value = md.BetterContainers and md.BetterContainers.customize and md.BetterContainers.customize[owner]
    if type(value) ~= 'table' then return nil end
    if ci ~= 0 then
        if create then value.containers = value.containers or {}; value.containers[ci] = value.containers[ci] or {} end
        value = value.containers and value.containers[ci]
    end
    return value
end
loaded['BetterContainers/Customize/ModData'] = {
    getEffective = function(owner, username, ci)
        calls.get = calls.get + 1
        local md = owner:getModData()
        local c = md.BetterContainers and md.BetterContainers.customize
        if c and type(c._global) ~= 'table' then c._global = nil end -- native getter's repair
        for _, name in ipairs({username, '_global'}) do
            local v = node(md, name, ci)
            if v and (v.name or v.icon or v.color) then return clone({name = v.name, icon = v.icon, color = v.color}) end
        end
    end,
    setUser = function(owner, username, payload, ci)
        calls.user = calls.user + 1
        local v = node(owner:getModData(), username, ci, true)
        v.name, v.icon, v.color = payload.name, clone(payload.icon), clone(payload.color)
    end,
    setGlobal = function(owner, payload, ci)
        calls.global = calls.global + 1
        local v = node(owner:getModData(), '_global', ci, true)
        v.name, v.icon, v.color = payload.name, clone(payload.icon), clone(payload.color)
    end,
}
local Rules = require 'PZSurvivorToolkit/QuartermasterTagRules'
local Appearance = require 'PZSurvivorToolkit/ContainerAppearance'
local Config = require 'PZSurvivorToolkit/QuartermasterContainerConfig'
dofile(root .. 'server/PZSurvivorToolkit/QuartermasterTagRuleAuthority.lua')
dofile(root .. 'client/PZSurvivorToolkit/QuartermasterTagRuleClient.lua')
local rule = {mode = 'all', include = {'food'}, exclude = {'perishable'}}
local function baseline()
    object.md = {unrelated = {untouched = 42}, LSBox = {['0'] = {Old = true}, ['1'] = {Other = true}},
        LSBoxItems = {['0'] = {OldItem = true}}, LSBoxPresets = {['0'] = {OldPreset = 12}}, LSBoxPriority = {['0'] = 8},
        LSBoxNoDuplicates = {['1'] = true},
        [Rules.FIELD] = {['1'] = {mode = 'all', include = {'electrical'}, exclude = {}}},
        [Rules.REVISIONS] = {['0'] = 3, ['1'] = 7},
        BetterContainers = {customize = {survivor = {name = 'User', icon = {kind = 'item', value = 'Base.Axe'},
            containers = {[1] = {name = 'Other compartment'}}}, _global = {name = 'Global'}, other = {name = 'Other player'}}},
        crate_customContainerName = 'Native', container_0_customContainerName = 'Native'}
end
local function args(config)
    return {x = 10, y = 20, z = 0, object = 0, ci = 0, rule = rule, baseRevision = Rules.getBoxRevision(object, 0), configuration = config}
end
local config = {cats = {Food = true}, items = {['Base.Beans'] = true}, presets = {Pantry = 41}, priority = 7, noDuplicates = true,
    appearance = {name = ' Pantry ', icon = {kind = 'texture', value = 'media/ui/pantry.png'}, color = {r = 0.2, g = 0.3, b = 0.4, a = 0.5}}}
baseline()
local before = clone(object.md)
local originalNext = next
next = nil -- Kahlua's standard library does not expose next().
local read = Appearance.read(object, 0, player)
assert(read.name == 'User' and read.icon.value == 'Base.Axe' and calls.get == 1)
read.icon.value = 'changed'; assert(object.md.BetterContainers.customize.survivor.icon.value == 'Base.Axe')
object.md.BetterContainers.customize.survivor.color = {r = 255, g = 128, b = 0, a = 1}
read = Appearance.read(object, 0, player)
assert(read.name == 'User' and read.color.r == 255, 'legacy BC color dropped the existing appearance')
assert(Config.read(object, 0, player).appearance.color.r == 255, 'configuration read discarded BC legacy appearance')
object.md.BetterContainers.customize._global = 'malformed'
Appearance.read(object, 0, player)
assert(object.md.BetterContainers.customize._global == 'malformed', 'opening editor repaired live ModData')
object.md.BetterContainers = nil
assert(Appearance.read(object, 0, player).name == 'Native', 'native existing name was lost')
available = false; assert(not Appearance.available() and Appearance.read(object, 0, player).name == 'Native'); available = true
baseline()
local publications = 0
object.transmitModData = function(self)
    publications = publications + 1
    assert(self.md.LSBox['0'].Food and self.md.LSBoxItems['0']['Base.Beans'] and self.md.LSBoxPresets['0'].Pantry == 41)
    assert(self.md.LSBoxPriority['0'] == 7 and self.md[Rules.FIELD]['0'].include[1] == 'food' and self.md[Rules.REVISIONS]['0'] == 4)
    assert(self.md.LSBoxNoDuplicates['0'] == true, 'publication omitted duplicate policy')
    assert(self.md.crate_customContainerName == 'Pantry' and self.md.BetterContainers.customize._global.name == 'Pantry',
        'publication exposed a partial configuration')
end
assert(Rules.applyBox(player, args(config)) == 'ok' and publications == 1 and calls.user == 1 and calls.global == 1)
assert(object.md.unrelated.untouched == 42 and object.md.LSBox['1'].Other and object.md[Rules.REVISIONS]['1'] == 7)
assert(Config.read(object, 0, player).noDuplicates and object.md.LSBoxNoDuplicates['1'],
    'duplicate policy was lost or changed another compartment')
assert(object.md.BetterContainers.customize.other.name == 'Other player'
    and object.md.BetterContainers.customize.survivor.containers[1].name == 'Other compartment')
config.presets.Pantry = 99; config.appearance.icon.value = 'changed'
assert(object.md.LSBoxPresets['0'].Pantry == 41 and object.md.BetterContainers.customize._global.icon.value == 'media/ui/pantry.png')
object.transmitModData = function() publications = publications + 1 end
local saved = clone(object.md)
local stale = args({cats = {Bad = true}, appearance = {name = 'Bad'}}); stale.baseRevision = 3
assert(Rules.applyBox(player, stale) == 'stale' and same(saved, object.md) and publications == 1)
local invalid = args({cats = {}, appearance = {color = {r = 2, g = 0, b = 0}}})
assert(Rules.applyBox(player, invalid) == 'invalid' and same(saved, object.md))
for _, value in ipairs({'true', 1, {}}) do
    assert(Rules.applyBox(player, args({noDuplicates = value})) == 'invalid' and same(saved, object.md),
        'invalid duplicate policy changed the configuration')
end
mode = 'server'; interact = false
assert(Rules.applyBox(player, args({})) == 'denied' and same(saved, object.md)); interact = true
safe = false; assert(Rules.applyBox(player, args({})) == 'denied'); safe = true
current.blocked = true; assert(Rules.applyBox(player, args({})) == 'unreachable'); current.blocked = false
containers[0].locked = true; assert(Rules.applyBox(player, args({})) == 'denied'); containers[0].locked = false
object.kind = 'IsoWorldInventoryObject'; assert(Rules.applyBox(player, args({})) == 'invalid'); object.kind = 'IsoObject'
mode = 'sp'
assert(Rules.applyBox(player, args({cats = {Manual = true}})) == 'ok')
assert(same(saved.BetterContainers, object.md.BetterContainers) and object.md.crate_customContainerName == 'Pantry',
    'omitted appearance changed existing customization')
assert(not object.md.LSBoxItems['0'] and not object.md.LSBoxPresets['0'] and not object.md.LSBoxPriority['0'])
assert(object.md.LSBoxNoDuplicates['0'] == nil and object.md.LSBoxNoDuplicates['1'] == true
    and Config.read(object, 0, player).noDuplicates == false, 'omitted policy did not restore default for selected compartment')
assert(Rules.applyBox(player, args({appearance = {}})) == 'ok')
assert(not object.md.crate_customContainerName and not object.md.container_0_customContainerName)
assert(not object.md.BetterContainers.customize.survivor.name and not object.md.BetterContainers.customize._global.icon)
assert(object.md.BetterContainers.customize.survivor.containers[1].name == 'Other compartment')
local bc = clone(object.md.BetterContainers)
assert(Rules.applyBox(player, args()) == 'ok' and same(bc, object.md.BetterContainers), 'legacy tag-only save changed appearance')
-- Accepted acknowledgements mirror only selected fields, against current ModData, without publishing.
mode = 'client'; baseline(); local sent, verdict
dofile(root .. 'shared/LootSorter_Rpc.lua')
sendClientCommand = function(selected, module, command, packet)
    assert(selected == player and module == 'Quartermaster' and command == 'saveBox')
    sent = packet
end
local submitted = {cats = {Food = true}, presets = {Pantry = 41}, noDuplicates = true, appearance = {name = 'Client'}}
Rules.saveBox(object, 0, rule, player, function(value) verdict = value end, 3, submitted)
submitted.cats.Food = nil; submitted.appearance.name = 'changed'; submitted.noDuplicates = false
assert(sent.configuration.noDuplicates == true, 'client request lost duplicate policy snapshot')
object.md.unrelated.untouched = 99
local function respond(value, revision)
    for _, fn in ipairs(Events.OnServerCommand.handlers) do
        fn('Quartermaster', 'rpcResult', {rpcToken = sent.rpcToken, verdict = value, detail = {revision = revision}})
    end
end
local previousPublications = publications
respond('ok', 4)
assert(verdict == 'ok' and object.md.LSBox['0'].Food and object.md.BetterContainers.customize._global.name == 'Client'
    and object.md.unrelated.untouched == 99 and publications == previousPublications)
assert(object.md.LSBoxNoDuplicates['0'] == true and object.md.LSBoxNoDuplicates['1'] == true,
    'accepted acknowledgement lost duplicate policy or changed sibling compartment')
Rules.saveBox(object, 0, rule, player, function(value) verdict = value end, 4, {appearance = {name = 'Refused'}})
local stable = clone(object.md); respond('denied', 5)
assert(verdict == 'denied' and same(stable, object.md))
Rules.saveBox(object, 0, rule, player, function(value) verdict = value end, 4, {appearance = {name = 'Stale'}})
object.md[Rules.REVISIONS]['0'] = 6; stable = clone(object.md); respond('ok', 5)
assert(verdict == 'stale' and same(stable, object.md))
assert(Config.normalize({presets = {Pantry = 41}}).presets.Pantry == 41)
assert(Config.normalize({}).noDuplicates == false and Config.normalize({noDuplicates = false}).noDuplicates == false)
assert(Config.normalize({noDuplicates = true}).noDuplicates == true)
assert(not Config.normalize({priority = math.huge}) and not Appearance.normalize({icon = {kind = 'item'}}))
next = originalNext
print('Quartermaster complete container configuration checks passed')
