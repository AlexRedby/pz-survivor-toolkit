-- Running server-owned work from either side.
--
-- serverFn defines the work and returns the way to reach it, so a command is one statement:
--
--     LootSorter.removePreset = LootSorter.serverFn("removePreset", function(player, args) ... end)
--     LootSorter.removePreset({ name = name }, function(verdict) ... end)
--
-- Where we own the data it runs inline; on a multiplayer client it goes out as a command and the
-- answer comes back later. No caller has to know which mode it is in.
--
-- Arguments travel as one table because they cross a wire. A mistyped key arrives as nil rather than
-- erroring, so validate inside the function -- the side that must not trust them anyway.
--
-- The callback runs DURING the call where we are authoritative and on a later frame where we are
-- not, so code after callServer runs before the callback in multiplayer and after it in
-- single-player. Do the work in the callback, not around it.
-- Both called at file scope below, and both sort AFTER this file in shared/ -- boot order is
-- alphabetical, so without these requires the registrations below run against nil.
require "LootSorter_Authority"      -- isAuthority
require "LootSorter_Util"           -- addOrReplaceHandler
LootSorter = LootSorter or {}

local COMMAND_MODULE = "Quartermaster"
local RESULT_COMMAND = "rpcResult"

LootSorter.serverFns = LootSorter.serverFns or {}

-- fn(player, args) -> verdict, detail
--   verdict: "ok" on success, anything else is a refusal the caller can act on
--   detail:  optional result table, passed to the callback with the verdict
-- Returns the caller, so the work and the way to invoke it are one declaration instead of two that
-- have to be kept in step.
function LootSorter.serverFn(name, fn)
    LootSorter.serverFns[name] = fn
    return function(args, onDone, player) LootSorter.callServer(name, args, onDone, player) end
end

-- Callbacks waiting on an answer, keyed by a token that rides out with the command and back with the
-- reply. Without it two writes in flight could not tell whose answer had arrived.
-- Reset rather than preserved on load: nextToken restarts at 0, so keeping old entries would let a
-- fresh token match a stale one and fire the wrong callback. In-flight closures reference code that
-- has just been replaced anyway.
LootSorter._rpcPending = {}
local nextToken = 0

-- UI callers can supply their player; existing callers use the primary local player.
function LootSorter.callServer(name, args, onDone, player)
    player = player or getSpecificPlayer(0)

    if LootSorter.isAuthority() then
        local fn = LootSorter.serverFns[name]
        if not fn then if onDone then onDone(nil) end return end
        local verdict, detail = fn(player, args)
        if onDone then onDone(verdict, detail) end
        return
    end

    if not player then if onDone then onDone(nil) end return end
    -- Tokens belong to this request, never to a caller's retained draft or reusable arguments.
    local packet = {}
    for key, value in pairs(args or {}) do packet[key] = value end
    packet.rpcToken = nil
    if onDone then
        nextToken = nextToken + 1
        packet.rpcToken = nextToken
        LootSorter._rpcPending[nextToken] = { onDone = onDone, sentAt = getTimestampMs() }
    end
    pcall(function() sendClientCommand(player, COMMAND_MODULE, name, packet) end)
end

-- Authoritative side: run the function and answer. Answers on success too -- a reply that only came
-- back on failure would leave every successful write's callback hanging forever.
if LootSorter.isAuthority() then
    LootSorter.addOrReplaceHandler(Events.OnClientCommand, "_rpcDispatch",
        function(module, command, player, args)
            if module ~= COMMAND_MODULE then return end
            local token = args and args.rpcToken
            local fn = LootSorter.serverFns[command]
            -- Answer even when the command is unknown to us. Staying silent would leave the caller's
            -- callback pending forever, holding whatever its closure captured.
            local verdict, detail
            if fn then verdict, detail = fn(player, args) end
            if token and player then
                pcall(function()
                    sendServerCommand(player, COMMAND_MODULE, RESULT_COMMAND,
                        { rpcToken = token, verdict = verdict, detail = detail })
                end)
            end
        end)
end

-- Client side: match an answer back to whoever asked for it.
LootSorter.addOrReplaceHandler(Events.OnServerCommand, "_rpcResult", function(module, command, args)
    if module ~= COMMAND_MODULE or command ~= RESULT_COMMAND then return end
    local token = args and args.rpcToken
    local waiting = token and LootSorter._rpcPending[token]
    if not waiting then return end
    LootSorter._rpcPending[token] = nil
    waiting.onDone(args.verdict, args.detail)
end)

-- A login starts a fresh conversation; anything still waiting belongs to the last one.
LootSorter.addOrReplaceHandler(Events.OnGameStart, "_rpcOnGameStart",
    function() LootSorter._rpcPending = {} end)

-- Give up on an answer that is never coming. Not about lost packets -- the transport retransmits --
-- but about a reply that structurally cannot arrive: a server without this module has no dispatcher
-- to answer with, so every call would wait forever holding whatever its closure captured.
-- The callback still runs, with nil, so the caller learns it will never know rather than hanging.
local nextSweepAt = 0

if not LootSorter.isAuthority() then
    LootSorter.addOrReplaceHandler(Events.OnTick, "_rpcSweep", function()
        local now = getTimestampMs()
        if now < nextSweepAt then return end
        nextSweepAt = now + LootSorter.RPC_SWEEP_MS
        local expired
        for token, waiting in pairs(LootSorter._rpcPending) do
            if now - waiting.sentAt > LootSorter.RPC_TIMEOUT_MS then
                expired = expired or {}
                expired[#expired + 1] = token
            end
        end
        if not expired then return end
        -- collected first: calling back while iterating lets a callback issue a new call and mutate
        -- the table we are walking
        for _, token in ipairs(expired) do
            local waiting = LootSorter._rpcPending[token]
            LootSorter._rpcPending[token] = nil
            if waiting then
                LootSorter.DBG("rpc: no answer for token " .. tostring(token) .. ", giving up")
                pcall(waiting.onDone, nil)
            end
        end
    end)
end
