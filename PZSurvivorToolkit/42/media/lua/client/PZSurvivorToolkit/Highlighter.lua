require "PZSurvivorToolkit"
require "PZSurvivorToolkit/Settings"

local Toolkit = PZSurvivorToolkit
if Toolkit.Highlighter then return end

local Highlighter = {}
Toolkit.Highlighter = Highlighter

local SQUARE_BUDGET = 32
local ITEM_BUDGET = 128
local SQUARE_SLICE = 16
local REFRESH_MS = 250
local tracked, byObject = {}, {}
local cursor, refreshEpoch = 1, 0
local scan, previous, nextScanAt = nil, nil, 0
local lastError
local clearing = false
local offsetsByRadius = {}

local function reportError(message)
    message = tostring(message)
    if message ~= lastError then
        lastError = message
        print("[PZ Survivor Toolkit] Highlight error: " .. message)
    end
end

local function sameHighlight(record)
    local object = record.object
    local colour = object:getHighlightColor(record.playerNum)
    local expected = record.modelColour
    return object:isHighlighted(record.playerNum)
        and object:isOutlineHighlight(record.playerNum)
        and object:isOutlineHlAttached(record.playerNum) == record.attached
        and object:getOutlineHighlightCol(record.playerNum) == record.colour
        and colour:getR() == expected.r and colour:getG() == expected.g
        and colour:getB() == expected.b and colour:getA() == expected.a
end

local function release(record)
    if not record.owned then return end
    -- A different colour indicates that another highlighter took over.
    local ok, errorMessage = pcall(function()
        local object = record.object
        if sameHighlight(record) then
            -- World items clear their sprite outline together with the model highlight.
            object:setHighlighted(record.playerNum, false, false)
        end
    end)
    if not ok then reportError(errorMessage) end
end

