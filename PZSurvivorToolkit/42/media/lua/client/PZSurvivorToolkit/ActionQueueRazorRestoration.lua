-- P4 owns grooming while present. Otherwise observe tools selected by the native menu.
local Toolkit = PZSurvivorToolkit
local Hand = require 'PZSurvivorToolkit/ActionQueueHandRestoration'
local Heavy = require 'PZSurvivorToolkit/ActionQueueHeavyPickup'
local Generator = require 'PZSurvivorToolkit/ActionQueueGeneratorReturn'
local Belt = require 'PZSurvivorToolkit/ActionQueueBeltTool'
local Razor = {}
Toolkit.ActionQueueRazorRestoration = Razor
local installed = false
local commandMarker = {}

function Razor.enabled()
    return installed
end

local function command(actor, callback)
    local action = Toolkit.ActionQueueOperations.command(actor, callback, {})
    action[commandMarker] = function(candidate)
        return candidate == action and action.addActionsFunction == callback
    end
    return action
end

function Razor.install()
    if installed then return true end
    local definitions, ops = Toolkit.ActionQueueDefinitions, Toolkit.ActionQueueOperations
    if not definitions or not ops or not Toolkit.ActionQueueTidyIntent
        or not Toolkit.ActionQueueRestoration.prepareOwnHandIntent()
        or not ops.installRazorProducer() then return false end
    definitions.registerBehavior('toolkit.razor-restoration', {
        types = {'ISQueueActionsAction'},
        matches = function(action)
            local seal = rawget(action, commandMarker)
            return type(seal) == 'function' and seal(action) and ops.isCommand(action)
        end,
        inspect = function(action)
            return {knownInputs=false, items={}, targets={[action.character]=true}, hands=action.character,
                equipment=action.character, deferred=true, cancelWaiting=true}
        end,
    })
    installed = true
    return true
end

local function isPrimaryEquip(action, actor, item, bothHands, belt)
    return action.character == actor and action.item == item and action.primary == true
        and (action.twoHands == true) == (bothHands == true)
        and (belt and action.fromHotbar == true and action.hotbar == belt.hotbar or not belt and not action.fromHotbar)
        and not action.alwaysTurnOn
        and Toolkit.ActionQueuePolicy.matchesNative(action)
end

local function currentTool(episode)
    local root = episode.actor:getInventory()
    local item = root:getItemById(episode.itemId)
    if item and item:getFullType() == episode.itemType and item:getContainer() == root
        and (item == episode.tool or isClient()) then return item end
end

local function episodeHands(episode, incoming, bothHands)
    local tool = episode.belt and currentTool(episode)
    if episode.belt and (not tool or not Belt.current(episode.actor, tool)) then return end
    return Toolkit.ActionQueueEquip.restorationHands(episode.actor, incoming, bothHands, tool)
end

