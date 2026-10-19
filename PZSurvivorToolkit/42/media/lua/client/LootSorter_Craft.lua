-- Quartermaster: craft-fetch engine.
-- Given a recipe + desired quantity, the character walks to the designated boxes that hold the
-- missing ingredients, hauls them into the main inventory, then crafts. Because it works on
-- world/inventory STATE (not on any crafting UI), it drives vanilla B42 and Neat Crafting alike --
-- both resolve craftability from the same accessible-container set, which our haul feeds.
--
-- The right-click hooks + quantity slider that call in here live in LootSorter_CraftMenu.lua.
-- Depends on LootSorter.gatherBoxes / WalkAction (Core + WalkAction) and these B42 craft APIs:
--   recipe:getInputs() -> input scripts; input:getResourceType()==ResourceType.Item; input:getIntAmount();
--   input:hasFlag(InputFlag.ToolLeft/ToolRight); CraftRecipeManager.getValidInputScriptForItem(recipe,item);
--   CraftRecipeManager.getAllItemsFromContainers(containers,list); ISInventoryPaneContextMenu.getContainers(player);
--   logic:getPossibleCraftCount(true); ISEntityUI.HandcraftStartMultiple(player,logic,force,qty,addToQueue).
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISInventoryTransferAction"
local Containers = require "PZSurvivorToolkit/QuartermasterCraftContainers"
local inventoryContainers, withoutCraftContainers = Containers.inventory, Containers.withoutContext

LootSorter = LootSorter or {}
LootSorter.craft = LootSorter.craft or {}


-- If our gather path errors and the UI hook falls back to a NORMAL craft, we must first make that
-- craft inventory-only: the logic already cached the box-including container set (that's why the
-- recipe lit up), so a plain fallback would consume the box-resident input in place = teleport.
-- Suppress availability injection for the whole re-pin, including input-resolution callbacks.
-- Re-pin the logic to ordinary containers and re-resolve inputs, as CraftTriggerAction:perform does.
function LootSorter.craft.repinInventoryOnly(logic, player)
    pcall(withoutCraftContainers, function()
        if logic and logic.setContainers then
            logic:setContainers(inventoryContainers(player))
            if logic.autoPopulateInputs then logic:autoPopulateInputs() end
        end
    end)
end

-- The recipe's consumable ITEM inputs (skips fluids / energy / other resource types).
-- Each entry: { input = inputScript, per = amount-needed-per-craft, tool = is-a-tool (kept, not consumed) }.
local function itemInputs(recipe)
    local out = {}
    local ok = pcall(function()
        local inputs = recipe:getInputs()
        for i = 0, inputs:size() - 1 do
            local inp = inputs:get(i)
            if inp:getResourceType() == ResourceType.Item then
                -- Vanilla marks a kept tool with `mode:keep` (isKeep) and leaves ToolLeft/ToolRight
                -- unset, so testing only the flags treated every tool as a consumable -- a batch of N
                -- crafts then fetched N of them. Flags kept as an OR in case a recipe does set them.
                local keep = false
                pcall(function() keep = inp:isKeep() == true end)
                local tool = keep or inp:hasFlag(InputFlag.ToolLeft) or inp:hasFlag(InputFlag.ToolRight)
                local per = inp:getIntAmount(); if not per or per < 1 then per = 1 end
                local io; pcall(function() io = recipe:getIndexForIO(inp) end)   -- stable numeric id (robust match)
                out[#out + 1] = { input = inp, per = per, tool = tool, io = io }
            end
        end
    end)
    if not ok then LootSorter.DBG("itemInputs: failed reading recipe inputs") end
    return out
end

-- Which of myInputs (by index) does this item satisfy? nil if none.
-- Matches the input the game reports (getValidInputScriptForItem) to our list by the recipe's stable
-- IO index (getIndexForIO) -- numeric, so it doesn't depend on Kahlua returning the same wrapper object
-- for the same input across calls. Falls back to wrapper identity only if getIndexForIO is unavailable.
local function inputIndexFor(recipe, myInputs, item, player)
    local matched
    pcall(function()
        local inp = CraftRecipeManager.getValidInputScriptForItem(recipe, item, player)
        if not inp then return end
        local io; pcall(function() io = recipe:getIndexForIO(inp) end)
        for idx, e in ipairs(myInputs) do
            local hit
            if io ~= nil and e.io ~= nil then hit = (e.io == io)   -- robust numeric match
            else hit = (e.input == inp) end                        -- fallback: wrapper identity
            if hit then matched = idx break end
        end
    end)
    return matched
end

-- Respect favourited items -- never pull them for a craft.
local function skipItem(it)
    if not it then return true end
    local skip = false
    pcall(function() if it.isFavorite and it:isFavorite() then skip = true end end)
    return skip
end

-- Count matching items per input across the player's currently-accessible containers (what vanilla
-- already "sees" for crafting: inventory + reachable nearby containers).
local function accessibleCounts(recipe, myInputs, player)
    local counts = {}
    pcall(function()
        local containers = inventoryContainers(player)
        local list = CraftRecipeManager.getAllItemsFromContainers(containers, ArrayList.new())
        for i = 0, list:size() - 1 do
            local idx = inputIndexFor(recipe, myInputs, list:get(i), player)
            if idx then counts[idx] = (counts[idx] or 0) + 1 end
        end
    end)
    return counts
