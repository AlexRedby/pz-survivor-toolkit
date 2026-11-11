-- Pure hand-assignment projection. Native admission, timings, item lookup,
-- selected-mod callbacks and network freshness remain separate contracts.
if not NativeActionRoot then
    if TestCoverage then TestCoverage('source-contract', 'skipped', 'Hand assignment oracle requires --game or --native-action-root.') end
    return
end

local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/'
local env = setmetatable({PZSurvivorToolkit = {}}, {__index = _G})
local Model = assert(setfenv(assert(loadfile(root .. 'ActionQueueEditModel.lua')), env))()
local Hands = assert(setfenv(assert(loadfile(root .. 'ActionQueueHands.lua')), env))()
assert(env.PZSurvivorToolkit.ActionQueueHands == Hands)
for key, value in pairs(Hands) do
    assert(key == 'equipResource' and type(value) == 'function', 'hand assignment exposes unexpected authority')
end

local nativePath = NativeActionRoot .. '/shared/TimedActions/ISEquipWeaponAction.lua'
local nativeSource
if NativeReadText then nativeSource = NativeReadText(nativePath)
else
    local file = assert(io.open(nativePath)); nativeSource = file:read('*a'); file:close()
end

local getterCalls, hiddenCalls = 0, 0
local traits = {}
local function descriptor(requiresBoth, handWeapon, handgun)
    local item = {}
    local row = {item = item, requiresBoth = requiresBoth, handWeapon = handWeapon, handgun = handgun}
    traits[item] = row
    function item:isRequiresEquippedBothHands() getterCalls = getterCalls + 1; return row.requiresBoth end
    function item:getSwingAnim() getterCalls = getterCalls + 1; return row.handgun and 'Handgun' or 'Other' end
    function item:canBeActivated() getterCalls = getterCalls + 1; return false end
    function item:getCurrentUsesFloat() getterCalls = getterCalls + 1; return 1 end
    function item:isActivated() getterCalls = getterCalls + 1; return false end
    function item:hasTag() getterCalls = getterCalls + 1; return false end
    function item:getScriptItem() getterCalls = getterCalls + 1; return {isItemType = function() return false end} end
    return row
end
-- Distinct identities share traits deliberately. Optional two-hand support is
-- a constructor concern: this API receives the already normalized mode.
local normalA, normalB = descriptor(false, false, false), descriptor(false, false, false)
local tool, bat = descriptor(false, true, false), descriptor(false, true, false)
local required, handgun = descriptor(true, true, false), descriptor(false, true, true)
local requiredNormal = descriptor(true, false, false)
local requiredHandgun = descriptor(true, true, true)
local items = {normalA, normalB, tool, bat, required, handgun, requiredNormal, requiredHandgun}
local slots = {false, normalA, normalB, tool, bat, required, handgun, requiredNormal, requiredHandgun}
local modes = {'primary', 'secondary', 'both'}
local actor = {}
local function identity(row) return row and row.item or false end
local function snapshot(primary, secondary) return {primary = primary, secondary = secondary} end

local fields = {'primary', 'secondary', 'primaryRequiresBoth', 'primaryHandWeapon', 'primaryHandgun',
    'secondaryRequiresBoth', 'secondaryHandWeapon', 'secondaryHandgun'}
local function flat(state)
    local primary, secondary = state.primary, state.secondary
    return {primary = identity(primary), secondary = identity(secondary),
        primaryRequiresBoth = primary and primary.requiresBoth or false,
        primaryHandWeapon = primary and primary.handWeapon or false,
        primaryHandgun = primary and primary.handgun or false,
        secondaryRequiresBoth = secondary and secondary.requiresBoth or false,
        secondaryHandWeapon = secondary and secondary.handWeapon or false,
        secondaryHandgun = secondary and secondary.handgun or false}
end
local function sameFacts(left, right)
    for _, field in ipairs(fields) do assert(rawequal(left[field], right[field]), 'hand fact mismatch: ' .. field) end
    for field in pairs(left) do
        local known = false; for _, expected in ipairs(fields) do if field == expected then known = true end end
        assert(known, 'unexpected hand fact: ' .. tostring(field))
    end
