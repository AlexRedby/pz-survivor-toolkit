-- Quartermaster: crafting UI integration (STABLE / injection approach).
--
-- A "Storage" tickbox in the craft window toggles the feature. While ON, we APPEND your in-range /
-- cross-floor designated boxes during the crafting panels' container refresh calls.
-- Unrelated ISInventoryPaneContextMenu.getContainers callers retain their ordinary set.
-- The crafting logic caches the availability set via
-- NC_CraftLogicPanel:updateContainers() -> logic:setContainers(), so a single re-scan makes EVERYTHING
-- (button greying, quantity cap, required-items list, and the recipe list) count the boxes at once --
-- no per-widget wrapping. The logic only re-scans on init / recipe-change / after a craft, so the one
-- missing trigger was: re-scan when the tickbox flips. We do that via a "dirty" flag the panel drains.
--
-- Physical haul preserved: pressing craft runs the gather engine; the craft trigger sets the logic's
-- containers to INVENTORY-ONLY right before crafting, so the hauled items are consumed, never teleported.
LootSorter = LootSorter or {}
LootSorter.craftFromBoxes = LootSorter.craftFromBoxes or false
local Containers = require "PZSurvivorToolkit/QuartermasterCraftContainers"

-- shared label/tooltip for the injected "Storage" tickbox (used by both the vanilla + Neat hooks)
local NO_SURFACE = "Quartermaster: stand near a crafting surface"
local STORAGE_LABEL = "Quartermaster: Storage"
local STORAGE_TOOLTIP = "Craft from your designated storage boxes: the character hauls the ingredients over, then crafts. It fetches everything the batch needs in one trip, so a large batch can leave you overburdened."

-- Flip the feature flag, mark for a re-scan, AND mirror the value into the Mod Options tickbox so the
-- in-menu "Storage" checkbox and the settings-menu fallback stay in sync (and the choice persists).
local function setCraftFromBoxes(on)
    LootSorter.craftFromBoxes = on and true or false
    LootSorter._craftDirty = true
    pcall(function()
        local o = PZAPI and PZAPI.ModOptions and PZAPI.ModOptions:getOptions("LootSorter")
        local c = o and o:getOption("craftFromBoxes")
        if c then c:setValue(LootSorter.craftFromBoxes) end
    end)
end

