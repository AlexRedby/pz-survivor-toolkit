if isClient() then return end
local C = require "PZSurvivorToolkit/TagCustomization"
local Access = require "PZSurvivorToolkit/ItemAccess"
local Authority = {}
local requests = setmetatable({}, {__mode="k"})
local function knownFields(value, fields)
    for key in pairs(value) do if not fields[key] then return false end end
    return true
end
local function arraySize(value, max)
    if type(value) ~= "table" then return end
    local count = 0
    for index in pairs(value) do
        count = count + 1
        if count > max or not C.integer(index, max) or index < 1 then return end
    end
    for index = 1, count do if value[index] == nil then return end end
    return count
end
local function actorReady(player)
    return player and not player:isDead() and player:getCurrentSquare() ~= nil
end
local function result(player, args, status, reason, id)
    local payload = {request=type(args)=="table" and args.request or nil,
        revision=C.getRevision(), status=status, reason=reason, id=id,
        owner=player and player:getOnlineID() or nil}
    if isServer() and player then sendServerCommand(player, C.MODULE, "Result", payload) end
    return status, payload
end
local function persist(candidate)
    local live = C.catalog()
    for key in pairs(live) do live[key] = nil end
    for key, value in pairs(candidate) do live[key] = value end
end
local editFields = {request=true,baseRevision=true,id=true,definition=true}
local assignFields = {request=true,baseRevision=true,scope=true,items=true,changes=true,reset=true}

function Authority.applyRequest(player, command, args)
    if not actorReady(player) or type(args) ~= "table" or not C.integer(args.request) or args.request < 1
        or not C.integer(args.baseRevision) or args.baseRevision < 0 then
        return result(player, args, "rejected", "invalid request")
    end
    if args.request <= (requests[player] or 0) then return result(player, args, "rejected", "replayed request") end
    -- A rejected newer packet must not allow an older packet to undo the user's newer intent.
    requests[player] = args.request
    local candidate = C.normalizeCatalog(C.catalog())
    if not candidate then return result(player, args, "rejected", "invalid saved catalog") end
    if args.baseRevision ~= candidate.revision then
        if isServer() then sendServerCommand(player, C.MODULE, "State", {catalog=candidate}) end
        return result(player, args, "conflict", "catalog changed")
    end
    if candidate.revision == 2147483647 then return result(player, args, "rejected", "revision limit") end
    local id, updates = args.id, {}
    if command == "Edit" then
        if not knownFields(args, editFields) or id ~= nil and not C.isValidId(id) then
            return result(player, args, "rejected", "invalid definition id")
        end
        if args.definition == false then
            if not id or C.customId(id) and (not candidate.definitions[id] or candidate.definitions[id].deleted) then
                return result(player, args, "rejected", "missing tag")
            end
            if C.customId(id) then
                local definition = candidate.definitions[id]
                definition.deleted = true
            else candidate.definitions[id] = nil end
        else
            local patch = C.normalizeDefinition(args.definition, true)
            if not patch then return result(player, args, "rejected", "invalid definition") end
            if not id then
                if not patch.name or candidate.nextId == 2147483647 then return result(player, args, "rejected", "name required or id limit") end
                for attempt = 1, 4 do
                    local uuid = getRandomUUID()
                    local generated = type(uuid) == "string" and "custom:" .. uuid:lower()
                    if generated and C.customId(generated) and not candidate.definitions[generated] then id = generated; break end
                end
                if not id then return result(player, args, "rejected", "id allocation failed") end
                candidate.nextId = candidate.nextId + 1
            elseif C.customId(id) and (not candidate.definitions[id] or candidate.definitions[id].deleted) then
                return result(player, args, "rejected", "missing tag")
            end
            local definition = C.copy(candidate.definitions[id] or {})
            for field, value in pairs(patch) do definition[field] = value ~= false and value or nil end
            if C.customId(id) and not definition.name then return result(player, args, "rejected", "name required") end
            candidate.definitions[id] = C.hasEntries(definition) and definition or nil
        end
    elseif command == "Assign" then
        local count = arraySize(args.items, C.MAX_ITEMS)
        local changes = C.normalizeChanges(args.changes)
        if not knownFields(args, assignFields) or (args.scope ~= "type" and args.scope ~= "item")
            or type(args.reset) ~= "boolean" or not count or count < 1 or not changes then
            return result(player, args, "rejected", "invalid assignment")
        end
        for changedId, operation in pairs(changes) do
            local definition = candidate.definitions[changedId]
            if operation ~= "default" and C.customId(changedId) and (not definition or definition.deleted) then
                return result(player, args, "rejected", "inactive tag")
            end
        end
        local seen, types = {}, {}
        for _, locator in ipairs(args.items) do
            local item = Access.admit(player, locator)
            -- Any failed exact access check rejects the complete selection before any edit.
            if not item then return result(player, args, "rejected", "item unavailable") end
            if not seen[item] then
                seen[item] = true
                if args.scope == "type" then
                    local fullType = C.normalizeType(item:getFullType())
                    if not fullType then return result(player, args, "rejected", "invalid item type") end
                    types[fullType] = true
                else
                    local current = item:hasModData() and item:getModData()[C.FIELD] or {}
                    local clean = C.normalizeChanges(current or {}, true)
                    if not clean and not args.reset then return result(player, args, "rejected", "invalid saved item delta") end
                    local delta = C.changeDelta(clean or {}, changes, args.reset)
                    if not C.normalizeChanges(delta, true) then return result(player, args, "rejected", "item delta limit") end
                    updates[#updates + 1] = {item=item, locator=C.copy(locator), delta=delta}
                end
            end
        end
        for fullType in pairs(types) do
            local delta = C.changeDelta(candidate.types[fullType] or {}, changes, args.reset)
            candidate.types[fullType] = C.hasEntries(delta) and delta or nil
        end
    else return result(player, args, "rejected", "unknown command") end
    candidate.revision = candidate.revision + 1
    local clean = C.normalizeCatalog(candidate)
    if not clean then return result(player, args, "rejected", "catalog limit") end
    -- The entire selection/catalog has passed bounds, revision and admission checks.
    persist(clean)
    local rows = {}
    for _, update in ipairs(updates) do
        update.item:getModData()[C.FIELD] = C.hasEntries(update.delta) and C.copy(update.delta) or nil
        rows[#rows + 1] = {locator=update.locator, delta=update.delta}
        if update.item:getContainer() then syncItemModData(player, update.item) end
    end
    local state = {catalog=C.copy(clean), owner=player:getOnlineID(), items=rows}
    C.changed(state)
    if isServer() then sendServerCommand(C.MODULE, "State", state) end
    return result(player, args, "accepted", nil, id)
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= C.MODULE then return end
    if command == "Refresh" then
        if player and not player:isDead() then sendServerCommand(player, C.MODULE, "State", {catalog=C.snapshot()}) end
    else Authority.applyRequest(player, command, args) end
end)
Events.OnInitGlobalModData.Add(function()
    requests = setmetatable({}, {__mode="k"})
    C.catalog()
end)
return Authority
