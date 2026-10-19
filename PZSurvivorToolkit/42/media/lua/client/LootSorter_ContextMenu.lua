-- LootSorter: right-click context-menu entry points.
--   * World object (crate/locker/stacked boxes) -> "Configure sorting..." (opens the designation picker)
--   * Items in a container panel -> "Configure sorting..." (designation only; distribution is the button)
-- Handlers are LootSorter.* functions (reloadLuaFile-safe via the stable wrappers below).
-- Depends on LootSorter.openPicker / containerIndex (Core + Picker).
require "ISUI/ISWorldObjectContextMenu"   -- addToolTip, for the disabled-option hint

LootSorter = LootSorter or {}
-- diagnostic trace: silent unless LootSorter.DEBUG is set or the game runs in -debug mode

-- highlight the specific crate/object while its menu entry is hovered (like Destroy/Grab)
function LootSorter.onHighlightBox(option, menu, isHighlighted, obj)
    if not obj then return end
    pcall(function()
        local pnum = (menu and menu.player) or 0
        local color = getCore():getWorldItemHighlightColor()
        obj:setHighlighted(pnum, isHighlighted, false)
        obj:setHighlightColor(pnum, color)
        obj:setOutlineHighlight(pnum, isHighlighted)
        obj:setOutlineHighlightCol(pnum, color)
        ISInventoryPage.OnObjectHighlighted(pnum, obj, isHighlighted)
    end)
end

-- Right-click a WORLD object (box/crate/locker) -> configure its designation (categories + items)
function LootSorter.onWorldContext(playerNum, context, worldobjects, test)
    if test then return end
    -- collect every (object, container index) on the clicked tile(s) -> supports stacked boxes
    local seen, targets = {}, {}
    for _, o in ipairs(worldobjects) do
        local cc = o.getContainerCount and o:getContainerCount() or 0
        if cc and cc > 0 and not seen[o] then
            seen[o] = true
            for ci = 0, cc - 1 do targets[#targets + 1] = { obj = o, ci = ci, ccount = cc } end
        end
    end
    if #targets == 0 then return end
    local player = getSpecificPlayer(playerNum)

    local allowed = {}
    for _, t in ipairs(targets) do
        -- Per target, not once: worldobjects can span more than one tile, so a crate you may
        -- configure must not be hidden by a neighbouring one inside someone else's safehouse.
        if LootSorter.canLootSquare(t.obj and t.obj:getSquare(), player) then
            allowed[#allowed + 1] = t
        end
    end
    if #allowed == 0 then return end

    for _, t in ipairs(allowed) do
        -- separate stacked crates highlight independently; only compartments of ONE object need a hint
        local suffix = (t.ccount > 1) and (" (" .. (t.ci + 1) .. "/" .. t.ccount .. ")") or ""
        LootSorter.addBoxOptions(context, t.obj, t.ci, suffix, playerNum)
    end
end

-- The three per-container actions, shared by the world and inventory menus so they cannot drift.
-- At the top level rather than in a submenu: one hover less matters more for Configure sorting, the
-- action taken most, than a shorter menu does.
function LootSorter.addBoxOptions(menu, obj, ci, suffix, playerNum)
    local function track(option)
        option.onHighlightParams = { obj }
        option.onHighlight = LootSorter.onHighlightBox
        return option
    end

    track(menu:addOption("Configure sorting..." .. suffix, nil, function()
        LootSorter.openPicker(obj, ci, playerNum)
    end))

    track(menu:addOption("Copy sorting" .. suffix, nil, function()
        LootSorter.copyDesignation(obj, ci)
        local player = getSpecificPlayer(playerNum)
        if LootSorter.hasClipboardContent() then
            LootSorter.notify(player, "Copied sorting: " .. tostring(LootSorter.describeClipboard()))
        else
            LootSorter.notify(player, "That box has no sorting to copy")
        end
    end))

    -- Only offered when there is something to paste: a dead entry is worse than no entry.
    if LootSorter.hasClipboardContent() then
        track(menu:addOption("Paste sorting" .. suffix, nil,
            function()
                local pasted = LootSorter.describeClipboard()
                LootSorter.pasteDesignation(obj, ci)
                LootSorter.notify(getSpecificPlayer(playerNum),
                    "Pasted sorting: " .. tostring(pasted))
            end))
    end
end

-- Right-click items in a container panel -> sort it, or designate THAT specific container
function LootSorter.onInvContext(playerNum, context, items)
    local item = items[1]
    if not item then return end
    if not instanceof(item, "InventoryItem") then item = item.items and item.items[1] end
    if not item then return end
    -- our craftable Storage Manifest item: right-click -> open the manifest window (from anywhere)
    if item.getFullType and item:getFullType() == "Quartermaster.StorageManifest" then
        if LootSorter.toggleManifest then
            context:addOption("Open storage manifest", nil, function() LootSorter.toggleManifest() end)
        else
            -- The item is still craftable in multiplayer, so say why it does nothing rather than
            -- leave the player right-clicking a dead object.
            local option = context:addOption("Open storage manifest", nil, nil)
            option.notAvailable = true
            local tip = ISWorldObjectContextMenu.addToolTip()
            tip.description = "Single-player only for now."
            option.toolTip = tip
        end
        return
    end
    local container = item:getContainer()
    if not container then return end
    -- The control-strip "Distribute Loot" button/joypad menu can't reach the player's OWN inventory
    -- (vanilla gates the joypad control menu to loot/world containers), so offer it on right-click
    -- there. World crates keep the button/joypad-menu path.
    -- The floor is offered here too, but MOUSE ONLY: for a bound joypad vanilla already injects the
    -- floor handler's own "Distribute Loot" into this same menu (it calls controlsUI:handleJoypad-
    -- ContextMenu for any container that isn't the player's inventory), so offering it again would
    -- list the option twice on a controller.
    local isFloorContainer = false
    pcall(function() isFloorContainer = container:getType() == "floor" end)
    local player = getSpecificPlayer(playerNum)
    local floorForMouse = isFloorContainer and player and player:getJoypadBind() == -1
    if (item:isInPlayerInventory() or floorForMouse) and not container:isEmpty() then
        context:addOption("Distribute Loot", nil, function() LootSorter.sort(container, playerNum) end)
    end
    -- designate this exact container (precise even when stacked/multi-container)
    -- (world-container distribution stays on the button; right-click here is designation-only)
    local obj = container.getParent and container:getParent()
    if obj then
        local ci = LootSorter.containerIndex(obj, container)
        if ci ~= nil then
            LootSorter.addBoxOptions(context, obj, ci, "", playerNum)
        end
    end
end

-- Register ONCE (guarded), via stable wrappers that dispatch to the current LootSorter.* handlers.
-- This makes the file reloadLuaFile-safe: reloading redefines the handlers and updates the picker,
-- but the wrappers are added only on first load, so menu entries never stack into duplicates.
if not LootSorter._ctxAdded then
    LootSorter._ctxAdded = true
    Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
        return LootSorter.onWorldContext(playerNum, context, worldobjects, test)
    end)
    Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, items)
        return LootSorter.onInvContext(playerNum, context, items)
    end)
end
LootSorter.DBG("context menus loaded")
