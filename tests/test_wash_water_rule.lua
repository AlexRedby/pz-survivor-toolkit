if not NativeActionRoot and not NativeWishlistWorkshopRoot then print('WMI water restoration SKIP (pass native and Workshop sources).'); return end
assert(NativeActionRoot and NativeWishlistWorkshopRoot, 'WMI water restoration requires --game/--native-action-root and --wishlist-workshop-root')
local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/'
local modRoot = NativeWishlistWorkshopRoot .. '/3460812542/mods/WashingMenusImproved/42.15/'
local stockRawget = rawget
-- PZ's KahluaTableImpl.rawget(Object) falls back to metatable.rawget for a
-- missing delegate key. Lua 5.1's rawget does not; model the native contract.
rawget = function(value, key)
    local found = stockRawget(value, key)
    if found ~= nil then return found end
    local parent = getmetatable(value)
    if parent then return rawget(parent, key) end
end
local function ownMember(value, key)
    for name, member in pairs(value) do if name == key then return member end end
end
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r', '') end
    local file = assert(io.open(path)); local value = file:read('*a'); file:close(); return value:gsub('\r', '')
end
local function reader(value)
    local cursor = 1
    return {close = function() end, readLine = function()
        if cursor > #value then return end
        local boundary = value:find('\n', cursor, true) or #value + 1
        local line = value:sub(cursor, boundary - 1); cursor = boundary + 1; return line
    end}
end
local function setup(options)
    options = options or {}
    local f = assert(loadfile(ProjectRoot .. '/tests/support/action_queue_native.lua'))()
    -- The general queue fixture eagerly sets each derived class's __index.
    -- Use actual native inheritance here: derive sets only the parent's index;
    -- the first base-action construction sets the wash class's own index.
    f.native('shared/ISBaseObject.lua')
    f.native('shared/TimedActions/ISBaseTimedAction.lua')
    f.native('shared/TimedActions/ISWashClothing.lua')
    local nativeComplete = ISWashClothing.complete
    getGameVersion = function() return '42.21.0' end
    isClient = function() return options.client or false end
    isServer = function() return options.server or false end
    getActivatedMods = function() return {contains = function(_, id) return id == 'WashFix' and not options.inactive end} end
    getFilenameOfClosure = NativeFilenameOfClosure or function(callback) return debug.getinfo(callback, 'S').source end
    getGameFilesInput = function(path)
        local source = read(NativeActionRoot .. '/' .. path:gsub('^media/lua/', ''))
        return reader(source .. (options.changedNative and '-- unreviewed\n' or ''))
    end
    getModFileReader = function(id, path)
        assert(id == 'WashFix'); return reader(read(modRoot .. path) .. (options.changedWMI and '-- unreviewed\n' or ''))
    end
    local loaded = {}
    local oldRequire = require
    require = function(module)
        if module == 'TimedActions/WMI_PatchWashClothing' then
            if not loaded[module] then loaded[module] = true; assert(loadfile(modRoot .. 'media/lua/shared/' .. module .. '.lua'))() end
        elseif module == 'PZSurvivorToolkit/SourceProof' then
            if not loaded[module] then loaded[module] = assert(loadfile(root .. module .. '.lua'))() end
            return loaded[module]
        else return oldRequire(module) end
    end
    require 'TimedActions/WMI_PatchWashClothing'
    if options.nativeDeriveShadow then ISBaseTimedAction.derive = ISBaseTimedAction.derive end
    if options.foreignBaseDerive then ISBaseTimedAction.derive = function() end end
    if options.foreignWashDerive then ISWashClothing.derive = function() end end
    if options.foreign then ISWashClothing[options.foreign] = function() return 'foreign', nil, 4 end end
    if options.foreignIndex then ISWashClothing.__index = {} end
    if options.foreignSuper then ISWashClothing.SuperType = {} end
    if options.foreignMetatable then setmetatable(ISWashClothing, {__index = ISBaseTimedAction}) end
    local before = ISWashClothing.complete
    local rule
    if not options.unpatched then rule = assert(loadfile(root .. 'PZSurvivorToolkit/WashWaterRule.lua'))() end
    local startupIndex = ownMember(ISWashClothing, '__index')
    local inheritedIndex, inheritedDerive = rawget(ISWashClothing, '__index'), rawget(ISWashClothing, 'derive')
    local startupSafe, startupReason
    if rule then startupSafe, startupReason = rule.matchesComplete(ISWashClothing.complete) end
    local nativeWater = ISWashClothing.GetRequiredWater
    local actor, effects = f.player, {blood = 0, fields = 0, visuals = 0, hands = 0, water = 0}
    local item = {getItemAfterCleaning = function() end, getBloodLevel = function() return 0 end,
        setBloodLevel = function(_, value) assert(value == 0); effects.blood = effects.blood + 1 end}
    function actor:updateHandEquips() effects.hands = effects.hands + 1 end
    function actor:isPrimaryHandItem() return false end
    function actor:isSecondaryHandItem() return false end
    syncItemFields = function() effects.fields = effects.fields + 1 end
    syncVisuals = function() effects.visuals = effects.visuals + 1 end
    Math = {ceil = math.ceil}
    local failure = {}
    local sink = {useFluid = function(_, amount)
        effects.water = effects.water + 1; effects.amount = amount
        if options.onWater then options.onWater() end
        if options.fail then error(failure, 0) end
    end}
    local action
    if options.nativeConstructor then
        actor.inventory.getSoapList = function() return {size = function() return 0 end} end
        local instant = actor.isTimedActionInstant
        actor.isTimedActionInstant = function() return true end
        action = ISWashClothing:new(actor, sink, item, 0, 0, true, nil, 2)
        actor.isTimedActionInstant = instant
    else action = f.action(ISWashClothing, {item = item, sink = sink, noSoap = true, wmiWaterOverride = 2}) end
    if options.override == false then action.wmiWaterOverride = nil end
    return {action = action, rule = rule, before = before, water = nativeWater, native = nativeComplete,
        effects = effects, failure = failure, owner = ISWashClothing, startupIndex = startupIndex,
        startupSafe = startupSafe, startupReason = startupReason,
        inheritedIndex = inheritedIndex, inheritedDerive = inheritedDerive}
