local base = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/"
-- PZ's Kahlua provides pairs(), but not the standard Lua next() global.
next = nil
PZSurvivorWishlist = {}
local modules = {}
require = function(name)
    if name == "PZSurvivorWishlist" then return PZSurvivorWishlist end
    if modules[name] then return modules[name] end
    local value = dofile(base .. "shared/" .. name .. ".lua")
    modules[name] = value
    return value
end
local Model = require "PZSurvivorWishlist/Model"
local factions, itemTypes = {}, {['Base.Hammer'] = true, ['Base.Nails'] = true}
local env = {validItem = function(item) return itemTypes[item] == true end,
    factionOf = function(name) return factions[name] end}
local passed = 0
local function check(name, fn)
    fn()
    passed = passed + 1
    print("PASS wishlist model: " .. name)
end
local function own(store, actor)
    local payload = Model.snapshot(store, actor, env)
    for _, list in ipairs(payload.lists) do if list.id == actor then return list end end
end
local function request(store, actor, action, id, extra)
    local args = extra or {}
    args.action, args.listId = action, id or actor
    args.revision = args.revision or store.lists[args.listId].revision
    return Model.request(store, actor, args, env)
end
local function add(store, actor, id, amount)
    return request(store, actor, "add", id, {fullType = "Base.Hammer", amount = amount or 1})
