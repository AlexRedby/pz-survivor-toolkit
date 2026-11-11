-- Pure projection of audited contracts. Native actions and their resources are never executed here.
local Model = {}
PZSurvivorToolkit.ActionQueueEditModel = Model

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function plain(value)
    return type(value) == "table" and getmetatable(value) == nil
end
local function scalar(value)
    local kind = type(value)
    return kind == "boolean" or kind == "string" or kind == "table" or kind == "userdata"
        or (kind == "number" and finite(value))
end
local function fields(value, allowed)
    if not plain(value) then return false end
    for key in pairs(value) do if not allowed[key] then return false end end
    return true
end
local function array(value)
    if not plain(value) then return end
    local count, maximum = 0, 0
    for key in pairs(value) do
        if not finite(key) or key < 1 or key % 1 ~= 0 then return end
        count, maximum = count + 1, math.max(maximum, key)
    end
    if count == maximum then return count end
end
local function result(status, reason, entry, key, field)
    return {status = status, reason = reason, blocker = entry and entry.action, resource = key, field = field}
end
local entryFields = {action = true, edit = true, deferred = true, active = true, snapshotOnly = true}
local editFields = {version = true, complete = true, capacity = true, resources = true}
local resourceFields = {domain = true, key = true, facts = true, requires = true, effects = true, cases = true, bounds = true}
local predicateFields = {field = true, equal = true, notEqual = true, oneOf = true, sameAs = true, min = true, max = true, above = true}
local caseFields = {when = true, effects = true}
local effectFields = {field = true, set = true, delta = true, toggle = true, cap = true, scale = true, deplete = true}
local deferredFields = {version=true,kind=true,actor=true,targetSquare=true,invalidates=true,routing=true,expansion=true,outcome=true}
local function deferredSpatial(value)
    if not fields(value,deferredFields) or value.version~=1 or value.kind~="deferred-spatial"
        or value.invalidates~="all-resources" or value.routing~="native" or value.expansion~="native" or value.outcome~="native" then return false end
    local actor,target=type(value.actor),type(value.targetSquare)
    return (actor=="table"or actor=="userdata")and(target=="table"or target=="userdata")
end
local boundFields = {min = true, max = true, reason = true}
local boundReasons = {edit_resource_amount = true, edit_capacity = true}
local function named(field)
    return type(field) == "string" and field ~= ""
end
local function range(value)
    return (value.min ~= nil or value.max ~= nil)
        and (value.min == nil or finite(value.min)) and (value.max == nil or finite(value.max))
        and (value.min == nil or value.max == nil or value.min <= value.max)
end
local function outside(value, bound)
    return (bound.min ~= nil and value < bound.min) or (bound.max ~= nil and value > bound.max)
        or (bound.above ~= nil and value <= bound.above)
end


local function numericPredicate(predicate)
    if predicate.above == nil then return range(predicate) end
    return finite(predicate.above) and (predicate.min == nil or finite(predicate.min))
        and (predicate.max == nil or finite(predicate.max))
        and (predicate.min == nil or predicate.max == nil or predicate.min <= predicate.max)
        and (predicate.max == nil or predicate.max > predicate.above)
end
local function validPredicate(predicate)
    if not fields(predicate, predicateFields) or not named(predicate.field) then return false end
    local numeric = predicate.min ~= nil or predicate.max ~= nil or predicate.above ~= nil
    if predicate.sameAs ~= nil then
        return named(predicate.sameAs) and predicate.equal == nil and predicate.notEqual == nil
            and predicate.oneOf == nil and not numeric
    end
    if predicate.equal ~= nil then return scalar(predicate.equal) and predicate.notEqual == nil and predicate.oneOf == nil and not numeric end
    if predicate.notEqual ~= nil then return scalar(predicate.notEqual) and predicate.oneOf == nil and not numeric end
    if predicate.oneOf ~= nil then
        if numeric then return false end
        local count = array(predicate.oneOf)
        if not count or count == 0 then return false end
        for i = 1, count do if not scalar(predicate.oneOf[i]) then return false end end
        return true
    end
    return numericPredicate(predicate)
