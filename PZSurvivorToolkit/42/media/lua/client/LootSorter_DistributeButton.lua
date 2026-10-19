-- Adds a "Distribute Loot" button to the inventory window's control row (next to Transfer All).
-- Distributes THIS container's contents into your designated boxes. (Assignment stays on right-click.)
require "ISUI/InventoryWindow/ISInventoryWindowContainerControls"
require "ISUI/InventoryWindow/ISInventoryWindowControlHandler"
require "ISUI/LootWindow/ISLootWindowFloorControlHandler"

ISInventoryWindowControlHandler_LootSorterDistribute =
    ISInventoryWindowControlHandler:derive("ISInventoryWindowControlHandler_LootSorterDistribute")
local Handler = ISInventoryWindowControlHandler_LootSorterDistribute

function Handler:shouldBeVisible()
    if getCore():getGameMode() == "Tutorial" then return false end
    return self.container ~= nil and not self.container:isEmpty()
end

function Handler:getControl()
    self.control = self:getButtonControl("Distribute Loot")
    self.control.tooltip = "Sort this container's loot into your designated boxes"
    return self.control
end

function Handler:perform()
    if isGamePaused() then return end
    local playerNum = (self.inventoryWindow and self.inventoryWindow.player) or 0
    LootSorter.sort(self.container, playerNum)
end

-- Controller support: the on-screen control strip (where the button lives) isn't reachable with a
-- gamepad, so surface the action in the joypad context menu instead. Only invoked when a controller
-- is bound (getJoypadBind() ~= -1), so mouse users are unaffected.
function Handler:handleJoypadContextMenu(context)
    self:addJoypadContextMenuOption(context, "Distribute Loot")
end

function Handler:new()
    return ISInventoryWindowControlHandler.new(self)
end

-- Registered unguarded: AddHandler matches on handlerClass.Type and REPLACES the existing list
-- entry, so a reload swaps in the new class instead of stacking a duplicate. A boolean guard would
-- only stop the NEW class from ever replacing the old one, so edits wouldn't take until a restart.
if not LootSorter then LootSorter = {} end
ISInventoryWindowContainerControls.AddHandler(ISInventoryWindowControlHandler_LootSorterDistribute)

-- === Loot window (trunks, storage crates) uses a SEPARATE control system ===
require "ISUI/LootWindow/ISLootWindowObjectControlHandler"
require "ISUI/LootWindow/ISLootWindowContainerControls"

ISLootWindowObjectControlHandler_LootSorterDistribute =
    ISLootWindowObjectControlHandler:derive("ISLootWindowObjectControlHandler_LootSorterDistribute")
local LH = ISLootWindowObjectControlHandler_LootSorterDistribute

function LH:shouldBeVisible()
    if getCore():getGameMode() == "Tutorial" then return false end
    return self.container ~= nil and not self.container:isEmpty()
end

function LH:getControl()
    self.control = self:getButtonControl("Distribute Loot")
    self.control.tooltip = "Sort this container's loot into your designated boxes"
    return self.control
end

function LH:perform()
    if isGamePaused() then return end
    local playerNum = self.playerNum or (self.lootWindow and self.lootWindow.player) or 0
    LootSorter.sort(self.container, playerNum)
end

-- Controller support (loot/crate window): same as the inventory handler above.
function LH:handleJoypadContextMenu(context)
    self:addJoypadContextMenuOption(context, "Distribute Loot")
end

function LH:new()
    return ISLootWindowObjectControlHandler.new(self)
end

ISLootWindowContainerControls.AddHandler(ISLootWindowObjectControlHandler_LootSorterDistribute)

-- The FLOOR container needs its own handler: arrange() walks a separate FloorHandlerList for it
-- (the floor has no IsoObject parent), so an AddHandler registration is never instantiated there.
-- The joypad context menu mirrors the same branch, so this covers the controller path too.
ISLootWindowFloorControlHandler_LootSorterDistribute =
    ISLootWindowFloorControlHandler:derive("ISLootWindowFloorControlHandler_LootSorterDistribute")
local FloorHandler = ISLootWindowFloorControlHandler_LootSorterDistribute

function FloorHandler:shouldBeVisible()
    if getCore():getGameMode() == "Tutorial" then return false end
    return self.container ~= nil and not self.container:isEmpty()
end

function FloorHandler:getControl()
    self.control = self:getButtonControl("Distribute Loot")
    self.control.tooltip = "Sort the loot on this tile into your designated boxes"
    return self.control
end

function FloorHandler:perform()
    if isGamePaused() then return end
    local playerNum = self.playerNum or (self.lootWindow and self.lootWindow.player) or 0
    LootSorter.sort(self.container, playerNum)
end

function FloorHandler:handleJoypadContextMenu(context)
    self:addJoypadContextMenuOption(context, "Distribute Loot")
end

function FloorHandler:new()
    return ISLootWindowFloorControlHandler.new(self)
end

-- Registered unguarded so a hot-reload takes effect: AddFloorHandler matches on handlerClass.Type
-- and REPLACES the existing entry, so re-running this file swaps in the new class rather than
-- stacking a duplicate -- the same remove-then-add effect the event handlers get explicitly.
ISLootWindowContainerControls.AddFloorHandler(ISLootWindowFloorControlHandler_LootSorterDistribute)
