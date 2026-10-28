require "PZSurvivorWishlist"
require "PZSurvivorWishlist/Service"

local W = PZSurvivorWishlist
local Client = {}
W.Client = Client
local states, serial = {}, 0

local function notifyError(playerNum, error)
    local player = getSpecificPlayer(playerNum)
    if error and player and HaloTextHelper then
        HaloTextHelper.addText(player, getText("UI_PZSW_Error_" .. error))
    end
end

function Client.state(playerNum)
    playerNum = playerNum or 0
    if not states[playerNum] then
        states[playerNum] = { lists = {}, selectedId = nil, queue = {}, generation = 0, wanted = {}, hasWanted = false }
    end
    return states[playerNum]
end

function Client.getList(playerNum, listId)
    for _, list in ipairs(Client.state(playerNum).lists) do
        if list.id == listId then return list end
    end
end

function Client.selected(playerNum)
    return Client.getList(playerNum, Client.state(playerNum).selectedId)
end

-- Removal targets entries in one displayed list, including completed requests.
-- Batch menus invert the variants once; standalone reads restrict work to one type.
local function entryIndex(list, onlyType)
    local index, exact = {}, {}
    if not list then return index end
    for key, entry in pairs(list.entries) do
        if not onlyType or key == onlyType then
            exact[key] = true
            index[key] = index[key] or {}
        end
        if entry.vehicleTypes then
            local seen = {}
            for _, variant in ipairs(entry.vehicleTypes) do
                if (not onlyType or variant == onlyType) and not seen[variant] then
                    local keys = index[variant] or {}
                    index[variant], seen[variant] = keys, true
                    keys[#keys + 1] = key
                    if onlyType then break end
                end
            end
        end
    end
    for fullType, keys in pairs(index) do
        table.sort(keys)
        if exact[fullType] then table.insert(keys, 1, fullType) end
    end
    return index
end

function Client.entryIndex(list)
    -- Detached snapshot for one menu build; do not retain across menu openings.
    return entryIndex(list)
end

function Client.entryKeys(list, fullType, index)
    if not index then return entryIndex(list, fullType)[fullType] or {} end
    local keys = {}
    for _, key in ipairs(index[fullType] or {}) do keys[#keys + 1] = key end
    return keys
end

function Client.select(playerNum, id)
    local state = Client.state(playerNum)
    for _, list in ipairs(state.lists) do
        if list.id == id then
            state.selectedId = id
            state.generation = state.generation + 1
            return true
        end
    end
    return false
end

-- Membership is supplied only by the server; highlights never scan containers.
function Client.isWanted(playerNum, fullType)
    return Client.state(playerNum).wanted[fullType] == true
end

function Client.hasWanted(playerNum)
    -- Kahlua pairs snapshots keys; this per-tick read must not enumerate membership.
    return Client.state(playerNum).hasWanted == true
end

local function send(playerNum, args)
    local player = getSpecificPlayer(playerNum)
    if not player then return end
    if isClient() then
        sendClientCommand(player, "PZSurvivorWishlist", "request", args)
    else
        Client.receive(playerNum, W.Service.request(player, args))
    end
end

local function flush(playerNum)
    local state = Client.state(playerNum)
    if state.pending or #state.queue == 0 then return end
    local request = table.remove(state.queue, 1)
    local list
    for _, candidate in ipairs(state.lists) do
        if candidate.id == request.listId then list = candidate; break end
    end
    if not list then
        state.error = "forbidden"
        state.queue = {}
        notifyError(playerNum, state.error)
        return
    end
    serial = serial + 1
    request.revision, request.requestId = list.revision, tostring(serial)
    state.pending, state.sentAt = request, getTimestampMs()
    send(playerNum, request)
end

function Client.receive(playerNum, payload)
    if type(payload) ~= "table" or type(payload.lists) ~= "table" then return end
    local state = Client.state(playerNum)
    local previousError = state.error
    state.lists, state.wanted, state.hasWanted = payload.lists, {}, false
    for _, list in ipairs(state.lists) do
        for fullType, entry in pairs(list.entries) do
            if not entry.done then
                if not entry.vehicleTypes then state.wanted[fullType], state.hasWanted = true, true end
                for _, variant in ipairs(entry.vehicleTypes or {}) do
                    state.wanted[variant], state.hasWanted = true, true
                end
            end
        end
    end
    state.generation = state.generation + 1
    local player = getSpecificPlayer(playerNum)
    state.username = player and W.Service.username(player)
    if not Client.selected(playerNum) then
        state.selectedId = nil
        for _, list in ipairs(state.lists) do
            if list.owner == state.username then state.selectedId = list.id; break end
        end
        if not state.selectedId and state.lists[1] then state.selectedId = state.lists[1].id end
    end
    if state.pending and payload.requestId == state.pending.requestId then
        state.pending = nil
        state.error = payload.error
        if payload.error then state.queue = {} end
    elseif payload.error then
        state.error = payload.error
    end
    if state.error ~= previousError then notifyError(playerNum, state.error) end
    flush(playerNum)
end

function Client.sync(playerNum)
    send(playerNum, { action = "sync" })
end

function Client.edit(playerNum, action, values)
    local state, list = Client.state(playerNum), Client.selected(playerNum)
    if not list then Client.sync(playerNum); return false end
    if #state.queue >= 32 then
        state.error = "limit"
        notifyError(playerNum, state.error)
        return false
    end
    local request = { action = action, listId = list.id }
    for key, value in pairs(values or {}) do request[key] = value end
    state.queue[#state.queue + 1] = request
    state.error = nil
    flush(playerNum)
    return true
end

function Client.addItems(playerNum, entries)
    if not Client.selected(playerNum) then Client.open(playerNum); return false end
    return Client.edit(playerNum, "addMany", { entries = entries })
end

function Client.addItem(playerNum, fullType, amount)
    return Client.addItems(playerNum, { { fullType = fullType, amount = amount or 1 } })
end

function Client.open(playerNum)
    if W.UI then W.UI.open(playerNum or 0) end
end

function Client.carried(playerNum)
    local player, result = getSpecificPlayer(playerNum), {}
    local seen = {}
    local function count(container)
        if not container or seen[container] then return end
        seen[container] = true
        local items = container:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            local fullType = item:getFullType()
            result[fullType] = (result[fullType] or 0) + 1
            if instanceof(item, "InventoryContainer") then count(item:getInventory()) end
        end
    end
    if player then count(player:getInventory()) end
    return result
end

function Client.carriedCount(counts, fullType, entry)
    if not entry.vehicleTypes then return counts[fullType] or 0 end
    local total = 0
    for _, variant in ipairs(entry.vehicleTypes) do total = total + (counts[variant] or 0) end
    return total
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PZSurvivorWishlist" or command ~= "snapshot" then return end
    for playerNum = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(playerNum)
        if player and args.recipient == W.Service.username(player) then Client.receive(playerNum, args) end
    end
end)

local nextSync = 0
Events.OnTick.Add(function()
    local now = getTimestampMs()
    if now < nextSync then return end
    nextSync = now + 5000
    for playerNum = 0, getNumActivePlayers() - 1 do
        if getSpecificPlayer(playerNum) then
            local state = Client.state(playerNum)
            local timedOut = state.pending and now - state.sentAt > 15000
            if timedOut then
                -- Never retry an uncertain increment: the server may already have applied it.
                state.pending, state.queue, state.error = nil, {}, "timeout"
                notifyError(playerNum, state.error)
            end
            if not state.pending and (not state.username or timedOut) then Client.sync(playerNum) end
        end
    end
end)
Events.OnGameStart.Add(function() states, nextSync = {}, 0 end)
Events.OnMainMenuEnter.Add(function() states, nextSync = {}, 0 end)
return Client
