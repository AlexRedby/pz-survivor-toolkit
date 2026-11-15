-- Qualification observes the installed mod's ordinary callback and timed action.
-- This module never supplies the effects it is meant to verify.
local S = {}

local function itemID(item) return item and item:getID() or -1 end
local function queue(player) return ISTimedActionQueue.getTimedActionQueue(player) end
local function now() return getTimestampMs() end

local function vehicle(ids)
    -- SP vehicles need not have a registered network ID. Keep the fixture's exact
    -- local reference; MP packets contain only the numeric ID.
    local value = ids.vehicle or getVehicleById(ids.vehicleID)
    if value and value:isRemovedFromWorld() then return nil end
    return value
end

function S.observe(player, ids)
    assert(player and ids, 'salvage observation needs actor and fixture identities')
    local inventory = player:getInventory()
    local torch = inventory:getItemWithIDRecursiv(ids.torchID)
    local container = torch and torch:getContainer()
    local maskWornID = -1
    local worn = player:getWornItems()
    for i = 0, worn:size() - 1 do
        local item = worn:get(i):getItem()
        if itemID(item) == ids.maskID then maskWornID = ids.maskID end
    end
    local square = assert(getCell():getGridSquare(ids.x, ids.y, ids.z), 'salvage square is not loaded')
    local ground = {}
    local objects = square:getWorldObjects()
    for i = 0, objects:size() - 1 do
        local item = objects:get(i):getItem()
        if item then ground[#ground + 1] = {id = item:getID(), fullType = item:getFullType()} end
    end
    table.sort(ground, function(a, b) return a.id < b.id end)
    return {
        vehicleID = ids.vehicleID, vehicleKey = ids.vehicleKey, removed = vehicle(ids) == nil,
        torchID = ids.torchID, torchPresent = torch ~= nil,
        torchUses = torch and torch:getCurrentUses() or -1,
        torchContainerType = container and container:getType() or '',
        torchInRoot = container == inventory,
        primaryID = itemID(player:getPrimaryHandItem()), secondaryID = itemID(player:getSecondaryHandItem()),
        maskID = ids.maskID, maskWornID = maskWornID,
        metalWeldingXP = player:getXp():getXP(Perks.MetalWelding),
        x = ids.x, y = ids.y, z = ids.z, ground = ground,
    }
end

local function groundDelta(before, after)
    local old, added = {}, {}
    for _, item in ipairs(before.ground) do old[item.id] = item.fullType end
    for _, item in ipairs(after.ground) do
        if old[item.id] then
            if old[item.id] ~= item.fullType then return nil, 'preexisting ground item changed type' end
            old[item.id] = nil
        else added[#added + 1] = item end
    end
    for _ in pairs(old) do return nil, 'preexisting ground item disappeared during salvage' end
    return added
end

-- Expected replication lag must not invoke Lua assert: Kahlua logs caught assertions.
local function ready(before, after, mode)
    if before.vehicleID ~= after.vehicleID or before.torchID ~= after.torchID
        or before.vehicleKey ~= after.vehicleKey or before.maskID ~= after.maskID then
        return nil, 'salvage fixture identity changed'
    end
    if before.removed or not before.torchPresent then return nil, 'invalid salvage baseline' end
    if not after.torchPresent or not after.torchInRoot then return nil, 'owned salvage torch left root inventory' end
    local added, reason = groundDelta(before, after)
    if not added then return nil, reason end
    if mode == 'complete' then
        if not after.removed then return nil, 'salvage vehicle removal not observed' end
        if before.torchUses - after.torchUses ~= 10 then return nil, 'salvage torch consumption is not ten uses' end
        if after.metalWeldingXP <= before.metalWeldingXP then return nil, 'salvage XP effect not observed' end
        if #added == 0 then return nil, 'salvage material output inconclusive: no new ground items observed' end
    else
        if after.removed then return nil, 'cancelled salvage removed vehicle' end
        if after.torchUses ~= before.torchUses then return nil, 'cancelled salvage consumed torch' end
        if after.metalWeldingXP ~= before.metalWeldingXP then return nil, 'cancelled salvage awarded XP' end
        if #added ~= 0 then return nil, 'cancelled salvage produced ground items' end
    end
    return added
end

function S.validate(before, after, mode)
    assert(mode == 'complete' or mode == 'cancel', 'unknown salvage mode')
    local result, reason = ready(before, after, mode)
    assert(result, reason)
    return result
end

local function findOption(menu)
    local found
    for _, option in ipairs(menu.options or {}) do
        if option.onSelect == ISVehicleMenu.onVehicleSalvage then
            assert(not found, 'duplicate native salvage menu option')
            found = option
        end
        if option.subOption then
            local sub = menu:getSubMenu(option.subOption)
            local child = sub and findOption(sub)
            assert(not (found and child), 'duplicate native salvage menu option')
            found = found or child
        end
    end
    return found
end

local function capture(state)
    for _, action in ipairs(queue(state.player).queue) do
        if action.Type == 'ISVehicleSalvage' then
            assert(not state.action or state.action == action, 'duplicate native salvage action')
            assert(action.character == state.player and action.vehicle == state.vehicle, 'native salvage target changed')
            state.action = action
        end
    end
end

function S.close(state)
    if state and state.menu and not state.closed then
        -- Do not hide another menu if the shared native instance has been reused.
        if not state.option then state.menu:hideAndChildren() end
        if state.option and state.menu.options then
            for _, option in ipairs(state.menu.options) do
                if option == state.option then state.menu:hideAndChildren(); break end
            end
        end
        state.closed = true
    end
end

function S.start(player, ids, mode)
    assert(mode == 'complete' or mode == 'cancel', 'unknown salvage mode')
    assert(not player:isTimedActionInstant(), 'instant actions invalidate salvage qualification')
    assert(#queue(player).queue == 0, 'preexisting actions invalidate salvage baseline')
    assert(player:getCharacterActions():size() == 0 and not player:hasPath(),
        'preexisting native actions or path invalidate salvage baseline')
    assert(ISVehicleMenu and ISVehicleMenu.onVehicleSalvage, 'installed VSO menu callback is unavailable')
    assert(ISVehicleSalvage, 'installed VSO timed action is unavailable')
    local target = assert(vehicle(ids), 'fixture salvage vehicle is unavailable')
    local state = {player = player, ids = ids, vehicle = target, mode = mode,
        before = S.observe(player, ids), since = now(),
        sourceDuration = 2000 - player:getPerkLevel(Perks.MetalWelding) * 20}
    assert(state.before.torchPresent and state.before.torchUses >= 10 and state.before.torchInRoot,
        'salvage fixture needs owned root-inventory torch with ten uses')
    local menu = ISContextMenu.get(player:getPlayerNum(), 150, 150)
    state.menu = menu
    local ok, reason = pcall(function()
        ISVehicleMenu.FillMenuOutsideVehicle(player:getPlayerNum(), menu, target, false)
        local option = assert(findOption(menu), 'native salvage menu option is absent')
        state.option = option
        assert(not option.notAvailable, 'native salvage menu option is disabled')
        option.onSelect(option.target, option.param1, option.param2, option.param3,
            option.param4, option.param5, option.param6)
        state.menuCallback = true
        capture(state)
        assert(state.action, 'native menu did not enqueue salvage action')
    end)
    S.close(state)
    if not ok then error(reason) end
    return state
end

local function signature(observed)
    local values = {tostring(observed.removed), observed.torchUses, observed.metalWeldingXP,
        observed.primaryID, observed.secondaryID, observed.maskWornID, tostring(observed.torchInRoot), observed.torchContainerType}
    for _, item in ipairs(observed.ground) do
        values[#values + 1] = tostring(item.id) .. ':' .. item.fullType
    end
    return table.concat(values, '|')
end

function S.poll(state)
    if state.receipt then return state.receipt end
    assert(now() - state.since < 300000, 'native salvage timeout: ' .. tostring(state.problem or 'action did not drain'))
    local action, actions = state.action, queue(state.player)
    if actions.current == action and action.action and action:isStarted() then
        local progress = action:getJobDelta()
        if progress > 0 then
            state.started = true
            state.nativeDuration = action.maxTime
            assert(state.nativeDuration and state.nativeDuration > 1, 'native salvage duration was bypassed')
            assert(itemID(state.player:getPrimaryHandItem()) == state.ids.torchID, 'native salvage borrowed another torch')
            assert(S.observe(state.player, state.ids).maskWornID == state.ids.maskID,
                'native salvage did not wear the owned welding mask')
            if state.mode == 'cancel' and not state.cancelled then
                assert(progress < .9, 'native salvage could not be cancelled before completion')
                action.action:forceStop()
                state.cancelled = true
            end
        end
    end
    if #actions.queue ~= 0 or actions.current ~= nil or state.player:getCharacterActions():size() ~= 0
        or state.player:hasPath() then
        state.settleSince = nil
        state.lastSignature = nil
        return nil
    end
    assert(state.started, 'native salvage drained before ordinary progress was observed')
    assert(state.mode ~= 'cancel' or state.cancelled, 'native salvage cancellation was not issued')
    local after = S.observe(state.player, state.ids)
    local result, reason = ready(state.before, after, state.mode)
    if not result then
        state.problem = reason
        state.settleSince = nil
        state.drainedSince = state.drainedSince or now()
        assert(now() - state.drainedSince < 20000, 'native salvage effects failed: ' .. state.problem)
        return nil
    end
    local current = signature(after)
    if state.lastSignature ~= current then state.lastSignature = current; state.settleSince = now() end
    if now() - state.settleSince < 1500 then return nil end
    state.receipt = {mode = state.mode, vehicleID = state.ids.vehicleID, vehicleKey = state.ids.vehicleKey,
        before = state.before, after = after,
        started = true, nativeDuration = state.nativeDuration, sourceDuration = state.sourceDuration,
        cancelled = state.cancelled == true, menuCallback = state.menuCallback == true, drops = result,
        luaActions = 0, nativeActions = 0, hasPath = false}
    return state.receipt
end

return S
