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
getCurrentSaveName = function() return world end
getFileReader = function(path, create)
    assert(create == false)
    if readFailure then error("disk read failed") end
    if files[path] == nil then return nil end
    local position, contents = 1, files[path]
    return {readLine = function()
        if position > #contents then return nil end
        local finish = contents:find("\n", position, true)
        local line = contents:sub(position, finish and finish - 1 or #contents)
        position = finish and finish + 1 or #contents + 1
        return line
    end, close = function() end}
end
getFileWriter = function(path, create, append)
    assert(create == true and append == false and not path:find("..", 1, true))
    for component in path:gmatch("[^/]+") do assert(#component <= 80) end
    paths[#paths + 1] = path
    files[path] = ""
    local writes = 0
    return {write = function(_, text)
        writes = writes + 1
        if writeFailure == "throw" and writes > 1 then error("disk write failed") end
        if writeFailure ~= "silent" then files[path] = files[path] .. text end
    end, close = function() end}
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
check("save identities isolate worlds and split long paths into safe components", function()
    local p = player("")
    world = "/Saves/Sandbox/" .. string.rep("longworld", 40)
    assert(Service.snapshot(p).lists[1].revision == 0)
    world = "/Saves/Sandbox/sp-test"
    assert(Service.snapshot(p).lists[1].entries['Base.Hammer'].done)
end)
check("unknown journal version is retained and read failures block writes", function()
    local p = player("")
    world = "/Saves/Sandbox/version-test"
    assert(not Service.snapshot(p).error)
    local path = paths[#paths]
    files[path] = "PZSW\t2\t1\n"
    modules['PZSurvivorWishlist/Service'] = nil
    Service = require "PZSurvivorWishlist/Service"
    local count = #paths
    assert(Service.request(p, {action = "sync"}).error == "storage_version")
    assert(#paths == count and files[path] == "PZSW\t2\t1\n")
    world, readFailure = "/Saves/Sandbox/read-failure", true
    assert(Service.snapshot(p).error == "storage_read" and #paths == count)
    readFailure = false
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
getOnlinePlayers = function() return {size = function() return 3 end,
    get = function(_, i) return ({owner, friend, stranger})[i + 1] end} end
local sent = {}
sendServerCommand = function(p, module, command, args)
    assert(p and module == "PZSurvivorWishlist" and command == "snapshot")
    sent[#sent + 1] = {player = p, args = args}
end
server, world = true, "/Saves/Multiplayer/server-test"
dofile(base .. "server/PZSurvivorWishlist/Server.lua")
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
print("Wishlist model/server checks passed: " .. passed)
