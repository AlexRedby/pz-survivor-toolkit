require "LootSorter_Rpc"
local Model = require "PZSurvivorToolkit/ManifestModel"
local Discovery = require "PZSurvivorToolkit/ManifestDiscovery"
local Appearance = require "PZSurvivorToolkit/ContainerAppearance"
local Authority = {}
PZSurvivorToolkit.ManifestAuthority = Authority
if not LootSorter.isAuthority() then return Authority end
local runtime
local function now() return getTimestampMs() end
function Authority.resetRuntime()
    runtime = {sessions = {}, serial = 0, activeUntil = 0, nextAt = 0}
end
Authority.resetRuntime()
local function changed(store) store.revision = store.revision + 1 end
local function sameFields(a, b, fields)
    if not a or not b then return a == b end
    for _, field in ipairs(fields) do if a[field] ~= b[field] then return false end end
    return true
end
local HEADER_FIELDS = {"id", "key", "x", "y", "z", "object", "ci", "kind", "name", "loaded", "legacy"}
local ICON_FIELDS, COLOR_FIELDS = {"kind", "value"}, {"r", "g", "b", "a"}
local ENTRY_FIELDS = {"key", "ft", "name", "cat", "mediaId", "mediaIndex", "tagKey", "ingredient", "cookingState", "fluidState", "usageState", "n"}
local function sameHeader(a, b)
    return sameFields(a, b, HEADER_FIELDS) and sameFields(a.icon, b.icon, ICON_FIELDS)
        and sameFields(a.color, b.color, COLOR_FIELDS)