function Razor.observe(episode, action)
    if not Toolkit.ActionQueueRazorProducer.owns(episode) then return end
    local settlement, policy = Toolkit.ActionQueueSettlement, Toolkit.ActionQueuePolicy
    local actor, tool = episode.actor, episode.tool
    if episode.belt and action == episode.equip then
        episode.itemId, episode.itemType = tool:getID(), tool:getFullType()
        if not Toolkit.Settings.actionQueue() and not settlement.beginIndependentRestoration(episode, action) then return end
    end
    if action == episode.pickup then
        local itemType = tool:getFullType()
        if (itemType ~= 'Base.Razor' and itemType ~= 'Base.Scissors') or not policy.matchesNative(action)
            or not policy.isOrdinaryTransfer(action) or not policy.isCarriedContainer(action.srcContainer, actor)
            or actor:isEquipped(tool) then return end
        if not Toolkit.Settings.actionQueue() and not settlement.beginIndependentRestoration(episode, action) then return end
        local source, root = action.srcContainer, actor:getInventory()
        episode.itemId, episode.itemType = tool:getID(), itemType
        episode.loan = settlement.observePreparation(action, {
            guard = function(value)
                return value == action and value.character == actor and value.srcContainer == source
                    and value.destContainer == root and episode.source() and policy.matchesNative(value)
                    and policy.isOrdinaryTransfer(value)
            end,
            capture = function() return {source=source} end,
            observed = function() return false end, -- Settlement verifies the native transfer itself.
        })
    elseif (episode.loan or episode.belt) and action == episode.equip then
        settlement.rememberPreparation(action, Toolkit.ActionQueueDefinitions.inspect)
        local function guard(value)
            -- Native Host isValid resolves the inventory ID after begin. The
            -- original menu reference may still be present at capture time.
            local canonical = currentTool(episode)
            return canonical ~= nil and value == action and episode.source()
                and (value.item == canonical or isClient() and value.item == tool)
                and isPrimaryEquip(value, actor, value.item, false, episode.belt)
                and (not episode.belt or Belt.current(actor, canonical) ~= nil)
        end
        local intent = Toolkit.ActionQueueTidyIntent
        local primaryRevision = intent.handRequestRevision(actor, false)
        local bothRevision = intent.handRequestRevision(actor, true)
        episode.equipHandle = settlement.observePreparation(action, {
            guard = guard,
            capture = function()
                local before, drop
                if not episode.belt and Generator.holding(actor) then
                    local reason
                    episode.generator, reason = Generator.arm(actor, currentTool(episode), action)
                    if Generator.trace then pcall(Generator.trace, action, 'arm', reason or 'armed') end
                    drop = episode.generator
                    if not drop then return end
                else
                    before = episodeHands(episode)
                    if not before and not episode.belt then drop = Heavy.capture(actor) end
                end
                if drop then
                    local grip = {item=drop.item, requiresBoth=true, handWeapon=false, handgun=false}
                    before = {primary=grip, secondary=grip}
                end
                if not before then return end
                episode.bothHands = before.primary and before.secondary and before.primary.item == before.secondary.item
                episode.revision = episode.bothHands and bothRevision or primaryRevision
                if episode.revision ~= nil then return {hands=before, drop=drop} end
            end,
            observed = function(_, before)
                local after = episodeHands(episode)
                if not after or not after.primary or after.primary.item ~= currentTool(episode) then return false end
                if before.drop and not episode.generator and Heavy.placed(before.drop) then episode.drop = before.drop end
                if not episode.hand then
                    local reason
                    episode.hand, reason = Hand.capture(before.hands, after, after.primary)
                    if episode.generator and Generator.trace then pcall(Generator.trace, action, 'hand-observed', reason or 'captured') end
                end
                return episode.hand ~= nil
            end,
        })
    elseif (episode.loan or episode.belt) and action == episode.body then
        settlement.rememberPreparation(action, Toolkit.ActionQueueDefinitions.inspect)
    end
end

