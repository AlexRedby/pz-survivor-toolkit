-- LootSorter: haul walk action -- fast transfers, safe walking.
-- Vanilla ISWalkToTimedAction cancels itself when game speed > tier 2 (isValid). This variant
-- overrides that (so a walk never cancels at high speed), throttles the walk to tier 2, and
-- restores the player's chosen speed when the walk ends.
--
-- THE FIX: after a floor change mid-walk the engine drops the throttled speed to normal, so the
-- character crawls the rest of the way. While a walk is throttled we re-assert tier 2 every tick
-- if the engine knocks it below. We touch speed ONLY during our throttled walks -- between trips
-- the per-walk restore holds, and the end-of-haul reset to normal is deliberately left alone.
--
-- Speed/floor logging gated behind LootSorter.DEBUG (or -debug); remove before release.
require "TimedActions/WalkToTimedAction"

LootSorter = LootSorter or {}


local function spd()
    local lvl, mult = -1, -1
    pcall(function() lvl = getGameSpeed(); mult = getGameTime():getTrueMultiplier() end)
    return lvl, mult
end
local function zOf(char)
    local z = "?"
    pcall(function() local sq = char and char:getCurrentSquare(); if sq then z = sq:getZ() end end)
    return z
end
-- "leg 5/15" if this walk was tagged by sort()'s queueWalk(), else "leg ?/?" (untagged/old instance)
local function legStr(self)
    local total = LootSorter._sortProgress and LootSorter._sortProgress.total
    return ("run %s leg %s/%s"):format(tostring(self.lsRunId or "?"), tostring(self.lsLegIndex or "?"), tostring(total or "?"))
end