end
local function add(store, record, unchanged)
    if not store.containers[record.id] then store.liveCount = store.liveCount + 1 end
    if not store.positions[record.id] then
        store.order[#store.order + 1] = record.id
        store.positions[record.id] = #store.order
    end
    store.byCoord[record.key] = store.byCoord[record.key] or {}
    store.byCoord[record.key][record.id] = true
    store.containers[record.id] = record
    if not unchanged then changed(store) end
end
local function remove(store, id)
    local old = store.containers[id]
    if not old then return end
    store.containers[id] = nil
    store.liveCount = store.liveCount - 1
    if store.byCoord[old.key] then store.byCoord[old.key][id] = nil end
    changed(store)
end
function Authority.getStore()
    local store = ModData.getOrCreate(Model.STORE)
    if store.schema ~= Model.SCHEMA then
        store.containers, store.order, store.byCoord, store.positions, store.revision = {}, {}, {}, {}, 0
        store.liveCount = 0
        store.schema = Model.SCHEMA
    end
    return store
end
local function registry() return ModData.getOrCreate("LootSorter_Registry").boxes or {} end
local function square(coord)
    local x, y, z = LootSorter.parseCoordKey(coord)
    local cell = getCell()
    return x and cell and cell:getGridSquare(x, y, z) or nil
end
local function beginCycle(store)
    if #store.order > 256 and #store.order > store.liveCount * 2 then
        runtime.compact = {oldOrder = store.order, order = {}, positions = {}, index = 1}
    end
    -- pairs() provides a resumable iterator without relying on Kahlua's absent next global.
    runtime.regIter, runtime.regState, runtime.regKey = pairs(registry())
    runtime.phase = "registry"
end
local function beginTile(coord, sq)
    runtime.tile = {key = coord, square = sq, object = 0, ci = 0, found = {}}
end
local function scanContainer(store, tile, obj, container)
    local appearance = Appearance.read(obj, tile.ci, nil)
    local record = {id = tile.key .. "/" .. tile.object .. "/" .. tile.ci,
        key = tile.key, x = tile.square:getX(), y = tile.square:getY(), z = tile.square:getZ(),
        object = tile.object, ci = tile.ci, kind = Model.text(container:getType()),
        name = Model.text(appearance.name, 256), icon = appearance.icon and {
            kind = Model.text(appearance.icon.kind, 32), value = Model.text(appearance.icon.value)},
        color = appearance.color and {r = appearance.color.r, g = appearance.color.g,
            b = appearance.color.b, a = appearance.color.a},
        loaded = true, sampledAt = now(), entries = {}, itemOrder = {}}
    tile.scan = {container = container, object = obj, items = container:getItems(), index = 0,
        record = record, previous = store.containers[record.id], matches = 0}
    tile.scan.size = tile.scan.items:size()
end
local function cleanupTile(store, tile)
    tile.cleanIter, tile.cleanState, tile.cleanKey = pairs(store.byCoord[tile.key] or {})
    tile.cleaning = true
end
local function migrateOne(store)
    local migration = runtime.migration
    if not migration then
        local iter, state, key = pairs(store.boxes or {})
        local coord, entries = iter(state, key)
        if not coord then store.boxes = nil; return false end
        local x, y, z = LootSorter.parseCoordKey(coord)
        if not x or type(entries) ~= "table" then store.boxes[coord] = nil; return true end
        local record = {id = "legacy:" .. coord, key = coord, x = x, y = y, z = z,
            legacy = true, loaded = false, sampledAt = 0, entries = {}, itemOrder = {}}
        local entryIter, entryState, entryKey = pairs(entries)
        migration = {coord = coord, record = record, iter = entryIter, state = entryState, key = entryKey}
        runtime.migration = migration
    end
    local label, entry = migration.iter(migration.state, migration.key)
    if not label then
        if not store.containers[migration.record.id] then add(store, migration.record) end
        store.boxes[migration.coord], runtime.migration = nil, nil
    else
        migration.key = label
        if type(entry) == "table" and type(entry.n) == "number" and entry.n > 0 then
            local ft, name = Model.text(entry.ft), Model.text(label)
            local key = Model.identity(ft, name, Model.text(entry.cat, 256))
            migration.record.entries[key] = {key = key, ft = ft, name = name,
                cat = Model.text(entry.cat, 256), n = entry.n}
            migration.record.itemOrder[#migration.record.itemOrder + 1] = key
        end
    end
    return true
end
function Authority.step(itemBudget, nodeBudget)
    local store = Authority.getStore()
    itemBudget, nodeBudget = itemBudget or 160, nodeBudget or 40
    local used, nodes = 0, 0
    if not runtime.phase then beginCycle(store) end
    while used < itemBudget and nodes < nodeBudget do
        nodes = nodes + 1
        local tile = runtime.tile
        if store.boxes then
            migrateOne(store)
            used = used + 1
        elseif runtime.compact then
            local work = runtime.compact
            local id = work.oldOrder[work.index]
            if id == nil then
                store.order, store.positions = work.order, work.positions
                runtime.compact = nil
            else
                work.index = work.index + 1
                if store.containers[id] then
                    work.order[#work.order + 1] = id
                    work.positions[id] = #work.order
                end
            end
        elseif runtime.unloaded then
            local work = runtime.unloaded
            local id = work.iter(work.state, work.key)
            if not id then runtime.unloaded = nil
            else
                work.key = id
                local record = store.containers[id]
                if record and record.loaded then
                    local replacement = Model.header(record)
                    replacement.entries, replacement.itemOrder, replacement.loaded = record.entries, record.itemOrder, false
                    add(store, replacement)
                end
            end
        elseif tile then
            if square(tile.key) ~= tile.square then runtime.tile = nil
            elseif tile.cleaning then
                local id = tile.cleanIter(tile.cleanState, tile.cleanKey)
                if not id then
                    local any = false
                    for _ in pairs(store.byCoord[tile.key] or {}) do any = true; break end
                    if not any then store.byCoord[tile.key] = nil end
                    runtime.tile = nil
                else
                    tile.cleanKey = id
                    if not tile.found[id] then remove(store, id) end
                end
            elseif tile.scan then
                local scan = tile.scan
                if scan.container:getItems() ~= scan.items or scan.items:size() ~= scan.size
                    or scan.object:getContainerByIndex(tile.ci) ~= scan.container then
                    -- A transfer during an incremental sample must not publish a partial count.
                    tile.scan = nil
                elseif scan.index < scan.size then
                    local entry = Model.item(scan.items:get(scan.index))
                    scan.index, used = scan.index + 1, used + 1
                    if entry then
                        local old = scan.record.entries[entry.key]
                        local previous = scan.previous and scan.previous.entries[entry.key]
                        -- matches counts fully equal groups in the partial aggregate. A later item
                        -- may take a group past its old count, so remove that match before adding.
                        if old then
                            if previous and old.n == previous.n and sameFields(old, previous, ENTRY_FIELDS) then
                                scan.matches = scan.matches - 1
                            end
                            old.n = old.n + 1
                        else
                            old = entry
                            scan.record.entries[entry.key] = entry
                            scan.record.itemOrder[#scan.record.itemOrder + 1] = entry.key
                        end
                        if previous and old.n == previous.n and sameFields(old, previous, ENTRY_FIELDS) then
                            scan.matches = scan.matches + 1
                        end
                    end
                else
                    if Discovery.designated(scan.object, tile.ci) then
                        tile.found[scan.record.id] = true
                        -- Compare while sampling, rather than traversing a large aggregate a second
                        -- time at completion. Cardinality also detects missing and additional keys.
                        local unchanged = scan.previous and scan.matches == #scan.record.itemOrder
                            and #scan.previous.itemOrder == #scan.record.itemOrder
                            and sameHeader(scan.previous, scan.record)
                        if unchanged then
                            scan.record.entries, scan.record.itemOrder = scan.previous.entries, scan.previous.itemOrder
                        end
                        add(store, scan.record, unchanged)
                    end
                    tile.scan, tile.ci = nil, tile.ci + 1
                end
            else
                local objects = tile.square:getObjects()
                if tile.object >= objects:size() then cleanupTile(store, tile)
                else
                    local obj = objects:get(tile.object)
                    local count = obj and obj:getContainerCount() or 0
                    if tile.ci >= count then tile.object, tile.ci = tile.object + 1, 0
                    else
                        local container = obj:getContainerByIndex(tile.ci)
                        if container and Discovery.designated(obj, tile.ci) then scanContainer(store, tile, obj, container)
                        else tile.ci = tile.ci + 1 end
                    end
                end
            end
        elseif runtime.phase == "registry" then
            local ok, coord = pcall(runtime.regIter, runtime.regState, runtime.regKey)
            if not ok then beginCycle(store)
            elseif not coord then
                runtime.phase = "stored"
                runtime.storedIter, runtime.storedState, runtime.storedKey = pairs(store.byCoord)
            else
                runtime.regKey = coord
                local sq = square(coord)
                if sq then beginTile(coord, sq)
                else
                    local iter, state, key = pairs(store.byCoord[coord] or {})
                    runtime.unloaded = {iter = iter, state = state, key = key}
                end
            end
        else
            local ok, coord = pcall(runtime.storedIter, runtime.storedState, runtime.storedKey)
            if not ok or not coord then runtime.phase = nil; break end
            runtime.storedKey = coord
            -- Index removals may be observed while unloaded; retaining these last-known records is
            -- safer than erasing them. A loaded tile proves removal or destruction.
            if not registry()[coord] then
                local sq = square(coord)
                if sq then beginTile(coord, sq)
                else
                    local iter, state, key = pairs(store.byCoord[coord] or {})
                    runtime.unloaded = {iter = iter, state = state, key = key}
                end
            end
        end
    end
    return used, nodes
end
-- Pages carry fixed metadata and at most PAGE_ROWS entries. Session cursors are server-issued;
-- clients cannot submit world coordinates, inventories, counts, or an unbounded discovery hint.
function Authority.requestPage(player, args)
    if not player or type(args) ~= "table" then return "invalid" end
    for _, key in ipairs({"revision", "cursor"}) do
        local value = args[key]
        if value ~= nil and (type(value) ~= "number" or value ~= value
            or value < 0 or value > 1000000000000000 or value ~= math.floor(value)) then return "invalid" end
    end
    local store, timestamp = Authority.getStore(), now()
    runtime.activeUntil = timestamp + 6000
    local session = runtime.sessions[player]
    if args.cursor ~= nil then
        if not session or args.cursor ~= session.token or timestamp > session.expires then return "stale" end
    else
        runtime.serial = runtime.serial + 1
        session = {token = runtime.serial, revision = store.revision, index = 1, item = 1,
            unchanged = args.revision == store.revision,
            limit = #store.order, order = store.order, legacySeen = {}}
        runtime.sessions[player] = session
    end
    -- Freshness belongs to exactly the cached content revision. Do not date old counts with a
    -- newer sample after an intervening mutation; the client will restart as a full refresh.
    if session.unchanged and store.revision ~= session.revision then
        runtime.sessions[player] = nil
        return "stale"
    end
    session.expires = timestamp + 15000
    local page = {schema = Model.SCHEMA, revision = session.revision}
    if session.unchanged then page.unchanged, page.samples = true, {}
    else page.containers = {} end
    local rows, count, bytes, steps = 0, 0, 0, 0
    while session.index <= session.limit and rows < Model.PAGE_ROWS
        and count < Model.PAGE_CONTAINERS and bytes < Model.PAGE_BYTES and steps < 128 do
        steps = steps + 1
        local record = session.record or store.containers[session.order[session.index]]
        -- Coordinate legacy data overlaps every compartment until that tile finishes its first scan.
        if record then
            if record.legacy then session.legacySeen[record.key] = true
            elseif session.legacySeen[record.key] or store.containers["legacy:" .. record.key] then record = nil end
        end
        if not record then session.index = session.index + 1
        elseif session.unchanged then
            page.samples[record.id] = record.sampledAt
            count, bytes, session.index = count + 1, bytes + #record.id + 32, session.index + 1
        else
            session.record = record -- pin this immutable sample through all of its pages
            local header = Model.header(record)
            page.containers[#page.containers + 1] = header
            count, bytes = count + 1, bytes + 1800
            while session.item <= #record.itemOrder and rows < Model.PAGE_ROWS and bytes < Model.PAGE_BYTES do
                local key = record.itemOrder[session.item]
                local entry = record.entries[key]
                header.entries[key] = {key = entry.key, ft = entry.ft, name = entry.name, cat = entry.cat,
                    mediaId = entry.mediaId, mediaIndex = entry.mediaIndex, n = entry.n,
                    tagKey = entry.tagKey, tagDelta = entry.tagDelta, ingredient = entry.ingredient,
                    cookingState = entry.cookingState, fluidState = entry.fluidState, usageState = entry.usageState}
                rows, bytes, session.item = rows + 1, bytes + #key + #(entry.ft or "")
                    + #(entry.name or "") + #(entry.cat or "") + #(entry.mediaId or "") + #(entry.tagKey or "") + 222, session.item + 1
            end
            if session.item > #record.itemOrder then session.index, session.item, session.record = session.index + 1, 1, nil end
        end
    end
    if session.index <= session.limit then page.cursor = session.token
    else runtime.sessions[player] = nil end
    return "ok", page
end
LootSorter.serverFn("manifestPage", Authority.requestPage)
LootSorter.addOrReplaceHandler(Events.OnTick, "_manifestAuthorityTick", function()
    local timestamp = now()
    if timestamp < runtime.nextAt then return end
    runtime.nextAt = timestamp + (timestamp < runtime.activeUntil and 50 or 250)
    local ok, err = pcall(Authority.step, 160, 240)
    if not ok then
        runtime.tile, runtime.phase = nil, nil
        if LootSorter.DBG then LootSorter.DBG("manifest reconciliation: " .. tostring(err)) end
    end
    for player, session in pairs(runtime.sessions) do
        if timestamp > session.expires then runtime.sessions[player] = nil end
    end
end)
LootSorter.addOrReplaceHandler(Events.OnGameStart, "_manifestAuthorityStart", Authority.resetRuntime)
return Authority