end
check("persistent personal list and detached snapshots", function()
    local store = {}
    local first = own(store, "owner")
    assert(first.revision == 0 and store.version == 1)
    assert(add(store, "owner").error == nil)
    local snapshot = own(store, "owner")
    snapshot.entries['Base.Hammer'].amount = 900
    snapshot.members.evil = true
    assert(own(store, "owner").entries['Base.Hammer'].amount == 1)
    assert(not own(store, "owner").members.evil)
    modules['PZSurvivorWishlist/Model'] = nil
    local reloaded = require "PZSurvivorWishlist/Model"
    assert(reloaded.snapshot(store, "owner", env).lists[1].entries['Base.Hammer'].amount == 1)
end)
check("owners control ACL; members edit; spoofed actors cannot edit", function()
    local store = {}
    own(store, "owner")
    local payload = request(store, "owner", "share", nil, {members = {"friend"}, faction = false})
    assert(not payload.error)
    assert(add(store, "friend", "owner").error == nil)
    assert(request(store, "friend", "share", "owner", {members = {"evil"}, faction = false}).error == "forbidden")
    local denied = add(store, "evil", "owner")
    assert(denied.error == "forbidden" and #denied.lists == 1 and denied.lists[1].id == "evil")
    denied = request(store, "evil", "add", "owner", {owner = "owner", fullType = "Base.Hammer", amount = 1})
    assert(denied.error == "invalid_request")
    assert(own(store, "owner").entries['Base.Hammer'].amount == 1)
end)
check("live faction ACL requires both actors still in selected faction", function()
    local store = {}
    factions.owner, factions.friend = "Builders", "Builders"
    own(store, "owner")
    assert(not request(store, "owner", "share", nil, {members = {}, faction = true}).error)
    assert(not add(store, "friend", "owner").error)
    factions.friend = "Other"
    assert(add(store, "friend", "owner").error == "forbidden")
    factions.friend, factions.owner = "Builders", nil
    assert(add(store, "friend", "owner").error == "forbidden")
    assert(own(store, "owner").faction == nil)
    assert(request(store, "owner", "share", nil, {members = {"friend"}, faction = true}).error == "no_faction")
    assert(not store.lists.owner.members.friend)
    factions.owner, factions.friend = nil, nil
end)
check("revocation replaces entire authorized snapshot", function()
    local store = {}
    own(store, "owner")
    request(store, "owner", "share", nil, {members = {"friend"}, faction = false})
    assert(#Model.snapshot(store, "friend", env).lists == 2)
    request(store, "owner", "share", nil, {members = {}, faction = false})
    local payload = Model.snapshot(store, "friend", env)
    assert(#payload.lists == 1 and payload.lists[1].id == "friend")
    assert(add(store, "friend", "owner").error == "forbidden")
end)
check("expected revision rejects concurrent updates and duplicate delivery", function()
    local store = {}
    own(store, "owner")
    local _, changed = request(store, "owner", "add", nil, {revision = 0, fullType = "Base.Hammer", amount = 2})
    assert(changed)
    local payload, rejected = request(store, "owner", "add", nil, {revision = 0, fullType = "Base.Hammer", amount = 8, requestId = "duplicate"})
    assert(not rejected and payload.error == "stale_revision" and payload.requestId == "duplicate")
    assert(payload.lists[1].revision == 1 and payload.lists[1].entries['Base.Hammer'].amount == 2)
end)
check("batch validation is atomic and repeated items combine once", function()
    local store = {}
    own(store, "owner")
    add(store, "owner", nil, 5)
    local revision = store.lists.owner.revision
    local payload = request(store, "owner", "addMany", nil, {entries = {
        {fullType = "Base.Hammer", amount = 2}, {fullType = "Unknown.Item", amount = 1}}})
    assert(payload.error == "invalid_item" and store.lists.owner.revision == revision)
    assert(store.lists.owner.entries['Base.Hammer'].amount == 5)
    payload = request(store, "owner", "addMany", nil, {entries = {
        {fullType = "Base.Nails", amount = 3}, {fullType = "Base.Nails", amount = 2}}})
    assert(not payload.error and store.lists.owner.entries['Base.Nails'].amount == 5)
    assert(store.lists.owner.revision == revision + 1)
    payload = request(store, "owner", "addMany", nil, {entries = {
        {fullType = "Base.Nails", amount = 1}, {fullType = "Base.Hammer", amount = 9999}}})
    assert(payload.error == "limit" and store.lists.owner.entries['Base.Nails'].amount == 5)
end)
check("done, set, add and removal preserve intended quantities", function()
    local store = {}
    own(store, "owner")
    add(store, "owner", nil, 2)
    request(store, "owner", "done", nil, {fullType = "Base.Hammer", done = true})
    request(store, "owner", "set", nil, {fullType = "Base.Hammer", amount = 4})
    assert(store.lists.owner.entries['Base.Hammer'].done)
    add(store, "owner", nil, 1)
    assert(not store.lists.owner.entries['Base.Hammer'].done and store.lists.owner.entries['Base.Hammer'].amount == 5)
    request(store, "owner", "remove", nil, {fullType = "Base.Hammer"})
    assert(not store.lists.owner.entries['Base.Hammer'])
    assert(request(store, "owner", "done", nil, {fullType = "Base.Hammer", done = false}).error == "not_found")
end)
check("uninstalled item types can still be marked and removed", function()
    local store = {}
    own(store, "owner")
    add(store, "owner")
    itemTypes['Base.Hammer'] = nil
    assert(not request(store, "owner", "done", nil, {fullType = "Base.Hammer", done = true}).error)
    assert(request(store, "owner", "set", nil, {fullType = "Base.Hammer", amount = 2}).error == "invalid_item")
    assert(not request(store, "owner", "remove", nil, {fullType = "Base.Hammer"}).error)
    itemTypes['Base.Hammer'] = true
end)
check("malformed, oversized and forged requests never mutate", function()
    local store = {}
    own(store, "owner")
    local malformed = {
        false, "add", {}, {action = "sync", actor = "evil"}, {action = "bad"},
        {action = "sync", requestId = string.rep("x", 65)}, {action = "sync", requestId = 7},
        {action = "add", listId = "owner", revision = 0, fullType = "Base.Hammer", amount = 0/0},
        {action = "add", listId = "owner", revision = 0, fullType = "Base.Hammer", amount = math.huge},
        {action = "add", listId = "owner", revision = 0, fullType = {}, amount = 1},
        {action = "add", listId = "owner", revision = 0, fullType = "Base.Hammer", amount = "1"},
        {action = "add", listId = "owner", revision = 0, fullType = "Base.Hammer", amount = 1.5},
        {action = "done", listId = "owner", revision = 0, fullType = "Base.Hammer", done = "true"},
        {action = "share", listId = "owner", revision = 0, members = {[2] = "friend"}, faction = false},
        {action = "share", listId = "owner", revision = 0, members = {"friend\n"}, faction = false},
        {action = "addMany", listId = "owner", revision = 0, entries = {}},
        {action = "addMany", listId = "owner", revision = 0, entries = {{fullType = "Base.Hammer", amount = 1, owner = "evil"}}},
    }
    for _, args in ipairs(malformed) do
        local payload, changed = Model.request(store, "owner", args, env)
        assert(payload.error and not changed and store.lists.owner.revision == 0)
    end
    assert(Model.request(store, nil, {action = "sync"}, env).error == "invalid_actor")
end)
check("entry, sharing, batch, owner and amount bounds", function()
    local store = {}
    own(store, "owner")
    local previous = Model.limits.entries
    Model.limits.entries = 1
    add(store, "owner")
    assert(request(store, "owner", "add", nil, {fullType = "Base.Nails", amount = 1}).error == "limit")
    Model.limits.entries = previous
    local members, entries = {}, {}
    for i = 1, 33 do members[i] = "friend" .. i end
    for i = 1, 129 do entries[i] = {fullType = "Base.Nails", amount = 1} end
    assert(request(store, "owner", "share", nil, {members = members, faction = false}).error == "invalid_request")
    assert(request(store, "owner", "addMany", nil, {entries = entries}).error == "invalid_request")
    assert(add(store, "owner", nil, 9999).error == "limit")
    previous = Model.limits.lists
    Model.limits.lists = 1
    assert(Model.snapshot(store, "new-owner", env).error == "limit" and not store.lists['new-owner'])
    Model.limits.lists = previous
end)
check("vehicle alternatives are bounded, detached and retained by quantity and done edits", function()
    local store = {}
    own(store, "owner")
    itemTypes['Base.OldTire2'], itemTypes['Base.NormalTire2'], itemTypes['Base.ModernTire2'] = true, true, true
    local variants = {"Base.OldTire2", "Base.NormalTire2", "Base.ModernTire2"}
    assert(not request(store, "owner", "add", nil, {fullType = variants[1], amount = 1,
        vehicleTypes = variants, vehicleClass = 2}).error)
    assert(not request(store, "owner", "add", nil, {fullType = "Base.OldTire2", amount = 2}).error)
    assert(own(store, "owner").entries['Base.OldTire2'].amount == 2)
    variants[2] = "Base.Hammer"
    local entry = own(store, "owner").entries['vehicle:Base.OldTire2']
    assert(entry.vehicleTypes[2] == "Base.NormalTire2" and entry.vehicleClass == 2)
    entry.vehicleTypes[2] = "Base.Nails"
    assert(not request(store, "owner", "set", nil, {fullType = "vehicle:Base.OldTire2", amount = 3}).error)
    assert(not request(store, "owner", "done", nil, {fullType = "vehicle:Base.OldTire2", done = true}).error)
    entry = own(store, "owner").entries['vehicle:Base.OldTire2']
    assert(entry.amount == 3 and entry.done and entry.vehicleTypes[2] == "Base.NormalTire2")
    assert(Model.validateStore(store) == nil)
    assert(request(store, "owner", "add", nil, {fullType = "Base.OldTire2", amount = 1,
        vehicleTypes = {"Base.OldTire2", "Base.NormalTire2"}, vehicleClass = 2}).error == "invalid_request")
    local revision = store.lists.owner.revision
    local bad = {{}, {[2] = "Base.OldTire2"}, {"Base.NormalTire2"},
        {"Base.OldTire2", "Unknown.Item"}, {"Base.OldTire2", "Base.OldTire2"}, "Base.OldTire2"}
    local tooMany = {}; for i = 1, 33 do tooMany[i] = "Base.OldTire2" end
    bad[#bad + 1] = tooMany
    for _, value in ipairs(bad) do
        assert(request(store, "owner", "add", nil, {fullType = "Base.OldTire2", amount = 1,
            vehicleTypes = value, vehicleClass = 2}).error == "invalid_request")
    end
    for _, value in ipairs({false, "2", 4, 0/0}) do
        assert(request(store, "owner", "add", nil, {fullType = "Base.OldTire2", amount = 1,
            vehicleTypes = {"Base.OldTire2"}, vehicleClass = value}).error == "invalid_request")
    end
    assert(request(store, "owner", "add", nil, {fullType = "Base.Hammer", amount = 1,
        vehicleClass = 2}).error == "invalid_request")
    assert(store.lists.owner.revision == revision)
    assert(not request(store, "owner", "remove", nil, {fullType="vehicle:Base.OldTire2"}).error)
    assert(not own(store,"owner").entries['vehicle:Base.OldTire2'])
    assert(own(store,"owner").entries['Base.OldTire2'].amount==2, "group removal preserves exact wishes")
end)
check("unknown saved schema is preserved and refused", function()
    local store = {version = 2, lists = {owner = {marker = "keep"}}}
    assert(Model.request(store, "owner", {action = "sync"}, env).error == "storage_version")
    assert(store.version == 2 and store.lists.owner.marker == "keep")
    assert(Model.snapshot({version = 1}, "owner", env).error == "storage_invalid")
end)

local server, client, now, store = false, false, 0, {}
isServer = function() return server end
isClient = function() return client end
ModData = {getOrCreate = function() error("Private wishlist must never enter globally requestable ModData") end}
local world, files, paths, writeFailure, readFailure = "/Saves/Sandbox/sp-test", {}, {}, nil, false
local directories, bootstrapFailure, opened, closed, bootstrapOpens = {}, nil, 0, 0, 0
cacheFileExists = function(path) return directories[path] == true or files[path] ~= nil end
getCurrentSaveName = function() return world end
getFileReader = function(path, create)
    assert(create == true)
    if readFailure == "nil" then return nil end
    if readFailure == true then error("disk read failed") end
    assert(directories[path:match("^(.*[/])")], "native reader cannot create parent directories")
    if files[path] == nil then files[path] = "" end
    opened = opened + 1
    local position, contents = 1, files[path]
    return {readLine = function()
        if readFailure == "read" then error("disk read failed") end
        if position > #contents then return nil end
        local finish = contents:find("\n", position, true)
        local line = contents:sub(position, finish and finish - 1 or #contents)
        position = finish and finish + 1 or #contents + 1
        return line
    end, close = function()
        closed = closed + 1
        if readFailure == "close" then error("disk close failed") end
    end}
end
getFileWriter = function(path, create, append)
    assert(create == true and not path:find("..", 1, true))
    for component in path:gmatch("[^/]+") do assert(#component <= 80) end
    if append then
        bootstrapOpens = bootstrapOpens + 1
        if bootstrapFailure == "nil" then return nil end
        if bootstrapFailure == "throw" then error("directory unavailable") end
        directories[path:match("^(.*[/])")] = true
        files[path] = files[path] or ""
        return {write = function() error("bootstrap must not write") end, close = function()
            if bootstrapFailure == "close" then error("bootstrap close failed") end
        end}
    end
    paths[#paths + 1] = path
    files[path] = ""
    local writes = 0
    return {write = function(_, text)
        writes = writes + 1
        if writeFailure == "throw" and writes > 1 then error("disk write failed") end
        if writeFailure ~= "silent" then files[path] = files[path] .. text end
    end, close = function() if writeFailure == "close" then error("write close failed") end end}
end
Faction = {getPlayerFaction = function(username)
    local name = factions[username]
    if name then return {getName = function() return name end} end
end}
ScriptManager = {instance = {FindItem = function(_, item)
    if itemTypes[item] then return {getFullName = function() return item end} end
end}}
local function player(username) return {getUsername = function() return username end} end
local resets = {}
Events = {OnMainMenuEnter = {Add = function(fn) resets[#resets + 1] = fn end},
    OnGameStart = {Add = function() end}}
local Service = require "PZSurvivorWishlist/Service"
check("SP uses identical persisted validation and stable local owner", function()
    local p = player("")
    assert(Service.username(p) == "local")
    assert(Service.username(player("another-character")) == "local")
    assert(Service.request(p, {action = "sync"}).recipient == "local")
    assert(not Service.request(p, {action = "add", listId = "local", revision = 0, fullType = "Base.Hammer", amount = 2}).error)
    assert(Service.snapshot(p).lists[1].entries['Base.Hammer'].amount == 2)
    assert(Service.request(p, {action = "add", listId = "local", revision = 0, fullType = "Base.Hammer", amount = 2}).error == "stale_revision")
    client = true
    assert(Service.request(p, {action = "sync"}).error == "forbidden")
    client = false
end)
check("private journal reloads entries and done state without executing saved text", function()
    local p = player("")
    assert(not Service.request(p, {action = "done", listId = "local", revision = 1, fullType = "Base.Hammer", done = true}).error)
    modules['PZSurvivorWishlist/Service'] = nil
    Service = require "PZSurvivorWishlist/Service"
    local entry = Service.snapshot(p).lists[1].entries['Base.Hammer']
    assert(entry.amount == 2 and entry.done)
    assert(not Service.request(p, {action = "done", listId = "local", revision = 2, fullType = "Base.Hammer", done = false}).error)
    files[paths[#paths]] = "os.execute('untrusted')\n"
    modules['PZSurvivorWishlist/Service'] = nil
    Service = require "PZSurvivorWishlist/Service"
    assert(Service.snapshot(p).lists[1].entries['Base.Hammer'].done) -- previous complete slot survives
end)
check("failed write keeps previous memory and complete disk slot", function()
    local p = player("")
    local before = Service.snapshot(p).lists[1]
    writeFailure = "throw"
    local payload, changed = Service.request(p, {action = "add", listId = "local", revision = before.revision,
        fullType = "Base.Hammer", amount = 8, requestId = "disk-error"})
    assert(not changed and payload.error == "storage_write" and payload.requestId == "disk-error")
    assert(payload.lists[1].entries['Base.Hammer'].amount == 2 and payload.lists[1].revision == before.revision)
    writeFailure = nil
    modules['PZSurvivorWishlist/Service'] = nil
    Service = require "PZSurvivorWishlist/Service"
    assert(Service.snapshot(p).lists[1].revision == before.revision)
    writeFailure = "silent"
    assert(Service.request(p, {action = "remove", listId = "local", revision = before.revision, fullType = "Base.Hammer"}).error == "storage_write")
    writeFailure = nil
    assert(Service.snapshot(p).lists[1].entries['Base.Hammer'].amount == 2)
end)
check("legacy version-one journal is read and upgraded without losing exact wishes", function()
    local previousWorld = world
    world = "/Saves/Sandbox/legacy-wishlist"
    local p = player("")
    local Identity = require "PZSurvivorWishlist/StorageIdentity"
    local prefix = Identity.legacyPrefix(world)
    directories[prefix] = true
    local original = "PZSW\t1\t7\nL\tlocal\t2\t\nE\tBase.Hammer\t3\t0\nE\tBase.Nails\t1\t1\nEND\t7\t268429812\n"
    files[prefix .. "a.txt"], files[prefix .. "b.txt"] = original, "incomplete peer\n"
    modules['PZSurvivorWishlist/Service'] = nil
    Service = require "PZSurvivorWishlist/Service"
    local list = Service.snapshot(p).lists[1]
    assert(list.revision == 2 and list.entries['Base.Hammer'].amount == 3)
    assert(list.entries['Base.Nails'].done and not list.entries['Base.Hammer'].vehicleTypes)
    assert(not Service.request(p, {action = "set", listId = "local", revision = 2,
        fullType = "Base.Hammer", amount = 4}).error)
    assert(files[paths[#paths]]:find("PZSW\t3\t9\nI\t" .. Identity.encode(world) .. "\n", 1, true) == 1)
    assert(files[prefix .. "a.txt"] == original and files[prefix .. "b.txt"] == "incomplete peer\n")
    modules['PZSurvivorWishlist/Service'] = nil
    Service = require "PZSurvivorWishlist/Service"
    list = Service.snapshot(p).lists[1]
    assert(list.revision == 3 and list.entries['Base.Hammer'].amount == 4 and list.entries['Base.Nails'].done)
    world = previousWorld
end)
check("vehicle rules survive private journal reload alongside legacy exact entries", function()
    local previousWorld = world
    world = "/Saves/Sandbox/vehicle-wishlist"
    local p = player("")
    assert(not Service.snapshot(p).error)
    assert(not Service.request(p, {action = "add", listId = "local", revision = 0,
        fullType = "Base.Hammer", amount = 2}).error)
    assert(not Service.request(p, {action = "addMany", listId = "local", revision = 1, entries = {{
        fullType = "Base.OldTire2", amount = 4, vehicleClass = 2,
        vehicleTypes = {"Base.OldTire2", "Base.NormalTire2", "Base.ModernTire2"}}}}).error)
    modules['PZSurvivorWishlist/Service'] = nil
    Service = require "PZSurvivorWishlist/Service"
    local entries = Service.snapshot(p).lists[1].entries
    assert(entries['vehicle:Base.OldTire2'].vehicleTypes[3] == "Base.ModernTire2")
    assert(entries['vehicle:Base.OldTire2'].vehicleClass == 2 and entries['vehicle:Base.OldTire2'].amount == 4)
    assert(entries['Base.Hammer'].amount == 2 and not entries['Base.Hammer'].vehicleTypes)
    assert(not Service.request(p,{action="remove",listId="local",revision=2,fullType="vehicle:Base.OldTire2"}).error)
    modules['PZSurvivorWishlist/Service']=nil;Service=require "PZSurvivorWishlist/Service"
    entries=Service.snapshot(p).lists[1].entries
    assert(not entries['vehicle:Base.OldTire2'] and entries['Base.Hammer'].amount==2, "removed groups stay removed after reload")
    world = previousWorld
end)
check("save identities isolate worlds with a bounded complete path", function()
    local p = player("")
    world = "/Saves/Sandbox/" .. string.rep("longworld", 40)
    assert(Service.snapshot(p).lists[1].revision == 0)
    assert(#paths[#paths] < 100, "identity expands the total storage path")
    world = "/Saves/Sandbox/sp-test"
    assert(Service.snapshot(p).lists[1].entries['Base.Hammer'].done)
end)
check("unknown journal version is retained and read failures block writes", function()
    local p = player("")
    world = "/Saves/Sandbox/version-test"
    assert(not Service.snapshot(p).error)
    local path = paths[#paths]
    files[path] = "PZSW\t4\t1\n"
    modules['PZSurvivorWishlist/Service'] = nil
    Service = require "PZSurvivorWishlist/Service"
    local count = #paths
    assert(Service.request(p, {action = "sync"}).error == "storage_version")
    assert(#paths == count and files[path] == "PZSW\t4\t1\n")
    world, readFailure = "/Saves/Sandbox/read-failure", true
    assert(Service.snapshot(p).error == "storage_read" and #paths == count)
    readFailure = false
end)
check("nil/read/close failures retain existing slots and never publish an empty cache", function()
    world = "/Saves/Sandbox/read-retry"
    local p = player("")
    assert(not Service.snapshot(p).error)
    assert(not Service.request(p, {action = "add", listId = "local", revision = 0,
        fullType = "Base.Hammer", amount = 6}).error)
    local baseline = {}
    for path, bytes in pairs(files) do baseline[path] = bytes end
    local count, bootstraps = #paths, bootstrapOpens
    for _, fault in ipairs({"nil", true, "read", "close"}) do
        resets[#resets]()
        readFailure = fault
        assert(Service.snapshot(p).error == "storage_read")
        assert(Service.request(p, {action = "add", listId = "local", revision = 0,
            fullType = "Base.Nails", amount = 1}).error == "storage_read")
        assert(#paths == count and bootstrapOpens == bootstraps, "read failure opened a writer")
        for path, bytes in pairs(baseline) do assert(files[path] == bytes, "read failure changed disk") end
        readFailure = false
        local list = Service.snapshot(p).lists[1]
        assert(list.entries['Base.Hammer'].amount == 6 and list.revision == 1, "failed load cached an empty store")
        assert(#paths == count)
    end
    assert(opened == closed, "reader leaked on failure")
end)
check("empty new slots retry after failed bootstrap/read without truncating data", function()
    local p = player("")
    for _, fault in ipairs({"nil", "throw", "close"}) do
        world = "/Saves/Sandbox/bootstrap-" .. fault
        local count = #paths
        bootstrapFailure = fault
        assert(Service.snapshot(p).error == "storage_read" and #paths == count)
        bootstrapFailure = nil
        assert(Service.snapshot(p).lists[1].revision == 0)
        resets[#resets]()
        assert(Service.snapshot(p).lists[1].revision == 0)
    end
    world, readFailure = "/Saves/Sandbox/new-slots-read-retry", "nil"
    local count = #paths
    assert(Service.snapshot(p).error == "storage_read" and #paths == count)
    readFailure = false
    assert(Service.snapshot(p).lists[1].revision == 0)
    resets[#resets]()
    assert(Service.snapshot(p).lists[1].revision == 0)
    assert(opened == closed)
end)
check("nonempty invalid slots block initialization while empty slots remain uninitialized", function()
    world = "/Saves/Sandbox/corrupt-slots"
    local p = player("")
    assert(not Service.snapshot(p).error)
    local path, count = paths[#paths], #paths
    files[path] = "not a wishlist snapshot\n"
    resets[#resets]()
    assert(Service.snapshot(p).error == "storage_invalid" and #paths == count)
    assert(files[path] == "not a wishlist snapshot\n")
    files[path] = ""
    assert(Service.snapshot(p).lists[1].revision == 0)
end)

check("bounded slots bind exact identities and refuse a foreign opposite slot", function()
    local Identity = require "PZSurvivorWishlist/StorageIdentity"
    world = "/Saves/Sandbox/bound-identity"
    assert(not Service.snapshot(player("")).error)
    local prefix = Identity.prefix(world)
    local original = files[prefix .. "a.txt"]
    files[prefix .. "b.txt"] = original
    files[prefix .. "a.txt"] = "PZSW\t3\t2\nI\t" .. Identity.encode(world .. "-foreign") .. "\n"
    local count = #paths
    resets[#resets]()
    assert(Service.snapshot(player("")).error == "storage_invalid")
    assert(#paths == count and files[prefix .. "b.txt"] == original)
    files[prefix .. "a.txt"] = "PZSW\t3\tinvalid\nI\t" .. Identity.encode(world .. "-foreign") .. "\n"
    assert(Service.snapshot(player("")).error == "storage_invalid" and #paths == count)
    files[prefix .. "a.txt"] = ""
    local originalPrefix = Identity.prefix
    Identity.prefix = function() return prefix end -- deterministic bucket collision, full binding must reject it
    world = world .. "-collision"
    assert(Service.snapshot(player("")).error == "storage_invalid" and #paths == count)
    Identity.prefix = originalPrefix
end)
check("nonempty new corruption cannot resurrect a valid legacy store", function()
    local Identity = require "PZSurvivorWishlist/StorageIdentity"
    world = "/Saves/Sandbox/no-stale-fallback"
    assert(not Service.snapshot(player("")).error)
    local prefix, legacy = Identity.prefix(world), Identity.legacyPrefix(world)
    local old = "PZSW\t1\t7\nL\tlocal\t2\t\nE\tBase.Hammer\t3\t0\nE\tBase.Nails\t1\t1\nEND\t7\t268429812\n"
    directories[legacy], files[legacy .. "a.txt"] = true, old
    files[prefix .. "a.txt"] = "torn new data\n"
    resets[#resets]()
    local count = #paths
    assert(Service.snapshot(player("")).error == "storage_invalid")
    assert(#paths == count and files[legacy .. "a.txt"] == old)
end)
check("legacy corruption and explicit existence failures never initialize a replacement", function()
    local Identity = require "PZSurvivorWishlist/StorageIdentity"
    world = "/Saves/Sandbox/bad-legacy"
    local prefix = Identity.legacyPrefix(world)
    directories[prefix], files[prefix .. "a.txt"] = true, "corrupt legacy\n"
    local count = #paths
    assert(Service.snapshot(player("")).error == "storage_invalid" and #paths == count)
    local original = cacheFileExists
    cacheFileExists = function(path) if path:find("/v3/", 1, true) then return original(path) end; error("metadata denied") end
    world = "/Saves/Sandbox/metadata-error"
    assert(Service.snapshot(player("")).error == "storage_read" and #paths == count)
    cacheFileExists = original
end)
check("writer close failure retains previous memory and legacy migration bytes", function()
    world = "/Saves/Sandbox/write-close"
    local p = player("")
    assert(not Service.snapshot(p).error)
    writeFailure = "close"
    local payload, changed = Service.request(p, {action="add",listId="local",revision=0,fullType="Base.Hammer",amount=9})
    assert(not changed and payload.error == "storage_write" and payload.lists[1].revision == 0)
    writeFailure = nil
    assert(Service.snapshot(p).lists[1].revision == 0)
    local Identity = require "PZSurvivorWishlist/StorageIdentity"
    world = "/Saves/Sandbox/migration-write-close"
    local prefix = Identity.legacyPrefix(world)
    local old = "PZSW\t1\t7\nL\tlocal\t2\t\nE\tBase.Hammer\t3\t0\nE\tBase.Nails\t1\t1\nEND\t7\t268429812\n"
    directories[prefix], files[prefix .. "a.txt"] = true, old
    writeFailure = "close"
    assert(Service.snapshot(p).error == "storage_write" and files[prefix .. "a.txt"] == old)
    writeFailure = nil
    assert(Service.snapshot(p).lists[1].entries['Base.Hammer'].amount == 3)
end)
check("new readback failures keep the acknowledged memory and previous complete slot", function()
    world = "/Saves/Sandbox/readback-failures"
    local p, Identity = player(""), require "PZSurvivorWishlist/StorageIdentity"
    assert(not Service.snapshot(p).error)
    local before = files[Identity.prefix(world) .. "a.txt"]
    for _, fault in ipairs({"nil", "read", "close"}) do
        readFailure = fault
        local payload, changed = Service.request(p, {action="add",listId="local",revision=0,fullType="Base.Nails",amount=3})
        assert(not changed and payload.error == "storage_write" and payload.lists[1].revision == 0)
        readFailure = false
        assert(Service.snapshot(p).lists[1].revision == 0)
        assert(files[Identity.prefix(world) .. "a.txt"] == before)
    end
end)
check("legacy v2 migration chooses newest complete slot and retains version or I/O errors", function()
    local Identity = require "PZSurvivorWishlist/StorageIdentity"
    local function journal(version, generation)
        local lines = {"PZSW\t" .. version .. "\t" .. generation, "L\tlocal\t2\t", "E\tBase.Hammer\t3\t0"}
        local hash = 0
        for _, line in ipairs(lines) do
            for index = 1, #line do hash = (hash * 33 + string.byte(line,index)) % 2147483647 end
            hash = (hash * 33 + 10) % 2147483647
        end
        return table.concat(lines,"\n") .. "\nEND\t" .. generation .. "\t" .. hash .. "\n"
    end
    world = "/Saves/Sandbox/legacy-v2"
    local legacy = Identity.legacyPrefix(world)
    local older, newer = journal(1, 6), journal(2, 9)
    directories[legacy], files[legacy.."a.txt"], files[legacy.."b.txt"] = true, older, newer
    assert(Service.snapshot(player("")).lists[1].entries['Base.Hammer'].amount == 3)
    assert(files[Identity.prefix(world).."a.txt"]:find("PZSW\t3\t10\n",1,true)==1)
    assert(files[legacy.."a.txt"]==older and files[legacy.."b.txt"]==newer)
    world = "/Saves/Sandbox/legacy-future-peer"
    legacy = Identity.legacyPrefix(world)
    directories[legacy], files[legacy.."a.txt"], files[legacy.."b.txt"] = true, older, "PZSW\t4\t11\n"
    local count = #paths
    assert(Service.snapshot(player("")).error=="storage_version" and #paths==count)
    world = "/Saves/Sandbox/legacy-read-error"
    legacy = Identity.legacyPrefix(world)
    directories[legacy], files[legacy.."a.txt"] = true, newer
    local originalReader = getFileReader
    getFileReader = function(path, create)
        if path:find(legacy, 1, true)==1 then error("legacy read denied") end
        return originalReader(path, create)
    end
    assert(Service.snapshot(player("")).error=="storage_read" and #paths==count)
    getFileReader = originalReader
    assert(files[legacy.."a.txt"]==newer)
    assert(not Service.snapshot(player("")).error, "failed legacy read was cached as empty")
end)
local function probeSnapshots(fn)
    local model = modules['PZSurvivorWishlist/Model']
    local originalSnapshot, originalPairs = model.snapshot, pairs
    local entries, counts = {}, {snapshots = 0, entries = 0}
    model.snapshot = function(value, ...)
        counts.snapshots = counts.snapshots + 1
        for _, list in originalPairs(value.lists or {}) do entries[list.entries] = true end
        return originalSnapshot(value, ...)
    end
    pairs = function(value)
        if entries[value] then counts.entries = counts.entries + 1 end
        return originalPairs(value)
    end
    local ok, message = pcall(fn, counts)
    model.snapshot, pairs = originalSnapshot, originalPairs
    assert(ok, message)
end
check("unchanged periodic snapshots skip payload construction and visible entry traversal", function()
    server, world = true, "/Saves/Multiplayer/compact-refresh"
    local owner, viewer = player("compact-owner"), player("compact-viewer")
    assert(not Service.snapshot(owner).error)
    assert(not Service.request(owner, {action = "add", listId = "compact-owner", revision = 0,
        fullType = "Base.Hammer", amount = 2}).error)
    probeSnapshots(function(counts)
        local payload, ownerStamp = Service.snapshot(owner)
        local _, viewerStamp = Service.snapshot(viewer)
        assert(payload.lists[1].entries['Base.Hammer'].amount == 2)
        counts.snapshots, counts.entries = 0, 0
        for i = 1, 3 do
            payload, ownerStamp = Service.snapshot(owner, ownerStamp)
            assert(payload == nil)
        end
        assert(counts.snapshots == 0 and counts.entries == 0,
            "unchanged refresh constructed a payload or traversed cached entries")
        assert(not Service.request(owner, {action = "add", listId = "compact-owner", revision = 1,
            fullType = "Base.Nails", amount = 3}).error)
        counts.snapshots, counts.entries = 0, 0
        assert(Service.snapshot(viewer, viewerStamp) == nil,
            "a hidden private list edit republished an unrelated recipient")
        assert(counts.snapshots == 0 and counts.entries == 0)
        payload = Service.snapshot(owner, ownerStamp)
        assert(payload.lists[1].entries['Base.Nails'].amount == 3)
    end)
    server = false
end)
check("live faction metadata and explicit or faction revocation invalidate periodic stamps", function()
    server, world = true, "/Saves/Multiplayer/compact-acl"
    local owner, member = player("acl-owner"), player("acl-member")
    factions['acl-owner'], factions['acl-member'] = "Builders", "Builders"
    Service.snapshot(owner)
    assert(not Service.request(owner, {action = "share", listId = "acl-owner", revision = 0,
        members = {"acl-member"}, faction = true}).error)
    local _, ownerStamp = Service.snapshot(owner)
    local _, memberStamp = Service.snapshot(member)
    factions['acl-owner'] = nil
    local payload
    payload, memberStamp = Service.snapshot(member, memberStamp)
    assert(#payload.lists == 2, "explicit membership must survive owner's faction departure")
    for _, list in ipairs(payload.lists) do assert(list.faction == nil) end
    payload, ownerStamp = Service.snapshot(owner, ownerStamp)
    assert(payload.lists[1].faction == nil, "owner's effective faction metadata stayed cached")
    assert(not Service.request(owner, {action = "share", listId = "acl-owner", revision = 1,
        members = {}, faction = false}).error)
    payload, memberStamp = Service.snapshot(member, memberStamp)
    assert(#payload.lists == 1 and payload.lists[1].id == "acl-member")
    factions['acl-owner'] = "Builders"
    assert(not Service.request(owner, {action = "share", listId = "acl-owner", revision = 2,
        members = {}, faction = true}).error)
    payload, memberStamp = Service.snapshot(member, memberStamp)
    assert(#payload.lists == 2)
    factions['acl-member'] = "Other"
    payload, memberStamp = Service.snapshot(member, memberStamp)
    assert(#payload.lists == 1, "recipient faction departure retained a shared list")
    factions['acl-member'] = "Builders"
    payload, memberStamp = Service.snapshot(member, memberStamp)
    assert(#payload.lists == 2)
    factions['acl-owner'] = nil
    payload = Service.snapshot(member, memberStamp)
    assert(#payload.lists == 1, "owner faction departure retained faction access")
    factions['acl-member'], server = nil, false
end)
check("periodic stamps publish save and cache changes even at identical revisions", function()
    local p = player("")
    world = "/Saves/Sandbox/compact-context-a"
    local payload, stamp = Service.snapshot(p)
    assert(payload.lists[1].revision == 0)
    world = "/Saves/Sandbox/compact-context-b"
    payload, stamp = Service.snapshot(p, stamp)
    assert(payload and payload.lists[1].revision == 0)
    resets[#resets]()
    payload, stamp = Service.snapshot(p, stamp)
    assert(payload and payload.lists[1].revision == 0, "reloaded cache reused an old context's stamp")
    assert(Service.snapshot(p, stamp) == nil)
end)
check("periodic storage errors retry, suppress repeats and publish recovery", function()
    world, readFailure = "/Saves/Sandbox/compact-retry", "nil"
    local p, originalReader, attempts = player(""), getFileReader, 0
    getFileReader = function(...)
        attempts = attempts + 1
        return originalReader(...)
    end
    local payload, stamp = Service.snapshot(p)
    assert(payload.error == "storage_read")
    local previousAttempts = attempts
    payload, stamp = Service.snapshot(p, stamp)
    assert(payload == nil and attempts > previousAttempts, "identical errors stopped storage retries")
    readFailure = false
    payload, stamp = Service.snapshot(p, stamp)
    getFileReader = originalReader
    assert(payload and not payload.error and #payload.lists == 1)
    assert(Service.snapshot(p, stamp) == nil)
    local changed
    payload, changed, stamp = Service.request(p, {action = "remove", listId = "local", revision = 0,
        fullType = "Base.Hammer", requestId = "missing-entry"})
    assert(not changed and payload.error == "not_found" and payload.requestId == "missing-entry")
    payload, stamp = Service.snapshot(p, stamp)
    assert(payload and not payload.error and not payload.requestId,
        "transient command error remained in the periodic publication stamp")
    assert(Service.snapshot(p, stamp) == nil)
end)
local function event()
    local result = {}
    result.Add = function(fn) result[#result + 1] = fn end
    result.fire = function(...) for _, fn in ipairs(result) do fn(...) end end
    return result
end
Events = {OnClientCommand = event(), OnTick = event()}
getTimestampMs = function() return now end
local owner, friend, stranger = player("owner"), player("friend"), player("stranger")
local online = {owner, friend, stranger}
getOnlinePlayers = function() return {size = function() return #online end,
    get = function(_, i) return online[i + 1] end} end
local sent = {}
sendServerCommand = function(p, module, command, args)
    assert(p and module == "PZSurvivorWishlist" and command == "snapshot")
    sent[#sent + 1] = {player = p, args = args}
end
server, world = true, "/Saves/Multiplayer/server-test"
-- Kahlua does not implement weak table ownership.
local nativeSetmetatable = setmetatable
setmetatable = function(value, meta)
    return meta and meta.__mode and value or nativeSetmetatable(value, meta)
end
dofile(base .. "server/PZSurvivorWishlist/Server.lua")
setmetatable = nativeSetmetatable
local function command(p, args) Events.OnClientCommand.fire("PZSurvivorWishlist", "request", p, args) end
check("targeted server snapshots notify edits, revoke access, isolate request ids", function()
    Events.OnTick.fire()
    assert(#sent == 3)
    sent = {}
    command(owner, {action = "share", listId = "owner", revision = 0, members = {"friend"}, faction = false, requestId = "1"})
    assert(#sent == 2 and sent[1].player == owner and sent[2].player == friend)
    assert(sent[1].args.requestId == "1" and sent[2].args.requestId == nil)
    assert(sent[2].args.recipient == "friend" and #sent[2].args.lists == 2)
    sent = {}
    command(friend, {action = "add", listId = "owner", revision = 1, fullType = "Base.Hammer", amount = 1, requestId = "2"})
    assert(#sent == 2 and sent[1].player == friend and sent[2].player == owner and not sent[2].args.requestId)
    sent = {}
    command(owner, {action = "share", listId = "owner", revision = 2, members = {}, faction = false})
    assert(#sent == 2 and sent[2].player == friend and #sent[2].args.lists == 1)
    command(stranger, {action = "add", listId = "owner", revision = 3, fullType = "Base.Hammer", amount = 1})
    assert(sent[#sent].args.error == "forbidden" and #sent[#sent].args.lists == 1)
end)
check("periodic faction changes send replacement only when visibility changes", function()
    factions.owner, factions.friend = "Builders", "Builders"
    command(owner, {action = "share", listId = "owner", revision = 3, members = {}, faction = true})
    sent, now = {}, 5000
    Events.OnTick.fire()
    assert(#sent == 0)
    sent = {}
    factions.owner = nil
    now = 10000
    Events.OnTick.fire()
    assert(#sent == 2)
    for _, response in ipairs(sent) do
        if response.player == friend then assert(#response.args.lists == 1) end
        if response.player == owner then assert(response.args.lists[1].faction == nil) end
    end
    sent, now = {}, 15000
    Events.OnTick.fire()
    assert(#sent == 0)
end)
check("server bounds mutation bursts with explicit denial", function()
    now, sent = 20000, {}
    for i = 1, 10 do command(owner, {action = "sync", requestId = tostring(i)}) end
    assert(#sent == 9 and sent[9].args.error == "rate_limited" and sent[9].args.requestId == "9")
end)
check("refresh preserves online rate limits and releases departed players without weak keys", function()
    local former = setmetatable({}, {__mode = "v"})
    do
        local departed = player("departed")
        former[1] = departed
        online[#online + 1] = departed
        command(departed, {action = "sync"})
    end
    online = {owner, friend, stranger}
    sent = {}
    Events.OnTick.fire()
    sent = {}
    collectgarbage("collect")
    assert(former[1] == nil, "snapshots or request buckets retained a departed player")
    command(owner, {action = "sync", requestId = "11"})
    assert(#sent == 0, "refresh must not reset an online player's rate limit")
    now = now + 5000
    Events.OnTick.fire()
    assert(#sent == 0, "unchanged online snapshots must remain cached")
end)
check("unchanged server refresh skips payloads and keeps the five-second ACL interval", function()
    factions.owner = "Builders"
    sent = {}
    now = now + 4999
    Events.OnTick.fire()
    assert(#sent == 0, "ACL refresh ran before five seconds elapsed")
    now = now + 1
    Events.OnTick.fire()
    assert(#sent == 2, "live faction restoration was not checked at five seconds")
    for _, response in ipairs(sent) do
        assert(response.player == owner or response.player == friend)
        assert(not response.args.requestId and not response.args.error)
    end
    probeSnapshots(function(counts)
        -- Discover the actual cached entry tables before checking a periodic read.
        for _, p in ipairs(online) do Service.snapshot(p) end
        counts.snapshots, counts.entries = 0, 0
        sent, now = {}, now + 5000
        Events.OnTick.fire()
        assert(#sent == 0 and counts.snapshots == 0 and counts.entries == 0,
            "unchanged online refresh constructed or traversed full snapshots")
    end)
end)
check("private edits stay targeted and unchanged command replies retain request ids", function()
    sent = {}
    command(stranger, {action = "add", listId = "stranger", revision = 0,
        fullType = "Base.Nails", amount = 2, requestId = "private-edit"})
    assert(#sent == 1 and sent[1].player == stranger and sent[1].args.requestId == "private-edit")
    sent = {}
    command(stranger, {action = "sync", requestId = "same-state-a"})
    command(stranger, {action = "sync", requestId = "same-state-b"})
    assert(#sent == 2 and sent[1].args.requestId == "same-state-a" and sent[2].args.requestId == "same-state-b")
    sent, now = {}, now + 5000
    Events.OnTick.fire()
    assert(#sent == 0, "an unchanged command response invalidated periodic state")
    command(stranger, {action = "remove", listId = "stranger", revision = 1,
        fullType = "Base.Hammer", requestId = "missing-server-entry"})
    assert(#sent == 1 and sent[1].args.error == "not_found")
    sent, now = {}, now + 5000
    Events.OnTick.fire()
    assert(#sent == 1 and sent[1].player == stranger and not sent[1].args.error
        and not sent[1].args.requestId, "periodic refresh did not clear a transient command error")
end)
print("Wishlist model/server checks passed: " .. passed)