local lastSpeed, lastZ = -99, -99
-- rebound each reload so edits to this closure apply (a boolean guard alone would keep running the
-- FIRST load's closure forever).
LootSorter.addOrReplaceHandler(Events.OnTick, "_onSpeedProbe",
    function()
        -- Hold the walk at tier 2 while throttled. Only active during our throttled walks, so the
        -- end-of-haul reset (and everything else) is untouched.
        if LootSorter._throttling then
            pcall(function()
                local s = getGameSpeed()
                if s > 2 then
                    -- speed raised above tier 2 DURING a walk (you cranked it up mid-walk) -> remember
                    -- it as your preferred speed and cap the walk to tier 2
                    LootSorter._lsDesired = s
                    LootSorter._lsDesiredMult = getGameTime():getTrueMultiplier()
                    setGameSpeed(2)
                    getGameTime():setMultiplier(5)
                elseif s == 1 and LootSorter._lsDesired then
                    -- a floor change reset us to normal mid-haul while fast-forwarding -> hold tier 2.
                    -- gated on a saved preference so an un-sped walk (and pause = 0) are left alone
                    setGameSpeed(2)
                    getGameTime():setMultiplier(5)
                end
            end)
        end
        -- WATCHDOG: if a sort armed the progress tracker (queued at least one walk) and the queue drains
        -- before the last leg's perform() ever fires, something outside our control ended it early
        -- (manual movement, a right-click menu -- all clear PZ's action queue). Catches BOTH a walk
        -- interrupted mid-stride AND future legs simply removed from the queue (which get no callback) --
        -- either way, "queue empty but not marked complete" is the proof.
        -- isDebug-gated too (not just the DBG inside): the block's ONLY effect is a debug log, so in a
        -- release build there's nothing to detect -- skip the per-tick getSpecificPlayer/queue probe.
        if LootSorter.isDebug() and LootSorter._sortProgress then
            pcall(function()
                local player = getSpecificPlayer(0)
                local actionQueue = player and ISTimedActionQueue.queues and ISTimedActionQueue.queues[player]
                if (not actionQueue) or (not actionQueue.queue) or #actionQueue.queue == 0 then
                    LootSorter.DBG(("run #%d sort interrupted: queue emptied before finishing (expected %d leg(s) total)")
                        :format(LootSorter._sortProgress.runId, LootSorter._sortProgress.total))
                    LootSorter._sortProgress = nil
                end
            end)
        end
        -- DEBUG change-logger
        if LootSorter.isDebug() then
            local lvl, mult = spd()
            local z = -1
            pcall(function() local player = getSpecificPlayer(0); local sq = player and player:getCurrentSquare(); if sq then z = sq:getZ() end end)
            if lvl ~= lastSpeed or z ~= lastZ then
                LootSorter.DBG(("  [dt] speed=%d mult=%.1f z=%d   (prev speed=%d z=%d)"):format(lvl, mult, z, lastSpeed, lastZ))
                lastSpeed, lastZ = lvl, z
            end
        end
    end)

-- Catch the wipe at its source: resetQueue() is what clears the queue (called from any action's
-- stop()/forceStop()), so log it during an active sort -- otherwise a wipe is just "queue emptied,
-- cause unknown". True-vanilla is stored ONCE so a hot-reload re-wraps from the original (no stacking);
-- gated on isDebug + _sortProgress, so it's a pure pass-through otherwise.
LootSorter._vanillaResetQueue = LootSorter._vanillaResetQueue or ISTimedActionQueue.resetQueue
function ISTimedActionQueue:resetQueue(...)
    if LootSorter.isDebug() and LootSorter._sortProgress then
        pcall(function()
            local pending = (self.queue and #self.queue) or -1
            -- NB: no debug.traceback() here -- PZ's Kahlua has no `debug` table, so calling it throws
            -- (caught, but still dumped to console). The DepositAction:stop line logged immediately
            -- before this IS the trigger; that identifies the phantom deposit that forced the wipe.
            LootSorter.DBG(("run #%s resetQueue: %d queued action(s) about to be WIPED (trigger = the DepositAction:stop just above)"):format(
                tostring(LootSorter._sortProgress.runId), pending))
        end)
    end
    return LootSorter._vanillaResetQueue(self, ...)
end

LootSorter.WalkAction = ISWalkToTimedAction:derive("LootSorterWalkAction")

function LootSorter.WalkAction:isValid()
    -- a false here cancels the walk -> resetQueue() -> the whole remaining sort is WIPED; log it so a
    -- mid-haul stall right as a walk begins is traceable to the character being considered in a vehicle
    if self.character:getVehicle() then
        LootSorter.DBG("WalkAction:isValid FALSE -- character in vehicle; walk cancels -> queue wipe")
        return false
    end
    return true   -- drop vanilla's "getGameSpeed() <= 2" so a high speed no longer aborts the walk
end

function LootSorter.WalkAction:lsRestoreSpeed(where)
    LootSorter._throttling = false                   -- stop capping once the walk ends
    local lvl, mult = spd()
    if not LootSorter._lsDesired then
        LootSorter.DBG(("WalkAction:%s %s z=%s  restore SKIPPED (no fast preference); speed now=%d mult=%.1f"):format(
            tostring(where), legStr(self), tostring(zOf(self.character)), lvl, mult))
        return
    end
    LootSorter.DBG(("WalkAction:%s %s z=%s  as-arrived speed=%d mult=%.1f  ->  restoring preference=%d mult=%.1f"):format(
        tostring(where), legStr(self), tostring(zOf(self.character)), lvl, mult, LootSorter._lsDesired, LootSorter._lsDesiredMult or -1))
    pcall(function()
        setGameSpeed(LootSorter._lsDesired)
        if LootSorter._lsDesiredMult then getGameTime():setMultiplier(LootSorter._lsDesiredMult) end
    end)
    LootSorter._lsDesired = nil
    LootSorter._lsDesiredMult = nil
end

function LootSorter.WalkAction:start()
    LootSorter._throttling = true                     -- cap for the WHOLE walk, so a mid-walk speed-up is capped too
    pcall(function()
        local lvl, mult = spd()
        LootSorter.DBG(("WalkAction:start %s z=%s  speed=%d mult=%.1f  -> %s"):format(
            legStr(self), tostring(zOf(self.character)), lvl, mult, (lvl > 2) and "throttling to 2/5" or "cap armed (<=2, no change yet)"))
        if lvl and lvl > 2 then                        -- already fast-forwarding: remember it and cap now
            LootSorter._lsDesired = lvl
            LootSorter._lsDesiredMult = mult
            setGameSpeed(2)
            getGameTime():setMultiplier(5)
        end
    end)
    ISWalkToTimedAction.start(self)
end

function LootSorter.WalkAction:perform()
    self:lsRestoreSpeed("perform")
    -- completion signal: only the LAST leg of the CURRENT run reaching perform() means the whole sort
    -- finished on its own; the watchdog in the OnTick probe above reports anything else.
    if self.lsRunId and LootSorter._sortProgress and self.lsRunId == LootSorter._sortProgress.runId
       and self.lsLegIndex == LootSorter._sortProgress.total then
        LootSorter.DBG(("run #%d sort complete: all %d leg(s) finished"):format(LootSorter._sortProgress.runId, LootSorter._sortProgress.total))
        LootSorter._sortProgress = nil
    end
    ISWalkToTimedAction.perform(self)
end

function LootSorter.WalkAction:stop()
    self:lsRestoreSpeed("stop")                      -- also covers cancel / forceStop / interruption
    ISWalkToTimedAction.stop(self)
end
