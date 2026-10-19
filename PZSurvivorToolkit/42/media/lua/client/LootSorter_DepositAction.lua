-- LootSorter: resilient deposit action.
--
-- WHY THIS EXISTS: a distribute queues one transfer per item across several boxes. If a box fills
-- up, vanilla ISInventoryTransferAction:isValid() returns false (its final "hasRoomFor" branch) when
-- that deposit's turn comes. The engine then CANCELS the running action, and a cancel runs
-- ISBaseTimedAction:stop() -> ISTimedActionQueue:resetQueue(), which WIPES every remaining action --
-- including walks/deposits to OTHER boxes that still have room. The character just stops mid-sort.
-- (Seen in the wild: the nearest partly-full box couldn't take one item and the ENTIRE rest of the
-- sort -- empty boxes included -- was silently dropped.)
--
-- THE FIX: never return false from isValid() (returning false is exactly what triggers the wipe).
-- We stay "valid" and decide at start() whether the box can really take the item: if not, we mark
-- this one deposit as a no-op and let the queue march on to the next box. transferItem() does NOT
-- re-check capacity, so we must gate BEFORE it runs -- otherwise a forced transfer would overfill
-- the box past its capacity.
require "TimedActions/ISInventoryTransferAction"

LootSorter = LootSorter or {}
-- DBG / isDebug / describeContainer live in shared/LootSorter_Debug.lua; safeCall in LootSorter_Util.lua

LootSorter.DepositAction = ISInventoryTransferAction:derive("LootSorterDeposit")

