if not FridgeSource then
    print('Fridge transfer compatibility SKIP (pass --fridge-source).'); return
end
local root = ProjectRoot or '.'
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r', '') end
    local file = assert(io.open(path)); local text = file:read('*a'); file:close()
    return text:gsub('\r', '')
end
local compatPath = root .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua'
local compatSource = read(compatPath)
local catalog = assert(compatSource:match('(local projectCookActionSources = %b{})')) .. '\n'
    .. assert(compatSource:match('(local sourceFiles = %b{})'))
local verified = assert(compatSource:match('(local function verified%(id, files%).-\nend)'))
local install = assert(compatSource:match('(local function installFridgeTransfers%(%).-\nend)'))
local query = assert(compatSource:match('(function Compat.isTransferPerform%(callback%).-\nend)'))
local methods = assert(compatSource:match('(local function transferMethods%(%).-\nend)'))
local proofPath = root .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'
local modulePaths = {
    ['TurnOffFridges/TOF_Core'] = 'shared/TurnOffFridges/TOF_Core.lua',
    ['TurnOffFridges/TOF_TileProps'] = 'shared/TurnOffFridges/TOF_TileProps.lua',
    ['TurnOffFridges/TOF_Client'] = 'client/TurnOffFridges/TOF_Client.lua',
    ['TurnOffFridges/TOF_Light'] = 'client/TurnOffFridges/TOF_Light.lua',
}
local function fixture(options)
    options = options or {}
    local h = {trace = {}, loads = {}, events = {}, reads = {}, priorValid = true, policy = {}, returns = {}}
    local origins = {}
    local nativeFilename = NativeFilenameOfClosure or function(callback)
        return debug.getinfo(callback, 'S').source:gsub('^@', '')
    end
    getFilenameOfClosure = function(callback) return origins[callback] or nativeFilename(callback) end
    getActivatedMods = function() return {contains = function(_, id) return id == 'NicksTurnOffFridges' end} end
    Events = {}
    for _, name in ipairs({'OnGameStart', 'OnGameBoot', 'OnServerStarted', 'OnServerCommand', 'LoadChunk', 'OnTick'}) do
        local callbacks = {}; h.events[name] = callbacks
        Events[name] = {Add = function(callback) callbacks[#callbacks + 1] = callback end}
    end
    TurnOffFridges = nil
    isClient = function() return true end
    isServer = function() return false end
    getTimestampMs = function() return 100 end
    getSpecificPlayer = function() return {} end
    local function native(action)
        h.trace[#h.trace + 1] = 'native'; h.nativeAction = action
    end
    origins[native] = 'TimedActions/ISInventoryTransferAction.lua'
    local function constructor() end
    local function transferItem() end
    ISInventoryTransferAction = {new = constructor, perform = native, transferItem = transferItem}
    h.native = native
    local initial
    if options.bc then
        initial = function(action) h.trace[#h.trace + 1] = 'bc'; native(action) end
        origins[initial] = 'BetterContainers/Proximity/Proximity_ISInventoryTransferAction.lua'
        ISInventoryTransferAction.perform = initial
    elseif options.foreign then
        initial = function(action) native(action) end
        origins[initial] = 'ForeignTransfer.lua'
        ISInventoryTransferAction.perform = initial
    end
    h.previous = ISInventoryTransferAction.perform
    local loaded = {}
    require = function(module)
        if module == 'TimedActions/ISInventoryTransferAction' then return ISInventoryTransferAction end
        local path = modulePaths[module]
        if path then
            if not loaded[module] then
                h.loads[module] = (h.loads[module] or 0) + 1
                local value = assert(loadstring(read(FridgeSource .. '/' .. path), '@' .. FridgeSource .. '/' .. path))()
                loaded[module] = value or true
            end
            return loaded[module]
        end
        error('unexpected fridge require: ' .. tostring(module))
    end
    getModFileReader = function(id, path)
        assert(id == 'NicksTurnOffFridges')
        path = path:gsub('^media/lua/', '')
        h.reads[path] = (h.reads[path] or 0) + 1
        local text = read(FridgeSource .. '/' .. path)
        if options.changed == path then text = text .. '\n-- changed source\n' end
        local lines = {}; for line in (text .. '\n'):gmatch('(.-)\n') do lines[#lines + 1] = line end
        if text:sub(-1) == '\n' then lines[#lines] = nil end
        local index = 0
        return {readLine = function() index = index + 1; return lines[index] end, close = function() end}
    end
    local function adopt(target, previous, replacement, guard)
        assert(previous.new == constructor and previous.perform == h.previous and previous.transferItem == transferItem,
            'fridge adoption lost the exact previous constructor/delegate/helper')
        assert(replacement.new == constructor and replacement.perform == ISInventoryTransferAction.perform
            and replacement.perform ~= previous.perform and replacement.transferItem == transferItem,
            'fridge adoption changed an unrelated native transfer method')
        assert(type(guard) == 'function' and guard(), 'fridge adoption did not supply a live helper guard')
        target[#target + 1] = {previous = previous, replacement = replacement, guard = guard}
        return true
    end
    local policy = {adoptTransferHooks = function(...) return adopt(h.policy, ...) end}
    local operations = {adoptReturnHooks = function(...) return adopt(h.returns, ...) end}
    PZSurvivorToolkit = {ActionQueuePolicy = policy, ActionQueueOperations = operations}
    -- The game loads shared TOF modules before the Toolkit client compatibility pass.
    require('TurnOffFridges/TOF_Core')
    require('TurnOffFridges/TOF_TileProps')
    local Proof = assert(loadfile(proofPath))()
    local code = 'local Toolkit,Operations,Policy,Proof,reviewedTransferPerform,transferPerformGuard=...\n'
        .. 'local Compat,ready={},{}\n' .. catalog .. '\n' .. verified .. '\n' .. methods .. '\n' .. install .. '\n' .. query
        .. '\nreturn {install=installFridgeTransfers,compat=Compat,ready=ready}'
    h.adapter = assert(loadstring(code, '@' .. compatPath))(PZSurvivorToolkit, operations, policy, Proof,
        options.bc and initial or nil, options.bc and function() return h.priorValid end or nil)
    function h.run()
        local object = {getContainerCount = function() h.trace[#h.trace + 1] = 'fridge'; return 1 end,
            getContainerByIndex = function() return {getType = function() return 'fridge' end} end,
            hasModData = function() return false end}
        local container = {getParent = function() return object end}
        local action = {srcContainer = container, destContainer = container}
        ISInventoryTransferAction.perform(action)
        assert(h.nativeAction == action, 'actual TOF wrapper delegated a different native transfer')
        return table.concat(h.trace, ',')
    end
    return h
end

for _, bc in ipairs({false, true}) do
    local h = fixture({bc = bc})
    h.adapter.install()
    local wrapped = ISInventoryTransferAction.perform
    assert(wrapped ~= h.previous and h.adapter.compat.isTransferPerform(wrapped),
        'reviewed TOF transfer wrapper was not approved over ' .. (bc and 'BC' or 'native'))
    assert(#h.policy == 1 and #h.returns == 1, 'fridge wrapper must be adopted once by policy and returns')
    assert(h.loads['TurnOffFridges/TOF_Core'] == 1 and h.loads['TurnOffFridges/TOF_TileProps'] == 1
        and h.loads['TurnOffFridges/TOF_Client'] == 1
        and h.loads['TurnOffFridges/TOF_Light'] == 1, 'all reviewed native TOF modules must load before the snapshot')
    assert(#h.events.OnGameStart == 1 and #h.events.OnServerStarted == 1,
        'native TileProps startup callbacks were not preserved exactly once')
    assert(h.run() == (bc and 'bc,native,fridge' or 'native,fridge'),
        'actual TOF wrapper must call the exact delegate once before inspecting its container')
    require('TurnOffFridges/TOF_TileProps'); require('TurnOffFridges/TOF_Client'); require('TurnOffFridges/TOF_Light')
    assert(ISInventoryTransferAction.perform == wrapped and h.loads['TurnOffFridges/TOF_Client'] == 1,
        'the later native module pass wrapped an already-preloaded transfer again')
    assert(not h.adapter.compat.isTransferPerform(function() end), 'a different callback borrowed TOF approval')
    if bc then
        h.priorValid = false
        assert(not h.adapter.compat.isTransferPerform(wrapped) and not h.policy[1].guard() and not h.returns[1].guard(),
            'TOF approval detached itself from its previous BC helper guard')
    end
end

for _, path in pairs(modulePaths) do
    local h = fixture({changed = path})
    h.adapter.install()
    assert(ISInventoryTransferAction.perform == h.previous and #h.policy == 0 and #h.returns == 0,
        path .. ': changed source gained transfer adoption')
    assert(not h.loads['TurnOffFridges/TOF_Client'], path .. ': changed source ran the actual transfer wrapper before rejection')
end

do
    local h = fixture({foreign = true})
    h.adapter.install()
    assert(ISInventoryTransferAction.perform == h.previous and #h.policy == 0 and #h.returns == 0,
        'an unknown preinstalled transfer delegate acquired TOF approval')
end

-- Disk pins cannot bless helper callbacks that were replaced before capture.
do
    local h = fixture()
    require('TurnOffFridges/TOF_Core')
    local original = TurnOffFridges.isFridgeObject
    TurnOffFridges.isFridgeObject = function(...) return original(...) end
    h.adapter.install()
    assert(#h.policy == 0 and #h.returns == 0
        and not h.adapter.compat.isTransferPerform(ISInventoryTransferAction.perform),
        'an early foreign Core helper wrapper gained approval from unchanged on-disk TOF sources')
end

for _, mutation in ipairs({'MODULE', 'AUTO_KEY', 'ON-value', 'OFF-value', 'ON-extra', 'OFF-extra'}) do
    local h = fixture()
    require('TurnOffFridges/TOF_Core')
    local owner = TurnOffFridges
    if mutation == 'MODULE' or mutation == 'AUTO_KEY' then owner[mutation] = 'changed'
    elseif mutation == 'ON-value' then owner.ON.fridgeoff = 'changed'
    elseif mutation == 'OFF-value' then owner.OFF.fridge = 'changed'
    elseif mutation == 'ON-extra' then owner.ON.foreignoff = 'foreign'
    else owner.OFF.foreign = 'foreignoff' end
    h.adapter.install()
    assert(#h.policy == 0 and #h.returns == 0
        and not h.adapter.compat.isTransferPerform(ISInventoryTransferAction.perform),
        mutation .. ': preloaded foreign Core constants gained transfer approval')
end

local mutations = {'owner', 'MODULE', 'AUTO_KEY', 'ON', 'OFF', 'ON-value', 'OFF-value', 'autoTick',
    'isFridgeObject', 'isAuto', 'isUnitEmpty', 'isUnplugged', 'requestAutoEval', 'applyLight', 'toggleUnit'}
for _, mutation in ipairs(mutations) do
    local h = fixture(); h.adapter.install()
    local wrapped, owner = ISInventoryTransferAction.perform, TurnOffFridges
    assert(h.adapter.compat.isTransferPerform(wrapped), mutation .. ': fixture never had valid approval')
    if mutation == 'owner' then TurnOffFridges = {}
    elseif mutation == 'MODULE' or mutation == 'AUTO_KEY' then owner[mutation] = 'changed'
    elseif mutation == 'ON' or mutation == 'OFF' then owner[mutation] = {}
    elseif mutation == 'ON-value' then owner.ON.fridgeoff = 'changed'
    elseif mutation == 'OFF-value' then owner.OFF.fridge = 'changed'
    else owner[mutation] = function() end end
    assert(not h.adapter.compat.isTransferPerform(wrapped) and not h.policy[1].guard() and not h.returns[1].guard(),
        mutation .. ': changed TOF provenance retained transfer/return permission')
end

-- TileProps is loaded as a shared module before Compat captures the TOF helper set.
do
    local h = fixture()
    local owner = TurnOffFridges
    assert(type(owner.clearFridgeProperty) == 'function', 'native shared TileProps did not define clearFridgeProperty')
    owner.clearFridgeProperty = function() end
    h.adapter.install()
    assert(#h.policy == 0 and #h.returns == 0
        and not h.adapter.compat.isTransferPerform(ISInventoryTransferAction.perform),
        'an early foreign TileProps clearFridgeProperty gained transfer approval')
end

do
    local h = fixture(); h.adapter.install()
    local wrapped, owner = ISInventoryTransferAction.perform, TurnOffFridges
    assert(h.adapter.compat.isTransferPerform(wrapped), 'fixture never had valid TileProps approval')
    owner.clearFridgeProperty = function() end
    assert(not h.adapter.compat.isTransferPerform(wrapped) and not h.policy[1].guard() and not h.returns[1].guard(),
        'changed TileProps clearFridgeProperty retained transfer/return permission')
end
print('Fridge transfer compatibility: real Core/Client/Light, exact native/BC delegates, startup ordering, source pins and live guards passed.')
