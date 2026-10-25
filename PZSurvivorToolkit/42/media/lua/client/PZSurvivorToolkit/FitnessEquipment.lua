require 'TimedActions/ISDropWorldItemAction'
require 'TimedActions/ISInventoryTransferUtil'

local Toolkit = PZSurvivorToolkit
local Equipment = {}
Toolkit.FitnessEquipment = Equipment
local Proof = require 'PZSurvivorToolkit/SourceProof'
local nativeRestoration
local panels, borrowed, episodes = {}, setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})

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

-- Native placement/replication can precede refresh of the UI floor projection.
-- Confirm the exact real world object without changing that projection or gameplay.
function Equipment.placed(ref, square)
    if not square then return end
    local result
    local objects = square:getWorldObjects()
    for i = 0, objects:size() - 1 do
        local world = objects:get(i)
        local item = world:getItem()
        if matches(item, ref) then
            if result or world:getSquare() ~= square or item:getWorldItem() ~= world then return end
            result = item
        end
    end
    return result
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

-- Native UI preparation runs with queue editing disabled as well. A private
-- receipt records the actual selected pickup, never an enqueue-only item claim.
local function liveLoan(loan, action)
    local player, policy = loan.player, Toolkit.ActionQueuePolicy
    return not player:isDead() and getSpecificPlayer(player:getPlayerNum()) == player
        and ISTimedActionQueue.queues[player] == loan.queue and action.character == player
        and (loan.queue.toolkitOperationGeneration or 0) == loan.generation
        and action.srcContainer == loan.source and action.destContainer == player:getInventory()
        and Toolkit.ActionQueueTidyIntent == loan.intent and loan.intent.observeTransfers == loan.observe
        and policy == loan.policy and policy.matchesNative == loan.matchesNative and loan.matchesNative(action)
        and not action.onStartFunc and not action.onCompleteFunc and not action.onCancelFunc
end

local function observeLoans(intent)
    local previous = ISInventoryTransferAction.checkQueueList
    intent.observeTransfers(function() end, function(action) return borrowed[action] ~= nil end, {
        begin = function(action)
            local loan = borrowed[action]
            if not loan then return false end
            local groups = action.queueList
            local member = type(groups) == 'table' and #groups == 1
                and type(groups[1].items) == 'table' and #groups[1].items == 1 and groups[1].items[1]
            if loan.begun or not liveLoan(loan, action) or loan.queue.current ~= action
                or loan.queue.queue[1] ~= action or not matches(action.item, loan.item)
                or not matches(member, loan.item) or member ~= action.item
                    and not (isClient() and member == loan.member and member:getContainer() == nil
                        and Equipment.root(loan.player, loan.item) == action.item) then
                borrowed[action] = nil; return false
            end
            loan.begun = true
            if isClient() and (type(action.transactionId) ~= 'number' or action.transactionId == 0
                or not isItemTransactionDone(action.transactionId) or isItemTransactionRejected(action.transactionId)) then
                borrowed[action] = nil; return false
            end
            loan.proof = Toolkit.ActionQueueSettlement.captureEffect(action)
            return true
        end,
        finish = function(action, succeeded)
            local loan = borrowed[action]
            borrowed[action] = nil
            if not loan or not loan.begun or not loan.proof or not succeeded or not liveLoan(loan, action) then return end
            local item = Equipment.root(loan.player, loan.item)
            if item and not loan.source:containsID(loan.item.id)
                and Toolkit.ActionQueueSettlement.confirmEffect(loan.proof, true) then loan.earned = true end
        end,
    })
    local replacement = ISInventoryTransferAction.checkQueueList
    local policy = Toolkit.ActionQueuePolicy
    return previous == replacement or policy and policy.adoptTransferQueueObserver
        and policy.adoptTransferQueueObserver(previous, replacement) == true
end

local function retire(handle)
    local episode = episodes[handle]
    episodes[handle] = nil
    if episode and episode.loan then borrowed[episode.loan.action] = nil end
    return episode
end

local function currentEpisode(player, handle)
    local episode = episodes[handle]
    if not episode or player ~= episode.player then return end
    if player:isDead() or getSpecificPlayer(player:getPlayerNum()) ~= player
        or ISTimedActionQueue.queues[player] ~= episode.queue
        or (episode.queue.toolkitOperationGeneration or 0) ~= episode.cleanupGeneration then
        retire(handle); return
    end
    return episode
end

