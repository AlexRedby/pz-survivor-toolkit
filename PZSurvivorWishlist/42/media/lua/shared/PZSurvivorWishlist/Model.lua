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
            if not text(fullType, 128) or not fields(entry, {amount = true, done = true}, 2)
                or not integer(entry.amount, 1, Model.limits.amount) or type(entry.done) ~= "boolean" then return "storage_invalid" end
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
        result.entries[fullType] = {amount = entry.amount, done = entry.done}
    end
    for username in pairs(list.members) do result.members[username] = true end
    return result
end

function Model.snapshot(store, actor, env)
    local error = initialize(store)
    if error then return {lists = {}, error = error} end
    if not text(actor, 128) then return {lists = {}, error = "invalid_actor"} end
    if not store.lists[actor] then
        if count(store.lists) >= Model.limits.lists then return {lists = {}, error = "limit"} end
        store.lists[actor] = {id = actor, owner = actor, revision = 0, entries = {}, members = {}}
    end
    local result = {lists = {}}
    for _, list in pairs(store.lists) do
        if authorized(list, actor, env) then result.lists[#result.lists + 1] = copyList(list, env) end
    end
    table.sort(result.lists, function(a, b) return a.id < b.id end)
    return result
end

local schemas = {
    sync = {action = true, requestId = true},
    add = {action = true, requestId = true, listId = true, revision = true, fullType = true, amount = true},
    set = {action = true, requestId = true, listId = true, revision = true, fullType = true, amount = true},
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
        local entries = args.action == "addMany" and args.entries or {{fullType = args.fullType, amount = args.amount}}
        local n = array(entries, Model.limits.batch)
        if not n or n == 0 then return "invalid_request" end
        local pending, total = {}, count(list.entries)
        for i = 1, n do
            local item = entries[i]
            if not fields(item, {fullType = true, amount = true}, 2)
                or not text(item.fullType, 128) or not integer(item.amount, 1, Model.limits.amount) then return "invalid_request" end
            if not env.validItem(item.fullType) then return "invalid_item" end
            local old = pending[item.fullType] or list.entries[item.fullType]
            local amount = item.amount
            if args.action ~= "set" and old then amount = amount + old.amount end
            if amount > Model.limits.amount then return "limit" end
            if not old then total = total + 1 end
            if total > Model.limits.entries then return "limit" end
            pending[item.fullType] = {amount = amount, done = args.action == "set" and old and old.done or false}
        end
        for fullType, entry in pairs(pending) do list.entries[fullType] = entry end
    else
        if not text(args.fullType, 128) then return "invalid_request" end
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
