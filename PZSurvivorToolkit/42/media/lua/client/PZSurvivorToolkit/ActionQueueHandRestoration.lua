-- Pure, one-shot scheduling obligation for an ordinary primary-hand tool.
-- Rows have exactly Hands' item/requiresBoth/handWeapon/handgun fields; states
-- have primary/secondary rows (or false). Item identities are opaque.
--
-- capture(before, after, tool) verifies the projected native preparation write.
-- The caller must separately earn that exact native episode/hand outcome and
-- exclude heavy, worn, hotbar, optional two-hand, activation and other effects.
-- Restoring an empty prior primary projects an exact-tool primary unequip;
-- an independently held secondary remains unchanged.
-- propose(handle, current) returns an opaque proposal and a detached plan DTO.
-- consume(handle, proposal, current) consumes the scheduling right BEFORE any
-- native restore is issued and returns a fresh DTO. It proves no native effect,
-- pays no debt and cannot authorize replay after an unknown outcome. Settlement
-- must retain unresolved debt until its separately authenticated native result.
-- waive(handle) is explicit caller intent, distinct from consuming a proposal.
-- A temporarily stale current snapshot grants nothing and does not waive debt.
-- Handles must stay in the caller's private episode; never import public or
-- caller-supplied handles. This pure helper grants no native/admission rights.
-- Valid snapshots invoke no getters or native actions. Inspecting a forged
-- handle may invoke its foreign seal, which cannot export state or mint a plan;
-- this boundary is not a sandbox for arbitrary callbacks supplied as handles.
local Hands = require 'PZSurvivorToolkit/ActionQueueHands'
local Model = require 'PZSurvivorToolkit/ActionQueueEditModel'
local Toolkit = PZSurvivorToolkit
local Restoration = {}
Toolkit.ActionQueueHandRestoration = Restoration
local equip, evaluate = Hands.equipResource, Model.evaluate
local kind, meta, each, equal, raw = type, getmetatable, pairs, rawequal, rawget
local globals = _G
-- State lives with its exact handle, never in a global map. Native Kahlua's
-- lifetime must not depend on Lua 5.1 weak-key collection. The seal exports no
-- state: only its minted handle can fill this synchronous private dispatch slot.
local sealMarker, dispatchHandle, dispatchState = {}, nil, nil
local busy = false
local capture, propose, consume, waive
local rowFields = {item=true, requiresBoth=true, handWeapon=true, handgun=true}
local stateFields = {primary=true, secondary=true}
local function plain(value, fields)
    if kind(value) ~= 'table' or meta(value) ~= nil then return false end
    for key in each(value) do if not fields[key] then return false end end
    return true
end
local function row(value)
    if not plain(value, rowFields) then return end
    local item = raw(value, 'item')
    if (kind(item) ~= 'table' and kind(item) ~= 'userdata')
        or kind(raw(value, 'requiresBoth')) ~= 'boolean'
        or kind(raw(value, 'handWeapon')) ~= 'boolean'
        or kind(raw(value, 'handgun')) ~= 'boolean' then return end
    if value.requiresBoth or value.handgun then return nil, 'unsupported_traits' end
    return {item=item, requiresBoth=false, handWeapon=value.handWeapon, handgun=false}
end
local function copyRow(value)
    if value == false then return false end
    return {item=value.item, requiresBoth=value.requiresBoth, handWeapon=value.handWeapon, handgun=value.handgun}
end
local function sameRow(left, right)
    if left == false or right == false then return left == right end
    return equal(left.item, right.item) and left.requiresBoth == right.requiresBoth
        and left.handWeapon == right.handWeapon and left.handgun == right.handgun
end
local function snapshot(value)
    if not plain(value, stateFields) then return nil, 'invalid_input' end
    local result = {}
    for _, side in ipairs({'primary', 'secondary'}) do
        local input = raw(value, side)
        if input == false then result[side] = false
        else
            local saved, reason = row(input)
            if not saved then return nil, reason or 'invalid_input' end
            result[side] = saved
        end
    end
    if result.primary ~= false and result.secondary ~= false
        and equal(result.primary.item, result.secondary.item) then return nil, 'overlapping_hands' end
    return result