end
local baseline = setup({unpatched = true, fail = true})
local ok, failure = pcall(baseline.action.complete, baseline.action)
assert(not ok and failure == baseline.failure and ISWashClothing.GetRequiredWater ~= baseline.water,
    'actual WMI/native sources no longer demonstrate the temporary water-rule leak: ok=' .. tostring(ok)
    .. ' errorIdentity=' .. tostring(failure == baseline.failure) .. ' errorType=' .. type(failure)
    .. ' waterRestored=' .. tostring(ISWashClothing.GetRequiredWater == baseline.water) .. ' error=' .. tostring(failure))
assert(ISWashClothing.GetRequiredWater(baseline.action.item) == 2)
print('Actual WMI/native completion failure reproduces the water-rule leak.')
local restoredDerive = setup()
-- Compat.loadSource temporarily observes derive, then restores the inherited
-- native callback by assigning it to the base's own slot.
ISBaseTimedAction.derive = ISBaseTimedAction.derive
local restored, restoredReason = restoredDerive.rule.matchesComplete(restoredDerive.owner.complete)
assert(restored and restoredReason == 'installed',
    'restoring the exact native inherited derive callback invalidated cleanup')
local preexistingDerive = setup({nativeDeriveShadow = true})
assert(preexistingDerive.startupSafe and preexistingDerive.rule.matchesComplete(preexistingDerive.owner.complete),
    'a prior native derive restoration prevented shared installation')
for _, mode in ipairs({{nativeConstructor = true}, {nativeConstructor = true, client = true}, {nativeConstructor = true, server = true}}) do
    local startup = setup(mode)
    assert(startup.startupIndex == nil and startup.startupSafe, 'shared startup rejected native pre-construction inheritance')
    assert(startup.inheritedIndex == ISBaseTimedAction and startup.inheritedDerive == ISBaseObject.derive,
        'fixture did not exercise Kahlua rawget metatable fallback before first construction')
    assert(ownMember(startup.owner, '__index') == startup.owner and startup.rule.matchesComplete(startup.owner.complete),
        'native first construction invalidated completion cleanup')
end
for _, mode in ipairs({{}, {client = true}, {server = true}}) do
    mode.fail, mode.unpatched = true, WashWaterRuleUnpatched
    local f = setup(mode)
    local savedNext = next; next = nil -- Stock Kahlua has pairs, but no global next.
    local completed, message = pcall(f.action.complete, f.action)
    next = savedNext
    assert(not completed and message == f.failure, 'original native failure object changed')
    assert(ISWashClothing.GetRequiredWater == f.water, 'failed WMI completion leaked its temporary water rule')
    assert(f.effects.blood == 1 and f.effects.fields == 1 and f.effects.visuals == 1 and f.effects.hands == 1
        and f.effects.water == 1 and f.effects.amount == 2, 'native effects replayed, skipped or changed')
    assert(f.rule.matchesComplete(f.owner.complete))