local function restore(episode, parent)
    local settlement, ops = Toolkit.ActionQueueSettlement, Toolkit.ActionQueueOperations
    local actor, loan = episode.actor, episode.loan
    local function report(stage, value)
        if episode.generator and Generator.trace then pcall(Generator.trace, episode.equip, stage, value) end
    end
    if loan and not settlement.reserveClaimedReturn(parent, loan) then report('return', 'loan-unavailable'); return end
    if not episode.source() or not episode.hand or not settlement.earned(episode.equipHandle) then
        report('return', 'preparation-unconfirmed')
        return
    end
    local function hands(_, incoming, bothHands) return episodeHands(episode, incoming, bothHands) end
    local revision = Toolkit.ActionQueueTidyIntent.handRequestRevision
    local function eligible()
        return episode.source() and revision(actor, episode.bothHands) == episode.revision
    end
    if not eligible() then Generator.cancel(episode.generator); return end
    local proposal, plan = Hand.propose(episode.hand, hands(actor))
    if not proposal then report('proposal', plan); return end
    local borrowed = currentTool(episode)
    if not borrowed then return end
    local previous = plan.incoming and plan.incoming.item
    local bothHands = plan.mode == 'both'
    local token = parent.toolkitQueueOperation
    local drop = episode.drop
    local action, pickup, pickupHandle, unequipBelt
    local generator = episode.generator
    if generator then
        if not bothHands or previous ~= generator.item then return end
        action = Generator.pickup(generator)
        report('return', action and 'constructed' or 'revoked')
        if not action then return end
    elseif drop then
        if not bothHands or previous ~= drop.item then return end
        Toolkit.FitnessEquipment.refreshFloor(actor)
        local floorItem, floor = Heavy.resolveFloor(drop)
        if not floorItem or not eligible() then return end
        pickup = ISInventoryTransferUtil.newInventoryTransferAction(actor, floorItem, floor, actor:getInventory())
        pickup:setAllowMissingItems(true)
        ops.adopt(pickup, token)
        local enrolled
        enrolled, pickupHandle = settlement.observeCleanupTransfer(pickup, parent, episode.equipHandle)
        if not enrolled then return end
        action = ISEquipWeaponAction:new(actor, floorItem, 50, true, true)
    elseif plan.mode == 'unequip' then
        unequipBelt = episode.belt and Belt.current(actor, borrowed)
        if episode.belt and not unequipBelt then return end
        action = ISUnequipAction:new(actor, borrowed, 50)
    else
        if not previous or not hands(actor, previous, bothHands) then return end
        action = ISEquipWeaponAction:new(actor, previous, 50, true, bothHands)
    end
    ops.adopt(action, token)
    if not settlement.inheritCleanup(action, parent) then report('return', 'unowned-cleanup'); return end
    local function bound(value)
        if value ~= action then return false end
        if generator then return Generator.bound(generator, value) end
        if drop then
            return (value.item == pickup.item or value.item == Heavy.restoredRoot(drop))
                and isPrimaryEquip(value, actor, value.item, true)
        end
        if previous then return isPrimaryEquip(value, actor, previous, bothHands) end
        local current = episode.belt and Belt.current(actor, borrowed)
        local attachmentSafe = not episode.belt and not value.fromHotbar
            or current and unequipBelt and current.hotbar == unequipBelt.hotbar
                and current.index == unequipBelt.index and current.kind == unequipBelt.kind
                and current.model == unequipBelt.model and current.definition == unequipBelt.definition
                and (current.detached == true) == (unequipBelt.detached == true)
                and (value.fromHotbar == true) == (not current.detached)
        return getmetatable(value) == ISUnequipAction and value.character == actor and value.item == borrowed
            and attachmentSafe and value.reason == nil and Toolkit.ActionQueuePolicy.matchesNative(value)
    end
    local effect = settlement.observeCleanupEffect(action, {
        guard = function(value)
            local receipt = generator and generator.receipt
            return bound(value) and not (receipt and (receipt.skipped or receipt.unknown))
        end, sourceGuard = bound,
        admit = function(value)
            if not bound(value) or not eligible() then Generator.cancel(generator); return false end
            local current
            if generator then
                current = hands(actor)
            elseif drop then
                if not settlement.earned(pickupHandle) or not Heavy.restoredRoot(drop) then return false end
                current = hands(actor)
            else
                current = hands(actor, previous, bothHands)
            end
            return Hand.consume(episode.hand, proposal, current) ~= nil
        end,
        capture = function() return hands(actor) end,
        observed = function(_, before)
            if generator then return Generator.observed(generator) end
            if drop then
                local item = Heavy.restoredRoot(drop)
                return item ~= nil and actor:getPrimaryHandItem() == item and actor:getSecondaryHandItem() == item
                    and before.primary and before.primary.item == currentTool(episode)
            end
            local after = hands(actor)
            return after and (after.primary and after.primary.item) == previous and before.primary
                and before.primary.item == currentTool(episode)
                and (after.secondary and after.secondary.item) == (plan.expected.secondary and plan.expected.secondary.item)
        end,
    })
    if not effect then report('return', 'effect-unobserved'); return end
    if not loan then ISTimedActionQueue.add(action); return end
    local continuation = command(actor, function()
        if settlement.earned(effect) then settlement.enqueueBorrowedReturn(loan) end
    end)
    ops.adopt(continuation, token)
    if settlement.inheritCleanup(continuation, parent)
        and settlement.requireBorrowedReturnSuccess(loan, {effect}, continuation) then
        report('return', 'enrolled')
        if pickup then ISTimedActionQueue.add(pickup) end
        ISTimedActionQueue.add(action)
        ISTimedActionQueue.add(continuation)
    else
        report('return', 'continuation-unavailable')
    end
end

function Razor.finish(episode)
    if not Toolkit.ActionQueueRazorProducer.owns(episode) or not (episode.loan or episode.belt) or not episode.equipHandle then return end
    local body, actor = episode.body, episode.actor
    local token = body.toolkitQueueOperation
    local queue = ISTimedActionQueue.queues[actor]
    if not token or episode.pickup and episode.pickup.toolkitQueueOperation ~= token or episode.equip.toolkitQueueOperation ~= token
        or not queue or queue.queue[#queue.queue] ~= body or queue.queue[#queue.queue - 1] ~= episode.equip
        or not Toolkit.ActionQueueDefinitions.inspect(body) or not episode.source() then return end
    local parent
    parent = command(actor, function() restore(episode, parent) end)
    local ops, settlement = Toolkit.ActionQueueOperations, Toolkit.ActionQueueSettlement
    ops.adopt(parent, token)
    if episode.belt then episode.cleanup = parent end
    if settlement.cleanup(parent, episode.loan or episode.equipHandle)
        and (not episode.loan or settlement.claimBorrowedReturn(parent, episode.loan)) then
        ops.runWith(token, ISTimedActionQueue.add, parent)
    end
end

if Events and Events.OnGameStart then Events.OnGameStart.Add(function()
    if P4TidyUpMeister == nil and not getActivatedMods():contains('P4TidyUpMeister') then Razor.install() end
end) end

return Razor