-- append the designated boxes to the availability container set (see header)
local function installContainerInjection()
    if LootSorter._getContainersWrapped then return end
    LootSorter._getContainersWrapped = true
    local orig = ISInventoryPaneContextMenu.getContainers
    local active = Containers.active
    ISInventoryPaneContextMenu.getContainers = function(character)
        local list = orig(character)
        -- Also gate OFF while the player is doing a timed action: this covers the whole haul + the
        -- queued craft batch (incl. Neat's between-craft callbacks), so boxes can't be re-injected
        -- mid-batch and cause a consume-from-distant-box "teleport". Injection is only for availability
        -- while browsing recipes (idle), never during the haul/craft itself.
        local busy = ISTimedActionQueue and ISTimedActionQueue.isPlayerDoingAction
            and ISTimedActionQueue.isPlayerDoingAction(character)
        if list and list.add and LootSorter.craftFromBoxes and not LootSorter._activelyCrafting and not busy
                and character ~= nil and active(character) then
            pcall(function()
                -- Silent when unsynced: this runs on every container-list rebuild, so a message here
                -- would be spam. Injecting nothing simply reads as "no boxes yet".
                local boxes = LootSorter.gatherBoxes(character)
                for _, b in ipairs(boxes) do
                    if b.container then list:add(b.container) end
                end
            end)
        end
        return list
    end
    LootSorter.DBG("getContainers injection installed")
end

local function scopeRefresh(class, method)
    local original = class and class[method]
    if not original then return end
    local withContext = Containers.withContext
    class[method] = function(self, ...)
        return withContext(self.player, original, self, ...)
    end
end

local function installRefreshScopes()
    scopeRefresh(_G.ISHandCraftPanel, "updateContainers")
    scopeRefresh(_G.NC_HandCraftPanel, "updateContainers")
    -- Neat's movement refresh reads containers directly instead of calling updateContainers.
    scopeRefresh(_G.NC_HandCraftPanel, "update")
    scopeRefresh(_G.NC_CraftLogicPanel, "updateContainers")
end

local function placeTick(window)
    local header, tick = window.header, window.qmTick
    if not header or not tick or not header.buttonPanel or not header.buttonColumn then return end
    local cell = header:cellFor(tick)
    if not cell then
        local buttons = header.buttonPanel
        local buttonCell = header:cellFor(buttons)
        if not buttonCell then return end
        local column = header:addColumn(nil, false)
        column.minimumWidth = header.buttonColumn.minimumWidth
        header.buttonColumn.minimumWidth = tick:getWidth() + (header.padding or 6) * 2
        header.buttonColumn = column
        window:removeChild(tick)
        header:setElement(buttonCell.columnIndex, buttonCell.rowIndex, tick)
        header:setElement(header:columnCount() - 1, buttonCell.rowIndex, buttons)
        window:calculateLayout(window:getWidth(), window:getHeight())
        cell = header:cellFor(tick)
    end
    -- Quartermaster still writes window-relative coordinates each frame; restore the table's position.
    cell:setX(cell:getX())
    cell:setY(cell:getY())
    return true
end


-- "Storage" tickbox on the craft WINDOW (plain ISPanel), floated by the close button
local function installWindowTick(WindowClass, name)
    if not WindowClass then LootSorter.DBG("window tick SKIPPED: " .. name .. " not found"); return end
    local origCreate = WindowClass.createChildren
    function WindowClass:createChildren()
        if origCreate then origCreate(self) end
        local t = ISTickBox:new(0, 0, 90, 18, "", self, function(_t, _idx, selected)
            setCraftFromBoxes(selected)            -- sets flag + _craftDirty + mirrors to Mod Options
            LootSorter.DBG("craftFromBoxes -> " .. tostring(LootSorter.craftFromBoxes))
        end)
        t:initialise(); t:instantiate()
        t:addOption(STORAGE_LABEL)
        t:setWidthToFit()
        t:setSelected(1, LootSorter.craftFromBoxes)
        t.tooltip = STORAGE_TOOLTIP
        self:addChild(t)
        self.qmTick = t
    end
    local origPre = WindowClass.prerender
    function WindowClass:prerender()
        if origPre then origPre(self) end
        if self.qmTick then
            self.qmTick:setSelected(1, LootSorter.craftFromBoxes)
            if placeTick(self) then return end
            local hh = self.headerHeight or 24
            local bx = (self.header and self.header.buttonPanel and self.header.buttonPanel:getX())
                or (self:getWidth() - 40)
            self.qmTick:setX(math.max(4, bx - self.qmTick:getWidth() - 12))
            self.qmTick:setY(math.max(2, (hh - self.qmTick:getHeight()) / 2))
        end
    end
    LootSorter.DBG("window tick installed: " .. name)
end

-- Action panel: drain the "dirty" flag (re-scan), and intercept the craft.
local function installActionPanel()
    if not _G.NC_CraftActionPanel then LootSorter.DBG("craft panel hook SKIPPED: NC_CraftActionPanel not found"); return end

    local origPre = NC_CraftActionPanel.prerender
    function NC_CraftActionPanel:prerender()
        -- Full display refresh once when asked (toggle flip / after craft). refreshAfterCraftBatch is
        -- Neat's own post-craft routine: updateContainers (re-scan, injection applies) + autoPopulateInputs
        -- (required-items) + sortRecipeList (the recipe list) + recipeInfoPanel:onRecipeChanged. Calling it
        -- here mimics a reselect, so everything updates without navigating away and back.
        if LootSorter._craftDirty then
            LootSorter._craftDirty = false
            if self.refreshAfterCraftBatch then
                pcall(function() self:refreshAfterCraftBatch() end)
            elseif self.HandCraftPanel and self.HandCraftPanel.updateContainers then
                pcall(function() self.HandCraftPanel:updateContainers() end)
            end
        end
        if origPre then origPre(self) end
    end

    local origClick = NC_CraftActionPanel.onCraftButtonClick
    function NC_CraftActionPanel:onCraftButtonClick()
        if not (LootSorter.craftFromBoxes and self.logic) then return origClick and origClick(self) end
        -- our gather-and-craft path; on any error disarm injection and fall back to a normal craft
        -- (matches the vanilla handler; the disarm prevents the fallback consuming from a distant box)
        local pok = pcall(function()
            if self.logic:isCraftActionInProgress() then return end
            if ISTimedActionQueue and ISTimedActionQueue.isPlayerDoingAction
                    and ISTimedActionQueue.isPlayerDoingAction(self.player) then return end  -- one haul at a time
            local recipe = self.logic:getRecipe()
            if not recipe then return end
            local maxCount = 0
            pcall(function() maxCount = self.logic:getPossibleCraftCount(true) or 0 end)  -- boxes counted (logic set)
            if maxCount < 1 then return end
            local qty = 1
            if self.allowBatchCraft and self.quantityInput then
                qty = tonumber(self.quantityInput:getText()) or 1
                qty = math.max(1, math.min(maxCount, qty))
            end
            -- surface recipes: need a table nearby; capture it + the tile we're on (bail if none)
            local surface, craftSquare, ok = LootSorter.craft.surfaceFor(self.player, self.logic, recipe)
            if not ok then
                LootSorter.notify(self.player, NO_SURFACE)
                return
            end
            -- delegate the actual crafting to Neat's own batch-aware startHandcraft (it wires the per-craft
            -- onComplete callbacks that re-populate inputs between crafts -- calling HandcraftStartMultiple
            -- raw only ever produced the first item of a batch)
            local panel = self
            LootSorter.craft.gatherAndCraft(self.player, recipe, self.logic, qty, function(q)
                panel:startHandcraft(false, q)
            end, surface, craftSquare)
        end)
        if not pok then LootSorter.craft.repinInventoryOnly(self.logic, self.player); return origClick and origClick(self) end
    end

    LootSorter.DBG("craft panel hook installed: NC_CraftActionPanel")