end

-- Max crafts the recipe supports given (accessible items + the given designated boxes).
-- boxes come from LootSorter.gatherBoxes (range/floor-filtered, nearest-first). Drives the UI slider cap.
function LootSorter.craft.maxCraftable(recipe, player, boxes)
    if not (recipe and player) then return 0 end
    local myInputs = itemInputs(recipe)
    if #myInputs == 0 then return 0 end

    local avail = accessibleCounts(recipe, myInputs, player)
    for _, b in ipairs(boxes or {}) do
        pcall(function()
            local items = b.container:getItems()
            for i = 0, items:size() - 1 do
                local it = items:get(i)
                if not skipItem(it) then
                    local idx = inputIndexFor(recipe, myInputs, it, player)
                    if idx then avail[idx] = (avail[idx] or 0) + 1 end
                end
            end
        end)
    end

    return LootSorter.craftPlan.maxCraftable(myInputs, avail)   -- pure math (unit-tested)
end

-- The craft trigger: queued AFTER the fetch transfers, so by the time it runs the ingredients are in
-- the player's inventory. It asks the game how many crafts are actually possible now and starts them.
-- (HandcraftStartMultiple checks availability at CREATION time and is all-or-nothing on qty, so we
-- must call it here -- post-fetch -- and cap qty to getPossibleCraftCount.)
LootSorter.CraftTriggerAction = ISBaseTimedAction:derive("LootSorterCraftTriggerAction")

function LootSorter.CraftTriggerAction:isValid() return true end
function LootSorter.CraftTriggerAction:update() end
function LootSorter.CraftTriggerAction:start() end

