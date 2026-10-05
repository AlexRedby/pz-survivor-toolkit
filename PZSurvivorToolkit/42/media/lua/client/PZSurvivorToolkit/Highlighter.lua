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
local cursor = 1
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
    return dx * dx + dy * dy <= context.radius * context.radius
end

local function refresh(record, context)
    local ok, valid = pcall(function()
        local object = record.object
        if not eligible(object, context) then return false end
        if object:isOutlineHighlight(record.playerNum) or object:isHighlighted(record.playerNum) then
            if record.owned and not sameHighlight(record) then record.owned = false end
        else
            local colour = context.colour
            -- The world-item override sets the vanilla colour and outline, so colour comes last.
            object:setHighlighted(record.playerNum, true, false)
            object:setHighlightColor(record.playerNum, colour.r, colour.g, colour.b, colour.a)
            object:setOutlineHlAttached(record.playerNum, false)
            object:setOutlineHighlightCol(record.playerNum, colour.r, colour.g, colour.b, colour.a)
            record.colour = object:getOutlineHighlightCol(record.playerNum)
            local actual = object:getHighlightColor(record.playerNum)
            record.modelColour = { r = actual:getR(), g = actual:getG(), b = actual:getB(), a = actual:getA() }
            record.attached = object:isOutlineHlAttached(record.playerNum)
            record.owned = true
        end
        return true
    end)
    if not ok then reportError(valid) end
    return ok and valid
end

local function visit(object, context)
    if not object then return end
    local existing = byObject[object]
    if existing then
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
        pending = {}, pendingIndex = 1,
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

local function scanTick(context)
    local squares, items = 0, 0
    -- Reserve half the item budget for dense squares, so neither discovery nor piles starve.
    while squares < SQUARE_BUDGET and items < ITEM_BUDGET / 2
        and scan.offsetIndex <= #scan.offsets do
        local offset = scan.offsets[scan.offsetIndex]
        scan.offsetIndex = scan.offsetIndex + 1
        squares = squares + 1
        local square = context.cell:getGridSquare(scan.centerX + offset.x, scan.centerY + offset.y, scan.z)
        if square then
            local entry = { square = square, index = 0 }
            local processed, done = visitSlice(entry, context, ITEM_BUDGET / 2 - items)
            items = items + processed
            if not done then scan.pending[#scan.pending + 1] = entry end
        end
    end
    local pendingSquares = 0
    while items < ITEM_BUDGET and #scan.pending > 0 and pendingSquares < SQUARE_BUDGET do
        if scan.pendingIndex > #scan.pending then scan.pendingIndex = 1 end
        local index = scan.pendingIndex
        local processed, done = visitSlice(scan.pending[index], context, ITEM_BUDGET - items)
        items, pendingSquares = items + processed, pendingSquares + 1
        if done then
            scan.pending[index] = scan.pending[#scan.pending]
            scan.pending[#scan.pending] = nil
        else
            scan.pendingIndex = index + 1
        end
    end
    if scan.offsetIndex > #scan.offsets and #scan.pending == 0 then
        scan = nil
        nextScanAt = getTimestampMs() + REFRESH_MS
    end
end

local function tick()
    if clearing then return end
    local player = getPlayer()
    local cell = getCell()
    if not Toolkit.Settings.isEnabled() or not player or player:isDead() or not cell then
        if #tracked > 0 or scan or previous then Highlighter.clear() end
        return
    end
    local context = {
        playerNum = player:getPlayerNum(),
        x = player:getX(), y = player:getY(), z = math.floor(player:getZ()),
        radius = Toolkit.Settings.getRadius(), colour = Toolkit.Settings.getColor(), cell = cell,
    }
    if previous then
        local dx, dy = context.x - previous.x, context.y - previous.y
        if context.playerNum ~= previous.playerNum or context.z ~= previous.z
            or cell ~= previous.cell or dx * dx + dy * dy > context.radius * context.radius then
            Highlighter.clear()
        end
    end
    local moved = previous and (math.floor(context.x) ~= math.floor(previous.x)
        or math.floor(context.y) ~= math.floor(previous.y))
    if moved then scan, nextScanAt = nil, 0 end
    previous = context
    if clearing then return end
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
    return { highlightedObjects = #tracked, scanning = scan ~= nil, clearing = clearing, lastError = lastError }
end

Events.OnTick.Add(onTick)
Events.OnGameStart.Add(Highlighter.clear)
Events.OnPlayerDeath.Add(Highlighter.clear)
Events.OnMainMenuEnter.Add(Highlighter.clear)
Events.OnTickEvenPaused.Add(function() if clearing then clearBatch() end end)