end

----------------------------------------------------------------------
-- Vanilla B42 crafting (no Neat): tickbox on the window + craft intercept.
-- Injection is shared; vanilla re-scans when ISHandCraftPanel.drawDirty is set.
----------------------------------------------------------------------
local function installVanillaHooks()
    -- Craft-control widget: the "Storage" tickbox + the craft intercept both live here.
    if _G.ISWidgetHandCraftControl then
        -- create the tickbox as a child of the widget
        local origCreate = ISWidgetHandCraftControl.createChildren
        function ISWidgetHandCraftControl:createChildren()
            if origCreate then origCreate(self) end
            pcall(function()
                local t = ISTickBox:new(0, 0, 90, 18, "", self, function(_t, _idx, selected)
                    setCraftFromBoxes(selected)    -- sets flag + _craftDirty + mirrors to Mod Options
                    if _G.ISHandCraftPanel then ISHandCraftPanel.drawDirty = true end  -- force vanilla re-scan
                    LootSorter.DBG("craftFromBoxes -> " .. tostring(LootSorter.craftFromBoxes))
                end)
                t:initialise(); t:instantiate()
                t:addOption(STORAGE_LABEL)
                t:setWidthToFit()
                t:setSelected(1, LootSorter.craftFromBoxes)
                t.tooltip = STORAGE_TOOLTIP
                self:addChild(t)
                self.qmTick = t
            end)
        end

        -- After vanilla lays the widget out, insert the tick ABOVE the Craft button: put it where Craft
        -- was, push Craft (and Force/KnowAll, if present) down one row, grow the widget, and splice the
        -- tick into the joypad rows between the quantity row and the Craft row so a controller reaches it.
        -- This hook reaches into ISWidgetHandCraftControl's private layout + joypad internals, which is
        -- the most brittle part of the mod. It's wrapped so that if a future Build 42 patch changes
        -- those internals, we degrade to "Storage tick hidden, vanilla craft window fully functional"
        -- (and stop trying) rather than throwing during layout and breaking the craft UI.
        local origLayout = ISWidgetHandCraftControl.calculateLayout
        function ISWidgetHandCraftControl:calculateLayout(pw, ph)
            if LootSorter._craftWidgetBroken then return origLayout(self, pw, ph) end
            -- Capture the joypad cursor in OUR (tick-including) row layout BEFORE vanilla rebuilds its
            -- own tick-less rows. recordJoypadState saves the cursor by ROW INDEX; if we recorded after
            -- origLayout, the Craft row's index would map onto the Storage tick, so Craft kept snapping
            -- back to the tick. Capturing first keeps the index consistent.
            local js; pcall(function() js = self.qmTick and self:recordJoypadState() or nil end)
            origLayout(self, pw, ph)   -- vanilla layout ALWAYS runs, regardless of our tweak
            local ok, err = pcall(function()
                local t = self.qmTick
                if not t or not self.buttonCraft then return end
                local pad = UI_BORDER_SPACING or 6
                local delta = t:getHeight() + pad
                t:setX(self.buttonCraft:getX())
                t:setY(self.buttonCraft:getY())
                self.buttonCraft:setY(self.buttonCraft:getY() + delta)
                if self.buttonForceCraft then self.buttonForceCraft:setY(self.buttonForceCraft:getY() + delta) end
                if self.buttonKnowAllRecipes then self.buttonKnowAllRecipes:setY(self.buttonKnowAllRecipes:getY() + delta) end
                if self.boxHeight then self.boxHeight = self.boxHeight + delta end
                self:setHeight(self:getHeight() + delta)
                -- rebuild joypad rows WITH the tick: quantity (if shown) -> Storage tick -> Craft -> Force.
                -- Clear stale focus flags first: origLayout ran its OWN restoreJoypadState and flagged an
                -- element (usually Craft) joypadFocused=true, drawing a selected background when the cursor
                -- is elsewhere. Reset allJoypadButtons too (insertNewLineOfButtons appends to it).
                for _, b in ipairs(self.allJoypadButtons or {}) do b.joypadFocused = false end
                self.joypadButtonsY = {}; self.joypadButtons = {}; self.allJoypadButtons = {}
                self.joypadIndexY = 1; self.joypadIndex = 1
                if self.buttonLess and self.buttonLess:isVisible() then
                    self:insertNewLineOfButtons(self.buttonLess, self.buttonMore, self.buttonMax)
                end
                self:insertNewLineOfButtons(t)
                self:insertNewLineOfButtons(self.buttonCraft)
                if self.buttonForceCraft then self:insertNewLineOfButtons(self.buttonForceCraft) end
                self:restoreJoypadState(js)
            end)
            if not ok then
                LootSorter._craftWidgetBroken = true                              -- stop touching the widget
                pcall(function() if self.qmTick then self.qmTick:setVisible(false) end end)
                LootSorter.DBG("craft widget layout hook disabled after error: " .. tostring(err))
            end
        end

        -- keep the tick's checkmark in sync with the flag
        local origPreW = ISWidgetHandCraftControl.prerender
        function ISWidgetHandCraftControl:prerender()
            if origPreW then origPreW(self) end
            pcall(function() if self.qmTick then self.qmTick:setSelected(1, LootSorter.craftFromBoxes) end end)
        end

        local origClick = ISWidgetHandCraftControl.onButtonClick
        function ISWidgetHandCraftControl:onButtonClick(_button)
            if not (LootSorter.craftFromBoxes and self.logic and _button == self.buttonCraft) then
                return origClick and origClick(self, _button)
            end
            -- our gather-and-craft path; on any error fall back to a normal (vanilla) craft
            local pok = pcall(function()
                if self.logic:isCraftActionInProgress() then return end
                if ISTimedActionQueue and ISTimedActionQueue.isPlayerDoingAction
                        and ISTimedActionQueue.isPlayerDoingAction(self.player) then return end  -- one haul at a time
                local recipe = self.logic:getRecipe()
                if not recipe then return end
                local maxCount = 0
                pcall(function() maxCount = self.logic:getPossibleCraftCount(true) or 0 end)
                if maxCount < 1 then return end
                local qty = 1
                if self.allowBatchCraft and self.entryBox then
                    qty = tonumber(self.entryBox:getInternalText()) or 1
                    qty = math.max(1, math.min(maxCount, qty))
                end
                local surface, craftSquare, ok = LootSorter.craft.surfaceFor(self.player, self.logic, recipe)
                if not ok then
                    LootSorter.notify(self.player, NO_SURFACE)
                    return
                end
                local control = self
                LootSorter.craft.gatherAndCraft(self.player, recipe, self.logic, qty, function(n)
                    control.craftTimes = nil
                    if control.entryBox then control.entryBox:setText(tostring(n)) end
                    control:startHandcraft(false)
                end, surface, craftSquare)
            end)
            if not pok then LootSorter.craft.repinInventoryOnly(self.logic, self.player); return origClick and origClick(self, _button) end
        end
        LootSorter.DBG("vanilla craft intercept installed: ISWidgetHandCraftControl")
    else
        LootSorter.DBG("vanilla craft intercept SKIPPED: ISWidgetHandCraftControl not found")
    end
end

local function installHooks()
    if LootSorter._craftHooksAdded then return end
    LootSorter._craftHooksAdded = true
    LootSorter.DBG("installHooks running; NC_HandcraftWindow=" .. tostring(_G.NC_HandcraftWindow ~= nil)
        .. " NC_EntityWindow=" .. tostring(_G.NC_EntityWindow ~= nil)
        .. " NC_CraftActionPanel=" .. tostring(_G.NC_CraftActionPanel ~= nil))
    installContainerInjection()
    installRefreshScopes()
    installWindowTick(_G.NC_HandcraftWindow, "NC_HandcraftWindow")
    installWindowTick(_G.NC_EntityWindow, "NC_EntityWindow")
    installActionPanel()
    installVanillaHooks()
end

Events.OnGameStart.Add(function()
    local compat = PZSurvivorToolkit and PZSurvivorToolkit.ActionQueueCompat
    if compat then compat.installQuartermasterCraft(installHooks) else installHooks() end
end)
LootSorter.DBG("craft menu file loaded")