function LootSorter.DepositAction:new(character, item, srcContainer, destContainer)
    local o = ISInventoryTransferAction.new(self, character, item, srcContainer, destContainer)
    -- A haul first LOADS items into a carrier (vehicle/box -> bag), then UNLOADS them (bag -> box). If a
    -- load is skipped because the bag is full, the item never enters the bag -- but the paired unload is
    -- still queued against it. Vanilla merges consecutive same-src->same-dest transfers into one action;
    -- when that action's perform() reaches the missing item, update() (ISInventoryTransferAction ~line
    -- 173) hits `not srcContainer:contains(item)` and calls forceStop() -> resetQueue(), WIPING every
    -- remaining action -- the whole rest of the haul. allowMissingItems is vanilla's own flag for exactly
    -- this (it's how crafting-ingredient return tolerates a vanished source item): a missing source item
    -- is skipped gracefully (time=0, no-op) instead of failing. Merging (and its perf) is preserved.
    o.allowMissingItems = true
    return o
end

-- The real vanilla check (item exists, container reachable, box has room, item allowed, ...).
function LootSorter.DepositAction:lsCanDeposit()
    local ok, valid = pcall(function() return ISInventoryTransferAction.isValid(self) end)
    return ok and valid == true
end

-- Vanilla's isValid() bundles many conditions into one true/false, so a skip only ever told us "(full?)"
-- -- a guess. This calls each condition on its own -- including the ones a naive check misses: container
-- REACHABILITY (getContainers -- a source the character walked away from drops out), isExistYet, and
-- whether isValid() itself THREW (our lsCanDeposit pcall then returns false). So a skip whose obvious
-- conditions all pass is still explained.
function LootSorter.DepositAction:lsDiagnose()
    local sc, dc, it, ch = self.srcContainer, self.destContainer, self.item, self.character
    local srcContains   = LootSorter.safeCall(function() return sc:contains(it) end, "?")
    local hasRoom       = LootSorter.safeCall(function() return dc:hasRoomFor(ch, it) end, "?")
    local destAllowed   = LootSorter.safeCall(function() return dc:isItemAllowed(it) end, "?")
    local removeAllowed = LootSorter.safeCall(function() return sc:isRemoveItemAllowed(it) end, "?")
    local curContainer  = LootSorter.safeCall(function() return it:getContainer() end, nil)
    local matchesSrc    = (curContainer == sc)
    local capW = LootSorter.safeCall(function() return dc:getCapacityWeight() end, -1)
    local cap  = LootSorter.safeCall(function() return dc:getCapacity() end, -1)
    local iw   = LootSorter.safeCall(function() return it:getActualWeight() end, -1)
    local destWhat = LootSorter.describeContainer(dc)
    local srcAcc, destAcc = "?", "?"
    LootSorter.safeCall(function()
        local conts = ISInventoryPaneContextMenu.getContainers(ch)
        srcAcc  = conts and conts:contains(sc) or false
        destAcc = conts and conts:contains(dc) or false
    end)
    local srcExists  = LootSorter.safeCall(function() return sc:isExistYet() end, "?")
    local destExists = LootSorter.safeCall(function() return dc:isExistYet() end, "?")
    local vok, vret = pcall(function() return ISInventoryTransferAction.isValid(self) end)
    return ("dest=%s srcContains=%s hasRoomFor=%s destItemAllowed=%s srcRemoveAllowed=%s itemContainerMatchesSrc=%s destCap=%.2f/%.2f itemW=%.2f srcReachable=%s destReachable=%s srcExists=%s destExists=%s isValid=%s/%s")
        :format(destWhat, tostring(srcContains), tostring(hasRoom), tostring(destAllowed), tostring(removeAllowed),
                tostring(matchesSrc), tonumber(capW) or -1, tonumber(cap) or -1, tonumber(iw) or -1,
                tostring(srcAcc), tostring(destAcc), tostring(srcExists), tostring(destExists),
                tostring(vok), tostring(vret))
end

-- NEVER false: a false here cancels the action -> stop() -> resetQueue() -> the whole sort is wiped.
function LootSorter.DepositAction:isValid()
    return true
end

function LootSorter.DepositAction:start()
    -- gate the WHOLE block, not just the print: getName + two LootSorter.describeContainer() calls (several engine
    -- calls each) run on EVERY deposit, so leaving them ungated would cost real work per item in a
    -- release build for a line that never prints. Logs every attempt so a mid-sort silence names the
    -- item/from/to in flight the moment it stopped.
    if LootSorter.isDebug() then
        local nm = "?"; pcall(function() nm = self.item and self.item:getName() end)
        local fromWhat = LootSorter.safeCall(function() return LootSorter.describeContainer(self.srcContainer) end, "?")
        local toWhat   = LootSorter.safeCall(function() return LootSorter.describeContainer(self.destContainer) end, "?")
        LootSorter.DBG(("run #%s DepositAction:start #%s (%s) item='%s' from=%s to=%s"):format(
            tostring(self.lsRunId or "?"), tostring(self.lsSeq or "?"), tostring(self.lsPhase or "?"), tostring(nm), fromWhat, toWhat))
    end
    if not self:lsCanDeposit() then
        -- box can't take this item right now (full / unreachable). Skip it WITHOUT killing the queue,
        -- so the remaining boxes still get serviced. The item simply stays where it is (a leftover).
        self._lsSkip = true
        if LootSorter.isDebug() then   -- lsDiagnose is ~10 engine calls; only when logging
            local nm = "?"; pcall(function() nm = self.item and self.item:getName() end)
            local diag = LootSorter.safeCall(function() return self:lsDiagnose() end, "diagnose failed")
            LootSorter.DBG(("run #%s deposit skipped: box rejected '%s' -- %s; continuing to next box"):format(
                tostring(self.lsRunId or "?"), tostring(nm), diag))
        end
        pcall(function() self.action:setTime(0) end)   -- finish instantly, no transfer animation
        return
    end
    ISInventoryTransferAction.start(self)
end

function LootSorter.DepositAction:perform()
    if self._lsSkip then
        ISBaseTimedAction.perform(self)                 -- advance the queue; move nothing
        return
    end
    ISInventoryTransferAction.perform(self)
end

-- DIAGNOSTIC: a log to catch this deposit exiting prematurely -- if it's force-stopped mid-sort, that
-- wipes the rest of the haul. Names the item/from/to. Gated: the describeContainer calls aren't free.
function LootSorter.DepositAction:stop()
    if LootSorter.isDebug() then
        local nm = "?"; pcall(function() nm = self.item and self.item:getName() end)
        local fromWhat = LootSorter.safeCall(function() return LootSorter.describeContainer(self.srcContainer) end, "?")
        local toWhat   = LootSorter.safeCall(function() return LootSorter.describeContainer(self.destContainer) end, "?")
        local present  = LootSorter.safeCall(function() return self.srcContainer:contains(self.item) end, "?")
        LootSorter.DBG(("run #%s DepositAction:stop #%s (%s) item='%s' from=%s to=%s srcContainsItem=%s -- FORCE-STOPPED (queue wipe imminent)"):format(
            tostring(self.lsRunId or "?"), tostring(self.lsSeq or "?"), tostring(self.lsPhase or "?"),
            tostring(nm), fromWhat, toWhat, tostring(present)))
    end
    ISInventoryTransferAction.stop(self)
end
