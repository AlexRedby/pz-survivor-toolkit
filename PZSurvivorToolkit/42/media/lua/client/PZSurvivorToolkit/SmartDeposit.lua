-- Routing and walking adapted from Better Containers 42.21 by Eurymachus.
-- One allocation policy feeds advisory drag feedback and fresh native transfer commands.
local Options = require "BetterContainers/_Options"
local Proximity = require "BetterContainers/Proximity"
local Category = require "BetterContainers/Categorize/InventoryCategory"
local Classes = require "PZSurvivorToolkit/InventoryClasses"
local Protection = require "PZSurvivorToolkit/InventoryTransferProtection"
require "TimedActions/ISInventoryTransferUtil"
require "TimedActions/WalkToTimedAction"

local Deposit = {}
PZSurvivorToolkit.SmartDeposit = Deposit
local installed, ready = {}, false
local PREVIEW_MS = 200
local previewEpoch, inventoryRevisions = 0, {}

local function invalidate(player)
    if player == nil then previewEpoch = previewEpoch + 1
    else inventoryRevisions[player] = (inventoryRevisions[player] or 0) + 1 end
end

local function pack(...) return {n = select("#", ...), ...} end
local function sameItems(left, right)
    if not left or #left ~= #right then return false end
    for index, item in ipairs(right) do if left[index] ~= item then return false end end
    return true
end
local function copyItems(items)
    local result = {}
    for index, item in ipairs(items) do result[index] = item end
    return result
end
local excluded = {
    floor = true, ["local"] = true, localContainer = true, localInventory = true,
    stove = true, microwave = true, oven = true, washingmachine = true, dryer = true,
    clothingwasher = true, clothingdryer = true, combinationwasherdryer = true,
}

local function corpseMode()
    return (Options.getEffectivePermissions() or {}).corpseOnly == true
end

function Deposit.isTarget(container)
    if not container then return false end
    local kind = container:getType()
    return kind == Proximity.invName or kind == Proximity.invName_corpses and corpseMode()
end

local function storage(container, player)
    local kind = container:getType()
    if excluded[kind] or kind == Proximity.invName or kind == Proximity.invName_corpses then return false end
    if (kind == "inventorymale" or kind == "inventoryfemale") and not corpseMode() then return false end
    local parent = container:getParent()
    return not (parent and instanceof(parent, "IsoThumpable") and parent:isLockedToCharacter(player))
end

local function weight(item)
    return item:getUnequippedWeight()
end

local function room(container, player, item, reserved)
    if not container:isItemAllowed(item) or container:isInside(item) then return false end
    if reserved == 0 then return container:hasRoomFor(player, item) == true end
    local total = reserved + weight(item)
    return container:hasRoomFor(player, total, total) == true
end

