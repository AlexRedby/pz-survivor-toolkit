local Tags = require "PZSurvivorToolkit/ItemTags"
local Groups = {STORE = "PZSTContainerGroups", FIELD = "PZSTContainerGroups"}
Groups.REVISIONS = Groups.FIELD .. "Revisions"
PZSurvivorToolkit.ContainerGroups = Groups
local received, owned
local listeners = {}

local function normalizeConfiguration(value)
    -- Appearance reads groups too; defer configuration loading until an actual edit/receipt.
    return require("PZSurvivorToolkit/QuartermasterContainerConfig").normalize(value)
end

local function changed()
    for fn in pairs(listeners) do pcall(fn) end
end

function Groups.onChanged(fn)
    assert(type(fn) == "function", "Expected container group listener")
    listeners[fn] = true
end

function Groups.offChanged(fn) listeners[fn] = nil end

local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = copy(item) end
    return out
end

local function integer(value)
    return type(value) == "number" and value >= 0 and value < 9007199254740991 and value % 1 == 0
end

local function world()
    assert(not isClient(), "Only the authority owns container groups")
    local store = ModData.getOrCreate(Groups.STORE)
    if store.schema == nil then
        store.schema, store.revision, store.nextId, store.groups = 1, 0, 0, {}
    end
    assert(store.schema == 1 and integer(store.revision) and integer(store.nextId)
        and type(store.groups) == "table", "Invalid container group store")
    owned = store
    return store
end

local function state()
    if isClient() then return received end
    -- Reading a container must not allocate world state or object ModData.
    if ModData.get then return ModData.get(Groups.STORE) end
    return owned
end

function Groups.synced() return not isClient() or received ~= nil end
function Groups.initialize() return world() end
function Groups.resetReceived() received = nil end
function Groups.snapshot() return copy(state()) end

function Groups.receive(value)
    if type(value) ~= "table" or value.schema ~= 1 or not integer(value.revision)
        or not integer(value.nextId) or type(value.groups) ~= "table" then return false, "invalid" end
    local clean = {schema = 1, revision = value.revision, nextId = value.nextId, groups = {}}
    for id, record in pairs(value.groups) do
        if type(id) ~= "string" or #id == 0 or #id > 128 or type(record) ~= "table"
            or record.id ~= id or not integer(record.rev) or record.rev < 1
            or type(record.createdBy) ~= "string" then return false, "invalid" end
        local config, rule = normalizeConfiguration(record.configuration), Tags.normalizeRule(record.rule)
        if not config or config.groupOperation or not rule or not config.appearance or not config.appearance.name then return false, "invalid" end
        clean.groups[id] = {id = id, rev = record.rev, createdBy = record.createdBy, configuration = config, rule = rule}
    end
    if received and value.revision <= received.revision then return false, "stale" end
    received = clean
    changed()
    return true
end

function Groups.publish()
    if isServer() then world(); ModData.transmit(Groups.STORE) end
end

function Groups.link(obj, ci)
    if obj and obj.hasModData and not obj:hasModData() then return nil end
    local md = obj and obj:getModData()
    local id = md and type(md[Groups.FIELD]) == "table" and md[Groups.FIELD][tostring(ci)] or nil
    return type(id) == "string" and #id > 0 and #id <= 128 and id or nil
end

function Groups.ready(obj, ci)
    if not isClient() or not Groups.link(obj, ci) then return true end
    if not received then return false end
    local md = obj:getModData()
    local markers = md[Groups.REVISIONS]
    local required = type(markers) == "table" and markers[tostring(ci)]
    return not integer(required) or required <= received.revision
end

