require "PZSurvivorWishlist"
local Model = {}
PZSurvivorWishlist.Model = Model
Model.limits = {entries = 256, members = 32, batch = 128, lists = 4096, amount = 9999}

local function integer(value, low, high)
    return type(value) == "number" and value >= low and value <= high and value == math.floor(value)
end
local function text(value, length)
    return type(value) == "string" and #value > 0 and #value <= length and not value:find("%c")
end
local function count(values)
    local n = 0
    for _ in pairs(values) do n = n + 1 end
    return n
end
local function fields(value, allowed, limit)
    if type(value) ~= "table" then return false end
    local n = 0
    for key in pairs(value) do
        n = n + 1
        if n > limit or not allowed[key] then return false end
    end
    return true
end
local function array(value, limit)
    if type(value) ~= "table" then return nil end
    local n = 0
    for key in pairs(value) do
        n = n + 1
        if n > limit or not integer(key, 1, limit) then return nil end
    end
    for i = 1, n do if value[i] == nil then return nil end end
    return n
end
local function vehicleTypes(value, fullType, env)
    if value == nil then return true end
    local n = array(value, 32)
    if not n or n == 0 or value[1] ~= fullType then return false end
    local seen = {}
    for i = 1, n do
        if not text(value[i], 128) or seen[value[i]] or (env and not env.validItem(value[i])) then return false end
        seen[value[i]] = true
    end
    return true
end
local function copyTypes(value)
    if not value then return nil end
    local result = {}
    for i, fullType in ipairs(value) do result[i] = fullType end
    return result
end

local function initialize(store)
    if type(store) ~= "table" then return "storage_invalid" end
    if count(store) == 0 then store.version, store.lists = 1, {} end
    if store.version ~= 1 then return "storage_version" end
    if type(store.lists) ~= "table" then return "storage_invalid" end
end
local function effectiveFaction(list, env)
    return list.faction and env.factionOf(list.owner) == list.faction and list.faction or nil
end
function Model.validateStore(store)
    if type(store) ~= "table" or store.version ~= 1 then return "storage_version" end
    if not fields(store, {version = true, lists = true}, 2) or type(store.lists) ~= "table"
        or count(store.lists) > Model.limits.lists then return "storage_invalid" end
    for id, list in pairs(store.lists) do
        if not text(id, 128) or not fields(list, {id = true, owner = true, revision = true, entries = true, members = true, faction = true}, 6)
            or list.id ~= id or list.owner ~= id or not integer(list.revision, 0, 2147483646)
            or type(list.entries) ~= "table" or type(list.members) ~= "table"
            or count(list.entries) > Model.limits.entries or count(list.members) > Model.limits.members
            or (list.faction ~= nil and not text(list.faction, 128)) then return "storage_invalid" end
        for fullType, entry in pairs(list.entries) do
            if not text(fullType, 136) or not fields(entry, {amount = true, done = true, vehicleTypes = true, vehicleClass = true}, 4)
                or not integer(entry.amount, 1, Model.limits.amount) or type(entry.done) ~= "boolean"
                or not vehicleTypes(entry.vehicleTypes, entry.vehicleTypes and fullType:sub(9) or fullType)
                or (entry.vehicleTypes and fullType:sub(1, 8) ~= "vehicle:")
                or (entry.vehicleTypes and not integer(entry.vehicleClass, 0, 3))
                or (not entry.vehicleTypes and entry.vehicleClass ~= nil) then return "storage_invalid" end
        end
        for username, member in pairs(list.members) do
            if not text(username, 128) or member ~= true then return "storage_invalid" end
        end
    end
end
local function authorized(list, actor, env)
    if actor == list.owner or list.members[actor] == true then return true end
    local faction = effectiveFaction(list, env)
    return faction ~= nil and env.factionOf(actor) == faction
end
local function copyList(list, env)
    local result = {id = list.id, owner = list.owner, revision = list.revision,
        entries = {}, members = {}, faction = effectiveFaction(list, env)}
    for fullType, entry in pairs(list.entries) do
        result.entries[fullType] = {amount = entry.amount, done = entry.done, vehicleTypes = copyTypes(entry.vehicleTypes), vehicleClass = entry.vehicleClass}
    end
    for username in pairs(list.members) do result.members[username] = true end
    return result
end

local function prepareSnapshot(store, actor)
    local error = initialize(store)
    if error then return error end
    if not text(actor, 128) then return "invalid_actor" end
    if not store.lists[actor] then
        if count(store.lists) >= Model.limits.lists then return "limit" end
        store.lists[actor] = {id = actor, owner = actor, revision = 0, entries = {}, members = {}}
    end
end
-- Access can change without a list edit when either actor leaves a faction.
-- Only this small projection is needed to detect an unchanged publication.
function Model.snapshotVersions(store, actor, env)
    local error = prepareSnapshot(store, actor)
    if error then return nil, error end
    local versions = {}
    for id, list in pairs(store.lists) do
        if authorized(list, actor, env) then
            versions[id] = {revision = list.revision, faction = effectiveFaction(list, env)}
        end
    end
    return versions