function LootSorter.CraftTriggerAction:perform()
    LootSorter._activelyCrafting = true    -- injection OFF for the craft: count/consume the carried items only
    pcall(function()
        local logic, qty = self.logic, self.qty or 1
        -- the row's logic may currently point at a different selected recipe -> pin it to ours
        pcall(function() if self.recipe then logic:setRecipe(self.recipe) end end)
        -- surface recipe: pin the captured table (we've walked back to it) so the craft targets it,
        -- not whatever surface the panel's per-frame FindCraftSurface last found near the boxes
        pcall(function() if self.surface then logic:setIsoObject(self.surface) end end)
        -- pin the logic to INVENTORY-ONLY (injection is off now) so it consumes the items we just
        -- hauled in -- never teleports the remainder out of a distant box
        pcall(function() logic:setContainers(inventoryContainers(self.character)) end)
        -- re-resolve the recipe's input items against the new (inventory-only) container set, so the
        -- multi-craft plan points at the hauled items. Without this the batch plan is stale (built from
        -- the injected box set) and only the first craft has resolvable ingredients.
        pcall(function() if logic.autoPopulateInputs then logic:autoPopulateInputs() end end)
        local k = 0
        pcall(function() k = logic:getPossibleCraftCount(true) or 0 end)
        local doN = math.min(qty, k)
        if doN > 0 then
            if self.craftFn then
                self.craftFn(doN)                       -- UI's batch-aware craft (wires per-craft callbacks)
                LootSorter.notify(self.character, "Quartermaster: crafting " .. doN)
            else
                local actions = ISEntityUI.HandcraftStartMultiple(self.character, logic, false, doN, false)
                if actions then
                    for _, a in ipairs(actions) do
                        if a then ISTimedActionQueue.add(a) end
                    end
                    LootSorter.notify(self.character, "Quartermaster: crafting " .. doN)
                else
                    LootSorter.notify(self.character, "Quartermaster: craft could not start")
                end
            end
        else
            LootSorter.notify(self.character, "Quartermaster: not enough ingredients to craft")
        end
    end)
    LootSorter._activelyCrafting = false   -- re-enable injection; Neat's end-of-batch refresh re-adds boxes.
    -- NOTE: deliberately do NOT set _craftDirty here. This runs BEFORE the queued craft actions, and a
    -- refresh now would updateContainers -> re-inject boxes -> undo the inventory-only pin, so the batch
    -- would see far-away boxes and consume nothing. Neat re-adds the boxes to the display after the batch.
    ISBaseTimedAction.perform(self)
end

function LootSorter.CraftTriggerAction:stop()
    LootSorter._activelyCrafting = false   -- cancelled/interrupted: don't leave injection disabled
    LootSorter._craftDirty = true          -- re-sync the craft UI after a cancel too
    ISBaseTimedAction.stop(self)
end

function LootSorter.CraftTriggerAction:new(character, logic, recipe, qty, craftFn, surface)
    local o = ISBaseTimedAction.new(self, character)
    o.stopOnWalk = false
    o.stopOnRun = false
    o.maxTime = 1
    o.logic = logic
    o.recipe = recipe
    o.qty = qty
    o.craftFn = craftFn
    o.surface = surface
    return o
end

-- For a surface recipe (needs a table/counter), resolve the surface object and remember the tile to
-- craft from. Returns (surface, craftSquare, ok). ok=false => surface required but none is nearby, so
-- the caller should bail. Non-surface (hand-craft) recipes return (nil, nil, true).
-- Robust across UIs: uses the logic's already-found surface if present, else finds one near the player.
function LootSorter.craft.surfaceFor(player, logic, recipe)
    local isSurface = false
    pcall(function() isSurface = recipe:isAnySurfaceCraft() end)
    if not isSurface then return nil, nil, true end
    local surface
    pcall(function() surface = logic:getIsoObject() end)
    if not surface then pcall(function() surface = ISEntityUI.FindCraftSurface(player, 2) end) end
    if not surface then return nil, nil, false end
    local sq; pcall(function() sq = player:getCurrentSquare() end)
    return surface, sq, true
end

-- Entry point: walk the boxes, haul the missing ingredients for `qty` crafts into inventory (one pass,
-- no carry-weight cap for v1), then craft. For a surface recipe pass surface+craftSquare (from
-- surfaceFor) and the character walks back to that tile to craft at the table.
function LootSorter.craft.gatherAndCraft(player, recipe, logic, qty, craftFn, surface, craftSquare)
    if not (player and recipe and logic) then return end
    qty = tonumber(qty) or 1; if qty < 1 then qty = 1 end

    local myInputs = itemInputs(recipe)
    if #myInputs == 0 then LootSorter.notify(player, "Quartermaster: nothing to fetch for this recipe"); return end

    if LootSorter.applyOptions then pcall(LootSorter.applyOptions) end   -- live range/floor settings (parity with sort)

    -- Turn OFF the craft-UI box injection for the shortfall calc, so it's measured against REAL inventory
    -- and the craft consumes the carried items (never teleports out of a distant box). The whole body is
    -- pcall-wrapped so a throw in gatherBoxes/plan/queueing can NEVER leave _activelyCrafting stuck true
    -- (which would silently disable injection -- the whole feature -- for the rest of the session).
    LootSorter._activelyCrafting = true
    local ok, err = pcall(function()
        local boxes = LootSorter.gatherBoxesOrWarn(player)
        if not boxes then return end

        -- Reduce boxes to the plain-data shape the pure planner wants: for each box, a parallel array of
        -- the actual items plus a match array (input index each item satisfies, or false). Then plan.
        local access = accessibleCounts(recipe, myInputs, player)
        local boxItems, boxMatch = {}, {}
        for _, b in ipairs(boxes) do
            local items, match = {}, {}
            pcall(function()
                local list = b.container:getItems()
                for i = 0, list:size() - 1 do
                    local it = list:get(i)
                    items[#items + 1] = it
                    if skipItem(it) then match[#match + 1] = false
                    else match[#match + 1] = inputIndexFor(recipe, myInputs, it, player) or false end
                end
            end)
            boxItems[#boxItems + 1] = items
            boxMatch[#boxMatch + 1] = match
        end

        local result = LootSorter.craftPlan.plan(myInputs, qty, access, boxMatch)   -- pure (unit-tested)

        -- queue: walk to each planned box, transfer its reserved picks into the main inventory
        local queued = 0
        for _, trip in ipairs(result.trips) do
            local b = boxes[trip.box]
            local stand
            pcall(function() stand = AdjacentFreeTileFinder.Find(b.square, player) end)
            if stand then
                ISTimedActionQueue.add(LootSorter.WalkAction:new(player, stand))
                for _, itemIdx in ipairs(trip.picks) do
                    local it = boxItems[trip.box][itemIdx]
                    pcall(function()
                        ISTimedActionQueue.add(ISInventoryTransferAction:new(player, it, it:getContainer(), player:getInventory()))
                        queued = queued + 1
                    end)
                end
            else
                LootSorter.DBG("craft: a box was unreachable, skipping it")
            end
        end

        -- surface recipe: walk back to the exact tile we crafted from (fast-forward-safe), so the table
        -- is adjacent again when the craft fires
        if surface and craftSquare then
            ISTimedActionQueue.add(LootSorter.WalkAction:new(player, craftSquare))
        end

        -- finally the craft trigger (runs once the fetch + walk-back above have completed)
        ISTimedActionQueue.add(LootSorter.CraftTriggerAction:new(player, logic, recipe, qty, craftFn, surface))
        LootSorter.notify(player, ("Quartermaster: fetching %d item(s), then crafting up to %d"):format(queued, qty))
    end)
    -- shortfall is measured; let injection resume during the walk. Always cleared, even on a throw above.
    LootSorter._activelyCrafting = false
    if not ok then LootSorter.DBG("gatherAndCraft error: " .. tostring(err)) end
end

LootSorter.DBG("craft engine loaded")