end
local function validEffect(effect)
    if not fields(effect, effectFields) or not named(effect.field) then return false end
    local operations = (effect.set ~= nil and 1 or 0) + (effect.delta ~= nil and 1 or 0)
        + (effect.toggle ~= nil and 1 or 0) + (effect.cap ~= nil and 1 or 0) + (effect.scale ~= nil and 1 or 0)
        + (effect.deplete ~= nil and 1 or 0)
    local valid = operations == 1 and (effect.set == nil or scalar(effect.set))
        and (effect.delta == nil or finite(effect.delta)) and (effect.toggle == nil or effect.toggle == true)
        and (effect.cap == nil or finite(effect.cap))
        and (effect.scale == nil or finite(effect.scale) and effect.scale >= 0)
        and (effect.deplete == nil or fields(effect.deplete, {amount=true,minimum=true})
            and finite(effect.deplete.amount) and effect.deplete.amount >= 0
            and finite(effect.deplete.minimum) and effect.deplete.minimum >= 0)
    if not valid then return false, effect.field end
    return true
end
local function validPredicates(predicates)
    local count = array(predicates)
    if not count then return false end
    for i = 1, count do if not validPredicate(predicates[i]) then return false end end
    return true
end
local function validEffects(effects)
    local count = array(effects)
    if not count then return false end
    for i = 1, count do
        local valid, field = validEffect(effects[i])
        if not valid then return false, field end
    end
    return true
end
local function numericEffect(effect, value)
    if not finite(value) then return end
    local projected
    if effect.delta ~= nil then projected = value + effect.delta
    elseif effect.cap ~= nil then projected = math.min(value, effect.cap)
    elseif effect.scale ~= nil then projected = value * effect.scale
    elseif effect.deplete ~= nil then
        projected = value - effect.deplete.amount
        if not finite(projected) then return end
        if projected < effect.deplete.minimum then projected = 0 end
    end
    if finite(projected) then return projected end
end
local function predicateOperands(predicates, facts)
    for _, predicate in ipairs(predicates) do
        local value = facts[predicate.field]
        if value == nil or (predicate.equal == nil and predicate.notEqual == nil and predicate.oneOf == nil
            and predicate.sameAs == nil and not finite(value)) then return false, predicate.field end
        if predicate.sameAs ~= nil and facts[predicate.sameAs] == nil then return false, predicate.sameAs end
    end
    return true
end
local function effectOperands(effects, facts, bounds, beforeBoundary)
    for _, effect in ipairs(effects) do
        local value = facts[effect.field]
        local numeric = effect.delta ~= nil or effect.cap ~= nil or effect.scale ~= nil or effect.deplete ~= nil
        if value == nil or (numeric and (not finite(value) or beforeBoundary and numericEffect(effect, value) == nil))
            or (effect.toggle and type(value) ~= "boolean")
            or (effect.set ~= nil and bounds and bounds[effect.field] and not finite(effect.set)) then
            return false, effect.field
        end
    end
    return true
end
local function matches(predicate, facts)
    local value = facts[predicate.field]
    if predicate.equal ~= nil then return rawequal(value, predicate.equal), "edit_required_state" end
    if predicate.notEqual ~= nil then return not rawequal(value, predicate.notEqual), "edit_required_state" end
    if predicate.sameAs ~= nil then return rawequal(value, facts[predicate.sameAs]), "edit_required_state" end
    if predicate.oneOf ~= nil then
        for _, candidate in ipairs(predicate.oneOf) do if rawequal(value, candidate) then return true end end
        return false, "edit_required_state"
    end
    if not finite(value) then return nil, "edit_unknown" end
    return not outside(value, predicate), "edit_resource_amount"
end