end
function Model.snapshot(store, actor, env)
    local error = prepareSnapshot(store, actor)
    if error then return {lists = {}, error = error} end
    local result = {lists = {}}
    for _, list in pairs(store.lists) do
        if authorized(list, actor, env) then result.lists[#result.lists + 1] = copyList(list, env) end
    end
    table.sort(result.lists, function(a, b) return a.id < b.id end)
    return result
end

local schemas = {
    sync = {action = true, requestId = true},
    add = {action = true, requestId = true, listId = true, revision = true, fullType = true, amount = true, vehicleTypes = true, vehicleClass = true},
    set = {action = true, requestId = true, listId = true, revision = true, fullType = true, amount = true, vehicleTypes = true, vehicleClass = true},
    remove = {action = true, requestId = true, listId = true, revision = true, fullType = true},
    done = {action = true, requestId = true, listId = true, revision = true, fullType = true, done = true},
    share = {action = true, requestId = true, listId = true, revision = true, members = true, faction = true},
    addMany = {action = true, requestId = true, listId = true, revision = true, entries = true},
}
local function mutate(store, actor, args, env)
    if type(args) ~= "table" or not schemas[args.action]
        or not fields(args, schemas[args.action], 8)
        or (args.requestId ~= nil and not text(args.requestId, 64)) then return "invalid_request" end
    if args.action == "sync" then return nil, false end
    if not text(args.listId, 128) or not integer(args.revision, 0, 2147483646) then return "invalid_request" end
    local list = store.lists[args.listId]
    if not list or not authorized(list, actor, env) then return "forbidden" end
    if args.action == "share" and actor ~= list.owner then return "forbidden" end
    if args.revision ~= list.revision then return "stale_revision" end
    if list.revision >= 2147483646 then return "limit" end
    if args.action == "share" then
        local n = array(args.members, Model.limits.members)
        if not n or type(args.faction) ~= "boolean" then return "invalid_request" end
        local members = {}
        for i = 1, n do
            if not text(args.members[i], 128) then return "invalid_request" end
            if args.members[i] ~= actor then members[args.members[i]] = true end
        end
        local faction = args.faction and env.factionOf(actor) or nil
        if args.faction and not faction then return "no_faction" end
        if faction and not text(faction, 128) then return "invalid_request" end
        list.members, list.faction = members, faction
    elseif args.action == "add" or args.action == "addMany" or args.action == "set" then
        local entries = args.action == "addMany" and args.entries or {{fullType = args.fullType, amount = args.amount, vehicleTypes = args.vehicleTypes, vehicleClass = args.vehicleClass}}
        local n = array(entries, Model.limits.batch)
        if not n or n == 0 then return "invalid_request" end
        local pending, total = {}, count(list.entries)
        for i = 1, n do
            local item = entries[i]
            if not fields(item, {fullType = true, amount = true, vehicleTypes = true, vehicleClass = true}, 4)
                or not text(item.fullType, 136) or not integer(item.amount, 1, Model.limits.amount) then return "invalid_request" end
            local key = item.vehicleTypes and ("vehicle:" .. item.fullType) or item.fullType
            local old = pending[key] or list.entries[key]
            local fullType = old and old.vehicleTypes and old.vehicleTypes[1] or item.fullType
            if not text(fullType, 128) or not env.validItem(fullType) then return "invalid_item" end
            if not vehicleTypes(item.vehicleTypes, item.fullType, env)
                or (item.vehicleTypes and not integer(item.vehicleClass, 0, 3))
                or (not item.vehicleTypes and item.vehicleClass ~= nil) then return "invalid_request" end
            if old and item.vehicleTypes then
                if #old.vehicleTypes ~= #item.vehicleTypes then return "invalid_request" end
                for j, variant in ipairs(old.vehicleTypes) do
                    if variant ~= item.vehicleTypes[j] then return "invalid_request" end
                end
                if old.vehicleClass ~= item.vehicleClass then return "invalid_request" end
            end
            local amount = item.amount
            if args.action ~= "set" and old then amount = amount + old.amount end
            if amount > Model.limits.amount then return "limit" end
            if not old then total = total + 1 end
            if total > Model.limits.entries then return "limit" end
            pending[key] = {amount = amount, done = args.action == "set" and old and old.done or false,
                vehicleTypes = copyTypes(item.vehicleTypes or (old and old.vehicleTypes)),
                vehicleClass = item.vehicleClass or (old and old.vehicleClass)}
        end
        for fullType, entry in pairs(pending) do list.entries[fullType] = entry end
    else
        if not text(args.fullType, 136) then return "invalid_request" end
        if not list.entries[args.fullType] then return "not_found" end
        if args.action == "done" then
            if type(args.done) ~= "boolean" then return "invalid_request" end
            list.entries[args.fullType].done = args.done
        else
            list.entries[args.fullType] = nil
        end
    end
    list.revision = list.revision + 1
    return nil, true
end

function Model.request(store, actor, args, env)
    local result = Model.snapshot(store, actor, env)
    local changed = false
    if not result.error then
        result.error, changed = mutate(store, actor, args, env)
        local error = result.error
        result = Model.snapshot(store, actor, env)
        result.error = error or result.error
    end
    if type(args) == "table" and text(args.requestId, 64) then result.requestId = args.requestId end
    return result, changed == true
end
return Model