end
local function sameState(left, right)
    return sameRow(left.primary, right.primary) and sameRow(left.secondary, right.secondary)
end
local function copyState(value)
    return {primary=copyRow(value.primary), secondary=copyRow(value.secondary)}
end
local function trusted()
    return equal(_G, globals) and equal(raw(globals, 'PZSurvivorToolkit'), Toolkit)
        and meta(Toolkit) == nil and meta(Restoration) == nil and meta(Hands) == nil and meta(Model) == nil
        and equal(raw(Toolkit, 'ActionQueueHandRestoration'), Restoration)
        and equal(raw(Toolkit, 'ActionQueueHands'), Hands) and raw(Hands, 'equipResource') == equip
        and equal(raw(Toolkit, 'ActionQueueEditModel'), Model) and raw(Model, 'evaluate') == evaluate
        and raw(Restoration, 'capture') == capture and raw(Restoration, 'propose') == propose
        and raw(Restoration, 'consume') == consume and raw(Restoration, 'waive') == waive
end
local function facts(state)
    local result = {}
    for _, side in ipairs({'primary', 'secondary'}) do
        local value = state[side]
        result[side] = value ~= false and value.item or false
        result[side..'RequiresBoth'] = value ~= false and value.requiresBoth or false
        result[side..'HandWeapon'] = value ~= false and value.handWeapon or false
        result[side..'Handgun'] = value ~= false and value.handgun or false
    end
    return result
