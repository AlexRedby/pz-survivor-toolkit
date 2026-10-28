require "LootSorter_Rpc"
local Model = require "PZSurvivorToolkit/ManifestModel"
-- SP runs the identical server function inline. Remote clients never open world ModData.
if not isClient() then require "PZSurvivorToolkit/ManifestAuthority" end
local Client = {}
PZSurvivorToolkit.ManifestClient = Client
local state, listeners, callbacks, pending, inFlight, player, epoch, nextAt
local function reset()
    epoch = (epoch or 0) + 1
    state, listeners, callbacks = {status = "idle"}, {}, {}
    pending, inFlight, player, nextAt = nil, false, nil, 0
end
reset()
local function resolve(selected)
    if type(selected) == "number" then return getSpecificPlayer(selected) end
    return selected or (getSpecificPlayer and getSpecificPlayer(0))
end
local function invoke(callback, payload, status)
    local ok, err = pcall(callback, payload, status)
    if not ok then print("[PZSurvivorToolkit] Manifest callback: " .. tostring(err)) end
end
local function emit()
    for _, listener in pairs(listeners) do invoke(listener, state.payload, state.status) end
end
local function finish(status, error)
    nextAt = getTimestampMs() + Model.POLL_MS
    state.status, state.error = status, error
    emit()
    local waiting = callbacks
    callbacks = {}
    for _, callback in ipairs(waiting) do invoke(callback, state.payload, state.status) end
end
function Client.getState(_) return state end
local function sendPage()
    if inFlight or not pending then return end
    local generation, request = epoch, pending
    local args = {revision = request.revision, cursor = request.cursor}
    inFlight = true -- before callServer: SP invokes this callback before returning
    LootSorter.callServer("manifestPage", args, function(verdict, detail)
        if epoch ~= generation or pending ~= request then return end
        inFlight = false
        if verdict == "stale" and request.samples then
            -- Content changed while freshness pages were in flight. Keep the visible cache and
            -- request full data on the next tick, without showing a spurious connection error.
            pending = {}
            return
        end
        if verdict ~= "ok" or type(detail) ~= "table" or detail.schema ~= Model.SCHEMA then
            pending = nil
            finish("error", verdict or "timeout")
            return
        end
        if detail.unchanged then
            if not state.payload or request.payload or detail.revision ~= request.revision
                or detail.revision ~= state.payload.revision then
                pending = nil; finish("error", "invalidFreshness"); return
            end
            if detail.samples ~= nil and type(detail.samples) ~= "table" then
                pending = nil; finish("error", "invalidFreshness"); return
            end
            request.samples = request.samples or {}
            for id, sampledAt in pairs(detail.samples or {}) do
                if type(id) ~= "string" or type(sampledAt) ~= "number" or sampledAt ~= sampledAt
                    or sampledAt < 0 or sampledAt == math.huge then
                    pending = nil; finish("error", "invalidFreshness"); return
                end
                request.samples[id] = sampledAt
            end
            request.cursor = detail.cursor
            if not detail.cursor then
                for id, sampledAt in pairs(request.samples) do
                    local record = state.payload.containers[id]
                    if record then record.sampledAt = sampledAt end
                end
                pending = nil
                finish("ready")
            end
            return
        end
        if request.samples then pending = nil; finish("error", "mixedFreshness"); return end
        request.payload = request.payload or {schema = Model.SCHEMA, revision = detail.revision, containers = {}}
        for _, part in ipairs(detail.containers or {}) do
            local record = request.payload.containers[part.id]
            if not record then record = part; request.payload.containers[part.id] = record
            else for key, entry in pairs(part.entries or {}) do record.entries[key] = entry end end
        end
        request.cursor = detail.cursor
        if not detail.cursor then
            state.payload, pending = request.payload, nil
            finish("ready")
        end
        -- Continuations wait for OnTick, including SP: a large ledger cannot recurse through all pages.
    end, player)
end
function Client.refresh(selected, callback)
    selected = resolve(selected)
    if callback then callbacks[#callbacks + 1] = callback end
    if pending then return end
    if not selected then finish("error", "noPlayer"); return end
    player = selected
    pending = {revision = state.payload and state.payload.revision}
    state.status, state.error = "loading", nil
    emit()
    nextAt = getTimestampMs() + Model.POLL_MS
    sendPage()
end
function Client.open(selected, onChange)
    selected = resolve(selected)
    if not selected then return end
    listeners[selected] = onChange or function() end
    if state.payload then invoke(listeners[selected], state.payload, state.status) end
    Client.refresh(selected)
end
function Client.close(selected)
    selected = resolve(selected)
    if selected then listeners[selected] = nil end
    local active = false
    for _ in pairs(listeners) do active = true; break end
    if not active and #callbacks == 0 then
        -- Ignore the already transmitted page, and never ask for its continuation after closing.
        epoch, pending, inFlight, player = epoch + 1, nil, false, nil
        state.status, state.error = state.payload and "ready" or "idle", nil
    end
end
LootSorter.addOrReplaceHandler(Events.OnTick, "_manifestClientTick", function()
    if pending then sendPage(); return end
    if getTimestampMs() < nextAt then return end
    for selected in pairs(listeners) do Client.refresh(selected); break end
end)
LootSorter.addOrReplaceHandler(Events.OnGameStart, "_manifestClientStart", reset)
return Client