local function forget(index)
    local record = tracked[index]
    release(record)
    byObject[record.object] = nil
    local last = tracked[#tracked]
    tracked[#tracked] = nil
    if index <= #tracked then
        tracked[index] = last
        last.index = index
    end
end

local function clearBatch()
    for i = #tracked, math.max(1, #tracked - ITEM_BUDGET + 1), -1 do forget(i) end
    clearing = #tracked > 0
end

function Highlighter.clear()
    cursor, scan, previous, nextScanAt = 1, nil, nil, 0
    clearBatch()
end

function Highlighter.settingsChanged()
    Highlighter.clear()
end

local function eligible(object, context)
    local square = object:getSquare()
    local item = object:getItem()
    if not square or not item or item:getWorldItem() ~= object then return false end
    if square:getZ() ~= context.z then return false end
    if context.cell:getGridSquare(square:getX(), square:getY(), square:getZ()) ~= square then
        return false
    end
    -- Seen/explored tiles are not proof of current sight: keep walls and FOV authoritative.
    if not square:isCanSee(context.playerNum) then return false end
    if not object:getDoRender() or object:getTargetAlpha(context.playerNum) <= 0 then return false end
    if not item:getScriptItem():isWorldRender() then return false end
    local dx = object:getWorldPosX() - context.x
    local dy = object:getWorldPosY() - context.y
    local radius, colour = context.normalRadius, context.normalColour
    if context.wishlist and context.wishlist.isWanted(context.playerNum, item:getFullType()) then
        radius, colour = 15, context.wantedColour
    elseif not context.normalEnabled then
        return false
    end
    if dx * dx + dy * dy <= radius * radius then return colour end
    return false
end

local function refresh(record, context)
    local ok, valid = pcall(function()
        local object = record.object
        local colour = eligible(object, context)
        if not colour then return false end
        local ours = record.owned and sameHighlight(record)
        if (object:isOutlineHighlight(record.playerNum) or object:isHighlighted(record.playerNum)) and not ours then
            record.owned = false
        elseif not ours or record.requestedColour.r ~= colour.r or record.requestedColour.g ~= colour.g
            or record.requestedColour.b ~= colour.b or record.requestedColour.a ~= colour.a then
            -- The world-item override sets the vanilla colour and outline, so colour comes last.
            if not ours then object:setHighlighted(record.playerNum, true, false) end
            object:setHighlightColor(record.playerNum, colour.r, colour.g, colour.b, colour.a)
            object:setOutlineHlAttached(record.playerNum, false)
            object:setOutlineHighlightCol(record.playerNum, colour.r, colour.g, colour.b, colour.a)
            record.colour = object:getOutlineHighlightCol(record.playerNum)
            local actual = object:getHighlightColor(record.playerNum)
            record.modelColour = { r = actual:getR(), g = actual:getG(), b = actual:getB(), a = actual:getA() }
            record.attached = object:isOutlineHlAttached(record.playerNum)
            record.requestedColour = { r = colour.r, g = colour.g, b = colour.b, a = colour.a }
            record.owned = true
        end
        return true
    end)
    if not ok then reportError(valid) end
    if ok and valid then record.refreshEpoch = refreshEpoch end
    return ok and valid
end

local function visit(object, context)
    if not object then return end
    local existing = byObject[object]
    if existing then
        -- Maintenance already read this object in this exact tick. Visibility and
        -- ownership are still rechecked on the next tick, even without movement.
        if existing.refreshEpoch == refreshEpoch then return end
        if not refresh(existing, context) then forget(existing.index) end
        return
    end
    local record = { object = object, playerNum = context.playerNum, owned = false }
    if refresh(record, context) then
        record.index = #tracked + 1
        tracked[record.index] = record
        byObject[object] = record
    end
end

local function prune(context)
    local count = math.min(ITEM_BUDGET, #tracked)
    for _ = 1, count do
        if #tracked == 0 then break end
        if cursor > #tracked then cursor = 1 end
        if refresh(tracked[cursor], context) then
            cursor = cursor + 1
        else
            forget(cursor)
        end
    end
end

local function beginScan(context)
    local offsets = offsetsByRadius[context.radius]
    if not offsets then
        offsets = {}
        for dy = -context.radius, context.radius do
            for dx = -context.radius, context.radius do
                offsets[#offsets + 1] = { x = dx, y = dy, distance = dx * dx + dy * dy }
            end
        end
        table.sort(offsets, function(a, b)
            if a.distance ~= b.distance then return a.distance < b.distance end
            if a.y ~= b.y then return a.y < b.y end
            return a.x < b.x
        end)
        offsetsByRadius[context.radius] = offsets
    end
    scan = {
        offsets = offsets, offsetIndex = 1,
        z = context.z,
        centerX = math.floor(context.x),
        centerY = math.floor(context.y),
        pending = {}, pendingIndex = 1, bySquare = {},
    }
end

local function visitSlice(entry, context, budget)
    local square = entry.square
    if context.cell:getGridSquare(square:getX(), square:getY(), square:getZ()) ~= square then
        return 0, true
    end
    local objects = square:getWorldObjects()
    local processed = 0
    while entry.index < objects:size() and processed < math.min(SQUARE_SLICE, budget) do
        visit(objects:get(entry.index), context)
        entry.index = entry.index + 1
        processed = processed + 1
    end
    return processed, entry.index >= objects:size()
end

local function forgetSquare(entry)
    scan.bySquare[entry.square] = nil
    local last = scan.pending[#scan.pending]
    scan.pending[#scan.pending] = nil
    if entry.slot <= #scan.pending then
        scan.pending[entry.slot] = last
        last.slot = entry.slot
    end
end

local function visitSquare(square, context, budget, enqueue)
    local pending = scan.bySquare[square]
    local entry = pending or {square = square, index = 0}
    local processed, done = visitSlice(entry, context, budget)
    if pending and done then
        forgetSquare(entry)
    elseif not pending and not done and enqueue and #scan.pending < #scan.offsets then
        -- Only finite sweeps admit cursors; priority resumes existing ones.
        -- The cap also covers transient stale identities after square reloads.
        entry.x, entry.y = square:getX(), square:getY()
        entry.slot = #scan.pending + 1
        scan.pending[entry.slot], scan.bySquare[square] = entry, entry
    end
    return processed, done
end

local function scanTick(context)
    local squares, items = 0, 0
    if context.moved then
        local x, y = math.floor(context.x), math.floor(context.y)
        -- Keep nearby discovery prompt without restarting the fair sweep.
        -- Reserve most item work and half the square work for its progress.
        for index = 1, SQUARE_BUDGET / 2 do
            local offset = scan.offsets[index]
            local square = context.cell:getGridSquare(x + offset.x, y + offset.y, context.z)
            squares = squares + 1
            if square then items = items + visitSquare(square, context, SQUARE_SLICE - items, false) end
            if items >= SQUARE_SLICE then break end
        end
    end
    -- Reserve half the item budget for dense squares, so neither discovery nor piles starve.
    while squares < SQUARE_BUDGET and items < ITEM_BUDGET / 2
        and scan.offsetIndex <= #scan.offsets do
        local offset = scan.offsets[scan.offsetIndex]
        scan.offsetIndex = scan.offsetIndex + 1
        squares = squares + 1
        local square = context.cell:getGridSquare(scan.centerX + offset.x, scan.centerY + offset.y, scan.z)
        if square then
            items = items + visitSquare(square, context, ITEM_BUDGET / 2 - items, true)
        end
    end
    local pendingSquares = 0
    while items < ITEM_BUDGET and #scan.pending > 0 and pendingSquares < SQUARE_BUDGET do
        if scan.pendingIndex > #scan.pending then scan.pendingIndex = 1 end
        local index = scan.pendingIndex
        local processed, done = visitSquare(scan.pending[index].square, context, ITEM_BUDGET - items, true)
        items, pendingSquares = items + processed, pendingSquares + 1
        if not done then scan.pendingIndex = index + 1 end
    end
    if scan.offsetIndex > #scan.offsets then
        local x, y = math.floor(context.x), math.floor(context.y)
        if x ~= scan.centerX or y ~= scan.centerY then
            -- A fresh area must not wait for every old item. Retain cursors
            -- in the new sweep's square lattice, exactly its discovery domain.
            -- Native world offsets are not clamped to a tile, so a circle/tile
            -- test would incorrectly skip displaced but eligible world items.
            -- At most #offsets cached-coordinate checks occur once per sweep.
            for index = #scan.pending, 1, -1 do
                local entry = scan.pending[index]
                if math.abs(entry.x - x) > context.radius or math.abs(entry.y - y) > context.radius then
                    forgetSquare(entry)
                end
            end
            scan.centerX, scan.centerY, scan.offsetIndex = x, y, 1
        elseif #scan.pending == 0 then
            scan = nil
            nextScanAt = getTimestampMs() + REFRESH_MS
        end
    end
end

local function tick()
    if clearing then return end
    local player = getPlayer()
    local cell = getCell()
    local normalEnabled = Toolkit.Settings.isEnabled()
    local wishlist = PZSurvivorWishlist
    local wantedEnabled = player and wishlist and wishlist.Client and wishlist.Settings
        and wishlist.Settings.groundEnabled() and wishlist.Client.hasWanted(player:getPlayerNum())
    if (not normalEnabled and not wantedEnabled) or not player or player:isDead() or not cell then
        if #tracked > 0 or scan or previous then Highlighter.clear() end
        return
    end
    local context = {
        playerNum = player:getPlayerNum(),
        x = player:getX(), y = player:getY(), z = math.floor(player:getZ()),
        normalEnabled = normalEnabled, normalRadius = Toolkit.Settings.getRadius(),
        normalColour = Toolkit.Settings.getColor(), cell = cell,
        wishlist = wantedEnabled and wishlist.Client,
        wantedColour = wantedEnabled and wishlist.Settings.color(),
    }
    context.radius = math.max(normalEnabled and context.normalRadius or 0, wantedEnabled and 15 or 0)
    if previous and context.radius ~= previous.radius then
        scan, nextScanAt = nil, 0
    end
    if previous then
        local dx, dy = context.x - previous.x, context.y - previous.y
        if context.playerNum ~= previous.playerNum or context.z ~= previous.z
            or cell ~= previous.cell or dx * dx + dy * dy > context.radius * context.radius then
            Highlighter.clear()
        end
    end
    local moved = previous and (math.floor(context.x) ~= math.floor(previous.x)
        or math.floor(context.y) ~= math.floor(previous.y))
    -- Finish the bounded sweep and its dense-square cursors across ordinary
    -- movement. New sweeps start at the current position; writes always use
    -- current eligibility, including during the nearby priority pass.
    if moved then nextScanAt = 0 end
    context.moved = moved
    previous = context
    if clearing then return end
    refreshEpoch = refreshEpoch + 1
    prune(context)
    if not scan and (moved or getTimestampMs() >= nextScanAt) then beginScan(context) end
    if scan then scanTick(context) end
end

local function onTick()
    local ok, errorMessage = pcall(tick)
    if not ok then
        reportError(errorMessage)
        Highlighter.clear()
    end
end

function Highlighter.getStatus()
    return { highlightedObjects = #tracked, scanning = scan ~= nil, clearing = clearing, lastError = lastError,
        pendingSquares = scan and #scan.pending or 0 }
end

Events.OnTick.Add(onTick)
Events.OnGameStart.Add(Highlighter.clear)
Events.OnPlayerDeath.Add(Highlighter.clear)
Events.OnMainMenuEnter.Add(Highlighter.clear)
Events.OnTickEvenPaused.Add(function() if clearing then clearBatch() end end)