end
local function projects(key, before, incoming, expected)
    local resource
    if incoming == false then
        -- The caller separately authenticates native unequip and excludes its
        -- non-hand effects. This resource clears only the exact held tool;
        -- capture rejects moving it from secondary or overlapping hand slots.
        if before.primary == false then return nil, 'assignment_refused' end
        resource = {domain='hands', key=key, facts=facts(before),
            requires={{field='primary', equal=before.primary.item}}, effects={
                {field='primary', set=false}, {field='primaryRequiresBoth', set=false},
                {field='primaryHandWeapon', set=false}, {field='primaryHandgun', set=false}}}
    else resource = equip(key, copyState(before), copyRow(incoming), 'primary') end
    if not trusted() then return nil, 'source_changed' end
    if kind(resource) ~= 'table' then return nil, 'assignment_refused' end
    local requires = {}
    for field, value in each(facts(expected)) do requires[#requires+1] = {field=field, equal=value} end
    local decision = evaluate({
        {action={}, edit={version=1, complete=true, capacity='unchanged', resources={resource}}},
        {action={}, edit={version=1, complete=true, capacity='unchanged', resources={
            {domain='hands', key=key, facts=facts(before), requires=requires}}}},
    })
    if not trusted() then return nil, 'source_changed' end
    if kind(decision) ~= 'table' or decision.status ~= 'allowed' then return nil, 'assignment_mismatch' end
    return true
end
local function obligation(handle)
    if kind(handle) ~= 'table' or meta(handle) ~= nil then return end
    for key in each(handle) do if not equal(key, sealMarker) then return end end
    local seal = raw(handle, sealMarker)
    if kind(seal) ~= 'function' then return end
    dispatchHandle, dispatchState = handle, nil
    local ok = pcall(seal)
    local state = dispatchState
    dispatchHandle, dispatchState = nil, nil
    if not trusted() then return nil, 'source_changed' end
    if ok then return state end
end
local function plan(state)
    return {mode=state.before.primary == false and 'unequip' or 'primary',
        incoming=copyRow(state.before.primary), expected=copyState(state.before)}
end
local function guarded(callback, ...)
    if busy then return nil, 'reentrant' end
    if not trusted() then return nil, 'source_changed' end
    busy = true
    local ok, value, detail = pcall(callback, ...)
    busy = false
    if not ok then return nil, 'invalid_input' end
    return value, detail
end
local function captureState(before, after, tool)
    local initial, reason = snapshot(before)
    if not initial then return nil, reason end
    local prepared; prepared, reason = snapshot(after)
    if not prepared then return nil, reason end
    local incoming; incoming, reason = row(tool)
    if not incoming then return nil, reason or 'invalid_input' end
    if sameRow(initial.primary, incoming) then return nil, 'unchanged_primary' end
    if initial.secondary ~= false and equal(initial.secondary.item, incoming.item) then return nil, 'overlapping_hands' end
    if not sameRow(initial.secondary, prepared.secondary) then return nil, 'secondary_changed' end
    -- The same opaque item cannot acquire different native traits between rows.
    local rows = {incoming}
    if initial.primary ~= false then rows[#rows+1] = initial.primary end
    if initial.secondary ~= false then rows[#rows+1] = initial.secondary end
    if prepared.primary ~= false then rows[#rows+1] = prepared.primary end
    for i, left in ipairs(rows) do
        for j = i+1, #rows do
            if equal(left.item, rows[j].item) and not sameRow(left, rows[j]) then return nil, 'inconsistent_traits' end
        end
    end
    local key = {}
    local accepted; accepted, reason = projects(key, initial, incoming, prepared)
    if not accepted then return nil, reason end
    accepted, reason = projects(key, prepared, initial.primary, initial)
    if not accepted then return nil, reason end
    local handle = {}
    local state = {before=initial, after=prepared, key=key, phase='open'}
    handle[sealMarker] = function()
        if equal(dispatchHandle, handle) then dispatchState = state end
    end
    return handle
end
local function proposeState(handle, current)
    local state, reason = obligation(handle)
    if not state then return nil, reason or 'unknown_obligation' end
    if state.phase ~= 'open' then return nil, 'not_open' end
    local observed, reason = snapshot(current)
    if not observed then return nil, reason end
    if not sameState(observed, state.after) then return nil, 'current_changed' end
    local accepted; accepted, reason = projects(state.key, observed, state.before.primary, state.before)
    if not accepted then return nil, reason end
    local proposal = {}
    state.proposal, state.phase = proposal, 'proposed'
    return proposal, plan(state)
end
local function consumeState(handle, proposal, current)
    local state, reason = obligation(handle)
    if not state then return nil, reason or 'unknown_obligation' end
    if state.phase ~= 'proposed' or not equal(state.proposal, proposal) then return nil, 'invalid_proposal' end
    local observed, reason = snapshot(current)
    if not observed then return nil, reason end
    if not sameState(observed, state.after) then return nil, 'current_changed' end
    local result = plan(state)
    state.phase, state.proposal, state.before, state.after, state.key = 'consumed', nil, nil, nil, nil
    return result
end
local function waiveState(handle)
    local state, reason = obligation(handle)
    if not state then return nil, reason or 'unknown_obligation' end
    if state.phase ~= 'open' and state.phase ~= 'proposed' then return nil, 'not_open' end
    state.phase, state.proposal, state.before, state.after, state.key = 'waived', nil, nil, nil, nil
    return true
end
capture = function(...)
    if select('#', ...) ~= 3 then return nil, 'invalid_input' end
    return guarded(captureState, ...)
end
propose = function(...)
    if select('#', ...) ~= 2 then return nil, 'invalid_input' end
    return guarded(proposeState, ...)
end
consume = function(...)
    if select('#', ...) ~= 3 then return nil, 'invalid_input' end
    return guarded(consumeState, ...)
end
waive = function(...)
    if select('#', ...) ~= 1 then return nil, 'invalid_input' end
    return guarded(waiveState, ...)
end
Restoration.capture, Restoration.propose, Restoration.consume, Restoration.waive = capture, propose, consume, waive
return Restoration