function Deposit.plan(pane, items, target)
    local result = {destinations = {}, groups = {}, accepted = {}}
    local player = getSpecificPlayer(pane.player or 0)
    if not player or not Deposit.isTarget(target) then return result end
    local dragging = ISMouseDrag and ISMouseDrag.dragging
    local deliberate = dragging and Protection.containsSelection(dragging, items)
    local moving, ordered = {}, {}
    for _, item in ipairs(items) do
        if not moving[item] and (deliberate or Protection.allowsAutomatic(item)) then
            -- Preserve BC's affinity rule: selected items, including favorites
            -- that cannot move, do not count as the destination's existing stock.
            moving[item] = true
            if item:getContainer() and item:getContainer() ~= target
                and not item:isFavorite() and not target:isInside(item) then
                ordered[#ordered + 1] = item
            end
        end
    end
    -- Work on a private list: preview must not change the current drag selection.
    pane:sortItemsByTypeAndWeight(ordered)
    local nearby, seen = {}, {}
    local page = getPlayerLoot(pane.player or 0)
    for _, button in ipairs(page and page.backpacks or {}) do
        local container = button.inventory
        if container and not seen[container] and storage(container, player) then
            seen[container] = true
            local record = {container = container, types = {}, categories = {}, reserved = 0}
            local contents = container:getItems()
            for i = 0, contents:size() - 1 do
                local other = contents:get(i)
                if not moving[other] then
                    record.types[other:getFullType()] = true
                    local category = Category.get(other)
                    if category and category ~= "" then record.categories[category] = true end
                end
            end
            nearby[#nearby + 1] = record
        end
    end
    for _, item in ipairs(ordered) do
        local fullType, category = item:getFullType(), Category.get(item)
        local destination
        for pass = 1, 3 do
            for _, record in ipairs(nearby) do
                if (pass == 3 or pass == 1 and record.types[fullType]
                    or pass == 2 and category and record.categories[category])
                    and room(record.container, player, item, record.reserved) then
                    destination = record
                    break
                end
            end
            if destination then break end
        end
        if destination and destination.container ~= item:getContainer() then
            local container = destination.container
            if not result.groups[container] then
                result.groups[container] = {}
                result.destinations[#result.destinations + 1] = container
            end
            local group = result.groups[container]
            group[#group + 1] = item
            result.accepted[item] = container
            destination.reserved = destination.reserved + weight(item)
        end
    end
    return result
end

local function walk(container, player)
    if container:getType() == "floor" or container:isInCharacterInventory(player) then return true end
    local parent = container:getParent()
    if not parent or not parent:getSquare() then return true end
    local square = player:getCurrentSquare()
    if not square then return false end
    if instanceof(parent, "IsoDeadBody") then return true end
    if instanceof(parent, "BaseVehicle") then
        if player:getVehicle() == parent then return true end
        local part = container:getVehiclePart()
        if part and part:getArea() then
            if part:getVehicle():canAccessContainer(part:getIndex(), player) then return true end
            ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(player, part:getVehicle(), part:getArea()))
            return true
        end
        return false
    end
    if parent:getSquare():DistToProper(square) < 2 then return true end
    local adjacent = AdjacentFreeTileFinder.Find(parent:getSquare(), player)
    if not adjacent then return false end
    if adjacent ~= square then ISTimedActionQueue.add(ISWalkToTimedAction:new(player, adjacent)) end
    return true
end

local function execute(pane, items, target)
    local plan = Deposit.plan(pane, items, target)
    local player = getSpecificPlayer(pane.player or 0)
    for _, container in ipairs(plan.destinations) do
        if walk(container, player) then
            for _, item in ipairs(plan.groups[container]) do
                local origin = item:getContainer()
                if origin and origin ~= container then
                    ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(player, item, origin, container))
                end
            end
        end
    end
end

local function preview(pane, target)
    local dragging = ISMouseDrag and ISMouseDrag.dragging
    return Deposit.plan(pane, dragging and ISInventoryPane.getActualItems(dragging) or {}, target)
end

-- Only the visual hint may be briefly stale. Stock, affinity and capacity are
-- always read again by canPutIn/execute, including same-count inventory changes.
local function dragPreview(drag, target)
    local pane, rows = drag.inventoryPane, ISMouseDrag and ISMouseDrag.dragging
    if not rows then drag.toolkitSmartDepositPreview = nil; return nil end
    local items = ISInventoryPane.getActualItems(rows)
    local player, now = pane.player or 0, getTimestampMs()
    local revision = inventoryRevisions[player] or 0
    local cached = drag.toolkitSmartDepositPreview
    if not cached or cached.pane ~= pane or cached.player ~= player or cached.target ~= target
        or cached.dragging ~= rows or cached.nativeItems ~= drag.items
        or cached.epoch ~= previewEpoch or cached.revision ~= revision
        or now < cached.at or now - cached.at >= PREVIEW_MS
        or not sameItems(cached.rows, rows) or not sameItems(cached.items, items)
        or not sameItems(cached.nativeSelection, drag.items) then
        cached = {pane = pane, player = player, target = target, dragging = rows,
            nativeItems = drag.items, nativeSelection = copyItems(drag.items),
            rows = copyItems(rows), items = items, at = now,
            epoch = previewEpoch, revision = revision, plan = Deposit.plan(pane, items, target)}
        drag.toolkitSmartDepositPreview = cached
    end
    return cached.plan
end

local function installPane(class)
    if not class or installed[class] then return end
    installed[class] = true
    local refresh = class.refreshContainer
    if refresh then
        class.refreshContainer = function(pane, ...)
            invalidate(pane.player)
            local result = pack(refresh(pane, ...))
            invalidate(pane.player)
            return unpack(result, 1, result.n)
        end
    end
    local transfer, canPut = class.transferItemsByWeight, class.canPutIn
    class.transferItemsByWeight = function(pane, items, container, ...)
        if Deposit.isTarget(container) then return execute(pane, items, container) end
        return transfer(pane, items, container, ...)
    end
    class.canPutIn = function(pane, ...)
        if Deposit.isTarget(pane.inventory) then return #preview(pane, pane.inventory).destinations > 0 end
        return canPut(pane, ...)
    end
end

local function installPage(class)
    if not class or installed[class] then return end
    installed[class] = true
    local canPut = class.canPutIn
    class.canPutIn = function(page, ...)
        local target = page.mouseOverButton and page.mouseOverButton.inventory
        if Deposit.isTarget(target) then return #preview(page.inventoryPane, target).destinations > 0 end
        return canPut(page, ...)
    end
end

local function installDrag(class)
    if not class or installed[class] then return end
    installed[class] = true
    local reset, update = class.reset, class.update
    if reset then
        class.reset = function(self, ...)
            self.toolkitSmartDepositPreview = nil
            return reset(self, ...)
        end
    end
    class.update = function(self, ...)
        local result = update(self, ...)
        if Deposit.isTarget(self.mouseOverContainer) and self.items then
            local plan = dragPreview(self, self.mouseOverContainer)
            if plan then
                for _, item in ipairs(self.items) do
                    self.itemNotOK[item] = not plan.accepted[item] or nil
                end
            end
        else self.toolkitSmartDepositPreview = nil end
        return result
    end
end

function Deposit.install()
    ready = true
    invalidate()
    Classes.panes(installPane)
    installPage(CleanUI_Clean_ISInventoryPage)
    installPage(CleanUI_Vanilla_ISInventoryPage)
    installPage(ISInventoryPage)
    installDrag(ISInventoryPaneDraggedItems)
    installDrag(CleanUI_Vanilla_ISInventoryPaneDraggedItems)
end
-- These events retire the UI projection; they are not claimed as complete
-- contents revisions. The wall-clock limit also catches changes they do not see.
Events.OnRefreshInventoryWindowContainers.Add(function(page, phase)
    if phase == "end" then invalidate(page and page.player) end
end)
Events.OnContainerUpdate.Add(function() invalidate() end)
Classes.onToggle(function() if ready then Deposit.install() end end)
return Deposit