function Groups.applyLink(obj, ci, id, requiredRevision)
    local md, key = obj:getModData(), tostring(ci)
    local previous = Groups.link(obj, ci)
    local markers = type(md[Groups.REVISIONS]) == "table" and md[Groups.REVISIONS]
    local previousRevision = markers and markers[key]
    local revision = id and integer(requiredRevision) and requiredRevision or nil
    if id then
        md[Groups.FIELD] = type(md[Groups.FIELD]) == "table" and md[Groups.FIELD] or {}
        md[Groups.FIELD][key] = id
        if previous == id and integer(previousRevision) then
            revision = math.max(revision or 0, previousRevision)
        end
        if revision ~= nil then
            md[Groups.REVISIONS] = markers or {}
            md[Groups.REVISIONS][key] = revision
        elseif markers then markers[key] = nil end
    elseif type(md[Groups.FIELD]) == "table" then md[Groups.FIELD][key] = nil end
    if not id and markers then markers[key] = nil end
    local updated = previous ~= (id or nil) or previousRevision ~= revision
    if updated then changed() end
    return updated
end

function Groups.resolve(obj, ci)
    local id = Groups.link(obj, ci)
    if not id then return nil end
    local store = state()
    return store and type(store.groups) == "table" and copy(store.groups[id]) or nil
end

function Groups.list()
    local store, result = state(), {}
    for _, record in pairs(store and store.groups or {}) do result[#result + 1] = copy(record) end
    table.sort(result, function(a, b)
        local an, bn = a.configuration.appearance.name, b.configuration.appearance.name
        return an == bn and a.id < b.id or an < bn
    end)
    return result
end

function Groups.canEdit(record, player)
    if not record or not player then return false end
    return record.createdBy == player:getUsername()
        or (player.getAccessLevel and player:getAccessLevel() == "admin") or false
end

-- Prepare without touching either world or object. Box authority checks run first.
function Groups.prepare(obj, ci, player, configuration, rule)
    local store, link = world(), Groups.link(obj, ci)
    local op = configuration and configuration.groupOperation
    local config = configuration and normalizeConfiguration(configuration)
    if config then config.groupOperation = nil end
    local plan = {configuration = config, rule = copy(rule), link = link}
    if not op then
        if configuration then
            plan.link = false
            if config.appearance == nil and link and store.groups[link] then
                config.appearance = copy(store.groups[link].configuration.appearance)
            end
        elseif link and store.groups[link] then
            plan.configuration, plan.link = copy(store.groups[link].configuration), false
        end
        return "ok", plan
    end
    if op.mode == "detach" then plan.link = false; return "ok", plan end
    if op.mode == "create" then
        if not config.appearance or not config.appearance.name then return "invalid" end
        if store.nextId >= 9007199254740990 then return "invalid" end
        local id = string.format("%.0f", store.nextId + 1)
        if store.groups[id] ~= nil then return "invalid" end
        plan.record = {id = id, rev = 1, createdBy = player:getUsername(), configuration = copy(config), rule = copy(rule)}
        plan.link, plan.nextId = id, store.nextId + 1
        return "ok", plan
    end
    local record = store.groups[op.id]
    if not record then return "missingGroup" end
    if op.mode == "join" then
        plan.configuration, plan.rule, plan.link = copy(record.configuration), copy(record.rule), op.id
        return "ok", plan
    end
    if not Groups.canEdit(record, player) then return "deniedGroup" end
    if record.rev ~= op.baseRevision then return "staleGroup" end
    if not config.appearance or not config.appearance.name then return "invalid" end
    plan.record = {id = record.id, rev = record.rev + 1, createdBy = record.createdBy,
        configuration = copy(config), rule = copy(rule)}
    plan.link = record.id
    return "ok", plan
end

function Groups.commit(obj, ci, plan)
    assert(not isClient(), "Only the authority changes container groups")
    local store = world()
    if plan.record then
        store.groups[plan.record.id] = copy(plan.record)
        store.nextId = plan.nextId or store.nextId
        store.revision = store.revision + 1
    end
    local linkChanged = Groups.applyLink(obj, ci, plan.link, store.revision)
    if plan.record and not linkChanged then changed() end
    if plan.record then Groups.publish() end
end

return Groups