function Model.evaluate(entries)
    local count = array(entries)
    if not count then return result("unhandled", "edit_unknown") end
    local domains, snapshots, plan = {}, {}, {}
    local deferred,firstDeferred
    for i = 1, count do
        local entry = entries[i]
        if not fields(entry, entryFields) or not scalar(entry.action)
            or (entry.active ~= nil and type(entry.active) ~= "boolean")
            or (entry.snapshotOnly ~= nil and type(entry.snapshotOnly) ~= "boolean") then
            return result("unhandled", "edit_unknown")
        end
        if entry.active then return result("unhandled", "edit_in_flight", entry) end
        if entry.deferred~=nil then
            if entry.edit~=nil or entry.snapshotOnly==true or not deferredSpatial(entry.deferred) then
                return result("unhandled","edit_unknown",entry)
            end
            firstDeferred=firstDeferred or i
            deferred=deferred or {}
            deferred[#deferred+1]={action=entry.action,index=i,descriptor=entry.deferred}
            plan[#plan+1]={entry=entry,steps={},deferred=entry.deferred}
        else
            local edit = entry.edit
            if not fields(edit, editFields) or edit.version ~= 1 or edit.complete ~= true
                or (edit.capacity ~= "unchanged" and edit.capacity ~= "modeled" and edit.capacity ~= "external") then
                return result("unhandled", "edit_unknown", entry)
            end
            local resources = array(edit.resources)
            if not resources then return result("unhandled", "edit_unknown", entry) end
            local steps = {}
            plan[#plan + 1] = {entry = entry, steps = steps}
            for j = 1, resources do
                local resource = edit.resources[j]
                if not fields(resource, resourceFields) or not named(resource.domain) or not scalar(resource.key)
                    or not plain(resource.facts) or (resource.bounds ~= nil and not plain(resource.bounds)) then
                    return result("unhandled", "edit_unknown", entry)
                end
                local key = resource.key
                local domain = domains[resource.domain]
                if not domain then domain = {}; domains[resource.domain] = domain end
                local snapshot = domain[key]
                if not snapshot then
                    snapshot = {facts = {}, bounds = {}, key = key, entry = entry}
                    domain[key] = snapshot; snapshots[#snapshots + 1] = snapshot
                end
                for field, value in pairs(resource.facts) do
                    if not named(field) or not scalar(value) then return result("unhandled", "edit_unknown", entry, key, field) end
                    local previous = snapshot.facts[field]
                    -- Opaque values are identities, including values with an __eq metamethod.
                    if previous ~= nil and not rawequal(previous, value) then
                        return result("unhandled", "edit_unknown", entry, key, field)
                    end
                    snapshot.facts[field] = value
                end
                -- Bounds belong to the phase that declares them. Current facts
                -- are one observation, but a later phase cannot constrain an
                -- earlier effect after an all-resource native boundary.
                local phase=firstDeferred and #deferred or nil
                local bounds=snapshot.bounds
                if phase then
                    bounds=nil
                    if resource.bounds~=nil then
                        snapshot.laterBounds=snapshot.laterBounds or {}
                        bounds=snapshot.laterBounds[phase]
                        if not bounds then bounds={};snapshot.laterBounds[phase]=bounds end
                    end
                end
                for field, bound in pairs(resource.bounds or {}) do
                    if not named(field) or not fields(bound, boundFields) or not range(bound)
                        or (bound.reason ~= nil and not boundReasons[bound.reason]) then
                        return result("unhandled", "edit_unknown", entry, key, field)
                    end
                    local reason = bound.reason or "edit_resource_amount"
                    local previous = bounds[field]
                    if previous and (previous.min ~= bound.min or previous.max ~= bound.max or previous.reason ~= reason) then
                        return result("unhandled", "edit_unknown", entry, key, field)
                    end
                    bounds[field] = {min = bound.min, max = bound.max, reason = reason}
                end
                local requires = resource.requires == nil and {} or resource.requires
                local effects = resource.effects == nil and {} or resource.effects
                if not validPredicates(requires) or resource.cases ~= nil and resource.effects ~= nil then
                    return result("unhandled", "edit_unknown", entry, key)
                end
                local valid, field = validEffects(effects)
                if not valid then return result("unhandled", "edit_unknown", entry, key, field) end
                if resource.cases ~= nil then
                    local caseCount = array(resource.cases)
                    if not caseCount then return result("unhandled", "edit_unknown", entry, key) end
                    for k = 1, caseCount do
                        local case = resource.cases[k]
                        if not fields(case, caseFields) or not validPredicates(case.when) then
                            return result("unhandled", "edit_unknown", entry, key)
                        end
                        valid, field = validEffects(case.effects)
                        if not valid then return result("unhandled", "edit_unknown", entry, key, field) end
                    end
                end
                steps[#steps + 1] = {entry = entry, snapshot = snapshot, requires = requires,
                    effects = effects, cases = resource.cases, phase=phase}
            end
        end
    end
    -- Check completeness and operand types even for removed commands; removal does not validate unknown semantics.
    for index, action in ipairs(plan) do
        local beforeBoundary=not firstDeferred or index<firstDeferred
        for _, step in ipairs(action.steps) do
            local facts, key = step.snapshot.facts, step.snapshot.key
            local bounds=step.snapshot.bounds
            if step.phase then bounds=step.snapshot.laterBounds and step.snapshot.laterBounds[step.phase]end
            local valid, field = predicateOperands(step.requires, facts)
            if not valid then return result("unhandled", "edit_unknown", step.entry, key, field) end
            valid, field = effectOperands(step.effects, facts, bounds, beforeBoundary)
            if not valid then return result("unhandled", "edit_unknown", step.entry, key, field) end
            -- Inactive branches and removed actions remain audited contracts.
            if step.cases then
                for _, case in ipairs(step.cases) do
                    valid, field = predicateOperands(case.when, facts)
                    if not valid then return result("unhandled", "edit_unknown", step.entry, key, field) end
                    valid, field = effectOperands(case.effects, facts, bounds, beforeBoundary)
                    if not valid then return result("unhandled", "edit_unknown", step.entry, key, field) end
                end
            end
        end
    end
    -- Validate every phase's bound operand types before any prefix denial.
    -- Only the first phase's bounds/effects can be evaluated now; later native
    -- admission must read its own fresh facts, limits and outcome.
    if firstDeferred then
        for _,snapshot in ipairs(snapshots)do
            for field in pairs(snapshot.bounds)do
                if not finite(snapshot.facts[field])then return result("unhandled","edit_unknown",snapshot.entry,snapshot.key,field)end
            end
            if snapshot.laterBounds then
                for _,bounds in pairs(snapshot.laterBounds)do
                    for field in pairs(bounds)do
                        if not finite(snapshot.facts[field])then return result("unhandled","edit_unknown",snapshot.entry,snapshot.key,field)end
                    end
                end
            end
        end
    end
    for _, snapshot in ipairs(snapshots) do
        for field, bound in pairs(snapshot.bounds) do
            local value = snapshot.facts[field]
            if not firstDeferred and not finite(value) then return result("unhandled", "edit_unknown", snapshot.entry, snapshot.key, field) end
            if outside(value, bound) then return result("denied", bound.reason, snapshot.entry, snapshot.key, field) end
        end
    end
    for index, action in ipairs(plan) do
        if firstDeferred and index==firstDeferred then
            local value=result("deferred","edit_native_resolution",action.entry)
            value.evaluatedPrefix,value.deferred=firstDeferred-1,deferred
            return value
        end
        if not action.entry.snapshotOnly then
            -- All of an action's preconditions precede all of its effects, across resources.
            for _, step in ipairs(action.steps) do
                local facts, key = step.snapshot.facts, step.snapshot.key
                for _, predicate in ipairs(step.requires) do
                    local matched, reason = matches(predicate, facts)
                    if not matched then return result(matched == nil and "unhandled" or "denied", reason, step.entry, key, predicate.field) end
                end
                if step.cases then
                    -- Select against the pre-action projection. No resource can
                    -- observe another resource's effects from this same action.
                    local selected
                    for _, case in ipairs(step.cases) do
                        local matched = true
                        for _, predicate in ipairs(case.when) do
                            local match = matches(predicate, facts)
                            if match == nil then return result("unhandled", "edit_unknown", step.entry, key, predicate.field) end
                            if not match then matched = false; break end
                        end
                        if matched then selected = case.effects; break end
                    end
                    if not selected then return result("denied", "edit_required_state", step.entry, key) end
                    step.effects = selected
                end
            end
            for _, step in ipairs(action.steps) do
                local facts, key = step.snapshot.facts, step.snapshot.key
                for _, effect in ipairs(step.effects) do
                    local field, value = effect.field, effect.set
                    if effect.delta ~= nil or effect.cap ~= nil or effect.scale ~= nil or effect.deplete ~= nil then
                        value = numericEffect(effect, facts[field])
                        if value == nil then return result("unhandled", "edit_unknown", step.entry, key, field) end
                    elseif effect.toggle then
                        if type(facts[field]) ~= "boolean" then return result("unhandled", "edit_unknown", step.entry, key, field) end
                        value = not facts[field]
                    end
                    facts[field] = value
                    local bound = step.snapshot.bounds[field]
                    if bound then
                        if not finite(value) then return result("unhandled", "edit_unknown", step.entry, key, field) end
                        if outside(value, bound) then return result("denied", bound.reason, step.entry, key, field) end
                    end
                end
            end
        end
    end
    return result("allowed")
end

return Model