end
local success = setup()
assert(success.action:complete() == true and ISWashClothing.GetRequiredWater == success.water and success.effects.water == 1)
local installed, installReason = success.rule.install()
local unchanged, unchangedReason = success.rule.unchanged()
assert(installed and unchanged and installReason == 'installed' and unchangedReason == 'installed')
local owned, ownedReason = success.rule.matchesComplete(function() end)
assert(not owned and ownedReason == 'completion-not-owned', 'foreign completion diagnostic changed')
local ordinary = setup({override = false})
assert(ordinary.action:complete() == true and ordinary.effects.amount == 4 and ISWashClothing.GetRequiredWater == ordinary.water,
    'direct native water/completion result changed')
for _, options in ipairs({{inactive = true}, {changedWMI = true}, {changedNative = true}, {foreign = 'useSoap'}, {foreign = 'complete'},
    {foreignIndex = true}, {foreignSuper = true}, {foreignMetatable = true}, {foreignBaseDerive = true}, {foreignWashDerive = true}}) do
    local f = setup(options)
    assert(f.owner.complete == f.before and not f.rule.matchesComplete(f.before), 'unreviewed sources/methods received cleanup wrapper')
    local intact, reason = f.rule.unchanged()
    assert(not intact and reason == f.startupReason and type(reason) == 'string' and #reason <= 90,
        'installation refusal lost its bounded diagnostic reason')
end
local foreignBase = setup()
ISBaseTimedAction.derive = function() end
local intact, reason = foreignBase.rule.unchanged()
assert(not intact and reason == 'hierarchy:base-own-derive', 'foreign base derive callback received native alias proof')
local diagnostic = setup()
diagnostic.owner[string.rep('x', 300)] = function() end
local intact, reason = diagnostic.rule.unchanged()
assert(not intact and reason == 'method-added:' .. string.rep('x', 64), 'method diagnostic is not bounded')
for _, change in ipairs({
    function(f) f.owner.__index = {} end,
    function(f) f.owner.SuperType = {} end,
    function() ISBaseTimedAction.new = function() end end,
    function() ISBaseObject.derive = function() end end,
}) do
    local f = setup(); change(f)
    assert(not f.rule.matchesComplete(f.owner.complete), 'foreign live inheritance/construction retained cleanup proof')
end
local replaced = setup({fail = true})
replaced.owner.useSoap = function() return true end
local completed, message = pcall(replaced.action.complete, replaced.action)
assert(not completed and message == replaced.failure and replaced.owner.GetRequiredWater ~= replaced.water
    and not replaced.rule.matchesComplete(replaced.owner.complete), 'live replaced method lost the original fallback')
local foreignWater = function() return 9 end
local foreign = setup({fail = true, onWater = function() ISWashClothing.GetRequiredWater = foreignWater end})
completed, message = pcall(foreign.action.complete, foreign.action)
assert(not completed and message == foreign.failure and foreign.owner.GetRequiredWater == foreignWater,
    'cleanup overwrote a foreign replacement instead of the reviewed temporary rule')
local observed = setup({fail = true})
local nativePerform, observations = observed.action.perform, 0
observed.action.perform = function(self, ...) observations = observations + 1; return nativePerform(self, ...) end
completed, message = pcall(observed.action.complete, observed.action)
assert(not completed and message == observed.failure and observed.owner.GetRequiredWater == observed.water
    and observations == 0 and observed.effects.water == 1 and observed.effects.blood == 1
    and observed.effects.fields == 1 and observed.effects.visuals == 1 and observed.effects.hands == 1,
    'an observation-only perform wrapper bypassed completion cleanup or replayed native effects')
local instance = setup({fail = true})
local calls = 0
instance.action.complete = function() calls = calls + 1; error(instance.failure, 0) end
completed, message = pcall(instance.owner.complete, instance.action)
assert(not completed and message == instance.failure and calls == 0 and instance.owner.GetRequiredWater ~= instance.water
    and instance.effects.water == 1, 'foreign instance completion received source-owned cleanup instead of the original fallback')
local noOverride = setup({fail = true, override = false})
completed, message = pcall(noOverride.action.complete, noOverride.action)
assert(not completed and message == noOverride.failure and noOverride.owner.GetRequiredWater == noOverride.water,
    'ordinary native failure changed the class water rule')
local direct = setup({foreign = 'complete'})
local function pack(...) return {n = select('#', ...), ...} end
local result = pack(direct.action:complete())
assert(result.n == 3 and result[1] == 'foreign' and result[2] == nil and result[3] == 4,
    'fallback completion tuple changed')
rawget = stockRawget
TestWashWaterRulePassed = true
print('WMI water restoration tests passed.')
