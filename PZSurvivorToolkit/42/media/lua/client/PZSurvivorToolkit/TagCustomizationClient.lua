local C = require "PZSurvivorToolkit/TagCustomization"
local Access = require "PZSurvivorToolkit/ItemAccess"
local Client = {}
PZSurvivorToolkit.TagCustomizationClient = Client
local sequences = setmetatable({}, {__mode="k"})
local pending = {}
local nextRefreshAt = 0
local itemRevisions = setmetatable({}, {__mode="k"})
local function finish(callback, status, payload)
    if type(callback) == "function" then pcall(callback, status, payload) end
end
local function reject(callback, reason)
    finish(callback, "rejected", {status="rejected",reason=reason,revision=C.getRevision()})
end
C.onChange(function()
    for playerNum = 0, getNumActivePlayers() - 1 do
        for _, getter in pairs({getPlayerInventory, getPlayerLoot}) do
            if type(getter) == "function" then
                local page = getter(playerNum)
                if page and page.inventoryPane then page.inventoryPane:refreshContainer() end
            end
        end
    end
end)
local function request(playerNum, command, args, callback, baseRevision)
    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() or not C.synced() then return reject(callback, "not ready") end
    local number = (sequences[player] or 0) + 1
    if number > 2147483647 then return reject(callback, "request limit") end
    local revision = baseRevision == nil and C.getRevision() or baseRevision
    if not C.integer(revision) or revision < 0 then return reject(callback, "invalid revision") end
    sequences[player] = number
    args.request, args.baseRevision = number, revision
    if isClient() then
        pending[playerNum] = pending[playerNum] or {}
        pending[playerNum][number] = {callback=callback, actor=player}
        sendClientCommand(player, C.MODULE, command, args)
    else
        local authority = require "PZSurvivorToolkit/TagCustomizationAuthority"
        local status, payload = authority.applyRequest(player, command, args)
        finish(callback, status, payload)
    end
    return number
end
function Client.edit(playerNum, id, definition, callback, baseRevision)
    if id ~= nil and not C.isValidId(id) then return reject(callback, "invalid id") end
    id = C.canonicalId(id)
    if definition ~= false and not C.normalizeDefinition(definition, true) then return reject(callback, "invalid definition") end
    return request(playerNum, "Edit", {id=id,definition=C.copy(definition)}, callback, baseRevision)
end
function Client.assign(playerNum, items, scope, changes, reset, callback, baseRevision)
    if scope ~= "type" and scope ~= "item" or type(reset) ~= "boolean" then return reject(callback, "invalid scope") end
    local clean = C.normalizeChanges(changes)
    if not clean or type(items) ~= "table" then return reject(callback, "invalid changes or selection") end
    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() then return reject(callback, "not ready") end
    local locators, seen, count = {}, {}, 0
    for index in pairs(items) do
        count = count + 1
        if count > C.MAX_ITEMS or not C.integer(index, C.MAX_ITEMS) or index < 1 then return reject(callback, "selection limit") end
    end
    for index = 1, count do
        local item = items[index]
        if not item then return reject(callback, "sparse selection") end
        if not seen[item] then
            local ok, locator = pcall(Access.locate, item, player)
            if not ok or not Access.validLocator(locator) then return reject(callback, "item unavailable") end
            locators[#locators + 1], seen[item] = locator, true
        end
    end
    if #locators == 0 then return reject(callback, "empty selection") end
    return request(playerNum, "Assign", {scope=scope,items=locators,changes=clean,reset=reset}, callback, baseRevision)
end
function Client.onChange(fn) C.onChange(fn) end
function Client.refresh()
    if not isClient() then C.changed({revision=C.getRevision()}); return end
    for playerNum = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(playerNum)
        if player and not player:isDead() then sendClientCommand(player, C.MODULE, "Refresh", {}) end
    end
end
local function validRows(rows)
    if type(rows) ~= "table" then return end
    local out, count = {}, 0
    for index in pairs(rows) do
        count = count + 1
        if count > C.MAX_ITEMS or not C.integer(index, C.MAX_ITEMS) or index < 1 then return end
    end
    for index = 1, count do
        local row = rows[index]
        if type(row) ~= "table" or not Access.validLocator(row.locator) then return end
        for key in pairs(row) do if key ~= "locator" and key ~= "delta" then return end end
        local delta = C.normalizeChanges(row.delta, true)
        if not delta then return end
        out[index] = {locator=row.locator, delta=delta}
    end
    return out
end
function Client.receive(command, args)
    if not isClient() or type(args) ~= "table" then return end
    if command == "Result" then
        if not C.integer(args.request) or (args.status ~= "accepted" and args.status ~= "conflict" and args.status ~= "rejected") then return end
        -- A request number is only unique for its owning local actor.
        for playerNum, requests in pairs(pending) do
            local saved = requests[args.request]
            if saved and (args.owner == nil or saved.actor:getOnlineID() == args.owner) then
                requests[args.request] = nil
                if getSpecificPlayer(playerNum) == saved.actor then finish(saved.callback, args.status, args) end
            end
        end
        return
    end
    if command ~= "State" then return end
    local catalog = C.normalizeCatalog(args.catalog)
    local rows = validRows(args.items or {})
    if not catalog or not rows or #rows > 0 and not C.integer(args.owner, 32767) then return end
    -- An older catalog can still carry the first State for a different loose world
    -- item. Per-item revisions keep that update without rolling back known edits.
    C.receive(catalog)
    for playerNum = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(playerNum)
        if player then
            for _, row in ipairs(rows) do
                if not row.locator.inv or player:getOnlineID() == args.owner then
                    local ok, item = pcall(Access.resolve, player, row.locator)
                    if ok and item and catalog.revision >= (itemRevisions[item] or -1) then
                        local located, exact = pcall(Access.sameLocation, item, player, row.locator)
                        if located and exact then
                            item:getModData()[C.FIELD] = C.hasEntries(row.delta) and C.copy(row.delta) or nil
                            itemRevisions[item] = catalog.revision
                        end
                    end
                end
            end
        end
    end
    C.changed({revision=C.getRevision(),items=rows,owner=args.owner})
end
Events.OnServerCommand.Add(function(module, command, args)
    if module == C.MODULE then Client.receive(command, args) end
end)
Events.OnReceiveGlobalModData.Add(function(key, value)
    if key == C.MODULE and isClient() then C.receive(value) end
end)
Events.OnGameStart.Add(function()
    nextRefreshAt = 0
    pending, itemRevisions = {}, setmetatable({}, {__mode="k"})
    C.resetReceived()
    Client.refresh()
end)
Events.OnCreatePlayer.Add(function() Client.refresh() end)
-- Early create/start events can precede native player admission. Keep catalog
-- readiness independent of that one-shot event order, with one read per second.
Events.OnTick.Add(function()
    if not isClient() or C.synced() then return end
    local now = getTimestampMs()
    if now < nextRefreshAt then return end
    nextRefreshAt = now + 1000
    for playerNum = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(playerNum)
        if player and not player:isDead() and player:getCurrentSquare() then
            sendClientCommand(player, C.MODULE, "Refresh", {})
        end
    end
end)
return Client
