local Model = require "PZSurvivorWishlist/Model"
local Service = {}
PZSurvivorWishlist.Service = Service
local saveKey, context

function Service.username(player)
    if not player then return nil end
    if not isClient() and not isServer() then return "local" end
    local username = player:getUsername()
    return username
end
local environment = {
    validItem = function(fullType)
        local item = ScriptManager.instance:FindItem(fullType)
        return item ~= nil and item:getFullName() == fullType
    end,
    factionOf = function(username)
        local faction = Faction.getPlayerFaction(username)
        return faction and faction:getName() or nil
    end,
}
local function checksum(hash, line)
    for i = 1, #line do hash = (hash * 33 + string.byte(line, i)) % 2147483647 end
    return (hash * 33 + 10) % 2147483647
end
local function columns(line)
    local values = {}
    for value in (line .. "\t"):gmatch("(.-)\t") do values[#values + 1] = value end
    return values
end
local function parse(reader)
    local header = reader:readLine()
    if not header or #header > 128 then return {error = "storage_invalid"} end
    local values = columns(header)
    if values[1] ~= "PZSW" or #values ~= 3 then return {error = "storage_invalid"} end
    if values[2] ~= "1" and values[2] ~= "2" then return {error = "storage_version"} end
    local generation = tonumber(values[3])
    if not generation or generation < 1 or generation > 2147483646 or generation ~= math.floor(generation) then return {error = "storage_invalid"} end
    local store, list, lines, hash = {version = 1, lists = {}}, nil, 0, checksum(0, header)
    while true do
        local line = reader:readLine()
        if not line or #line > 4608 then return {error = "storage_invalid"} end
        local fields = columns(line)
        if fields[1] == "END" then
            if #fields ~= 3 or tonumber(fields[2]) ~= generation or tonumber(fields[3]) ~= hash
                or reader:readLine() ~= nil then return {error = "storage_invalid"} end
            local error = Model.validateStore(store)
            return error and {error = error} or {store = store, generation = generation, hash = hash}
        end
        lines = lines + 1
        if lines > Model.limits.lists * (1 + Model.limits.members + Model.limits.entries) then return {error = "storage_invalid"} end
        hash = checksum(hash, line)
        if fields[1] == "L" and #fields == 4 and not store.lists[fields[2]] then
            list = {id = fields[2], owner = fields[2], revision = tonumber(fields[3]),
                faction = fields[4] ~= "" and fields[4] or nil, entries = {}, members = {}}
            store.lists[fields[2]] = list
        elseif fields[1] == "M" and #fields == 2 and list and not list.members[fields[2]] then
            list.members[fields[2]] = true
        elseif ((fields[1] == "E" and #fields == 4) or (fields[1] == "V" and #fields >= 6 and #fields <= 37))
            and list and not list.entries[fields[2]] and (fields[4] == "0" or fields[4] == "1") then
            local variants
            if fields[1] == "V" then
                variants = {}
                for i = 6, #fields do variants[#variants + 1] = fields[i] end
            end
            list.entries[fields[2]] = {amount = tonumber(fields[3]), done = fields[4] == "1", vehicleTypes = variants, vehicleClass = variants and tonumber(fields[5]) or nil}
        else
            return {error = "storage_invalid"}
        end
    end
end
local function read(path)
    local reader
    local ok, value = pcall(function()
        reader = getFileReader(path, false)
        return reader and parse(reader) or {missing = true}
    end)
    if reader then
        local closed = pcall(function() reader:close() end)
        if not closed then ok = false end
    end
    return ok and value or {error = "storage_read"}
end
local function loadContext()
    local world = getCurrentSaveName()
    if type(world) ~= "string" or #world == 0 or #world > 512 then return {error = "storage_unavailable"} end
    if saveKey == world and context then return context end
    -- Vanilla file APIs write under Lua cache. Chunk the encoded save path to keep filename components short.
    local encoded = world:gsub(".", function(char) return string.format("%04x", string.byte(char)) end)
    local parts = {"PZSurvivorWishlist"}
    for i = 1, #encoded, 80 do parts[#parts + 1] = encoded:sub(i, i + 79) end
    local prefix = table.concat(parts, "/") .. "/"
    local a, b = read(prefix .. "a.txt"), read(prefix .. "b.txt")
    if a.error == "storage_version" or b.error == "storage_version" then return {error = "storage_version"} end
    if a.error == "storage_read" or b.error == "storage_read" then return {error = "storage_read"} end
    local chosen, slot
    if a.store and (not b.store or a.generation >= b.generation) then chosen, slot = a, "a"
    elseif b.store then chosen, slot = b, "b"
    elseif not a.missing or not b.missing then return {error = "storage_invalid"} end
    context = {prefix = prefix, store = chosen and chosen.store or {}, generation = chosen and chosen.generation or 0, slot = slot}
    saveKey = world
    return context
end
local function write(ctx, store)
    if ctx.generation >= 2147483646 then return "limit" end
    local generation = ctx.generation + 1
    local slot = ctx.slot == "a" and "b" or "a"
    local path = ctx.prefix .. slot .. ".txt"
    local writer, hash
    local ok = pcall(function()
        writer = getFileWriter(path, true, false)
        if not writer then error("Cannot open wishlist file") end
        local function line(value)
            hash = checksum(hash or 0, value)
            writer:write(value .. "\n")
        end
        line("PZSW\t2\t" .. generation)
        for id, list in pairs(store.lists) do
            line("L\t" .. id .. "\t" .. list.revision .. "\t" .. (list.faction or ""))
            for username in pairs(list.members) do line("M\t" .. username) end
            for fullType, entry in pairs(list.entries) do
                local prefix = entry.vehicleTypes and "V" or "E"
                local variants = entry.vehicleTypes and ("\t" .. entry.vehicleClass .. "\t" .. table.concat(entry.vehicleTypes, "\t")) or ""
                line(prefix .. "\t" .. fullType .. "\t" .. entry.amount .. "\t" .. (entry.done and "1" or "0") .. variants)
            end
        end
        writer:write("END\t" .. generation .. "\t" .. hash .. "\n")
        writer:close()
        writer = nil
    end)
    if writer then pcall(function() writer:close() end) end
    if not ok then return "storage_write" end
    -- PrintWriter can swallow I/O errors; verify the new slot before acknowledging or replacing memory.
    local saved = read(path)
    if not saved.store or saved.generation ~= generation or saved.hash ~= hash then return "storage_write" end
    ctx.store, ctx.generation, ctx.slot = store, generation, slot
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local function candidate(ctx, listId)
    if not ctx.store.lists then return {} end
    local result = {version = ctx.store.version, lists = {}}
    for id, list in pairs(ctx.store.lists) do result.lists[id] = id == listId and copy(list) or list end
    return result
end
local lastStorageError
local function failure(ctx, actor, error, args)
    if error:find("storage_", 1, true) == 1 and lastStorageError ~= error then
        lastStorageError = error
        print("[Survivor Wishlist] " .. error .. "; check Lua/PZSurvivorWishlist for this save. Existing data was retained.")
    end
    local payload = ctx.store and Model.snapshot(copy(ctx.store), actor, environment) or {lists = {}}
    payload.error, payload.recipient = error, actor
    if type(args) == "table" and type(args.requestId) == "string" and #args.requestId > 0
        and #args.requestId <= 64 and not args.requestId:find("%c") then payload.requestId = args.requestId end
    return payload, false
end
function Service.snapshot(player)
    if isClient() then return {lists = {}, error = "forbidden"} end
    local actor, ctx = Service.username(player), loadContext()
    if ctx.error then return failure(ctx, actor, ctx.error) end
    if not ctx.store.lists or not ctx.store.lists[actor] then
        local nextStore = candidate(ctx)
        local payload = Model.snapshot(nextStore, actor, environment)
        if payload.error then return failure(ctx, actor, payload.error) end
        local error = write(ctx, nextStore)
        if error then return failure(ctx, actor, error) end
    end
    local payload = Model.snapshot(ctx.store, actor, environment)
    payload.recipient = actor
    return payload
end
function Service.request(player, args)
    if isClient() then return {lists = {}, error = "forbidden"}, false end
    local actor, ctx = Service.username(player), loadContext()
    if ctx.error then return failure(ctx, actor, ctx.error, args) end
    local nextStore = candidate(ctx, type(args) == "table" and args.listId or nil)
    local payload, changed = Model.request(nextStore, actor, args, environment)
    if changed or (nextStore.lists and nextStore.lists[actor] and (not ctx.store.lists or not ctx.store.lists[actor])) then
        local error = write(ctx, nextStore)
        if error then return failure(ctx, actor, error, args) end
    end
    payload.recipient = actor
    return payload, changed
end
local function clearCache() saveKey, context, lastStorageError = nil, nil, nil end
Events.OnMainMenuEnter.Add(clearCache)
Events.OnGameStart.Add(clearCache)
return Service