end
local function declaration(initial, command)
    local before = getterCalls
    local resource = assert(Hands.equipResource(actor, initial, command.incoming, command.mode), 'valid assignment rejected')
    assert(getterCalls == before, 'hand projection called an item getter')
    assert(resource.domain == 'hands' and rawequal(resource.key, actor), 'hand resource identity differs')
    assert(resource.complete == nil and resource.capacity == nil and resource.outcome == nil and resource.effects == nil,
        'assignment resource gained completion/capacity/outcome authority')
    sameFacts(resource.facts, flat(initial))
    return {action = command, edit = {version = 1, complete = true, capacity = 'unchanged', resources = {resource}}}
end
local function probe(initial, expected, wrongField)
    local facts, requires = flat(initial), {}
    for _, field in ipairs(fields) do
        local value = expected[field]
        if field == wrongField then
            if field == 'primary' or field == 'secondary' then
                if rawequal(value, normalA.item) then value = false else value = normalA.item end
            else value = not value end
        end
        requires[#requires + 1] = {field = field, equal = value}
    end
    return {action = {}, edit = {version = 1, complete = true, capacity = 'unchanged', resources = {
        {domain = 'hands', key = actor, facts = facts, requires = requires},
    }}}
end

-- Execute the installed native body as an independent oracle. Its own early
-- isAlreadyEquipped gate runs before clearing; no generated case is decoded.
local native = setmetatable({require = function() end,
    ISBaseTimedAction = {derive = function(_, name) return {Type = name} end},
    ItemTag = {REPLACE_PRIMARY = {}, LIGHTER = {}}, ItemType = {RADIO = {}},
}, {__index = _G})
local server, sends, refreshes = false, 0, 0
native.isServer = function() return server end
native.instanceof = function(item, class)
    assert(class == 'HandWeapon', 'unexpected native class query')
    local row = traits[item]; return row and row.handWeapon or false
end
native.getPlayerInventory = function() return {refreshBackpacks = function() refreshes = refreshes + 1 end} end
native.sendEquip = function() sends = sends + 1 end
native.syncItemActivated = function() error('excluded activation path executed') end
native.triggerEvent = function() error('excluded clothing path executed') end
assert(setfenv(assert(loadstring(nativeSource, '@' .. nativePath)), native))()
local NativeAction = assert(native.ISEquipWeaponAction)
local function execute(initial, commands, serverSide)
    server = serverSide == true
    local writes = 0
    local player = {primary = initial.primary and initial.primary.item or nil, secondary = initial.secondary and initial.secondary.item or nil}
    function player:getPrimaryHandItem() return self.primary end
    function player:getSecondaryHandItem() return self.secondary end
    function player:setPrimaryHandItem(item) self.primary = item; writes = writes + 1 end
    function player:setSecondaryHandItem(item) self.secondary = item; writes = writes + 1 end
    function player:getClothingItem_Back() return nil end
    function player:isEquippedClothing() return false end
    function player:getCurrentSquare() return nil end -- native forceDropHeavyItems has no excluded drop work
    function player:getPlayerNum() return 0 end
    local noops = 0
    for _, command in ipairs(commands) do
        local action = setmetatable({character = player, item = command.incoming.item,
            primary = command.mode == 'primary', twoHands = command.mode == 'both'}, {__index = NativeAction})
        local beforeWrites = writes
        local already = action:isAlreadyEquipped()
        local completed = action:complete()
        assert(completed == not already, 'native early no-op outcome differs')
        if already then assert(writes == beforeWrites, 'native no-op changed hands'); noops = noops + 1 end
    end
    return snapshot(player.primary and assert(traits[player.primary]) or false,
        player.secondary and assert(traits[player.secondary]) or false), noops
end
local function checked(initial, commands, serverSide, wrongProbes)
    local initialFacts = flat(initial)
    local expected, noops = execute(initial, commands, serverSide)
    local entries = {}
    for _, command in ipairs(commands) do entries[#entries + 1] = declaration(initial, command) end
    local expectedFacts = flat(expected)
    entries[#entries + 1] = probe(initial, expectedFacts)
    local before = getterCalls
    local decision = Model.evaluate(entries)
    assert(decision.status == 'allowed', 'native hand result rejected: ' .. tostring(decision.reason) .. ':' .. tostring(decision.field))
    if wrongProbes then
        for _, field in ipairs(fields) do
            entries[#entries] = probe(initial, expectedFacts, field)
            decision = Model.evaluate(entries)
            assert(decision.status == 'denied' and decision.reason == 'edit_required_state', 'wrong hand result accepted: ' .. field)
        end
    end
    assert(getterCalls == before, 'edit model executed item callbacks')
    sameFacts(flat(initial), initialFacts)
    return noops
end

local noops = 0
for _, primary in ipairs(slots) do for _, secondary in ipairs(slots) do
    local initial = snapshot(primary, secondary)
    for _, incoming in ipairs(items) do for _, mode in ipairs(modes) do
        local commands = {{incoming = incoming, mode = mode}}
        noops = noops + checked(initial, commands, false, true)
        checked(initial, commands, true, false)
    end end
end end
assert(noops > 0 and sends > 0 and refreshes > 0, 'native oracle did not cover early no-op and both source-side branches')

-- All declarations share one current snapshot. The native oracle mutates its
-- current hands for each proposed ordering, so later branch reads must observe
-- projected traits and identities, not those of the captured initial hands.
local bank = {
    {incoming = normalA, mode = 'primary'}, {incoming = normalB, mode = 'secondary'},
    {incoming = tool, mode = 'secondary'}, {incoming = bat, mode = 'both'},
    {incoming = required, mode = 'primary'}, {incoming = requiredNormal, mode = 'both'},
    {incoming = handgun, mode = 'primary'},
}
local starts = {snapshot(false, false), snapshot(normalA, normalB), snapshot(tool, normalA),
    snapshot(bat, bat), snapshot(required, false), snapshot(false, requiredNormal), snapshot(handgun, tool)}
for _, initial in ipairs(starts) do
    for ai, first in ipairs(bank) do for bi, second in ipairs(bank) do
        local commands = {first, second, bank[(ai + bi) % #bank + 1]}
        checked(initial, commands, false, false)
        for removed = 1, #commands do
            local rest = {}; for i, command in ipairs(commands) do if i ~= removed then rest[#rest + 1] = command end end
            checked(initial, rest, false, false)
            for destination = 1, #commands do
                local moved = {}; for _, command in ipairs(rest) do moved[#moved + 1] = command end
                table.insert(moved, destination, commands[removed])
                checked(initial, moved, false, false)
            end
            -- Removed actions still declare the current snapshot, with none of
            -- their assignment effects applied to the surviving native chain.
            local entries = {}
            for i, command in ipairs(commands) do
                local entry = declaration(initial, command); if i == removed then entry.snapshotOnly = true end
                entries[#entries + 1] = entry
            end
            entries[#entries + 1] = probe(initial, flat((execute(initial, rest, false))))
            assert(Model.evaluate(entries).status == 'allowed', 'removed assignment affected native surviving chain')
        end
    end end
end

-- Opaque values can carry hostile metamethods and are identities only. Rows
-- and snapshots, by contrast, are bounded plain structures with exact fields.
local hostile = {__eq = function() hiddenCalls = hiddenCalls + 1; error('opaque equality called') end,
    __index = function() hiddenCalls = hiddenCalls + 1; error('opaque getter called') end,
    __pairs = function() hiddenCalls = hiddenCalls + 1; error('opaque enumeration called') end}
local opaqueActor, opaqueA, opaqueB = setmetatable({}, hostile), setmetatable({}, hostile), setmetatable({}, hostile)
local opaqueRowA = {item = opaqueA, requiresBoth = false, handWeapon = false, handgun = false}
local opaqueRowB = {item = opaqueB, requiresBoth = false, handWeapon = false, handgun = false}
local opaqueState = snapshot(opaqueRowA, opaqueRowB)
local opaqueResource = assert(Hands.equipResource(opaqueActor, opaqueState, opaqueRowA, 'secondary'))
assert(rawequal(opaqueResource.key, opaqueActor))
local opaqueProbe = {domain = 'hands', key = opaqueActor, facts = flat(opaqueState), requires = {
    {field = 'primary', equal = false}, {field = 'secondary', equal = opaqueA},
}}
assert(Model.evaluate({{action = {}, edit = {version = 1, complete = true, capacity = 'unchanged', resources = {opaqueResource}}},
    {action = {}, edit = {version = 1, complete = true, capacity = 'unchanged', resources = {opaqueProbe}}}}).status == 'allowed')
assert(hiddenCalls == 0, 'pure hand assignment inspected opaque values')

local function copyRow(row)
    return {item = row.item, requiresBoth = row.requiresBoth, handWeapon = row.handWeapon, handgun = row.handgun}
end
local malformed = {
    function(s) s.actor = false end, function(s) s.actor = true end, function(s) s.actor = 1 end,
    function(s) s.actor = 'actor' end, function(s) s.actor = function() error('never execute') end end,
    function(s) s.actor = nil end,
    function(s) s.state = false end, function(s) s.state = nil end,
    function(s) s.state.primary = nil end, function(s) s.state.secondary = nil end,
    function(s) s.state.extra = true end, function(s) setmetatable(s.state, hostile) end,
    function(s) s.state.primary = true end, function(s) s.state.secondary = 'item' end,
    function(s) s.incoming = false end, function(s) s.incoming = nil end,
    function(s) setmetatable(s.incoming, hostile) end,
    function(s) s.incoming.item = false end, function(s) s.incoming.item = true end,
    function(s) s.incoming.item = 1 end, function(s) s.incoming.item = 'item' end,
    function(s) s.incoming.item = function() error('never execute') end end,
    function(s) s.incoming.item = nil end,
    function(s) s.incoming.requiresBoth = nil end, function(s) s.incoming.requiresBoth = 1 end,
    function(s) s.incoming.handWeapon = nil end, function(s) s.incoming.handWeapon = 'weapon' end,
    function(s) s.incoming.handgun = nil end, function(s) s.incoming.handgun = 1 end,
    function(s) s.incoming.handgun = true end,
    function(s) s.incoming.extra = true end, function(s) s.incoming.callback = function() error('never execute') end end,
    function(s) s.state.primary = setmetatable(copyRow(normalA), hostile) end,
    function(s) s.state.primary.requiresBoth = not s.incoming.requiresBoth end,
    function(s) s.state.primary.handWeapon = not s.incoming.handWeapon end,
    function(s) s.state.primary.handgun = true; s.state.primary.handWeapon = true end,
    function(s) s.state.secondary = copyRow(s.state.primary); s.state.secondary.requiresBoth = true end,
    function(s) s.mode = false end, function(s) s.mode = nil end,
    function(s) s.mode = 'twoHands' end, function(s) s.mode = {} end,
}
for _, mutate in ipairs(malformed) do
    local test = {actor = opaqueActor, state = snapshot(copyRow(normalA), copyRow(normalB)), incoming = copyRow(normalA), mode = 'primary'}
    mutate(test)
    local before = getterCalls
    local result = Hands.equipResource(test.actor, test.state, test.incoming, test.mode)
    assert(result == nil, 'malformed hand snapshot accepted')
    assert(getterCalls == before and hiddenCalls == 0, 'malformed hand snapshot executed callbacks')
end
-- Separate rows with identical traits for the same opaque identity are valid.
assert(Hands.equipResource(opaqueActor, snapshot(copyRow(normalA), copyRow(normalA)), copyRow(normalA), 'both'))
assert(Hands.equipResource()==nil and Hands.equipResource(opaqueActor)==nil)
assert(Hands.equipResource(opaqueActor,opaqueState,opaqueRowA)==nil,'omitted mode borrowed native frame data')
assert(Hands.equipResource(opaqueActor,opaqueState,opaqueRowA,'primary',true)==nil,'unexpected input tuple accepted')
-- Captured facts and effects retain value metadata, not mutable descriptor
-- rows. A caller can reuse its data structures after declaring the component.
local captured = snapshot(copyRow(normalA), copyRow(normalB))
local mutableState, mutableIncoming = snapshot(copyRow(normalA), copyRow(normalB)), copyRow(requiredHandgun)
local resource = assert(Hands.equipResource(actor, mutableState, mutableIncoming, 'primary'))
mutableState.primary.item, mutableState.secondary.requiresBoth = tool.item, true
mutableIncoming.item, mutableIncoming.requiresBoth, mutableIncoming.handWeapon, mutableIncoming.handgun = normalA.item, false, false, false
sameFacts(resource.facts, flat(captured))
local entries = {{action = {}, edit = {version = 1, complete = true, capacity = 'unchanged', resources = {resource}}},
    probe(captured, flat((execute(captured, {{incoming = requiredHandgun, mode = 'primary'}}, false))))}
assert(Model.evaluate(entries).status == 'allowed', 'captured assignment retained mutable caller metadata')
assert(hiddenCalls == 0)
if TestCoverage then TestCoverage('source-contract', 'passed', 'Pure native hand-assignment oracle, projected chains, no-op precedence, removals and opaque malformed-input protection; no gameplay admission or network qualification.') end
print('Native hand-assignment oracle and pure projection checks passed.')
