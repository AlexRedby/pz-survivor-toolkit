require 'TimedActions/ISDropWorldItemAction'
require 'TimedActions/ISInventoryTransferUtil'

local Toolkit = PZSurvivorToolkit
local Equipment = {}
Toolkit.FitnessEquipment = Equipment
local Proof = require 'PZSurvivorToolkit/SourceProof'
local panels = {}

local function matches(item, ref)
    return item and item:getID() == ref.id and item:getFullType() == ref.kind
end

function Equipment.root(player, ref)
    local item = player:getInventory():getItemById(ref.id)
    if matches(item, ref) and item:getContainer() == player:getInventory() then return item end
end

function Equipment.capture(player)
    local result, seen = {}, {}
    local primary, secondary = player:getPrimaryHandItem(), player:getSecondaryHandItem()
    local function add(item, slot)
        if not instanceof(item, 'InventoryContainer') or item:getContainer() ~= player:getInventory()
            or item:isForceDropHeavyItem() then return end
        local ref = seen[item]
        if not ref then
            ref = {id = item:getID(), kind = item:getFullType(), primary = primary == item, secondary = secondary == item}
            seen[item], result[#result + 1] = ref, ref
        end
        if slot then ref.slot = slot end
    end
    local worn = player:getWornItems()
    for i = 0, worn:size() - 1 do
        local entry = worn:get(i)
        add(entry:getItem(), entry:getLocation())
    end
    add(primary); add(secondary)
    return result
end

function Equipment.refreshFloor(player)
    local loot = getPlayerLoot(player:getPlayerNum())
    if loot then loot:refreshBackpacks() end
end

function Equipment.ground(player, ref)
    local floor = ISInventoryPage.GetFloorContainer(player:getPlayerNum())
    local item = floor:getItemById(ref.id)
    if not matches(item, ref) or item:getContainer() ~= floor then return end
    local world = item:getWorldItem()
    local square, here = world and world:getSquare(), player:getCurrentSquare()
    if not square or not here or world:getItem() ~= item or not square:getWorldObjects():contains(world)
        or square:getZ() ~= here:getZ() or math.abs(square:getX() - here:getX()) > 1
        or math.abs(square:getY() - here:getY()) > 1
        or (square ~= here and square:isBlockedTo(here)) then return end
    return item
end

function Equipment.canWear(player, ref)
    return not ref.slot or not player:getWornItem(ref.slot)
        or matches(player:getWornItem(ref.slot), ref)
end

function Equipment.canDrop(player, ref, square)
    local item = Equipment.root(player, ref)
    return item ~= nil and square ~= nil and player:getCurrentSquare() == square
        and square:getTotalWeightOfItemsOnFloor() + item:getUnequippedWeight() <= 50
end

function Equipment.drops(player, refs)
    if #refs == 0 then return {} end
    local square = player:getCurrentSquare()
    if not square then return end
    local result, weight = {}, square:getTotalWeightOfItemsOnFloor()
    for _, ref in ipairs(refs) do
        local item = Equipment.root(player, ref)
        if not item then return end
        weight = weight + item:getUnequippedWeight()
        if weight > 50 then return end
        -- Native placement also handles favourite bags, without changing their flag.
        local drop = ISDropWorldItemAction:new(player, item, square, 0.5, 0.5, 0, 0, false)
        drop.isPlaceItem = true
        result[#result + 1] = drop
    end
    return result
end

function Equipment.pickups(player, refs, add)
    if #refs == 0 then return end
    Equipment.refreshFloor(player)
    for _, ref in ipairs(refs) do
        local item = Equipment.canWear(player, ref) and Equipment.ground(player, ref)
        if item then
            local action = ISInventoryTransferUtil.newInventoryTransferAction(player, item, item:getContainer(), player:getInventory())
            action:setAllowMissingItems(true)
            add(action, ref)
        end
    end
end

local function carried(container, ref)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if matches(item, ref) or (instanceof(item, 'InventoryContainer') and carried(item:getInventory(), ref)) then return true end
    end
    return false
end

function Equipment.stowed(player, refs)
    for _, ref in ipairs(refs) do if carried(player:getInventory(), ref) then return false end end
    return true
end

local function restore(player, refs)
    if player:isDead() then return end
    for _, ref in ipairs(refs) do
        local item = Equipment.root(player, ref)
        if item then
            if ref.slot and Equipment.canWear(player, ref) and not player:getWornItems():contains(item) then
                ISTimedActionQueue.add(ISWearClothing:new(player, item))
            end
            if ref.primary or ref.secondary then
                ISTimedActionQueue.add(ISEquipWeaponAction:new(player, item, 50, ref.primary, ref.primary and ref.secondary))
            end
        end
    end
end

function Equipment.install(ui)
    local equip, update = ui.equipItems, ui.update
    if not Proof.matches('media/lua/client/ISUI/ISFitnessUI.lua', 219506148)
        or not Proof.closure(equip, 'ISFitnessUI.lua') or not Proof.closure(update, 'ISFitnessUI.lua') then return false end
    local equipHook = function(panel)
        -- Repeated OK presses during native preparation must not enqueue a second
        -- placement for the same still-worn bag or overwrite its restoration state.
        for pending in pairs(panels) do if pending.player == panel.player then return false end end
        local refs = Equipment.capture(panel.player)
        local drops = Equipment.drops(panel.player, refs)
        if not drops then return false end
        if not equip(panel) then return false end
        if #refs > 0 then
            panels[panel] = refs
            for _, action in ipairs(drops) do ISTimedActionQueue.add(action) end
        end
        return true
    end
    local updateHook = function(panel)
        local refs = panels[panel]
        if refs and panel.currentExercice and not panel.player:getFitness():getCurrentExe() then
            panels[panel] = nil
            -- Native UI still restores ordinary hand items. Storage is resolved by ID
            -- only after pickup, because Host may deliver a different item replica.
            for key, item in pairs(panel.itemsToReequip) do
                for _, ref in ipairs(refs) do if matches(item, ref) then panel.itemsToReequip[key] = nil; break end end
            end
            update(panel)
            if not panel.player:isDead() then
                Equipment.pickups(panel.player, refs, function(action) ISTimedActionQueue.add(action) end)
                ISTimedActionQueue.add(Toolkit.ActionQueueOperations.command(panel.player, restore, refs))
            end
            return
        end
        return update(panel)
    end
    ui.equipItems, ui.update = equipHook, updateHook
    -- Native restoration normally depends on the window remaining open.
    Events.OnTick.Add(function()
        for panel in pairs(panels) do
            if panel.player:isDead() or ui.update ~= updateHook or ui.equipItems ~= equipHook then panels[panel] = nil
            elseif panel.currentExercice then updateHook(panel) end
        end
    end)
    if Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(function() panels = {} end) end
    return true
end

return Equipment
