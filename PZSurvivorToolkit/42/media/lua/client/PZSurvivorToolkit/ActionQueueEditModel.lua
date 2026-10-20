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
local entryFields = {action = true, edit = true, active = true, snapshotOnly = true}
local editFields = {version = true, complete = true, capacity = true, resources = true}
local resourceFields = {domain = true, key = true, facts = true, requires = true, effects = true, bounds = true}
local predicateFields = {field = true, equal = true, oneOf = true, min = true, max = true, above = true}
local effectFields = {field = true, set = true, delta = true, toggle = true, cap = true, scale = true}
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
    if predicate.equal ~= nil then return scalar(predicate.equal) and predicate.oneOf == nil and not numeric end
    if predicate.oneOf ~= nil then
        if numeric then return false end
        local count = array(predicate.oneOf)
        if not count or count == 0 then return false end
        for i = 1, count do if not scalar(predicate.oneOf[i]) then return false end end
        return true
    end
    return numericPredicate(predicate)
end
local function numericEffect(effect, value)
    if not finite(value) then return end
    local projected
    if effect.delta ~= nil then projected = value + effect.delta
    elseif effect.cap ~= nil then projected = math.min(value, effect.cap)
    elseif effect.scale ~= nil then projected = value * effect.scale end
    if finite(projected) then return projected end
end

function Model.evaluate(entries)
    local count = array(entries)
    if not count then return result("unhandled", "edit_unknown") end
    local domains, snapshots, plan = {}, {}, {}
    for i = 1, count do
        local entry = entries[i]
        if not fields(entry, entryFields) or not scalar(entry.action)
            or (entry.active ~= nil and type(entry.active) ~= "boolean")
            or (entry.snapshotOnly ~= nil and type(entry.snapshotOnly) ~= "boolean") then
            return result("unhandled", "edit_unknown")
        end
        if entry.active then return result("unhandled", "edit_in_flight", entry) end
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
            for field, bound in pairs(resource.bounds or {}) do
                if not named(field) or not fields(bound, boundFields) or not range(bound)
                    or (bound.reason ~= nil and not boundReasons[bound.reason]) then
                    return result("unhandled", "edit_unknown", entry, key, field)
                end
                local reason = bound.reason or "edit_resource_amount"
                local previous = snapshot.bounds[field]
                if previous and (previous.min ~= bound.min or previous.max ~= bound.max or previous.reason ~= reason) then
                    return result("unhandled", "edit_unknown", entry, key, field)
                end
                snapshot.bounds[field] = {min = bound.min, max = bound.max, reason = reason}
            end
            local requires = resource.requires == nil and {} or resource.requires
            local effects = resource.effects == nil and {} or resource.effects
            local requirementCount, effectCount = array(requires), array(effects)
            if not requirementCount or not effectCount then return result("unhandled", "edit_unknown", entry, key) end
            for k = 1, requirementCount do
                local predicate = requires[k]
                if not validPredicate(predicate) then
                    return result("unhandled", "edit_unknown", entry, key)
                end
            end
            for k = 1, effectCount do
                local effect = effects[k]
                if not fields(effect, effectFields) or not named(effect.field) then return result("unhandled", "edit_unknown", entry, key) end
                local operations = (effect.set ~= nil and 1 or 0) + (effect.delta ~= nil and 1 or 0)
                    + (effect.toggle ~= nil and 1 or 0) + (effect.cap ~= nil and 1 or 0) + (effect.scale ~= nil and 1 or 0)
                if operations ~= 1 or (effect.set ~= nil and not scalar(effect.set))
                    or (effect.delta ~= nil and not finite(effect.delta)) or (effect.toggle ~= nil and effect.toggle ~= true)
                    or (effect.cap ~= nil and not finite(effect.cap))
                    or (effect.scale ~= nil and (not finite(effect.scale) or effect.scale < 0)) then
                    return result("unhandled", "edit_unknown", entry, key, effect.field)
                end
            end
            steps[#steps + 1] = {entry = entry, snapshot = snapshot, requires = requires, effects = effects}
        end
    end
    -- Check completeness and operand types even for removed commands; removal does not validate unknown semantics.
    for _, action in ipairs(plan) do
        for _, step in ipairs(action.steps) do
            local facts, key = step.snapshot.facts, step.snapshot.key
            for _, predicate in ipairs(step.requires) do
                local value = facts[predicate.field]
                if value == nil or (predicate.equal == nil and predicate.oneOf == nil and not finite(value)) then
                    return result("unhandled", "edit_unknown", step.entry, key, predicate.field)
                end
            end
            for _, effect in ipairs(step.effects) do
                local value = facts[effect.field]
                local numeric = effect.delta ~= nil or effect.cap ~= nil or effect.scale ~= nil
                if value == nil or (numeric and numericEffect(effect, value) == nil)
                    or (effect.toggle and type(value) ~= "boolean")
                    or (effect.set ~= nil and step.snapshot.bounds[effect.field] and not finite(effect.set)) then
                    return result("unhandled", "edit_unknown", step.entry, key, effect.field)
                end
            end
        end
    end
    for _, snapshot in ipairs(snapshots) do
        for field, bound in pairs(snapshot.bounds) do
            local value = snapshot.facts[field]
            if not finite(value) then return result("unhandled", "edit_unknown", snapshot.entry, snapshot.key, field) end
            if outside(value, bound) then return result("denied", bound.reason, snapshot.entry, snapshot.key, field) end
        end
    end
    for _, action in ipairs(plan) do
        if not action.entry.snapshotOnly then
            -- All of an action's preconditions precede all of its effects, across resources.
            for _, step in ipairs(action.steps) do
                local facts, key = step.snapshot.facts, step.snapshot.key
                for _, predicate in ipairs(step.requires) do
                    local value = facts[predicate.field]
                    if predicate.equal ~= nil then
                        if not rawequal(value, predicate.equal) then return result("denied", "edit_required_state", step.entry, key, predicate.field) end
                    elseif predicate.oneOf ~= nil then
                        local found = false
                        for _, candidate in ipairs(predicate.oneOf) do
                            if rawequal(value, candidate) then found = true; break end
                        end
                        if not found then return result("denied", "edit_required_state", step.entry, key, predicate.field) end
                    else
                        if not finite(value) then return result("unhandled", "edit_unknown", step.entry, key, predicate.field) end
                        if outside(value, predicate) then return result("denied", "edit_resource_amount", step.entry, key, predicate.field) end
                    end
                end
            end
            for _, step in ipairs(action.steps) do
                local facts, key = step.snapshot.facts, step.snapshot.key
                for _, effect in ipairs(step.effects) do
                    local field, value = effect.field, effect.set
                    if effect.delta ~= nil or effect.cap ~= nil or effect.scale ~= nil then
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