local function returnLoan(player, handle)
    local episode = currentEpisode(player, handle)
    if not episode then return end
    retire(handle)
    local loan = episode.loan
    if episode then episode.loan = nil end -- Each native borrowing episode has one cleanup opportunity.
    if not loan or loan.player ~= player or not loan.earned or ISTimedActionQueue.queues[player] ~= loan.queue
        or (loan.queue.toolkitOperationGeneration or 0) ~= episode.cleanupGeneration then return end
    local item, bag = Equipment.root(player, loan.item), Equipment.root(player, loan.bag)
    if not item or not bag or not bag:getInventory():hasRoomFor(player, item)
        or player:getPrimaryHandItem() == item or player:getSecondaryHandItem() == item then return end
    local action = ISInventoryTransferUtil.newInventoryTransferAction(player, item, player:getInventory(), bag:getInventory())
    if Toolkit.ActionQueueTidyIntent == loan.intent and loan.intent.observeTransfers == loan.observe
        and Toolkit.ActionQueuePolicy == loan.policy and loan.policy.matchesNative == loan.matchesNative
        and loan.matchesNative(action) then ISTimedActionQueue.add(action) end
end

local function restore(player, handle)
    local episode = currentEpisode(player, handle)
    if not episode or episode.restoring then return end
    episode.restoring = true
    local refs = episode.refs
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
    local loan = episode.loan
    if loan and (ISTimedActionQueue.queues[player] ~= loan.queue
        or (loan.queue.toolkitOperationGeneration or 0) ~= episode.cleanupGeneration) then
        borrowed[loan.action] = nil
        episode.loan, loan = nil, nil
    end
    local prop = loan and loan.earned and Equipment.root(player, loan.item)
    if prop and (loan.emptyPrimary and player:getPrimaryHandItem() == prop
        or loan.emptySecondary and player:getSecondaryHandItem() == prop) then
        local unequip = ISUnequipAction:new(player, prop, 50)
        if Toolkit.ActionQueuePolicy == loan.policy and loan.policy.matchesNative == loan.matchesNative
            and loan.matchesNative(unequip) then ISTimedActionQueue.add(unequip) end
    end
    -- A carrier may itself be the original hand item. Let its native equip
    -- finish before returning the prop, so no held item is moved by cleanup.
    if episode.loan then ISTimedActionQueue.add(Toolkit.ActionQueueOperations.command(player, returnLoan, handle))
    else retire(handle) end
end

