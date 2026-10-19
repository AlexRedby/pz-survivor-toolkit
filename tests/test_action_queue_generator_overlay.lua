if not NativeActionRoot or not NativeWishlistWorkshopRoot then
    print('Generator overlay source checks SKIP (pass native action and Workshop roots).'); return
end
local function read(path, raw)
    if raw and NativeReadRawText then return NativeReadRawText(path):gsub('\r', '') end
    if NativeReadText then return NativeReadText(path):gsub('\r', '') end
    local file = assert(io.open(path)); local text = file:read('*a'); file:close(); return text:gsub('\r', '')
end
local base = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/'
local overlaySource = read(base .. 'PZSurvivorToolkit/ActionQueueGeneratorOverlay.lua')
local compatSource = read(base .. 'PZSurvivorToolkit/ActionQueueCompat.lua')
local bgiPath = NativeWishlistWorkshopRoot .. '/3576056135/mods/Better Generator Info/42.20/media/lua/client/BGI/BGI_PowerRange.lua'
local bgiSource = read(bgiPath)
local function run(source, path, env)
    local callback = assert(loadstring(source, '@' .. path)); setfenv(callback, env); return callback()
end
local function fixture(options)
    options = options or {}
    local env = setmetatable({}, {__index = _G}); env._G = env
    local loaded, loads, queued = {}, 0, {}
    env.isClient = function() return false end
    local function event() return {Add = function() end, Remove = function() end} end
    env.Events = setmetatable({}, {__index = function(self, name) local value = event(); rawset(self, name, value); return value end})
    env.isClient = function() return false end
    env.PZSurvivorToolkit = {ActionQueueOperations = {registerProducer = function() end},
        ActionQueueDefinitions = {registerBehavior = function() end}}
    -- ActionQueueCompat's manifest installer expects the owned Quartermaster namespace to exist.
    env.LootSorter = {}
    env.ISTimedActionQueue = {add = function(action) queued[#queued + 1] = action end,
        addAfter = function() end, addToQueue = function() end}
    env.getActivatedMods = function() return {contains = function(_, id) return id == 'BetterGeneratorInfo' and not options.inactive end} end
    env.getModFileReader = function(id, path)
        assert(id == 'BetterGeneratorInfo' and path == 'media/lua/client/BGI/BGI_PowerRange.lua')
        local text = bgiSource .. (options.changed and '\n-- changed\n' or '')
        local index = 1
        return {readLine = function()
            if index > #text then return end
            local ending = text:find('\n', index, true)
            local line = text:sub(index, ending and ending - 1 or #text); index = ending and ending + 1 or #text + 1
            return line
        end, close = function() end}
    end
    env.getFilenameOfClosure = NativeFilenameOfClosure or function(callback) return debug.getinfo(callback, 'S').source:gsub('^@', '') end
    local proofPath = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'
    local proof = run(read(proofPath), proofPath, env)
    local nativeClosure = proof.closure
    env.getGameFilesInput = function(path)
        path = path:gsub('^media/lua/', '')
        local text = path == 'client/BGI/BGI_PowerRange.lua' and read(bgiPath, true) or read(NativeActionRoot .. '/' .. path, true)
        if options.shadowed and path == 'client/BGI/BGI_PowerRange.lua' then text = text .. '\n-- shadowed\n' end
        local index = 1
        return {readLine = function()
            if index > #text then return end
            local ending = text:find('\n', index, true)
            local line = text:sub(index, ending and ending - 1 or #text); index = ending and ending + 1 or #text + 1
            return line
        end, close = function() end}
    end
    local function sourceMatches(path, expected)
        return not options.nativeChanged and proof.matches('media/lua/' .. path, expected)
    end
    local function derive(self, name)
        local class = {Type = name, derive = derive}; class.__index = class; return setmetatable(class, {__index = self})
    end
    env.ISBaseTimedAction = {derive = derive, new = function(self, character) return setmetatable({character = character}, self) end}
    env.ISGeneratorInfoWindow = {}
    env.ISWorldObjectContextMenu = {}
    env.getSpecificPlayer = function() return {isTimedActionInstant = function() return false end} end
    env.luautils = {walkAdj = function() return true end}
    env.getCell = function() return {} end
    env.getPlayer = function() return nil end
    env.instanceof = function(object, kind) return object and object.class == kind end
    env.ZombRand = function() return options.failedStart and 0 or 1 end
    env.require = function(module)
        if loaded[module] then return loaded[module] end
        if module == 'PZSurvivorToolkit/SourceProof' then return proof
        elseif module == 'PZSurvivorToolkit/QuartermasterCraftContainers' then
            loaded[module] = run(read(base .. module .. '.lua'), base .. module .. '.lua', env)
            return loaded[module]
        elseif module == 'PZSurvivorToolkit/ActionQueueCompat' then
            loaded[module] = run(compatSource, base .. module .. '.lua', env); return loaded[module]
        elseif module == 'BGI/BGI_PowerRange' then
            loads = loads + 1; run(bgiSource, module .. '.lua', env); loaded[module] = true
        elseif module == 'PZSurvivorToolkit/ActionQueueGenerators' then
            env.PZSurvivorToolkit.ActionQueueGenerators = {prepareOverlay = function()
                return env.PZSurvivorToolkit.ActionQueueGeneratorOverlay.prepare(sourceMatches, nativeClosure)
            end}
        end
        return loaded[module]
    end
    for _, name in ipairs({'ISPlugGenerator', 'ISActivateGenerator'}) do
        local path = 'shared/TimedActions/' .. name .. '.lua'
        run(read(NativeActionRoot .. '/' .. path), path, env)
    end
    local contextPath = 'client/ISUI/ISWorldObjectContextMenu.lua'
    local source = read(NativeActionRoot .. '/' .. contextPath)
    local producer = assert(source:match('(ISWorldObjectContextMenu.onActivateGenerator = function%(.-\nend)'))
    run(producer, contextPath, env)
    if options.delegate then env.ISActivateGenerator.complete = function() error('untrusted delegate ran') end end
    if options.loaded then env.BGI_PowerRange = {} end
    if options.flagged then env.ISPlugGenerator._BGI_wrapComplete = true end
    local overlay = run(overlaySource, base .. 'PZSurvivorToolkit/ActionQueueGeneratorOverlay.lua', env)
    return env, overlay, function() return loads end, queued, function()
        run(read(base .. '000ToolkitGeneratorCompatibility.lua'), base .. '000ToolkitGeneratorCompatibility.lua', env)
    end
end

for _, options in ipairs({{inactive = true}, {changed = true}, {nativeChanged = true}, {shadowed = true},
    {loaded = true}, {flagged = true}, {delegate = true}}) do
    local _, overlay, loads, _, early = fixture(options)
    early(); assert(not overlay.powerScopeKnown() and loads() == 0, 'unknown source/load order/delegate was trusted')
    early(); assert(loads() == 0, 'failed preparation must not retry module execution')
end
local env, overlay, loads, queued, early = fixture()
early(); assert(overlay.powerScopeKnown() and loads() == 1, 'pinned BGI did not install through the early loader')
assert(overlay.matches(env.ISPlugGenerator, 'complete', env.ISPlugGenerator.complete))
assert(overlay.matches(env.ISActivateGenerator, 'complete', env.ISActivateGenerator.complete))
local activate = env.ISWorldObjectContextMenu.onActivateGenerator
assert(overlay.matches(env.ISWorldObjectContextMenu, 'onActivateGenerator', activate))
assert(not overlay.matches(env.ISPlugGenerator, 'complete', activate), 'wrong owner/callback must fail')
early(); assert(loads() == 1 and overlay.powerScopeKnown(), 'repeat preparation reloaded BGI')
env.ISWorldObjectContextMenu.onActivateGenerator = function() end
assert(overlay.matches(env.ISWorldObjectContextMenu, 'onActivateGenerator', activate), 'Toolkit producer binding invalidated its captured BGI delegate')
local square = {getX = function() return 0 end, getY = function() return 0 end, getZ = function() return 0 end}
local generator = {class = 'IsoGenerator', connected = false, activated = false, getSquare = function() return square end,
    isActivated = function(self) return self.activated end, getCondition = function() return 100 end,
    setConnected = function(self, value) self.connected = value end, setActivated = function(self, value) self.activated = value end,
    sync = function() end}
assert(env.ISPlugGenerator.complete({generator = generator, plug = true}) and generator.connected)
activate({}, true, generator, 0)
assert(#queued == 1 and not generator.activated, 'BGI enqueue predicted power before native completion')
assert(env.BGI_PowerRange._unionGenStates[generator] == false,
    'a requested activation cancelled before complete must retain the real off snapshot')
assert(env.ISActivateGenerator.complete({generator = generator, activate = true}) and generator.activated)
local old = env.BGI_PowerRange._rebuildUnionEdges
env.BGI_PowerRange._rebuildUnionEdges = function() error('changed helper ran') end
assert(not overlay.powerScopeKnown() and not overlay.matches(env.ISPlugGenerator, 'complete', env.ISPlugGenerator.complete))
env.BGI_PowerRange._rebuildUnionEdges = old
env.BGI_PowerRange.extra = function() end
assert(not overlay.powerScopeKnown(), 'new BGI helper escaped runtime guard')
env.BGI_PowerRange.extra = nil
local owner = env.ISPlugGenerator; env.ISPlugGenerator = {}
assert(not overlay.powerScopeKnown(), 'native owner replacement escaped runtime guard')
env.ISPlugGenerator = owner
local complete = owner.complete; owner.complete = function() end
assert(not overlay.powerScopeKnown(), 'complete replacement escaped runtime guard')
owner.complete = complete
local context = env.ISWorldObjectContextMenu; env.ISWorldObjectContextMenu = {}
assert(not overlay.powerScopeKnown(), 'world owner replacement escaped runtime guard')
env.ISWorldObjectContextMenu = context
local range = env.BGI_PowerRange; env.BGI_PowerRange = {}
assert(not overlay.powerScopeKnown(), 'BGI table replacement escaped runtime guard')
env.BGI_PowerRange = range
range.TargetGen = {}
assert(not overlay.powerScopeKnown(), 'unknown selected generator escaped runtime guard')
range.TargetGen = nil
setmetatable(env.BGI_PowerRange, {})
assert(not overlay.powerScopeKnown(), 'BGI metatable escaped runtime guard')
local failedEnv, failedOverlay, failedLoads, _, failedEarly = fixture({failedStart = true})
failedEarly(); assert(failedOverlay.powerScopeKnown() and failedLoads() == 1)
generator.activated = false
generator.getCondition = function() return 25 end
generator.failToStart = function(self) self.failed = true end
assert(failedEnv.ISActivateGenerator.complete({generator = generator, activate = true})
    and generator.failed and not generator.activated, 'BGI failed start changed native power state')
print('Generator overlay passed: real selected BGI source, proof by installation, actual native completes and runtime identity guards.')