function Equipment.install(ui)
    local equip, update = ui.equipItems, ui.update
    if not Proof.matches('media/lua/client/ISUI/ISFitnessUI.lua', 219506148)
        or not Proof.closure(equip, 'ISFitnessUI.lua') or not Proof.closure(update, 'ISFitnessUI.lua') then return false end
    local intent, observe = Toolkit.ActionQueueTidyIntent, Toolkit.ActionQueueTidyIntent and Toolkit.ActionQueueTidyIntent.observeTransfers
    local observing
    local equipHook = function(panel)
        -- Repeated OK presses during native preparation must not enqueue a second
        -- placement for the same still-worn bag or overwrite its restoration state.
        for pending in pairs(panels) do if pending.player == panel.player then return false end end
        local refs = Equipment.capture(panel.player)
        local drops = Equipment.drops(panel.player, refs)
        if not drops then return false end
        local player, policy = panel.player, Toolkit.ActionQueuePolicy
        local queue = ISTimedActionQueue.getTimedActionQueue(player)
        local before = {}; for _, action in ipairs(queue.queue) do before[action] = true end
        local primary, secondary = player:getPrimaryHandItem(), player:getSecondaryHandItem()
        if not equip(panel) then return false end
        -- B42.21 clears this slot locally for primary/switch props; publish that
        -- already-applied native change using the game's own Equip packet.
        if isClient() and player:isLocalPlayer() and getSpecificPlayer(player:getPlayerNum()) == player
            and secondary ~= player:getSecondaryHandItem() then player:updateHandEquips() end
        do
            local handle, episode = {}, {player = player, queue = queue, refs = refs}
            episodes[handle], panels[panel] = episode, handle
            if intent and intent == Toolkit.ActionQueueTidyIntent and intent.observeTransfers == observe then
                if observing == nil then observing = observeLoans(intent) == true end
                local selected
                for _, action in ipairs(observing and queue.queue or {}) do
                    if not before[action] and getmetatable(action) == ISInventoryTransferAction
                        and action.character == player and action.destContainer == player:getInventory()
                        and action.item and action.item:getFullType() == panel.exeData.item
                        and action.item:getContainer() == action.srcContainer and policy.matchesNative(action) then
                        for _, ref in ipairs(refs) do
                            local bag = Equipment.root(player, ref)
                            if bag and bag:getInventory() == action.srcContainer then
                                if selected then selected = false; break end
                                selected = {action = action, player = player, queue = queue, source = action.srcContainer,
                                    item = {id = action.item:getID(), kind = action.item:getFullType()}, member = action.item,
                                    bag = {id = ref.id, kind = ref.kind},
                                    emptyPrimary = primary == nil, emptySecondary = secondary == nil, intent = intent, observe = observe, policy = policy, matchesNative = policy.matchesNative, generation = queue.toolkitOperationGeneration or 0}
                            end
                        end
                        if selected == false then break end
                    end
                end
                if selected then episode.loan = selected; borrowed[selected.action] = selected end
            end
            for _, action in ipairs(drops) do ISTimedActionQueue.add(action) end
        end
        return true
    end
    local updateHook = function(panel)
        local handle = panels[panel]
        local episode = handle and episodes[handle]
        local refs = episode and episode.refs
        -- A settled native terminal owns this exact restoration episode until
        -- its stop packet/receipt has finished; UI ticks cannot append it behind the tail.
        if episode and episode.hold then return end
        if refs and panel.currentExercice and not panel.player:getFitness():getCurrentExe() then
            panels[panel] = nil
            episode.cleanupGeneration = (ISTimedActionQueue.queues[panel.player].toolkitOperationGeneration or 0)
            -- Native UI still restores ordinary hand items. Storage is resolved by ID
            -- only after pickup, because Host may deliver a different item replica.
            for key, item in pairs(panel.itemsToReequip) do
                for _, ref in ipairs(refs) do if matches(item, ref) then panel.itemsToReequip[key] = nil; break end end
            end
            update(panel)
            if #refs == 0 then retire(handle); return end
            if not panel.player:isDead() then
                Equipment.pickups(panel.player, refs, function(action) ISTimedActionQueue.add(action) end)
                ISTimedActionQueue.add(Toolkit.ActionQueueOperations.command(panel.player, restore, handle))
            end
            return
        end
        return update(panel)
    end
    nativeRestoration = function(action, panel)
        local handle = panels[panel]
        local episode = handle and episodes[handle]
        if not episode or episode.player ~= action.character or episode.hold
            or panel.player ~= action.character or panel.currentExercice ~= action.exeData.type
            or ui.update ~= updateHook or ui.equipItems ~= equipHook then return end
        local exercise, items = panel.currentExercice, panel.itemsToReequip
        local snapshot = {}; for key, item in pairs(items) do snapshot[key] = item end
        episode.hold = action
        local function release()
            if episode.hold == action then episode.hold = nil end
            if ISTimedActionQueue.queues[episode.player] ~= episode.queue
                or getSpecificPlayer(episode.player:getPlayerNum()) ~= episode.player then
                if panels[panel] ~= handle or episodes[handle] ~= episode then return end
                panels[panel] = nil
                retire(handle)
                if panel.player ~= episode.player or panel.currentExercice ~= exercise or panel.itemsToReequip ~= items then return end
                for key, item in pairs(snapshot) do if items[key] ~= item then return end end
                for key, item in pairs(items) do if snapshot[key] ~= item then return end end
                -- This detached panel no longer owns restoration into the new
                -- queue. Leave every real item where the native effects put it.
                panel.itemsToReequip, panel.currentExercice = {}, nil
            end
        end
        local function valid()
            if panels[panel] ~= handle or episodes[handle] ~= episode or episode.hold ~= action
                or ui.update ~= updateHook or ui.equipItems ~= equipHook or panel.player ~= episode.player
                or panel.currentExercice ~= exercise or panel.itemsToReequip ~= items then return false end
            for key, item in pairs(snapshot) do if items[key] ~= item then return false end end
            for key, item in pairs(items) do if snapshot[key] ~= item then return false end end
            return true
        end
        local function cleanup()
            if not valid() then release(); return end
            release()
            updateHook(panel)
        end
        return cleanup, release, valid
    end
    ui.equipItems, ui.update = equipHook, updateHook
    -- Native restoration normally depends on the window remaining open.
    Events.OnTick.Add(function()
        for panel in pairs(panels) do
            if panel.player:isDead() or ui.update ~= updateHook or ui.equipItems ~= equipHook then retire(panels[panel]); panels[panel] = nil
            elseif panel.currentExercice then
                local loan = episodes[panels[panel]] and episodes[panels[panel]].loan
                if loan and loan.earned and not Equipment.root(panel.player, loan.item) then loan.earned = false end
                updateHook(panel)
            end
        end
    end)
    if Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(function() panels, borrowed, episodes = {}, setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"}) end) end
    return true
end

-- Only the source-proven native UI producer has an episode in this registry.
-- The returned callbacks retain no public action-field capability.
function Equipment.deferRestoration(action, panel)
    if nativeRestoration then return nativeRestoration(action, panel) end
end

return Equipment
